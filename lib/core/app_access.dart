import 'package:supabase_flutter/supabase_flutter.dart';

/// Server-side RLS remains authoritative. The gate gives a clear explanation
/// before attempting to load a private collection.
class AppAccess {
  AppAccess(
    this.client, {
    this.requirePrivateAccess = enabledByDefault,
    this.requireEmailAccess = emailAccessByDefault,
  });

  /// Keep private access on unless a pre-migration phone preview explicitly
  /// opts out at build time. Missing RPCs and network errors never opt out.
  static const enabledByDefault = bool.fromEnvironment(
    'COLLECTION_PRIVATE_ACCESS',
    defaultValue: true,
  );

  /// Membership is independent of the optional cover reservation rollout.
  static const emailAccessByDefault = bool.fromEnvironment(
    'COLLECTION_EMAIL_ALLOWLIST',
    defaultValue: true,
  );

  final SupabaseClient client;
  final bool requirePrivateAccess;
  final bool requireEmailAccess;

  Future<bool> allowed() async {
    if (!requirePrivateAccess && !requireEmailAccess) {
      return client.auth.currentUser != null;
    }
    if (requireEmailAccess &&
        !await client.rpc<bool>('collection_email_access_allowed')) {
      return false;
    }
    return requirePrivateAccess
        ? client.rpc<bool>('collection_access_allowed')
        : true;
  }

  Future<void> reserveCover(String path) async {
    if (requirePrivateAccess) {
      await client.rpc(
        'reserve_collection_cover',
        params: {'object_path': path},
      );
    }
  }

  Future<void> releaseCover(String path) async {
    if (requirePrivateAccess) {
      await client.rpc(
        'release_collection_cover',
        params: {'object_path': path},
      );
    }
  }
}
