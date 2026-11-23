part of 'memory_backend.dart';

/// [MemoryChurchData]'s 不能服事的日子 (#91): kept as firestore.rules let
/// them be, and asked for as functions/src/unavailable.ts does.
mixin _MemoryUnavailable on _MemoryChurchBase implements UnavailableData {
  @override
  Stream<UnavailableDays> of(String uid) => _b
      .watch(() {
        if (uid != _uid) _requireArrangesRosters();
        _requireMember();
        return _b.unavailable[churchId]?[uid] ?? const UnavailableDays();
      })
      .asyncMap((days) async {
        await _b.unavailableEchoHeld?.future;
        return days;
      });

  @override
  Stream<Map<String, UnavailableDays>> everyones() => _b.watch(() {
    _requireArrangesRosters();
    return {...?_b.unavailable[churchId]};
  }, equals: mapEquals);

  @override
  Future<void> saveMine(UnavailableDays days) async {
    await _b.write(() {
      final me = _b.requireMember(churchId);
      if (days.spans.length > Limits.unavailableSpans ||
          days.spans.any((s) => !withinTextLimit(s.note, TextLimits.unavailableNote))) {
        throw const CloudException(CloudErrorCode.unknown);
      }
      (_b.unavailable[churchId] ??= {})[me.uid] = days;
    });
  }

  @override
  Future<void> send() => _b.write(() {
    final me = _b.requireMember(churchId);
    (_b.unavailableSentAt[churchId] ??= {})[me.uid] = _b.clock();
  });

  @override
  Stream<UnavailableAsked?> askedOfMe() => _b.watch(() {
    final me = _b.requireMember(churchId);
    final asked = _b.unavailableAsked[churchId]?[me.uid];
    if (asked == null) return null;
    return UnavailableAsked(
      at: asked.at,
      from: asked.from,
      to: asked.to,
      sentAt: _b.unavailableSentAt[churchId]?[me.uid],
    );
  });

  @override
  Stream<UnavailableRound?> round(String serviceType) => _b.watch(() {
    _requireArrangesRosters();
    final ask = _b.unavailableAsks[churchId]?[serviceType];
    if (ask == null) return null;
    final sentAt = _b.unavailableSentAt[churchId] ?? const <String, DateTime>{};
    return UnavailableRound(
      at: ask.at,
      from: ask.from,
      to: ask.to,
      told: ask.told,
      sent: {
        for (final uid in ask.told)
          if (sentSince(sentAt[uid], ask.at)) uid,
      },
    );
  });

  Future<int> askUnavailable(String serviceType, {required Day from, required Day to}) async {
    var told = 0;
    await _b.write(() {
      final me = _b.requireMember(churchId);
      final ministries = (_b.ministries[churchId] ?? const MinistrySettings()).ministries;
      final arranges = me.arranges(ministries, serviceType);
      if (!_b.services[churchId]!.ids.contains(serviceType) || !arranges.any || to.isBefore(from)) {
        throw const CloudException(CloudErrorCode.permissionDenied);
      }
      final asked = askedToFill(_b.members[churchId]!.values, serviceType, arranges, me.uid);
      final at = _b.clock();
      (_b.unavailableAsks[churchId] ??= {})[serviceType] = (
        at: at,
        from: from,
        to: to,
        told: [for (final m in asked) m.uid],
      );
      // Each told in their own, the months stretched over any asked before,
      // not sent and not all gone by, as functions/src/unavailable.ts does.
      final thisMonth = _b.churches[churchId]!.timeZone.today(at).firstOfMonth;
      final theirs = _b.unavailableAsked[churchId] ??= {};
      for (final m in asked) {
        final before = theirs[m.uid];
        if (before != null &&
            !sentSince(_b.unavailableSentAt[churchId]?[m.uid], before.at) &&
            !before.to.isBefore(thisMonth)) {
          final earlier = before.from.isBefore(thisMonth) ? thisMonth : before.from;
          theirs[m.uid] = (
            at: at,
            from: earlier.isBefore(from) ? earlier : from,
            to: before.to.isAfter(to) ? before.to : to,
          );
        } else {
          theirs[m.uid] = (at: at, from: from, to: to);
        }
      }
      told = asked.length;
    });
    return told;
  }

  Future<int> remindUnavailable(String serviceType) async {
    var told = 0;
    await _b.write(() {
      final me = _b.requireMember(churchId);
      final ministries = (_b.ministries[churchId] ?? const MinistrySettings()).ministries;
      if (!_b.services[churchId]!.ids.contains(serviceType) || !me.arranges(ministries, serviceType).any) {
        throw const CloudException(CloudErrorCode.permissionDenied);
      }
      final ask = _b.unavailableAsks[churchId]?[serviceType];
      if (ask == null) throw const CloudException(CloudErrorCode.unknown);
      final sentAt = _b.unavailableSentAt[churchId] ?? const <String, DateTime>{};
      told = ask.told
          .where(
            (uid) => _b.members[churchId]!.containsKey(uid) && !sentSince(sentAt[uid], ask.at),
          )
          .length;
    });
    return told;
  }
}
