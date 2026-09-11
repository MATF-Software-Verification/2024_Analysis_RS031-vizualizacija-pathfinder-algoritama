#!/usr/bin/env bash

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="${HERE}/build"
RESULTS="${HERE}/results"
mkdir -p "${RESULTS}"

QT_PREFIX="${QT_PREFIX:-/home/jovan/Qt/6.10.2/gcc_64}"

echo "==> $(valgrind --version)"

echo "==> Plain debug build (no coverage / no sanitizer)"
cmake -S "${HERE}/../tests" -B "${BUILD}" \
    -DCMAKE_PREFIX_PATH="${QT_PREFIX}" \
    -DENABLE_COVERAGE=OFF \
    -DCMAKE_BUILD_TYPE=Debug >/dev/null
cmake --build "${BUILD}" -j"$(nproc)" >/dev/null

export QT_QPA_PLATFORM=offscreen

echo "==> Running memcheck"
for t in tst_points tst_hangman tst_leaderboard tst_words tst_manager; do
    echo "----- ${t} -----"
    valgrind \
        --tool=memcheck \
        --leak-check=full \
        --show-leak-kinds=definite,indirect \
        --errors-for-leak-kinds=definite,indirect \
        --track-origins=yes \
        --suppressions="${HERE}/qt.supp" \
        --log-file="${RESULTS}/${t}.memcheck.log" \
        "${BUILD}/${t}" >/dev/null 2>&1 || true
    grep -E "ERROR SUMMARY|definitely lost|indirectly lost|possibly lost" "${RESULTS}/${t}.memcheck.log" \
        | sed 's/^/    /'
done

echo "==> Done. Per-test logs in ${RESULTS}/*.memcheck.log"
