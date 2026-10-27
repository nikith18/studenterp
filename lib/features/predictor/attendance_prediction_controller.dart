import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/institution_settings.dart';
import 'attendance_prediction_repository.dart';
import 'attendance_predictor.dart';

class SubjectPrediction {
  const SubjectPrediction({required this.counts, required this.result});

  final SubjectAttendanceCounts counts;
  final AttendancePrediction result;
}

enum PredictionLoadStatus { loading, loaded, error }

const minimumPersonalThresholdPercent = 50;
const maximumPersonalThresholdPercent = 100;

class AttendancePredictionState {
  const AttendancePredictionState({
    required this.status,
    this.subjects = const [],
    this.thresholdPercent =
        InstitutionSettings.defaultAttendanceThresholdPercent,
    this.errorMessage,
    this.offline = false,
    this.canRetry = true,
  });

  final PredictionLoadStatus status;
  final List<SubjectPrediction> subjects;
  final int thresholdPercent;
  final String? errorMessage;
  final bool offline;
  final bool canRetry;
}

/// Recalculates predictions for every emission from the repository stream.
class AttendancePredictionController extends ChangeNotifier {
  AttendancePredictionController({
    required this.repository,
    required this.studentId,
  });

  final AttendancePredictionRepository repository;
  final String? studentId;
  StreamSubscription<AttendancePredictionSnapshot>? _subscription;
  AttendancePredictionState _state = const AttendancePredictionState(
    status: PredictionLoadStatus.loading,
  );

  AttendancePredictionState get state => _state;

  void start() {
    _subscription?.cancel();
    final id = studentId;
    if (id == null || id.isEmpty) {
      _setError(
        'A signed-in student profile is unavailable in this local demo.',
        false,
        canRetry: false,
      );
      return;
    }
    _state = const AttendancePredictionState(
      status: PredictionLoadStatus.loading,
    );
    notifyListeners();
    _subscription = repository
        .watchStudent(id)
        .listen(
          _update,
          onError: (Object error) => _setError(
            error is AttendancePredictionOfflineException
                ? 'You are offline. Reconnect and retry to refresh attendance.'
                : 'Live attendance is unavailable. Check Firebase setup and retry.',
            error is AttendancePredictionOfflineException,
            canRetry: true,
          ),
        );
  }

  void _update(AttendancePredictionSnapshot snapshot) {
    try {
      final thresholdPercent =
          snapshot.personalThresholdPercent ??
          snapshot.settings.defaultAttendanceThreshold;
      if (thresholdPercent < minimumPersonalThresholdPercent ||
          thresholdPercent > maximumPersonalThresholdPercent) {
        throw const FormatException(
          'Threshold is outside the supported range.',
        );
      }
      final threshold =
          thresholdPercent / InstitutionSettings.percentagePointsPerWhole;
      final buffer =
          snapshot.settings.warningBuffer /
          InstitutionSettings.percentagePointsPerWhole;
      final predictions = snapshot.subjects
          .map((counts) {
            return SubjectPrediction(
              counts: counts,
              result: AttendancePredictor.calculate(
                counts: counts,
                threshold: threshold,
                warningBuffer: buffer,
                countApprovedOdAsPresent:
                    snapshot.settings.countApprovedOdAsPresent,
              ),
            );
          })
          .toList(growable: false);
      _state = AttendancePredictionState(
        status: PredictionLoadStatus.loaded,
        subjects: predictions,
        thresholdPercent: thresholdPercent,
      );
      notifyListeners();
    } on Object {
      _setError(
        'Attendance data is invalid. Retry after the data is corrected.',
        false,
        canRetry: true,
      );
    }
  }

  void _setError(String message, bool offline, {required bool canRetry}) {
    _state = AttendancePredictionState(
      status: PredictionLoadStatus.error,
      errorMessage: message,
      offline: offline,
      canRetry: canRetry,
    );
    notifyListeners();
  }

  void retry() => start();

  Future<void> savePersonalThreshold(int value) async {
    if (value < minimumPersonalThresholdPercent ||
        value > maximumPersonalThresholdPercent) {
      throw ArgumentError.value(
        value,
        'value',
        'Choose a threshold from $minimumPersonalThresholdPercent to $maximumPersonalThresholdPercent.',
      );
    }
    final id = studentId;
    if (id == null || id.isEmpty) {
      throw StateError('A signed-in student account is required.');
    }
    await repository.savePersonalThreshold(id, value);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
