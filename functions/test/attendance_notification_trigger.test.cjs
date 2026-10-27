const assert = require('node:assert/strict');
const { after, before, test } = require('node:test');
const { initializeApp } = require('firebase-admin/app');
const { Timestamp, getFirestore } = require('firebase-admin/firestore');

const projectId = 'demo-student-attendance';
const studentId = 'trigger-student';
const subjectId = 'trigger-subject';
const notificationId = 'lowAttendance_trigger-student_trigger-subject_20261027';
let app;
let firestore;

before(() => {
  app = initializeApp({ projectId }, 'attendance-trigger-test');
  firestore = getFirestore(app);
});

after(async () => {
  await firestore.collection('notifications').doc(notificationId).delete();
  await Promise.all(Array.from({ length: 4 }, (_, index) =>
    firestore.doc(`attendanceRecords/trigger-session-${index}_${studentId}`).delete(),
  ));
  await Promise.all(Array.from({ length: 4 }, (_, index) =>
    firestore.doc(`attendanceSessions/trigger-session-${index}`).delete(),
  ));
  await firestore.doc(`users/${studentId}`).delete();
  await firestore.doc('institutionSettings/default').delete();
  await app.delete();
});

test('creates one low-attendance notification for repeated same-day record writes', async () => {
  await firestore.collection('notifications').doc(notificationId).delete();
  await firestore.doc('institutionSettings/default').set({
    defaultAttendanceThreshold: 75,
    warningBuffer: 5,
    countApprovedOdAsPresent: false,
  });
  await firestore.doc(`users/${studentId}`).set({ role: 'student' });
  const sessionDate = Timestamp.fromDate(new Date('2026-10-27T00:00:00.000Z'));
  const statuses = ['present', 'present', 'absent', 'absent'];

  await Promise.all(statuses.map((status, index) => {
    const sessionId = `trigger-session-${index}`;
    return firestore.doc(`attendanceSessions/${sessionId}`).set({
      classId: 'trigger-class',
      subjectId,
      date: sessionDate,
    }).then(() => firestore.doc(
      `attendanceRecords/${sessionId}_${studentId}`,
    ).set({
      sessionId,
      studentId,
      subjectId,
      classId: 'trigger-class',
      date: sessionDate,
      status,
    }));
  }));

  await _waitForNotification();
  await firestore.doc(`attendanceRecords/trigger-session-3_${studentId}`).update({
    status: 'present',
  });
  await new Promise((resolve) => setTimeout(resolve, 1500));

  const notifications = await firestore.collection('notifications')
    .where('recipientId', '==', studentId)
    .where('type', '==', 'lowAttendance')
    .get();
  assert.equal(notifications.size, 1);
  assert.equal(notifications.docs[0].id, notificationId);
  assert.equal(notifications.docs[0].get('isRead'), false);
});

async function _waitForNotification() {
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const snapshot = await firestore.collection('notifications').doc(notificationId).get();
    if (snapshot.exists) return;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  assert.fail('Attendance trigger did not create the expected notification.');
}
