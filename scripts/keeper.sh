#!/usr/bin/env bash
#
# HATCH keeper — sweep fees into the egg, and crack it when it is full.
#
#   ./scripts/keeper.sh
#
# Both actions are permissionless: ANY wallet can call them. Sweeping pays the
# caller nothing (you just pay gas). Cracking pays the caller 5% of the egg.
# Addresses are read from web/config.js, so there is nothing to paste.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BOLD=$'\033[1m'; DIM=$'\033[2m'; GRN=$'\033[32m'; RED=$'\033[31m'; YEL=$'\033[33m'; RST=$'\033[0m'
ok(){ echo "  ${GRN}✓${RST} $*"; }
inf(){ echo "  ${DIM}·${RST} $*"; }
die(){ echo "  ${RED}✗ $*${RST}" >&2; exit 1; }

export PATH="$HOME/.foundry/bin:$PATH"
command -v cast >/dev/null || die "cast not found (install Foundry)"
RPC="${ROBINHOOD_RPC_URL:-https://rpc.mainnet.chain.robinhood.com}"

cfg(){ grep -oE "$1: \"0x[0-9a-fA-F]{40}\"" web/config.js | grep -oE '0x[0-9a-fA-F]{40}'; }
EGG=$(cfg nest); ROUTER=$(cfg feeRouter); TOKEN=$(cfg hatchToken)
[ -n "$EGG" ] && [ -n "$ROUTER" ] || die "addresses missing from web/config.js"
call(){ cast call "$1" "$2" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}'; }
wei(){ cast from-wei "${1:-0}"; }

echo
echo "${BOLD}HATCH keeper${RST}"
PENDING=$(call "$ROUTER" 'pendingPonsFees()(uint256)')
EGGBAL=$(call "$EGG"    'eggBalance()(uint256)')
THRESH=$(call "$EGG"    'crackThreshold()(uint256)')
ROUND=$(call  "$EGG"    'round()(uint256)')
BOUNTY=$(call "$EGG"    'currentBounty()(uint256)')
CRACKABLE=$(cast call "$EGG" 'crackable()(bool)' --rpc-url "$RPC" 2>/dev/null)
BURNED=$(call "$EGG"    'totalBurned()(uint256)')

inf "round $ROUND, cracks at $(wei "$THRESH") NVDA"
inf "egg        $(wei "$EGGBAL") NVDA"
inf "in escrow  $(wei "$PENDING") NVDA (unswept)"
inf "burned     $(wei "$BURNED") HATCH so far"

DO_SWEEP=0; DO_CRACK=0
[ "${PENDING:-0}" != "0" ] && DO_SWEEP=1
[ "$CRACKABLE" = "true" ] && DO_CRACK=1

if [ "$DO_SWEEP" = "0" ] && [ "$DO_CRACK" = "0" ]; then
  echo
  echo "  Nothing to do. No unswept fees, and the egg needs"
  echo "  $(wei $((THRESH - EGGBAL))) more NVDA before it can crack."
  echo
  exit 0
fi

echo
[ "$DO_SWEEP" = "1" ] && echo "  ${BOLD}SWEEP${RST}  $(wei "$PENDING") NVDA from escrow into the split (pays you nothing)"
[ "$DO_CRACK" = "1" ] && echo "  ${BOLD}CRACK${RST}  the egg is full — you would earn $(wei "$BOUNTY") NVDA"
echo
read -rsp "Private key of the wallet to send from (hidden, not saved): " KEY; echo
[ -n "$KEY" ] || die "no key given"
[[ "$KEY" == 0x* ]] || KEY="0x$KEY"
FROM=$(cast wallet address --private-key "$KEY") || die "invalid key"
BAL=$(cast balance "$FROM" --rpc-url "$RPC")
ok "sending from $FROM ($(wei "$BAL") ETH)"
[ "$BAL" = "0" ] && die "that wallet has no ETH for gas"

if [ "$DO_SWEEP" = "1" ]; then
  echo
  echo "  sweeping…"
  cast send "$ROUTER" "claimAndSplit()" --rpc-url "$RPC" --private-key "$KEY" >/tmp/keeper.log 2>&1 \
    || { tail -4 /tmp/keeper.log; die "sweep failed"; }
  ok "swept — egg now $(wei "$(call "$EGG" 'eggBalance()(uint256)')") NVDA"
  CRACKABLE=$(cast call "$EGG" 'crackable()(bool)' --rpc-url "$RPC" 2>/dev/null)
  [ "$CRACKABLE" = "true" ] && DO_CRACK=1
fi

if [ "$DO_CRACK" = "1" ]; then
  CURVE=$(call "$EGG" 'curve()(address)')
  GRAD=$(cast call "$CURVE" 'graduated()(bool)' --rpc-url "$RPC" 2>/dev/null)
  SIZE=$(call "$EGG" 'eggBalance()(uint256)')
  SPEND=$((SIZE - SIZE * 500 / 10000))

  # Quote the buy so we never hand the trade to a sandwicher with minOut = 1.
  MINOUT=1
  if [ "$GRAD" = "false" ]; then
    RES=$(cast call "$CURVE" 'getReserves()(uint256,uint256)' --rpc-url "$RPC" 2>/dev/null || true)
    QR=$(echo "$RES" | sed -n 1p | awk '{print $1}')
    TR=$(echo "$RES" | sed -n 2p | awk '{print $1}')
    SELL=$(call "$CURVE" 'sellableTokens()(uint256)')
    FEE=$(call "$CURVE" 'feeBps()(uint256)')
    if [ -n "$QR" ] && [ -n "$TR" ] && [ "$QR" != "0" ]; then
      MINOUT=$(python3 -c "
net=$SPEND-($SPEND*${FEE:-100})//10000
exp=(net*$TR)//($QR+net)
sell=$SELL
exp=min(exp,sell)
print(max(1,exp*85//100))")
      inf "quoted ~$(wei "$MINOUT") HATCH floor (15% slippage allowance)"
    fi
  else
    echo "  ${YEL}!${RST} curve has graduated — crack routes through the v4 pool"
    POOLOK=$(cast call "$EGG" 'poolConfigured()(bool)' --rpc-url "$RPC" 2>/dev/null)
    [ "$POOLOK" = "true" ] || die "the v4 pool is not configured yet; run configurePool first"
  fi

  echo
  echo "  cracking…"
  cast send "$EGG" "crackEgg(uint256)" "$MINOUT" --rpc-url "$RPC" --private-key "$KEY" >/tmp/keeper.log 2>&1 \
    || { tail -4 /tmp/keeper.log; die "crack failed (try again — the price may have moved)"; }

  NEWBURN=$(call "$EGG" 'totalBurned()(uint256)')
  echo
  echo "${GRN}${BOLD}EGG CRACKED.${RST}"
  echo "  HATCH burned total  $(wei "$NEWBURN")"
  echo "  bounty paid to you  $(wei "$BOUNTY") NVDA"
  echo "  now on round        $(call "$EGG" 'round()(uint256)'), cracks at $(wei "$(call "$EGG" 'crackThreshold()(uint256)')") NVDA"
fi
echo
