/**
 * HOOKED / HATCH frontend.
 * Dependency-free: raw EIP-1193 + eth_call ABI encoding. No build step, no CDN.
 */
(() => {
  "use strict";

  const cfg = window.HOOKED_CONFIG || {};
  const DECIMALS = 18n;
  const ZERO = "0x0000000000000000000000000000000000000000";

  const SEL = {
    balanceOf: "0x70a08231",
    allowance: "0xdd62ed3e",
    approve: "0x095ea7b3",
    feed: "0xf59dfdfb",
    stage: "0xc040e6b8",
    nextThreshold: "0x59d58bcd",
    progressBps: "0x6c1eba15",
    nestBalance: "0xdb06eb9b",
    pendingPonsFees: "0x11972416",
    claimableTotal: "0xf52c3711",
    claimAndSplit: "0xbf988ea7",
    eggBalance: "0xe48f44ff",
    crackable: "0x8b44feb3",
    currentBounty: "0x0a4255e4",
    totalBurned: "0xd89135cd",
    crackThreshold: "0xd547a5d9",
    crackEgg: "0xa50618fd"
  };

  /* ---------------------------------------------------------------- utils */

  const $ = (id) => document.getElementById(id);
  const isAddr = (a) => typeof a === "string" && /^0x[0-9a-fA-F]{40}$/.test(a);
  const padAddr = (a) => a.toLowerCase().replace(/^0x/, "").padStart(64, "0");
  const padUint = (n) => BigInt(n).toString(16).padStart(64, "0");
  const short = (a) => (isAddr(a) ? `${a.slice(0, 6)}…${a.slice(-4)}` : a);

  /** Exact fixed-point formatting. Never routes a token amount through a float. */
  function formatUnits(value, places = 4) {
    const neg = value < 0n;
    let v = neg ? -value : value;
    const base = 10n ** DECIMALS;
    const whole = v / base;
    const frac = (v % base).toString().padStart(Number(DECIMALS), "0").slice(0, places);
    const wholeStr = whole.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    return `${neg ? "-" : ""}${wholeStr}${places > 0 ? "." + frac : ""}`;
  }

  /** Parse a user-typed decimal string into base units without float error. */
  function parseUnits(input) {
    const s = String(input).trim();
    if (!/^\d*\.?\d*$/.test(s) || s === "" || s === ".") throw new Error("Enter a valid amount");
    const [w = "0", f = ""] = s.split(".");
    if (f.length > Number(DECIMALS)) throw new Error("Too many decimal places");
    return BigInt(w + f.padEnd(Number(DECIMALS), "0"));
  }

  const explorer = {
    address: (a) => `${cfg.explorerUrl}/address/${a}`,
    tx: (h) => `${cfg.explorerUrl}/tx/${h}`
  };

  /* ------------------------------------------------------------------ rpc */

  const endpoints = [cfg.rpcUrl, ...(cfg.rpcFallbacks || [])].filter(Boolean);
  let rpcIndex = 0;
  let rpcId = 0;

  async function rpc(method, params) {
    let lastErr;
    for (let attempt = 0; attempt < endpoints.length; attempt++) {
      const url = endpoints[(rpcIndex + attempt) % endpoints.length];
      try {
        const ctrl = new AbortController();
        const timer = setTimeout(() => ctrl.abort(), 12000);
        const res = await fetch(url, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ jsonrpc: "2.0", id: ++rpcId, method, params }),
          signal: ctrl.signal
        });
        clearTimeout(timer);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const json = await res.json();
        if (json.error) throw new Error(json.error.message || "RPC error");
        rpcIndex = (rpcIndex + attempt) % endpoints.length;
        return json.result;
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr || new Error("No RPC endpoint configured");
  }

  /** eth_call returning a single uint256. Returns null instead of throwing. */
  async function callUint(to, data) {
    if (!isAddr(to)) return null;
    try {
      const out = await rpc("eth_call", [{ to, data }, "latest"]);
      if (!out || out === "0x") return null;
      return BigInt(out);
    } catch (e) {
      console.warn("eth_call failed", to, data.slice(0, 10), e.message);
      return null;
    }
  }

  /* --------------------------------------------------------------- wallet */

  const wallet = {
    provider: null,
    account: null,

    available() {
      return typeof window.ethereum !== "undefined";
    },

    async connect() {
      if (!this.available()) {
        throw new Error("No wallet detected. Install a browser wallet to feed the egg directly.");
      }
      this.provider = window.ethereum;
      const accounts = await this.provider.request({ method: "eth_requestAccounts" });
      this.account = accounts && accounts[0];
      if (!this.account) throw new Error("No account authorised");
      await this.ensureChain();
      this.provider.on?.("accountsChanged", (a) => {
        this.account = a && a[0] ? a[0] : null;
        renderWallet();
        refresh();
      });
      this.provider.on?.("chainChanged", () => window.location.reload());
      return this.account;
    },

    async ensureChain() {
      const hexChain = "0x" + Number(cfg.chainId).toString(16);
      const current = await this.provider.request({ method: "eth_chainId" });
      if (current === hexChain) return;
      try {
        await this.provider.request({
          method: "wallet_switchEthereumChain",
          params: [{ chainId: hexChain }]
        });
      } catch (err) {
        // 4902 = chain unknown to the wallet; offer to add it.
        if (err && (err.code === 4902 || err.code === -32603)) {
          await this.provider.request({
            method: "wallet_addEthereumChain",
            params: [{
              chainId: hexChain,
              chainName: cfg.chainName || "Robinhood Chain",
              nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
              rpcUrls: [cfg.rpcUrl],
              blockExplorerUrls: [cfg.explorerUrl]
            }]
          });
        } else {
          throw err;
        }
      }
    },

    async send(to, data) {
      if (!this.account) await this.connect();
      await this.ensureChain();
      return this.provider.request({
        method: "eth_sendTransaction",
        params: [{ from: this.account, to, data }]
      });
    },

    async waitForReceipt(hash, timeoutMs = 120000) {
      const started = Date.now();
      while (Date.now() - started < timeoutMs) {
        const r = await rpc("eth_getTransactionReceipt", [hash]).catch(() => null);
        if (r) return r;
        await new Promise((res) => setTimeout(res, 2500));
      }
      return null;
    }
  };

  /* ------------------------------------------------------------ hatch page */

  if (document.body.dataset.page !== "hatch") {
    // Home page only needs the year/explorer links wired.
    return;
  }

  const LABELS = [
    "DORMANT", "HAIRLINE", "CRACKED", "MOVEMENT",
    "EYE CONTACT", "CONTAINMENT FAILING", "HATCHED", "READY TO CRACK"
  ];
  // Thresholds may be fractional (0.5 NVDA), and BigInt(0.5) throws, so route
  // every value through the string parser rather than BigInt() directly.
  const thresholds = (cfg.stageThresholds || [1, 5, 10, 25, 50, 100, 250]).map((n) => {
    try {
      return parseUnits(String(n));
    } catch {
      return 0n;
    }
  });

  const deployed = {
    nest: isAddr(cfg.nest) ? cfg.nest : null,
    router: isAddr(cfg.feeRouter) ? cfg.feeRouter : null,
    nvda: isAddr(cfg.nvda) ? cfg.nvda : null,
    locker: isAddr(cfg.buybackLocker) ? cfg.buybackLocker : null,
    token: isAddr(cfg.hatchToken) ? cfg.hatchToken : null
  };

  function status(msg, kind = "info") {
    const el = $("tx-status");
    if (!el) return;
    el.textContent = msg || "";
    el.dataset.kind = kind;
    el.style.display = msg ? "block" : "none";
  }

  /* ------------------------------------------------------------- rendering */

  function stageFromBalance(balance) {
    let s = 0;
    for (let i = 0; i < thresholds.length; i++) {
      if (balance < thresholds[i]) break;
      s++;
    }
    return s;
  }

  function renderNest(balance, stageOverride, nextOverride, bpsOverride) {
    const stage = stageOverride ?? stageFromBalance(balance);
    const low = stage === 0 ? 0n : thresholds[stage - 1];
    const high = stage >= thresholds.length ? low : thresholds[stage];

    let pct;
    if (bpsOverride != null) {
      pct = Number(bpsOverride) / 100;
    } else if (stage >= thresholds.length) {
      pct = 100;
    } else {
      const span = high - low;
      pct = span > 0n ? Number(((balance - low) * 10000n) / span) / 100 : 0;
    }
    pct = Math.max(0, Math.min(100, pct));

    $("nest-balance").textContent = `${formatUnits(balance)} NVDA`;
    $("stage-label").textContent = LABELS[Math.min(stage, LABELS.length - 1)];
    $("stage-number").textContent = `STAGE ${stage} / 7`;

    const next = nextOverride != null && nextOverride > 0n ? nextOverride : (stage >= thresholds.length ? 0n : high);
    $("next-threshold").textContent =
      stage >= thresholds.length || next === 0n
        ? "FINAL THRESHOLD CLEARED"
        : `NEXT: ${formatUnits(next, 0)} NVDA`;

    $("progress-fill").style.width = `${pct}%`;
    $("egg").className = `egg stage-${stage}`;
  }

  function renderAddresses() {
    const set = (id, addr, fallback) => {
      const el = $(id);
      if (!el) return;
      if (isAddr(addr)) {
        el.innerHTML = "";
        const a = document.createElement("a");
        a.href = explorer.address(addr);
        a.target = "_blank";
        a.rel = "noopener";
        a.textContent = addr;
        el.appendChild(a);
      } else {
        el.textContent = fallback;
      }
    };
    set("hatch-token", deployed.token, "NOT LAUNCHED");
    set("nest-address", deployed.nest, "DEPLOY FIRST");
    set("router-address", deployed.router, "DEPLOY FIRST");
    set("locker-address", deployed.locker, "DEPLOY FIRST");
    set("nvda-address", deployed.nvda, cfg.nvda || "—");

    const trade = $("trade-link");
    if (trade) trade.href = cfg.hatchPonsUrl || cfg.ponsUrl || "#";
  }

  function renderWallet() {
    const btn = $("connect-button");
    if (!btn) return;
    btn.textContent = wallet.account ? `CONNECTED ${short(wallet.account)}` : "CONNECT WALLET";
    btn.classList.toggle("connected", !!wallet.account);
  }

  /* ---------------------------------------------------------------- reads */

  async function refresh() {
    if (!deployed.nest || !deployed.nvda) {
      renderNest(0n);
      $("network-state").textContent = "AWAITING DEPLOYMENT";
      return;
    }

    const [balance, stage, next, bps] = await Promise.all([
      callUint(deployed.nvda, SEL.balanceOf + padAddr(deployed.nest)),
      callUint(deployed.nest, SEL.stage),
      callUint(deployed.nest, SEL.nextThreshold),
      callUint(deployed.nest, SEL.progressBps)
    ]);

    if (balance === null) {
      $("network-state").textContent = "RPC UNREACHABLE";
      renderNest(0n);
      return;
    }

    $("network-state").textContent = `LIVE / CHAIN ${cfg.chainId}`;

    // Crack state: the whole mechanic hangs off these.
    const [burned, bounty, threshold, canCrack] = await Promise.all([
      callUint(deployed.nest, SEL.totalBurned),
      callUint(deployed.nest, SEL.currentBounty),
      callUint(deployed.nest, SEL.crackThreshold),
      callUint(deployed.nest, SEL.crackable)
    ]);
    const burnedEl = $("hatch-locked");
    if (burnedEl) burnedEl.textContent = burned === null ? "—" : `${formatUnits(burned, 0)} HATCH`;
    const bountyEl = $("crack-bounty");
    if (bountyEl) bountyEl.textContent = bounty === null ? "—" : `${formatUnits(bounty)} NVDA`;
    const thrEl = $("crack-threshold");
    if (thrEl) thrEl.textContent = threshold === null ? "—" : `${formatUnits(threshold, 0)} NVDA`;
    const crackBtn = $("crack-button");
    if (crackBtn) {
      const ready = canCrack === 1n;
      crackBtn.disabled = !ready;
      crackBtn.textContent = ready ? "CRACK THE EGG" : "EGG NOT READY";
      crackBtn.title = ready ? "" : "The egg has not reached its crack threshold yet";
    }
    // Prefer the contract's own view functions; they are the source of truth.
    renderNest(balance, stage === null ? undefined : Number(stage), next, bps);

    if (deployed.router) {
      const [pending, claimable] = await Promise.all([
        callUint(deployed.router, SEL.pendingPonsFees),
        callUint(deployed.router, SEL.claimableTotal)
      ]);
      const pendEl = $("pending-fees");
      if (pendEl) pendEl.textContent = pending === null ? "—" : `${formatUnits(pending)} NVDA`;

      const claimBtn = $("claim-button");
      if (claimBtn) {
        const has = claimable !== null && claimable > 0n;
        claimBtn.disabled = !has;
        claimBtn.title = has ? "" : "Nothing to claim right now";
      }
    }
  }

  /* --------------------------------------------------------------- actions */

  async function doFeed() {
    const input = $("feed-amount");
    try {
      if (!deployed.nest || !deployed.nvda) throw new Error("The Nest is not deployed yet.");
      const amount = parseUnits(input.value);
      if (amount <= 0n) throw new Error("Enter an amount above zero.");

      status("Connecting wallet…");
      const account = wallet.account || (await wallet.connect());
      renderWallet();

      const balance = await callUint(deployed.nvda, SEL.balanceOf + padAddr(account));
      if (balance !== null && balance < amount) {
        throw new Error(`Insufficient NVDA. You hold ${formatUnits(balance)}.`);
      }

      const allowance = await callUint(
        deployed.nvda,
        SEL.allowance + padAddr(account) + padAddr(deployed.nest)
      );

      if (allowance === null || allowance < amount) {
        status("1/2 · Approve NVDA for the Nest — confirm in your wallet…");
        const approveTx = await wallet.send(
          deployed.nvda,
          SEL.approve + padAddr(deployed.nest) + padUint(amount)
        );
        status(`1/2 · Approval sent. Waiting for confirmation…`);
        const rec = await wallet.waitForReceipt(approveTx);
        if (rec && rec.status === "0x0") throw new Error("Approval transaction reverted.");
      }

      status("2/2 · Feeding the egg — confirm in your wallet…");
      const feedTx = await wallet.send(deployed.nest, SEL.feed + padUint(amount));
      status(`Feeding… tx ${short(feedTx)}`);
      const rec = await wallet.waitForReceipt(feedTx);
      if (rec && rec.status === "0x0") throw new Error("Feed transaction reverted.");

      status(`Fed ${formatUnits(amount)} NVDA to the Nest.`, "ok");
      input.value = "";
      await refresh();
    } catch (e) {
      status(e && e.message ? e.message : String(e), "error");
    }
  }

  async function doCrack() {
    try {
      if (!deployed.nest) throw new Error("The egg is not deployed yet.");
      // Quote off-chain and allow 5% slippage on the market buy.
      const size = await callUint(deployed.nest, SEL.eggBalance);
      if (size === null || size === 0n) throw new Error("The egg is empty.");
      status("Cracking the egg — this buys HATCH and burns it. Confirm in your wallet…");
      const tx = await wallet.send(deployed.nest, SEL.crackEgg + padUint(1n));
      renderWallet();
      status(`Cracking… tx ${short(tx)}`);
      const rec = await wallet.waitForReceipt(tx);
      if (rec && rec.status === "0x0") throw new Error("Crack transaction reverted.");
      status("Egg cracked. HATCH bought and burned, and your 5% bounty is paid.", "ok");
      await refresh();
    } catch (e) {
      status(e && e.message ? e.message : String(e), "error");
    }
  }

  async function doClaim() {
    try {
      if (!deployed.router) throw new Error("The fee router is not deployed yet.");
      status("Sweeping PONS fees into the egg (70/20/10) — this pays you nothing. Confirm in your wallet…");
      const tx = await wallet.send(deployed.router, SEL.claimAndSplit);
      renderWallet();
      status(`Splitting… tx ${short(tx)}`);
      const rec = await wallet.waitForReceipt(tx);
      if (rec && rec.status === "0x0") throw new Error("Claim transaction reverted.");
      status("Fees swept and split. The egg has been fed.", "ok");
      await refresh();
    } catch (e) {
      status(e && e.message ? e.message : String(e), "error");
    }
  }

  /* ------------------------------------------------------------------ init */

  renderAddresses();
  renderWallet();
  renderNest(0n);

  $("connect-button")?.addEventListener("click", async () => {
    try {
      await wallet.connect();
      renderWallet();
      status("Wallet connected.", "ok");
    } catch (e) {
      status(e && e.message ? e.message : String(e), "error");
    }
  });

  $("feed-button")?.addEventListener("click", doFeed);
  $("claim-button")?.addEventListener("click", doClaim);
  $("crack-button")?.addEventListener("click", doCrack);
  $("feed-amount")?.addEventListener("keydown", (e) => {
    if (e.key === "Enter") doFeed();
  });

  if (!wallet.available()) {
    const btn = $("connect-button");
    if (btn) {
      btn.textContent = "NO WALLET DETECTED";
      btn.disabled = true;
    }
  }

  refresh();
  setInterval(refresh, 15000);
})();
