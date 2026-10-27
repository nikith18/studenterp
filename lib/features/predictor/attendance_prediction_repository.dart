import '../../models/institution_settings.dart';
import 'attendance_predictor.dart';

class AttendancePredictionSnapshot {
  const AttendancePredictionSnapshot({
    required this.subjects,
    required this.settings,
    this.personalThresholdPercent,
  });

  final List<SubjectAttendanceCounts> subjects;
  final InstitutionSettings settings;
  final int? personalThresholdPercent;
}

abstract interface class AttendancePredictionRepository {
  Stream<AttendancePredictionSnapshot> watchStudent(String studentId);

  Future<void> savePersonalThreshold(String studentId, int thresholdPercent);
}

class AttendancePredictionConfigurationException implements Exception {
  const AttendancePredictionConfigurationException();

  @override
  String toString() => 'Firebase attendance prediction is not configured.';
}

class AttendancePredictionOfflineException implements Exception {
  const AttendancePredictionOfflineException();
}

/// Explicit placeholder until Firebase Auth and Firestore are configured.
/// It never supplies demo or fabricated attendance values.
class UnconfiguredAttendancePredictionRepository
    implements AttendancePredictionRepository {
  const UnconfiguredAttendancePredictionRepository();

  @override
  Stream<AttendancePredictionSnapshot> watchStudent(String studentId) {
    return Stream.error(const AttendancePredictionConfigurationException());
  }

  @override
  Future<void> savePersonalThreshold(String studentId, int thresholdPercent) {
    return Future.error(const AttendancePredictionConfigurationException());
  }
}
