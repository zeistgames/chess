// SPDX-License-Identifier: AGPL-3.0-or-later
#include <iostream>
extern "C" void zeist_flush_cxx(void) {
  std::cout.flush();
  std::cerr.flush();
}
