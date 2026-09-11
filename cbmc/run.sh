#!/usr/bin/env bash

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS="${HERE}/results"
mkdir -p "${RESULTS}"

echo "==> cbmc $(cbmc --version)"

run_case() {
    local name="$1"; shift
    echo "==> ${name}"
    # kod 10 = svojstvo oboreno, ocekivano; svaki drugi pad je greska alata
    cbmc "${HERE}/${name}.c" "$@" >"${RESULTS}/${name}.log" 2>&1 || [ $? -eq 10 ]
    # sidro ^: neusidren obrazac bi hvatao i putanju, a ime points_overflow.c sadrzi "overflow"
    grep -E '^\[main\.|^VERIFICATION' "${RESULTS}/${name}.log" | sed 's/^/    /'
    echo
}

#--trace samo kod testova koji ne prolaze; *-overflow-check imenuje uzrok
run_case hangman_masklen --unsigned-overflow-check --trace

run_case points_domain --signed-overflow-check

run_case points_overflow --signed-overflow-check --trace

echo "==> Done. Full traces in ${RESULTS}/*.log"
