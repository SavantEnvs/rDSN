#!/usr/bin/env bash
#
# mayhem/build.sh — build rDSN's fuzz harnesses (sanitized), their standalone reproducers, and the
# project's own unit-test runtime (normal flags: libdsn.core.so + test modules + dsn.svchost).
# prefixes the Dockerfile builds under /opt/toolchains/deps; the upstream CMake build would fetch them.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
THRIFT=$(echo /opt/toolchains/deps/thrift-0.9.3-*)
GTEST=$(echo /opt/toolchains/deps/googletest-*)
PROTOBUF=/opt/toolchains/deps/protobuf-3.0.0
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS STANDALONE_FUZZ_MAIN THRIFT GTEST PROTOBUF

cd "$SRC"
mkdir -p mayhem/build
# LeakSanitizer off for every fuzz/standalone binary; the standalone driver is compiled as C so
# clang++ doesn't mangle its LLVMFuzzerTestOneInput reference.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o mayhem/build/lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o mayhem/build/standalone_main.o
make -f mayhem/build.mk -j"$MAYHEM_JOBS" all
