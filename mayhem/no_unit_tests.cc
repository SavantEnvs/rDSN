// rDSN's main.cpp calls these two hooks, which live in unit_test_driver.cpp (a gtest-linked file that
// only does anything with `[core] gtest = true`). The fuzz binaries don't link gtest, so no-op them.
void run_all_unit_tests_prepare_when_necessary() {}
void run_all_unit_tests_when_necessary() {}
