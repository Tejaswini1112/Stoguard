const AUTO_INTERVAL_MS = 30 * 60 * 1000; // 30 minutes
const AUTO_KEY = "stoguard.scanAutomation";

const state = {
  status: null,
  tier: null,
  scan: null,
  doctor: null,
  duplicates: [],
  models: [],
  packages: [],
  packagesLoading: false,
  packagesError: null,
  packagesLoaded: false,
  agentTools: [],
  history: [],
  fleet: [],
  intelligence: null,
  media: [],
  mediaNote: "",
  view: "overview",
  scanning: false,
  scanAutomation: localStorage.getItem(AUTO_KEY) === "1",
  autoTimer: null,
  findingsFilter: "all", // all | safe | check | command
};

const titles = {
  overview: ["Overview", "Find AI models, packages, and caches — with definitions and safe cleanup"],
  health: ["Health", "Score, predictions, and proactive alerts"],
  doctor: ["Workstation Doctor", "Prioritized cleanup recommendations"],
  ask: ["Ask Stoguard", "Answers grounded in your last scan"],
  learning: ["Learning Center", "What terms mean, when to delete, what happens after"],
  automation: ["Automation", "Scheduled scans, tidy rules, opt-in cohort benchmarks"],
  duplicates: ["Duplicates", "Overlapping caches and installs"],
  aicleanup: ["AI Cleanup", "Models, skills, MCP, and AI caches — clean safe items immediately"],
  packages: ["Package Finder", "Each install with a definition and how much disk it uses"],
  media: ["Media Optimizer", "Large images, videos, documents — detect here; full optimize in the macOS app"],
  history: ["Storage Timeline", "Reclaimable safe space over time"],
  items: ["All Findings", "Everything the scanner measured"],
  fleet: ["Fleet", "Team machine rollup"],
  account: ["Pricing / Account", "Free, Pro, and Team features"],
};

const $ = (sel) => document.querySelector(sel);

function currentOS() {
  return (state.status && (state.status.platform || state.status.os)) || "";
}

function isWindows() {
  const o = String(currentOS()).toLowerCase();
  return o === "windows" || o === "win32";
}

function trashVerb() {
  return isWindows() ? "Recycle Bin" : "Trash";
}

function trashButtonLabel() {
  return isWindows() ? "Recycle" : "Trash";
}

function packageFinderHint() {
  if (isWindows()) {
    return "Looks for npm globals, Scoop, winget packages, pipx, Cargo bins, and Local\\Programs.";
  }
  return "Looks for Homebrew Cellar, npm globals, pipx, Cargo bins, and ~/.local/bin.";
}

function packageFinderLoadingCopy() {
  if (isWindows()) {
    return "Scanning npm, Scoop, winget, pipx, and CLI installs…";
  }
  return "Scanning Homebrew, npm, pipx, and CLI installs…";
}

function fmtBytes(n) {
  if (n == null || Number.isNaN(n)) return "—";
  const u = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  let v = Math.abs(n);
  while (v >= 1000 && i < u.length - 1) {
    v /= 1000;
    i++;
  }
  return `${(n < 0 ? "-" : "")}${v.toFixed(v >= 10 || i === 0 ? 0 : 1)} ${u[i]}`;
}

function toast(msg) {
  const el = $("#toast");
  el.textContent = msg;
  el.classList.remove("hidden");
  clearTimeout(toast._t);
  toast._t = setTimeout(() => el.classList.add("hidden"), 3200);
}

function notifyOS(title, body) {
  try {
    if (!("Notification" in window)) return;
    if (Notification.permission === "granted") {
      new Notification(title, { body, silent: false });
    }
  } catch (_) {}
}

function showNotify({ title, body, actions }) {
  const root = $("#notify");
  $("#notify-title").textContent = title || "Stoguard";
  $("#notify-body").textContent = body || "";
  const box = $("#notify-actions");
  box.innerHTML = "";
  (actions || [{ label: "OK", primary: true }]).forEach((a) => {
    const btn = document.createElement("button");
    btn.className = `btn ${a.primary ? "primary" : a.danger ? "danger" : ""}`;
    btn.textContent = a.label;
    btn.onclick = async () => {
      root.classList.add("hidden");
      if (a.onClick) await a.onClick();
    };
    box.appendChild(btn);
  });
  root.classList.remove("hidden");
}

function hideNotify() {
  $("#notify")?.classList.add("hidden");
}

function clearScanResults() {
  state.scan = null;
  state.doctor = null;
  state.duplicates = [];
  state.models = [];
  // Keep Package Finder installs — those are independent of workstation scan.
  state.agentTools = [];
  toast("Scan results cleared — run Scan again when ready");
  setView("overview");
  render();
}

function setScanAutomation(on) {
  state.scanAutomation = !!on;
  localStorage.setItem(AUTO_KEY, on ? "1" : "0");
  if (state.autoTimer) {
    clearInterval(state.autoTimer);
    state.autoTimer = null;
  }
  if (on) {
    state.autoTimer = setInterval(() => {
      if (!state.scanning) runScan({ source: "automation" });
    }, AUTO_INTERVAL_MS);
  }
  renderHero();
}

async function api(path, opts = {}) {
  let res;
  try {
    res = await fetch(path, {
      headers: { "Content-Type": "application/json", ...(opts.headers || {}) },
      ...opts,
    });
  } catch (e) {
    throw new Error(
      "Stoguard server is offline (127.0.0.1:8787). In Terminal run:\ncd stoguard && ./dist/stoguard -port 8787"
    );
  }
  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || res.statusText);
  }
  const ct = res.headers.get("content-type") || "";
  if (ct.includes("application/json")) return res.json();
  return res.text();
}

function allows(feature) {
  return !!(state.tier?.features?.[feature] ?? state.status?.features?.[feature]);
}

function renderSystemDetails(scan) {
  const sys = state.status?.system || {};
  const lines = [
    ["Hostname", sys.hostname || "—"],
    ["User", sys.username || "—"],
    ["Platform", `${sys.platform || scan?.platform || "—"} (${sys.os || "—"} / ${sys.arch || "—"})`],
    ["CPUs", sys.numCPU != null ? String(sys.numCPU) : "—"],
    ["Disk free", `${fmtBytes(sys.diskFreeBytes ?? scan?.freeBytes)} / ${fmtBytes(sys.diskTotalBytes ?? scan?.diskTotalBytes)} (${(sys.diskUsedPercent ?? 0).toFixed?.(1) || "—"}% used)`],
    ["App memory", `${fmtBytes(sys.memAllocBytes)} alloc · ${fmtBytes(sys.memSysBytes)} sys`],
    ["Home", sys.home || state.status?.home || "—"],
    ["Data dir", sys.dataDir || state.status?.dataDir || "—"],
    ["Tier", state.tier?.displayName || state.status?.tierName || "Team"],
    ["Go runtime", sys.goVersion || "—"],
    ["Process uptime", sys.uptimeSeconds != null ? `${sys.uptimeSeconds}s` : "—"],
    ["Scan findings", scan ? String(scan.items?.length ?? 0) : "—"],
    ["Adaptive skips", scan ? String(scan.skippedRules ?? 0) : "—"],
    ["Cache hits", scan ? String(scan.cachedHits ?? 0) : "—"],
    ["Collected", sys.collectedAt ? new Date(sys.collectedAt).toLocaleString() : "—"],
  ];
  return `<div class="list" style="margin-top:10px">${lines
    .map(
      ([k, v]) => `<div class="row" style="grid-template-columns:120px 1fr;gap:8px;padding:6px 0;background:transparent;border:0">
      <div class="meta" style="margin:0">${escapeHtml(k)}</div>
      <div class="name" style="font-weight:500;word-break:break-all">${escapeHtml(v)}</div>
    </div>`
    )
    .join("")}</div>`;
}

