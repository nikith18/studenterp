import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/attendance_enums.dart';
import 'live_attendance_models.dart';
import 'live_attendance_repository.dart';

const _uiUpdateThrottle = Duration(milliseconds: 100);

class LiveAttendanceState {
  const LiveAttendanceState({
    required this.loading,
    this.assignments = const [],
    this.selectedAssignment,
    this.session,
    this.roster = const [],
    this.records = const [],
    this.errorMessage,
    this.offline = false,
    this.canRetry = true,
  });

  final bool loading;
  final List<AttendanceAssignment> assignments;
  final AttendanceAssignment? selectedAssignment;
  final LiveAttendanceSession? session;
  final List<SessionStudent> roster;
  final List<LiveAttendanceRecord> records;
  final String? errorMessage;
  final bool offline;
  final bool canRetry;

  bool get sessionDataLoaded => session != null;

  AttendanceSessionCounts get counts {
    final rosterIds = roster.map((student) => student.id).toSet();
    return AttendanceSessionCounts.aggregate(
      totalStudents: session?.totalStudents ?? roster.length,
      records: records.where((record) => rosterIds.contains(record.studentId)),
    );
  }

  List<LiveAttendanceRecord> get markedStudents {
    final studentIds = roster.map((student) => student.id).toSet();
    return records
        .where((record) => studentIds.contains(record.studentId))
        .toList(growable: false);
  }

  List<SessionStudent> get pendingStudents {
    final markedIds = markedStudents.map((record) => record.studentId).toSet();
    return roster
        .where((student) => !markedIds.contains(student.id))
        .toList(growable: false);
  }
}

class LiveAttendanceController extends ChangeNotifier {
  LiveAttendanceController({
    required this.repository,
    required this.userId,
    required this.canEdit,
  });

  final LiveAttendanceRepository repository;
  final String? userId;
  final bool canEdit;
  StreamSubscription<List<AttendanceAssignment>>? _assignmentsSubscription;
  StreamSubscription<LiveAttendanceSession?>? _sessionSubscription;
  StreamSubscription<List<SessionStudent>>? _rosterSubscription;
  StreamSubscription<List<LiveAttendanceRecord>>? _recordsSubscription;
  Timer? _publishTimer;
  LiveAttendanceState _state = const LiveAttendanceState(loading: true);
  List<AttendanceAssignment> _assignments = const [];
  AttendanceAssignment? _selectedAssignment;
  LiveAttendanceSession? _session;
  List<SessionStudent> _roster = const [];
  List<LiveAttendanceRecord> _records = const [];
  bool _assignmentsLoaded = false;
  bool _sessionLoaded = false;
  bool _rosterLoaded = false;
  bool _recordsLoaded = false;
  String? _sessionId;

  LiveAttendanceState get state => _state;

  void start() {
    _cancelSessionSubscriptions();
    _assignmentsSubscription?.cancel();
    final id = userId;
    if (id == null || id.isEmpty) {
      _setError(
        'A signed-in account is unavailable in this local demo.',
        canRetry: false,
      );
      return;
    }
    _state = const LiveAttendanceState(loading: true);
    notifyListeners();
    _assignmentsSubscription = repository.watchAssignments(id).listen((
      assignments,
    ) {
      _assignments = assignments;
      _assignmentsLoaded = true;
      _publish();
    }, onError: _handleStreamError);
  }

  Future<void> openOrViewSession(AttendanceAssignment assignment) async {
    _selectedAssignment = assignment;
    String? sessionId;
    if (canEdit) {
      final now = DateTime.now();
      final dateKey =
          '${now.year}${_twoDigits(now.month)}${_twoDigits(now.day)}';
      sessionId = await repository.openSession(
        assignment: assignment,
        dateKey: dateKey,
      );
    } else {
      sessionId = assignment.activeSessionId;
    }
    if (sessionId == null || sessionId.isEmpty) {
      _selectedAssignment = assignment;
      _session = null;
      _state = LiveAttendanceState(
        loading: false,
        assignments: _assignments,
        selectedAssignment: assignment,
      );
      notifyListeners();
      return;
    }
    await _watchSession(assignment, sessionId);
  }

