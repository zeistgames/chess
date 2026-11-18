// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Linked into every single-threaded Emscripten engine port.
//
// 1. Threads run inline. A non-pthread Emscripten build cannot start a thread,
//    so pthread_create (and so std::thread) calls the start routine at once, on
//    the calling thread, and returns when it is done. An engine that starts a
//    search thread on `go` therefore searches to completion inside `go`, which
//    is what a one-line-at-a-time worker wants. `stop` cannot interrupt it.
//    Engines that park threads in an idle loop need their own patch instead.
//
// 2. zeist_uci(line) is the one exported entry: it hands one UCI line to the
//    engine's patched command handler, zeist_handle_line, then flushes output.

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <emscripten.h>

static uintptr_t zeist_next_thread = 0x1000;

int pthread_create(pthread_t *thread, const pthread_attr_t *attr, void *(*start)(void *), void *arg) {
  (void)attr;
  zeist_next_thread += 0x10;
  *thread = (pthread_t)zeist_next_thread;
  start(arg);
  return 0;
}

int pthread_join(pthread_t thread, void **retval) {
  (void)thread;
  if (retval) *retval = 0;
  return 0;
}

int pthread_detach(pthread_t thread) {
  (void)thread;
  return 0;
}

void zeist_handle_line(const char *line);
void zeist_flush_cxx(void);

EMSCRIPTEN_KEEPALIVE void zeist_uci(const char *line) {
  zeist_handle_line(line);
  zeist_flush_cxx();
  fflush(stdout);
  fflush(stderr);
}
