import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backend.dart';
import '../domain/export.dart';
import 'attendance.dart';
import 'providers.dart';

/// Hands a file to the person: a download on the web, the share sheet on
/// phones (save to Files, send by mail…). Overridden in tests.
abstract interface class FileSaver {
  /// False when the person closed the share sheet without using it.
  Future<bool> save(String name, Uint8List bytes, String mimeType);
}

class PlatformFileSaver implements FileSaver {
  const PlatformFileSaver();

  @override
  Future<bool> save(String name, Uint8List bytes, String mimeType) async {
    final file = XFile.fromData(bytes, name: name, mimeType: mimeType);
    if (kIsWeb) {
      await file.saveTo(name);
      return true;
    }
    // The title is what the share sheet shows above the file.
    final result = await SharePlus.instance.share(ShareParams(files: [file], fileNameOverrides: [name], title: name));
    return result.status != ShareResultStatus.dismissed;
  }
}

final fileSaverProvider = Provider<FileSaver>((ref) => const PlatformFileSaver());

/// How long 匯出資料 waits for the church to be read before it says the
/// connection failed.
const exportWait = Duration(seconds: 30);

/// Reads everything an admin can see of the current church, once; the
/// 人數 of its meetings too, with 回報人數 on. Not all read in
/// [exportWait], it throws a [CloudException] unavailable.
Future<ChurchSnapshot> loadChurchSnapshot(WidgetRef ref) => _loadChurchSnapshot(
  ref,
).timeout(exportWait, onTimeout: () => throw const CloudException(CloudErrorCode.unavailable));

Future<ChurchSnapshot> _loadChurchSnapshot(WidgetRef ref) async {
  final data = ref.churchData;
  final ((church, services, members, pending, staffOrders, rosters, calendar, link, webhook), attendance) = await (
    (
      data.church().first,
      data.services().first,
      data.readOnce.members(),
      data.readOnce.pendingMembers(),
      data.readOnce.staffOrders(),
      data.readOnce.rosters(),
      data.calendar.settings().first,
      data.churchLink.watch().first,
      data.webhook.watch().first,
    ).wait,
    loadAttendanceLines(ref),
  ).wait;
  return ChurchSnapshot(
    church: church!,
    services: services,
    members: members,
    pendingMembers: pending,
    staffOrders: staffOrders,
    rosters: rosters,
    calendar: calendar,
    link: link,
    webhook: webhook,
    attendance: attendance,
  );
}
