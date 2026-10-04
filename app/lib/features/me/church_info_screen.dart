import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/logo.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../church/links.dart';
import '../common/errors.dart';

/// 教會資訊: the church's name and logo, the admin tools, and at the very
/// bottom, in red, leaving the church.
///
/// Self-host had no way to leave; an admin had to delete the account.
class ChurchInfoScreen extends ConsumerStatefulWidget {
  const ChurchInfoScreen({super.key});

  @override
  ConsumerState<ChurchInfoScreen> createState() => _ChurchInfoScreenState();
}

class _ChurchInfoScreenState extends ConsumerState<ChurchInfoScreen> {
  bool _uploading = false;

  Future<void> _pickLogo() async {
    final l10n = L10n.of(context);
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = prepareLogo(await file.readAsBytes());
      await ref.read(churchDataProvider)!.uploadLogo(bytes);
      if (mounted) showToast(context, l10n.logoUploaded);
    } on LogoException catch (e) {
      if (mounted) {
        showToast(
          context,
          e.error == LogoError.tooLarge ? l10n.logoTooLarge : l10n.logoNotImage,
        );
      }
    } catch (_) {
      if (mounted) showToast(context, l10n.saveFailed);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _churchUrlActions(String url) async {
    final l10n = L10n.of(context);
    final choice = await showAppSheet<String>(
      context,
      builder: (context) => SafeArea(
        child: ListSection(
          header: displayUrl(url),
          children: [
            ListRow(
              title: l10n.churchUrlShare,
              leading: const Icon(Icons.ios_share),
              onTap: () => Navigator.pop(context, 'share'),
            ),
            ListRow(
              title: l10n.churchUrlCopy,
              leading: const Icon(Icons.copy),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'share':
        await shareText(context, url, copied: l10n.churchUrlCopied);
      case 'copy':
        await copyText(context, url, copied: l10n.churchUrlCopied);
    }
  }

  Future<void> _leave(Church church, Member me) async {
    final l10n = L10n.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.leaveChurchTitle(church.name),
      message: l10n.leaveChurchBody,
      action: l10n.leave,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(churchDataProvider)!.removeMember(me.uid);
      if (!mounted) return;
      showToast(context, l10n.leftChurch(church.name));
      context.go('/home');
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
    }
  }

  Future<void> _deleteChurch(Church church) async {
    final l10n = L10n.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.deleteChurchTitle(church.name),
      message: l10n.deleteChurchBody,
      action: l10n.deleteChurch,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(backendProvider).cloud.deleteChurch(church.id);
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final church = ref.watch(churchProvider).value;
    final me = ref.watch(meProvider).value;
    if (church == null || me == null) return Scaffold(appBar: AppBar());
    final admin = me.isAdmin;
    final logo = church.logoUrl;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.churchInfo)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.l,
              Space.m,
              Space.l,
              Space.s,
            ),
            child: Column(
              children: [
                if (logo != null && logo.startsWith('http'))
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.l),
                    child: Image.network(
                      logo,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      semanticLabel: l10n.churchLogo,
                    ),
                  ),
                const SizedBox(height: Space.s),
                Text(
                  church.name,
                  textAlign: TextAlign.center,
                  style: AppText.title2,
                ),
              ],
            ),
          ),
          ListSection(
            children: [
              ListRow(
                title: l10n.churchUrl,
                subtitle: displayUrl(churchUrl(church.id)),
                onTap: () => _churchUrlActions(churchUrl(church.id)),
              ),
            ],
          ),
          if (admin)
            ListSection(
              children: [
                ListRow(
                  title: l10n.members,
                  onTap: () => context.push('/me/members'),
                ),
                ListRow(
                  title: l10n.invites,
                  onTap: () => context.push('/me/invites'),
                ),
                ListRow(
                  title: l10n.serviceSettings,
                  onTap: () => context.push('/me/services'),
                ),
                ListRow(title: l10n.calendarSetting, onTap: () => context.push('/me/calendar')),
                ListRow(
                  title: logo == null ? l10n.uploadLogo : l10n.changeLogo,
                  trailing: _uploading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _uploading ? null : _pickLogo,
                ),
              ],
            )
          else if (me.inGroup(Group.rosterEditors))
            ListSection(
              children: [
                ListRow(
                  title: l10n.members,
                  onTap: () => context.push('/me/members'),
                ),
              ],
            ),
          if (admin)
            ListSection(
              footer: l10n.adminCannotLeave,
              children: [
                ListRow(
                  title: l10n.deleteChurch,
                  destructive: true,
                  onTap: () => _deleteChurch(church),
                ),
              ],
            )
          else
            ListSection(
              children: [
                ListRow(
                  title: l10n.leaveChurch,
                  destructive: true,
                  onTap: () => _leave(church, me),
                ),
              ],
            ),
          SizedBox(height: Space.xl + MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }
}
