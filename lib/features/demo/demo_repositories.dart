import 'dart:async';

import '../../models/attendance_enums.dart';
import '../../models/institution_settings.dart';
import '../live_attendance/live_attendance_models.dart';
import '../live_attendance/live_attendance_repository.dart';
import '../notifications/attendance_notification.dart';
import '../notifications/notifications_repository.dart';
import '../predictor/attendance_prediction_repository.dart';
import '../predictor/attendance_predictor.dart';

/// In-memory sample repositories for the explicitly labeled local demo.
class DemoRepositories
    implements
        AttendancePredictionRepository,
        NotificationsRepository,
        LiveAttendanceRepository {
  DemoRepositories._();

  static final instance = DemoRepositories._();
  static const studentId = 'demo-student';
  static const facultyId = 'demo-faculty';
  static const adminId = 'demo-admin';

  final _predictionChanges = StreamController<void>.broadcast();
  final _notificationChanges = StreamController<void>.broadcast();
  final _sessionChanges = StreamController<void>.broadcast();
  int personalThreshold = InstitutionSettings.defaultAttendanceThresholdPercent;
  final Map<String, List<AttendanceNotification>> _notifications = {};
  final Map<String, LiveAttendanceSession> _sessions = {};
  final Map<String, Map<String, LiveAttendanceRecord>> _records = {};
  final List<SessionStudent> roster = const [
    SessionStudent(
      id: 'demo-student',
      name: 'Ananya Sharma',
      rollNumber: 'CS23018',
    ),
    SessionStudent(id: 'CS23001', name: 'Aarav Sharma', rollNumber: 'CS23001'),
    SessionStudent(id: 'CS23002', name: 'Aditi Rao', rollNumber: 'CS23002'),
    SessionStudent(id: 'CS23003', name: 'Arjun Patel', rollNumber: 'CS23003'),
    SessionStudent(id: 'CS23004', name: 'Diya Nair', rollNumber: 'CS23004'),
    SessionStudent(id: 'CS23005', name: 'Ishaan Das', rollNumber: 'CS23005'),
  ];

  static const assignments = [
    AttendanceAssignment(
      classId: 'cse-sem5',
      className: 'CSE · Semester 5',
      subjectId: 'data-structures',
      subjectName: 'Data Structures',
    ),
  ];

  @override
  Stream<AttendancePredictionSnapshot> watchStudent(String id) async* {
    yield _predictionSnapshot();
    await for (final _ in _predictionChanges.stream) {
      yield _predictionSnapshot();
    }
  }

  AttendancePredictionSnapshot _predictionSnapshot() =>
      AttendancePredictionSnapshot(
        subjects: const [
          SubjectAttendanceCounts(
            subjectId: 'data-structures',
            subjectName: 'Data Structures',
            presentSessions: 18,
            approvedOdSessions: 1,
            totalConducted: 24,
          ),
          SubjectAttendanceCounts(
            subjectId: 'database-systems',
            subjectName: 'Database Systems',
            presentSessions: 20,
            approvedOdSessions: 0,
            totalConducted: 24,
          ),
          SubjectAttendanceCounts(
            subjectId: 'operating-systems',
            subjectName: 'Operating Systems',
            presentSessions: 15,
            approvedOdSessions: 0,
            totalConducted: 24,
          ),
        ],
        settings: const InstitutionSettings(),
        personalThresholdPercent: personalThreshold,
      );

  @override
  Future<void> savePersonalThreshold(String id, int percent) async {
    if (percent < 50 || percent > 100) throw ArgumentError.value(percent);
    personalThreshold = percent;
    _predictionChanges.add(null);
  }

  List<AttendanceNotification> _seedNotifications(String id) => [
    AttendanceNotification(
      id: 'demo-low-attendance',
      recipientId: id,
      type: NotificationType.lowAttendance,
      title: 'Attendance needs attention',
      body: 'Operating Systems is below the 75% threshold.',
      isRead: false,
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      relatedId: 'operating-systems',
    ),
    AttendanceNotification(
      id: 'demo-session-saved',
      recipientId: id,
      type: NotificationType.attendanceCorrected,
      title: 'Attendance updated',
      body: 'Data Structures attendance was recorded for today.',
      isRead: true,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      relatedId: 'data-structures',
    ),
  ];

  @override
  Stream<List<AttendanceNotification>> watchForUser(String id) async* {
    _notifications.putIfAbsent(id, () => _seedNotifications(id));
    yield List.unmodifiable(_notifications[id]!);
    await for (final _ in _notificationChanges.stream) {
      yield List.unmodifiable(_notifications[id]!);
    }
  }

  @override
  Future<void> markRead(String userId, String notificationId) async {
    _setRead(userId, {notificationId});
  }

  @override
  Future<void> markAllRead(String userId, List<String> ids) async {
    _setRead(userId, ids.toSet());
  }

  void _setRead(String id, Set<String> ids) {
    _notifications.putIfAbsent(id, () => _seedNotifications(id));
    _notifications[id] = _notifications[id]!
        .map(
          (n) => ids.contains(n.id)
              ? AttendanceNotification(
                  id: n.id,
                  recipientId: n.recipientId,
                  type: n.type,
                  title: n.title,
                  body: n.body,
                  isRead: true,
                  createdAt: n.createdAt,
                  relatedId: n.relatedId,
                  readAt: DateTime.now(),
                )
              : n,
        )
        .toList();
    _notificationChanges.add(null);
  }

  @override
  Stream<List<AttendanceAssignment>> watchAssignments(String userId) async* {
    yield _currentAssignments();
    await for (final _ in _sessionChanges.stream) {
      yield _currentAssignments();
    }
  }

  List<AttendanceAssignment> _currentAssignments() => assignments
      .map((item) {
        final active = _sessions.values
            .where(
              (session) =>
                  session.classId == item.classId &&
                  session.subjectId == item.subjectId &&
                  session.status == SessionStatus.open &&
                  DateTime.now().isBefore(session.expiresAt),
            )
            .firstOrNull;
        return AttendanceAssignment(
          classId: item.classId,
          className: item.className,
          subjectId: item.subjectId,
          subjectName: item.subjectName,
          activeSessionId: active?.id,
        );
      })
      .toList(growable: false);

  @override
  Stream<LiveAttendanceSession?> watchSession(String sessionId) async* {
    yield _sessions[sessionId];
    await for (final _ in _sessionChanges.stream) {
      yield _sessions[sessionId];
    }
  }

  @override
  Stream<List<SessionStudent>> watchRoster(String classId) async* {
    yield roster;
  }

  @override
  Stream<List<LiveAttendanceRecord>> watchRecords(String sessionId) async* {
    yield List.unmodifiable((_records[sessionId] ?? {}).values);
    await for (final _ in _sessionChanges.stream) {
      yield List.unmodifiable((_records[sessionId] ?? {}).values);
    }
  }

  @override
  Future<String> openSession({
    required AttendanceAssignment assignment,
    required String dateKey,
  }) async {
    final id = '${assignment.classId}_${assignment.subjectId}_$dateKey';
    if (_sessions[id]?.status == SessionStatus.open) return id;
    final now = DateTime.now();
    _sessions[id] = LiveAttendanceSession(
      id: id,
      classId: assignment.classId,
      subjectId: assignment.subjectId,
      facultyId: facultyId,
      date: now,
      status: SessionStatus.open,
      startedAt: now,
      expiresAt: now.add(const Duration(minutes: 60)),
      totalStudents: roster.length,
    );
    _records[id] = {};
    _sessionChanges.add(null);
    return id;
  }

  @override
  Future<void> markAttendance({
    required String sessionId,
    required String studentId,
    required AttendanceRecordStatus status,
  }) async {
    final session = _sessions[sessionId];
    if (session == null ||
        session.status == SessionStatus.closed ||
        DateTime.now().isAfter(session.expiresAt)) {
      throw const LiveAttendanceSessionClosedException();
    }
    if (_records[sessionId]!.containsKey(studentId)) {
      throw const AttendanceRecordAlreadyExistsException();
    }
    _records[sessionId]![studentId] = LiveAttendanceRecord(
      id: '${sessionId}_$studentId',
      sessionId: sessionId,
      studentId: studentId,
      status: status,
      facultyId: facultyId,
      createdAt: DateTime.now(),
    );
    _recount(sessionId);
  }

  @override
  Future<void> markAllPresent({
    required String sessionId,
    required List<String> studentIds,
  }) async {
    for (final studentId in studentIds) {
      if (!(_records[sessionId]?.containsKey(studentId) ?? true)) {
        await markAttendance(
          sessionId: sessionId,
          studentId: studentId,
          status: AttendanceRecordStatus.present,
        );
      }
    }
  }

  @override
  Future<void> closeSession(String sessionId) async {
    final s = _sessions[sessionId];
    if (s == null) throw StateError('No demo session is open.');
    _sessions[sessionId] = LiveAttendanceSession(
      id: s.id,
      classId: s.classId,
      subjectId: s.subjectId,
      facultyId: s.facultyId,
      date: s.date,
      status: SessionStatus.closed,
      startedAt: s.startedAt,
      expiresAt: s.expiresAt,
      totalStudents: s.totalStudents,
      closedAt: DateTime.now(),
      closedBy: facultyId,
      presentCount: s.presentCount,
      absentCount: s.absentCount,
      onDutyCount: s.onDutyCount,
    );
    _sessionChanges.add(null);
  }

  void _recount(String id) {
    final s = _sessions[id]!;
    final counts = AttendanceSessionCounts.aggregate(
      totalStudents: roster.length,
      records: _records[id]!.values,
    );
    _sessions[id] = LiveAttendanceSession(
      id: s.id,
      classId: s.classId,
      subjectId: s.subjectId,
      facultyId: s.facultyId,
      date: s.date,
      status: s.status,
      startedAt: s.startedAt,
      expiresAt: s.expiresAt,
      totalStudents: s.totalStudents,
      presentCount: counts.present,
      absentCount: counts.absent,
      onDutyCount: counts.onDuty,
    );
    _sessionChanges.add(null);
  }
}
