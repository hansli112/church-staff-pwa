// Web push. The Firebase JS SDK registers this file to receive messages
// while no tab of the app is open; it shows the notification and opens its
// link on click. Firebase Hosting serves /__/firebase/init.js with the
// config of the project it is deployed to, so one file serves dev and prod.
// Keep the SDK version in step with firebase_core_web
// (supportedFirebaseJsSdkVersion).
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');
importScripts('/__/firebase/init.js');

firebase.messaging();
