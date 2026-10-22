import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';

/// 登入方式: the ways this account signs in, a Google or Apple account to
/// link, whatever its email, and unlinking any but the last. Linked or not, it stays the one
/// account: churches, rosters and roles do not change.
class SignInMethodsScreen extends ConsumerStatefulWidget {
  const SignInMethodsScreen({super.key});

  @override
  ConsumerState<SignInMethodsScreen> createState() => _SignInMethodsScreenState();
}

class _SignInMethodsScreenState extends ConsumerState<SignInMethodsScreen> {
  bool _busy = false;

  /// Being linked: its row shows so while the link goes on.
  SignInMethod? _linking;

  Future<void> _run(Future<void> Function() action, {String? done, SignInMethod? linking}) async {
    final l10n = L10n.of(context);
    setState(() {
      _busy = true;
      _linking = linking;
    });
    try {
      await action();
      Haptics.success();
      if (mounted && done != null) showToast(context, done);
    } catch (e) {
      // Closing Google's or Apple's sheet has nothing to say.
      final text = errorText(l10n, e);
      if (mounted && text.isNotEmpty) showToast(context, text);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _linking = null;
        });
      }
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
    bool linked(SignInMethod m) => signIns.any((s) => s.method == m);
    final toLink = [
      if (!linked(SignInMethod.google))
        (method: SignInMethod.google, title: l10n.linkGoogle, link: auth.linkGoogle, done: l10n.linkedGoogle),
      if (auth.offersApple && !linked(SignInMethod.apple))
        (method: SignInMethod.apple, title: l10n.linkApple, link: auth.linkApple, done: l10n.linkedApple),
    ];
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
          if (toLink.isNotEmpty)
            ListSection(
              footer: l10n.linkFooter,
              children: [
                for (final (:method, :title, :link, :done) in toLink)
                  ListRow(
                    title: title,
                    // Linking goes on after Google's or Apple's sheet closes.
                    trailing: _linking == method
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator.adaptive(strokeWidth: 2.5),
                          )
                        : null,
                    onTap: _busy ? null : () => _run(link, done: done, linking: method),
                  ),
              ],
            ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }
}
