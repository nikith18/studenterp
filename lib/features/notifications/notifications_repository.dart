import 'attendance_notification.dart';

abstract interface class NotificationsRepository {
  Stream<List<AttendanceNotification>> watchForUser(String userId);

  Future<void> markRead(String userId, String notificationId);

  /// Implementations should update the supplied unread documents in one batch.
  Future<void> markAllRead(String userId, List<String> notificationIds);
}

class NotificationsConfigurationException implements Exception {
  const NotificationsConfigurationException();
}

class NotificationsOfflineException implements Exception {
  const NotificationsOfflineException();
}

/// Explicit fallback until Firebase Auth and Firestore are configured.
class UnconfiguredNotificationsRepository implements NotificationsRepository {
  const UnconfiguredNotificationsRepository();

  @override
  Stream<List<AttendanceNotification>> watchForUser(String userId) =>
      Stream.error(const NotificationsConfigurationException());

  @override
  Future<void> markRead(String userId, String notificationId) =>
      Future.error(const NotificationsConfigurationException());

  @override
  Future<void> markAllRead(String userId, List<String> notificationIds) =>
      Future.error(const NotificationsConfigurationException());
}
