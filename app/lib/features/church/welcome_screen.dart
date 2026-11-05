import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../core/languages.dart';
import '../../data/backend.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../common/errors.dart';
import '../common/time_zones.dart';
import 'add_to_home.dart';
import 'church_entry_screen.dart';
import 'church_logo.dart';
import 'claims.dart';
import 'links.dart';
import 'your_name.dart';

/// For someone signed in who belongs to no church yet. Most people arrive
/// through an invite link and never see this; the rest either have a code
/// or are starting a church.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Also under the code and new-church pages opened from 切換教會, where
    // going back lands here: blank for someone in a church (a swipe back
    // shows it), and back to 設定 once it is the top page, since a pop is
    // not redirected.
    if (ref.watch(appStageProvider) == AppStage.ready) {
      if (ModalRoute.of(context)?.isCurrent ?? true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go('/me');
        });
      }
      return const Scaffold();
    }
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    // 加入 on moved data is the way in then; a code, the other one.
    final claiming = (ref.watch(pendingClaimsProvider).value ?? const []).isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(Space.l),
              children: [
                const VerifyEmailBanner(),
                const PendingClaimsCard(),
                if (claiming) const SizedBox(height: Space.l),
                const AskedToJoinRows(),
                BalancedText(
                  l10n.welcomeTitle,
                  style: AppText.title,
                ),
                const SizedBox(height: Space.s),
                BalancedText(l10n.welcomeBody, style: AppText.body.copyWith(color: c.secondaryLabel)),
                const SizedBox(height: Space.xl),
                if (claiming)
                  SecondaryButton(
                    label: l10n.enterInviteCode,
                    expand: true,
                    onPressed: () => context.push('/welcome/join'),
                  )
                else
                  PrimaryButton(
                    label: l10n.enterInviteCode,
                    onPressed: () => context.push('/welcome/join'),
                  ),
                const SizedBox(height: Space.s),
                SecondaryButton(
                  label: l10n.createChurch,
                  expand: true,
                  onPressed: () => context.push('/welcome/create'),
                ),
                const SizedBox(height: Space.xl),
                SecondaryButton(
                  label: l10n.signOut,
                  expand: true,
                  onPressed: () => signOut(ref),
                ),
                // In no church there is no 設定, where it is otherwise.
                SecondaryButton(
                  label: l10n.deleteAccount,
                  expand: true,
                  destructive: true,
                  onPressed: () => context.push('/account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 「已申請加入〈希望堂〉，等管理員允許」 on the welcome page, one row a
/// church still waited on, opening its church URL (to take it back, say).
/// One turned down or taken back meanwhile is forgotten; back in the app,
/// each is asked again.
class AskedToJoinRows extends ConsumerStatefulWidget {
  const AskedToJoinRows({super.key});

  @override
  ConsumerState<AskedToJoinRows> createState() => _AskedToJoinRowsState();
}

class _AskedToJoinRowsState extends ConsumerState<AskedToJoinRows> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        for (final churchId in ref.read(askedToJoinProvider)) {
          ref.invalidate(churchPreviewProvider(churchId));
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final waiting = <ChurchPreview>[];
    for (final churchId in ref.watch(askedToJoinProvider)) {
      ref.listen(churchPreviewProvider(churchId), (_, next) {
        if (next.hasValue && next.value!.joinRequest != JoinRequestState.pending) {
          ref.read(askedToJoinProvider.notifier).remove(churchId);
        }
      });
      // Not known while offline: kept, shown again once it is.
      final church = ref.watch(churchPreviewProvider(churchId)).value;
      if (church?.joinRequest == JoinRequestState.pending) waiting.add(church!);
    }
    if (waiting.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.m),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final church in waiting)
              ListRow(
                title: l10n.welcomeAskedToJoin(church.name),
                onTap: () => context.push('/c/${church.id}'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Where an email sign-up waits until its email is verified (AppStage
/// .unverified): nothing else opens before then, so whoever has the account
/// is known to read that email.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> with _Verifying {
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final email = ref.watch(authUserProvider.select((u) => u.value?.email ?? ''));
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(Space.l),
              children: [
                BalancedText(l10n.verifyEmailTitle, style: AppText.title),
                const SizedBox(height: Space.s),
                BalancedText(l10n.verifyEmailBody(email), style: AppText.body.copyWith(color: c.secondaryLabel)),
                const SizedBox(height: Space.xs),
                BalancedText(l10n.verifyEmailNoMail, style: AppText.footnote.copyWith(color: c.secondaryLabel)),
                const SizedBox(height: Space.xl),
                SecondaryButton(label: l10n.verifyResend, expand: true, onPressed: resend),
                const SizedBox(height: Space.xl),
                SecondaryButton(label: l10n.signOut, expand: true, onPressed: () => signOut(ref)),
                SecondaryButton(
                  label: l10n.deleteAccount,
                  expand: true,
                  destructive: true,
                  onPressed: () => context.push('/account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks to click the link in the verification email, where a password
/// account a Google or Apple account vouches for (so not stopped at
/// [VerifyEmailScreen]) must still verify its own email: starting a church,
/// asking to join one. Shows nothing for anyone else, or once verified.
class VerifyEmailBanner extends ConsumerStatefulWidget {
  const VerifyEmailBanner({super.key});

  @override
  ConsumerState<VerifyEmailBanner> createState() => _VerifyEmailBannerState();
}

class _VerifyEmailBannerState extends ConsumerState<VerifyEmailBanner> with _Verifying {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).value;
    if (user == null || user.verified) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: Space.xl),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(Radii.m),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.verifyEmailTitle, style: AppText.headline),
          const SizedBox(height: Space.xs),
          BalancedText(l10n.verifyEmailBody(user.email), textAlign: TextAlign.start, style: AppText.subheadline),
          const SizedBox(height: Space.s),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SecondaryButton(label: l10n.verifyResend, onPressed: resend),
          ),
        ],
      ),
    );
  }
}

/// Looking for the email to be verified, so nobody has to say so: every
/// few seconds while the app is on screen, and on coming back to it (from
/// the email's link, say). And 重寄驗證信.
mixin _Verifying<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  static const _every = Duration(seconds: 4);

  Timer? _poll;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onShow: _watch, onHide: _rest);
    WidgetsBinding.instance.addPostFrameCallback((_) => _watch());
  }

  @override
  void dispose() {
    _rest();
    _lifecycle.dispose();
    super.dispose();
  }

  void _watch() {
    if (!mounted) return;
    _recheck();
    _poll ??= Timer.periodic(_every, (_) => _recheck());
  }

  void _rest() {
    _poll?.cancel();
    _poll = null;
  }

  void _recheck() {
    final user = ref.read(authUserProvider).value;
    if (user == null || user.verified) return _rest();
    // Offline, say: the next look will do.
    ref.read(backendProvider).auth.reload().catchError((_) {});
  }

  Future<void> resend() async {
    final l10n = L10n.of(context);
    try {
      await ref.read(backendProvider).auth.sendEmailVerification(AppLanguage.shownIn(context));
      if (mounted) showToast(context, l10n.verifyResent);
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
    }
  }
}

