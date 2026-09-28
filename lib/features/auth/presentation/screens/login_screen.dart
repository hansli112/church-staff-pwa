import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/config/church_config.dart';
import '../providers/session_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      final session = context.read<SessionProvider>();
      await session.login(_usernameController.text, _passwordController.text);
    }
  }

  Future<void> _showForgotPassword() async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _ForgotPasswordDialog(initialEmail: _usernameController.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 32,
                right: 32,
                top: 24,
                bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                ChurchConfig.current.appName,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 32),
                              TextFormField(
                                controller: _usernameController,
                                // 登入走 Firebase Email/Password，只收 email；寫「帳號」
                                // 會讓第一次登入的管理員不知道該填什麼。
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.person),
                                ),
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                textInputAction: TextInputAction.next,
                                onFieldSubmitted: (_) =>
                                    FocusScope.of(context).nextFocus(),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return '請輸入 Email';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passwordController,
                                decoration: InputDecoration(
                                  labelText: '密碼',
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.lock),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                    ),
                                    tooltip: _obscurePassword ? '顯示密碼' : '隱藏密碼',
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                ),
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return '請輸入密碼';
                                  }
                                  return null;
                                },
                                onFieldSubmitted: (_) => _handleLogin(),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _showForgotPassword,
                                  child: const Text('忘記密碼？'),
                                ),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: FilledButton(
                                  onPressed: session.isLoading
                                      ? null
                                      : _handleLogin,
                                  child: session.isLoading
                                      ? const SizedBox(
                                          height: 24,
                                          width: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text('登入'),
                                ),
                              ),
                              if (session.error != null) ...[
                                const SizedBox(height: 16),
                                Text(
                                  session.error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 寄重設密碼信。新密碼是在信裡的 Firebase 頁面設定，不在 App 裡。
class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(
    text: widget.initialEmail,
  );
  bool _isSending = false;
  String? _error;
  String? _sentTo;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_isSending || !_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    setState(() {
      _isSending = true;
      _error = null;
    });
    final error = await context.read<SessionProvider>().sendPasswordReset(
      email,
    );
    if (!mounted) return;
    setState(() {
      _isSending = false;
      _error = error;
      if (error == null) _sentTo = email;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sentTo = _sentTo;
    if (sentTo != null) {
      // Firebase 不告訴我們這個 Email 有沒有帳號，所以話只能說到「如果有」。
      return AlertDialog(
        title: const Text('請到信箱收信'),
        content: Text(
          '如果 $sentTo 有帳號，重設密碼的信已經寄出。'
          '點信裡的連結設定新密碼，再回來登入。\n\n'
          '幾分鐘內沒收到的話，看一下垃圾郵件；還是沒有就請管理員確認帳號的 Email。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('好'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('忘記密碼'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('輸入登入用的 Email，我們會寄一封重設密碼的信給你。'),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              autofocus: widget.initialEmail.isEmpty,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.send,
              onFieldSubmitted: (_) => _send(),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '請輸入 Email' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isSending ? null : _send,
          child: _isSending
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('寄出'),
        ),
      ],
    );
  }
}
