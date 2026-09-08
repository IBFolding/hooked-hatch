# HOOKED — HATCH #001

HOOKED is an experimental launch gallery for mechanism-driven meme coins on Robinhood Chain.

Launch #001 is **HATCH**: a PONS token paired with tokenized NVIDIA (NVDA). PONS creator fees are routed to a dedicated `HatchFeeRouter`, which claims NVDA from the PONS V2 fee escrow and splits it:

- **70%** → HATCH Nest (permanently locked NVDA)
- **20%** → HOOKED treasury
- **10%** → team/operations

HATCH launches with **0% additional creator tax**. PONS's own base creator share remains the revenue source.

## Repo

- `web/` — dependency-free HOOKED landing + HATCH page
- `contracts/` — HATCH Nest, fee router, generic HOOKED launch registry, mocks/tests
- `scripts/` — config validation and launch checklist helpers
- `docs/CODEX_HANDOFF.md` — build/deploy handoff
- `docs/LAUNCH_RUNBOOK.md` — exact launch-day sequence
- `docs/ARCHITECTURE.md` — system design and trust model
- `brand/` — logo direction / usage notes

## Canonical Robinhood Chain addresses used

These were current when this package was prepared (2026-09-08). **Re-verify before signing any production transaction.**

- Chain ID: `4663`
- PONS V2 Launch Factory: `0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e`
- PONS V2 Fee Escrow: `0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e`
- NVIDIA Robinhood Token (NVDA): `0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC`
- Uniswap v4 PoolManager: `0x8366a39CC670B4001A1121B8F6A443A643e40951`

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
forge test -vvv
```

## Important

This is production-oriented starter code, **not an audit**. Before mainnet value is routed through the contracts, have the exact deployed bytecode reviewed and test the full PONS escrow claim path on a fork/test environment.