/// Typing an invite code by hand; it opens the same join page as a link.
class EnterCodeScreen extends StatefulWidget {
  const EnterCodeScreen({super.key});

  @override
  State<EnterCodeScreen> createState() => _EnterCodeScreenState();
}

class _EnterCodeScreenState extends State<EnterCodeScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _next() {
    final text = _code.text.trim();
    if (text.isEmpty) return;
    // Accept a whole pasted link too.
    final fromLink = inviteCodeIn(Uri.tryParse(text)?.path ?? '');
    context.push('/welcome/join/${fromLink ?? text.toUpperCase()}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.enterInviteCode)),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          TextField(
            controller: _code,
            autofocus: true,
            autocorrect: false,
            // The code is letters and digits: a Zhuyin or Pinyin keyboard
            // would turn them into ㄍㄆㄍ or 中文. Asking for a password's
            // keyboard opens a Latin one; _next uppercases what is typed.
            keyboardType: TextInputType.visiblePassword,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.go,
            style: AppText.title3.copyWith(letterSpacing: 2),
            decoration: InputDecoration(labelText: l10n.inviteCode),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _next(),
          ),
          const SizedBox(height: Space.l),
          PrimaryButton(
            label: l10n.next,
            onPressed: _code.text.trim().isEmpty ? null : _next,
          ),
        ],
      ),
    );
  }
}

/// Starting a new church. The backend checks the name is not taken.
class CreateChurchScreen extends ConsumerStatefulWidget {
  const CreateChurchScreen({super.key});

  @override
  ConsumerState<CreateChurchScreen> createState() => _CreateChurchScreenState();
}

class _CreateChurchScreenState extends ConsumerState<CreateChurchScreen> {
  final _churchName = TextEditingController();
  String? _typedName;
  bool _busy = false;
  String? _error;
  bool _duplicate = false;

  @override
  void dispose() {
    _churchName.dispose();
    super.dispose();
  }

  /// Starts the church, its first admin named [myName].
  Future<void> _create(String myName) async {
    final name = _churchName.text.trim();
    if (name.isEmpty || myName.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _duplicate = false;
    });
    try {
      final language = AppLanguage.shownIn(context);
      final timeZone = await ref.read(deviceTimeZoneProvider)();
      await saveJoiningName(ref, myName);
      final cid = await ref.read(backendProvider).cloud.createChurch(name, timeZone: timeZone, language: language);
      ref.read(telemetryProvider).logEvent('church_create', {'method': 'new'});
      ref.read(selectedChurchProvider.notifier).select(cid);
      Haptics.success();
      if (mounted) goAfterJoining(context, ref, cid);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorText(L10n.of(context), e);
        _duplicate = e is CloudException && e.code == CloudErrorCode.duplicateName;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final verified = ref.watch(
      authUserProvider.select((u) => u.value?.verified ?? false),
    );
    final myName = joiningName(ref, _typedName);
    final ready = verified && _churchName.text.trim().isNotEmpty && myName.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.createChurch)),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          const VerifyEmailBanner(),
          TextField(
            controller: _churchName,
            autofocus: verified,
            enabled: verified,
            maxLength: TextLimits.churchName,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.churchName,
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.m),
          YourNameField(
            typed: _typedName,
            enabled: verified,
            onChanged: (v) => setState(() => _typedName = v),
            onSubmitted: ready ? () => _create(myName) : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.s),
            BalancedText(
              _error!,
              textAlign: TextAlign.start,
              style: AppText.subheadline.copyWith(color: c.destructive),
            ),
            if (_duplicate)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: SecondaryButton(
                  label: l10n.contactUs,
                  onPressed: () => launchUrl(Uri.parse(supportUrl)),
                ),
              ),
          ],
          const SizedBox(height: Space.l),
          PrimaryButton(
            label: l10n.create,
            busy: _busy,
            onPressed: ready ? () => _create(myName) : null,
          ),
          const SizedBox(height: Space.xl),
          SecondaryButton(
            label: l10n.moveFromSelfHost,
            expand: true,
            onPressed: () => context.push('/welcome/move'),
          ),
        ],
      ),
    );
  }
}
