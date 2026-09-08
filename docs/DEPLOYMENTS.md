# HOOKED / HATCH deployments

Single source of truth for deployed addresses and the transactions that created
them. Fill this in as part of the launch, not afterwards.

Every address below must also be pasted into `web/config.js` and verified on the
explorer before the mechanism is announced as live.

---

## Robinhood Chain (chain id 4663)

Explorer: https://robinhoodchain.blockscout.com

### External protocol (not ours — verified onchain 2026-09-08)

| Contract | Address | Verified |
|---|---|---|
| PONS V2 Launch Factory | `0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e` | code present, 24177B |
| PONS V2 Fee Escrow | `0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e` | code present, 1932B |
| NVDA (quote asset) | `0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC` | symbol NVDA, decimals 18 |
| Uniswap v4 PoolManager | `0x8366a39CC670B4001A1121B8F6A443A643e40951` | code present, 24009B |

### HATCH contracts

| Contract | Address | Deploy tx | Explorer verified |
|---|---|---|---|
| HatchNestVault | `TBD` | `TBD` | ☐ |
| HatchFeeRouter | `TBD` | `TBD` | ☐ |
| HookedLaunchRegistry | `TBD` | `TBD` | ☐ |

### Operator addresses

| Role | Address | Type |
|---|---|---|
| Governance | `TBD` | Safe (required) |
| HOOKED treasury | `TBD` | Safe (required) |
| Team / ops | `TBD` | |

Governance, HOOKED treasury and team are **immutable** in `HatchFeeRouter`.
They cannot be changed after deployment. Only the PONS creator-fee recipient can
be migrated, via `migratePonsRecipient`, and that never touches Nest principal.

### HATCH token (PONS launch)

| Item | Value |
|---|---|
| HATCH token | `TBD` |
| Bonding curve | `TBD` |
| Launch tx | `TBD` |
| CREATE2 salt | `TBD` |
| Launch config id | `TBD` |
| `creatorFeeRecipient` | `TBD` (must equal HatchFeeRouter) |
| `creatorTaxBps` | `0` |
| `buybackEnabled` | `false` |
| PONS trade URL | `TBD` |
| Launch fee paid | `TBD` |
| Pair economics at launch | `TBD` (record what `pairTokenEconomics` returned) |

### Post-launch confirmations

| Check | Tx / evidence | Done |
|---|---|---|
| `bindLaunch(HATCH)` called from governance | `TBD` | ☐ |
| Registered in HookedLaunchRegistry | `TBD` | ☐ |
| First real `claimAndSplit()` | `TBD` | ☐ |
| Split observed exactly 70/20/10 | `TBD` | ☐ |
| Router retained zero dust | `TBD` | ☐ |
| Site reads live Nest balance | `TBD` | ☐ |

---

## Nest stage thresholds

Set at deployment and immutable. Must match `web/config.js` `stageThresholds`.

| Stage | Threshold (NVDA) | Name |
|---|---|---|
| 0 | 0 | DORMANT |
| 1 | 1 | HAIRLINE |
| 2 | 5 | CRACKED |
| 3 | 10 | MOVEMENT |
| 4 | 25 | EYE CONTACT |
| 5 | 50 | CONTAINMENT FAILING |
| 6 | 100 | HATCHED |
| 7 | 250 | ??? |
