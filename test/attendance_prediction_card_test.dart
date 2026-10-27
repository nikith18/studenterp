import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studenterp/features/predictor/attendance_prediction_controller.dart';
import 'package:studenterp/features/predictor/attendance_prediction_widgets.dart';
import 'package:studenterp/features/predictor/attendance_predictor.dart';

void main() {
  testWidgets('prediction card shows historical and projection details', (
    tester,
  ) async {
    final counts = SubjectAttendanceCounts(
      subjectId: 'subject-1',
      subjectName: 'Data Structures',
      presentSessions: 3,
      approvedOdSessions: 0,
      totalConducted: 4,
    );
    final prediction = AttendancePredictor.calculate(
      counts: counts,
      threshold: 0.75,
      warningBuffer: 0.05,
      countApprovedOdAsPresent: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        ),
        home: Scaffold(
          body: AttendancePredictionCard(
            prediction: SubjectPrediction(counts: counts, result: prediction),
            thresholdPercent: 75,
          ),
        ),
      ),
    );

    expect(find.text('Data Structures'), findsOneWidget);
    expect(find.text('At risk'), findsOneWidget);
    expect(find.text('75.0% · 3 of 4 counted as present'), findsOneWidget);
    expect(find.text('Historical attendance'), findsOneWidget);
    expect(find.text('Projection'), findsOneWidget);
    expect(find.text('Projected attendance: 88.9%'), findsOneWidget);
  });
}
