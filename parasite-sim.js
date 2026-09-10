/**
 * PARASITE — live console, driven by a running simulation of the mechanic.
 *
 * Nothing here touches a chain. It models the game the contracts would play so
 * the pacing, drain rates and escalation can be felt and tuned before any of it
 * is written in Solidity. Every number on screen comes out of this model.
 */
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  if (!$("console-root")) return;

  // --- tunables: these are the actual game parameters under test ------------
  const P = {
    holders: 140,
    baseDrainPerSec: 0.08 / 3600, // 8%/h at strength 1 — swept for 25-55h rounds
    growthDiv: 80000,             // how fast it strengthens on what it eats
    airborneBaseSec: 600,         // 10 min of quiet before it hunts
    airborneMinSec: 60,           // floor as it gets aggressive
    resistK: 60,                  // each cure makes the next harder
    survivorFloor: 0.10,        // round ends at 10% clean
    tradePerSec: 1 / 120,       // pool-wide trade flow; each trade infects the trader
    tickMs: 250,
    // The console is a demo, so time is compressed: one simulated hour per
    // second of wall clock. A 30h round plays out in about half a minute.
    timeScale: 3600
  };

  const REAGENTS = ["GLD","DJT","GME","AMC","SPCX","TSLA","AAPL","RBLX","SPY","HIMS","GOOGL"];
  const fmt = (n, d = 2) => n.toLocaleString(undefined, { minimumFractionDigits: d, maximumFractionDigits: d });
  const addr = () => "0x" + Math.random().toString(16).slice(2, 6) + "…" + Math.random().toString(16).slice(2, 6);

  // --- state ----------------------------------------------------------------
  let S;
  function newRound(n = 1, carriedPot = 0) {
    const wallets = Array.from({ length: P.holders }, () => ({
      id: addr(),
      bal: 200 + Math.random() * 9000,
      infected: false,
      bled: 0,
      since: 0,
      lastAct: Math.random() * 60,
      held: Math.random() * 9 * 86400
    }));
    wallets[Math.floor(Math.random() * wallets.length)].infected = true;
    return {
      round: n, t: 0, strength: 1, consumed: 0,
      pot: carriedPot, equities: { NVDA: 0, GLD: 0, GME: 0, AMC: 0 },
      wallets, quiet: 0, feed: [], cures: 0, airborneCount: 0, ended: false
    };
  }
  S = newRound();

  const log = (kind, text) => {
    S.feed.unshift({ kind, text, t: Date.now() });
    if (S.feed.length > 40) S.feed.pop();
  };
  log("sys", "ROUND 1 OPEN — one host seeded");

  const clean = () => S.wallets.filter((w) => !w.infected && w.bal > 1);
  const infected = () => S.wallets.filter((w) => w.infected);

  /** Airborne targeting: fattest, oldest, laziest. Same weighting the contract uses. */
  function riskScore(w) {
    const total = S.wallets.reduce((a, x) => a + x.bal, 0) || 1;
    const size = w.bal / total;
    const held = Math.min(w.held / (9 * 86400), 1);
    const idle = Math.min(w.lastAct / 120, 1);
    return size * 0.45 + held * 0.25 + idle * 0.30;
  }

  function step() {
    if (S.ended) return;
    const dt = (P.tickMs / 1000) * P.timeScale;
    S.t += dt;

    // 1. infected bleed into the pot; the parasite grows on what it eats
    infected().forEach((w) => {
      const bite = w.bal * P.baseDrainPerSec * S.strength * dt;
      const real = Math.min(bite, w.bal);
      w.bal -= real; w.bled += real; S.pot += real; S.consumed += real;
      w.since += dt;
    });
    S.strength = 1 + S.consumed / P.growthDiv;

    // 2. players act: trade (pass it on), or cure
    S.wallets.forEach((w) => {
      w.lastAct += dt; w.held += dt;
      const cureChance = (0.0009 / (1 + S.cures / P.resistK)) * dt;
      if (w.infected && Math.random() < cureChance) {
        // cure: brew an antidote, ingredients go to the pot
        const carried = w.since;               // read before we clear it
        w.infected = false; w.since = 0; w.lastAct = 0; S.cures++;
        S.equities.NVDA += 0.04 + Math.random() * 0.05;
        const r = ["GLD","GME","AMC"][Math.floor(Math.random() * 3)];
        S.equities[r] += 0.02 + Math.random() * 0.08;
        log("cure", `${w.id} brewed an antidote — infected ${fmt(carried / 3600, 1)}h, bled ${fmt(w.bled)}`);
      }
    });

    // 3. every trade infects the trader — the pool is permanently contaminated
    if (Math.random() < P.tradePerSec * dt) {
      const c = clean();
      if (c.length) {
        const n = c[Math.floor(Math.random() * c.length)];
        n.infected = true; n.since = 0; n.lastAct = 0;
        log("pass", `${n.id} traded — caught it from the pool`);
      }
      S.quiet = 0;
    }

    // 4. if the pool goes quiet it hunts on its own
    S.quiet += dt;
    const window = Math.max(P.airborneMinSec, P.airborneBaseSec / S.strength);
    if (S.quiet >= window) {
      S.quiet = 0;
      const c = clean();
      if (c.length) {
        const scored = c.map((w) => ({ w, s: riskScore(w) })).sort((a, b) => b.s - a.s);
        const take = Math.max(1, Math.floor(S.strength));
        const taken = [];
        for (let k = 0; k < take && k < scored.length; k++) {
          scored[k].w.infected = true; scored[k].w.since = 0; taken.push(scored[k].w.id);
        }
        S.airborneCount++;
        log("air", taken.length > 1
          ? `AIRBORNE — it took ${taken.length} at once: ${taken.slice(0,2).join(", ")}…`
          : `AIRBORNE — it took ${taken[0]} (risk ${(riskScore(scored[0].w) * 100).toFixed(0)}%)`);
      }
    }

    // 5. round end at the survivor floor
    const c = clean().length;
    if (c <= Math.ceil(S.wallets.length * P.survivorFloor)) {
      S.ended = true;
      log("sys", `ROUND ${S.round} CLOSED — ${c} survivors split ${fmt(S.pot)} PARASITE`);
      setTimeout(() => { S = newRound(S.round + 1, 0); log("sys", `ROUND ${S.round} OPEN`); }, 4200);
    }
  }

  // --- render ---------------------------------------------------------------
  function paint() {
    const inf = infected(), cl = clean();
    const floor = Math.ceil(S.wallets.length * P.survivorFloor);
    const toGo = Math.max(0, cl.length - floor);

    $("c-round").textContent = S.round;
    const el = $("c-elapsed");
    if (el) el.textContent = (S.t / 3600).toFixed(1) + "h";
    $("c-strength").textContent = fmt(S.strength) + "×";
    $("c-strength-bar").style.width = Math.min(100, (S.strength / 6) * 100) + "%";
    $("c-drain").textContent = fmt(P.baseDrainPerSec * S.strength * 3600 * 100, 1) + "%/h";
    const win = Math.max(P.airborneMinSec, P.airborneBaseSec / S.strength);
    $("c-aggression").textContent = "hunts every " + fmt(win, 0) + "s";
    $("c-consumed").textContent = fmt(S.consumed);

    $("c-pot").textContent = fmt(S.pot);
    $("c-equities").innerHTML = Object.entries(S.equities)
      .map(([k, v]) => `<span><b>${k}</b>${fmt(v, 3)}</span>`).join("");

    $("c-clean").textContent = cl.length;
    $("c-infected").textContent = inf.length;
    $("c-floor").textContent = floor;
    $("c-togo").textContent = toGo;
    const pct = (cl.length / S.wallets.length) * 100;
    $("c-survivor-bar").style.width = Math.max(0, Math.min(100, pct)) + "%";
    $("c-survivor-bar").className = pct <= 20 ? "danger" : "";

    $("c-infected-list").innerHTML = inf
      .sort((a, b) => b.bled - a.bled).slice(0, 8)
      .map((w) => `<div class="c-row"><span>${w.id}</span><span>${fmt(w.since, 0)}s</span>
        <span class="c-bled">−${fmt(w.bled)}</span><span>${fmt(w.bal, 0)}</span></div>`).join("")
      || `<div class="c-empty">no active infections</div>`;

    $("c-risk-list").innerHTML = cl
      .map((w) => ({ w, s: riskScore(w) })).sort((a, b) => b.s - a.s).slice(0, 5)
      .map(({ w, s }) => `<div class="c-row"><span>${w.id}</span><span>${fmt(w.bal, 0)}</span>
        <span>${fmt(w.lastAct, 0)}s</span><span class="c-risk"><i style="width:${Math.min(100, s * 260)}%"></i>${(s * 100).toFixed(0)}%</span></div>`).join("");

    $("c-feed").innerHTML = S.feed.slice(0, 14)
      .map((f) => `<div class="c-ev c-${f.kind}">${f.text}</div>`).join("");

    const EP = 43200, now = Date.now() / 1000;
    $("c-reagent").textContent = REAGENTS[Math.floor(now / EP) % REAGENTS.length];
    const left = EP - (now % EP);
    $("c-rotate").textContent = Math.floor(left / 3600) + "h " + String(Math.floor((left % 3600) / 60)).padStart(2, "0") + "m";
  }

  let timer = null;
  const run = () => { timer = setInterval(() => { step(); paint(); }, P.tickMs); };
  const halt = () => { clearInterval(timer); timer = null; };

  paint(); run();
  document.addEventListener("visibilitychange", () => document.hidden ? halt() : (!timer && run()));
})();
