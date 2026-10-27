import { FieldValue, type Firestore } from 'firebase-admin/firestore';

export type NotificationKind =
  | 'lowAttendance'
  | 'attendanceCorrected'
  | 'reportReady'
  | 'requestDecision'
  | 'disputeUpdate';

export interface CreateNotificationInput {
  dedupeKey: string;
  recipientId: string;
  type: NotificationKind;
  title: string;
  body: string;
  relatedId: string;
}

/** Creates once per deterministic document ID. Retries become no-ops. */
export async function createNotification(
  firestore: Firestore,
  input: CreateNotificationInput,
): Promise<boolean> {
  if (!input.dedupeKey || input.dedupeKey.includes('/')) {
    throw new Error('Notification dedupeKey must be a non-empty document ID.');
  }
  const reference = firestore.collection('notifications').doc(input.dedupeKey);
  try {
    await reference.create({
      recipientId: input.recipientId,
      type: input.type,
      title: input.title,
      body: input.body,
      relatedId: input.relatedId,
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
      readAt: null,
    });
    return true;
  } catch (error) {
    const code = (error as { code?: string | number }).code;
    if (code === 6 || code === 'already-exists') return false;
    throw error;
  }
}
