/* Dedicated scope: /push/ (kept separate from Flutter's application worker). */
let pushQueue = Promise.resolve();

function enqueuePush(handler) {
  const next = pushQueue.then(handler, handler);
  // Keep the queue usable after a failed presentation or storage operation.
  pushQueue = next.catch(() => {});
  return next;
}

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { body: event.data ? event.data.text() : '' };
  }
  const title = data.title || 'Farmer';
  const notificationId = data.notificationId;
  const url = data.url || '/';
  const options = {
    body: data.body || data.message || 'มีการแจ้งเตือนใหม่',
    icon: data.icon || '/icons/Icon-192.png',
    badge: data.badge || '/icons/Icon-192.png',
    // notificationId is the durable presentation id: transport retries are
    // at-least-once, while IndexedDB makes browser presentation idempotent.
    data: { url, notificationId },
  };
  event.waitUntil(enqueuePush(async () => {
    let db = null;
    if (notificationId) {
      try {
        db = await openNotificationDb();
        if (await hasShownNotification(db, notificationId)) return;
      } catch (_) {
        // IndexedDB is best-effort; a storage failure must not suppress a push.
        db = null;
      }
    }

    // Keep presentation before persistence so a successful push is never lost.
    await self.registration.showNotification(title, options);

    if (db) {
      try {
        await markNotificationShown(db, notificationId);
      } catch (_) {
        // Presentation succeeded; persistence can fail without rejecting push.
      }
    }
  }));
});

function openNotificationDb() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('farmer-push', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('notifications', { keyPath: 'id' });
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

function hasShownNotification(db, notificationId) {
  return new Promise((resolve, reject) => {
    const transaction = db.transaction('notifications', 'readonly');
    const request = transaction.objectStore('notifications').get(notificationId);
    request.onsuccess = () => resolve(Boolean(request.result));
    request.onerror = () => reject(request.error);
    transaction.onerror = () => reject(transaction.error);
    transaction.onabort = () => reject(transaction.error || new Error('notification lookup aborted'));
  });
}

function markNotificationShown(db, notificationId) {
  return new Promise((resolve, reject) => {
    const transaction = db.transaction('notifications', 'readwrite');
    transaction.objectStore('notifications').put({ id: notificationId, shownAt: Date.now() });
    transaction.oncomplete = resolve;
    transaction.onerror = () => reject(transaction.error);
    transaction.onabort = () => reject(transaction.error || new Error('notification marker write aborted'));
  });
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = event.notification.data && event.notification.data.url || '/';
  event.waitUntil((async () => {
    const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of clients) {
      if ('focus' in client) {
        await client.focus();
        if ('navigate' in client) await client.navigate(url);
        return;
      }
    }
    if (self.clients.openWindow) await self.clients.openWindow(url);
  })());
});
