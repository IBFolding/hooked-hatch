#!/usr/bin/env bash
#
# HOOKED / HATCH — one-shot launch.
#
#   ./scripts/launch.sh
#
# Add your key to .env (or paste it when prompted) and press enter.
# Everything else runs itself:
#   1. preflight the live chain
#   2. deploy Nest + Router (governance burned)
#   3. launch HATCH on PONS against NVDA
#   4. write the addresses into web/config.js and docs/DEPLOYMENTS.md
#   5. redeploy the website
#
# Nothing is broadcast until you confirm. The key is never echoed or logged.

set -euo pipefail

# --no-launch : deploy the contracts and wire the site, but do NOT create the
#               HATCH token on PONS. Run this script again later to launch.
# --launch-only : skip deployment and only launch, using FEE_ROUTER from .env.
DO_DEPLOY=1; DO_LAUNCH=1
for arg in "$@"; do
  case "$arg" in
    --no-launch)   DO_LAUNCH=0 ;;
    --launch-only) DO_DEPLOY=0 ;;
    --dev-buy=*)   DEV_BUY_NVDA="${arg#*=}" ;;
    -h|--help)
      echo "usage: ./scripts/launch.sh [--no-launch | --launch-only]"
      echo "  (no flags)     deploy contracts AND launch HATCH on PONS"
      echo "  --no-launch    deploy contracts only; no token is created"
      echo "  --launch-only  launch the token using FEE_ROUTER from .env
  --dev-buy=N    also buy N NVDA of HATCH at launch, from the launcher wallet
                 (the launcher is snipe-tax exempt automatically)"
      exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BOLD=$'\033[1m'; DIM=$'\033[2m'; GRN=$'\033[32m'; RED=$'\033[31m'; YEL=$'\033[33m'; RST=$'\033[0m'
step()  { echo; echo "${BOLD}▸ $*${RST}"; }
ok()    { echo "  ${GRN}✓${RST} $*"; }
warn()  { echo "  ${YEL}!${RST} $*"; }
die()   { echo "  ${RED}✗ $*${RST}" >&2; exit 1; }

export PATH="$HOME/.foundry/bin:$PATH"
command -v forge >/dev/null || die "forge not found. Install Foundry: https://getfoundry.sh"
command -v node  >/dev/null || die "node not found."

# ---------------------------------------------------------------- config
[ -f .env ] || { cp .env.example .env; warn "created .env from .env.example"; }
set -a; . ./.env; set +a

RPC="${ROBINHOOD_RPC_URL:-https://rpc.mainnet.chain.robinhood.com}"

# A fork rehearsal must never publish fork addresses to the live site.
IS_FORK=0
case "$RPC" in *127.0.0.1*|*localhost*|*0.0.0.0*) IS_FORK=1 ;; esac
: "${HOOKED_TREASURY:?HOOKED_TREASURY missing from .env}"
: "${TEAM_TREASURY:?TEAM_TREASURY missing from .env}"
export ROBINHOOD_RPC_URL="$RPC" HOOKED_TREASURY TEAM_TREASURY

if [ -z "${PRIVATE_KEY:-}" ]; then
  echo
  read -rsp "Deployer private key (hidden, not saved): " PRIVATE_KEY; echo
  [ -n "$PRIVATE_KEY" ] || die "no key given"
fi
[[ "$PRIVATE_KEY" == 0x* ]] || PRIVATE_KEY="0x$PRIVATE_KEY"
export PRIVATE_KEY

DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY" 2>/dev/null) || die "that private key is not valid"

# ---------------------------------------------------------------- 1. preflight
step "1/5  Preflight — live chain checks"
node scripts/verify-chain.mjs || die "preflight failed. Do not launch."

BAL_WEI=$(cast balance "$DEPLOYER" --rpc-url "$RPC")
BAL=$(cast from-wei "$BAL_WEI")
ok "deployer $DEPLOYER"
ok "balance  $BAL ETH"
awk -v b="$BAL" 'BEGIN{exit !(b+0 < 0.002)}' && die "balance too low; need ~0.002 ETH for both transactions"

# ---------------------------------------------------------------- confirm
if [ "$DO_LAUNCH" = "1" ] && [ "$DO_DEPLOY" = "1" ]; then
  PLAN="${BOLD}About to broadcast TWO real transactions on Robinhood Chain (4663).${RST}
  ${RED}This DEPLOYS the contracts AND CREATES the HATCH token on PONS.${RST}"
elif [ "$DO_LAUNCH" = "0" ]; then
  PLAN="${BOLD}About to broadcast ONE real transaction on Robinhood Chain (4663).${RST}
  ${GRN}Contracts only. NO token is created. Nothing appears on PONS.${RST}"
else
  PLAN="${BOLD}About to broadcast ONE real transaction on Robinhood Chain (4663).${RST}
  ${RED}This CREATES the HATCH token on PONS using the router in .env.${RST}"
fi

cat <<EOF

