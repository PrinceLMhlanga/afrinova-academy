importScripts('https://www.gstatic.com/firebasejs/9.23.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.23.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDAMiHqhaKQ33dAHaJLuldeNPXz3EMEOj4',
  authDomain: 'afrinova-academy.firebaseapp.com',
  projectId: 'afrinova-academy',
  storageBucket: 'afrinova-academy.firebasestorage.app',
  messagingSenderId: '563580728976',
  appId: '1:563580728976:web:48c88535de756b9484ca15',
  measurementId: 'G-CM4DF0G5XK',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message', payload);
  const notificationTitle = payload?.notification?.title || 'AfriNova Academy';
  const notificationOptions = {
    body: payload?.notification?.body || 'You have a new update',
    icon: '/favicon_new.png?v=2',
    badge: '/favicon_new.png?v=2',
    data: payload?.data || {},
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});

self.addEventListener('push', (event) => {
  const payload = event.data?.json?.() || {};
  const title = payload.notification?.title || 'AfriNova Academy';
  const options = {
    body: payload.notification?.body || 'You have a new update',
    icon: '/favicon_new.png?v=2',
    badge: '/favicon_new.png?v=2',
    data: payload.data || {},
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow('/');
      }
      return Promise.resolve();
    })
  );
});
