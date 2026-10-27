import 'dart:async';

import 'package:flutter/foundation.dart';

import 'attendance_notification.dart';
import 'notifications_repository.dart';

class NotificationsState {
  const NotificationsState({
    required this.loading,
    this.items = const [],
    this.errorMessage,
    this.offline = false,
    this.canRetry = true,
  });

  final bool loading;
  final List<AttendanceNotification> items;
  final String? errorMessage;
  final bool offline;
  final bool canRetry;

  int get unreadCount => items.where((item) => !item.isRead).length;
}

/// Holds the live notification stream and performs read actions through a repository.
class NotificationsController extends ChangeNotifier {
  NotificationsController({required this.repository, required this.userId});

  final NotificationsRepository repository;
  final String? userId;
  StreamSubscription<List<AttendanceNotification>>? _subscription;
  NotificationsState _state = const NotificationsState(loading: true);

  NotificationsState get state => _state;

  void start() {
    _subscription?.cancel();
    final id = userId;
    if (id == null || id.isEmpty) {
      _state = const NotificationsState(
        loading: false,
        errorMessage: 'Notifications require a signed-in account.',
        canRetry: false,
      );
      notifyListeners();
      return;
    }
    _state = const NotificationsState(loading: true);
    notifyListeners();
    _subscription = repository
        .watchForUser(id)
        .listen(
          _update,
          onError: (Object error) {
            _state = NotificationsState(
              loading: false,
              errorMessage: error is NotificationsOfflineException
                  ? 'You are offline. Reconnect and retry to load notifications.'
                  : 'Notifications are unavailable. Check Firebase setup and retry.',
              offline: error is NotificationsOfflineException,
            );
            notifyListeners();
          },
        );
  }

  void _update(List<AttendanceNotification> items) {
    final ordered = [...items]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _state = NotificationsState(
      loading: false,
      items: List.unmodifiable(ordered),
    );
    notifyListeners();
  }

  void retry() => start();

  Future<void> markRead(String notificationId) async {
    final id = userId;
    if (id == null || id.isEmpty) throw StateError('Sign-in is required.');
    await repository.markRead(id, notificationId);
  }

  Future<void> markAllRead() async {
    final id = userId;
    if (id == null || id.isEmpty) throw StateError('Sign-in is required.');
    final unreadIds = _state.items
        .where((item) => !item.isRead)
        .map((item) => item.id)
        .toList(growable: false);
    if (unreadIds.isEmpty) return;
    await repository.markAllRead(id, unreadIds);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
