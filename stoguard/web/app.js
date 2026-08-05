const state = {
  status: null,
  tier: null,
  scan: null,
  doctor: null,
  duplicates: [],
  models: [],
  history: [],
  fleet: [],
  view: "overview",
};

const titles = {
  overview: ["Overview", "AI developer workstation manager"],
  doctor: ["Workstation Doctor", "Prioritized cleanup recommendations"],
  ask: ["Ask Stoguard", "Answers grounded in your last scan"],
  duplicates: ["Duplicates", "Overlapping caches and installs"],
  models: ["AI Models", "Local model paths from scan"],
  history: ["Storage Timeline", "Reclaimable safe space over time"],
  items: ["All Findings", "Everything the scanner measured"],
  fleet: ["Fleet", "Team machine rollup"],
  account: ["Pricing / Account", "Free, Pro, and Team features"],
};

const $ = (sel) => document.querySelector(sel);

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
  toast._t = setTimeout(() => el.classList.add("hidden"), 2800);
}

async function api(path, opts = {}) {
  const res = await fetch(path, {
    headers: { "Content-Type": "application/json", ...(opts.headers || {}) },
    ...opts,
  });
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
  if (name === "models" && state.scan && !state.models.length) loadModels();
  if (name === "account") renderAccount();
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

function itemRow(it, { showChildren = true } = {}) {
  const kids =
    showChildren && it.children?.length
      ? `<div class="meta">Top: ${it.children
          .slice(0, 3)
          .map((c) => escapeHtml(c.name))
          .join(", ")}</div>`
      : "";
  const trashBtn =
    it.safety === "safe" || it.safety === "check"
      ? `<button class="btn small" data-trash="${escapeAttr(it.path)}" data-name="${escapeAttr(it.name)}">Trash</button>`
      : "";
  return `<div class="row">
    <div>
      <div class="name">${escapeHtml(it.name)} <span class="badge ${escapeAttr(it.safety)}">${escapeHtml(it.safety)}</span></div>
      <div class="meta">${escapeHtml(it.path)}</div>
      ${kids}
    </div>
    <div class="size">${fmtBytes(it.sizeBytes)}</div>
    <div class="actions">
      <button class="btn small" data-reveal="${escapeAttr(it.path)}">Reveal</button>
      ${trashBtn}
    </div>
  </div>`;
}

function renderHero() {
  const s = state.scan;
  const box = $("#hero-stats");
  if (!s) {
    box.innerHTML = `<div class="stat"><b>—</b><span>Scan first</span></div>`;
    return;
  }
  box.innerHTML = `
    <div class="stat"><b>${fmtBytes(s.safeBytes)}</b><span>Safe</span></div>
    <div class="stat"><b>${fmtBytes(s.checkBytes)}</b><span>Review</span></div>
    <div class="stat"><b>${fmtBytes(s.freeBytes)}</b><span>Free disk</span></div>
    <div class="stat"><b>${s.items.length}</b><span>Findings</span></div>`;
}

function renderOverview() {
  const el = $("#view-overview");
  if (!state.scan) {
    el.innerHTML = `<div class="empty">Press <strong>Scan workstation</strong> to analyze developer caches on this machine.</div>`;
    return;
  }
  const s = state.scan;
  const d = state.doctor;
  const top = s.items.slice(0, 8);
  const cats = Object.entries(s.categoryTotals || {})
    .sort((a, b) => b[1] - a[1])
    .slice(0, 6);
  el.innerHTML = `
    <div class="grid">
      <div class="card wide">
        <h3>${escapeHtml(d?.headline || "Scan complete")}</h3>
        <p>${(d?.summaryLines || []).map(escapeHtml).join(" · ")}</p>
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
        <h3>Largest findings</h3>
        <div class="list" style="margin-top:12px">${top.map((it) => itemRow(it)).join("")}</div>
      </div>
    </div>`;
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
    el.innerHTML = `<div class="empty">No obvious duplicate groups found.</div>`;
    return;
  }
  el.innerHTML = `<div class="list">${groups
    .map(
      (g) => `<div class="card wide" style="margin-bottom:12px">
      <h3>${escapeHtml(g.label)} <span class="badge check">${escapeHtml(g.kind)}</span></h3>
      <p>${escapeHtml(g.advice)} · potential waste ${fmtBytes(g.wasteBytes)}</p>
      <div class="list" style="margin-top:12px">${g.items.map((it) => itemRow(it, { showChildren: false })).join("")}</div>
    </div>`
    )
    .join("")}</div>`;
}

function renderModels() {
  const el = $("#view-models");
  if (!allows("models")) {
    el.innerHTML = `<div class="empty">AI model inventory requires <strong>Pro</strong>.</div>`;
    return;
  }
  if (!state.scan) {
    el.innerHTML = `<div class="empty">Scan first to list model paths.</div>`;
    return;
  }
  const list = state.models || [];
  if (!list.length) {
    el.innerHTML = `<div class="empty">No AI model stores matched this scan.</div>`;
    return;
  }
  el.innerHTML = `<div class="list">${list
    .map(
      (m) => `<div class="row">
      <div>
        <div class="name">${escapeHtml(m.name)} <span class="badge command">${escapeHtml(m.provider)}</span></div>
        <div class="meta">${escapeHtml(m.path)}</div>
        <div class="meta">${escapeHtml(m.note || m.category)}</div>
      </div>
      <div class="size">${fmtBytes(m.sizeBytes)}</div>
      <div class="actions"><button class="btn small" data-reveal="${escapeAttr(m.path)}">Reveal</button></div>
    </div>`
    )
    .join("")}</div>`;
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
  renderDoctor();
  renderDuplicates();
  renderModels();
  renderHistory();
  renderItems();
  renderFleet();
  renderAccount();
  bindActions();
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
  document.querySelectorAll("[data-trash]").forEach((btn) => {
    btn.onclick = async () => {
      if (!confirm(`Move “${btn.dataset.name}” to Trash?\n\n${btn.dataset.trash}`)) return;
      try {
        await api("/api/trash", {
          method: "POST",
          body: JSON.stringify({ path: btn.dataset.trash }),
        });
        toast("Moved to Trash");
        await runScan();
      } catch (e) {
        toast(e.message);
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

async function loadModels() {
  if (!allows("models") || !state.scan) return;
  try {
    state.models = await api("/api/models");
  } catch {
    state.models = [];
  }
  renderModels();
  bindActions();
}

async function runScan() {
  const btn = $("#btn-scan");
  btn.disabled = true;
  btn.textContent = "Scanning…";
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
    toast(`Found ${state.scan.items.length} items · ${fmtBytes(state.scan.safeBytes)} safe`);
    render();
  } catch (e) {
    toast(e.message);
  } finally {
    btn.disabled = false;
    btn.textContent = "Scan workstation";
  }
}

async function init() {
  document.querySelectorAll(".nav").forEach((b) => {
    b.onclick = () => setView(b.dataset.view);
  });
  $("#btn-scan").onclick = runScan;
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
  render();
}

init();
