#!/usr/bin/env bash
set -euo pipefail

#BASH_SOURCE cita sa komandne linije ./run.sh
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="${HERE}/build"
RESULTS="${HERE}/results"
#realpath razresava ..
SERVER_DIR="$(realpath "${HERE}/../SketchIt/SketchIt/server")"

QT_PREFIX="${QT_PREFIX:-/home/jovan/Qt/6.10.2/gcc_64}"

echo "==> Configuring"
cmake -S "${HERE}" -B "${BUILD}" \
    -DCMAKE_PREFIX_PATH="${QT_PREFIX}" >/dev/null

#build paralelno sa n jezgara(nroc)
echo "==> Building"
cmake --build "${BUILD}" -j"$(nproc)" >/dev/null

#neophodan za linkovanje Qt-a bez ikakvog display-a
#i pokrece testove
echo "==> Running tests (headless)"
export QT_QPA_PLATFORM=offscreen
ctest --test-dir "${BUILD}" --output-on-failure

#sa -p ignorisemo File exists
echo "==> Capturing coverage"
mkdir -p "${RESULTS}"
LCOV_IGNORE="mismatch,gcov"
#prolazi kroz build skupi sve .gcno/.gcda parove pozovi gco
#sakupi rez i stavi u coverage.info
lcov --capture --directory "${BUILD}" \
     --output-file "${RESULTS}/coverage.info" \
     --ignore-errors "${LCOV_IGNORE}" --quiet

#iz sakupljenog zadrzi samo  stvari sa server putanjom i zapisi
# u coverage.server.info
lcov --extract "${RESULTS}/coverage.info" "${SERVER_DIR}/*" \
     --output-file "${RESULTS}/coverage.server.info" \
     --ignore-errors "${LCOV_IGNORE}" --quiet

echo "==> Per-file line coverage (analyzed sources, via gcov):"
GCDA_DIR="${BUILD}/CMakeFiles/serverlogic.dir${SERVER_DIR}"
for f in points hangman words leaderboard manager player game; do
    echo -n "${f}.cpp: "
    gcov -n -o "${GCDA_DIR}" "${GCDA_DIR}/${f}.cpp.gcda" 2>/dev/null \
        | grep -A1 "${f}.cpp" | grep "Lines executed" | head -1
done | tee "${RESULTS}/coverage.summary.txt"

echo "==> Generating HTML report"
genhtml "${RESULTS}/coverage.server.info" \
        --output-directory "${RESULTS}/html" --quiet

echo "==> Done. Open ${RESULTS}/html/index.html for the full report."
