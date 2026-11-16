# Driven by mayhem/build.sh (which exports the compiler, sanitizer and dependency variables).
CORE_SRCS := $(filter-out %.win.cpp %.test.cpp %.perf.test.cpp %/unit_test_driver.cpp,$(wildcard src/core/src/*.cpp))
OTHER_SRCS := $(filter-out %.win.cpp %.test.cpp,$(wildcard src/dev/utility/*.cpp src/dev/cpp/*.cpp src/plugins/tools.common/*.cpp))
C_SRCS := src/plugins/tools.common/http_parser.c
CXX_SRCS := $(CORE_SRCS) $(OTHER_SRCS)

DEFS := -DDSN_USE_THRIFT_SERIALIZATION -DDSN_ENABLE_THRIFT_RPC
INC := -Iinclude -Iinclude/dsn/cpp/serialization_helper -I$(THRIFT)/include -Isrc/core/src -Isrc/plugins/tools.common
CXXSTD := -std=c++14 -pthread -fPIC -Wno-everything
LIBS := $(THRIFT)/lib/libthrift.a -laio -lrt -ldl -lpthread -lboost_system -lm

SAN_OBJS := $(addprefix mayhem/build/san/,$(addsuffix .o,$(CXX_SRCS) $(C_SRCS))) mayhem/build/no_unit_tests.o

$(addprefix mayhem/build/san/,$(addsuffix .o,$(CORE_SRCS))): EXTRA := -DDSN_IN_CORE

# FIELD_OFFSET (include/dsn/utility/ports.h) takes the field address off a bogus (s*)10 pointer, which
# UBSan's alignment check reports on every CRC-enabled header. This is its only user.
mayhem/build/san/src/plugins/tools.common/dsn_message_parser.cpp.o: EXTRA += -fno-sanitize=alignment

# thrift's headers (instantiated in rDSN translation units) read wire bytes straight into TType
# enums, so UBSan's `enum` check fires on any malformed payload. Relaxed; ASan and the rest of
# UBSan stay on and halting.
RELAX := -fno-sanitize=enum
COV := -fsanitize=fuzzer-no-link $(RELAX)
SAN_CXX = $(CXX) $(SANITIZER_FLAGS) $(DEBUG_FLAGS) -O1
SAN_CC = $(CC) $(SANITIZER_FLAGS) $(DEBUG_FLAGS) -O1
PLAIN_CXX = $(CXX) -g -O2 $(COVERAGE_FLAGS)
PLAIN_CC = $(CC) -g -O2 $(COVERAGE_FLAGS)

mayhem/build/san/%.cpp.o: %.cpp mayhem/build.mk
	@mkdir -p $(@D)
	$(SAN_CXX) $(COV) $(CXXSTD) $(DEFS) $(EXTRA) $(INC) -c $< -o $@
mayhem/build/san/%.c.o: %.c mayhem/build.mk
	@mkdir -p $(@D)
	$(SAN_CC) $(COV) -fPIC -Wno-everything $(DEFS) $(INC) -c $< -o $@

mayhem/build/no_unit_tests.o: mayhem/no_unit_tests.cc
	@mkdir -p $(@D)
	$(CXX) $(SANITIZER_FLAGS) $(DEBUG_FLAGS) -c $< -o $@
# mayhem/build/lsan_off.o and mayhem/build/standalone_main.o are compiled by mayhem/build.sh

HARNESSES := $(basename $(notdir $(wildcard mayhem/fuzz_*.cc)))

define HARNESS_RULES
/mayhem/$(1): mayhem/$(1).cc $(SAN_OBJS) mayhem/build/lsan_off.o
	$(SAN_CXX) $(CXXSTD) $(DEFS) $(INC) $(RELAX) $(LIB_FUZZING_ENGINE) $$< $(SAN_OBJS) mayhem/build/lsan_off.o $(LIBS) -o $$@
/mayhem/$(1)-standalone: mayhem/$(1).cc $(SAN_OBJS) mayhem/build/lsan_off.o mayhem/build/standalone_main.o
	$(SAN_CXX) $(RELAX) $(CXXSTD) $(DEFS) $(INC) $$< mayhem/build/standalone_main.o $(SAN_OBJS) mayhem/build/lsan_off.o $(LIBS) -o $$@
endef
$(foreach h,$(HARNESSES),$(eval $(call HARNESS_RULES,$(h))))

all: $(addprefix /mayhem/,$(HARNESSES) $(addsuffix -standalone,$(HARNESSES))) suite
.PHONY: all

# ---- upstream's unit-test runtime, normal flags (mirrors the CMake modules bin/Linux/test.sh runs) ----
# libdsn.core.so: core sources + every core *.test.cpp + unit_test_driver.cpp, with the dev/cpp and
# dev/utility objects linked in (upstream's static dsn.dev.{cpp,utility}.core.use). Each plugin module
# links its own copy of the dev objects and libdsn.core.so, like upstream's dsn.dev.cpp/dsn.dev.utility.
# gtest and thrift are the shared builds, as upstream's ext/ links them, so all modules share one
# gtest registry. dsn.svchost loads the modules named in each test config's [modules].
SUITE := mayhem/build/suite
TEST_INC := -I$(GTEST)/include
SUITE_CXX = $(PLAIN_CXX) $(CXXSTD) $(DEFS) $(INC) $(TEST_INC)
SUITE_LDFLAGS := -L$(SUITE) -L$(THRIFT)/lib -L$(GTEST)/lib -Wl,-rpath,'$$ORIGIN' -Wl,-rpath,$(THRIFT)/lib -Wl,-rpath,$(GTEST)/lib
SUITE_SYSLIBS := -lthrift -lgtest -laio -lrt -ldl -lpthread -lboost_system -lm

src_of = $(filter-out %.win.cpp %.perf.test.cpp,$(wildcard $(1)/*.cpp $(1)/*.c))
suite_objs = $(addprefix $(SUITE)/obj/$(2)/,$(addsuffix .o,$(1)))

CORE_ALL := $(call src_of,src/core/src)
DEV_ALL := $(call src_of,src/dev/cpp) $(call src_of,src/dev/utility)
COMMON_ALL := $(call src_of,src/plugins/tools.common)
EMU_ALL := $(call src_of,src/plugins/tools.emulator) src/plugins/tools.common/native_aio_provider.posix.cpp
NFS_ALL := $(call src_of,src/plugins/tools.nfs)
URI_ALL := $(call src_of,src/plugins/dist.uri.resolver)

$(SUITE)/obj/core/%.cpp.o: %.cpp mayhem/build.mk
	@mkdir -p $(@D)
	$(SUITE_CXX) -DDSN_IN_CORE -c $< -o $@
$(SUITE)/obj/mod/%.cpp.o: %.cpp mayhem/build.mk
	@mkdir -p $(@D)
	$(SUITE_CXX) -Isrc/plugins/tools.common -c $< -o $@
$(SUITE)/obj/mod/%.c.o: %.c mayhem/build.mk
	@mkdir -p $(@D)
	$(PLAIN_CC) -fPIC -Wno-everything $(DEFS) $(INC) -c $< -o $@

CORE_DEV_OBJS := $(call suite_objs,$(DEV_ALL),core)
MOD_DEV_OBJS := $(call suite_objs,$(DEV_ALL),mod)

$(SUITE)/libdsn.core.so: $(call suite_objs,$(CORE_ALL),core) $(CORE_DEV_OBJS)
	$(PLAIN_CXX) -shared $^ $(SUITE_LDFLAGS) $(SUITE_SYSLIBS) -o $@

define SUITE_MODULE
$(SUITE)/libdsn.$(1).so: $(call suite_objs,$(2),mod) $(MOD_DEV_OBJS) $(SUITE)/libdsn.core.so
	$(PLAIN_CXX) -shared $(call suite_objs,$(2),mod) $(MOD_DEV_OBJS) $(SUITE_LDFLAGS) -ldsn.core $(SUITE_SYSLIBS) -o $$@
endef
$(eval $(call SUITE_MODULE,tools.common,$(COMMON_ALL)))
$(eval $(call SUITE_MODULE,tools.emulator,$(EMU_ALL)))
$(eval $(call SUITE_MODULE,tools.nfs,$(NFS_ALL)))
$(eval $(call SUITE_MODULE,dist.uri.resolver,$(URI_ALL)))

$(SUITE)/dsn.svchost: $(call suite_objs,src/tools/svchost/main.cpp,mod) $(MOD_DEV_OBJS) $(SUITE)/libdsn.core.so
	$(PLAIN_CXX) $(call suite_objs,src/tools/svchost/main.cpp,mod) $(MOD_DEV_OBJS) $(SUITE_LDFLAGS) -ldsn.core $(SUITE_SYSLIBS) -o $@

# dsn.idl.tests (src/tests/idl, upstream's MY_SERIALIZATION_TYPE thrift+protobuf executable linked to
# dsn.core): the thrift/protobuf serialization tests. Upstream's main() is renamed so that
# mayhem/idl_tests_main.cc can run its prepare() and the thrift_helper cases minus code generation.
IDL_DIR := src/tests/idl
IDL_CXX = $(SUITE_CXX) -DDSN_USE_PROTOBUF_SERIALIZATION -I$(PROTOBUF)/include -I$(IDL_DIR) \
  -DDSN_ROOT_DIR='"$(CURDIR)"' -DDSN_INSTALL_ROOT_DIR='"$(CURDIR)/$(SUITE)"' -DDSN_BUILD_DIR='"$(CURDIR)/$(SUITE)"'
IDL_OBJS := $(addprefix $(SUITE)/obj/idl/,idl_test.main.cpp.o idl_test_types.cpp.o idl_test.pb.cc.o idl_tests_main.cc.o)

$(SUITE)/obj/idl/idl_test.main.cpp.o: $(IDL_DIR)/idl_test.main.cpp mayhem/build.mk
	@mkdir -p $(@D)
	$(IDL_CXX) -Dmain=idl_upstream_main -c $< -o $@
$(SUITE)/obj/idl/%.o: $(IDL_DIR)/% mayhem/build.mk
	@mkdir -p $(@D)
	$(IDL_CXX) -c $< -o $@
$(SUITE)/obj/idl/idl_tests_main.cc.o: mayhem/idl_tests_main.cc mayhem/build.mk
	@mkdir -p $(@D)
	$(IDL_CXX) -c $< -o $@

$(SUITE)/dsn.idl.tests: $(IDL_OBJS) $(SUITE)/libdsn.core.so
	$(PLAIN_CXX) $(IDL_OBJS) $(SUITE_LDFLAGS) -ldsn.core $(PROTOBUF)/lib/libprotobuf.a $(SUITE_SYSLIBS) -o $@

suite: $(SUITE)/dsn.svchost $(SUITE)/dsn.idl.tests $(addprefix $(SUITE)/libdsn.,$(addsuffix .so,tools.common tools.emulator tools.nfs dist.uri.resolver))
.PHONY: suite
