# HATCH launch runbook — target: today

## Locked product decisions

- Parent: **HOOKED**
- Launch: **001 / HATCH**
- Token: **HATCH**
- PONS quote asset: **NVDA**
- Additional creator tax: **0%**
- PONS buyback toggle: **OFF for V1**
- Creator fee recipient: **HatchFeeRouter**
- Router split: **70 Nest / 20 HOOKED / 10 team**
- Nest: permanent NVDA accumulation

## Before signing anything

### 1. Run the automated preflight

```bash
node scripts/verify-chain.mjs
```

This asserts every external precondition HATCH depends on and exits non-zero on
failure: chain id 4663, code present at the factory/escrow/NVDA/PoolManager,
`decimals() == 18`, `approvedPairTokens(NVDA) == true`, launch config 0 active,
and that every selector our contracts call is present in the deployed bytecode.
It prints live pair economics for a human to eyeball but never asserts them.

**Re-run it immediately before signing.** It reads mutable mainnet state.

### 2. Run the live fork test suite

```bash
cd contracts
ROBINHOOD_RPC_URL=https://rpc.mainnet.chain.robinhood.com forge test --match-contract PonsFork -vv
```

This deploys the real HATCH contracts against a fork of live chain state and
reads through the production PONS escrow, proving our ABI still matches.

### 3. Confirm operator inputs

Confirm the HOOKED treasury, team and governance addresses. Governance and the
HOOKED treasury should both be a Safe/multisig. These are **immutable** in the
router once deployed - there is no setter.

### 4. Deploy

```bash
cd contracts
PRIVATE_KEY=... GOVERNANCE=... HOOKED_TREASURY=... TEAM_TREASURY=... \
  forge script script/DeployHatch.s.sol:DeployHatch \
  --rpc-url $ROBINHOOD_RPC_URL --broadcast --verify
```

The script runs its own onchain preflight and reverts before spending gas if the
chain, NVDA decimals or PONS approval are not what we expect. Deployment order is
Nest -> Router -> Registry and is enforced by the router's constructor.

Verify all three contracts on the explorer.

## PONS launch values

```text
name                 HATCH
symbol               HATCH
pairToken             0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC  # NVDA
creatorFeeRecipient   <HatchFeeRouter>
creatorTaxBps         0
buybackEnabled        false
logo                  <final HATCH image URI>
description           Feed the egg. Every trade routes creator-fee NVDA into the HATCH Nest. The Nest cannot withdraw NVDA.
website               https://<hooked-domain>/hatch
```

Use PONS `previewLaunchEconomics` immediately before submission and pin the returned economics digest if using the direct factory route.

## Immediately after launch

1. Record HATCH token and curve addresses.
2. Call `HatchFeeRouter.bindLaunch(HATCH_TOKEN)` from governance.
3. Add HATCH to `HookedLaunchRegistry` if registry is deployed.
4. Update `web/config.js` with:
   - `hatchToken`
   - `hatchPonsUrl`
   - `nest`
   - `feeRouter`
   Then run `node scripts/validate-config.mjs`.
5. Redeploy site.
6. Execute a tiny real trade only after PONS launch-window snipe tax has decayed.
7. Wait for/trigger a normal PONS fee sweep.
8. Confirm PONS escrow shows NVDA pending for the router.
9. Call `claimAndSplit()`.
10. Verify exact 70/20/10 token transfers onchain.
11. Verify the website Nest balance increments.
12. Re-run the preflight with the deployed addresses included:
    ```bash
    NEST_ADDRESS=0x... ROUTER_ADDRESS=0x... node scripts/verify-chain.mjs
    ```
13. Record every address and tx hash in `docs/DEPLOYMENTS.md`.

## Ship gate

Do not announce the mechanism as live until all five are true:

- [ ] PONS pair is HATCH/NVDA
- [ ] creator recipient equals deployed router
- [ ] Nest has no NVDA withdrawal route
- [ ] a real fee claim split was tested onchain
- [ ] site reads actual Nest NVDA balance
