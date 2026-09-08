#!/usr/bin/env node
/**
 * HOOKED pre-launch onchain verification.
 *
 * Re-run this immediately before signing anything on launch day. It reads LIVE
 * mutable protocol state and asserts only what HATCH actually depends on.
 * It never hard-codes PONS economics — it prints them for a human to approve.
 *
 *   node scripts/verify-chain.mjs
 *   RPC_URL=https://... node scripts/verify-chain.mjs
 */

const RPC = process.env.RPC_URL || "https://rpc.mainnet.chain.robinhood.com";

const ADDR = {
  ponsFactory: "0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e",
  ponsEscrow: "0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e",
  nvda: "0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC",
  poolManager: "0x8366a39CC670B4001A1121B8F6A443A643e40951"
};
const EXPECTED_CHAIN_ID = 4663;

// Selectors used by the HATCH contracts and site.
const SEL = {
  decimals: "0x313ce567",
  symbol: "0x95d89b41",
  launchFee: "0xcf3cf573",
  approvedPairTokens: "0x9831705e",
  pairTokenEconomics: "0x31082134",
  getLaunchConfig: "0x1cad862d",
  balanceOfToken: "0xf59e38b7",
  // must exist in factory bytecode for router migration to be possible
  transferCreatorFeeRecipient: "0x2931861b",
  previewLaunchEconomics: "0xf718b78c",
  claimToken1: "0x32f289cf",
  claimToken2: "0x1698755f"
};

let id = 0;
async function rpc(method, params = []) {
  const res = await fetch(RPC, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params })
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const json = await res.json();
  if (json.error) throw new Error(json.error.message);
  return json.result;
}

const call = (to, data) => rpc("eth_call", [{ to, data }, "latest"]);
const pad = (a) => a.toLowerCase().replace(/^0x/, "").padStart(64, "0");
const words = (hex) => {
  const h = hex.replace(/^0x/, "");
  return Array.from({ length: Math.ceil(h.length / 64) }, (_, i) => BigInt("0x" + h.slice(i * 64, i * 64 + 64)));
};
const fmt = (v, d = 18) => {
  const base = 10n ** BigInt(d);
  return `${v / base}.${(v % base).toString().padStart(d, "0").slice(0, 6)}`;
};

let pass = 0, fail = 0, warn = 0;
const ok = (m, extra = "") => { pass++; console.log(`  \x1b[32mPASS\x1b[0m  ${m}${extra ? "  " + extra : ""}`); };
const bad = (m, extra = "") => { fail++; console.log(`  \x1b[31mFAIL\x1b[0m  ${m}${extra ? "  " + extra : ""}`); };
const info = (m, extra = "") => { console.log(`  \x1b[36mINFO\x1b[0m  ${m}${extra ? "  " + extra : ""}`); };
const wrn = (m) => { warn++; console.log(`  \x1b[33mWARN\x1b[0m  ${m}`); };

function assert(cond, msg, extra) { cond ? ok(msg, extra) : bad(msg, extra); return cond; }

