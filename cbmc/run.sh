#!/usr/bin/env bash
# What: Runs CBMC bounded model checking on the SketchIt arithmetic harnesses.
# Why:  CBMC exhaustively verifies properties over all inputs within bounds, giving
#       either a proof (VERIFICATION SUCCESSFUL) or a concrete counterexample trace.
#       It complements KLEE (different engine: SAT/SMT bounded MC vs. symbolic exec).
# How:  Each harness is checked with the relevant built-in safety checks enabled;
#       output (including counterexample traces) is captured per harness in results/.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS="${HERE}/results"
mkdir -p "${RESULTS}"

echo "==> cbmc $(cbmc --version)"

run_case() {
    local name="$1"; shift
    echo "==> ${name}"
    # `|| true`: a refuted property makes CBMC exit non-zero; that is an expected
    # outcome for the bug-finding harnesses, so we capture it rather than abort.
    cbmc "${HERE}/${name}.c" "$@" 2>&1 | tee "${RESULTS}/${name}.log" | \
        grep -E "VERIFICATION|assertion|overflow|FAILURE|SUCCESS" | sed 's/^/    /' || true
    echo
}

# Hangman: prove the masked-length never underflows. --unsigned-overflow-check makes
# CBMC reason about size_t wrap-around; expected: VERIFICATION FAILED (len == 0).
run_case hangman_masklen --unsigned-overflow-check --bounds-check

# Points over the legal domain: expected VERIFICATION SUCCESSFUL (formula proven).
run_case points_domain --signed-overflow-check --div-by-zero-check

# Points without an input contract: expected VERIFICATION FAILED (overflow / range).
run_case points_overflow --signed-overflow-check

echo "==> Done. Full traces in ${RESULTS}/*.log"
