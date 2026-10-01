import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shou_cang_gui/core/session_cache.dart';

void main() {
  test(
    'Shares in-flight requests, reuses URLs, and refreshes before expiry',
    () async {
      var now = DateTime(2026);
      final cache = SessionCache<String>(now: () => now);
      final request = Completer<String>();
      var calls = 0;
      Future<String> fetch() {
        calls++;
        return request.future;
      }

      final first = cache.get(
        'account:path',
        fetch,
        ttl: const Duration(minutes: 55),
      );
      final second = cache.get('account:path', fetch);
      expect(calls, 1);
      request.complete('url1');
      expect(await first, 'url1');
      expect(await second, 'url1');
      now = now.add(const Duration(minutes: 54));
      expect(await cache.get('account:path', fetch), 'url1');
      expect(calls, 1);
      now = now.add(const Duration(minutes: 1));
      expect(cache.peek('account:path'), isNull);
      expect(
        await cache.get('account:path', () async {
          calls++;
          return 'url2';
        }),
        'url2',
      );
      expect(calls, 2);
    },
  );

  test(
    'Invalidated work cannot replace a newer value; failures can retry',
    () async {
      final cache = SessionCache<String>();
      final request = Completer<String>();
      final pending = cache.get('path', () => request.future);
      cache.invalidate('path');
      cache.put('path', 'new');
      request.complete('old');
      await pending;
      expect(cache.peek('path'), 'new');
      await expectLater(
        cache.get('failed', () async => throw StateError('offline')),
        throwsStateError,
      );
      expect(await cache.get('failed', () async => 'retry'), 'retry');
      cache.clear();
      expect(cache.contains('path'), isFalse);
    },
  );
}
