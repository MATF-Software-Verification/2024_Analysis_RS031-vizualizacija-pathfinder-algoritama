cmake_minimum_required(VERSION 3.16)
project(sketchit_tests LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Network Widgets Test)

# Path to the analyzed project's server sources (inside the git submodule).
set(SERVER_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../SketchIt/SketchIt/server")
set(RES_QRC    "${SERVER_DIR}/../../resources/resources.qrc")

# Coverage instrumentation (gcov). -O0 keeps line mapping faithful.
option(ENABLE_COVERAGE "Build with gcov coverage instrumentation" ON)
if(ENABLE_COVERAGE)
    add_compile_options(--coverage -O0 -g)
    add_link_options(--coverage)
endif()

# Server logic under test. server.cpp/main.cpp are excluded (they pull in QtZeroConf
# and the networking entry point, which are out of scope for unit testing).
set(SERVERLOGIC_SOURCES
    "${SERVER_DIR}/points.cpp"
    "${SERVER_DIR}/hangman.cpp"
    "${SERVER_DIR}/words.cpp"
    "${SERVER_DIR}/leaderboard.cpp"
    "${SERVER_DIR}/player.cpp"
    "${SERVER_DIR}/manager.cpp"
    "${SERVER_DIR}/game.cpp"
)

qt_add_library(serverlogic STATIC ${SERVERLOGIC_SOURCES} ${RES_QRC})
target_include_directories(serverlogic PUBLIC "${SERVER_DIR}")
target_link_libraries(serverlogic PUBLIC Qt6::Core Qt6::Network Qt6::Widgets)

enable_testing()

# Helper: declare one QtTest executable + CTest entry per test source file.
function(add_qt_test name src)
    qt_add_executable(${name} "${src}")
    target_link_libraries(${name} PRIVATE serverlogic Qt6::Test)
    add_test(NAME ${name} COMMAND ${name})
endfunction()

# --- Unit tests (jedinični) — jedinice bez spoljnih zavisnosti (nema šta da se mockuje) ---
add_qt_test(tst_points   tests/unit/tst_points.cpp)
add_qt_test(tst_hangman  tests/unit/tst_hangman.cpp)

# --- Integration tests (integracioni) — prelaze granicu ka resursu/fajl-sistemu/drugoj klasi ---
add_qt_test(tst_leaderboard tests/integration/tst_leaderboard.cpp)
add_qt_test(tst_words       tests/integration/tst_words.cpp)
add_qt_test(tst_manager     tests/integration/tst_manager.cpp)
