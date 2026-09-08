# HOOKED contracts

## HATCH contracts

### HatchNestVault
Holds NVDA forever. It has no NVDA withdrawal method. Anyone may call `feed(amount)` after approving NVDA to the vault.

### HatchFeeRouter
Set this address as HATCH's PONS V2 `creatorFeeRecipient` at launch.

`claimAndSplit()`:
1. calls PONS V2 Fee Escrow `claimToken(NVDA)` as the creator recipient;
2. reads all NVDA held by the router;
3. sends 70% Nest / 20% HOOKED treasury / 10% team.

The function is permissionless. No caller reward is charged in V1.

### HookedLaunchRegistry
Optional lightweight registry for adding HATCH and later experiments to HOOKED.

## Mainnet constants

```text
Robinhood Chain ID      4663
PONS V2 Factory         0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e
PONS V2 Fee Escrow      0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e
NVDA quote asset        0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC
```

Re-read PONS live config before launch. PONS pair allowlists/economics are live protocol state and should not be assumed from source.
