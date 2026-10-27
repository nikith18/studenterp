import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:studenterp/features/notifications/attendance_notification.dart';
import 'package:studenterp/features/notifications/notifications_controller.dart';
import 'package:studenterp/features/notifications/notifications_repository.dart';
import 'package:studenterp/models/attendance_enums.dart';

class _TestNotificationsRepository implements NotificationsRepository {
  final changes = StreamController<List<AttendanceNotification>>();
  String? markedUserId;
  String? markedNotificationId;
  List<String>? markedAllIds;

  @override
  Stream<List<AttendanceNotification>> watchForUser(String userId) =>
      changes.stream;

  @override
  Future<void> markRead(String userId, String notificationId) async {
    markedUserId = userId;
    markedNotificationId = notificationId;
  }

  @override
  Future<void> markAllRead(String userId, List<String> notificationIds) async {
    markedUserId = userId;
    markedAllIds = notificationIds;
  }
}

AttendanceNotification _notification({
  required String id,
  required bool isRead,
  required DateTime createdAt,
}) => AttendanceNotification(
  id: id,
  recipientId: 'student-1',
  type: NotificationType.lowAttendance,
  title: 'Attendance warning',
  body: 'Attendance is below the warning boundary.',
  isRead: isRead,
  createdAt: createdAt,
);

void main() {
  late _TestNotificationsRepository repository;
  late NotificationsController controller;

  setUp(() {
    repository = _TestNotificationsRepository();
    controller = NotificationsController(
      repository: repository,
      userId: 'student-1',
    )..start();
  });

  tearDown(() async {
    controller.dispose();
    await repository.changes.close();
  });

  test('updates the unread count from a repository stream emission', () async {
    final now = DateTime(2026, 10, 27);
    repository.changes.add([
      _notification(id: 'new', isRead: false, createdAt: now),
      _notification(
        id: 'old',
        isRead: true,
        createdAt: now.subtract(const Duration(days: 1)),
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.loading, isFalse);
    expect(controller.state.unreadCount, 1);
    expect(controller.state.items.first.id, 'new');
  });

  test(
    'routes read actions through the repository for the signed-in user',
    () async {
      final now = DateTime(2026, 10, 27);
      repository.changes.add([
        _notification(id: 'new', isRead: false, createdAt: now),
      ]);
      await Future<void>.delayed(Duration.zero);

      await controller.markRead('new');
      await controller.markAllRead();

      expect(repository.markedUserId, 'student-1');
      expect(repository.markedNotificationId, 'new');
      expect(repository.markedAllIds, ['new']);
    },
  );
}
