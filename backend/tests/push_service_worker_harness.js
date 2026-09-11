const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const workerPath = path.join(__dirname, '..', '..', 'web', 'push_service_worker.js');
const source = fs.readFileSync(workerPath, 'utf8');
const handlers = {};
const shown = [];
const records = new Map();

function request(value) {
  const result = {};
  queueMicrotask(() => {
    result.result = value;
    result.onsuccess?.();
  });
  return result;
}

const db = {
  createObjectStore() { return {}; },
  transaction(_name, mode) {
    const transaction = { objectStore: () => ({
      get: (id) => request(records.get(id)),
      put: (record) => {
        records.set(record.id, record);
      },
    }) };
    if (mode === 'readwrite') queueMicrotask(() => transaction.oncomplete?.());
    return transaction;
  },
};

const indexedDB = {
  open() {
    const result = {};
    queueMicrotask(() => {
      result.result = db;
      result.onupgradeneeded?.();
      result.onsuccess?.();
    });
    return result;
  },
};

let releaseFirstShow;
const firstShowFinished = new Promise((resolve) => { releaseFirstShow = resolve; });
const registration = {
  showNotification(title, options) {
    shown.push({ title, options });
    if (shown.length === 1) return firstShowFinished;
    return Promise.resolve();
  },
};

const context = {
  self: {
    registration,
    addEventListener: (name, handler) => { handlers[name] = handler; },
    clients: {},
  },
  indexedDB,
  Date,
  Promise,
  Error,
  queueMicrotask,
};
vm.runInNewContext(source, context, { filename: workerPath });

function pushEvent(id) {
  const event = {
    data: { json: () => ({ notificationId: id, title: 'Reminder', body: id, url: `/tasks/${id}` }) },
    waitUntil(promise) { this.promise = promise; },
  };
  handlers.push(event);
  return event;
}

(async () => {
  const first = pushEvent('same-id');
  const second = pushEvent('same-id');
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(shown.length, 1, 'second concurrent push must wait for the first presentation');
  releaseFirstShow();
  await Promise.all([first.promise, second.promise]);
  assert.equal(shown.length, 1, 'duplicate notification must only be shown once');
  assert.equal(shown[0].options.data.url, '/tasks/same-id');
  assert.equal(shown[0].options.data.notificationId, 'same-id');
  console.log('push service worker concurrency harness passed');
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
