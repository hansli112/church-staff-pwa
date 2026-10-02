import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import 'providers.dart';

/// Creates users/{uid} the first time someone signs in. Watched once by the
/// app root.
final profileBootstrapProvider = Provider<void>((ref) {
  ref.listen(authUserProvider, (_, next) {
    final user = next.value;
    if (user == null) return;
    ref
        .read(backendProvider)
        .profiles
        .ensure(
          UserProfile(
            uid: user.uid,
            name: user.displayName?.trim().isNotEmpty == true ? user.displayName!.trim() : user.email.split('@').first,
            email: user.email,
          ),
        )
        .ignore();
  }, fireImmediately: true);
});

/// Signs out and forgets the picked church.
Future<void> signOut(WidgetRef ref) async {
  await ref.read(prefsProvider).remove('selected_church');
  await ref.read(backendProvider).auth.signOut();
}
