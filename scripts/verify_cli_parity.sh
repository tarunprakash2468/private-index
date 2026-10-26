#!/usr/bin/env bash
set -euo pipefail

# Parity Verification Harness for private-index-cli
# Ensures CLI commands, flags, JSON serialization, and error contracts remain identical.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PACKAGE_PATH="${REPO_ROOT}/Packages/PrivateIndexEngine"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BOLD}${CYAN}=== Private Index CLI Parity Verification Suite ===${NC}\n"

# 1. Compile private-index-cli
echo -e "${BOLD}[1/4] Compiling private-index-cli...${NC}"
swift build --package-path "${PACKAGE_PATH}" --product private-index-cli

# 2. Locate compiled executable
echo -e "\n${BOLD}[2/4] Locating compiled binary...${NC}"
CANDIDATE_PATHS=(
    "$(swift build --package-path "${PACKAGE_PATH}" --product private-index-cli --show-bin-path 2>/dev/null)/private-index-cli"
    "${PACKAGE_PATH}/.build/out/Products/Debug/private-index-cli"
    "${PACKAGE_PATH}/.build/debug/private-index-cli"
    "${REPO_ROOT}/.build/out/Products/Debug/private-index-cli"
    "${REPO_ROOT}/.build/debug/private-index-cli"
)

CLI_BIN=""
for path in "${CANDIDATE_PATHS[@]}"; do
    if [[ -x "${path}" ]]; then
        CLI_BIN="${path}"
        break
    fi
done

if [[ -z "${CLI_BIN}" ]]; then
    # Fallback search
    FALLBACK="$(find "${REPO_ROOT}" -name "private-index-cli" -type f -perm +111 2>/dev/null | head -n 1)"
    if [[ -n "${FALLBACK}" && -x "${FALLBACK}" ]]; then
        CLI_BIN="${FALLBACK}"
    fi
fi

if [[ -z "${CLI_BIN}" ]]; then
    echo -e "${RED}Error: Could not locate compiled private-index-cli binary.${NC}" >&2
    exit 1
fi

echo -e "${GREEN}✔ Found CLI binary:${NC} ${CLI_BIN}\n"

# 3. Test verification checks
PASSED=0
FAILED=0

run_check() {
    local test_name="$1"
    shift
    echo -n "  • Checking: ${test_name}... "
    if "$@"; then
        echo -e "${GREEN}PASS${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        FAILED=$((FAILED + 1))
    fi
}

echo -e "${BOLD}[3/4] Running Parity Verification Checks...${NC}"

# Check: pi help
check_help() {
    local output
    output="$("${CLI_BIN}" help 2>&1)"
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo -e "\n${RED}Exit code was $exit_code (expected 0)${NC}" >&2
        return 1
    fi
    if ! echo "${output}" | grep -q "USAGE" || ! echo "${output}" | grep -q "COMMANDS"; then
        echo -e "\n${RED}Output missing USAGE or COMMANDS header:${NC}\n${output}" >&2
        return 1
    fi
    return 0
}
run_check "pi help (exit 0 and USAGE/COMMANDS presence)" check_help

# Check: pi stats
check_stats() {
    local output
    output="$("${CLI_BIN}" stats 2>&1)"
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo -e "\n${RED}Exit code was $exit_code (expected 0)${NC}" >&2
        return 1
    fi
    if ! echo "${output}" | grep -q "Database"; then
        echo -e "\n${RED}Output missing expected stats details:${NC}\n${output}" >&2
        return 1
    fi
    return 0
}
run_check "pi stats (exit 0)" check_stats

# Check: Subcommand helps
SUBCOMMANDS=("search" "watch" "bench" "index" "stats" "reset")
for subcmd in "${SUBCOMMANDS[@]}"; do
    check_subcmd_help() {
        local output
        output="$("${CLI_BIN}" "${subcmd}" --help 2>&1)"
        local exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
            echo -e "\n${RED}Exit code was $exit_code for ${subcmd} --help (expected 0)${NC}" >&2
            return 1
        fi
        if ! echo "${output}" | grep -qi "USAGE"; then
            echo -e "\n${RED}${subcmd} --help output missing USAGE header:${NC}\n${output}" >&2
            return 1
        fi
        return 0
    }
    run_check "pi ${subcmd} --help" check_subcmd_help