function escapeHtml(s) {
  return String(s ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
function escapeAttr(s) {
  return escapeHtml(s).replaceAll("'", "&#39;");
}

function setView(name) {
  state.view = name;
  document.querySelectorAll(".nav").forEach((b) => {
    b.classList.toggle("active", b.dataset.view === name);
  });
  document.querySelectorAll(".view").forEach((v) => {
    v.classList.toggle("active", v.id === `view-${name}`);
  });
  const [t, s] = titles[name] || [name, ""];
  $("#view-title").textContent = t;
  $("#view-sub").textContent = s;
  if (name === "fleet") loadFleet();
  if (name === "aicleanup") loadAICleanup();
  if (name === "packages") loadPackages();
  if (name === "account") renderAccount();
  render();
}

function updateTierUI() {
  const info = state.tier || {};
  const name = info.displayName || state.status?.tierName || "Team";
  const tier = (info.tier || state.status?.tier || "team").toLowerCase();
  const pill = $("#tier-pill");
  pill.textContent = name;
  pill.className = "tier-pill " + tier;
  document.querySelectorAll(".nav[data-feature]").forEach((btn) => {
    const ok = allows(btn.dataset.feature);
    const badge = btn.querySelector(".tier-badge");
    if (badge) badge.classList.toggle("locked", !ok);
    btn.title = ok ? "" : `Requires ${badge?.textContent || "upgrade"}`;
  });
}

function itemRow(it, { showChildren = true, selectable = false } = {}) {
  const kids =
    showChildren && it.children?.length
      ? `<div class="meta">Top: ${it.children
          .slice(0, 3)
          .map((c) => escapeHtml(c.name))
          .join(", ")}</div>`
      : "";
  const canTrash = it.safety === "safe" || it.safety === "check";
  const check =
    selectable && canTrash
      ? `<input type="checkbox" class="clean-check" data-path="${escapeAttr(it.path)}" data-name="${escapeAttr(it.name)}" data-safety="${escapeAttr(it.safety)}" ${it.safety === "safe" ? "checked" : ""} />`
      : selectable
        ? `<span class="meta" title="Use the CLI command — not direct delete">—</span>`
        : "";
  let actionBtn = "";
  if (canTrash) {
    actionBtn = `<button class="btn small primary" data-trash="${escapeAttr(it.path)}" data-name="${escapeAttr(it.name)}">${trashButtonLabel()}</button>`;
  } else if (it.safety === "command" && it.command) {
    actionBtn = `<button class="btn small" data-copy-cmd="${escapeAttr(it.command)}">Copy command</button>`;
  }
  return `<div class="row ${selectable ? "row-select" : ""}">
    ${selectable ? `<div class="check-cell">${check}</div>` : ""}
    <div>
      <div class="name">${escapeHtml(it.name)} <span class="badge ${escapeAttr(it.safety)}">${escapeHtml(it.safety)}</span></div>
      <div class="meta">${escapeHtml(it.path)}</div>
      ${it.safety === "command" && it.command ? `<div class="meta">CLI: <code>${escapeHtml(it.command)}</code></div>` : ""}
      ${kids}
    </div>
    <div class="size">${fmtBytes(it.sizeBytes)}</div>
    <div class="actions">
      <button class="btn small" data-reveal="${escapeAttr(it.path)}">Reveal</button>
      ${actionBtn}
    </div>
  </div>`;
}

function renderHero() {
  const s = state.scan;
  const box = $("#hero-stats");
  const autoOn = state.scanAutomation;
  const scanning = state.scanning;
  const primaryLabel = scanning ? "Scanning…" : s ? "Scan again" : "Scan now";
  const autoLabel = autoOn ? "Automation on" : "Scan automation";
  const statusText = scanning
    ? "Scan in progress…"
    : autoOn
      ? "Automation on · re-scans every 30 min"
      : s
        ? "Ready · scan again anytime"
        : "No scan yet — start here";

  const stats = s
    ? `
    <div class="stat"><b>${fmtBytes(s.safeBytes)}</b><span>Safe</span></div>
    <div class="stat"><b>${fmtBytes(s.checkBytes)}</b><span>Review</span></div>
    <div class="stat"><b>${fmtBytes(s.freeBytes)}</b><span>Free disk</span></div>
    <div class="stat"><b>${s.items.length}</b><span>Findings</span></div>`
    : `<div class="stat"><b>—</b><span>No results yet</span></div>`;

  box.innerHTML = `
    ${stats}
    <div class="scan-controls">
      <div class="scan-row">
        <button class="btn primary" id="btn-scan-top" ${scanning ? "disabled" : ""}>${primaryLabel}</button>
        <button class="btn ${autoOn ? "active-auto" : "ghost"}" id="btn-scan-auto" ${scanning ? "disabled" : ""}>${autoLabel}</button>
      </div>
      <div class="scan-status ${autoOn ? "on" : ""}" id="scan-status">${statusText}</div>
    </div>`;

  const top = $("#btn-scan-top");
  if (top) top.onclick = () => runScan({ source: "manual" });
  const autoBtn = $("#btn-scan-auto");
  if (autoBtn) autoBtn.onclick = () => toggleScanAutomation();
}

async function loadIntelligence() {
  try {
    state.intelligence = await api("/api/intelligence");
  } catch (_) {
    /* optional until first scan */
  }
}

function renderHealth() {
  const el = $("#view-health");
  if (!el) return;
  const intel = state.intelligence;
  if (!intel?.health) {
    el.innerHTML = `<div class="empty">Run a scan, then open Health for your score and forecasts.</div>`;
    return;
  }
  const h = intel.health;
  const dims = (h.dimensions || [])
    .map(
      (d) => `<div class="card"><h3>${escapeHtml(d.name)} · ${d.score}</h3><p>${escapeHtml(d.detail || "")}</p>
      <div class="bar"><i style="width:${d.score}%"></i></div></div>`
    )
    .join("");
  const preds = (intel.predictive || [])
    .map((p) => `<div class="card"><h3>${escapeHtml(p.title)}</h3><p>${escapeHtml(p.body)}</p><span class="hint">${escapeHtml(p.severity)}</span></div>`)
    .join("");
  const alerts = (intel.proactive || [])
    .map(
      (a) => `<div class="card"><h3>${escapeHtml(a.title)}</h3><p>${escapeHtml(a.explanation)}</p>
      <p><strong>${escapeHtml(a.recommendation)}</strong></p></div>`
    )
    .join("");
  const benches = (intel.benchmarks || [])
    .map(
      (b) => `<div class="card"><h3>${escapeHtml(b.cohort)}</h3>
      <p>You ${fmtBytes(b.yourBytes)} · cohort avg ${fmtBytes(b.averageBytes)}</p>
      <p>${escapeHtml(b.recommendation)}</p></div>`
    )
    .join("");
  el.innerHTML = `
    <div class="grid">
      <div class="card wide">
        <h3>Score ${h.overall} / 100</h3>
        <p>${escapeHtml(h.headline)}</p>
      </div>
      ${dims}
      <div class="card wide"><h3>Predictive insights</h3></div>
      ${preds || `<div class="empty">Need more scan history for forecasts.</div>`}
      <div class="card wide"><h3>Proactive alerts</h3></div>
      ${alerts || `<div class="empty">No proactive alerts right now.</div>`}
      ${benches ? `<div class="card wide"><h3>Cohort benchmarks</h3></div>${benches}` : ""}
    </div>`;
}

function renderLearning() {
  const el = $("#view-learning");
  if (!el) return;
  const articles = state.intelligence?.learning || [];
  if (!articles.length) {
    el.innerHTML = `<div class="empty">Loading learning articles…</div>`;
    loadIntelligence().then(() => renderLearning());
    return;
  }
  el.innerHTML = `<div class="grid">${articles
    .map(
      (a) => `<div class="card wide">
      <h3>${escapeHtml(a.title)} <span class="hint">${escapeHtml(a.category)}</span></h3>
      <p><strong>What:</strong> ${escapeHtml(a.what)}</p>
      <p><strong>Why created:</strong> ${escapeHtml(a.whyCreated)}</p>
      <p><strong>Why safe:</strong> ${escapeHtml(a.whySafe)}</p>
      <p><strong>When to delete:</strong> ${escapeHtml(a.whenDelete)}</p>
      <p><strong>After:</strong> ${escapeHtml(a.afterDelete)}</p>
      <button class="btn small" data-ask-learn="${escapeHtml(a.title)}">Ask Stoguard about this</button>
    </div>`
    )
    .join("")}</div>`;
  el.querySelectorAll("[data-ask-learn]").forEach((btn) => {
    btn.onclick = () => {
      setView("ask");
      const input = $("#chat-input");
      if (input) {
        input.value = `Explain ${btn.dataset.askLearn} like a teacher — what it is, when to delete, what happens after.`;
        input.focus();
      }
    };
  });
}

function renderAutomation() {
  const el = $("#view-automation");
  if (!el) return;
  if (!allows("automation") && state.tier) {
    el.innerHTML = `<div class="empty">Automation schedules are a Pro feature. Health score still works on Free.</div>`;
  }
  const auto = state.intelligence?.automation || { rules: [], cloudOptIn: false };
  const rules = (auto.rules || [])
    .map(
      (r) => `<div class="card" style="display:flex;justify-content:space-between;align-items:center;gap:12px">
      <div>
        <h3>${escapeHtml(r.name)}</h3>
        <p class="hint">${escapeHtml(r.schedule)} · ${escapeHtml(r.action)} · min ${fmtBytes(r.minBytes)}</p>
      </div>
      <label><input type="checkbox" data-rule="${escapeHtml(r.id)}" ${r.enabled ? "checked" : ""}/> On</label>
    </div>`
    )
    .join("");
  el.innerHTML = `
    <div class="grid">
      <div class="card wide">
        <h3>Automation</h3>
        <p>Scheduled maintenance hints. Destructive cleans never run without your review in the findings list.</p>
        <label style="display:flex;gap:8px;align-items:center;margin-top:12px">
          <input type="checkbox" id="cloud-optin" ${auto.cloudOptIn ? "checked" : ""}/>
          Opt in to anonymous cohort benchmarks (compared on-device for now)
        </label>
      </div>
      ${rules || `<div class="empty">No rules loaded.</div>`}
      <div class="card wide">
        <button class="btn primary" id="save-automation">Save automation</button>
      </div>
    </div>`;
  const save = $("#save-automation");
  if (save) {
    save.onclick = async () => {
      const next = {
        cloudOptIn: !!$("#cloud-optin")?.checked,
        rules: (auto.rules || []).map((r) => ({
          ...r,
          enabled: !!el.querySelector(`[data-rule="${r.id}"]`)?.checked,
        })),
      };
      try {
        state.intelligence = state.intelligence || {};
        state.intelligence.automation = await api("/api/automation", {
          method: "POST",
          body: JSON.stringify(next),
        });
        await loadIntelligence();
        toast("Automation saved");
        renderAutomation();
        renderHealth();
      } catch (e) {
        toast(e.message);
      }
    };
  }
}

function renderOverview() {
  const el = $("#view-overview");
  if (!state.scan) {
    el.innerHTML = `<div class="empty">
      Use <strong>Scan now</strong> at the top (or <strong>Scan workstation</strong> in the sidebar) to analyze developer caches on this machine.<br/><br/>
      After a scan, select <strong>safe</strong> items and click <strong>Clean Selected</strong> — items go to ${trashVerb()} (never silent delete).
    </div>`;
    return;
  }
  const s = state.scan;
  const d = state.doctor;
  const h = state.intelligence?.health;
  const filter = state.findingsFilter || "all";
  let list = s.items || [];
  if (filter === "safe") list = list.filter((it) => it.safety === "safe");
  else if (filter === "check") list = list.filter((it) => it.safety === "check");
  else if (filter === "command") list = list.filter((it) => it.safety === "command");
  const safeCount = (s.items || []).filter((it) => it.safety === "safe").length;
  const cats = Object.entries(s.categoryTotals || {})
    .sort((a, b) => b[1] - a[1])
    .slice(0, 6);
  const pill = (id, label) =>
    `<button type="button" class="btn small filter-pill ${filter === id ? "primary" : "ghost"}" data-filter="${id}">${label}</button>`;

  el.innerHTML = `
    <div class="grid">
      ${
        h
          ? `<div class="card">
        <h3>Health ${h.overall}/100</h3>
        <p>${escapeHtml(h.headline)}</p>
        <button class="btn small" id="goto-health">Open Health</button>
      </div>`
          : ""
      }
      <div class="card wide">
        <h3>${escapeHtml(d?.headline || "Scan complete")}</h3>
        <p>${(d?.summaryLines || []).map(escapeHtml).join(" · ")}</p>
        <p class="hint" style="margin-top:8px">
          Like VACS: review findings → check safe items → <strong>Clean Selected</strong> → ${trashVerb()}.
          Docker / WSL stay <span class="badge command">command</span> (copy CLI — no direct delete).
        </p>
      </div>
      <div class="card">
        <h3>Categories</h3>
        <div class="list" style="margin-top:12px">
          ${cats
            .map(
              ([c, b]) => `<div class="row" style="grid-template-columns:1fr auto">
              <div class="name">${escapeHtml(c)}</div><div class="size">${fmtBytes(b)}</div></div>`
            )
            .join("")}
        </div>
      </div>
      <div class="card">
        <h3>Engine · system</h3>
        ${renderSystemDetails(s)}
        <button class="btn small" id="reset-adaptive" style="margin-top:12px">Reset adaptive skips</button>
        ${
          allows("fleet_export")
            ? `<button class="btn small" id="export-fleet" style="margin-top:8px">Export fleet JSON</button>`
            : ""
        }
        ${
          allows("fleet_admin")
            ? `<button class="btn small" id="ingest-self" style="margin-top:8px">Add this machine to Fleet</button>`
            : ""
        }
      </div>
      <div class="card wide">
        <div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center;justify-content:space-between">
          <h3 style="margin:0">Findings · Clean</h3>
          <div style="display:flex;flex-wrap:wrap;gap:6px">
            ${pill("all", "All")}
            ${pill("safe", `Safe (${safeCount})`)}
            ${pill("check", "Check first")}
            ${pill("command", "Commands")}
          </div>
        </div>
        <div class="clean-bar" style="display:flex;flex-wrap:wrap;gap:8px;margin:12px 0;align-items:center">
          <button class="btn primary" id="btn-clean-selected">Clean Selected → ${trashVerb()}</button>
          <button class="btn small" id="btn-select-safe">Select all safe</button>
          <button class="btn small ghost" id="btn-clear-sel">Clear selection</button>
          <span class="hint">${fmtBytes(s.safeBytes)} marked safe · recoverable until you empty ${trashVerb()}</span>
        </div>
        <div class="list list-select" style="margin-top:8px">${
          list.length
            ? list.map((it) => itemRow(it, { selectable: true })).join("")
            : `<div class="empty">No findings in this filter.</div>`
        }</div>
      </div>
    </div>`;

  el.querySelectorAll("[data-filter]").forEach((btn) => {
    btn.onclick = () => {
      state.findingsFilter = btn.dataset.filter;
      renderOverview();
      bindActions();
    };
  });
  const selSafe = $("#btn-select-safe");
  if (selSafe) {
    selSafe.onclick = () => {
      el.querySelectorAll(".clean-check").forEach((c) => {
        c.checked = c.dataset.safety === "safe";
      });
    };
  }
  const clearSel = $("#btn-clear-sel");
  if (clearSel) {
    clearSel.onclick = () => {
      el.querySelectorAll(".clean-check").forEach((c) => {
        c.checked = false;
      });
    };
  }
  const cleanBtn = $("#btn-clean-selected");
  if (cleanBtn) cleanBtn.onclick = () => cleanSelected();
}


function packageCachesFromScan() {
  const items = state.scan?.items || [];
  return items.filter((it) => (it.category || "") === "Package Managers");
}

async function loadMedia() {
  try {
    const data = await api("/api/media");
    state.media = data.assets || [];
    state.mediaNote = data.note || "";
  } catch (e) {
    state.media = [];
    state.mediaNote = e.message;
  }
}

function renderMedia() {
  const el = $("#view-media");
  if (!el) return;
  const rows = (state.media || [])
    .map(
      (a) => `<div class="row" style="grid-template-columns:1fr auto auto;gap:10px">
      <div><div class="name">${escapeHtml(a.name)}</div>
      <div class="hint">${escapeHtml(a.kind)} · ${escapeHtml(a.path)}</div></div>
      <div class="size">${fmtBytes(a.sizeBytes)}</div>
      <button class="btn small" data-reveal="${escapeHtml(a.path)}">Reveal</button>
    </div>`
    )
    .join("");
  el.innerHTML = `
    <div class="card wide">
      <h3>Large media detected</h3>
      <p>${escapeHtml(state.mediaNote || "Scan Downloads, Documents, Desktop, Pictures, Movies for oversized files.")}</p>
      <p class="hint">Optimize with approval (keep resolution, or target KB/MB/GB/TB) in the native macOS <strong>Media Optimizer</strong>.</p>
      <button class="btn primary" id="scan-media" style="margin-top:12px">Scan large media</button>
    </div>
    <div class="list" style="margin-top:14px">${rows || `<div class="empty">No oversized media found yet — click Scan.</div>`}</div>`;
  const btn = $("#scan-media");
  if (btn) {
    btn.onclick = async () => {
      btn.disabled = true;
      btn.textContent = "Scanning…";
      await loadMedia();
      renderMedia();
      bindActions();
    };
  }
}

function renderPackages() {
  const el = $("#view-packages");
  if (!el) return;
  if (!allows("packages")) {
    el.innerHTML = `<div class="empty">Package Finder is a Pro feature.</div>`;
    return;
  }
  if (state.packagesLoading && !(state.packages || []).length) {
    el.innerHTML = `<div class="empty">${packageFinderLoadingCopy()}<br/><span class="hint">This lists what you installed — not just caches.</span></div>`;
    return;
  }
  if (state.packagesError && !(state.packages || []).length) {
    el.innerHTML = `<div class="empty">Couldn’t load installed packages.<br/><strong>${escapeHtml(state.packagesError)}</strong><br/><br/>
      <button class="btn primary" id="btn-reload-packages">Try again</button></div>`;
    const btn = $("#btn-reload-packages");
    if (btn) btn.onclick = () => loadPackages({ force: true });
    return;
  }
  const list = state.packages || [];
  const caches = packageCachesFromScan();
  if (!list.length && !caches.length) {
    el.innerHTML = `<div class="empty">
      No installed packages measured yet.<br/><br/>
      <button class="btn primary" id="btn-reload-packages">Scan installs now</button>
      <p class="hint" style="margin-top:12px">${packageFinderHint()}</p>
    </div>`;
    const btn = $("#btn-reload-packages");
    if (btn) btn.onclick = () => loadPackages({ force: true });
    return;
  }
  const total = list.reduce((a, p) => a + (p.sizeBytes || 0), 0);
  const cacheTotal = caches.reduce((a, it) => a + (it.sizeBytes || 0), 0);
  const installRows = list.length
    ? list.map((p, idx) => {
        const def = p.definition || "Installed developer package.";
        return `
    <div class="row">
      <div>
        <div class="name">
          ${escapeHtml(p.name)}
          <button class="info-btn" type="button" title="What is this package?"
            data-pkg-info="${idx}" aria-label="Why is ${escapeAttr(p.name)} installed?">i</button>
          <span class="badge check">${escapeHtml(p.source)}</span>
        </div>
        <div class="pkg-def">${escapeHtml(def)}</div>
        <div class="meta">${escapeHtml(p.path)}</div>
        <div class="meta">${escapeHtml(p.detail || "")}${p.daysIdle != null && p.daysIdle >= 45 ? ` · idle ${p.daysIdle}d` : ""}</div>
      </div>
      <div class="size">${fmtBytes(p.sizeBytes)}</div>
      <button class="btn small" data-reveal="${escapeAttr(p.path)}">Reveal</button>
    </div>`;
      }).join("")
    : `<div class="empty">No Cellar / global installs matched yet — try Scan installs again.</div>`;

  const cacheRows = caches.length
    ? `<div class="card wide" style="margin-top:16px">
        <h3>Package caches (from workstation scan)</h3>
        <p class="hint">${caches.length} items · ${fmtBytes(cacheTotal)} — rebuildable caches, separate from installed formulae.</p>
        <div class="list" style="margin-top:12px">${caches.map((it) => itemRow(it)).join("")}</div>
      </div>`
    : "";

  el.innerHTML = `
    <div class="card wide">
      <h3>Installed packages</h3>
      <p class="hint" style="margin-bottom:12px">${list.length} packages · ${fmtBytes(total)} — tap the <strong>i</strong> for why each one is installed.
        ${state.packagesLoading ? " · refreshing…" : ""}
        <button class="btn small" id="btn-reload-packages" style="margin-left:8px">Refresh</button>
      </p>
      <div class="list">${installRows}</div>
    </div>
    ${cacheRows}`;
  const reload = $("#btn-reload-packages");
  if (reload) reload.onclick = () => loadPackages({ force: true });
  el.querySelectorAll("[data-pkg-info]").forEach((btn) => {
    btn.onclick = (e) => {
      e.stopPropagation();
      const p = list[Number(btn.dataset.pkgInfo)];
      if (!p) return;
      showNotify({
        title: `${p.name} — why is this installed?`,
        body: packageWhy(p),
        actions: [
          { label: "OK", primary: true },
          p.path
            ? {
                label: "Reveal on disk",
                onClick: async () => {
                  try {
                    await api(`/api/reveal?path=${encodeURIComponent(p.path)}`);
                  } catch (err) {
                    toast(err.message);
                  }
                },
              }
            : null,
        ].filter(Boolean),
      });
    };
  });
}

/** Plain-English explanation: what it is, why you might have it, how to remove. */
function packageWhy(p) {
  const def = (p.definition || "Installed developer package.").trim();
  const src = (p.source || "install").toLowerCase();
  let why = "You (or a setup script) installed this as a developer tool.";
  if (src.includes("homebrew")) {
    why = "Installed with Homebrew — usually for a CLI, language runtime, or library you needed for a project.";
  } else if (src.includes("npm")) {
    why = "Installed globally with npm so the CLI is available in every project terminal.";
  } else if (src.includes("pipx")) {
    why = "Installed with pipx as an isolated Python CLI app (its own virtualenv).";
  } else if (src.includes("cargo")) {
    why = "Installed with Cargo as a Rust binary on your PATH.";
  } else if (src.includes("user bin")) {
    why = "Dropped into ~/.local/bin — a tool you installed manually for shell use.";
  }
  const remove =
    p.detail ||
    (src.includes("homebrew")
      ? `Uninstall: brew uninstall ${p.name}`
      : src.includes("npm")
        ? `Uninstall: npm uninstall -g ${p.name}`
        : src.includes("pipx")
          ? `Uninstall: pipx uninstall ${p.name}`
          : "Remove only if you are sure nothing depends on it.");
  const idle =
    p.daysIdle != null && p.daysIdle >= 45
      ? `\n\nIdle ~${p.daysIdle} days — may be unused.`
      : "";
  return `What it is:\n${def}\n\nWhy it’s here:\n${why}\n\nDisk: ${fmtBytes(p.sizeBytes)}\nPath: ${p.path || "—"}\n\n${remove}${idle}`;
}

function renderDoctor() {
  const el = $("#view-doctor");
  if (!allows("doctor")) {
    el.innerHTML = `<div class="empty">Workstation Doctor requires Pro+. Local builds default to Team — set <code>STOGUARD_TIER=free</code> to simulate Free.</div>`;
    return;
  }
  const d = state.doctor;
  if (!d) {
    el.innerHTML = `<div class="empty">Run a scan to generate the doctor report.</div>`;
    return;
  }
  el.innerHTML = `
    <div class="grid">
      <div class="card wide">
        <h3>${escapeHtml(d.headline)}</h3>
        <p>${d.summaryLines.map((l) => `• ${escapeHtml(l)}`).join("<br/>")}</p>
      </div>
      <div class="card wide">
        <h3>Recommendations</h3>
        <div class="list" style="margin-top:12px">
          ${(d.recommendations || [])
            .map(
              (r) => `<div class="row" style="grid-template-columns:1fr auto">
              <div>
                <div class="name">${escapeHtml(r.title)} <span class="badge ${r.action === "trashSafe" ? "safe" : "check"}">${escapeHtml(r.action)}</span></div>
                <div class="meta">${escapeHtml(r.advice)}</div>
                ${r.command ? `<div class="meta">$ ${escapeHtml(r.command)}</div>` : ""}
              </div>
              <div class="size">${fmtBytes(r.bytes)}</div>
            </div>`
            )
            .join("")}
        </div>
      </div>
    </div>`;
}

function renderDuplicates() {
  const el = $("#view-duplicates");
  if (!allows("duplicates")) {
    el.innerHTML = `<div class="empty">Duplicate grouping requires <strong>Pro</strong>.</div>`;
    return;
  }
  const groups = state.duplicates || [];
  if (!state.scan) {
    el.innerHTML = `<div class="empty">Scan first to detect duplicates.</div>`;
    return;
  }
  if (!groups.length) {
    el.innerHTML = `<div class="empty">No confirmed duplicates or related groups found.</div>`;
    return;
  }
  const confirmed = groups.filter((g) => g.verdict === "duplicate");
  const related = groups.filter((g) => g.verdict !== "duplicate");
  const card = (g) => {
    const badge =
      g.verdict === "duplicate"
        ? `<span class="badge check">DUPLICATE</span>`
        : `<span class="badge">NOT A DUPLICATE</span>`;
    const diffs = (g.differences || [])
      .map(
        (d) => `<div class="hint" style="margin:4px 0">✦ <strong>${escapeHtml(d.label)}</strong> — ${escapeHtml(d.detail)}</div>`
      )
      .join("");
    const waste =
      g.verdict === "duplicate" && g.wasteBytes
        ? ` · reclaimable ${fmtBytes(g.wasteBytes)}`
        : "";
    return `<div class="card wide" style="margin-bottom:12px">
      <h3>${escapeHtml(g.label)} ${badge}</h3>
      <p>${escapeHtml(g.advice)}${waste}</p>
      ${diffs ? `<div style="margin:10px 0;padding:8px;border-radius:8px;background:rgba(127,160,190,.12)">${diffs}</div>` : ""}
      <div class="list" style="margin-top:12px">${g.items.map((it) => itemRow(it, { showChildren: false })).join("")}</div>
    </div>`;
  };
  el.innerHTML = `
    ${confirmed.length ? `<h3 style="margin:8px 0">Confirmed duplicates</h3>${confirmed.map(card).join("")}` : ""}
    ${
      related.length
        ? `<h3 style="margin:16px 0 8px">Related — not duplicates</h3>
           <p class="hint">Compared thoroughly; differences are listed. These are not reclaimable duplicate waste.</p>
           ${related.map(card).join("")}`
        : ""
    }`;
}

function renderAICleanup() {
  const el = $("#view-aicleanup");
  if (!el) return;
  if (!allows("models") && !allows("agent_tools")) {
    el.innerHTML = `<div class="empty">AI Cleanup requires <strong>Pro</strong>.</div>`;
    return;
  }
  const models = state.models || [];
  const tools = state.agentTools || [];
  const aiItems = (state.scan?.items || []).filter(
    (it) => /ai|ollama|huggingface|llm|model|claude|chatgpt|cursor/i.test(`${it.category || ""} ${it.name || ""}`)
  );
  const safeAI = aiItems.filter((it) => it.safety === "safe");
  const safeBytes = safeAI.reduce((a, it) => a + (it.sizeBytes || 0), 0);

  const modelRows = models.length
    ? models.map((m) => `<div class="row">
        <div>
          <div class="name">${escapeHtml(m.name)} <span class="badge command">${escapeHtml(m.provider || "model")}</span></div>
          <div class="meta">${escapeHtml(m.path)}</div>
          <div class="meta">${escapeHtml(m.note || m.category || "Local model store")}</div>
        </div>
        <div class="size">${fmtBytes(m.sizeBytes)}</div>
        <div class="actions"><button class="btn small" data-reveal="${escapeAttr(m.path)}">Reveal</button></div>
      </div>`).join("")
    : `<div class="empty">No AI model stores found yet — run a scan.</div>`;

  const toolRows = tools.length
    ? tools.map((f) => `<div class="row">
        <div>
          <div class="name">${escapeHtml(f.name)} <span class="badge ${f.isStale ? "never" : "check"}">${escapeHtml(f.kind)}</span></div>
          <div class="meta">${escapeHtml(f.path)}</div>
          <div class="meta">${escapeHtml(f.detail || "")}</div>
        </div>
        <div class="size">${fmtBytes(f.sizeBytes)}</div>
        <button class="btn small" data-reveal="${escapeAttr(f.path)}">Reveal</button>
      </div>`).join("")
    : `<div class="empty">No MCP configs, skills, or large AI extensions found.</div>`;

  const cacheRows = aiItems.length
    ? aiItems.slice(0, 40).map((it) => itemRow(it, { showChildren: false })).join("")
    : `<div class="empty">No AI app caches in the last scan.</div>`;

  el.innerHTML = `
    <div class="grid">
      <div class="card wide">
        <h3>Immediate AI cleanup</h3>
        <p>Models, skills/MCP, and AI caches in one place. Safe AI caches: <strong>${fmtBytes(safeBytes)}</strong> (${safeAI.length} items).</p>
      </div>
      <div class="card wide"><h3>Local AI models</h3><div class="list" style="margin-top:12px">${modelRows}</div></div>
      <div class="card wide"><h3>Skills &amp; MCP</h3><div class="list" style="margin-top:12px">${toolRows}</div></div>
      <div class="card wide"><h3>AI app caches</h3><div class="list" style="margin-top:12px">${cacheRows}</div></div>
    </div>`;
}

function renderHistory() {
  const el = $("#view-history");
  const h = state.history || [];
  if (!h.length) {
    el.innerHTML = `<div class="empty">Timeline fills in after each scan.</div>`;
    return;
  }
  const max = Math.max(...h.map((e) => e.reclaimableSafe || 0), 1);
  el.innerHTML = `<div class="timeline">${h
    .slice()
    .reverse()
    .map((e) => {
      const pct = Math.round(((e.reclaimableSafe || 0) / max) * 100);
      const when = new Date(e.date).toLocaleString();
      return `<div class="t-row">
        <div>${escapeHtml(when)}</div>
        <div class="bar"><i style="width:${pct}%"></i></div>
        <div class="size">${fmtBytes(e.reclaimableSafe)}</div>
      </div>`;
    })
    .join("")}</div>`;
}

function renderItems() {
  const el = $("#view-items");
  if (!state.scan) {
    el.innerHTML = `<div class="empty">No findings yet.</div>`;
    return;
  }
  el.innerHTML = `<div class="list">${state.scan.items.map((it) => itemRow(it)).join("")}</div>`;
}

function renderFleet() {
  const el = $("#view-fleet");
  if (!allows("fleet_admin")) {
    el.innerHTML = `<div class="empty">
      <p>Team fleet console aggregates machines via <code>POST /api/fleet/ingest</code>.</p>
      <p>Local builds default to Team. To simulate a lower tier: <code>STOGUARD_TIER=pro</code>.</p>
      ${
        allows("fleet_export")
          ? `<p style="margin-top:12px"><button class="btn" id="export-fleet-2">Export this machine JSON</button></p>`
          : ""
      }
    </div>`;
    return;
  }
  const machines = state.fleet || [];
  el.innerHTML = `
    <div class="grid">
      <div class="card wide">
        <h3>Fleet machines (${machines.length})</h3>
        <p>Ingest reports with <code>POST /api/fleet/ingest</code>. Stored under dataDir/fleet/.</p>
        <div style="display:flex;gap:8px;margin-top:12px;flex-wrap:wrap">
          <button class="btn primary" id="ingest-self">Ingest this machine</button>
          <button class="btn" id="refresh-fleet">Refresh</button>
          <button class="btn" id="export-fleet-2">Export JSON</button>
        </div>
      </div>
      <div class="card wide">
        <div class="list">
          ${
            machines.length
              ? machines
                  .map((m) => {
                    const tops = (m.topCategories || [])
                      .map((c) => `${escapeHtml(c.category)} ${fmtBytes(c.bytes)}`)
                      .join(" · ");
                    return `<div class="row" style="grid-template-columns:1fr auto">
                      <div>
                        <div class="name">${escapeHtml(m.hostname)} <span class="badge command">${escapeHtml(m.platform || "")}</span></div>
                        <div class="meta">Scanned ${escapeHtml(new Date(m.scannedAt).toLocaleString())}</div>
                        <div class="meta">${tops || "No categories"}</div>
                      </div>
                      <div class="size">${fmtBytes(m.reclaimable)}</div>
                    </div>`;
                  })
                  .join("")
              : `<div class="empty">No fleet reports yet — ingest this machine after a scan.</div>`
          }
        </div>
      </div>
    </div>`;
}

function renderAccount() {
  const el = $("#view-account");
  const info = state.tier || { tier: "team", displayName: "Team", matrix: [], source: "default-team" };
  const matrix = info.matrix || [];
  const active = (info.tier || "pro").toLowerCase();
  el.innerHTML = `
    <div class="grid">
      <div class="card wide">
        <h3>Current plan: ${escapeHtml(info.displayName || "Pro")}</h3>
        <p>Source: <code>${escapeHtml(info.source || "default-team")}</code>.
        Override with <code>STOGUARD_TIER=free|pro|team</code> or <code>license.json</code> in the data directory.</p>
      </div>
      <div class="card wide">
        <div class="pricing-grid">
          ${["free", "pro", "team"]
            .map((t) => {
              const label = t[0].toUpperCase() + t.slice(1);
              const price = t === "free" ? "$0" : t === "pro" ? "Local / Pro" : "Team";
              const blurb =
                t === "free"
                  ? "Scan, Trash, timeline"
                  : t === "pro"
                    ? "Doctor, Ask, duplicates, models, export"
                    : "Everything + fleet ingest & console";
              return `<div class="price-card ${active === t ? "active" : ""}">
                <h3>${label}</h3>
                <div class="price">${price}</div>
                <ul><li><strong>${blurb}</strong></li>
                ${active === t ? "<li><strong>Unlocked on this machine</strong></li>" : "<li>Not active</li>"}
                </ul>
              </div>`;
            })
            .join("")}
        </div>
      </div>
      <div class="card wide">
        <h3>Feature matrix</h3>
        <table class="feature-matrix">
          <thead><tr><th>Feature</th><th>Free</th><th>Pro</th><th>Team</th><th>Here</th></tr></thead>
          <tbody>
            ${matrix
              .map(
                (r) => `<tr>
                <td><strong>${escapeHtml(r.name)}</strong><div class="meta">${escapeHtml(r.description)}</div></td>
                <td class="${r.free ? "ok" : "no"}">${r.free ? "✓" : "—"}</td>
                <td class="${r.pro ? "ok" : "no"}">${r.pro ? "✓" : "—"}</td>
                <td class="${r.team ? "ok" : "no"}">${r.team ? "✓" : "—"}</td>
                <td class="${r.unlocked ? "ok" : "no"}">${r.unlocked ? "unlocked" : "locked"}</td>
              </tr>`
              )
              .join("")}
          </tbody>
        </table>
      </div>
    </div>`;
}

function render() {
  updateTierUI();
  renderHero();
  renderOverview();
  renderHealth();
  renderDoctor();
  renderLearning();
  renderAutomation();
  renderDuplicates();
  renderAICleanup();
  renderPackages();
  renderMedia();
  renderHistory();
  renderItems();
  renderFleet();
  renderAccount();
  bindActions();
  const gh = $("#goto-health");
  if (gh) gh.onclick = () => setView("health");
}

function bindActions() {
  document.querySelectorAll("[data-reveal]").forEach((btn) => {
    btn.onclick = async () => {
      try {
        await api(`/api/reveal?path=${encodeURIComponent(btn.dataset.reveal)}`);
      } catch (e) {
        toast(e.message);
      }
    };
  });
  document.querySelectorAll("[data-copy-cmd]").forEach((btn) => {
    btn.onclick = async () => {
      try {
        await navigator.clipboard.writeText(btn.dataset.copyCmd);
        toast("Command copied — paste in Terminal / PowerShell");
      } catch {
        toast(btn.dataset.copyCmd);
      }
    };
  });
  document.querySelectorAll("[data-trash]").forEach((btn) => {
    btn.onclick = async () => {
      if (!confirm(`Move “${btn.dataset.name}” to ${trashVerb()}?\n\n${btn.dataset.trash}\n\nRecoverable until you empty ${trashVerb()}.`)) return;
      try {
        const data = await api("/api/trash", {
          method: "POST",
          body: JSON.stringify({ path: btn.dataset.trash }),
        });
        const r = (data.results && data.results[0]) || {};
        if (r.status === "error") throw new Error(r.error || "Clean failed");
        if (r.method === "staging") {
          toast(`Staged (Recycle Bin blocked). Look in: ${r.destination || "%APPDATA%\\\\Stoguard\\\\Recycle"}`);
        } else {
          toast(`Moved to ${trashVerb()}`);
        }
        await runScan({ source: "after-clean" });
      } catch (e) {
        toast(`Clean failed: ${e.message}`);
      }
    };
  });
  const reset = $("#reset-adaptive");
  if (reset) {
    reset.onclick = async () => {
      await api("/api/reset-adaptive", { method: "POST" });
      toast("Adaptive skips cleared");
    };
  }
  const exportBtns = ["#export-fleet", "#export-fleet-2"];
  exportBtns.forEach((sel) => {
    const b = $(sel);
    if (!b) return;
    b.onclick = async () => {
      try {
        const data = await api("/api/fleet/export");
        const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
        const a = document.createElement("a");
        a.href = URL.createObjectURL(blob);
        a.download = `stoguard-fleet-${data.hostname || "machine"}.json`;
        a.click();
        toast("Fleet JSON exported");
      } catch (e) {
        toast(e.message);
      }
    };
  });
  const ingest = $("#ingest-self");
  if (ingest) {
    ingest.onclick = async () => {
      try {
        await api("/api/fleet/ingest", { method: "POST", body: "{}" });
        toast("Machine ingested");
        await loadFleet();
      } catch (e) {
        toast(e.message);
      }
    };
  }
  const refresh = $("#refresh-fleet");
  if (refresh) refresh.onclick = () => loadFleet();
}

async function cleanSelected() {
  const boxes = [...document.querySelectorAll(".clean-check:checked")];
  if (!boxes.length) {
    toast("Select safe/check items first (or click Select all safe)");
    return;
  }
  const checkFirst = boxes.filter((b) => b.dataset.safety === "check");
  let msg = `Move ${boxes.length} item(s) to ${trashVerb()}?\n\nNothing is permanent until you empty ${trashVerb()}.`;
  if (checkFirst.length) {
    msg += `\n\n${checkFirst.length} item(s) are “check first” — review paths carefully.`;
  }
  if (!confirm(msg)) return;
  const paths = boxes.map((b) => b.dataset.path);
  try {
    const data = await api("/api/trash", {
      method: "POST",
      body: JSON.stringify({ paths }),
    });
    const staged = (data.results || []).filter((r) => r.method === "staging");
    const failed = (data.results || []).filter((r) => r.status === "error");
    let note = `Cleaned ${data.cleaned || 0} / ${data.total || paths.length} → ${trashVerb()}`;
    if (staged.length) note += ` · ${staged.length} staged under %APPDATA%\\Stoguard\\Recycle`;
    if (failed.length) note += ` · ${failed.length} failed: ${failed[0].error || ""}`;
    toast(note);
    await runScan({ source: "after-clean" });
  } catch (e) {
    toast(`Clean failed: ${e.message}`);
  }
}

async function loadFleet() {
  if (!allows("fleet_admin")) {
    renderFleet();
    bindActions();
    return;
  }
  try {
    state.fleet = await api("/api/fleet");
  } catch (e) {
    state.fleet = [];
    toast(e.message);
  }
  renderFleet();
  bindActions();
}


async function loadPackages({ force = false } = {}) {
  if (!allows("packages")) { renderPackages(); bindActions(); return; }
  if (state.packagesLoading) return;
  if (state.packagesLoaded && !force && (state.packages || []).length) {
    renderPackages();
    bindActions();
    return;
  }
  state.packagesLoading = true;
  state.packagesError = null;
  renderPackages();
  try {
    state.packages = await api("/api/packages");
    state.packagesLoaded = true;
    if (!(state.packages || []).length) {
      toast("Package Finder finished — no sizable installs matched thresholds");
    } else {
      toast(`Package Finder: ${state.packages.length} installs · ${fmtBytes(state.packages.reduce((a, p) => a + (p.sizeBytes || 0), 0))}`);
    }
  } catch (e) {
    state.packagesError = e.message || "Request failed";
    toast(`Package Finder failed: ${state.packagesError}`);
  } finally {
    state.packagesLoading = false;
    renderPackages();
    bindActions();
  }
}

async function loadAICleanup() {
  if (allows("models")) {
    try { state.models = await api("/api/models"); }
    catch { state.models = []; }
  }
  if (allows("agent_tools")) {
    try { state.agentTools = await api("/api/agent-tools"); }
    catch { state.agentTools = []; }
  }
  renderAICleanup();
  bindActions();
}

async function toggleScanAutomation() {
  if (state.scanAutomation) {
    setScanAutomation(false);
    toast("Scan automation turned off");
    showNotify({
      title: "Scan automation off",
      body: "Automatic re-scans are paused. You can still use Scan again anytime.",
      actions: [{ label: "OK", primary: true }],
    });
    return;
  }

  if ("Notification" in window && Notification.permission === "default") {
    try { await Notification.requestPermission(); } catch (_) {}
  }

  setScanAutomation(true);
  notifyOS("Stoguard", "Scan automation started — beginning scan");
  showNotify({
    title: "Scan automation started",
    body: "You’ll be notified when this scan finishes.\n\nStarting now, then again every 30 minutes while this page stays open.",
    actions: [
      { label: "OK", primary: true },
      {
        label: "Cancel automation",
        onClick: () => {
          setScanAutomation(false);
          toast("Scan automation cancelled");
        },
      },
    ],
  });
  // Begin immediately after the notify is shown.
  runScan({ source: "automation" });
}

async function runScan({ source = "manual" } = {}) {
  if (state.scanning) return;
  state.scanning = true;
  const fromAuto = source === "automation";
  if (fromAuto) {
    toast("Automated scan starting…");
    notifyOS("Stoguard", "Automated scan starting");
  } else {
    toast(state.scan ? "Scanning again…" : "Scan starting…");
  }

  const btn = $("#btn-scan");
  if (btn) {
    btn.disabled = true;
    btn.textContent = "Scanning…";
  }
  renderHero();

  try {
    const data = await api("/api/scan", { method: "POST" });
    state.scan = data.scan;
    state.doctor = data.doctor;
    if (data.tier) state.tier = data.tier;
    try {
      state.status = await api("/api/status");
    } catch (_) {}
    if (allows("duplicates")) {
      try {
        state.duplicates = await api("/api/duplicates");
      } catch {
        state.duplicates = [];
      }
    }
    if (allows("models")) {
      try {
        state.models = await api("/api/models");
      } catch {
        state.models = [];
      }
    }
    state.history = await api("/api/history");
    await loadIntelligence();

    const summary = `Found ${state.scan.items.length} findings · ${fmtBytes(state.scan.safeBytes)} safe to clean · ${fmtBytes(state.scan.checkBytes)} to review.`;
    toast(summary);
    notifyOS("Stoguard — scan complete", summary);
    // Package Finder loads on demand (full Local\\Programs walks are slow on Windows).
    render();

    if (fromAuto || state.scanAutomation) {
      showNotify({
        title: "Scan complete",
        body: `${summary}\n\nWould you like to view the results, or clear them and start fresh?`,
        actions: [
          {
            label: "View results",
            primary: true,
            onClick: () => setView("overview"),
          },
          {
            label: "Clear results",
            danger: true,
            onClick: () => clearScanResults(),
          },
          { label: "Dismiss" },
        ],
      });
    }
  } catch (e) {
    toast(e.message);
    if (fromAuto) {
      showNotify({
        title: "Automated scan failed",
        body: e.message || "Something went wrong during the scan.",
        actions: [{ label: "OK", primary: true }],
      });
    }
  } finally {
    state.scanning = false;
    if (btn) {
      btn.disabled = false;
      btn.textContent = "Scan workstation";
    }
    renderHero();
  }
}

const THEME_KEY = "stoguard.theme";

function currentTheme() {
  return document.documentElement.getAttribute("data-theme") === "light" ? "light" : "dark";
}

function applyTheme(theme) {
  const next = theme === "light" ? "light" : "dark";
  document.documentElement.setAttribute("data-theme", next);
  try { localStorage.setItem(THEME_KEY, next); } catch (_) {}
  const btn = $("#theme-toggle");
  if (btn) btn.textContent = next === "light" ? "Dark mode" : "Light mode";
}

function toggleTheme() {
  applyTheme(currentTheme() === "light" ? "dark" : "light");
}

async function init() {
  applyTheme(currentTheme());
  const themeBtn = $("#theme-toggle");
  if (themeBtn) themeBtn.onclick = toggleTheme;

  document.querySelectorAll(".nav").forEach((b) => {
    b.onclick = () => setView(b.dataset.view);
  });
  $("#btn-scan").onclick = () => runScan({ source: "manual" });
  $("#notify").addEventListener("click", (e) => {
    if (e.target === $("#notify")) hideNotify();
  });
  if (state.scanAutomation) {
    setScanAutomation(true);
  }
  // Deep-link: http://127.0.0.1:8787/#packages
  const hashView = (location.hash || "").replace(/^#/, "");
  if (hashView && titles[hashView]) {
    state.view = hashView;
  }
  $("#chat-form").onsubmit = async (e) => {
    e.preventDefault();
    const input = $("#chat-input");
    const q = input.value.trim();
    if (!q) return;
    if (!allows("ask")) {
      toast("Ask Stoguard requires Pro");
      return;
    }
    if (!state.scan) {
      toast("Scan first");
      return;
    }
    const log = $("#chat-log");
    log.insertAdjacentHTML("beforeend", `<div class="bubble user">${escapeHtml(q)}</div>`);
    input.value = "";
    try {
      const { answer } = await api("/api/ask", {
        method: "POST",
        body: JSON.stringify({ question: q }),
      });
      log.insertAdjacentHTML("beforeend", `<div class="bubble bot">${escapeHtml(answer)}</div>`);
      log.scrollTop = log.scrollHeight;
    } catch (err) {
      toast(err.message);
    }
  };

  try {
    state.status = await api("/api/status");
    state.tier = await api("/api/tier");
    $("#platform-label").textContent = `${state.status.platform} · ${state.status.arch} · ${state.status.tierName}`;
  } catch {
    $("#platform-label").textContent = "offline";
  }
  if (state.view && state.view !== "overview") {
    setView(state.view);
  } else {
    render();
  }
}

init();
