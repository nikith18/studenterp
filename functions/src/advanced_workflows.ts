import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { createNotification } from './notification_service.js';

if (getApps().length === 0) initializeApp();
const firestore = getFirestore();

type Role = 'admin' | 'faculty' | 'student' | 'guardian';
type CallableData = Record<string, unknown>;

function auth(request: { auth?: { uid: string; token: Record<string, unknown> } | null }, roles: Role[]) {
  const uid = request.auth?.uid;
  const role = request.auth?.token.role;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in is required.');
  if (typeof role !== 'string' || !roles.includes(role as Role)) {
    throw new HttpsError('permission-denied', 'This account is not allowed to perform this action.');
  }
  return { uid, role: role as Role };
}

function text(value: unknown, label: string, maximum = 1000): string {
  if (typeof value !== 'string' || value.trim().length < 1 || value.length > maximum) {
    throw new HttpsError('invalid-argument', `${label} is required and must be at most ${maximum} characters.`);
  }
  return value.trim();
}

function id(value: unknown, label: string): string {
  const result = text(value, label, 128);
  if (result.includes('/')) throw new HttpsError('invalid-argument', `${label} is invalid.`);
  return result;
}

async function assertCanReview(
  transaction: FirebaseFirestore.Transaction,
  uid: string,
  role: Role,
  classId: string,
  subjectId: string | undefined,
) {
  if (role === 'admin') return;
  if (role !== 'faculty') throw new HttpsError('permission-denied', 'Reviewer access is required.');
  const faculty = await transaction.get(firestore.doc(`faculty/${uid}`));
  const data = faculty.data() ?? {};
  const classes = data.assignedClassIds;
  const subjects = data.assignedSubjectIds;
  if (!Array.isArray(classes) || !classes.includes(classId)
    || (subjectId && (!Array.isArray(subjects) || !subjects.includes(subjectId)))) {
    throw new HttpsError('permission-denied', 'This class or subject is not assigned to you.');
  }
}

export const reviewOdLeaveRequest = onCall(async (request) => {
  const { uid, role } = auth(request, ['admin', 'faculty']);
  const requestId = id((request.data as CallableData | undefined)?.requestId, 'requestId');
  const decision = (request.data as CallableData | undefined)?.decision;
  if (decision !== 'approved' && decision !== 'rejected') {
    throw new HttpsError('invalid-argument', 'Decision must be approved or rejected.');
  }
  const decisionReason = text((request.data as CallableData | undefined)?.decisionReason, 'decisionReason');
  const ref = firestore.doc(`odLeaveRequests/${requestId}`);
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new HttpsError('not-found', 'Request was not found.');
    const item = snapshot.data()!;
    if (item.status !== 'pending') throw new HttpsError('failed-precondition', 'This request has already been reviewed.');
    await assertCanReview(transaction, uid, role, item.classId, item.subjectId);
    const decidedAt = Timestamp.now();
    transaction.update(ref, {
      status: decision,
      reviewerId: uid,
      reviewerRole: role,
      decisionReason,
      decidedAt,
      updatedAt: decidedAt,
      decisionHistory: [{ status: decision, reviewerId: uid, reason: decisionReason, at: decidedAt }],
    });
  });
  return { requestId, status: decision };
});

export const reviewAttendanceDispute = onCall(async (request) => {
  const { uid, role } = auth(request, ['admin', 'faculty']);
  const data = request.data as CallableData;
  const disputeId = id(data.disputeId, 'disputeId');
  const status = data.status;
  if (!['underReview', 'resolved', 'rejected'].includes(String(status))) {
    throw new HttpsError('invalid-argument', 'Unsupported dispute status.');
  }
  const decisionReason = text(data.decisionReason, 'decisionReason');
  const correctedStatus = data.correctedStatus;
  if (correctedStatus !== undefined
    && (status !== 'resolved' || !['present', 'absent', 'onDuty'].includes(String(correctedStatus)))) {
    throw new HttpsError('invalid-argument', 'A correction must be a valid status on a resolved dispute.');
  }
  const disputeRef = firestore.doc(`attendanceDisputes/${disputeId}`);
  await firestore.runTransaction(async (transaction) => {
    const disputeSnapshot = await transaction.get(disputeRef);
    if (!disputeSnapshot.exists) throw new HttpsError('not-found', 'Dispute was not found.');
    const dispute = disputeSnapshot.data()!;
    if (['resolved', 'rejected'].includes(dispute.status)) {
      throw new HttpsError('failed-precondition', 'This dispute is already closed.');
    }
    const recordRef = firestore.doc(`attendanceRecords/${dispute.recordId}`);
    const recordSnapshot = correctedStatus === undefined ? undefined : await transaction.get(recordRef);
    await assertCanReview(transaction, uid, role, dispute.classId, dispute.subjectId);
    const now = Timestamp.now();
    if (recordSnapshot?.exists) {
      const before = recordSnapshot.get('status');
      if (before !== correctedStatus) {
        const audit = Array.isArray(recordSnapshot.get('audit')) ? recordSnapshot.get('audit') as unknown[] : [];
        audit.push({
          oldStatus: before,
          newStatus: correctedStatus,
          modifiedBy: uid,
          modifiedAt: now,
          disputeId,
          reason: decisionReason,
        });
        transaction.update(recordRef, {
          status: correctedStatus,
          modifiedAt: now,
          modifiedBy: uid,
          auditVersion: Number(recordSnapshot.get('auditVersion') ?? 0) + 1,
          audit: audit.slice(-20),
        });
      }
    } else if (correctedStatus !== undefined) {
      throw new HttpsError('not-found', 'Attendance record was not found.');
    }
    const notificationVersion = Number(dispute.notificationVersion ?? 0) + 1;
    transaction.update(disputeRef, {
      status,
      reviewerId: uid,
      reviewerRole: role,
      decisionReason,
      decidedAt: status === 'underReview' ? null : now,
      updatedAt: now,
      correctedStatus: correctedStatus ?? null,
      notificationVersion,
    });
  });
  return { disputeId, status };
});

