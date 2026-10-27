const assert = require('node:assert/strict');
const { after, before, beforeEach, test } = require('node:test');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { createNotification } = require('../lib/notification_service.js');

const projectId = 'demo-student-attendance';
const notificationId = 'lowAttendance_student-test_subject-test_20261027';
let app;
let firestore;

before(() => {
  app = initializeApp({ projectId }, 'notification-helper-test');
  firestore = getFirestore(app);
});

beforeEach(async () => {
  await firestore.collection('notifications').doc(notificationId).delete();
});

after(async () => {
  await firestore.collection('notifications').doc(notificationId).delete();
  await app.delete();
});

test('deduplicates retries with create semantics', async () => {
  const notification = {
    dedupeKey: notificationId,
    recipientId: 'student-test',
    type: 'lowAttendance',
    title: 'Attendance warning',
    body: 'Attendance is below the configured threshold.',
    relatedId: 'subject-test',
  };

  assert.equal(await createNotification(firestore, notification), true);
  assert.equal(await createNotification(firestore, notification), false);

  const docs = await firestore
    .collection('notifications')
    .where('recipientId', '==', 'student-test')
    .get();
  assert.equal(docs.size, 1);
  assert.equal(docs.docs[0].id, notificationId);
  assert.equal(docs.docs[0].get('isRead'), false);
});
