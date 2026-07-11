#!/usr/bin/env bash
#
# mayhem/build.sh — build fio's libFuzzer harness `fuzz_parseini` (exercises parse_jobs_ini).
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem. The base image
# (ghcr.io/mayhemheroes/base) exports the build contract: CC, CXX, LIB_FUZZING_ENGINE,
# SANITIZER_FLAGS (ASan+UBSan, halting), SRC=/mayhem.
#
# fio specifics: the fuzz target only exists when CFLAGS carries
# -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION (Makefile guards T_FUZZ_PROGS on it). The whole
# project is compiled with $SANITIZER_FLAGS + -fsanitize=fuzzer-no-link so the FUZZED CODE
# (parse_jobs_ini and all of fio's option parser) is instrumented, not just the harness, and
# gets libFuzzer coverage. The harness links the engine via $LIB_FUZZING_ENGINE.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the ENVIRONMENT (overridable), with sane defaults.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
export DEBUG_FLAGS

cd "$SRC"

# Instrument the project: sanitizers + debug info + coverage (fuzzer-no-link) + fio's fuzz-build define.
export CC CXX LIB_FUZZING_ENGINE
export CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION"
export LDFLAGS="$SANITIZER_FLAGS"

./configure
make -j"$MAYHEM_JOBS" t/fuzz/fuzz_parseini

cp t/fuzz/fuzz_parseini /mayhem/fuzz_parseini

# Standalone (non-fuzzer) reproducer: fio's Makefile links its own onefile.c driver when
# LIB_FUZZING_ENGINE is unset (a run-once main, no fuzzing engine). Rebuild that variant — keep the
# sanitizers + debug info + fuzz-build define, drop fuzzer-no-link (no engine to satisfy the coverage callbacks).
make clean >/dev/null 2>&1 || true
unset LIB_FUZZING_ENGINE
export CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION"
./configure >/dev/null
make -j"$MAYHEM_JOBS" t/fuzz/fuzz_parseini
cp t/fuzz/fuzz_parseini /mayhem/fuzz_parseini-standalone

# Build fio's CUnit unit-test suite with NORMAL flags so mayhem/test.sh only RUNS it. The fuzz
# binaries are already copied to /mayhem, so reconfiguring the tree clean here (dropping the
# sanitizer CFLAGS) is safe. Leaves the runner at unittests/unittest.
unset CFLAGS LDFLAGS
make clean >/dev/null 2>&1 || true
./configure >/dev/null
make -j"$MAYHEM_JOBS" unittests/unittest
