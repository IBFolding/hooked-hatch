# HOOKED / HATCH architecture

## Product model

HOOKED is the parent experience. Each launch is an independent mechanism with its own token, pair, fee recipient, mechanism vault, art, and page.

HATCH is launch `001`.

## HATCH flow

```text
Trader
  ↓
PONS HATCH/NVDA bonding curve
  ↓ graduation
PONS-managed Uniswap v4 HATCH/NVDA pool
  ↓
PONS base trading fee
  ↓ creator allocation
PONS V2 Fee Escrow
  ↓ claimToken(NVDA)
HatchFeeRouter
  ├─ 70% → HatchNestVault (NVDA permanently locked)
  ├─ 20% → HOOKED treasury
  └─ 10% → team treasury
```

## Why there is no custom HATCH v4 hook

A graduated PONS V2 pool already uses the PONS singleton `PonsV2MemeHook`. A Uniswap v4 pool has a single hook address in its `PoolKey`. HATCH therefore implements its mechanism at the creator-fee-recipient layer instead of trying to attach another hook to the PONS pool.

## HATCH Nest

- Asset: tokenized NVDA on Robinhood Chain.
- Anyone may feed the Nest directly with `feed()`.
- There is intentionally no method that withdraws NVDA from the Nest.
- Evolution is a pure function of `NVDA.balanceOf(nest)`.
- Default milestones: `1, 5, 10, 25, 50, 100, 250 NVDA`.

## HOOKED Treasury

V1 should use a Safe/multisig as the 20% recipient. Do not build a bespoke multisig.

The treasury should simply accumulate assets initially. Do **not** ship a `$HOOKED` buyback contract before a `$HOOKED` token exists. The later token can be designed against actual historical treasury flows rather than promises.

## Team revenue

10% of creator-side fees routes directly to the configured team treasury. This is transparent in the router bytecode and front-end mechanism page.

## Future launch template

Every future HOOKED launch should specify:

```text
id
slug
token / pair
PONS creatorFeeRecipient
mechanism vault
creator fee split
creator tax
mechanism description
site module
art stages
```

The HATCH contracts should not be generalized until launch #002 proves what abstractions are actually shared.

## Trust model

### Immutable
- HATCH Nest asset address
- HATCH Nest withdrawal impossibility for NVDA
- HATCH fee split percentages
- HATCH router destination addresses

### Governed
- router can ask PONS to migrate *future* creator fees after HATCH token is bound
- HOOKED registry live status

### External protocol trust
- PONS contracts and owner powers
- Robinhood Chain tokenized NVDA contract
- RPC/indexer/front-end availability

PONS itself retains protocol-level owner powers, including a timelocked creator-recipient override in current V2 source. Disclose this rather than claiming creator routing is unchangeable at the PONS protocol level.
