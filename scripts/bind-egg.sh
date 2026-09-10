#!/usr/bin/env bash
#
# Bind the egg to the launched HATCH token.
#
#   ./scripts/bind-egg.sh
#
# This is a ONE-SHOT call. It can only be sent by the wallet that deployed the
# egg, and it permanently burns that role. Until it lands the egg cannot crack.
#
# Addresses are read from web/config.js, so there is nothing to paste.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BOLD=$'\033[1m'; GRN=$'\033[32m'; RED=$'\033[31m'; YEL=$'\033[33m'; RST=$'\033[0m'
ok(){ echo "  ${GRN}✓${RST} $*"; }
die(){ echo "  ${RED}✗ $*${RST}" >&2; exit 1; }

export PATH="$HOME/.foundry/bin:$PATH"
command -v cast >/dev/null || die "cast not found (install Foundry)"

RPC="${ROBINHOOD_RPC_URL:-https://rpc.mainnet.chain.robinhood.com}"
cfg(){ grep -oE "$1: \"0x[0-9a-fA-F]{40}\"" web/config.js | grep -oE '0x[0-9a-fA-F]{40}'; }

EGG=$(cfg nest); TOKEN=$(cfg hatchToken)
[ -n "$EGG" ]   || die "no egg address in web/config.js"
[ -n "$TOKEN" ] || die "no hatchToken in web/config.js - has the token launched?"

# The curve is recorded on the PONS launch, so read it rather than trusting a paste.
FACTORY=0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e
REC=$(cast call $FACTORY 'getLaunchedToken(address)' "$TOKEN" --rpc-url "$RPC")
CURVE=0x$(echo "${REC:2}" | cut -c89-128 | sed 's/^0*//')
CURVE=$(cast to-check-sum-address "$CURVE")
RECIPIENT=0x$(echo "${REC:2}" | cut -c217-256)
RECIPIENT=$(cast to-check-sum-address "$RECIPIENT")
ROUTER=$(cfg feeRouter)

echo
echo "${BOLD}Binding the egg to HATCH${RST}"
ok "egg    $EGG"
ok "token  $TOKEN"
ok "curve  $CURVE  (read from the PONS launch record)"

# Refuse to bind a launch whose fees do not actually reach our router.
if [ "$(echo "$RECIPIENT" | tr 'A-Z' 'a-z')" != "$(echo "$ROUTER" | tr 'A-Z' 'a-z')" ]; then
  die "launch creatorFeeRecipient is $RECIPIENT, not the router $ROUTER - do not bind"
fi
ok "creatorFeeRecipient = the router"

BOUND=$(cast call "$EGG" 'hatchToken()(address)' --rpc-url "$RPC")
[ "$BOUND" = "0x0000000000000000000000000000000000000000" ] || die "egg already bound to $BOUND"
INIT=$(cast call "$EGG" 'initialiser()(address)' --rpc-url "$RPC")
ok "initialiser $INIT"

echo
read -rsp "Private key for $INIT (hidden, not saved): " KEY; echo
[ -n "$KEY" ] || die "no key given"
[[ "$KEY" == 0x* ]] || KEY="0x$KEY"
FROM=$(cast wallet address --private-key "$KEY") || die "invalid key"
[ "$(echo "$FROM"|tr 'A-Z' 'a-z')" = "$(echo "$INIT"|tr 'A-Z' 'a-z')" ] \
  || die "that key is $FROM but only $INIT can bind the egg"

echo
echo "${YEL}This is irreversible: it binds the egg permanently and burns the role.${RST}"
read -rp "Type BIND to continue: " c
[ "$c" = "BIND" ] || die "aborted"

cast send "$EGG" "initialise(address,address)" "$TOKEN" "$CURVE" \
  --rpc-url "$RPC" --private-key "$KEY" >/tmp/bind-egg.log 2>&1 \
  || { tail -5 /tmp/bind-egg.log; die "transaction failed"; }

TX=$(grep -oE "transactionHash\s+0x[0-9a-f]{64}" /tmp/bind-egg.log | grep -oE "0x[0-9a-f]{64}" | head -1)
echo
ok "sent ${TX:-see /tmp/bind-egg.log}"

NOW=$(cast call "$EGG" 'hatchToken()(address)' --rpc-url "$RPC")
LEFT=$(cast call "$EGG" 'initialiser()(address)' --rpc-url "$RPC")
[ "$(echo "$NOW"|tr 'A-Z' 'a-z')" = "$(echo "$TOKEN"|tr 'A-Z' 'a-z')" ] || die "egg did not bind"
[ "$LEFT" = "0x0000000000000000000000000000000000000000" ] || die "initialiser not burned: $LEFT"

echo
echo "${GRN}${BOLD}THE EGG IS ARMED.${RST}"
echo "  bound to      $NOW"
echo "  initialiser   burned - no privileged actor remains"
echo "  round 1       cracks at $(cast from-wei "$(cast call "$EGG" 'crackThreshold()(uint256)' --rpc-url "$RPC" | awk '{print $1}')") NVDA"
echo
