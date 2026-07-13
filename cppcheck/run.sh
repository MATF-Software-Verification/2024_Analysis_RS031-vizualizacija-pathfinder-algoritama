#!/usr/bin/env bash
# What: Runs cppcheck static analysis over the SketchIt server sources.
# Why:  Catches undefined behavior, leaks, out-of-bounds and API misuse without
#       executing the code; complements the dynamic tools (sanitizers/Valgrind).
# How:  Enables all checks, suppresses noise we can't fix in third-party Qt headers,
#       and writes both a human-readable log and a machine-readable XML report.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(realpath "${HERE}/../SketchIt/SketchIt/server")"
RESULTS="${HERE}/results"
mkdir -p "${RESULTS}"

# Analyze only the project's own translation units. QtZeroConf is a vendored
# third-party dependency and is excluded from the analysis scope.
SOURCES=(
    "${SERVER_DIR}/points.cpp"
    "${SERVER_DIR}/hangman.cpp"
    "${SERVER_DIR}/words.cpp"
    "${SERVER_DIR}/leaderboard.cpp"
    "${SERVER_DIR}/player.cpp"
    "${SERVER_DIR}/manager.cpp"
    "${SERVER_DIR}/game.cpp"
    "${SERVER_DIR}/server.cpp"
    "${SERVER_DIR}/main.cpp"
)

COMMON=(
    --enable=all
    --std=c++17
    --language=c++
    --inline-suppr
    # Teach cppcheck Qt's macros (Q_OBJECT, slots/signals) and container semantics;
    # without this it reports "unknownMacro" on every QObject subclass.
    --library=qt
    -I "${SERVER_DIR}"
    # We don't ship Qt's headers to cppcheck; silence the resulting noise so the
    # report only contains findings about the project's own code.
    --suppress=missingIncludeSystem
    --suppress=missingInclude
    --suppress=unmatchedSuppression
    --suppress=checkersReport
)

echo "==> cppcheck $(cppcheck --version)"

# Human-readable log (template makes each line grep-friendly: file:line: [id] msg).
cppcheck "${COMMON[@]}" \
    --template='{file}:{line}: [{severity}/{id}] {message}' \
    "${SOURCES[@]}" 2>&1 | tee "${RESULTS}/cppcheck.log"

# Machine-readable XML (handy for diffing / CI ingestion).
cppcheck "${COMMON[@]}" --xml --xml-version=2 \
    "${SOURCES[@]}" 2> "${RESULTS}/cppcheck.xml"

echo "==> Done. See ${RESULTS}/cppcheck.log and cppcheck.xml"
