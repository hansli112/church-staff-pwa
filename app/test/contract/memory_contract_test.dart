import 'contract_suite.dart';
import 'memory_world.dart';

/// The contract on MemoryBackend; firebase_contract_test.dart runs the same
/// cases on the emulators.
void main() {
  contractTests(() async => MemoryWorld());
}
