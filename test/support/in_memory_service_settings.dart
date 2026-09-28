import 'package:church_staff_pwa/core/config/church_config.dart';
import 'package:church_staff_pwa/core/config/service_catalog.dart';
import 'package:church_staff_pwa/features/services/data/service_settings_repository.dart';

/// settings/services 的記憶體版本，跟 Firestore 那份一樣只增不減 ids。
class InMemoryServiceSettings implements ServiceSettingsRepository {
  InMemoryServiceSettings([this.document]);

  ServiceSettings? document;
  int saves = 0;

  @override
  Future<ServiceSettings?> load() async => document;

  @override
  Future<void> save(List<ServiceDefinition> services) async {
    saves += 1;
    document = ServiceSettings(
      services: List.of(services),
      ids: ServiceCatalog.knownIds(document?.ids ?? const [], services),
    );
  }
}
