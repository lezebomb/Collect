import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_theme.dart';
import 'screens/auth_gate.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_supabaseUrl.isNotEmpty && _publishableKey.isNotEmpty) {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _publishableKey,
    );
  }
  runApp(const CollectionApp());
}

class CollectionApp extends StatelessWidget {
  const CollectionApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Dearshelf',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: _supabaseUrl.isEmpty || _publishableKey.isEmpty
        ? const _MissingConfiguration()
        : const AuthGate(),
  );
}

class _MissingConfiguration extends StatelessWidget {
  const _MissingConfiguration();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '请先配置 Supabase 项目 URL 和 Publishable Key。\n'
            '参见 README.md 中的启动步骤。',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
