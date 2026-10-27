/// Only the web needs this; phones report taps through FirebaseMessaging.
Stream<String> webNotificationClicks() => const Stream.empty();

/// Only the web needs this; phones go through martha/settings.
Future<void> setWebAppBadge(int count) async {}
