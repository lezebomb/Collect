/// Shares in-flight work and completed values during one signed-in session.
class SessionCache<T> {
  SessionCache({DateTime Function()? now, this.capacity = 300})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final int capacity;
  final _entries = <String, _Entry<T>>{};

  bool contains(String key) => _entry(key) != null;
  T? peek(String key) => _entry(key)?.value;

  _Entry<T>? _entry(String key) {
    final entry = _entries[key];
    if (entry?.expiresAt case final expiry?) {
      if (!_now().isBefore(expiry)) {
        _entries.remove(key);
        return null;
      }
    }
    return entry;
  }

  Future<T> get(String key, Future<T> Function() fetch, {Duration? ttl}) {
    final cached = _entry(key);
    if (cached != null) return cached.future;
    final entry = _Entry<T>();
    _insert(key, entry);
    entry.future = Future<T>.sync(fetch).then(
      (value) {
        entry.value = value;
        entry.expiresAt = ttl == null ? null : _now().add(ttl);
        return value;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_entries[key], entry)) _entries.remove(key);
        Error.throwWithStackTrace(error, stack);
      },
    );
    return entry.future;
  }

  void put(String key, T value) {
    _insert(
      key,
      _Entry<T>()
        ..value = value
        ..future = Future.value(value),
    );
  }

  void _insert(String key, _Entry<T> entry) {
    _entries.remove(key);
    _entries[key] = entry;
    if (_entries.length > capacity) _entries.remove(_entries.keys.first);
  }

  void invalidate(String key) => _entries.remove(key);
  void clear() => _entries.clear();
}

class _Entry<T> {
  late Future<T> future;
  T? value;
  DateTime? expiresAt;
}
