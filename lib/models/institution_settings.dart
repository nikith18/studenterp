/// Institution-wide defaults consumed by attendance and request workflows.
/// Percentages use whole-number percentage points (75 means 75%).
class InstitutionSettings {
  static const percentagePointsPerWhole = 100;
  static const defaultAttendanceThresholdPercent = 75;
  static const defaultWarningBufferPercent = 5;
  static const defaultSessionDurationMinutes = 60;

  const InstitutionSettings({
    this.defaultAttendanceThreshold = defaultAttendanceThresholdPercent,
    this.warningBuffer = defaultWarningBufferPercent,
    this.countApprovedOdAsPresent = false,
    this.sessionDurationMinutes = defaultSessionDurationMinutes,
  });

  static const defaults = InstitutionSettings();

  final int defaultAttendanceThreshold;
  final int warningBuffer;
  final bool countApprovedOdAsPresent;
  final int sessionDurationMinutes;

  factory InstitutionSettings.fromMap(Map<String, Object?> data) {
    return InstitutionSettings(
      defaultAttendanceThreshold:
          (data['defaultAttendanceThreshold'] as num?)?.toInt() ??
          defaultAttendanceThresholdPercent,
      warningBuffer:
          (data['warningBuffer'] as num?)?.toInt() ??
          defaultWarningBufferPercent,
      countApprovedOdAsPresent:
          data['countApprovedOdAsPresent'] as bool? ?? false,
      sessionDurationMinutes:
          (data['sessionDurationMinutes'] as num?)?.toInt() ??
          defaultSessionDurationMinutes,
    );
  }

  Map<String, Object> toMap() => {
    'defaultAttendanceThreshold': defaultAttendanceThreshold,
    'warningBuffer': warningBuffer,
    'countApprovedOdAsPresent': countApprovedOdAsPresent,
    'sessionDurationMinutes': sessionDurationMinutes,
  };
}
