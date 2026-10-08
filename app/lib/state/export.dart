import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/export.dart';
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

/// Reads everything an admin can see of the current church, once.
Future<ChurchSnapshot> loadChurchSnapshot(WidgetRef ref) async {
  final data = ref.churchData;
  final church = await data.church().first;
  final (services, members, pending, staffOrders, rosters, calendar, link, webhook) = await (
    data.services().first,
    data.allMembers(),
    data.allPendingMembers(),
    data.allStaffOrders(),
    data.allRosters(),
    data.calendarSettings().first,
    data.churchLink().first,
    data.webhook().first,
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
  );
}
