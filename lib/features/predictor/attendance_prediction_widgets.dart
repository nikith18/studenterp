import 'package:flutter/material.dart';

import '../../models/attendance_enums.dart';
import '../../models/institution_settings.dart';
import 'attendance_prediction_controller.dart';
import 'attendance_predictor.dart';

const projectionHorizon = 5;

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.level});

  final RiskLevel level;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, icon, background, foreground) = switch (level) {
      RiskLevel.safe => (
        'Safe',
        Icons.check_circle_outline,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      RiskLevel.atRisk => (
        'At risk',
        Icons.warning_amber_rounded,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      RiskLevel.critical => (
        'Critical',
        Icons.error_outline,
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
    };
    return Chip(
      avatar: Icon(icon, size: 18, color: foreground),
      label: Text(label),
      backgroundColor: background,
      labelStyle: TextStyle(color: foreground),
      side: BorderSide.none,
    );
  }
}

class AttendancePredictionCard extends StatefulWidget {
  const AttendancePredictionCard({
    super.key,
    required this.prediction,
    required this.thresholdPercent,
  });

  final SubjectPrediction prediction;
  final int thresholdPercent;

  @override
  State<AttendancePredictionCard> createState() =>
      _AttendancePredictionCardState();
}

class _AttendancePredictionCardState extends State<AttendancePredictionCard> {
  int _plannedAttendance = projectionHorizon;

  @override
  Widget build(BuildContext context) {
    final data = widget.prediction;
    final counts = data.counts;
    final result = data.result;
    final scheme = Theme.of(context).colorScheme;
    final projection = AttendancePredictor.project(
      attended: result.attendedCount,
      totalConducted: counts.totalConducted,
      attendNext: _plannedAttendance,
      nextClasses: projectionHorizon,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    counts.subjectName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (counts.totalConducted > 0)
                  StatusChip(level: result.riskLevel),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              counts.totalConducted == 0
                  ? 'No recorded classes yet'
                  : '${(result.currentPercentage * InstitutionSettings.percentagePointsPerWhole).toStringAsFixed(1)}% · '
                        '${result.attendedCount} of ${counts.totalConducted} counted as present',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (counts.totalConducted > 0) ...[
              const SizedBox(height: 8),
              Text(
                _thresholdSummary(result),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Divider(color: scheme.outlineVariant),
              const SizedBox(height: 8),
              Text(
                'Historical attendance',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: result.currentPercentage.clamp(0.0, 1.0),
                semanticsLabel: 'Historical attendance percentage',
                minHeight: 8,
              ),
              const SizedBox(height: 16),
              Text('Projection', style: Theme.of(context).textTheme.titleSmall),
              Text(
                'Attend $_plannedAttendance of the next $projectionHorizon classes',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Slider(
                value: _plannedAttendance.toDouble(),
                min: 0,
                max: projectionHorizon.toDouble(),
                divisions: projectionHorizon,
                label: '$_plannedAttendance classes',
                semanticFormatterCallback: (value) =>
                    'Attend ${value.round()} of the next $projectionHorizon classes',
                onChanged: (value) =>
                    setState(() => _plannedAttendance = value.round()),
              ),
              Text(
                'Projected attendance: '
                '${(projection * InstitutionSettings.percentagePointsPerWhole).toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Based on recorded sessions only; assumes all future classes are conducted.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _thresholdSummary(AttendancePrediction result) {
    if (!result.isRecoverable) {
      return 'Not recoverable at a ${widget.thresholdPercent}% threshold.';
    }
    if (result.currentPercentage >=
        widget.thresholdPercent /
            InstitutionSettings.percentagePointsPerWhole) {
      return 'You can miss ${result.maximumMisses} more '
          '${result.maximumMisses == 1 ? 'class' : 'classes'}.';
    }
    final needed = result.classesToReachThreshold;
    return 'Attend the next $needed '
        '${needed == 1 ? 'class' : 'classes'} to reach '
        '${widget.thresholdPercent}%.';
  }
}
