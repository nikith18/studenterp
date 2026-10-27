import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError, onCall, type CallableRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';

if (getApps().length === 0) initializeApp();
const firestore = getFirestore();
const defaultSessionDurationMinutes = 60;
const minimumSessionDurationMinutes = 5;
const maximumSessionDurationMinutes = 240;
const expiryBatchSize = 100;

function requiredString(value: unknown, name: string): string {
  if (typeof value !== 'string' || value.trim().length === 0 || value.includes('/')) {
    throw new HttpsError('invalid-argument', `${name} is required.`);
  }
  return value;
}

function deterministicSessionId(classId: string, subjectId: string, dateKey: string): string {
  if (!/^\d{8}$/.test(dateKey)) {
    throw new HttpsError('invalid-argument', 'dateKey must use YYYYMMDD format.');
  }
  const encode = (value: string) => Buffer.from(value, 'utf8').toString('base64url');
  return `session_${encode(classId)}~${encode(subjectId)}~${dateKey}`;
}

function requireFaculty(request: CallableRequest<Record<string, unknown>>): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in is required.');
  if (request.auth?.token.role !== 'faculty') {
    throw new HttpsError('permission-denied', 'Faculty access is required.');
  }
  return uid;
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === 'string');
}

export const openAttendanceSession = onCall(async (request) => {
  const facultyId = requireFaculty(request);
  const classId = requiredString(request.data?.classId, 'classId');
  const subjectId = requiredString(request.data?.subjectId, 'subjectId');
  const dateKey = requiredString(request.data?.dateKey, 'dateKey');
  const sessionId = deterministicSessionId(classId, subjectId, dateKey);
  const sessionRef = firestore.doc(`attendanceSessions/${sessionId}`);
  const facultyRef = firestore.doc(`faculty/${facultyId}`);
  const classRef = firestore.doc(`classes/${classId}`);
  const settingsRef = firestore.doc('institutionSettings/default');
  const now = Timestamp.now();

  return firestore.runTransaction(async (transaction) => {
    const [facultySnapshot, classSnapshot, settingsSnapshot, existing] = await Promise.all([
      transaction.get(facultyRef),
      transaction.get(classRef),
      transaction.get(settingsRef),
      transaction.get(sessionRef),
    ]);
    const faculty = facultySnapshot.data() ?? {};
    const classData = classSnapshot.data() ?? {};
    const assignedClasses = faculty.assignedClassIds;
    const assignedSubjects = faculty.assignedSubjectIds;
    const classSubjects = classData.subjectIds;
    const students = classData.studentIds;
    if (!facultySnapshot.exists || !classSnapshot.exists
      || !isStringArray(assignedClasses) || !assignedClasses.includes(classId)
      || !isStringArray(assignedSubjects) || !assignedSubjects.includes(subjectId)
      || !isStringArray(classSubjects) || !classSubjects.includes(subjectId)
      || !isStringArray(students) || students.length === 0) {
      throw new HttpsError('permission-denied', 'This class and subject are not assigned.');
    }
    if (existing.exists) {
      const existingData = existing.data()!;
      if (existingData.status === 'open'
        && (existingData.expiresAt as Timestamp).toMillis() > now.toMillis()) {
        if (existingData.facultyId !== facultyId) {
          throw new HttpsError('permission-denied', 'The active session belongs to another faculty member.');
        }
        return { sessionId };
      }
      throw new HttpsError('already-exists', 'A session already exists for this class, subject, and date.');
    }
    const configuredDuration = settingsSnapshot.get('sessionDurationMinutes');
    const duration = typeof configuredDuration === 'number'
      ? configuredDuration
      : defaultSessionDurationMinutes;
    if (!Number.isInteger(duration) || duration < minimumSessionDurationMinutes
      || duration > maximumSessionDurationMinutes) {
      throw new HttpsError('failed-precondition', 'Session duration settings are invalid.');
    }
    transaction.create(sessionRef, {
      classId,
      subjectId,
      facultyId,
      date: dateKey,
      status: 'open',
      startedAt: now,
      expiresAt: Timestamp.fromMillis(now.toMillis() + duration * 60_000),
      closedAt: null,
      closedBy: null,
      presentCount: 0,
      absentCount: 0,
      onDutyCount: 0,
      totalStudents: new Set(students).size,
    });
    return { sessionId };
  });
});

async function finalizeSession(sessionId: string, closedBy: string, allowedOwner?: string) {
  const sessionRef = firestore.doc(`attendanceSessions/${sessionId}`);
  await firestore.runTransaction(async (transaction) => {
    const sessionSnapshot = await transaction.get(sessionRef);
    if (!sessionSnapshot.exists) throw new HttpsError('not-found', 'Session was not found.');
    const session = sessionSnapshot.data()!;
    if (allowedOwner && session.facultyId !== allowedOwner) {
      throw new HttpsError('permission-denied', 'Only the session owner can close it.');
    }
    if (session.status === 'closed') return;
    const records = await transaction.get(
      firestore.collection('attendanceRecords').where('sessionId', '==', sessionId),
    );
    const latest = new Map<string, string>();
    for (const record of records.docs) {
      const studentId = record.get('studentId');
      const status = record.get('status');
      if (typeof studentId === 'string' && ['present', 'absent', 'onDuty'].includes(status)) {
        latest.set(studentId, status);
      }
    }
    const counts = { presentCount: 0, absentCount: 0, onDutyCount: 0 };
    for (const status of latest.values()) {
      if (status === 'present') counts.presentCount++;
      if (status === 'absent') counts.absentCount++;
      if (status === 'onDuty') counts.onDutyCount++;
    }
    transaction.update(sessionRef, {
      ...counts,
      status: 'closed',
      closedAt: Timestamp.now(),
      closedBy,
    });
  });
}

export const closeAttendanceSession = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in is required.');
  const role = request.auth.token.role;
  if (role !== 'faculty' && role !== 'admin') {
    throw new HttpsError('permission-denied', 'Faculty or admin access is required.');
  }
  const sessionId = requiredString(request.data?.sessionId, 'sessionId');
  await finalizeSession(sessionId, uid, role === 'faculty' ? uid : undefined);
  return { sessionId, status: 'closed' };
});

export const closeExpiredAttendanceSessions = onSchedule('every 1 minutes', async () => {
  const expired = await firestore.collection('attendanceSessions')
    .where('status', '==', 'open')
    .where('expiresAt', '<=', Timestamp.now())
    .limit(expiryBatchSize)
    .get();
  await Promise.all(expired.docs.map(async (session) => {
    try {
      await finalizeSession(session.id, 'system');
    } catch (error) {
      logger.error('Failed to close expired attendance session.', { sessionId: session.id, error });
    }
  }));
});
