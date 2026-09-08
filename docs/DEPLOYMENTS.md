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
| Router governance | `0x000000000000000000000000000000000000dEaD` | **BURNED** |
| HOOKED treasury (20%) | `0xFC41AF875a352b1d9A61bB1ec4f08e3a72d78a63` | EOA |
| Team / ops (10%) | `0xa9E3c85208250d97FED0B8eD1c659e5bEd8442f1` | EOA |

All three are **immutable** in `HatchFeeRouter` and cannot be changed after
deployment.

### Governance is burned — what that means

HATCH ships with **no privileged actor**. Router governance is set to the burn
address, so:

- `bindLaunch()` can never be called. `hatchToken` stays `address(0)` forever.
- `migratePonsRecipient()` can never be called. PONS creator fees can never be
  redirected away from this router, by anyone, including the deployer.
- There is no admin, no upgrade path, no pause, and no rescue function.

The mechanism is entirely unaffected by this:

- `claimAndSplit()` is permissionless — anyone can advance the Nest.
- The 70/20/10 split is immutable `constant` values.
- The Nest has no withdrawal function and never did.

`address(0)` is rejected by the router constructor, which is why the burn uses
`0x...dEaD`. Verified by `test_BurnedGovernance_MechanismStillWorks` and
`test_BurnedGovernance_PrivilegedFunctionsAreDead`.

The `HookedLaunchRegistry` is **not deployed** in this release. It is optional,
the site does not read it, and burning its governance would make it permanently
unusable. Deploy it separately with live governance if launches 002+ need it.

### HATCH token (PONS launch)

| Item | Value |
|---|---|
| HATCH token | `TBD` |
| Bonding curve | `TBD` |
| Launch tx | `TBD` |
| CREATE2 salt | `TBD` |
| Launch config id | `0` (launchConfigCount == 1) |
| `creatorFeeRecipient` | `TBD` (must equal HatchFeeRouter) |
| `creatorTaxBps` | `0` |
| `buybackEnabled` | `false` |
| PONS trade URL | `TBD` |
| Launch fee paid | `TBD` |
| Pair economics at launch | `TBD` (record what `pairTokenEconomics` returned) |
| Launch selector used | `0xf35abbcf` launchToken(TokenParams,uint256,address) |
| Economics digest | `TBD` (read fresh via previewLaunchEconomics at signing) |

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
