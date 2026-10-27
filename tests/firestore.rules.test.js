import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { after, before, beforeEach, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
} from 'firebase/firestore';

const projectId = 'demo-student-attendance';
let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: await readFile(new URL('../firestore/firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'institutionSettings/default'), {
      defaultAttendanceThreshold: 75,
      warningBuffer: 5,
      countApprovedOdAsPresent: false,
      sessionDurationMinutes: 60,
    });
    await setDoc(doc(db, 'users/student-1'), { role: 'student', displayName: 'Student One' });
    await setDoc(doc(db, 'users/student-2'), { role: 'student', displayName: 'Student Two' });
    await setDoc(doc(db, 'users/guardian-1'), { role: 'guardian', displayName: 'Guardian One' });
    await setDoc(doc(db, 'notifications/notice-student-1'), {
      recipientId: 'student-1',
      type: 'lowAttendance',
      title: 'Attendance warning',
      body: 'Attendance is approaching the threshold.',
      relatedId: 'subject-1',
      isRead: false,
      readAt: null,
      createdAt: serverTimestamp(),
    });
    await setDoc(doc(db, 'notifications/notice-student-2'), {
      recipientId: 'student-2',
      type: 'attendanceCorrected',
      title: 'Attendance corrected',
      body: 'A record was corrected.',
      relatedId: 'session-1',
      isRead: false,
      readAt: null,
      createdAt: serverTimestamp(),
    });
    await setDoc(doc(db, 'faculty/faculty-1'), {
      assignedClassIds: ['class-1'],
      assignedSubjectIds: ['subject-1'],
    });
    await setDoc(doc(db, 'attendanceSessions/session-1'), {
      classId: 'class-1', subjectId: 'subject-1', facultyId: 'faculty-1',
      date: '20261027', status: 'open', startedAt: serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + 60_000), closedAt: null,
      closedBy: null, presentCount: 0, absentCount: 0, onDutyCount: 0,
      totalStudents: 2,
    });
    await setDoc(doc(db, 'classes/class-1'), {
      studentIds: ['student-1', 'student-2'], subjectIds: ['subject-1'],
    });
    await setDoc(doc(db, 'students/student-1'), { classId: 'class-1' });
    await setDoc(doc(db, 'students/student-2'), { classId: 'class-1' });
    await setDoc(doc(db, 'attendanceRecords/session-1_student-1'), {
      sessionId: 'session-1', studentId: 'student-1', classId: 'class-1',
      subjectId: 'subject-1', facultyId: 'faculty-1', status: 'absent',
      createdAt: serverTimestamp(), modifiedAt: serverTimestamp(),
    });
    await setDoc(doc(db, 'attendanceRecords/session-1_student-2'), {
      sessionId: 'session-1', studentId: 'student-2', classId: 'class-1',
      subjectId: 'subject-1', facultyId: 'faculty-1', status: 'present',
      createdAt: serverTimestamp(), modifiedAt: serverTimestamp(),
    });
  });
});

test('requires authentication to read institution settings', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, 'institutionSettings/default')));
});

test('allows signed-in users to read institution settings', async () => {
  const db = testEnv.authenticatedContext('student-1', { role: 'student' }).firestore();
  const snapshot = await assertSucceeds(getDoc(doc(db, 'institutionSettings/default')));
  assert.equal(snapshot.data().defaultAttendanceThreshold, 75);
});

test('restricts institution setting writes to admins and valid values', async () => {
  const studentDb = testEnv.authenticatedContext('student-1', { role: 'student' }).firestore();
  await assertFails(updateDoc(doc(studentDb, 'institutionSettings/default'), { warningBuffer: 10 }));

  const adminDb = testEnv.authenticatedContext('admin-1', { role: 'admin' }).firestore();
  await assertSucceeds(updateDoc(doc(adminDb, 'institutionSettings/default'), { warningBuffer: 10 }));
  await assertFails(updateDoc(doc(adminDb, 'institutionSettings/default'), { defaultAttendanceThreshold: 101 }));
});

