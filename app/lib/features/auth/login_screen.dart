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
import '../../state/session.dart';
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

  /// The email or password was wrong: the note for those moved from the
  /// old version, whose old password never works here, goes under it.
  bool _wrongPassword = false;
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  /// Counts sign-ins, so one let go of ([_letGoOnReturn]) leaves the
  /// buttons alone when it answers at last.
  int _attempt = 0;

  /// Google's or Apple's page in an Android browser tab, which never
  /// answers when it is left by the app switcher: back in the app, the
  /// buttons wait only a moment more for it. Its answer, if it comes, still
  /// signs in.
  bool _inBrowser = false;

  static bool get _browserTabs => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _letGoOnReturn);
  }

  void _letGoOnReturn() {
    if (!_busy || !_inBrowser) return;
    final attempt = _attempt;
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted || !_busy || attempt != _attempt) return;
      setState(() {
        _busy = false;
        _attempt++;
      });
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  AuthGateway get _auth => ref.read(backendProvider).auth;

  /// [event]: what to count (GA4 `login`, `sign_up`) once [action] has
  /// signed someone in, by [method]; not when they backed out of it.
  Future<void> _run(
    Future<void> Function() action, {
    bool apple = false,
    bool inBrowser = false,
    String? event,
    String? method,
  }) async {
    if (_busy) return;
    final attempt = ++_attempt;
    _inBrowser = inBrowser;
    setState(() {
      _busy = true;
      _appleRunning = apple;
      _error = null;
      _wrongPassword = false;
    });
    // Read now: signed in, the page may go before [action] returns.
    final auth = _auth;
    final telemetry = ref.read(telemetryProvider);
    try {
      await action();
      if (event != null && auth.currentUser != null) telemetry.logEvent(event, {'method': method!});
    } catch (e) {
      // Let go of meanwhile: its error is no longer the page's.
      if (!mounted || attempt != _attempt) return;
      final text = errorText(L10n.of(context), e);
      setState(() {
        _error = text.isEmpty ? null : text;
        _wrongPassword = e is AuthException && e.code == AuthErrorCode.invalidCredential;
      });
    } finally {
      if (mounted && attempt == _attempt) setState(() => _busy = false);
    }
  }

  void _submit() {
    if (_busy) return;
    // As the keyboard's 送出 does: what comes of it is not under the keyboard.
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    final register = _mode == _Mode.register;
    _run(
      () => register
          ? _auth.registerWithEmail(_name.text, _email.text, _password.text, AppLanguage.shownIn(context))
          : _auth.signInWithEmail(_email.text, _password.text),
      event: register ? 'sign_up' : 'login',
      method: 'email',
    );
  }

  Future<void> _forgot() async {
    final l10n = L10n.of(context);
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() {
        _error = l10n.emailRequired;
        _wrongPassword = false;
      });
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
                // Signing in: stays on the form it is signing in from.
                onPressed: _busy
                    ? () {}
                    : () => setState(() {
                        _mode = _Mode.choose;
                        _error = null;
                        _wrongPassword = false;
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
                    children: [_emailForm(l10n, c)],
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
      onPressed: _busy
          ? null
          : () => _run(_auth.signInWithGoogle, inBrowser: _browserTabs, event: 'login', method: 'google'),
    );
    if (!_auth.offersApple) return [google];
    final apple = _SignInButton(
      label: l10n.signInWithApple,
      markSize: 22,
      mark: (size) => Icon(Icons.apple, size: size),
      foreground: Colors.black, // Apple allows only black or white
      busy: _busy && _appleRunning,
      onPressed: _busy
          ? null
          : () => _run(_auth.signInWithApple, apple: true, inBrowser: _browserTabs, event: 'login', method: 'apple'),
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

  Widget _movedNote(AppColors c) => BalancedText(
    L10n.of(context).movedPasswordNote,
    style: AppText.footnote.copyWith(color: c.secondaryLabel),
  );

  Widget _emailForm(L10n l10n, AppColors c) {
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
                decoration: InputDecoration(labelText: l10n.yourFullName),
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
            // Under the fields it is about, above the keyboard if it stays up.
            ..._errorText(c),
            if (!register && _wrongPassword) ...[
              const SizedBox(height: Space.xs),
              _movedNote(c),
            ],
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
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _mode = register ? _Mode.signIn : _Mode.register;
                      _error = null;
                      _wrongPassword = false;
                    }),
            ),
            if (!register) ...[
              SecondaryButton(
                label: l10n.forgotPassword,
                expand: true,
                onPressed: _busy ? null : _forgot,
              ),
              if (!_wrongPassword) ...[const SizedBox(height: Space.m), _movedNote(c)],
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
