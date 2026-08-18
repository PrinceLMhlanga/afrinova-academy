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

// Cleanly handle notification presentation when app is closed/in background
messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message', payload);
  
  // Extract content directly from the Firebase validated payload layout
  const notificationTitle = payload.notification?.title || 'AfriNova Academy';
  const notificationOptions = {
    body: payload.notification?.body || 'You have a new update',
    icon: '/favicon_new.png?v=2',
    badge: '/favicon_new.png?v=2',
    data: payload.data || {},
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});

// Handle custom deep-linking when a student clicks on the web notification banner
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  
  // Safe deep link extraction based on notify-dispatch's fcmOptions setup
  const targetData = event.notification.data || {};
  let targetUrl = '/';
  
  if (targetData.type === 'live_lesson') {
    targetUrl = `/lesson/${targetData.lesson_id || targetData.id || ''}`;
  } else if (targetData.type === 'chat_message') {
    targetUrl = `/chat/${targetData.session_id || ''}`;
  }

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      // If the app is already open in a tab, focus it and redirect it
      for (const client of clientList) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          if ('navigate' in client) client.navigate(targetUrl);
          return client.focus();
        }
      }
      // If the app is closed completely, open a fresh window pointing to the lesson/chat route
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
      return Promise.resolve();
    })
  );
});
