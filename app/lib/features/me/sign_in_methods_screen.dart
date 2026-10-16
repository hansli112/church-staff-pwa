import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';

/// 登入方式: the ways this account signs in, a Google account to link, whatever
/// its email, and unlinking any but the last. Linked or not, it stays the one
/// account: churches, rosters and roles do not change.
class SignInMethodsScreen extends ConsumerStatefulWidget {
  const SignInMethodsScreen({super.key});

  @override
  ConsumerState<SignInMethodsScreen> createState() => _SignInMethodsScreenState();
}

class _SignInMethodsScreenState extends ConsumerState<SignInMethodsScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    final l10n = L10n.of(context);
    setState(() => _busy = true);
    try {
      await action();
      Haptics.success();
      if (mounted && done != null) showToast(context, done);
    } catch (e) {
      // Closing Google's sheet has nothing to say.
      final text = errorText(l10n, e);
      if (mounted && text.isNotEmpty) showToast(context, text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _name(L10n l10n, SignInMethod method) => switch (method) {
    SignInMethod.password => l10n.signInMethodPassword,
    SignInMethod.google => 'Google',
    SignInMethod.apple => 'Apple',
  };

  Future<void> _unlink(SignIn s) async {
    final l10n = L10n.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.unlinkTitle(_name(l10n, s.method)),
      message: l10n.unlinkBody(s.email),
      action: l10n.unlink,
    );
    if (!ok || !mounted) return;
    await _run(() => ref.read(backendProvider).auth.unlink(s.method));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final auth = ref.read(backendProvider).auth;
    final signIns = ref.watch(authUserProvider.select((u) => u.value?.signIns ?? const <SignIn>[]));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.signInMethods)),
      body: ListView(
        children: [
          ListSection(
            footer: l10n.signInMethodsFooter,
            children: [
              for (final s in signIns)
                ListRow(
                  title: _name(l10n, s.method),
                  subtitle: s.email.isEmpty ? null : s.email,
                  // Never the last way in.
                  trailing: signIns.length < 2
                      ? null
                      : TextButton(
                          style: TextButton.styleFrom(foregroundColor: c.destructive),
                          onPressed: _busy ? null : () => _unlink(s),
                          child: Text(l10n.unlink),
                        ),
                ),
            ],
          ),
          if (!signIns.any((s) => s.method == SignInMethod.google))
            ListSection(
              footer: l10n.linkGoogleFooter,
              children: [
                ListRow(
                  title: l10n.linkGoogle,
                  onTap: _busy ? null : () => _run(auth.linkGoogle, done: l10n.linkedGoogle),
                ),
              ],
            ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }
}
