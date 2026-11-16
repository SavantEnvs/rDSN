# syntax=docker/dockerfile:1.7
# Commit image for rDSN: org C/C++ base + build deps + a pinned thrift/googletest, then mayhem/build.sh.
FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

# rDSN's own CMake build downloads thrift/gtest from the unpinned `master` of linmajia's forks and
# links boost-system/asio and libaio.
USER root
RUN [ -n "$SOURCE_DATE_EPOCH" ] && repro-sources-list.sh || true ; \
    apt-get update && apt-get install -yq --no-install-recommends \
        libboost-dev libboost-system-dev libaio-dev \
 && rm -rf /var/lib/apt/lists/*

# thrift (linmajia fork, the one rDSN's ext/thrift fetches), pinned, uninstrumented: static for the
# fuzzers, shared (as upstream links it) for the unit-test runtime.
ARG THRIFT_SHA=7f8e14a140e0a4e7e2718049ef5291d76491d0d2
RUN d=/opt/toolchains/deps/thrift-0.9.3-${THRIFT_SHA} && mkdir -p "$d/src" /tmp/dep-build \
 && cd "$d/src" && git init -q . \
 && git fetch -q --depth 1 https://github.com/linmajia/thrift.git "${THRIFT_SHA}" \
 && git checkout -q FETCH_HEAD && rm -rf .git && cd /tmp/dep-build \
 && cmake -S "$d/src" -B . -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$d" \
        -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_CXX_FLAGS="-g -gdwarf-3 -Wno-everything" -DCMAKE_C_FLAGS="-g -gdwarf-3 -Wno-everything" \
        -DBUILD_COMPILER=OFF -DBUILD_TESTING=OFF -DBUILD_TUTORIALS=OFF -DBUILD_EXAMPLES=OFF \
        -DBUILD_CPP=ON -DWITH_OPENSSL=OFF -DWITH_ZLIB=OFF -DWITH_LIBEVENT=OFF -DWITH_SHARED_LIB=ON \
        -DWITH_STATIC_LIB=ON -DWITH_BOOSTTHREADS=OFF -DWITH_STDTHREADS=OFF \
        -DWITH_C_GLIB=OFF -DWITH_JAVA=OFF -DWITH_PYTHON=OFF -DWITH_QT4=OFF -DWITH_QT5=OFF \
        -DWITH_NODEJS=OFF -DWITH_JAVASCRIPT=OFF \
 && cmake --build . -j"$(nproc)" && cmake --install . \
 && cd / && rm -rf /tmp/dep-build && chmod -R a+rX "$d"

# googletest (linmajia fork, pinned) for the project's own unit tests; shared, like upstream's
# ext/gtest, so every test module registers its cases with the one gtest registry in dsn.core.
ARG GTEST_SHA=8c710c28084e095a161acfcea247a747bd6abada
RUN d=/opt/toolchains/deps/googletest-${GTEST_SHA} && mkdir -p "$d/src" /tmp/dep-build \
 && cd "$d/src" && git init -q . \
 && git fetch -q --depth 1 https://github.com/linmajia/googletest.git "${GTEST_SHA}" \
 && git checkout -q FETCH_HEAD && rm -rf .git \
 && mkdir -p "$d/lib" /tmp/dep-build && cd /tmp/dep-build \
 && clang++ -O2 -g -gdwarf-3 -std=c++14 -pthread -I"$d/src" -I"$d/src/include" \
        -fPIC -c "$d/src/src/gtest-all.cc" -o gtest-all.o \
 && ar rcs "$d/lib/libgtest.a" gtest-all.o \
 && clang++ -shared -pthread gtest-all.o -o "$d/lib/libgtest.so" && ln -s src/include "$d/include" \
 && cd / && rm -rf /tmp/dep-build && chmod -R a+rX "$d"

# protobuf 3.0.0 (linmajia fork's master, pinned), uninstrumented, static + PIC like upstream's
# ext/protobuf: src/tests/idl (dsn.idl.tests) includes the protoc-3.0.0-generated idl_test.pb.h.
ARG PROTOBUF_SHA=5bb4a4780829bbd9cb4b6978e130bf0621183166
RUN d=/opt/toolchains/deps/protobuf-3.0.0 && mkdir -p "$d/src" /tmp/dep-build \
 && cd "$d/src" && git init -q . \
 && git fetch -q --depth 1 https://github.com/linmajia/protobuf.git "${PROTOBUF_SHA}" \
 && git checkout -q FETCH_HEAD && rm -rf .git && cd /tmp/dep-build \
 && cmake -S "$d/src/cmake" -B . -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$d" \
        -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_CXX_STANDARD=11 -DCMAKE_CXX_FLAGS="-g -gdwarf-3 -Wno-everything" \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON -Dprotobuf_BUILD_TESTS=OFF -DBUILD_SHARED_LIBS=OFF \
 && cmake --build . -j"$(nproc)" && cmake --install . \
 && cd / && rm -rf /tmp/dep-build && chmod -R a+rX "$d"
USER mayhem

WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
