import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studenterp/main.dart';

void main() {
  testWidgets('student dashboard opens from the demo entry point', (tester) async {
    await tester.pumpWidget(const AttendanceApp());
    await tester.pumpAndSettle();
    expect(find.text('Hi, Ananya 👋'), findsOneWidget);
    expect(find.text('YOUR ATTENDANCE'), findsOneWidget);
  });

  testWidgets('profile heading keeps readable contrast in dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(const AttendanceApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark appearance'));
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('Profile & settings'));
    final colors = Theme.of(tester.element(find.text('Profile & settings')))
        .colorScheme;
    expect(title.style?.color, colors.onSurface);
    expect(
      _contrast(colors.onSurface, colors.surface),
      greaterThanOrEqualTo(4.5),
    );
  });
}

double _contrast(Color first, Color second) {
  final luminances = [first.computeLuminance(), second.computeLuminance()]
    ..sort();
  return (luminances[1] + 0.05) / (luminances[0] + 0.05);
}
