import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/balanced_text.dart';
import '../../core/design/tokens.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/session.dart';

/// My profile, or what signing in makes it while that is not saved yet
/// (offline at first sign-in), so joining never waits on it.
final _joiningProfileProvider = Provider.autoDispose<UserProfile?>((ref) {
  final user = ref.watch(authUserProvider).value;
  return ref.watch(profileProvider).value ?? (user == null ? null : firstProfile(user));
});

/// 你的名字 where one joins a church (an invite, 申請加入) or starts one:
/// what the church sees on its 服事表 and in its lists, and what its admin
/// knows a request by. Until [typed] (by [onChanged]) it is the account's
/// name, which Google may give in English and Apple not at all.
class YourNameField extends ConsumerStatefulWidget {
  const YourNameField({super.key, required this.typed, required this.onChanged, this.onSubmitted, this.enabled = true});

  final String? typed;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitted;
  final bool enabled;

  @override
  ConsumerState<YourNameField> createState() => _YourNameFieldState();
}

class _YourNameFieldState extends ConsumerState<YourNameField> {
  TextEditingController? _name;

  @override
  void dispose() {
    _name?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // Renamed elsewhere before anything is typed: shown as it is.
    ref.listen(_joiningProfileProvider, (_, next) {
      if (widget.typed == null && next != null) _name?.text = next.name;
    });
    final profile = ref.watch(_joiningProfileProvider);
    if (profile != null) _name ??= TextEditingController(text: widget.typed ?? profile.name);
    return TextField(
      controller: _name,
      enabled: widget.enabled && _name != null,
      maxLength: TextLimits.profileName,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.name],
      decoration: InputDecoration(
        labelText: l10n.yourName,
        // Broken where a reader would: 「…用教會裡大家怎麼叫你」, not 「…怎麼／叫你」.
        helper: BalancedText(
          l10n.yourNameFooter,
          textAlign: TextAlign.start,
          style: AppText.footnote.copyWith(color: AppColors.of(context).secondaryLabel),
        ),
        counterText: '',
      ),
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted == null ? null : (_) => widget.onSubmitted!(),
    );
  }
}

/// The name to join with, as [YourNameField] shows it.
String joiningName(WidgetRef ref, String? typed) => (typed ?? ref.watch(_joiningProfileProvider)?.name ?? '').trim();

/// Makes [name] mine before joining, if it changed: the backend gives a new
/// member, a request and a church's first admin the account's name, and
/// copies it to the churches I am already in.
Future<void> saveJoiningName(WidgetRef ref, String name) async {
  final profile = ref.read(_joiningProfileProvider);
  final saved = ref.read(profileProvider).value;
  if (profile == null || name.isEmpty || (saved != null && saved.name == name)) return;
  await ref
      .read(backendProvider)
      .profiles
      .save(UserProfile(uid: profile.uid, name: name, email: profile.email, locale: profile.locale));
}
