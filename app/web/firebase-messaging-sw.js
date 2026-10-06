// Web push. The Firebase JS SDK registers this file to receive messages
// while no tab of the app is open; it shows the notification and opens its
// link on click. Firebase Hosting serves /__/firebase/init.js with the
// config of the project it is deployed to, so one file serves dev and prod.
// Keep the SDK version in step with firebase_core_web
// (supportedFirebaseJsSdkVersion).
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');
importScripts('/__/firebase/init.js');

// Registered before the SDK's own handler, which it stops. The SDK skips the
// notification whenever a tab of the app is merely visible (say, behind
// another window) and hands it to that tab instead; Chrome, which goes by
// focus, then shows its own "updated in the background" notice. Here a
// focused tab gets the message (the app shows it), anything else gets the
// notification, shaped as the SDK's so its click handler still opens it.
self.addEventListener('push', (event) => {
  let payload;
  try {
    payload = event.data?.json();
  } catch {
    return;
  }
  if (!payload?.notification) return;
  event.stopImmediatePropagation();
  event.waitUntil(
    (async () => {
      const tabs = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      const focused = tabs.filter((tab) => tab.focused);
      if (focused.length > 0) {
        for (const tab of focused) tab.postMessage({ ...payload, isFirebaseMessaging: true, messageType: 'push-received' });
        return;
      }
      await self.registration.showNotification(payload.notification.title ?? '', {
        ...payload.notification,
        data: { FCM_MSG: payload },
      });
    })(),
  );
});

firebase.messaging();
