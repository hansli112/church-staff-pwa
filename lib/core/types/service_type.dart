import '../config/church_config.dart';

/// 穩定的聚會 ID。顯示名稱及排程來自部署設定，不用改 ID 就能改名。
/// 未知 ID 原樣保留，不能把舊資料或未設定的聚會誤認為另一種聚會。
class ServiceType {
  const ServiceType(this.name);

  // 既有文件的 ID 保持不變；新部署可以使用完全不同的聚會清單。
  static const sundayService = ServiceType('sundayService');
  static const youth = ServiceType('youth');
  static const children = ServiceType('children');

  final String name;

  static List<ServiceType> get values => List.unmodifiable(
    ChurchConfig.current.services.map((service) => ServiceType(service.id)),
  );

  static ServiceType fromName(String name) => ServiceType(name);

  ServiceDefinition? get _definition => ChurchConfig.current.service(name);
  String get label => _definition?.label ?? name;
  String get serviceName => _definition?.name ?? name;
  bool get enabled => _definition?.enabled ?? false;
  int get weekday =>
      _definition?.weekday ?? (throw StateError('聚會 $name 不在部署設定內，不能產生排程'));
  int get index =>
      ChurchConfig.current.services.indexWhere((s) => s.id == name);

  @override
  bool operator ==(Object other) => other is ServiceType && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'ServiceType.$name';
}
