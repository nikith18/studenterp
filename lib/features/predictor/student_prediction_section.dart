import 'package:flutter/material.dart';

import 'attendance_prediction_controller.dart';
import 'attendance_prediction_repository.dart';
import 'attendance_prediction_widgets.dart';

class StudentPredictionSection extends StatefulWidget {
  const StudentPredictionSection({
    super.key,
    required this.studentId,
    this.repository = const UnconfiguredAttendancePredictionRepository(),
  });

  final String? studentId;
  final AttendancePredictionRepository repository;

  @override
  State<StudentPredictionSection> createState() =>
      _StudentPredictionSectionState();
}

class _StudentPredictionSectionState extends State<StudentPredictionSection> {
  late final AttendancePredictionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AttendancePredictionController(
      repository: widget.repository,
      studentId: widget.studentId,
    )..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final state = _controller.state;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Subject predictions',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (state.status == PredictionLoadStatus.loaded)
                  TextButton.icon(
                    onPressed: _editThreshold,
                    icon: const Icon(Icons.tune),
                    label: Text('Threshold ${state.thresholdPercent}%'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (state.status == PredictionLoadStatus.loading)
              const _PredictionLoadingState()
            else if (state.status == PredictionLoadStatus.error)
              _PredictionErrorState(
                message:
                    state.errorMessage ?? 'Attendance could not be loaded.',
                offline: state.offline,
                canRetry: state.canRetry,
                onRetry: _controller.retry,
              )
            else if (state.subjects.isEmpty)
              const _PredictionEmptyState()
            else
              ...state.subjects.map(
                (subject) => AttendancePredictionCard(
                  prediction: subject,
                  thresholdPercent: state.thresholdPercent,
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _editThreshold() async {
    final current = _controller.state.thresholdPercent;
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => _ThresholdDialog(initialValue: current),
    );
    if (selected == null) return;

    try {
      await _controller.savePersonalThreshold(selected);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Personal threshold saved.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save your threshold. Retry when connected.',
            ),
          ),
        );
      }
    }
  }
}

class _PredictionLoadingState extends StatelessWidget {
  const _PredictionLoadingState();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(20),
      child: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('Loading recorded attendance…')),
        ],
      ),
    ),
  );
}

class _PredictionErrorState extends StatelessWidget {
  const _PredictionErrorState({
    required this.message,
    required this.offline,
    required this.canRetry,
    required this.onRetry,
  });

  final String message;
  final bool offline;
  final bool canRetry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  offline ? Icons.cloud_off_outlined : Icons.cloud_outlined,
                  color: scheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            if (canRetry) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PredictionEmptyState extends StatelessWidget {
  const _PredictionEmptyState();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(
            Icons.event_note_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Text(
            'No attendance sessions yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text('Predictions will appear after sessions are recorded.'),
        ],
      ),
    ),
  );
}

class _ThresholdDialog extends StatefulWidget {
  const _ThresholdDialog({required this.initialValue});

  final int initialValue;

  @override
  State<_ThresholdDialog> createState() => _ThresholdDialogState();
}

class _ThresholdDialogState extends State<_ThresholdDialog> {
  late int _value = widget.initialValue;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Personal attendance threshold'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$_value%'),
        Slider(
          value: _value.toDouble(),
          min: minimumPersonalThresholdPercent.toDouble(),
          max: maximumPersonalThresholdPercent.toDouble(),
          divisions:
              maximumPersonalThresholdPercent - minimumPersonalThresholdPercent,
          label: '$_value%',
          semanticFormatterCallback: (value) =>
              'Attendance threshold ${value.round()} percent',
          onChanged: (value) => setState(() => _value = value.round()),
        ),
        Text(
          'Choose a value from $minimumPersonalThresholdPercent% to '
          '$maximumPersonalThresholdPercent%.',
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _value),
        child: const Text('Save'),
      ),
    ],
  );
}
