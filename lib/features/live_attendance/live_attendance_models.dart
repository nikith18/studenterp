import 'dart:convert';

import '../../models/attendance_enums.dart';

String deterministicSessionId({
  required String classId,
  required String subjectId,
  required String dateKey,
}) {
  if (classId.isEmpty ||
      subjectId.isEmpty ||
      !RegExp(r'^\d{8}$').hasMatch(dateKey)) {
    throw ArgumentError('Class, subject, and YYYYMMDD date are required.');
  }
  final classPart = base64Url.encode(utf8.encode(classId)).replaceAll('=', '');
  final subjectPart = base64Url
      .encode(utf8.encode(subjectId))
      .replaceAll('=', '');
  return 'session_$classPart~$subjectPart~$dateKey';
}

class AttendanceAssignment {
  const AttendanceAssignment({
    required this.classId,
    required this.className,
    required this.subjectId,
    required this.subjectName,
    this.activeSessionId,
  });

  final String classId;
  final String className;
  final String subjectId;
  final String subjectName;
  final String? activeSessionId;
}

class SessionStudent {
  const SessionStudent({
    required this.id,
    required this.name,
    required this.rollNumber,
  });

  final String id;
  final String name;
  final String rollNumber;
}

class LiveAttendanceRecord {
  const LiveAttendanceRecord({
    required this.id,
    required this.sessionId,
    required this.studentId,
    required this.status,
    required this.facultyId,
    required this.createdAt,
    this.modifiedAt,
  });

  final String id;
  final String sessionId;
  final String studentId;
  final AttendanceRecordStatus status;
  final String facultyId;
  final DateTime createdAt;
  final DateTime? modifiedAt;
}

class LiveAttendanceSession {
  const LiveAttendanceSession({
    required this.id,
    required this.classId,
    required this.subjectId,
    required this.facultyId,
    required this.date,
    required this.status,
    required this.startedAt,
    required this.expiresAt,
    required this.totalStudents,
    this.closedAt,
    this.closedBy,
    this.presentCount = 0,
    this.absentCount = 0,
    this.onDutyCount = 0,
  });

  final String id;
  final String classId;
  final String subjectId;
  final String facultyId;
  final DateTime date;
  final SessionStatus status;
  final DateTime startedAt;
  final DateTime expiresAt;
  final DateTime? closedAt;
  final String? closedBy;
  final int presentCount;
  final int absentCount;
  final int onDutyCount;
  final int totalStudents;
}

class AttendanceSessionCounts {
  const AttendanceSessionCounts({
    required this.present,
    required this.absent,
    required this.onDuty,
    required this.pending,
  });

  final int present;
  final int absent;
  final int onDuty;
  final int pending;

  factory AttendanceSessionCounts.aggregate({
    required int totalStudents,
    required Iterable<LiveAttendanceRecord> records,
  }) {
    final latestByStudent = <String, LiveAttendanceRecord>{};
    for (final record in records) {
      latestByStudent[record.studentId] = record;
    }
    var present = 0;
    var absent = 0;
    var onDuty = 0;
    for (final record in latestByStudent.values) {
      switch (record.status) {
        case AttendanceRecordStatus.present:
          present++;
        case AttendanceRecordStatus.absent:
          absent++;
        case AttendanceRecordStatus.onDuty:
          onDuty++;
      }
    }
    final pending = totalStudents - latestByStudent.length;
    return AttendanceSessionCounts(
      present: present,
      absent: absent,
      onDuty: onDuty,
      pending: pending < 0 ? 0 : pending,
    );
  }
}

class SessionCountdown {
  const SessionCountdown({
    required this.remaining,
    required this.isClosed,
    required this.isExpired,
  });

  final Duration remaining;
  final bool isClosed;
  final bool isExpired;

  factory SessionCountdown.calculate({
    required DateTime now,
    required DateTime expiresAt,
    required SessionStatus status,
  }) {
    final left = expiresAt.difference(now);
    final closed = status == SessionStatus.closed;
    final expired = !closed && !now.isBefore(expiresAt);
    return SessionCountdown(
      remaining: left.isNegative ? Duration.zero : left,
      isClosed: closed,
      isExpired: expired,
    );
  }
}

enum AttendanceRecordStatus { present, absent, onDuty }
