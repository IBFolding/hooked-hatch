// HOOKED / HATCH runtime configuration.
// Addresses are filled in at deploy time. Everything here is public, read-only data.
window.HOOKED_CONFIG = {
  chainId: 4663,
  chainName: "Robinhood Chain",

  // Public RPC. Override with a dedicated provider endpoint for production traffic.
  rpcUrl: "https://rpc.mainnet.chain.robinhood.com",
  // Optional fallbacks, tried in order if the primary fails.
  rpcFallbacks: [],

  // Verified 2026-09-08: explorer.mainnet.chain.robinhood.com redirects here.
  explorerUrl: "https://robinhoodchain.blockscout.com",

  ponsUrl: "https://www.ponsfamily.com/",

  // --- Deployed HATCH addresses (fill in after deployment) ---
  hatchToken: "",
  hatchPonsUrl: "",
  nest: "0xebb9Bd45d87FeC54c4ee34445b288816603A43e5",
  feeRouter: "0x8377292Fa54d0C53C590DAeCaCD719365E425e82",

  // --- Canonical Robinhood Chain addresses (verified onchain 2026-09-08) ---
  nvda: "0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC",
  ponsFactory: "0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e",
  ponsEscrow: "0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e",

  // Nest stage milestones in whole NVDA. Must match HatchNestVault's constructor thresholds.
  stageThresholds: [1, 5, 10, 25, 50, 100, 250]
};
