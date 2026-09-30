import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService(this.client);

  static const recoveryRedirect = 'collect://auth/recovery';

  final SupabaseClient client;

  User? get currentUser => client.auth.currentUser;
  Session? get currentSession => client.auth.currentSession;
  Stream<AuthState> get changes => client.auth.onAuthStateChange;

  Future<AuthResponse> signUp(String email, String password) =>
      client.auth.signUp(email: email.trim(), password: password);

  Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() => client.auth.signOut();

  Future<void> requestPasswordReset(String email) => client.auth
      .resetPasswordForEmail(email.trim(), redirectTo: recoveryRedirect);

  Future<void> updatePassword(String password) =>
      client.auth.updateUser(UserAttributes(password: password)).then((_) {});
}
