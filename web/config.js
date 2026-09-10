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
  // The egg. Named `nest` for backwards compatibility with the page markup.
  nest: "0xcDD7B542D9a768F15159889006e29Da11CDc9484",
  feeRouter: "0x37D6FB5ced95BB9372a43Ce5BbeA45FEAD20CfA1",

  // --- Canonical Robinhood Chain addresses (verified onchain 2026-09-08) ---
  nvda: "0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC",
  ponsFactory: "0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e",
  ponsEscrow: "0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e",

  // Stage ramp is derived on-chain as a percentage of the CURRENT round's
  // threshold, so these are only a fallback before the egg is deployed.
  stageThresholds: [1, 5, 10, 20, 30, 40, 50]
};
