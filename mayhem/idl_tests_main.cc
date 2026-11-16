// Entry point for upstream's dsn.idl.tests (src/tests/idl), as built by mayhem/build.mk.
//
// Upstream's main() (idl_test.main.cpp, compiled here with -Dmain=idl_upstream_main) runs prepare()
// and then forces --gtest_filter=thrift_helper.*. This main does the same, but leaves out the three
// thrift_helper.*code_generation* cases: they run the thrift compiler, CMake and a C++/JS build of a
// generated project at test time, and the image has no thrift compiler. Every other thrift_helper
// case (the thrift binary/JSON marshall/unmarshall round-trips and the golden-JSON compatibility
// check) runs unchanged.
#include <gtest/gtest.h>

bool prepare();

int main(int argc, char **argv)
{
    if (!prepare())
        return 1;

    const char *args[] = {"dsn.idl.tests", "--gtest_filter=thrift_helper.*:-*code_generation*"};
    int args_count = static_cast<int>(sizeof(args) / sizeof(args[0]));
    ::testing::InitGoogleTest(&args_count, (char **)&args[0]);
    return RUN_ALL_TESTS();
}
