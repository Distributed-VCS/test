#i/usr/bin/env bash
# integration test suite for the dvcs cli + contranct
#

# exits 0 if every scenario passes, non-zero with an summary of failure
# otherwise safe to rerun each run used a freash chain and fresh temp dir
#
set -u
# convenience for env where the v compiler isn't on path.
# but is checked out at a well-know location; harmless no-op otherwise
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_DIR="$(mktemp -d)"
RPC_PORT=18545
RPC_URL="http://127.0.0.1:${RPC_PORT}"

PASS=0
FAIL=0
FAILURES=()

log_section() {
  echo ""
  echo "=== $1 ==="
}

check() {
  #check <description> <atuatl_exit_code> <expected: 0=success,nonzero=should-fail>
  local desc="$1" code="$2" want="$3"
  if [ "$want" = "0" ] && [ "$code" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo " PASS: $desc"
  elif [ "$want" != "0" ] && [ "$code" -ne 0 ]; then
    PASS=$((PASS + 1))
    echo " PASS: $desc (correctly failed)"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("$desc")
    echo " FAIL: $desc (exit=$code, wanted 0=$want)"
  fi
}

check_contains() {
  #check contains <description> <haystack> <needle>
  local desc="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qf -- "$needle"; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("$desc")
    echo " FAIL: $desc (expected to find: $needle)"
  fi
}

check_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    FAIL=$((FAIL + 1))
    FAILURES+=("desc")
    echo " FAIL: $desc (should not contain: $needle)"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  fi
}

cleanup() {
  #killing $chain_pid alone isn't reliable npx often spawns the atuatl_exit_code
  #long running hardhat process as a child of the npx process it
  #returned, so $! only captures the wrapper's pid, which can exit on
  #its own while the real node keeps running (same issue fixed in
  #scripts/demo.sh). math by the exact command line instead.
  pkill -f "hardhat node --port ${RPC_PORT}" 2>/dev/null
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

#build cli + contraanct

log_section "Build"
cd "${PROJECT_ROOT}/cli"
v -cc tcc -o "${WORK_DIR}/dvcs". || {
  echo "CLI build failed"
  exit 1
}
DVCS="${WORK_DIR}/dvcs"
echo " built ${DVCS}"

cd "${PROJECT_ROOT}"
mkdir -p "${WORK_DIR}/build"
cat >"${WORK_DIR}/input.json" <<PYEOF
{
  "language": "Solidity",
  "sources" : {"Dvcs.sol": {"content": null}},
"settings": {
"evmVersion":"paris",
"viaIr":true,
"optimizer":{"enabled":true,"runs":200},
"outputSelection":{"*":{"*":["abi","evm.bytecode.object"]}}
}
}
PYEOF
python3 -c "
import json
d = json.load(open('${WORK_DIR}/input.json'))
d['sources']['DVCS.sol']['content']=open('contracts/DVCS.sol').read()
json.dump(d,open('${WORK_DIR}/input.json','w'))
"
npx -p solc solcjs --standard-json <"${WORK_DIR}/input.json" >"${WORK_DIR}/output.json" 2>/dev/null
tail -n +2 "${WORK_DIR}/output.json" >"${WORK_DIR}/output_clean.json"
python3 -c "
import json
d = json.load(open('${WORK_DIR}/output_clean.json'))
errs = [e for e in (d.get('errors') or []) if e.get('severity')=='error']
if errs:
    for e in errs: print(e.get('message'))
    raise SystemExit(1)
c = d['contracts']['DVCS.sol']['DVCS']
open('${WORK_DIR}/build/DVCS.bin','w').write(c['evm']['bytecode']['object'])
json.dump(c['abi'], open('${WORK_DIR}/build/DVCS.abi','w'))
" || {
  echo "Contract compile failed"
  exit 1
}
echo "  contract compiled"

#start an isolated chain + deploy
log_section "Chain setup"
cd "${SCRIPT_DIR}"
if [ ! -d node_modules/hardhat ] || [ ! -d node_modules/ethers ]; then
  echo "  installing hardhat + ethers (one-time)..."
  npm install --save-dev "hardhat@^2.22.0" ethers >/dev/null 2>&1
fi
if [ ! -f hardhat.config.js ]; then
  cat >hardhat.config.js <<'EOF'
module.exports = { solidity: "0.8.24" };
EOF
fi

# hardhat must be run from a directory containing its own node_modules and
# config hence `cd "${SCRIPT_DIR}"` above, which is already where we are)
npx hardhat node --port "${RPC_PORT}" >"${WORK_DIR}/hardhat.log" 2>&1 &
CHAIN_PID=$!

#poll for readiness instead of a fixed sleep -- a fresh 'npm install'
#right before this can make the fist startup noticeably slower than
#later ones.
