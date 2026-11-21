import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/staff.dart';
import 'providers.dart';

/// Adding to the church's 同工 ([staffProvider]).
class StaffActions {
  StaffActions(this._ref);

  final Ref _ref;

  /// Makes [name] one of [serviceType]'s 同工, without an account (新增同工),
  /// and, with [duty], on its list. Done once [staffProvider] lists them so,
  /// for whatever is asked next; their ID.
  ///
  /// Fails with duplicateName for a name one of the 同工 has, however
  /// written ([Staff.hasName]), adding nobody.
  Future<String> add(String name, String serviceType, {String? duty}) async {
    // Read before waiting: whoever asked can be gone by then.
    final data = _ref.churchData;
    final id = await data.addByName(name, serviceType);
    if (duty != null) await data.grantDuty(id, serviceType, duty);
    bool listed(Staff? staff) =>
        staff?.all.any((m) => m.uid == id && (duty == null || m.serves(serviceType, duty))) ?? false;
    if (listed(_ref.read(staffProvider).value)) return id;
    final shown = Completer<void>();
    final sub = _ref.listen(staffProvider, (_, staff) {
      if (listed(staff.value) && !shown.isCompleted) shown.complete();
    });
    // Not for ever: one who cannot read the list still has them added.
    await shown.future.timeout(const Duration(seconds: 10), onTimeout: () {}).whenComplete(sub.close);
    return id;
  }
}

final staffActionsProvider = Provider<StaffActions>(StaffActions.new);
