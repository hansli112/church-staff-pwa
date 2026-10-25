import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../domain/text.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import '../common/time_zones.dart';
import '../common/labels.dart';

/// Members, and requests to join turned down, hidden while it can still be
/// undone.
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

  /// Requests to join being answered, by uid.
  final _answering = <String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final members = ref.watch(membersProvider);
    final services = ref.watch(servicesProvider).value;
    final ministries = ref.watch(ministriesProvider).value;
    final smallGroups = ref.watch(smallGroupsProvider).value ?? const <SmallGroupDetails>[];
    final enabled = services?.enabled ?? const <Service>[];
    // A member's 小組 (#85).
    String? memberSmallGroups(Member m) => [
      for (final g in smallGroups)
        if (m.smallGroups.contains(g.id)) g.name,
    ].join(l10n.listSeparator).ifEmpty(null);
    // A pending member's: the names they had (zones[].smallGroups).
    List<String> smallGroupLabels(List<Zone> zones) => [
      for (final zone in zones)
        if (zone.smallGroups.isNotEmpty)
          l10n.labelValue(
            services?.byId(zone.serviceType)?.name ?? zone.serviceType,
            zone.smallGroups.join(l10n.listSeparator),
          ),
    ];
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
                // Admins, then whoever holds a 身分, then everyone else.
                int rank(Member m) => m.isAdmin ? 0 : (m.identities.isNotEmpty ? 1 : 2);
                final ra = rank(a).compareTo(rank(b));
                return ra != 0 ? ra : a.name.compareTo(b.name);
              });
          // 申請加入 (#88), on top: someone is waiting. Not anyone in already.
          final joined = {for (final m in all) m.uid};
          final requests = [
            for (final r in ref.watch(joinRequestsProvider).value ?? const <JoinRequest>[])
              if (!joined.contains(r.uid) &&
                  !hidden.contains(r.uid) &&
                  (matchesSearch(r.name, _query) || matchesSearch(r.email, _query)))
                r,
          ];
          final head = requests.isEmpty ? 0 : requests.length + 1;
          final clock = ChurchClock.of(context, ref);
          final takesRequests = ref.watch(churchProvider.select((c) => c.value?.takesJoinRequests ?? true));
          // Nobody else has joined: the next step is inviting them.
          final alone = isAdmin && _query.isEmpty && list.length <= 1 && pending.isEmpty && requests.isEmpty;
          final extra = alone ? 1 : (pending.isEmpty ? 0 : pending.length + 1);
          final count = _query.isEmpty ? 1 : 0;
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
              Expanded(
                child: list.isEmpty && pending.isEmpty && requests.isEmpty
                    ? EmptyState(message: l10n.noMembersFound)
                    : ListView.builder(
                        itemCount: head + count + list.length + extra,
                        itemExtent: null,
                        itemBuilder: (context, i) {
                          if (i < head) return _request(c, clock, requests, i, takesRequests: takesRequests);
                          i -= head;
                          // Under the requests, so it heads the members it counts.
                          if (count == 1 && i == 0) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs),
                              child: Text(
                                l10n.memberCount(all.length - hidden.where(joined.contains).length),
                                style: AppText.footnote.copyWith(color: c.secondaryLabel),
                              ),
                            );
                          }
                          i -= count;
                          if (alone && i == list.length) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
                              child: Column(
                                children: [
                                  BalancedText(
                                    l10n.membersOnlyYou,
                                    style: AppText.body.copyWith(color: c.secondaryLabel),
                                  ),
                                  SecondaryButton(
                                    label: l10n.inviteMembers,
                                    onPressed: () => context.push('/me/invites'),
                                  ),
                                ],
                              ),
                            );
                          }
                          if (i < list.length) {
                            final m = list[i];
                            return _grouped(
                              c,
                              first: i == 0,
                              last: i == list.length - 1,
                              child: ListRow(
                                title: m.uid == uid ? l10n.nameIsYou(m.name) : m.name,
                                subtitle: [
                                  identitiesLine(
                                    l10n,
                                    m,
                                    services: services,
                                    ministries: ministries,
                                    smallGroups: smallGroups,
                                  ).ifEmpty(null),
                                  if (m.waitsForZone(enabled)) l10n.waitsForZone,
                                  memberSmallGroups(m),
                                ].nonNulls.join(l10n.dotSeparator).ifEmpty(null),
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
                                ...smallGroupLabels(p.zones),
                              ].join(l10n.dotSeparator),
                              value: p.role == Role.admin ? l10n.roleAdmin : null,
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

  /// Row [i] of the requests to join: their count, then each with 允許
  /// and 拒絕.
  Widget _request(AppColors c, ChurchClock clock, List<JoinRequest> requests, int i, {required bool takesRequests}) {
    final l10n = L10n.of(context);
    if (i == 0) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
        child: Text(
          l10n.joinRequestsCount(requests.length),
          style: AppText.footnote.copyWith(color: c.secondaryLabel),
        ),
      );
    }
    final r = requests[i - 1];
    final name = r.name.isEmpty ? r.email : r.name;
    final busy = _answering.contains(r.uid);
    return Padding(
      padding: EdgeInsets.only(bottom: i == requests.length ? Space.l : 0),
      child: _grouped(
        c,
        first: i == 1,
        last: i == requests.length,
        child: ListRow(
          title: name,
          // A line each, so the date is not broken beside the buttons.
          subtitle: [
            if (r.note.isNotEmpty) r.note,
            if (r.name.isNotEmpty) r.email,
            l10n.joinRequestAskedOn(clock.day(r.createdAt)),
          ].join('\n'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RowButton(
                label: l10n.declineJoin,
                semanticsLabel: l10n.declineJoinLabel(name),
                onPressed: busy ? null : () => _decline(r, name),
              ),
              // While the church takes none, only turning down (#88).
              if (takesRequests) ...[
                const SizedBox(width: Space.xs),
                RowButton(
                  label: l10n.allowJoin,
                  semanticsLabel: l10n.allowJoinLabel(name),
                  onPressed: busy ? null : () => _allow(r, name),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _allow(JoinRequest r, String name) async {
    final l10n = L10n.of(context);
    setState(() => _answering.add(r.uid));
    try {
      await ref.churchData.answerJoinRequest(r.uid, allow: true);
      Haptics.success();
      if (mounted) showToast(context, l10n.joinAllowedToast(name));
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
    } finally {
      if (mounted) setState(() => _answering.remove(r.uid));
    }
  }

  /// Turning down cannot be taken back once written, so it waits out 復原
  /// as removing a member does.
  void _decline(JoinRequest r, String name) {
    final l10n = L10n.of(context);
    final hidden = ref.read(pendingRemovalsProvider.notifier);
    final data = ref.churchData;
    hidden.add(r.uid);
    showDeferredUndo(
      context,
      l10n.joinDeclinedToast(name),
      commit: () async {
        await data.answerJoinRequest(r.uid, allow: false);
        hidden.remove(r.uid);
      },
      onUndo: () => hidden.remove(r.uid),
      onError: (e) {
        if (mounted) showToast(context, errorText(l10n, e));
      },
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
              leading: const Icon(Symbols.delete_rounded),
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
        await ref.churchData.deletePendingMember(p.id);
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
    final data = ref.churchData;
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
