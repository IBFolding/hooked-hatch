(() => {
  const cfg = window.HOOKED_CONFIG || {};
  if (document.body.dataset.page !== "hatch") return;

  const $ = (id) => document.getElementById(id);
  const labels = ["DORMANT", "HAIRLINE", "CRACKED", "MOVEMENT", "EYE CONTACT", "CONTAINMENT FAILING", "HATCHED", "???"];
  const thresholds = cfg.stageThresholds || [1,5,10,25,50,100,250];

  $("hatch-token").textContent = cfg.hatchToken || "NOT LAUNCHED";
  $("nest-address").textContent = cfg.nest || "DEPLOY FIRST";
  $("router-address").textContent = cfg.feeRouter || "DEPLOY FIRST";
  $("trade-link").href = cfg.hatchPonsUrl || cfg.ponsUrl || "#";

  function apply(balance) {
    let stage = 0;
    while (stage < thresholds.length && balance >= thresholds[stage]) stage++;
    const low = stage === 0 ? 0 : thresholds[stage - 1];
    const high = stage >= thresholds.length ? low : thresholds[stage];
    const p = stage >= thresholds.length ? 100 : Math.max(0, Math.min(100, ((balance - low) / (high - low)) * 100));
    $("nest-balance").textContent = `${balance.toFixed(4)} NVDA`;
    $("stage-label").textContent = labels[stage];
    $("stage-number").textContent = `STAGE ${stage} / 7`;
    $("next-threshold").textContent = stage >= 7 ? "FINAL THRESHOLD CLEARED" : `NEXT: ${thresholds[stage]} NVDA`;
    $("progress-fill").style.width = `${p}%`;
    $("egg").className = `egg stage-${stage}`;
  }

  async function rpc(method, params) {
    const res = await fetch(cfg.rpcUrl, {method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({jsonrpc:"2.0",id:1,method,params})});
    const json = await res.json();
    if (json.error) throw new Error(json.error.message || "RPC error");
    return json.result;
  }

  async function loadBalance() {
    if (!cfg.nest || !cfg.nvda) { apply(0); return; }
    try {
      // balanceOf(address) = 0x70a08231 + left-padded address
      const data = "0x70a08231" + cfg.nest.toLowerCase().replace("0x","").padStart(64,"0");
      const out = await rpc("eth_call", [{to:cfg.nvda,data}, "latest"]);
      const raw = BigInt(out);
      const whole = Number(raw / 10n**14n) / 10000; // display 4 decimals without float BigInt overflow for realistic balances
      apply(whole);
      $("network-state").textContent = "LIVE / CHAIN 4663";
    } catch (e) {
      console.error(e);
      $("network-state").textContent = "RPC OFFLINE / DEMO";
      apply(0);
    }
  }

  $("feed-button").addEventListener("click", () => {
    alert("Direct feed will be enabled after the Nest address is deployed. It calls HatchNestVault.feed(amount) after NVDA approval.");
  });

  loadBalance();
  setInterval(loadBalance, 15000);
})();
