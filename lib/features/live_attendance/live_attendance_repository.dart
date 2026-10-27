import 'live_attendance_models.dart';

abstract interface class LiveAttendanceRepository {
  Stream<List<AttendanceAssignment>> watchAssignments(String userId);

  Stream<LiveAttendanceSession?> watchSession(String sessionId);

  Stream<List<SessionStudent>> watchRoster(String classId);

  Stream<List<LiveAttendanceRecord>> watchRecords(String sessionId);

  /// Calls the trusted open-session Function; returns the deterministic ID.
  Future<String> openSession({
    required AttendanceAssignment assignment,
    required String dateKey,
  });

  Future<void> markAttendance({
    required String sessionId,
    required String studentId,
    required AttendanceRecordStatus status,
  });

  /// Implementations should use batched writes for the roster update.
  Future<void> markAllPresent({
    required String sessionId,
    required List<String> studentIds,
  });

  /// Calls the trusted close-session Function.
  Future<void> closeSession(String sessionId);
}

class LiveAttendanceConfigurationException implements Exception {
  const LiveAttendanceConfigurationException();
}

class LiveAttendanceOfflineException implements Exception {
  const LiveAttendanceOfflineException();
}

class AttendanceRecordAlreadyExistsException implements Exception {
  const AttendanceRecordAlreadyExistsException();
}

class LiveAttendanceSessionClosedException implements Exception {
  const LiveAttendanceSessionClosedException();
}

/// Explicit fallback until Firebase Auth and Firestore are configured.
class UnconfiguredLiveAttendanceRepository implements LiveAttendanceRepository {
  const UnconfiguredLiveAttendanceRepository();

  Stream<T> _unavailable<T>() =>
      Stream.error(const LiveAttendanceConfigurationException());

  Future<T> _unavailableFuture<T>() =>
      Future.error(const LiveAttendanceConfigurationException());

  @override
  Stream<List<AttendanceAssignment>> watchAssignments(String userId) =>
      _unavailable();

  @override
  Stream<LiveAttendanceSession?> watchSession(String sessionId) =>
      _unavailable();

  @override
  Stream<List<SessionStudent>> watchRoster(String classId) => _unavailable();

  @override
  Stream<List<LiveAttendanceRecord>> watchRecords(String sessionId) =>
      _unavailable();

  @override
  Future<String> openSession({
    required AttendanceAssignment assignment,
    required String dateKey,
  }) => _unavailableFuture();

  @override
  Future<void> markAttendance({
    required String sessionId,
    required String studentId,
    required AttendanceRecordStatus status,
  }) => _unavailableFuture();

  @override
  Future<void> markAllPresent({
    required String sessionId,
    required List<String> studentIds,
  }) => _unavailableFuture();

  @override
  Future<void> closeSession(String sessionId) => _unavailableFuture();
}
