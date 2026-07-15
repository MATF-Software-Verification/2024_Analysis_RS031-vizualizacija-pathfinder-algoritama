#!/usr/bin/env bash
# What: Runs Valgrind's memcheck over the QtTest suite.
# Why:  Independent (binary-instrumentation) confirmation of the sanitizer results:
#       detects leaks, invalid reads/writes and use of uninitialized memory without
#       recompiling with instrumentation.
# How:  Builds a plain (non-coverage, non-sanitizer) debug build so line info is
#       accurate, then runs each test under memcheck with a Qt suppression file to
#       hide the framework's own "still reachable" globals.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(realpath "${HERE}/..")"
BUILD="${HERE}/build"
RESULTS="${HERE}/results"
mkdir -p "${RESULTS}"

QT_PREFIX="${QT_PREFIX:-/home/jovan/Qt/6.10.2/gcc_64}"

echo "==> $(valgrind --version)"

echo "==> Plain debug build (no coverage / no sanitizer)"
cmake -S "${ROOT}/tests" -B "${BUILD}" \
    -DCMAKE_PREFIX_PATH="${QT_PREFIX}" \
    -DENABLE_COVERAGE=OFF \
    -DCMAKE_BUILD_TYPE=Debug >/dev/null
cmake --build "${BUILD}" -j"$(nproc)" >/dev/null

export QT_QPA_PLATFORM=offscreen
SUPP="${HERE}/qt.supp"

echo "==> Running memcheck"
for t in tst_points tst_hangman tst_leaderboard tst_words tst_manager; do
    echo "----- ${t} -----"
    # --leak-check=full + show only definite/indirect leaks (the actionable ones);
    # --error-exitcode lets us see, per test, whether memcheck found anything.
    valgrind \
        --tool=memcheck \
        --leak-check=full \
        --show-leak-kinds=definite,indirect \
        --errors-for-leak-kinds=definite,indirect \
        --track-origins=yes \
        --suppressions="${SUPP}" \
        --gen-suppressions=no \
        --error-exitcode=99 \
        --log-file="${RESULTS}/${t}.memcheck.log" \
        "${BUILD}/${t}" >/dev/null 2>&1 || true
    # Surface the bottom-line summary for each test.
    grep -E "ERROR SUMMARY|definitely lost|indirectly lost" "${RESULTS}/${t}.memcheck.log" \
        | sed 's/^/    /'
done

echo "==> Done. Per-test logs in ${RESULTS}/*.memcheck.log"
