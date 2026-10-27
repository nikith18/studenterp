import 'package:flutter_test/flutter_test.dart';
import 'package:studenterp/models/attendance_enums.dart';
import 'package:studenterp/models/institution_settings.dart';

void main() {
  group('InstitutionSettings', () {
    test('uses the institution defaults', () {
      expect(InstitutionSettings.defaults.defaultAttendanceThreshold, 75);
      expect(InstitutionSettings.defaults.warningBuffer, 5);
      expect(InstitutionSettings.defaults.countApprovedOdAsPresent, isFalse);
    });

    test('round trips its Firestore representation', () {
      const settings = InstitutionSettings(
        defaultAttendanceThreshold: 80,
        warningBuffer: 7,
        countApprovedOdAsPresent: true,
      );

      expect(
        InstitutionSettings.fromMap(settings.toMap()).toMap(),
        settings.toMap(),
      );
    });

    test('fills missing fields from defaults', () {
      final settings = InstitutionSettings.fromMap({'warningBuffer': 8});

      expect(settings.defaultAttendanceThreshold, 75);
      expect(settings.warningBuffer, 8);
      expect(settings.countApprovedOdAsPresent, isFalse);
    });
  });

  test('shared feature enums expose the expected states', () {
    expect(RequestStatus.values, contains(RequestStatus.pending));
    expect(DisputeStatus.values, contains(DisputeStatus.underReview));
    expect(
      SessionStatus.values,
      containsAll([SessionStatus.open, SessionStatus.closed]),
    );
    expect(
      RiskLevel.values,
      containsAll([RiskLevel.safe, RiskLevel.atRisk, RiskLevel.critical]),
    );
    expect(NotificationType.values, contains(NotificationType.disputeUpdate));
  });
}
