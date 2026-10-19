import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../core/languages.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/session.dart';

/// 帳號, behind my name at the top of 設定: my name, how I sign in, signing
/// out and deleting the account, which are rarely needed.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final profile = ref.watch(profileProvider).value;
    final me = ref.watch(meProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.account)),
      body: ListView(
        children: [
          ListSection(
            children: [
              ListRow(
                title: l10n.name,
                value: profile?.name ?? me?.name,
                onTap: () => context.push('/me/profile/name'),
              ),
              if (profile != null) ListRow(title: l10n.email, value: profile.email),
            ],
          ),
          ListSection(
            children: [
              ListRow(
                leading: const IconTile(Symbols.key_rounded, color: TileColors.neutral),
                title: l10n.signInMethods,
                onTap: () => context.push('/account/sign-in'),
              ),
            ],
          ),
          ListSection(
            children: [
              ListRow(
                leading: const IconTile(Symbols.logout_rounded, color: TileColors.neutral),
                title: l10n.signOut,
                chevron: false,
                onTap: () => signOut(ref),
              ),
            ],
          ),
          ListSection(
            children: [
              ListRow(
                leading: const IconTile(Symbols.delete_rounded, color: TileColors.destructive),
                title: l10n.deleteAccount,
                destructive: true,
                onTap: () => context.push('/account'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// My name. Saving updates users/{uid}; a Cloud Function copies it to my
/// member doc in every church, which is the name others see.
class NameScreen extends ConsumerStatefulWidget {
  const NameScreen({super.key});

  @override
  ConsumerState<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends ConsumerState<NameScreen> {
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
      appBar: AppBar(title: Text(l10n.name)),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: TextLimits.profileName,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: l10n.name, counterText: ''),
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

/// Interface language, each listed by its own name; the choice is stored
/// on the profile so it follows the account to other devices.
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
              for (final language in AppLanguage.values)
                ListRow(
                  title: language.label,
                  selected: profile?.locale == language.tag,
                  onTap: () => pick(language.tag),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
