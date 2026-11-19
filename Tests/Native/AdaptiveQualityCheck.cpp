#include "adaptive_quality.h"
#include <cassert>
#include <cstdio>
int main() {
  video::AdaptiveQuality q;
  assert(!q.request(1, 2000));
  const auto session = q.begin(8000);
  assert(q.snapshot().maximum == 8000);
  assert(q.snapshot().applied == 0);
  q.applied(session, 8000);
  assert(!q.request(session, 999));
  assert(!q.request(session, 9000));
  assert(q.request(session, 4000));
  assert(q.target(session) == 4000);
  assert(q.snapshot().applied == 8000);
  q.applied(session, 4000);
  assert(q.snapshot().applied == 4000);
  q.end(session);
  assert(!q.request(session, 2000));
  const auto newer = q.begin(2000);
  assert(newer != session);
  q.end(session);
  assert(q.snapshot().session == newer);
  assert(!q.request(session, 1000));
  assert(q.request(newer, 1000));
  q.failed(newer);
  assert(q.target(newer) == 2000);
  assert(!q.request(newer, 1000));
  assert(q.snapshot().failed);
  puts("PASS: bounded adaptive bitrate, applied acknowledgment, stale session and failure fallback");
}
