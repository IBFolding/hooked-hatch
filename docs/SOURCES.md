# Current protocol sources — checked 2026-09-08

Re-check before production signing; protocol state can change.

## PONS

Official contracts repository:
https://github.com/ponsdotdev/ponsfamily

Key source facts used by this build:
- PONS V2 launches on a bonding curve and graduate to a locked Uniswap v4 pool governed by the shared PONS V2 meme hook.
- The launch factory accepts an arbitrary `creatorFeeRecipient` in `TokenParams`.
- Creator fees are credited into `IPonsV2FeeEscrow` in the quote asset.
- `IPonsV2FeeEscrow.claimToken(token)` pays the caller's credited ERC-20 balance.
- The current creator fee recipient can migrate future fees through the factory.
- PONS pair token approvals and per-pair economics are live state and must be queried before launch.

Official source files:
- `contractsV2/src/v2/PonsV2LaunchFactory.sol`
- `contractsV2/src/v2/PonsV2BondingCurve.sol`
- `contractsV2/src/v2/interfaces/ILaunchpadV2.sol`

## Current PONS economics / stock pair behavior

Dibs documentation mirrors PONS V2 launch economics and live quote-pair behavior:
https://www.dibs.family/docs/fees
https://www.dibs.family/docs/pairs

At the time checked:
- PONS trade fee: 1%
- creator fee recipient: 70% of that base fee
- creator tax: optional 0-10%, entirely to creator recipient
- stock-paired creator fees are paid in the paired stock token
- NVDA is a supported example pair

HATCH intentionally sets additional creator tax to 0%.

## Robinhood Chain NVDA

Tokenized NVIDIA quote token used for the PONS pair:
`0xd0601CE157Db5BDc3162BbaC2a2C8aF5320D9EEC`

Observed as:
- symbol: NVDA
- decimals: 18
- chain: Robinhood Chain / 4663

Explorer/reference:
https://robinscanner.com/tokens/0xd0601ce157db5bdc3162bbac2a2c8af5320d9eec

Important: this package refers to it as **tokenized NVDA / NVIDIA Robinhood Token**, not as an xStock. Do not conflate Robinhood's tokenized equities on Robinhood Chain with the separate xStocks product family.