export const odLeaveDecisionWritten = onDocumentUpdated(
  'odLeaveRequests/{requestId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status
      || !['approved', 'rejected'].includes(String(after.status))) return;
    await createNotification(firestore, {
      dedupeKey: `request_${event.params.requestId}_${String(after.status)}`,
      recipientId: String(after.studentId),
      type: 'requestDecision',
      title: `Your ${after.requestType === 'onDuty' ? 'On Duty' : 'leave'} request was ${after.status}.`,
      body: String(after.decisionReason ?? 'Your request was reviewed.'),
      relatedId: event.params.requestId,
    });
  },
);

export const attendanceDisputeUpdated = onDocumentUpdated(
  'attendanceDisputes/{disputeId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.notificationVersion === after.notificationVersion) return;
    await createNotification(firestore, {
      dedupeKey: `dispute_${event.params.disputeId}_${String(after.notificationVersion)}`,
      recipientId: String(after.studentId),
      type: 'disputeUpdate',
      title: `Attendance dispute ${after.status === 'underReview' ? 'under review' : String(after.status)}.`,
      body: String(after.decisionReason ?? 'Your attendance dispute was updated.'),
      relatedId: event.params.disputeId,
    });
  },
);

export const requestGuardianAccess = onCall(async (request) => {
  const { uid } = auth(request, ['guardian']);
  const studentId = id((request.data as CallableData).studentId, 'studentId');
  const student = await firestore.doc(`users/${studentId}`).get();
  if (!student.exists || student.get('role') !== 'student' || student.get('active') === false) {
    throw new HttpsError('not-found', 'An active student account was not found.');
  }
  const ref = firestore.doc(`guardianLinks/${uid}/students/${studentId}`);
  await firestore.runTransaction(async (transaction) => {
    const existing = await transaction.get(ref);
    if (existing.exists && existing.get('status') === 'approved') {
      throw new HttpsError('already-exists', 'Guardian access is already active.');
    }
    transaction.set(ref, {
      guardianId: uid,
      studentId,
      status: 'pendingStudentConsent',
      requestedAt: Timestamp.now(),
      consentedAt: null,
      revokedAt: null,
    });
  });
  return { studentId, status: 'pendingStudentConsent' };
});

export const respondGuardianAccess = onCall(async (request) => {
  const { uid } = auth(request, ['student']);
  const data = request.data as CallableData;
  const guardianId = id(data.guardianId, 'guardianId');
  const decision = data.decision;
  if (decision !== 'approved' && decision !== 'rejected') {
    throw new HttpsError('invalid-argument', 'Decision must be approved or rejected.');
  }
  const ref = firestore.doc(`guardianLinks/${guardianId}/students/${uid}`);
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists || snapshot.get('status') !== 'pendingStudentConsent') {
      throw new HttpsError('failed-precondition', 'There is no pending consent request.');
    }
    const now = Timestamp.now();
    transaction.update(ref, {
      status: decision,
      consentedAt: decision === 'approved' ? now : null,
      reviewedAt: now,
      reviewedBy: uid,
    });
  });
  return { studentId: uid, status: decision };
});

export const revokeGuardianAccess = onCall(async (request) => {
  const { uid, role } = auth(request, ['student', 'guardian']);
  const data = request.data as CallableData;
  const studentId = id(data.studentId, 'studentId');
  const guardianId = role === 'guardian' ? uid : id(data.guardianId, 'guardianId');
  if (role === 'student' && studentId !== uid) {
    throw new HttpsError('permission-denied', 'Students can revoke access only to their own account.');
  }
  const ref = firestore.doc(`guardianLinks/${guardianId}/students/${studentId}`);
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new HttpsError('not-found', 'Guardian link was not found.');
    const now = Timestamp.now();
    transaction.update(ref, { status: 'revoked', revokedAt: now, revokedBy: uid });
  });
  return { studentId, guardianId, status: 'revoked' };
});
