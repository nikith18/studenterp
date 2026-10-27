const assert = require('node:assert/strict');
const { after, before, test } = require('node:test');
const { initializeApp } = require('firebase-admin/app');
const { connectFirestoreEmulator, getFirestore } = require('firebase-admin/firestore');

const projectId = 'demo-student-attendance';
const sessionId = 'sync-session-test';
let writerApp;
let readerApp;
let writer;
let reader;

before(() => {
  const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080').split(':');
  writerApp = initializeApp({ projectId }, 'attendance-sync-writer');
  readerApp = initializeApp({ projectId }, 'attendance-sync-reader');
  writer = getFirestore(writerApp);
  reader = getFirestore(readerApp);
  connectFirestoreEmulator(writer, host, Number(port));
  connectFirestoreEmulator(reader, host, Number(port));
});

after(async () => {
  await writer.doc(`attendanceSessions/${sessionId}`).delete();
  await Promise.all([writerApp.delete(), readerApp.delete()]);
});

test('two emulator clients receive attendance updates through snapshots', async () => {
  const recordRef = reader.doc(`attendanceRecords/${sessionId}_student`);
  const observed = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('Snapshot was not received within two seconds.')), 2_000);
    const unsubscribe = recordRef.onSnapshot((snapshot) => {
      if (snapshot.get('status') === 'present') {
        clearTimeout(timeout);
        unsubscribe();
        resolve(snapshot.get('status'));
      }
    }, reject);
  });
  await writer.doc(`attendanceRecords/${sessionId}_student`).set({
    sessionId,
    studentId: 'student',
    status: 'present',
  });
  assert.equal(await observed, 'present');
  await writer.doc(`attendanceRecords/${sessionId}_student`).delete();
});