$PLAN

  deployer            $DEPLOYER
  egg         70%  →  (deployed in step 2)
                      fills with NVDA; at the crack threshold anyone may
                      crack it: it buys HATCH and BURNS it, cracker keeps 5%
  hooked      20%  →  $HOOKED_TREASURY
  team        10%  →  $TEAM_TREASURY
  governance       →  ${RED}BURNED${RST} (0x…dEaD) — irreversible, no admin ever
  pair token       →  NVDA
  creator tax      →  0%

${YEL}These addresses are immutable once deployed. There is no undo.${RST}
EOF
read -rp "Type LAUNCH to continue: " c
[ "$c" = "LAUNCH" ] || die "aborted"

# ---------------------------------------------------------------- 2. deploy
cd contracts
if [ "$DO_DEPLOY" = "0" ]; then
  ROUTER="${FEE_ROUTER:?--launch-only needs FEE_ROUTER in .env}"
  LOCKER="${HATCH_EGG:-$NEST_ADDRESS}"
  NEST="${NEST_ADDRESS:-}"
  ok "using existing router $ROUTER"

else
step "2/5  Deploying Nest + Router"
# Explorer verification needs a real verifier; skip it on a fork, and never let
# a verification failure look like a deployment failure.
VERIFY_FLAG="--verify"
if [ "$IS_FORK" = "1" ]; then
  VERIFY_FLAG=""
  warn "local RPC detected — fork rehearsal mode (no verify, no publish)"
fi
forge script script/DeployHatch.s.sol:DeployHatch --rpc-url "$RPC" --broadcast $VERIFY_FLAG 2>&1 \
  | tee /tmp/hatch-deploy.log | grep -E "HatchEgg|HatchFeeRouter|crack|bounty|BURNED" || true
grep -q "ONCHAIN EXECUTION COMPLETE" /tmp/hatch-deploy.log \
  || die "deployment failed — see /tmp/hatch-deploy.log"
# Source verification is cosmetic and often unavailable; never fail the launch on it.
if grep -q "contracts were verified\|Failed to verify" /tmp/hatch-deploy.log; then
  warn "contracts deployed but source verification did not complete"
  warn "verify later: cd contracts && forge verify-contract <addr> <Contract> --chain 4663"
fi

