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

1. Re-read PONS V2 factory live config:
   - chain ID is 4663
   - public launch gate is open / launcher is allowed
   - NVDA is currently approved by PONS
   - read current launch fee
   - read NVDA graduation threshold/economics
   - read current base fee policy
2. Verify NVDA contract symbol/decimals onchain.
3. Confirm HOOKED treasury and team addresses. Prefer Safe/multisig for HOOKED treasury.
4. Deploy `HatchNestVault`.
5. Deploy `HatchFeeRouter` pointing at the Nest and treasury addresses.
6. Verify both contracts on the explorer.

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
   - HATCH token
   - PONS HATCH URL
   - Nest address
   - Fee Router address
5. Redeploy site.
6. Execute a tiny real trade only after PONS launch-window snipe tax has decayed.
7. Wait for/trigger a normal PONS fee sweep.
8. Confirm PONS escrow shows NVDA pending for the router.
9. Call `claimAndSplit()`.
10. Verify exact 70/20/10 token transfers onchain.
11. Verify the website Nest balance increments.

## Ship gate

Do not announce the mechanism as live until all five are true:

- [ ] PONS pair is HATCH/NVDA
- [ ] creator recipient equals deployed router
- [ ] Nest has no NVDA withdrawal route
- [ ] a real fee claim split was tested onchain
- [ ] site reads actual Nest NVDA balance
