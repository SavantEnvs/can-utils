#!/usr/bin/env bash
#
# mayhem/build.sh — build can-utils' fuzz targets and its functional-test binaries.
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem; re-runnable and offline
# (only the system toolchain is used, nothing is fetched).
#
# Outputs (all under /mayhem):
#   fuzz_parse_canframe[-standalone]  libFuzzer harness over lib.c's CAN frame parser/formatters
#   asc2log-fuzz                      upstream's asc2log CLI, sanitized + SanCov, file input (-I @@)
#   asc2log, log2asc, kat_canframe    normal-flags oracle binaries that mayhem/test.sh runs
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# Same defines upstream's Makefile passes (they are needed to build against minimal kernel headers).
DEFS="-D_GNU_SOURCE -D_FILE_OFFSET_BITS=64 -DAF_CAN=PF_CAN -DPF_CAN=29 -DSO_RXQ_OVFL=40 \
-DSCM_TIMESTAMPING_OPT_STATS=54 -DCLOCK_TAI=11 -DSO_TXTIME=61 -DSCM_TXTIME=SO_TXTIME"
INC="-I$SRC -I$SRC/include"
# SanCov on the project code itself, unconditionally (also when SANITIZER_FLAGS is empty).
FUZZ_CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link -O1 $INC $DEFS"

# 1) Sanitized + instrumented project objects (build/ is gitignored upstream).
B="$SRC/build/mayhem"
mkdir -p "$B"
for f in lib canframelen asc2log; do
  # shellcheck disable=SC2086
  $CC $FUZZ_CFLAGS -c "$SRC/$f.c" -o "$B/$f.o"
done
# shellcheck disable=SC2086
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$B/lsan_off.o"
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$B/standalone_main.o"

# 2) asc2log CLI as a file-input target.
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link "$B/asc2log.o" "$B/lib.o" "$B/lsan_off.o" \
  -o "$SRC/asc2log-fuzz"

# 3) libFuzzer harness + standalone reproducer.
# shellcheck disable=SC2086
$CC $FUZZ_CFLAGS -c "$SRC/mayhem/fuzz_parse_canframe.c" -o "$B/fuzz_parse_canframe.o"
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$B/fuzz_parse_canframe.o" "$B/lib.o" "$B/lsan_off.o" \
  -o "$SRC/fuzz_parse_canframe"
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS "$B/standalone_main.o" "$B/fuzz_parse_canframe.o" "$B/lib.o" "$B/lsan_off.o" \
  -o "$SRC/fuzz_parse_canframe-standalone"

# 4) Oracle binaries with the project's NORMAL flags (upstream's own Makefile; objects land in-tree,
#    where *.o and the program names are gitignored upstream).
env -u CFLAGS -u CPPFLAGS -u LDFLAGS make -j"$MAYHEM_JOBS" asc2log log2asc CC="$CC" \
  CFLAGS="-O2 -Wall -Wno-parentheses -Wsign-compare $COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS"
# shellcheck disable=SC2086
$CC -O2 $COVERAGE_FLAGS $INC $DEFS "$SRC/mayhem/kat/kat_canframe.c" "$SRC/lib.c" -o "$SRC/kat_canframe"