  Future<void> _watchSession(
    AttendanceAssignment assignment,
    String sessionId,
  ) async {
    _cancelSessionSubscriptions();
    _selectedAssignment = assignment;
    _sessionId = sessionId;
    _session = null;
    _roster = const [];
    _records = const [];
    _sessionLoaded = false;
    _rosterLoaded = false;
    _recordsLoaded = false;
    _state = LiveAttendanceState(
      loading: true,
      assignments: _assignments,
      selectedAssignment: assignment,
    );
    notifyListeners();
    _sessionSubscription = repository.watchSession(sessionId).listen((session) {
      _session = session;
      _sessionLoaded = true;
      _publish();
    }, onError: _handleStreamError);
    _rosterSubscription = repository.watchRoster(assignment.classId).listen((
      students,
    ) {
      _roster = students;
      _rosterLoaded = true;
      _publish();
    }, onError: _handleStreamError);
    _recordsSubscription = repository.watchRecords(sessionId).listen((records) {
      _records = records;
      _recordsLoaded = true;
      _publish();
    }, onError: _handleStreamError);
  }

  void _publish() {
    final loading =
        !_assignmentsLoaded ||
        (_sessionId != null &&
            (!_sessionLoaded || !_rosterLoaded || !_recordsLoaded));
    _state = LiveAttendanceState(
      loading: loading,
      assignments: _assignments,
      selectedAssignment: _selectedAssignment,
      session: _session,
      roster: _roster,
      records: _records,
    );
    _publishTimer?.cancel();
    _publishTimer = Timer(_uiUpdateThrottle, notifyListeners);
  }

  void _handleStreamError(Object error) {
    final offline = error is LiveAttendanceOfflineException;
    _setError(
      offline
          ? 'You are offline. Reconnect to resume live attendance updates.'
          : 'Live attendance could not be loaded. Check Firebase setup and retry.',
      offline: offline,
      canRetry: true,
    );
  }

  void _setError(
    String message, {
    bool offline = false,
    required bool canRetry,
  }) {
    _state = LiveAttendanceState(
      loading: false,
      assignments: _assignments,
      selectedAssignment: _selectedAssignment,
      session: _session,
      roster: _roster,
      records: _records,
      errorMessage: message,
      offline: offline,
      canRetry: canRetry,
    );
    notifyListeners();
  }

  void retry() {
    final assignment = _selectedAssignment;
    final sessionId = _sessionId;
    start();
    if (assignment != null && sessionId != null) {
      _watchSession(assignment, sessionId);
    }
  }

  Future<void> markAttendance(
    String studentId,
    AttendanceRecordStatus status,
  ) async {
    final session = _session;
    final sessionId = _sessionId;
    if (!canEdit || session == null || sessionId == null) {
      throw StateError('Attendance editing is not permitted.');
    }
    if (session.status == SessionStatus.closed ||
        SessionCountdown.calculate(
          now: DateTime.now(),
          expiresAt: session.expiresAt,
          status: session.status,
        ).isExpired) {
      throw const LiveAttendanceSessionClosedException();
    }
    await repository.markAttendance(
      sessionId: sessionId,
      studentId: studentId,
      status: status,
    );
  }

  Future<void> markAllPresent() async {
    final sessionId = _sessionId;
    final session = _session;
    if (!canEdit || sessionId == null || session == null) {
      throw StateError('Attendance editing is not permitted.');
    }
    if (session.status == SessionStatus.closed ||
        SessionCountdown.calculate(
          now: DateTime.now(),
          expiresAt: session.expiresAt,
          status: session.status,
        ).isExpired) {
      throw const LiveAttendanceSessionClosedException();
    }
    await repository.markAllPresent(
      sessionId: sessionId,
      studentIds: _roster.map((student) => student.id).toList(growable: false),
    );
  }

  Future<void> closeSession() async {
    final sessionId = _sessionId;
    if (!canEdit || sessionId == null) {
      throw StateError(
        'Only the owning faculty or an admin can close a session.',
      );
    }
    await repository.closeSession(sessionId);
  }

  void returnToAssignments() {
    _cancelSessionSubscriptions();
    _selectedAssignment = null;
    _sessionId = null;
    _session = null;
    _roster = const [];
    _records = const [];
    _publish();
  }

  void _cancelSessionSubscriptions() {
    _sessionSubscription?.cancel();
    _rosterSubscription?.cancel();
    _recordsSubscription?.cancel();
    _sessionSubscription = null;
    _rosterSubscription = null;
    _recordsSubscription = null;
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  @override
  void dispose() {
    _publishTimer?.cancel();
    _assignmentsSubscription?.cancel();
    _cancelSessionSubscriptions();
    super.dispose();
  }
}
