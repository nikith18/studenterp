import 'package:flutter/material.dart';

import '../../models/attendance_enums.dart';
import 'attendance_notification.dart';
import 'notifications_controller.dart';

const _headerPadding = EdgeInsets.fromLTRB(20, 20, 20, 12);
const _notificationListPadding = EdgeInsets.fromLTRB(16, 0, 16, 24);
const _dayHeadingPadding = EdgeInsets.fromLTRB(4, 14, 4, 6);
const _errorPadding = EdgeInsets.all(24);
const _shortGap = SizedBox(height: 4);
const _contentGap = SizedBox(height: 8);
const _sectionGap = SizedBox(height: 12);
const _emptyStateIconSize = 36.0;

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.controller,
    this.onOpenRelated,
  });

  final NotificationsController controller;
  final ValueChanged<AttendanceNotification>? onOpenRelated;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      final entries = _entries(state.items);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: _headerPadding,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Notifications',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                if (!state.loading &&
                    state.errorMessage == null &&
                    state.unreadCount > 0)
                  TextButton.icon(
                    onPressed: _markAllRead,
                    icon: const Icon(Icons.done_all),
                    label: const Text('Mark all read'),
                  ),
              ],
            ),
          ),
          if (state.loading)
            const Expanded(child: _NotificationsLoading())
          else if (state.errorMessage != null)
            Expanded(
              child: _NotificationsError(
                message: state.errorMessage!,
                offline: state.offline,
                canRetry: state.canRetry,
                onRetry: widget.controller.retry,
              ),
            )
          else if (state.items.isEmpty)
            const Expanded(child: _NotificationsEmpty())
          else
            Expanded(
              child: ListView.builder(
                padding: _notificationListPadding,
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  if (entry.notification == null) {
                    return _DayHeading(label: entry.heading!);
                  }
                  return _NotificationTile(
                    notification: entry.notification!,
                    onTap: () => _open(entry.notification!),
                  );
                },
              ),
            ),
        ],
      );
    },
  );

  List<_NotificationEntry> _entries(List<AttendanceNotification> items) {
    final entries = <_NotificationEntry>[];
    String? previousDay;
    for (final item in items) {
      final day = DateUtils.dateOnly(item.createdAt.toLocal());
      final key = '${day.year}-${day.month}-${day.day}';
      if (key != previousDay) {
        entries.add(_NotificationEntry.heading(_dayLabel(day)));
        previousDay = key;
      }
      entries.add(_NotificationEntry.item(item));
    }
    return entries;
  }

  String _dayLabel(DateTime day) {
    final today = DateUtils.dateOnly(DateTime.now());
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${day.day}/${day.month}/${day.year}';
  }

  Future<void> _open(AttendanceNotification notification) async {
    if (!notification.isRead) {
      try {
        await widget.controller.markRead(notification.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notification marked as read.')),
          );
        }
      } catch (_) {
        if (mounted) _showActionError();
        return;
      }
    }
    widget.onOpenRelated?.call(notification);
  }

  Future<void> _markAllRead() async {
    try {
      await widget.controller.markAllRead();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All notifications marked as read.')),
        );
      }
    } catch (_) {
      if (mounted) _showActionError();
    }
  }

  void _showActionError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not update notifications. Retry when connected.'),
      ),
    );
  }
}

class _NotificationEntry {
  const _NotificationEntry.heading(this.heading) : notification = null;
  const _NotificationEntry.item(this.notification) : heading = null;

  final String? heading;
  final AttendanceNotification? notification;
}

class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: _dayHeadingPadding,
    child: Text(label, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AttendanceNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      color: notification.isRead ? colors.surface : colors.secondaryContainer,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          _iconFor(notification.type),
          color: notification.isRead
              ? colors.onSurfaceVariant
              : colors.onSecondaryContainer,
          semanticLabel: _labelFor(notification.type),
        ),
        title: Text(
          notification.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: notification.isRead
                ? FontWeight.normal
                : FontWeight.bold,
          ),
        ),
        subtitle: Text(notification.body),
        trailing: Text(_timeLabel(notification.createdAt.toLocal())),
        isThreeLine: true,
      ),
    );
  }

  IconData _iconFor(NotificationType type) => switch (type) {
    NotificationType.lowAttendance => Icons.warning_amber_rounded,
    NotificationType.attendanceCorrected => Icons.edit_calendar_outlined,
    NotificationType.reportReady => Icons.assessment_outlined,
    NotificationType.requestDecision => Icons.fact_check_outlined,
    NotificationType.disputeUpdate => Icons.forum_outlined,
  };

  String _labelFor(NotificationType type) => switch (type) {
    NotificationType.lowAttendance => 'Attendance alert',
    NotificationType.attendanceCorrected => 'Attendance correction',
    NotificationType.reportReady => 'Report ready',
    NotificationType.requestDecision => 'Request decision',
    NotificationType.disputeUpdate => 'Dispute update',
  };

  String _timeLabel(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _NotificationsLoading extends StatelessWidget {
  const _NotificationsLoading();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        _sectionGap,
        Text('Loading notifications…'),
      ],
    ),
  );
}

class _NotificationsEmpty extends StatelessWidget {
  const _NotificationsEmpty();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.notifications_none,
          color: Theme.of(context).colorScheme.primary,
          size: _emptyStateIconSize,
        ),
        _sectionGap,
        Text(
          'You’re all caught up',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        _shortGap,
        const Text('New attendance updates will appear here.'),
      ],
    ),
  );
}

class _NotificationsError extends StatelessWidget {
  const _NotificationsError({
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
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: _errorPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            offline ? Icons.cloud_off_outlined : Icons.cloud_outlined,
            color: Theme.of(context).colorScheme.error,
            size: _emptyStateIconSize,
          ),
          _sectionGap,
          Text(message, textAlign: TextAlign.center),
          if (canRetry) ...[
            _contentGap,
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
          _contentGap,
          Text(
            'Push notifications are not enabled in this build.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}
