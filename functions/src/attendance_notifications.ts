import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type DocumentData, type Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { createNotification } from './notification_service.js';

const defaultThresholdPercent = 75;
const defaultWarningBufferPercent = 5;
const minimumThresholdPercent = 50;
const maximumThresholdPercent = 100;
const percentagePointsPerWhole = 100;

if (getApps().length === 0) initializeApp();
const firestore = getFirestore();
const settingsDocument = firestore.doc('institutionSettings/default');

type AttendanceRecord = DocumentData & {
  studentId?: string;
  sessionId?: string;
  subjectId?: string;
  status?: string;
  date?: string | Date | Timestamp;
  attendanceDate?: string | Date | Timestamp;
  modifiedAt?: Timestamp | Date | string | number;
  auditVersion?: string | number;
  audit?: unknown;
  odApproved?: boolean;
};

type Settings = {
  defaultAttendanceThreshold?: number;
  warningBuffer?: number;
  countApprovedOdAsPresent?: boolean;
};

function timestampVersion(value: AttendanceRecord['modifiedAt']): string | undefined {
  if (value && typeof value === 'object' && 'toMillis' in value) {
    return String((value as Timestamp).toMillis());
  }
  if (value instanceof Date) return String(value.getTime());
  if (value === undefined || value === null) return undefined;
  return String(value);
}

function dateKey(value: AttendanceRecord['date'], fallback: string): string {
  let date: Date;
  if (value instanceof Date) date = value;
  else if (value && typeof value === 'object' && 'toDate' in value) {
    date = (value as Timestamp).toDate();
  } else if (typeof value === 'string' || typeof value === 'number') {
    const parsed = new Date(value);
    date = Number.isNaN(parsed.getTime()) ? new Date(fallback) : parsed;
  } else {
    date = new Date(fallback);
  }
  return date.toISOString().slice(0, 10).replaceAll('-', '');
}

function correctionChanged(before: AttendanceRecord, after: AttendanceRecord): boolean {
  return timestampVersion(before.modifiedAt) !== timestampVersion(after.modifiedAt)
    || before.auditVersion !== after.auditVersion
    || JSON.stringify(before.audit ?? null) !== JSON.stringify(after.audit ?? null);
}

export const attendanceRecordWritten = onDocumentWritten(
  {
    document: 'attendanceRecords/{recordId}',
    retry: true,
  },
  async (event) => {
    const beforeSnapshot = event.data?.before;
    const afterSnapshot = event.data?.after;
    if (!afterSnapshot?.exists) return;

    const after = afterSnapshot.data() as AttendanceRecord;
    const studentId = after.studentId;
    const subjectId = after.subjectId;
    if (!studentId || !subjectId) {
      logger.warn('Skipping notification for an attendance record missing identifiers.', {
        path: afterSnapshot.ref.path,
      });
      return;
    }

    const [settingsSnapshot, userSnapshot, sessionSnapshot] = await Promise.all([
      settingsDocument.get(),
      firestore.doc(`users/${studentId}`).get(),
      after.sessionId
        ? firestore.doc(`attendanceSessions/${after.sessionId}`).get()
        : Promise.resolve(undefined),
    ]);
    const settings = (settingsSnapshot.data() ?? {}) as Settings;
    const personalThreshold = userSnapshot.get('personalAttendanceThreshold');
    const threshold = typeof personalThreshold === 'number'
      ? personalThreshold
      : settings.defaultAttendanceThreshold ?? defaultThresholdPercent;
    const warningBuffer = settings.warningBuffer ?? defaultWarningBufferPercent;
    if (
      threshold < minimumThresholdPercent ||
      threshold > maximumThresholdPercent ||
      warningBuffer < 0 ||
      warningBuffer > maximumThresholdPercent - minimumThresholdPercent
    ) {
      logger.error('Skipping attendance notification for invalid settings.', { studentId });
      return;
    }

    const records = await firestore
      .collection('attendanceRecords')
      .where('studentId', '==', studentId)
      .where('subjectId', '==', subjectId)
      .get();
    let conducted = 0;
    let present = 0;
    let approvedOd = 0;
    for (const record of records.docs) {
      const status = record.get('status');
      if (!['present', 'absent', 'onDuty'].includes(status)) continue;
      conducted += 1;
      if (status === 'present') present += 1;
      if (status === 'onDuty' && record.get('odApproved') === true) approvedOd += 1;
    }
    if (conducted === 0) return;

    const countedPresent = present
      + (settings.countApprovedOdAsPresent === true ? approvedOd : 0);
    const percentage = countedPresent / conducted * percentagePointsPerWhole;
    const recordDate = after.attendanceDate ?? after.date
      ?? sessionSnapshot?.get('date');
    const day = dateKey(recordDate, event.time);
    const relatedId = after.sessionId ?? event.params.recordId;
    const safeSubjectId = subjectId.replaceAll('/', '_');
    const band = percentage < threshold ? 'below' : 'warning';
    if (percentage < threshold + warningBuffer) {
      const created = await createNotification(firestore, {
        dedupeKey: `lowAttendance_${studentId}_${safeSubjectId}_${day}`,
        recipientId: studentId,
        type: 'lowAttendance',
        title: band === 'below' ? 'Attendance below threshold' : 'Attendance warning',
        body: band === 'below'
          ? `${subjectId} attendance is ${percentage.toFixed(1)}%, below your ${threshold}% threshold.`
          : `${subjectId} attendance is ${percentage.toFixed(1)}%, within ${warningBuffer} percentage points of your threshold.`,
        relatedId,
      });
      if (created) logger.info('Created low attendance notification.', { studentId, subjectId, day });

      const guardianLinks = await firestore.collectionGroup('students')
        .where('studentId', '==', studentId)
        .where('status', '==', 'approved')
        .get();
      await Promise.all(guardianLinks.docs.map(async (link) => {
        const guardianId = link.get('guardianId');
        if (typeof guardianId !== 'string' || guardianId.length === 0) return;
        await createNotification(firestore, {
          dedupeKey: `lowAttendanceGuardian_${guardianId}_${studentId}_${safeSubjectId}_${day}`,
          recipientId: guardianId,
          type: 'lowAttendance',
          title: 'Linked student attendance alert',
          body: `${studentId}'s ${subjectId} attendance is ${percentage.toFixed(1)}%, below or near the ${threshold}% threshold.`,
          relatedId,
        });
      }));
    }

    const before = beforeSnapshot?.exists
      ? beforeSnapshot.data() as AttendanceRecord
      : undefined;
    if (before && correctionChanged(before, after)) {
      const version = timestampVersion(after.modifiedAt)
        ?? String(after.auditVersion ?? event.id);
      const recordKey = `${after.sessionId ?? 'session'}_${studentId}`
        .replaceAll('/', '_');
      await createNotification(firestore, {
        dedupeKey: `correction_${recordKey}_${version}`,
        recipientId: studentId,
        type: 'attendanceCorrected',
        title: 'Attendance record corrected',
        body: 'A recorded attendance entry was corrected.',
        relatedId,
      });
    }
  },
);
