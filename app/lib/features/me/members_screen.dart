import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../domain/text.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import '../common/labels.dart';

/// Members hidden while their removal can still be undone.
class PendingRemovals extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String uid) => state = {...state, uid};
  void remove(String uid) => state = {...state}..remove(uid);
}

final pendingRemovalsProvider = NotifierProvider<PendingRemovals, Set<String>>(
  PendingRemovals.new,
);

/// The church's members, searchable. Admins tap one to edit; roster
/// editors can look.
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final members = ref.watch(membersProvider);
    final hidden = ref.watch(pendingRemovalsProvider);
    final uid = ref.watch(uidProvider);
    final isAdmin = ref.watch(
      meProvider.select((m) => m.value?.isAdmin ?? false),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.members)),
      body: members.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (_, _) => ErrorRetry(
          message: l10n.loadFailed,
          onRetry: () => ref.invalidate(membersProvider),
        ),
        data: (all) {
          final pending = [
            for (final p in ref.watch(pendingMembersProvider).value ?? const <PendingMember>[])
              if (matchesSearch(p.name, _query) || matchesSearch(p.email, _query)) p,
          ]..sort((a, b) => a.name.compareTo(b.name));
          final list =
              [
                for (final m in all)
                  if (!hidden.contains(m.uid) && matchesSearch(m.name, _query)) m,
              ]..sort((a, b) {
                final ra = a.role.index.compareTo(b.role.index);
                return ra != 0 ? ra : a.name.compareTo(b.name);
              });
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.m,
                  0,
                  Space.m,
                  Space.s,
                ),
                child: SearchField(
                  hint: l10n.searchMembers,
                  onChanged: (q) => setState(() => _query = q),
                ),
              ),
              if (_query.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.l,
                    vertical: Space.xs,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      l10n.memberCount(all.length - hidden.length),
                      style: AppText.footnote.copyWith(color: c.secondaryLabel),
                    ),
                  ),
                ),
              Expanded(
                child: list.isEmpty && pending.isEmpty
                    ? EmptyState(message: l10n.noMembersFound)
                    : ListView.builder(
                        itemCount: list.length + (pending.isEmpty ? 0 : pending.length + 1),
                        itemExtent: null,
                        itemBuilder: (context, i) {
                          if (i < list.length) {
                            final m = list[i];
                            return _grouped(
                              c,
                              first: i == 0,
                              last: i == list.length - 1,
                              child: ListRow(
                                title: m.uid == uid ? '${m.name}（${l10n.you}）' : m.name,
                                subtitle: [
                                  if (m.inGroup(Group.rosterEditors) && !m.isAdmin) l10n.groupRosterEditors,
                                  if (m.inGroup(Group.calendarEditors) && !m.isAdmin) l10n.groupCalendarEditors,
                                ].join('・').ifEmpty(null),
                                value: roleLabel(l10n, m.role),
                                onTap: isAdmin ? () => _open(m) : null,
                              ),
                            );
                          }
                          if (i == list.length) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
                              child: Text(
                                l10n.pendingCount(pending.length),
                                style: AppText.footnote.copyWith(color: c.secondaryLabel),
                              ),
                            );
                          }
                          final j = i - list.length - 1;
                          final p = pending[j];
                          return _grouped(
                            c,
                            first: j == 0,
                            last: j == pending.length - 1,
                            child: ListRow(
                              title: p.name.isEmpty ? p.email : p.name,
                              subtitle: [
                                l10n.notSignedInYet,
                                if (p.email.isNotEmpty && p.name.isNotEmpty) p.email,
                              ].join('・'),
                              value: roleLabel(l10n, p.role),
                              onTap: isAdmin ? () => _openPending(p) : null,
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// One row of a rounded group.
  Widget _grouped(AppColors c, {required bool first, required bool last, required Widget child}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.m),
    child: Material(
      color: c.surface,
      borderRadius: BorderRadius.vertical(
        top: first ? const Radius.circular(Radii.m) : Radius.zero,
        bottom: last ? const Radius.circular(Radii.m) : Radius.zero,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );

  /// What an admin can do with someone who has not signed in yet.
  Future<void> _openPending(PendingMember p) async {
    final l10n = L10n.of(context);
    final name = p.name.isEmpty ? p.email : p.name;
    final choice = await showAppSheet<String>(
      context,
      builder: (context) => SafeArea(
        child: ListSection(
          header: name,
          children: [
            ListRow(
              title: l10n.pendingDelete,
              destructive: true,
              leading: const Icon(Icons.delete_outline),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'delete') {
      final ok = await confirmDestructive(
        context,
        title: l10n.pendingDeleteTitle(name),
        message: l10n.pendingDeleteBody,
        action: l10n.delete,
      );
      if (!ok || !mounted) return;
      try {
        await ref.read(churchDataProvider)!.deletePendingMember(p.id);
        if (mounted) showToast(context, l10n.pendingDeleted);
      } catch (e) {
        if (mounted) showToast(context, errorText(l10n, e));
      }
    }
  }

  Future<void> _open(Member m) async {
    final l10n = L10n.of(context);
    final result = await context.push<String>('/me/members/${m.uid}');
    if (result != 'remove' || !mounted) return;
    final pending = ref.read(pendingRemovalsProvider.notifier);
    final data = ref.read(churchDataProvider)!;
    pending.add(m.uid);
    showDeferredUndo(
      context,
      l10n.memberRemoved(m.name),
      commit: () async {
        await data.removeMember(m.uid);
        pending.remove(m.uid);
      },
      onUndo: () => pending.remove(m.uid),
      onError: (e) {
        if (mounted) showToast(context, errorText(l10n, e));
      },
    );
  }
}

extension on String {
  String? ifEmpty(String? fallback) => isEmpty ? fallback : this;
}
