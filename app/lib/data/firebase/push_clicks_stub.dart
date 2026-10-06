/// Only the web needs this; phones report taps through FirebaseMessaging.
Stream<String> webNotificationClicks() => const Stream.empty();
