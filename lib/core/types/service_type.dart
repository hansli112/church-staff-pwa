/// 聚會別。
///
/// enum 的 [name]（`sundayService` / `youth` / `children`）是資料格式的一部分：
/// 服事表文件的 `type` 欄位、使用者文件的 `zoneTypes` 陣列存的都是這幾個字串，
/// 改名等於要遷移資料。新增或改名時，這幾處要一起動：
///
///   - `firestore.rules` 的 `hasValidZoneTypes()` —— 沒跟上的話，管理員存那個
///     人時會直接 write denied（會當場爆，不是靜默壞掉）
///   - `scripts/backfill-user-zone-types.mjs` 的 `SERVICE_TYPES`
///   - `settings/roster_templates` 與 `settings/event_options` 這兩份文件是以
///     這些字串當 key
///
/// 同樣的取捨在 [UserGroup] 也有一份，理由一樣：規則語言認不得 Dart 的 enum，
/// 只能兩邊各寫一份字串清單。
enum ServiceType {
  sundayService, // 主日
  youth, // 青崇
  children, // 兒主
}

extension ServiceTypeExtension on ServiceType {
  String get label {
    switch (this) {
      case ServiceType.sundayService:
        return '主日';
      case ServiceType.youth:
        return '青崇';
      case ServiceType.children:
        return '兒主';
    }
  }
}
