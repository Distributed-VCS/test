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
