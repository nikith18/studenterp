import '../../models/attendance_enums.dart';

class AttendanceNotification {
  const AttendanceNotification({
    required this.id,
    required this.recipientId,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.relatedId,
    this.readAt,
  });

  final String id;
  final String recipientId;
  final NotificationType type;
  final String title;
  final String body;
  final String? relatedId;
  final bool isRead;
  final DateTime createdAt;
  final DateTime? readAt;
}