async function main() {
  console.log(`\nHOOKED / HATCH pre-launch verification`);
  console.log(`RPC: ${RPC}`);
  console.log(`Time: ${new Date().toISOString()}\n`);

  console.log("CHAIN");
  const chainId = Number(BigInt(await rpc("eth_chainId")));
  assert(chainId === EXPECTED_CHAIN_ID, `chain id is ${EXPECTED_CHAIN_ID}`, `got ${chainId}`);
  const head = Number(BigInt(await rpc("eth_blockNumber")));
  info("block height", String(head));

  console.log("\nCODE PRESENCE");
  const code = {};
  for (const [name, addr] of Object.entries(ADDR)) {
    code[name] = await rpc("eth_getCode", [addr, "latest"]);
    const size = (code[name].length - 2) / 2;
    assert(size > 0, `code deployed at ${name}`, `${addr} (${size}B)`);
  }

  console.log("\nNVDA QUOTE ASSET");
  const dec = Number(BigInt(await call(ADDR.nvda, SEL.decimals)));
  assert(dec === 18, "NVDA decimals == 18", `got ${dec}`);
  const symRaw = await call(ADDR.nvda, SEL.symbol);
  const sym = Buffer.from(symRaw.slice(2 + 128, 2 + 128 + 8), "hex").toString("utf8").replace(/\0/g, "");
  assert(sym === "NVDA", "NVDA symbol", sym);

  console.log("\nPONS FACTORY");
  const approved = BigInt(await call(ADDR.ponsFactory, SEL.approvedPairTokens + pad(ADDR.nvda)));
  assert(approved === 1n, "PONS approves NVDA as a pair token");

  const fee = BigInt(await call(ADDR.ponsFactory, SEL.launchFee));
  info("launchFee (native)", `${fmt(fee)} ETH`);
  if (fee > 10n ** 16n) wrn("launch fee is unusually high - confirm before launching");

  const econ = words(await call(ADDR.ponsFactory, SEL.pairTokenEconomics + pad(ADDR.nvda)));
  assert(econ.length >= 3, "pairTokenEconomics is readable");
  info("pair economics", econ.slice(0, 2).map((v) => fmt(v)).join("  |  ") + `  | decimals ${econ[2]}`);
  wrn("pair economics are LIVE state - never hard-code these; read at launch time");

  const cfg0 = words(await call(ADDR.ponsFactory, SEL.getLaunchConfig + BigInt(0).toString(16).padStart(64, "0")));
  assert(cfg0[cfg0.length - 1] === 1n, "launch config 0 is active");
  info("config0 total supply", fmt(cfg0[0]));

  console.log("\nREQUIRED SELECTORS IN DEPLOYED BYTECODE");
  const need = [
    ["ponsFactory", "transferCreatorFeeRecipient(address,address)", SEL.transferCreatorFeeRecipient],
    ["ponsFactory", "previewLaunchEconomics(uint256,address)", SEL.previewLaunchEconomics],
    ["ponsEscrow", "claimToken(address)", SEL.claimToken1],
    ["ponsEscrow", "claimToken(address,uint256)", SEL.claimToken2],
    ["ponsEscrow", "balanceOfToken(address,address)", SEL.balanceOfToken]
  ];
  for (const [target, sig, sel] of need) {
    const present = code[target].toLowerCase().includes(sel.slice(2).toLowerCase());
    assert(present, `${target}: ${sig}`);
  }

  console.log("\nESCROW LIVE READ");
  const probe = await call(ADDR.ponsEscrow, SEL.balanceOfToken + pad("0x0000000000000000000000000000000000000001") + pad(ADDR.nvda));
  assert(BigInt(probe) === 0n, "escrow balanceOfToken responds with the expected ABI shape");

  // If HATCH is already deployed, verify it too.
  const nest = process.env.NEST_ADDRESS;
  const router = process.env.ROUTER_ADDRESS;
  if (nest || router) {
    console.log("\nDEPLOYED HATCH CONTRACTS");
    if (nest) {
      const bal = BigInt(await call(ADDR.nvda, "0x70a08231" + pad(nest)));
      const stage = BigInt(await call(nest, "0xc040e6b8"));
      ok("nest reachable", `balance ${fmt(bal)} NVDA / stage ${stage}`);
    }
    if (router) {
      const pending = BigInt(await call(router, "0x11972416"));
      ok("router reachable", `pending fees ${fmt(pending)} NVDA`);
    }
  } else {
    info("HATCH not deployed yet", "set NEST_ADDRESS / ROUTER_ADDRESS to include it");
  }

  console.log(`\n${"-".repeat(60)}`);
  console.log(`  ${pass} passed, ${fail} failed, ${warn} warnings`);
  console.log(`${"-".repeat(60)}\n`);
  if (fail > 0) {
    console.error("VERIFICATION FAILED - do not launch until resolved.\n");
    process.exit(1);
  }
  console.log("All external protocol preconditions hold. Re-run immediately before signing.\n");
}

main().catch((e) => { console.error("\nverification error:", e.message, "\n"); process.exit(1); });
