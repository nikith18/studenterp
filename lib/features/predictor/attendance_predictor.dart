import '../../models/attendance_enums.dart';

/// A single subject's recorded attendance counts, not a stored percentage.
class SubjectAttendanceCounts {
  const SubjectAttendanceCounts({
    required this.subjectId,
    required this.subjectName,
    required this.presentSessions,
    required this.approvedOdSessions,
    required this.totalConducted,
  });

  final String subjectId;
  final String subjectName;
  final int presentSessions;
  final int approvedOdSessions;
  final int totalConducted;
}

/// Calculated attendance values for display and projections.
class AttendancePrediction {
  const AttendancePrediction({
    required this.currentPercentage,
    required this.attendedCount,
    required this.maximumMisses,
    required this.classesToReachThreshold,
    required this.riskLevel,
    required this.isRecoverable,
  });

  /// Fractions from 0 to 1, not percentage points.
  final double currentPercentage;
  final int attendedCount;
  final int maximumMisses;
  final int? classesToReachThreshold;
  final RiskLevel riskLevel;
  final bool isRecoverable;
}

/// Pure attendance calculations. All percentages use fractions from 0 to 1.
class AttendancePredictor {
  const AttendancePredictor._();

  static AttendancePrediction calculate({
    required SubjectAttendanceCounts counts,
    required double threshold,
    required double warningBuffer,
    required bool countApprovedOdAsPresent,
  }) {
    _validateCounts(counts);
    _validateThreshold(threshold);
    _validateBuffer(warningBuffer);

    final attended =
        counts.presentSessions +
        (countApprovedOdAsPresent ? counts.approvedOdSessions : 0);
    final total = counts.totalConducted;
    final percentage = total == 0 ? 0.0 : attended / total;
    final alreadyAtThreshold = total > 0 && percentage >= threshold;
    final isRecoverable = alreadyAtThreshold || threshold < 1;

    final int? classesToReach;
    if (alreadyAtThreshold) {
      classesToReach = 0;
    } else if (threshold == 1) {
      classesToReach = null;
    } else if (total == 0) {
      // With no recorded session, one attended future class is the first
      // meaningful way to reach a threshold; the algebraic result is zero.
      classesToReach = 1;
    } else {
      classesToReach = ((threshold * total - attended) / (1 - threshold))
          .ceil();
    }

    final possibleMisses = total == 0
        ? 0
        : ((attended / threshold) - total).floor();
    final misses = possibleMisses < 0 ? 0 : possibleMisses;
    final risk = percentage >= threshold + warningBuffer
        ? RiskLevel.safe
        : percentage >= threshold
        ? RiskLevel.atRisk
        : RiskLevel.critical;

    return AttendancePrediction(
      currentPercentage: percentage,
      attendedCount: attended,
      maximumMisses: misses,
      classesToReachThreshold: classesToReach,
      riskLevel: risk,
      isRecoverable: isRecoverable,
    );
  }

  static double project({
    required int attended,
    required int totalConducted,
    required int attendNext,
    required int nextClasses,
  }) {
    if (attended < 0 || totalConducted < 0) {
      throw ArgumentError('Attendance counts cannot be negative.');
    }
    if (attended > totalConducted) {
      throw ArgumentError('Attended classes cannot exceed classes conducted.');
    }
    if (nextClasses < 0 || attendNext < 0 || attendNext > nextClasses) {
      throw ArgumentError(
        'Projection must satisfy 0 <= attendNext <= nextClasses.',
      );
    }
    final total = totalConducted + nextClasses;
    return total == 0 ? 0 : (attended + attendNext) / total;
  }

  static void _validateCounts(SubjectAttendanceCounts counts) {
    if (counts.presentSessions < 0 ||
        counts.approvedOdSessions < 0 ||
        counts.totalConducted < 0) {
      throw ArgumentError('Attendance counts cannot be negative.');
    }
    if (counts.presentSessions + counts.approvedOdSessions >
        counts.totalConducted) {
      throw ArgumentError('Present and approved OD counts exceed sessions.');
    }
  }

  static void _validateThreshold(double threshold) {
    if (!threshold.isFinite || threshold <= 0 || threshold > 1) {
      throw ArgumentError.value(threshold, 'threshold', 'Must be in (0, 1].');
    }
  }

  static void _validateBuffer(double warningBuffer) {
    if (!warningBuffer.isFinite || warningBuffer < 0 || warningBuffer > 1) {
      throw ArgumentError.value(
        warningBuffer,
        'warningBuffer',
        'Must be in [0, 1].',
      );
    }
  }
}