test('prevents client role assignment or changes, including admin clients', async () => {
  const adminDb = testEnv.authenticatedContext('admin-1', { role: 'admin' }).firestore();
  await assertFails(setDoc(doc(adminDb, 'users/new-user'), { role: 'student', displayName: 'New User' }));
  await assertFails(updateDoc(doc(adminDb, 'users/student-1'), { role: 'admin' }));
  await assertSucceeds(updateDoc(doc(adminDb, 'users/student-1'), { displayName: 'Updated Name' }));
});

test('allows a student to write only a valid threshold on their own profile', async () => {
  const studentDb = testEnv.authenticatedContext('student-1', { role: 'student' }).firestore();
  await assertSucceeds(updateDoc(doc(studentDb, 'users/student-1'), {
    personalAttendanceThreshold: 82,
  }));
  await assertFails(updateDoc(doc(studentDb, 'users/student-1'), {
    personalAttendanceThreshold: 101,
  }));
  await assertFails(updateDoc(doc(studentDb, 'users/student-1'), {
    personalAttendanceThreshold: 80,
    displayName: 'Changed too',
  }));
  await assertFails(updateDoc(doc(studentDb, 'users/student-2'), {
    personalAttendanceThreshold: 80,
  }));
});

test('prevents students from reading another student attendance record', async () => {
  const db = testEnv.authenticatedContext('student-1', { role: 'student' }).firestore();
  await assertFails(getDoc(doc(db, 'attendanceRecords/session-1_student-2')));
});

test('assigned faculty can write deterministic records only while the session is open', async () => {
  const assignedDb = testEnv.authenticatedContext('faculty-1', { role: 'faculty' }).firestore();
  await assertSucceeds(setDoc(doc(assignedDb, 'attendanceRecords/session-1_student-1'), {
    sessionId: 'session-1', studentId: 'student-1', classId: 'class-1',
    subjectId: 'subject-1', facultyId: 'faculty-1', status: 'present',
    createdAt: serverTimestamp(), modifiedAt: serverTimestamp(),
  }));

  const unassignedDb = testEnv.authenticatedContext('faculty-2', { role: 'faculty' }).firestore();
  await assertFails(setDoc(doc(unassignedDb, 'attendanceRecords/session-1_student-1'), {
    sessionId: 'session-1', studentId: 'student-1', classId: 'class-1',
    subjectId: 'subject-1', facultyId: 'faculty-2', status: 'present',
    createdAt: serverTimestamp(), modifiedAt: serverTimestamp(),
  }));
  const studentDb = testEnv.authenticatedContext('student-1', { role: 'student' }).firestore();
  await assertFails(setDoc(doc(studentDb, 'attendanceRecords/session-1_student-1'), {
    sessionId: 'session-1', studentId: 'student-1', classId: 'class-1',
    subjectId: 'subject-1', facultyId: 'student-1', status: 'present',
    createdAt: serverTimestamp(), modifiedAt: serverTimestamp(),
  }));

  await testEnv.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'attendanceSessions/session-1'), {
      expiresAt: Timestamp.fromMillis(Date.now() - 1),
    });
  });
  await assertFails(setDoc(doc(assignedDb, 'attendanceRecords/session-1_student-1'), {
    sessionId: 'session-1', studentId: 'student-1', classId: 'class-1',
    subjectId: 'subject-1', facultyId: 'faculty-1', status: 'present',
    createdAt: serverTimestamp(), modifiedAt: serverTimestamp(),
  }));
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'attendanceSessions/session-1'), {
      expiresAt: Timestamp.fromMillis(Date.now() + 60_000),
      status: 'closed',
    });
  });
  await assertFails(setDoc(doc(assignedDb, 'attendanceRecords/session-1_student-1'), {
    sessionId: 'session-1', studentId: 'student-1', classId: 'class-1',
    subjectId: 'subject-1', facultyId: 'faculty-1', status: 'present',
    createdAt: serverTimestamp(), modifiedAt: serverTimestamp(),
  }));
});

test('clients cannot create or close attendance sessions', async () => {
  const assignedDb = testEnv.authenticatedContext('faculty-1', { role: 'faculty' }).firestore();
  await assertFails(setDoc(doc(assignedDb, 'attendanceSessions/session-2'), {
    classId: 'class-1', subjectId: 'subject-1', facultyId: 'faculty-1',
  }));
  await assertFails(updateDoc(doc(assignedDb, 'attendanceSessions/session-1'), {
    status: 'closed',
  }));
});

