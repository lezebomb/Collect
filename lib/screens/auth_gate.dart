import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import 'auth_screen.dart';
import 'collection_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthService _auth = AuthService(Supabase.instance.client);
  late final StreamSubscription<AuthState> _subscription;
  late bool _signedIn = _auth.currentSession != null;

  @override
  void initState() {
    super.initState();
    _subscription = _auth.changes.listen(
      (state) {
        if (mounted) setState(() => _signedIn = state.session != null);
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('Auth state error: $error');
      },
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _signedIn ? const CollectionScreen() : AuthScreen(auth: _auth);
}
