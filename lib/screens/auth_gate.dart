import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../core/app_access.dart';
import 'auth_screen.dart';
import 'collection_screen.dart';
import 'password_recovery_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthService _auth = AuthService(Supabase.instance.client);
  late final StreamSubscription<AuthState> _subscription;
  late bool _signedIn = _auth.currentSession != null;
  bool _recovering = false;
  Future<bool>? _access;
  String? _accessOwner;

  void _checkAccess() {
    _accessOwner = _auth.currentUser?.id;
    _access = _accessOwner == null ? null : AppAccess(_auth.client).allowed();
  }

  @override
  void initState() {
    super.initState();
    _checkAccess();
    _subscription = _auth.changes.listen(
      (state) {
        if (mounted) {
          setState(() {
            _signedIn = state.session != null;
            if (_accessOwner != state.session?.user.id ||
                state.event == AuthChangeEvent.signedIn) {
              _checkAccess();
            }
            if (state.event == AuthChangeEvent.passwordRecovery) {
              _recovering = true;
            } else if (state.event == AuthChangeEvent.signedOut) {
              _recovering = false;
            }
          });
        }
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
  Widget build(BuildContext context) => _recovering
      ? PasswordRecoveryScreen(
          auth: _auth,
          onComplete: () => setState(() => _recovering = false),
        )
      : _signedIn
      ? FutureBuilder<bool>(
          future: _access,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.data == true) {
              return CollectionScreen(
                key: ValueKey(_auth.currentSession?.user.id),
              );
            }
            return Scaffold(
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          snapshot.hasError
                              ? '暂时无法验证访问权限，请检查网络后重试。'
                              : '此应用仅向获准的邮箱开放。请确认邮箱已验证，并联系管理员添加白名单。',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: () => setState(_checkAccess),
                          child: const Text('重新检查'),
                        ),
                        TextButton(
                          onPressed: _auth.signOut,
                          child: const Text('退出登录'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        )
      : AuthScreen(auth: _auth);
}
