import 'package:flutter_test/flutter_test.dart';
import 'package:studenterp/models/attendance_enums.dart';
import 'package:studenterp/features/predictor/attendance_predictor.dart';

SubjectAttendanceCounts counts({
  required int present,
  required int total,
  int od = 0,
}) => SubjectAttendanceCounts(
  subjectId: 'subject-1',
  subjectName: 'Data Structures',
  presentSessions: present,
  approvedOdSessions: od,
  totalConducted: total,
);

AttendancePrediction calculate(
  SubjectAttendanceCounts value, {
  double threshold = 0.75,
  double buffer = 0.05,
  bool countOd = false,
}) => AttendancePredictor.calculate(
  counts: value,
  threshold: threshold,
  warningBuffer: buffer,
  countApprovedOdAsPresent: countOd,
);

void main() {
  group('AttendancePredictor.calculate', () {
    test('handles no sessions without dividing by zero', () {
      final result = calculate(counts(present: 0, total: 0));
      expect(result.currentPercentage, 0);
      expect(result.maximumMisses, 0);
      expect(result.classesToReachThreshold, 1);
      expect(result.riskLevel, RiskLevel.critical);
    });

    test('all attended sessions are safe and allow future misses', () {
      final result = calculate(counts(present: 4, total: 4));
      expect(result.currentPercentage, 1);
      expect(result.maximumMisses, 1);
      expect(result.classesToReachThreshold, 0);
      expect(result.isRecoverable, isTrue);
      expect(result.riskLevel, RiskLevel.safe);
    });

    test('zero attended sessions return a recovery count', () {
      final result = calculate(counts(present: 0, total: 4));
      expect(result.currentPercentage, 0);
      expect(result.maximumMisses, 0);
      expect(result.classesToReachThreshold, 12);
      expect(result.riskLevel, RiskLevel.critical);
    });

    test('75 percent is an exact threshold boundary', () {
      final result = calculate(counts(present: 3, total: 4));
      expect(result.currentPercentage, 0.75);
      expect(result.classesToReachThreshold, 0);
      expect(result.maximumMisses, 0);
      expect(result.riskLevel, RiskLevel.atRisk);
    });

    test(
      '100 percent threshold reports below-threshold attendance unrecoverable',
      () {
        final result = calculate(counts(present: 3, total: 4), threshold: 1);
        expect(result.classesToReachThreshold, isNull);
        expect(result.isRecoverable, isFalse);
      },
    );

    test(
      '100 percent threshold is met when every conducted session is attended',
      () {
        final result = calculate(counts(present: 4, total: 4), threshold: 1);
        expect(result.classesToReachThreshold, 0);
        expect(result.isRecoverable, isTrue);
      },
    );

    test('handles large attendance totals', () {
      final result = calculate(counts(present: 800000000, total: 1000000000));
      expect(result.currentPercentage, 0.8);
      expect(result.maximumMisses, 66666666);
      expect(result.riskLevel, RiskLevel.safe);
    });

    test('respects the warning buffer boundaries', () {
      expect(
        calculate(counts(present: 74, total: 100)).riskLevel,
        RiskLevel.critical,
      );
      expect(
        calculate(counts(present: 75, total: 100)).riskLevel,
        RiskLevel.atRisk,
      );
      expect(
        calculate(counts(present: 80, total: 100)).riskLevel,
        RiskLevel.safe,
      );
    });

    test('counts approved OD only when institution policy enables it', () {
      final value = counts(present: 2, od: 1, total: 4);
      final excluded = calculate(value, countOd: false);
      final included = calculate(value, countOd: true);
      expect(excluded.attendedCount, 2);
      expect(excluded.currentPercentage, 0.5);
      expect(included.attendedCount, 3);
      expect(included.currentPercentage, 0.75);
    });
  });

  group('AttendancePredictor.project', () {
    test('projects attended future classes from raw counts', () {
      expect(
        AttendancePredictor.project(
          attended: 6,
          totalConducted: 10,
          attendNext: 3,
          nextClasses: 5,
        ),
        0.6,
      );
    });

    test('rejects projections outside 0 <= X <= N', () {
      expect(
        () => AttendancePredictor.project(
          attended: 2,
          totalConducted: 4,
          attendNext: -1,
          nextClasses: 5,
        ),
        throwsArgumentError,
      );
      expect(
        () => AttendancePredictor.project(
          attended: 2,
          totalConducted: 4,
          attendNext: 6,
          nextClasses: 5,
        ),
        throwsArgumentError,
      );
      expect(
        () => AttendancePredictor.project(
          attended: 2,
          totalConducted: 4,
          attendNext: 1,
          nextClasses: -1,
        ),
        throwsArgumentError,
      );
    });
  });
}
