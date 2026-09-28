import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/church_config.dart';
import '../../../core/config/service_catalog.dart';

/// settings/services：管理員在 App 裡設定的聚會清單。
///
/// ```
/// { services: [{id, label, name, weekday, enabled}, …],
///   ids: [曾經用過的每一個聚會 ID] }
/// ```
///
/// ids 另外存一份，是因為 Firestore rules 沒辦法在 map 的清單裡找 id；
/// rules 用它判斷一個服事表的 type 存不存在，所以只能增加，不能減少。
class ServiceSettings {
  const ServiceSettings({required this.services, required this.ids});

  final List<ServiceDefinition>? services;
  final List<String> ids;
}

abstract class ServiceSettingsRepository {
  /// 文件不存在時回傳 null（沿用部署設定）。
  Future<ServiceSettings?> load();

  Future<void> save(List<ServiceDefinition> services);
}

class FirestoreServiceSettingsRepository implements ServiceSettingsRepository {
  FirestoreServiceSettingsRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection('settings').doc('services');

  @override
  Future<ServiceSettings?> load() async {
    // 一定要問伺服器：Firestore 的離線快取可能還是存檔前那一版。重新載入後
    // 讀到舊版的話，剛停用的聚會又會被套回來。離線時這裡會丟例外，呼叫端
    // 就沿用本機記下的清單。
    final snapshot = await _doc.get(const GetOptions(source: Source.server));
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    final ids = data['ids'];
    return ServiceSettings(
      services: ServiceCatalog.parseDocument(data),
      ids: ids is List ? ids.whereType<String>().toList() : const [],
    );
  }

  @override
  Future<void> save(List<ServiceDefinition> services) async {
    // 在 transaction 裡讀舊的 ids 再合併：兩位管理員同時存，也不會有人的
    // 新聚會 ID 被對方覆蓋掉（rules 也會擋減少 ids 的寫入）。
    await _firestore.runTransaction((transaction) async {
      final current = await transaction.get(_doc);
      final previous = current.data()?['ids'];
      transaction.set(_doc, {
        'services': [for (final service in services) service.toJson()],
        'ids': ServiceCatalog.knownIds(
          previous is List ? previous.whereType<String>() : const [],
          services,
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
