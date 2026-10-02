import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';

/// My name. Saving updates users/{uid}; a Cloud Function copies it to my
/// member doc in every church, which is the name others see.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  TextEditingController? _name;
  bool _busy = false;

  @override
  void dispose() {
    _name?.dispose();
    super.dispose();
  }

  Future<void> _save(UserProfile profile) async {
    final l10n = L10n.of(context);
    final name = _name!.text.trim();
    if (name.isEmpty || name == profile.name) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(backendProvider)
          .profiles
          .save(
            UserProfile(
              uid: profile.uid,
              name: name,
              email: profile.email,
              locale: profile.locale,
            ),
          );
      if (mounted) {
        showToast(context, l10n.nameSaved);
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) showToast(context, l10n.saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final profile = ref.watch(profileProvider).value;
    if (profile == null) return Scaffold(appBar: AppBar());
    _name ??= TextEditingController(text: profile.name);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profile)),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 40,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(hintText: l10n.name, counterText: ''),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(profile),
          ),
          const SizedBox(height: Space.s),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            child: Text(
              profile.email,
              style: AppText.subheadline.copyWith(color: c.secondaryLabel),
            ),
          ),
          const SizedBox(height: Space.l),
          PrimaryButton(
            label: l10n.save,
            busy: _busy,
            onPressed: _name!.text.trim().isEmpty || _name!.text.trim() == profile.name ? null : () => _save(profile),
          ),
        ],
      ),
    );
  }
}

/// Interface language. Only Traditional Chinese ships today; the choice is
/// stored on the profile so it follows the account to other devices.
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final profile = ref.watch(profileProvider).value;
    Future<void> pick(String? locale) async {
      if (profile == null) return;
      Haptics.selection();
      await ref
          .read(backendProvider)
          .profiles
          .save(
            UserProfile(
              uid: profile.uid,
              name: profile.name,
              email: profile.email,
              locale: locale,
            ),
          );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.language)),
      body: ListView(
        children: [
          ListSection(
            children: [
              ListRow(
                title: l10n.languageSystem,
                selected: profile?.locale == null,
                onTap: () => pick(null),
              ),
              ListRow(
                title: l10n.languageZhHant,
                selected: profile?.locale == 'zh-Hant',
                onTap: () => pick('zh-Hant'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
