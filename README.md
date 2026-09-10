# HOOKED — HATCH #001

HOOKED is an experimental launch gallery for mechanism-driven meme coins on Robinhood Chain.

Launch #001 is **HATCH**: a PONS token paired with tokenized NVIDIA (NVDA). PONS creator fees are routed to a dedicated `HatchFeeRouter`, which claims NVDA from the PONS V2 fee escrow and splits it:

- **70%** → the egg
- **20%** → HOOKED treasury
- **10%** → team/operations

The egg fills with NVDA in public. When it reaches the crack threshold, **anyone**
can crack it: the egg spends every NVDA inside buying HATCH on the open market and
**burns** it, and the caller keeps **5%** as a bounty. Then the egg refills and it
happens again.

Nothing is paid to holders. The egg has no withdrawal function and no admin — NVDA
can only ever leave through a crack, which can only buy-and-burn.

HATCH launches with **0% additional creator tax**. PONS's own base creator share remains the revenue source.

## Status

| Workstream | State |
|---|---|
| Contracts compile + unit/fuzz tests | done — 23 tests, 100k fuzz runs |
| Live-chain integration checks | done — 9 fork tests, 16 preflight assertions |
| Deploy script | done — broadcastable, with onchain preflight |
| Frontend wallet + live reads | done — verified end-to-end on a fork |
| Brand assets | house marks generated; awaiting final artwork |
| Deployed to mainnet | **not yet — requires operator keys** |
| HATCH launched on PONS | **not yet** |

See `docs/DEPLOYMENTS.md` for the address record and `docs/LAUNCH_RUNBOOK.md`
for the launch-day sequence.

## Repo

- `web/` — dependency-free HOOKED landing + HATCH page
- `brand/generate-assets.py` — generates every logo/social asset
- `contracts/` — HATCH Nest, fee router, generic HOOKED launch registry, mocks/tests
- `scripts/` — config validation and launch checklist helpers
- `docs/CODEX_HANDOFF.md` — build/deploy handoff
- `docs/LAUNCH_RUNBOOK.md` — exact launch-day sequence
- `docs/ARCHITECTURE.md` — system design and trust model
- `brand/` — logo direction / usage notes

## Canonical Robinhood Chain addresses used

Verified onchain 2026-09-08. **Re-verify before signing any production transaction**
with `node scripts/verify-chain.mjs`.

- Chain ID: `4663`
- PONS V2 Launch Factory: `0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e`
- PONS V2 Fee Escrow: `0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e`
- NVIDIA Robinhood Token (NVDA): `0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC`
- Uniswap v4 PoolManager: `0x8366a39CC670B4001A1121B8F6A443A643e40951`
- Explorer: https://robinhoodchain.blockscout.com

## Verify the chain before launching

```bash
node scripts/verify-chain.mjs
```

Asserts chain id, code presence, NVDA decimals, PONS approval of NVDA, active
launch config, and that every selector our contracts call exists in the deployed
bytecode. Exits non-zero on failure. Prints live pair economics without asserting
them — those are mutable protocol state and must never be hard-coded.

## Preview the site

```bash
cd web
python3 -m http.server 4173
# open http://localhost:4173
```

## Contracts

The contracts intentionally avoid a dependency-heavy custom Uniswap hook. PONS already owns the graduated pool hook. HATCH's custom behavior lives in its creator-fee recipient and Nest contracts.

With Foundry installed:

```bash
cd contracts
forge test                                     # 23 unit + fuzz tests
FOUNDRY_PROFILE=deep forge test --match-test testFuzz   # 20k runs each
ROBINHOOD_RPC_URL=https://rpc.mainnet.chain.robinhood.com \
  forge test --match-contract PonsFork -vv     # live chain integration
```

The fork suite deploys the real contracts against live Robinhood Chain state and
reads through the production PONS escrow, so it fails loudly if the external ABI
ever drifts.

## Important

This is production-oriented starter code, **not an audit**. Before mainnet value is routed through the contracts, have the exact deployed bytecode reviewed and test the full PONS escrow claim path on a fork/test environment.
