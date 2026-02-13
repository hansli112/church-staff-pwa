/* eslint-disable no-undef */
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDmxsNwAosSggaB-NvCyv2DS5OPbsTzRb8',
  authDomain: 'church-staff-pwa.firebaseapp.com',
  projectId: 'church-staff-pwa',
  storageBucket: 'church-staff-pwa.firebasestorage.app',
  messagingSenderId: '190764228437',
  appId: '1:190764228437:web:2e21123171fd47065819dc',
  measurementId: 'G-XVHTMHB7BV',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  const title = notification.title || '教會同工助手';
  const options = {
    body: notification.body || '',
    icon: '/icons/Icon-192.png',
    data: payload.data || {},
  };

  self.registration.showNotification(title, options);
});
