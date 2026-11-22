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
  Stream<DateTime?> lastAsk(String serviceType) => _b.watch(() {
    _requireArrangesRosters();
    return _b.unavailableAsks[churchId]?[serviceType]?.at;
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
      (_b.unavailableAsks[churchId] ??= {})[serviceType] = (
        at: _b.clock(),
        from: from,
        to: to,
        told: [for (final m in asked) m.uid],
      );
      told = asked.length;
    });
    return told;
  }
}
