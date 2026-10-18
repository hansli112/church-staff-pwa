import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../core/languages.dart';
import '../../data/backend.dart';
import '../../deep_link.dart';
import '../../env.dart';
import '../../domain/limits.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/web_page.dart';
import '../church/links.dart';
import '../common/errors.dart';
import 'in_app_browser.dart';

/// Sign-in. Google and, where the build offers it, Apple (App Store 4.8)
/// are two white buttons of one size, each with its own mark as its maker's
/// guidelines ask; Apple first in the iPhone app, where everyone has an
/// Apple Account, Google first on Android and the web. Email and password sit below.
///
/// Self-host showed a username/password form first and had no Google
/// sign-in. Here the form only appears when asked for.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.from});

  /// Where sign-in continues to. An invite link names its church here.
  final String? from;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _Mode { choose, signIn, register }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  _Mode _mode = _Mode.choose;
  bool _busy = false;

  /// The Apple button shows the spinner while Apple's sheet is up; the
  /// Google button does otherwise.
  bool _appleRunning = false;
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

  Future<void> _run(Future<void> Function() action, {bool apple = false}) async {
    setState(() {
      _busy = true;
      _appleRunning = apple;
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
          ? _auth.registerWithEmail(_name.text, _email.text, _password.text, AppLanguage.shownIn(context))
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
    final language = AppLanguage.shownIn(context);
    await _run(() => _auth.sendPasswordReset(email, language));
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

  /// One group, centred: icon, name, the verse under it, then the sign-in
  /// buttons. Scrolls when large text needs the room.
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
            BalancedText(l10n.appName, style: AppText.largeTitle),
            const SizedBox(height: Space.m),
            _verse(l10n, c),
            const SizedBox(height: Space.xxl),
            if (_invitedTo() case final church?) ...[
              BalancedText(l10n.loginInvitedTo(church), style: AppText.headline),
              const SizedBox(height: Space.m),
            ],
            if (inAppBrowser(ref.watch(userAgentProvider)) case final app?) ...[
              _InAppBrowserNote(app: app, url: _pageToOpen()),
              const SizedBox(height: Space.m),
            ],
            for (final button in _providerButtons(l10n)) ...[button, const SizedBox(height: Space.s)],
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

  List<Widget> _providerButtons(L10n l10n) {
    final google = _SignInButton(
      label: l10n.signInWithGoogle,
      markSize: 20,
      mark: (size) => Image.asset('assets/icons/google_g.png', width: size, height: size, excludeFromSemantics: true),
      foreground: const Color(0xFF1F1F1F), // Google's text colour
      busy: _busy && !_appleRunning,
      onPressed: _busy ? null : () => _run(_auth.signInWithGoogle),
    );
    if (!_auth.offersApple) return [google];
    final apple = _SignInButton(
      label: l10n.signInWithApple,
      markSize: 22,
      mark: (size) => Icon(Icons.apple, size: size),
      foreground: Colors.black, // Apple allows only black or white
      busy: _busy && _appleRunning,
      onPressed: _busy ? null : () => _run(_auth.signInWithApple, apple: true),
    );
    final applePlatform =
        !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);
    return applePlatform ? [apple, google] : [google, apple];
  }

  /// The address to open in the phone's browser: the page sign-in leads to
  /// (an invite link, a church's page), which carries the church's name and
  /// icon, rather than this one.
  String _pageToOpen() {
    final from = appLocation(widget.from);
    return from == null ? Uri.base.toString() : '${Env.current.webOrigin}$from';
  }

  /// The church name of the invite being opened, once it has loaded.
  String? _invitedTo() {
    final code = inviteCodeIn(widget.from ?? '');
    if (code == null) return null;
    final name = ref.watch(invitedChurchProvider(code)).value;
    return name == null || name.isEmpty ? null : name;
  }

  /// The verse, a short rule, then where it is from.
  Widget _verse(L10n l10n, AppColors c) {
    return Column(
      children: [
        BalancedText(l10n.loginTagline, style: AppText.subheadline.copyWith(color: c.secondaryLabel, height: 1.6)),
        const SizedBox(height: Space.s),
        Container(width: 20, height: 1, color: c.separator),
        const SizedBox(height: Space.s),
        BalancedText(
          l10n.loginTaglineSource,
          style: AppText.footnote.copyWith(color: c.secondaryLabel, letterSpacing: 1),
        ),
      ],
    );
  }

  List<Widget> _errorText(AppColors c) => [
    if (_error != null) ...[
      const SizedBox(height: Space.m),
      Semantics(
        liveRegion: true,
        child: BalancedText(_error!, style: AppText.subheadline.copyWith(color: c.destructive)),
      ),
    ],
  ];

  Widget _emailForm(L10n l10n) {
    final register = _mode == _Mode.register;
    return Form(
      key: _form,
      // An error goes away as soon as the field is fixed, not on the next submit.
      autovalidateMode: AutovalidateMode.onUserInteractionIfError,
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
                maxLength: TextLimits.profileName,
                decoration: InputDecoration(labelText: l10n.yourName),
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
              decoration: InputDecoration(labelText: l10n.email),
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
              decoration: InputDecoration(labelText: l10n.password),
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
              BalancedText(
                l10n.movedPasswordNote,
                style: AppText.footnote.copyWith(color: AppColors.of(context).secondaryLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A sign-in button in the style Google and Apple both allow: white, the
/// maker's mark before the title, and a thin grey border on light
/// backgrounds. White in dark mode too, without the border: Apple's outline
/// is only for light backgrounds, and Google's G sits on white.
class _SignInButton extends StatelessWidget {
  const _SignInButton({
    required this.label,
    required this.markSize,
    required this.mark,
    required this.foreground,
    required this.busy,
    required this.onPressed,
  });

  final String label;

  /// The maker's mark, drawn at [markSize] grown with the text size.
  final double markSize;
  final Widget Function(double size) mark;
  final Color foreground;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: foreground,
      // Disabled only while the other button runs: keep the colours.
      disabledBackgroundColor: Colors.white,
      disabledForegroundColor: foreground,
      side: Theme.of(context).brightness == Brightness.dark ? null : const BorderSide(color: Color(0xFF747775)),
    );
    if (busy) {
      return Semantics(
        label: label,
        button: true,
        excludeSemantics: true,
        child: FilledButton(
          onPressed: () {},
          style: style,
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: foreground),
          ),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      style: style,
      // The mark grows with the title, as on Apple's and Google's own buttons.
      icon: mark(MediaQuery.textScalerOf(context).scale(markSize)),
      label: Text(label, textAlign: TextAlign.center),
    );
  }
}

/// Inside LINE, Facebook or Instagram, whose built-in browsers Google's
/// sign-in policy turns away: the way out is the phone's browser, with
/// [url] to paste there.
class _InAppBrowserNote extends StatelessWidget {
  const _InAppBrowserNote({required this.app, required this.url});

  final String app;
  final String url;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.m)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BalancedText(l10n.inAppBrowserNote(app), textAlign: TextAlign.start, style: AppText.subheadline),
          const SizedBox(height: Space.s),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SecondaryButton(
              label: l10n.copyPageUrl,
              onPressed: () => copyText(context, url, copied: l10n.pageUrlCopied),
            ),
          ),
        ],
      ),
    );
  }
}