done

# Check: pi search "test" --json (valid JSON array)
check_search_json() {
    local output
    output="$("${CLI_BIN}" search "test" --json 2>&1)"
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo -e "\n${RED}Exit code was $exit_code (expected 0)${NC}" >&2
        return 1
    fi
    # Validate output parses as valid JSON array
    echo "${output}" | python3 -c '
import sys, json
try:
    data = json.loads(sys.stdin.read())
except Exception as e:
    sys.stderr.write(f"Invalid JSON: {e}\n")
    sys.exit(1)
if not isinstance(data, list):
    sys.stderr.write(f"Expected JSON array, got {type(data).__name__}\n")
    sys.exit(1)
'
}
run_check "pi search \"test\" --json (valid JSON array)" check_search_json

# Check: pi bench --vectors 50 --json (valid JSON dictionary with required keys)
check_bench_json() {
    local output
    output="$("${CLI_BIN}" bench --vectors 50 --json 2>&1)"
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo -e "\n${RED}Exit code was $exit_code (expected 0)${NC}" >&2
        return 1
    fi
    echo "${output}" | python3 -c '
import sys, json
try:
    data = json.loads(sys.stdin.read())
except Exception as e:
    sys.stderr.write(f"Invalid JSON: {e}\n")
    sys.exit(1)
if not isinstance(data, dict):
    sys.stderr.write(f"Expected JSON dictionary, got {type(data).__name__}\n")
    sys.exit(1)
required_keys = ["system", "chunker", "tokenizer", "inference", "vectorStore", "resources"]
missing = [k for k in required_keys if k not in data]
if missing:
    sys.stderr.write(f"Missing required benchmark keys: {missing}\n")
    sys.exit(1)
'
}
run_check "pi bench --vectors 50 --json (valid JSON dictionary with benchmark keys)" check_bench_json

# Check: Error handling: invalid mode writes JSON error to stderr and exits non-zero
check_invalid_mode_json() {
    local stderr_file
    stderr_file="$(mktemp)"
    local stdout_file
    stdout_file="$(mktemp)"
    
    set +e
    "${CLI_BIN}" search "test" --mode invalid --json >"${stdout_file}" 2>"${stderr_file}"
    local exit_code=$?
    set -e
    
    local stderr_content
    stderr_content="$(cat "${stderr_file}")"
    rm -f "${stderr_file}" "${stdout_file}"

    if [[ $exit_code -eq 0 ]]; then
        echo -e "\n${RED}Expected non-zero exit code, but got 0${NC}" >&2
        return 1
    fi

    # Validate stderr is valid JSON with "error" key
    echo "${stderr_content}" | python3 -c '
import sys, json
try:
    data = json.loads(sys.stdin.read())
except Exception as e:
    sys.stderr.write(f"Stderr is not valid JSON: {e}\nRaw stderr: {sys.stdin.read()}\n")
    sys.exit(1)
if not isinstance(data, dict) or "error" not in data:
    sys.stderr.write(f"Expected JSON object with \"error\" key, got: {data}\n")
    sys.exit(1)
'
}
run_check "pi search \"test\" --mode invalid --json (stderr JSON error & non-zero exit)" check_invalid_mode_json

# 4. Final summary
echo -e "\n${BOLD}[4/4] Parity Verification Summary${NC}"
echo -e "  • Total checks: $((PASSED + FAILED))"
echo -e "  • Passed:       ${GREEN}${PASSED}${NC}"
echo -e "  • Failed:       ${RED}${FAILED}${NC}"

if [[ $FAILED -gt 0 ]]; then
    echo -e "\n${RED}${BOLD}❌ Parity Verification Failed (${FAILED} check(s) failed).${NC}"
    exit 1
else
    echo -e "\n${GREEN}${BOLD}✔ All Parity Verification checks passed successfully!${NC}"
    exit 0
fi