RUN=broadcast/DeployHatch.s.sol/4663/run-latest.json
NEST=$(python3 -c "
import json;d=json.load(open('$RUN'))
print(next(t['contractAddress'] for t in d['transactions'] if t.get('contractName')=='HatchEgg'))")
ROUTER=$(python3 -c "
import json;d=json.load(open('$RUN'))
print(next(t['contractAddress'] for t in d['transactions'] if t.get('contractName')=='HatchFeeRouter'))")
NEST=$(cast to-check-sum-address "$NEST")
ROUTER=$(cast to-check-sum-address "$ROUTER")
LOCKER="$NEST"   # the egg IS the buyback venue now
ok "HatchEgg        $NEST"
ok "HatchFeeRouter  $ROUTER"
fi

# ---------------------------------------------------------------- 3. launch
if [ "$DO_LAUNCH" = "0" ]; then
  cd "$ROOT"
  step "Contracts deployed — token NOT launched"
  python3 - "$NEST" "$ROUTER" "$LOCKER" <<'PY2'
import re, sys
nest, router, locker = sys.argv[1:4]
p='web/config.js'; s=open(p).read()
s=re.sub(r'nest:\s*"[^"]*"',          f'nest: "{nest}"', s)
s=re.sub(r'feeRouter:\s*"[^"]*"',     f'feeRouter: "{router}"', s)
s=re.sub(r'buybackLocker:\s*"[^"]*"', f'buybackLocker: "{locker}"', s)
open(p,'w').write(s)
PY2
  ok "web/config.js updated with Nest + Router"
  cat <<EOF

${GRN}${BOLD}CONTRACTS ARE LIVE. THE TOKEN IS NOT.${RST}

  Egg (70%)       $NEST
  Fee router      $ROUTER

Nothing exists on PONS yet. When you are ready to create HATCH:

  ${BOLD}echo "FEE_ROUTER=$ROUTER" >> .env${RST}
  ${BOLD}echo "HATCH_EGG=$NEST" >> .env${RST}
  ${BOLD}./scripts/launch.sh --launch-only${RST}

EOF
  exit 0
fi

step "3/5  Launching HATCH on PONS"
DEV_BUY_NVDA_WEI=0
if [ -n "${DEV_BUY_NVDA:-}" ]; then
  DEV_BUY_NVDA_WEI=$(cast to-wei "$DEV_BUY_NVDA" ether)
  HELD=$(cast call 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC 'balanceOf(address)(uint256)' "$DEPLOYER" --rpc-url "$RPC" | awk '{print $1}')
  ok "opening buy requested: $DEV_BUY_NVDA NVDA"
  ok "launcher holds:        $(cast from-wei "$HELD") NVDA"
  python3 -c "import sys;sys.exit(0 if int('$HELD') >= int('$DEV_BUY_NVDA_WEI') else 1)" \
    || die "launcher holds too little NVDA for a $DEV_BUY_NVDA NVDA opening buy"
fi
export DEV_BUY_NVDA_WEI
FEE_ROUTER="$ROUTER" HATCH_EGG="$NEST" forge script script/LaunchHatch.s.sol:LaunchHatch \
  --rpc-url "$RPC" --broadcast 2>&1 | tee /tmp/hatch-launch.log | grep -E "HATCH token|bonding curve|launchFee|Error" || true
grep -q "ONCHAIN EXECUTION COMPLETE" /tmp/hatch-launch.log || die "launch failed — see /tmp/hatch-launch.log"

TOKEN=$(grep -oE "HATCH token +0x[0-9a-fA-F]{40}" /tmp/hatch-launch.log | grep -oE "0x[0-9a-fA-F]{40}" | tail -1)
CURVE=$(grep -oE "bonding curve +0x[0-9a-fA-F]{40}" /tmp/hatch-launch.log | grep -oE "0x[0-9a-fA-F]{40}" | tail -1)
[ -n "$TOKEN" ] || die "could not read the launched token address from the log"
TOKEN=$(cast to-check-sum-address "$TOKEN")
ok "HATCH token     $TOKEN"
ok "bonding curve   $CURVE"

# verify the launch record really points at our router
RECORD=$(cast call 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e 'getLaunchedToken(address)' "$TOKEN" --rpc-url "$RPC")
echo "$RECORD" | grep -qi "${ROUTER:2}" \
  && ok "creatorFeeRecipient confirmed = router" \
  || die "LAUNCH RECORD DOES NOT POINT AT THE ROUTER — investigate before announcing"
cd "$ROOT"

# ---------------------------------------------------------------- 4. wire site
step "4/5  Writing addresses into the site and docs"
python3 - "$TOKEN" "$NEST" "$ROUTER" "$LOCKER" <<'PY'
import re, sys
token, nest, router, locker = sys.argv[1:5]
p = 'web/config.js'; s = open(p).read()
s = re.sub(r'hatchToken:\s*"[^"]*"',    f'hatchToken: "{token}"', s)
s = re.sub(r'nest:\s*"[^"]*"',          f'nest: "{nest}"', s)
s = re.sub(r'feeRouter:\s*"[^"]*"',     f'feeRouter: "{router}"', s)
s = re.sub(r'buybackLocker:\s*"[^"]*"', f'buybackLocker: "{locker}"', s)
open(p,'w').write(s)

p = 'docs/DEPLOYMENTS.md'; d = open(p).read()
d = d.replace('| HatchNestVault | `TBD` |', f'| HatchNestVault | `{nest}` |')
d = d.replace('| HatchFeeRouter | `TBD` |', f'| HatchFeeRouter | `{router}` |')
d = d.replace('| HATCH token | `TBD` |',    f'| HATCH token | `{token}` |')
open(p,'w').write(d)
PY
node scripts/validate-config.mjs
ok "web/config.js updated"
ok "docs/DEPLOYMENTS.md updated"

# ---------------------------------------------------------------- 5. redeploy
step "5/5  Redeploying the website"
if [ "$IS_FORK" = "1" ]; then
  warn "fork rehearsal — skipping the production redeploy"
  warn "web/config.js and docs/DEPLOYMENTS.md now hold FORK addresses:"
  warn "  restore them with: git checkout web/config.js docs/DEPLOYMENTS.md"
elif command -v npx >/dev/null && [ -d web/.vercel ]; then
  (cd web && npx vercel deploy --prod --yes >/tmp/hatch-vercel.log 2>&1) \
    && ok "site redeployed" || warn "vercel redeploy failed — see /tmp/hatch-vercel.log"
else
  warn "vercel not linked; run: cd web && npx vercel deploy --prod"
fi

if NEST_ADDRESS="$NEST" ROUTER_ADDRESS="$ROUTER" RPC_URL="$RPC" node scripts/verify-chain.mjs >/tmp/hatch-postverify.log 2>&1; then
  ok "post-launch verification passed"
else
  warn "post-launch verification reported issues — see /tmp/hatch-postverify.log"
fi

cat <<EOF

${GRN}${BOLD}$([ "$IS_FORK" = "1" ] && echo "FORK REHEARSAL COMPLETE — nothing is live." || echo "HATCH IS LIVE.")${RST}

  HATCH token     $TOKEN
  bonding curve   $CURVE
  Egg (70%)       $NEST
  Fee router      $ROUTER
  Explorer        https://robinhoodchain.blockscout.com/address/$TOKEN
  Site            https://hookedlabs.vercel.app/hatch

${BOLD}Next:${RST}
  · Do NOT buy in the first seconds — PONS has anti-snipe behaviour on new launches.
  · Once trading produces fees, anyone can sweep them into the egg:
      cast send $ROUTER 'claimAndSplit()' --rpc-url $RPC
  · When the egg reaches its threshold, anyone can crack it and keep 5%:
      cast send $NEST 'crackEgg(uint256)' <minHatchOut> --rpc-url $RPC
  · Commit the updated config: git add -A && git commit -m "launch: HATCH live"

EOF