test('OD and leave requests are student-owned, validated, and reviewer read-only', async () => {
  const studentDb = testEnv.authenticatedContext('student-1', { role: 'student' }).firestore();
  const request = {
    studentId: 'student-1', classId: 'class-1', subjectId: 'subject-1',
    requestType: 'onDuty', startDate: '2026-10-27', endDate: '2026-10-27',
    reason: 'Representing the college team.', status: 'pending',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  };
  await assertSucceeds(setDoc(doc(studentDb, 'odLeaveRequests/request-1'), request));
  await assertFails(updateDoc(doc(studentDb, 'odLeaveRequests/request-1'), { status: 'approved' }));
  await assertFails(setDoc(doc(studentDb, 'odLeaveRequests/forged'), {
    ...request, studentId: 'student-2',
  }));
  const facultyDb = testEnv.authenticatedContext('faculty-1', { role: 'faculty' }).firestore();
  await assertSucceeds(getDoc(doc(facultyDb, 'odLeaveRequests/request-1')));
  await assertFails(updateDoc(doc(facultyDb, 'odLeaveRequests/request-1'), { status: 'approved' }));
});

test('attendance disputes require the student record and cannot be client-resolved', async () => {
  const studentDb = testEnv.authenticatedContext('student-1', { role: 'student' }).firestore();
  await assertSucceeds(setDoc(doc(studentDb, 'attendanceDisputes/dispute-1'), {
    studentId: 'student-1', sessionId: 'session-1', recordId: 'session-1_student-1',
    classId: 'class-1', subjectId: 'subject-1', date: '2026-10-27',
    reason: 'I attended this class but am marked absent.', status: 'pending',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(doc(studentDb, 'attendanceDisputes/dispute-1'), {
    status: 'resolved',
  }));
  await assertFails(setDoc(doc(studentDb, 'attendanceDisputes/forged'), {
    studentId: 'student-1', sessionId: 'session-1', recordId: 'session-1_student-2',
    classId: 'class-1', subjectId: 'subject-1', date: '2026-10-27',
    reason: 'This is another student record.', status: 'pending',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  }));
});

test('guardian attendance reads require approved student consent', async () => {
  const guardianDb = testEnv.authenticatedContext('guardian-1', { role: 'guardian' }).firestore();
  await assertFails(getDoc(doc(guardianDb, 'attendanceRecords/session-1_student-1')));
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'guardianLinks/guardian-1/students/student-1'), {
      guardianId: 'guardian-1', studentId: 'student-1', status: 'approved',
    });
  });
  await assertSucceeds(getDoc(doc(guardianDb, 'attendanceRecords/session-1_student-1')));
  await assertFails(getDoc(doc(guardianDb, 'attendanceRecords/session-1_student-2')));
  await assertFails(setDoc(doc(guardianDb, 'guardianLinks/guardian-1/students/student-2'), {
    guardianId: 'guardian-1', studentId: 'student-2', status: 'approved',
  }));
});

test('notification reads and read updates are limited to their recipient', async () => {
  const ownDb = testEnv.authenticatedContext('student-1', { role: 'student' }).firestore();
  await assertSucceeds(getDoc(doc(ownDb, 'notifications/notice-student-1')));
  await assertFails(getDoc(doc(ownDb, 'notifications/notice-student-2')));
  await assertSucceeds(updateDoc(doc(ownDb, 'notifications/notice-student-1'), {
    isRead: true,
    readAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(doc(ownDb, 'notifications/notice-student-2'), {
    isRead: true,
    readAt: serverTimestamp(),
  }));
});

test('clients cannot create, delete, or change notification content', async () => {
  const adminDb = testEnv.authenticatedContext('admin-1', { role: 'admin' }).firestore();
  await assertFails(setDoc(doc(adminDb, 'notifications/client-created'), {
    recipientId: 'student-1',
    type: 'lowAttendance',
    title: 'Forged',
    body: 'Forged',
    relatedId: 'subject-1',
    isRead: false,
    readAt: null,
    createdAt: serverTimestamp(),
  }));
  await assertFails(deleteDoc(doc(adminDb, 'notifications/notice-student-1')));
  await assertFails(updateDoc(doc(adminDb, 'notifications/notice-student-1'), {
    title: 'Edited title',
  }));
});
