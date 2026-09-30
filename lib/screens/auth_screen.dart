import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_theme.dart';
import '../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_register) {
        final response = await widget.auth.signUp(_email.text, _password.text);
        if (response.session == null && mounted) {
          setState(() {
            _message = '注册成功。请查收确认邮件，然后返回登录。';
            _register = false;
          });
        }
      } else {
        await widget.auth.signIn(_email.text, _password.text);
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = '暂时无法连接，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    var entered = _email.text.trim();
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('找回密码'),
        content: TextFormField(
          initialValue: entered,
          onChanged: (value) => entered = value.trim(),
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: '注册邮箱'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, entered),
            child: const Text('发送重置邮件'),
          ),
        ],
      ),
    );
    if (email == null) return;
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _message = '请输入有效邮箱');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.auth.requestPasswordReset(email);
      if (mounted) setState(() => _message = '如果邮箱已注册，重置邮件已发送，请在手机上打开邮件中的链接。');
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = '暂时无法发送，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.collections_bookmark_rounded,
                    color: AppTheme.accent,
                    size: 48,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    '给喜欢的东西，一个长久的位置。',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700, height: 1.25),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '你的私人数字收藏柜，记录物品，也记录与它们有关的故事。',
                    style: TextStyle(color: AppTheme.muted, height: 1.6),
                  ),
                  const SizedBox(height: 42),
                  Text(
                    _register ? '创建账号' : '欢迎回来',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: '邮箱'),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      return email.contains('@') && email.contains('.')
                          ? null
                          : '请输入有效邮箱';
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: [
                      _register
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    decoration: const InputDecoration(labelText: '密码'),
                    validator: (value) =>
                        (value?.length ?? 0) >= 6 ? null : '密码至少需要 6 位',
                    onFieldSubmitted: (_) => _busy ? null : _submit(),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _message!,
                      style: TextStyle(
                        color:
                            _message!.startsWith('注册成功') ||
                                _message!.startsWith('如果邮箱已注册')
                            ? AppTheme.accent
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(
                        _busy
                            ? '请稍候…'
                            : _register
                            ? '注册并开始收藏'
                            : '登录我的收藏柜',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!_register)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _forgotPassword,
                        child: const Text('忘记密码？'),
                      ),
                    ),
                  Center(
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _register = !_register;
                              _message = null;
                            }),
                      child: Text(_register ? '已有账号？去登录' : '还没有账号？创建一个'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
