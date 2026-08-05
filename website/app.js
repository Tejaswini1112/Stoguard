(() => {
  const meters = {
    docker: { label: "Docker", gb: 23, el: null },
    xcode: { label: "Xcode", gb: 14, el: null },
    ollama: { label: "Ollama Models", gb: 9, el: null },
  };

  const scanSteps = [
    { text: "Analyzing workstation…", cls: "run" },
    { text: "✓ Docker ……………… 23 GB", cls: "ok", meter: "docker" },
    { text: "✓ Scanning Xcode…", cls: "ok", meter: "xcode" },
    { text: "✓ Scanning AI Models…", cls: "ok", meter: "ollama" },
    { text: "✓ Finding Duplicates…", cls: "ok" },
  ];

  const termLines = [
    "$ Analyze my workstation",
    "",
    "✓ Docker images haven't been used in 64 days.",
    "✓ Flutter SDK duplicated.",
    "✓ 12 Node versions detected.",
    "✓ 8 Python environments inactive.",
    "✓ Xcode cache consuming 14GB.",
  ];

  const tech = [
    "Swift", "Docker", "Node", "Python", "Flutter", "Android Studio",
    "VS Code", "JetBrains", "Xcode", "Rust", "Go", "Unity",
    "Ollama", "LM Studio", "Homebrew", "Git", "Terraform", "Kubernetes",
  ];

  const logEl = document.getElementById("scan-log");
  const recoverEl = document.getElementById("recover-gb");
  const healthPct = document.getElementById("health-pct");
  const healthRing = document.getElementById("health-ring");
  const buildStatus = document.getElementById("build-status");
  const dashCta = document.getElementById("dash-cta");
  const runBtn = document.getElementById("run-analysis");
  const termBody = document.getElementById("term-body");
  const techCloud = document.getElementById("tech-cloud");
  const baSplit = document.getElementById("ba-split");

  document.querySelectorAll(".meter").forEach((el) => {
    const key = el.dataset.key;
    if (meters[key]) meters[key].el = el;
  });

  tech.forEach((name) => {
    const span = document.createElement("span");
    span.className = "tech-pill";
    span.textContent = name;
    techCloud.appendChild(span);
  });

  function setMeter(key, animate = true) {
    const m = meters[key];
    if (!m?.el) return;
    const max = 23;
    const pct = Math.round((m.gb / max) * 100);
    m.el.querySelector("b").textContent = `${m.gb} GB`;
    const bar = m.el.querySelector("i");
    if (animate) {
      requestAnimationFrame(() => bar.style.setProperty("--w", String(pct)));
    } else {
      bar.style.setProperty("--w", String(pct));
    }
  }

  function setHealth(pct) {
    healthPct.textContent = `${pct}%`;
    const circ = 2 * Math.PI * 52;
    healthRing.style.strokeDashoffset = String(circ * (1 - pct / 100));
  }

  function setRecover(gb) {
    recoverEl.textContent = `${gb.toFixed(1)} GB`;
  }

  let analysisRunning = false;
  let analysisDone = false;

  async function runAnalysis({ fromScroll = false } = {}) {
    if (analysisRunning) return;
    if (analysisDone && fromScroll) return;
    analysisRunning = true;
    analysisDone = false;
    dashCta.hidden = true;
    runBtn.disabled = true;
    runBtn.textContent = "Analyzing…";
    logEl.innerHTML = "";
    setRecover(0);
    setHealth(0);
    buildStatus.textContent = "Scanning…";
    buildStatus.style.color = "var(--muted)";
    Object.keys(meters).forEach((k) => {
      const el = meters[k].el;
      if (!el) return;
      el.querySelector("b").textContent = "0 GB";
      el.querySelector("i").style.setProperty("--w", "0");
    });

    let recovered = 0;
    for (const step of scanSteps) {
      const li = document.createElement("li");
      li.className = step.cls;
      li.textContent = step.text;
      logEl.appendChild(li);
      if (step.meter) {
        setMeter(step.meter);
        recovered += meters[step.meter].gb;
        setRecover(recovered);
        setHealth(Math.min(92, 40 + recovered));
      }
      await wait(fromScroll ? 380 : 520);
    }

    setRecover(46.8);
    setHealth(92);
    buildStatus.textContent = "Healthy ✓";
    buildStatus.style.color = "var(--ok)";
    dashCta.hidden = false;
    runBtn.disabled = false;
    runBtn.textContent = "Run AI Analysis";
    analysisRunning = false;
    analysisDone = true;
  }

  function wait(ms) {
    return new Promise((r) => setTimeout(r, ms));
  }

  runBtn.addEventListener("click", () => runAnalysis({ fromScroll: false }));

  // Scroll-driven first analysis when hero dashboard enters view
  const dash = document.getElementById("hero-dash");
  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((e) => {
        if (e.isIntersecting && !analysisDone && !analysisRunning) {
          runAnalysis({ fromScroll: true });
        }
      });
    },
    { threshold: 0.45 }
  );
  io.observe(dash);

  // Terminal typewriter when section visible
  let termDone = false;
  const termSection = document.getElementById("analysis");
  const termObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach(async (e) => {
        if (!e.isIntersecting || termDone) return;
        termDone = true;
        termBody.textContent = "";
        for (const line of termLines) {
          termBody.textContent += (termBody.textContent ? "\n" : "") + line;
          await wait(90);
        }
      });
    },
    { threshold: 0.35 }
  );
  termObserver.observe(termSection);

  // Before / After animation
  let baDone = false;
  const baObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((e) => {
        if (!e.isIntersecting || baDone) return;
        baDone = true;
        animateValue('[data-ba="a-free"]', 18, 74, " GB");
        animateValue('[data-ba="a-build"]', 52, 26, " sec");
        animateValue('[data-ba="a-cpu"]', 85, 44, "%");
        const health = document.querySelector('[data-ba="a-health"]');
        setTimeout(() => {
          health.textContent = "Excellent";
          health.classList.add("good");
        }, 700);
      });
    },
    { threshold: 0.4 }
  );
  baObserver.observe(baSplit);

  function animateValue(sel, from, to, suffix) {
    const el = document.querySelector(sel);
    if (!el) return;
    const start = performance.now();
    const dur = 900;
    function frame(t) {
      const p = Math.min(1, (t - start) / dur);
      const eased = 1 - Math.pow(1 - p, 3);
      const v = Math.round(from + (to - from) * eased);
      el.textContent = `${v}${suffix}`;
      if (p < 1) requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
  }

  // Subtle parallax on feature cards
  document.querySelectorAll(".fcard").forEach((card, i) => {
    card.style.transitionDelay = `${(i % 4) * 40}ms`;
  });
})();
