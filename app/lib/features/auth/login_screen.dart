import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';

/// Sign-in. Google is the main way in, so it is the one prominent button;
/// email and password sit below it.
///
/// Self-host showed a username/password form first and had no Google
/// sign-in. Here the form only appears when asked for.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _Mode { choose, signIn, register }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  _Mode _mode = _Mode.choose;
  bool _busy = false;
  String? _error;
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  AuthGateway get _auth => ref.read(backendProvider).auth;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      final text = errorText(L10n.of(context), e);
      setState(() => _error = text.isEmpty ? null : text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    _run(
      () => _mode == _Mode.register
          ? _auth.registerWithEmail(_name.text, _email.text, _password.text)
          : _auth.signInWithEmail(_email.text, _password.text),
    );
  }

  Future<void> _forgot() async {
    final l10n = L10n.of(context);
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = l10n.emailRequired);
      return;
    }
    await _run(() => _auth.sendPasswordReset(email));
    if (mounted && _error == null) showToast(context, l10n.resetSent(email));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    return Scaffold(
      appBar: _mode == _Mode.choose
          ? null
          : AppBar(
              leading: BackButton(
                onPressed: () => setState(() {
                  _mode = _Mode.choose;
                  _error = null;
                }),
              ),
            ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _mode == _Mode.choose
                ? _choose(l10n, c)
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(Space.l),
                    children: [_emailForm(l10n), ..._errorText(c)],
                  ),
          ),
        ),
      ),
    );
  }

  /// One group, centred: icon, name, the verse quietly under it, then the
  /// sign-in buttons. Scrolls when large text needs the room.
  Widget _choose(L10n l10n, AppColors c) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset('assets/icons/app.png', width: 88, height: 88, excludeFromSemantics: true),
              ),
            ),
            const SizedBox(height: Space.m),
            Text(l10n.appName, textAlign: TextAlign.center, style: AppText.largeTitle),
            const SizedBox(height: Space.m),
            // Narrow enough that the lines come out about even.
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Text(
                  l10n.loginTagline,
                  textAlign: TextAlign.center,
                  style: AppText.subheadline.copyWith(color: c.secondaryLabel, height: 1.5),
                ),
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(
              l10n.loginTaglineSource,
              textAlign: TextAlign.center,
              style: AppText.footnote.copyWith(color: c.secondaryLabel),
            ),
            const SizedBox(height: Space.xxl),
            PrimaryButton(
              label: l10n.signInWithGoogle,
              busy: _busy,
              onPressed: () => _run(_auth.signInWithGoogle),
            ),
            const SizedBox(height: Space.s),
            SecondaryButton(
              label: l10n.signInWithEmail,
              expand: true,
              onPressed: _busy ? null : () => setState(() => _mode = _Mode.signIn),
            ),
            ..._errorText(c),
          ],
        ),
      ),
    );
  }

  List<Widget> _errorText(AppColors c) => [
    if (_error != null) ...[
      const SizedBox(height: Space.m),
      Semantics(
        liveRegion: true,
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: AppText.subheadline.copyWith(color: c.destructive),
        ),
      ),
    ],
  ];

  Widget _emailForm(L10n l10n) {
    final register = _mode == _Mode.register;
    return Form(
      key: _form,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              register ? l10n.createAccount : l10n.signIn,
              style: AppText.title,
            ),
            const SizedBox(height: Space.l),
            if (register) ...[
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: InputDecoration(hintText: l10n.yourName),
                validator: (v) => (v ?? '').trim().isEmpty ? l10n.nameRequired : null,
              ),
              const SizedBox(height: Space.s),
            ],
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(hintText: l10n.email),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return l10n.emailRequired;
                if (!t.contains('@')) return l10n.errInvalidEmail;
                return null;
              },
            ),
            const SizedBox(height: Space.s),
            TextFormField(
              controller: _password,
              obscureText: true,
              textInputAction: TextInputAction.done,
              autofillHints: [
                register ? AutofillHints.newPassword : AutofillHints.password,
              ],
              decoration: InputDecoration(hintText: l10n.password),
              onFieldSubmitted: (_) => _submit(),
              validator: (v) => register && (v ?? '').length < 6 ? l10n.errWeakPassword : null,
            ),
            const SizedBox(height: Space.l),
            PrimaryButton(
              label: register ? l10n.register : l10n.signIn,
              busy: _busy,
              onPressed: _submit,
            ),
            const SizedBox(height: Space.s),
            SecondaryButton(
              label: register ? l10n.haveAccount : l10n.createAccount,
              expand: true,
              onPressed: () => setState(() {
                _mode = register ? _Mode.signIn : _Mode.register;
                _error = null;
              }),
            ),
            if (!register) ...[
              SecondaryButton(
                label: l10n.forgotPassword,
                expand: true,
                onPressed: _busy ? null : _forgot,
              ),
              const SizedBox(height: Space.m),
              Text(
                l10n.movedPasswordNote,
                textAlign: TextAlign.center,
                style: AppText.footnote.copyWith(color: AppColors.of(context).secondaryLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
