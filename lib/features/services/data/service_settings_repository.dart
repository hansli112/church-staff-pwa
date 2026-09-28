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
    // 要伺服器上的那一版：Firestore 的離線快取可能還是存檔前的，套回去的話
    // 剛停用的聚會又會出現。不用 get(Source.server)：網頁剛啟動、連線還沒
    // 建好時它會直接回報離線，每次啟動都撞在同一個時間點，就永遠拿不到新版。
    // 改成聽這份文件，等第一筆確定來自伺服器的快照；30 秒都等不到（真的離線）
    // 就丟例外，呼叫端沿用本機記下的清單。
    final snapshot = await _doc
        .snapshots(includeMetadataChanges: true)
        .firstWhere((snapshot) => !snapshot.metadata.isFromCache)
        .timeout(const Duration(seconds: 30));
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
