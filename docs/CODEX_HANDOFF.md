# CODEX HANDOFF — HOOKED + HATCH 001

## Mission

Take this repo from production-oriented starter to a verified, deployable HOOKED/HATCH release on Robinhood Chain **without redesigning the mechanism**.

HATCH must be launchable today if external protocol state allows it.

## Non-negotiable product decisions

1. Site name: **HOOKED**.
2. HOOKED landing page is a gallery of mechanism-driven launches.
3. Launch #001 is **HATCH**.
4. HATCH launches through **PONS V2**.
5. HATCH's PONS quote asset is **tokenized NVDA**.
6. HATCH launches with **0% additional creator tax**.
7. PONS V2's existing hook remains the pool hook. **Do not attempt a second v4 hook on the graduated PONS pool.**
8. HATCH mechanism is creator-fee routing:
   - 70% Nest
   - 20% HOOKED treasury
   - 10% team
9. The Nest's NVDA is permanent. Do not add an NVDA withdrawal/admin rescue function.
10. HOOKED does **not** launch a parent token in this release. It accumulates treasury assets for a possible later token.

## Current canonical addresses to verify onchain

```text
Chain ID               4663
PONS V2 Launch Factory 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e
PONS V2 Fee Escrow     0xd3AFEB2a57f70ef218Aa82451c51B2fb0416Ac9e
NVDA quote token       0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC
Uniswap v4 PoolManager 0x8366a39cc670b4001a1121b8f6a443a643e40951
```

Do not trust the README alone. Read deployed state and verified bytecode/source immediately before launch.

## Workstream A — contracts

### 1. Compile and test
- install/use Foundry
- compile Solidity 0.8.26
- run unit tests
- add fuzz tests for arbitrary fee amounts, especially dust values
- assert `nest + hooked + team == total` for all claim amounts
- assert router never retains quote-token dust after a successful split

### 2. Fork/integration tests
Against Robinhood Chain mainnet fork:
- check code exists at factory, escrow, NVDA addresses
- confirm NVDA `decimals() == 18`
- confirm PONS factory currently approves NVDA
- query `pairTokenEconomics(NVDA)` and do not hard-code its live threshold
- query current launch fee and launch config
- verify `IPonsV2FeeEscrow.claimToken(NVDA)` transfers the caller's credited balance to caller

### 3. Deployment
Use a governance Safe address supplied by operator.
Deploy in order:
1. HatchNestVault
2. HatchFeeRouter
3. Optional HookedLaunchRegistry

Verify source on the chain explorer.

### 4. Security review
Focus on:
- reentrancy through quote token / escrow
- non-standard ERC20 return values
- fee rounding
- accidental direct NVDA transfers to router
- permanent Nest invariants
- governance migration path
- inability to change split destinations or percentages after router deployment

Do not introduce upgradeable proxies for V1.

## Workstream B — PONS launch integration

Read the current official PONS V2 source / ABI rather than copying an old ABI.

Required launch params:

```text
name: HATCH
symbol: HATCH
creatorFeeRecipient: <deployed HatchFeeRouter>
creatorTaxBps: 0
buybackEnabled: false
pairToken: NVDA
```

Before launch:
- call/read `launchFee()`
- ensure `approvedPairTokens(NVDA) == true`
- read launch config(s)
- call `previewLaunchEconomics(configId, NVDA)`
- use its economics digest as `expectedEconomics`
- generate a random unused CREATE2 salt
- confirm metadata length constraints

After launch:
- capture `TokenLaunched`
- persist token + curve addresses
- call router `bindLaunch(token)` from governance

Do not buy in the first seconds as a normal wallet; PONS has launch-window anti-snipe behavior. If a dev buy is desired, use PONS's sanctioned launch-and-buy path and verify current contracts first.

## Workstream C — frontend

The current static frontend is intentionally dependency-free so it can go live immediately.

Make these production changes without changing art direction:
- replace config placeholders with deployed addresses
- use a robust RPC provider through env/config rather than exposing a fragile single endpoint if a better one is available
- add wallet connect only if it can be completed cleanly today
- `FEED DIRECTLY` should perform:
  1. NVDA approve Nest for selected amount
  2. `HatchNestVault.feed(amount)`
- add `CLAIM & FEED` button calling router `claimAndSplit()`; permissionless
- show pending PONS creator fees from router `pendingPonsFees()`
- show Nest balance, stage, next threshold, progress
- link each contract to a Robinhood Chain explorer
- add visible disclaimer that tokenized NVDA is tokenized equity exposure and HATCH itself is experimental

If wallet integration jeopardizes ship time, keep the read-only page and link trading to PONS. Do not block release on a custom swap widget.

## Workstream D — branding

Keep HOOKED master brand stark, black/dirty white + acid green, editorial/industrial, not glossy crypto-gradient style.

HATCH should feel like a contained biological/AI experiment:
- pale egg
- subtle NVIDIA/compute visual language without copying NVIDIA logo/trade dress
- cracks become increasingly disturbing by stage
- final stage remains unrevealed at launch

Required exports:
- HOOKED logo: SVG/PNG, dark and light variants, square icon
- HATCH logo: SVG/PNG, square PFP, transparent mark
- HATCH stage images 0-7, 1:1
- X banner 1500×500
- social share 1200×630

## Workstream E — deployment

Deploy static web to Vercel or equivalent.
Routes:
- `/` HOOKED
- `/hatch` HATCH

Set production domain later without code changes.

## Acceptance criteria

Release is complete when:

- [ ] contracts compile
- [ ] unit + fuzz tests pass
- [ ] mainnet-fork PONS interface checks pass
- [ ] Nest + router deployed and verified
- [ ] HATCH launched on PONS against live-approved NVDA
- [ ] creatorFeeRecipient is router
- [ ] 0% creator tax confirmed from PONS launch record
- [ ] router bound to HATCH token
- [ ] one real fee claim produces exact 70/20/10 split
- [ ] Nest balance is live on `/hatch`
- [ ] PONS trade link works
- [ ] HOOKED homepage lists HATCH as live and future experiments as classified
- [ ] all deployment addresses + tx hashes written into `DEPLOYMENTS.md`

## Do not do

- do not deploy `$HOOKED`
- do not add a custom Uniswap v4 hook to the existing PONS pool
- do not add Nest withdrawals
- do not turn on creator tax in V1
- do not turn on PONS buyback for HATCH V1
- do not invent or hard-code live PONS pair economics
- do not market NVDA tokens as direct NVIDIA shareholder ownership
