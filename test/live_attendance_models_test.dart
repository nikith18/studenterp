import 'package:flutter_test/flutter_test.dart';
import 'package:studenterp/features/live_attendance/live_attendance_models.dart';
import 'package:studenterp/models/attendance_enums.dart';

void main() {
  group('AttendanceSessionCounts', () {
    test('aggregates records and leaves the remainder pending', () {
      final counts = AttendanceSessionCounts.aggregate(
        totalStudents: 5,
        records: [
          _record('s1', AttendanceRecordStatus.present),
          _record('s2', AttendanceRecordStatus.absent),
          _record('s3', AttendanceRecordStatus.onDuty),
        ],
      );
      expect(counts.present, 1);
      expect(counts.absent, 1);
      expect(counts.onDuty, 1);
      expect(counts.pending, 2);
    });

    test('deduplicates student records and never reports negative pending', () {
      final counts = AttendanceSessionCounts.aggregate(
        totalStudents: 1,
        records: [
          _record('s1', AttendanceRecordStatus.absent),
          _record('s1', AttendanceRecordStatus.present),
          _record('s2', AttendanceRecordStatus.onDuty),
        ],
      );
      expect(counts.present, 1);
      expect(counts.absent, 0);
      expect(counts.pending, 0);
    });
  });

  group('SessionCountdown', () {
    final expiry = DateTime.utc(2026, 10, 27, 12);

    test('counts down before expiry', () {
      final result = SessionCountdown.calculate(
        now: expiry.subtract(const Duration(seconds: 45)),
        expiresAt: expiry,
        status: SessionStatus.open,
      );
      expect(result.remaining, const Duration(seconds: 45));
      expect(result.isExpired, isFalse);
    });

    test('expires at the exact expiry instant and clamps after it', () {
      for (final now in [expiry, expiry.add(const Duration(seconds: 1))]) {
        final result = SessionCountdown.calculate(
          now: now,
          expiresAt: expiry,
          status: SessionStatus.open,
        );
        expect(result.remaining, Duration.zero);
        expect(result.isExpired, isTrue);
      }
    });

    test('closed session is not reported expired', () {
      final result = SessionCountdown.calculate(
        now: expiry.add(const Duration(days: 1)),
        expiresAt: expiry,
        status: SessionStatus.closed,
      );
      expect(result.isClosed, isTrue);
      expect(result.isExpired, isFalse);
      expect(result.remaining, Duration.zero);
    });
  });

  test('session ID is deterministic for class, subject and day', () {
    expect(
      deterministicSessionId(
        classId: 'class-1',
        subjectId: 'subject-1',
        dateKey: '20261027',
      ),
      deterministicSessionId(
        classId: 'class-1',
        subjectId: 'subject-1',
        dateKey: '20261027',
      ),
    );
    expect(
      () => deterministicSessionId(
        classId: 'class-1',
        subjectId: 'subject-1',
        dateKey: 'today',
      ),
      throwsArgumentError,
    );
  });
}

LiveAttendanceRecord _record(String studentId, AttendanceRecordStatus status) =>
    LiveAttendanceRecord(
      id: 'session_$studentId',
      sessionId: 'session',
      studentId: studentId,
      status: status,
      facultyId: 'faculty',
      createdAt: DateTime.utc(2026),
    );
