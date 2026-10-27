import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/attendance_enums.dart';
import 'live_attendance_controller.dart';
import 'live_attendance_models.dart';
import 'live_attendance_repository.dart';

class LiveAttendancePage extends StatefulWidget {
  const LiveAttendancePage({
    super.key,
    required this.userId,
    required this.canEdit,
    required this.repository,
  });

  final String? userId;
  final bool canEdit;
  final LiveAttendanceRepository repository;

  @override
  State<LiveAttendancePage> createState() => _LiveAttendancePageState();
}

class _LiveAttendancePageState extends State<LiveAttendancePage> {
  late final LiveAttendanceController controller;
  final searchController = TextEditingController();
  String searchQuery = '';
  Timer? countdownTimer;

  @override
  void initState() {
    super.initState();
    controller = LiveAttendanceController(
      repository: widget.repository,
      userId: widget.userId,
      canEdit: widget.canEdit,
    )..start();
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && controller.state.session != null) setState(() {});
    });
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    searchController.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final state = controller.state;
      if (state.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (state.errorMessage != null) return _error(state);
      if (state.selectedAssignment == null) return _assignments(state);
      if (state.session == null) return _noSession();
      return _monitor(state);
    },
  );

  Widget _error(LiveAttendanceState state) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (state.offline)
          MaterialBanner(
            content: const Text(
              'Offline · live updates will resume on reconnect.',
            ),
            leading: const Icon(Icons.wifi_off_outlined),
            actions: [
              TextButton(
                onPressed: controller.retry,
                child: const Text('Retry'),
              ),
            ],
          ),
        const SizedBox(height: 40),
        Icon(
          Icons.cloud_off_outlined,
          size: 48,
          color: colors.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(state.errorMessage!, textAlign: TextAlign.center),
        if (state.canRetry)
          Center(
            child: TextButton.icon(
              onPressed: controller.retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ),
      ],
    );
  }

  Widget _assignments(LiveAttendanceState state) {
    if (state.assignments.isEmpty) {
      return const _InfoState(
        icon: Icons.class_outlined,
        title: 'No assigned classes',
        message: 'Classes available to your account will appear here.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Live classroom monitor',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          widget.canEdit
              ? 'Choose a class and subject to open today’s session.'
              : 'Choose an active class session to view.',
        ),
        const SizedBox(height: 16),
        for (final assignment in state.assignments)
          Card(
            child: ListTile(
              title: Text(assignment.subjectName),
              subtitle: Text(assignment.className),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  _perform(() => controller.openOrViewSession(assignment)),
            ),
          ),
      ],
    );
  }

  Widget _noSession() => _InfoState(
    icon: Icons.event_busy_outlined,
    title: 'No active session',
    message: widget.canEdit
        ? 'A session could not be opened. Check assignments and session settings.'
        : 'There is no active attendance session for this class.',
    onAction: controller.returnToAssignments,
    actionLabel: 'Choose another class',
  );

  Widget _monitor(LiveAttendanceState state) {
    final session = state.session!;
    final colors = Theme.of(context).colorScheme;
    final countdown = SessionCountdown.calculate(
      now: DateTime.now(),
      expiresAt: session.expiresAt,
      status: session.status,
    );
    final students = [...state.roster]
      ..sort((a, b) => a.name.compareTo(b.name));
    final query = searchQuery.trim().toLowerCase();
    final filtered = students
        .where(
          (student) =>
              student.name.toLowerCase().contains(query) ||
              student.rollNumber.toLowerCase().contains(query),
        )
        .toList();
    final markedIds = state.markedStudents
        .map((record) => record.studentId)
        .toSet();
    return Column(
      children: [
        if (state.offline)
          MaterialBanner(
            content: const Text('Offline · updates will resume automatically.'),
            leading: const Icon(Icons.wifi_off_outlined),
            actions: [
              TextButton(
                onPressed: controller.retry,
                child: const Text('Retry'),
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              IconButton(
                onPressed: controller.returnToAssignments,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Classes',
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.selectedAssignment!.subjectName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      state.selectedAssignment!.className,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Chip(
                avatar: Icon(
                  session.status == SessionStatus.open
                      ? Icons.circle
                      : Icons.lock_outline,
                  size: 12,
                ),
                label: Text(
                  countdown.isExpired ? 'Expired' : session.status.name,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _CountTile(
                label: 'Present',
                value: state.counts.present,
                color: colors.primary,
              ),
              _CountTile(
                label: 'Absent',
                value: state.counts.absent,
                color: colors.error,
              ),
              _CountTile(
                label: 'On Duty',
                value: state.counts.onDuty,
                color: colors.tertiary,
              ),
              _CountTile(
                label: 'Pending',
                value: state.counts.pending,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.timer_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                countdown.isClosed
                    ? 'Session closed'
                    : countdown.isExpired
                    ? 'Session expired'
                    : 'Closes in ${_duration(countdown.remaining)}',
              ),
              const Spacer(),
              if (widget.canEdit &&
                  session.status == SessionStatus.open &&
                  !countdown.isExpired)
                TextButton(
                  onPressed: () => _perform(
                    controller.closeSession,
                    confirmClose: true,
                    successMessage: 'Session closed.',
                  ),
                  child: const Text('Close session'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: searchController,
            onChanged: (value) => setState(() => searchQuery = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search students',
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final student = filtered[index];
              LiveAttendanceRecord? record;
              for (final candidate in state.records) {
                if (candidate.studentId == student.id) {
                  record = candidate;
                  break;
                }
              }
              return Card(
                child: ListTile(
                  title: Text(student.name),
                  subtitle: Text(student.rollNumber),
                  trailing:
                      widget.canEdit &&
                          session.status == SessionStatus.open &&
                          !countdown.isExpired
                      ? _StatusMenu(
                          status: record?.status,
                          onSelected: (status) => _perform(
                            () => controller.markAttendance(student.id, status),
                          ),
                        )
                      : Text(
                          record == null
                              ? 'Pending'
                              : _statusLabel(record.status),
                        ),
                  leading: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      markedIds.contains(student.id)
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      key: ValueKey(markedIds.contains(student.id)),
                      color: markedIds.contains(student.id)
                          ? colors.primary
                          : colors.outline,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.canEdit &&
            session.status == SessionStatus.open &&
            !countdown.isExpired)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _perform(controller.markAllPresent),
                  icon: const Icon(Icons.done_all),
                  label: const Text('Mark all present'),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _perform(
    Future<void> Function() action, {
    bool confirmClose = false,
    String successMessage = 'Attendance updated.',
  }) async {
    if (confirmClose) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Close attendance session?'),
          content: const Text(
            'No further attendance changes will be accepted after closing.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Close session'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } on AttendanceRecordAlreadyExistsException {
      _message('Already marked.');
    } on LiveAttendanceSessionClosedException {
      _message('Session closed or expired.');
    } catch (error) {
      _message(
        error is LiveAttendanceConfigurationException
            ? 'Firebase is not configured for this demo.'
            : 'Could not update attendance. Check your connection and retry.',
      );
    }
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
    }
  }

  static String _duration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  static String _statusLabel(AttendanceRecordStatus status) => switch (status) {
    AttendanceRecordStatus.present => 'Present',
    AttendanceRecordStatus.absent => 'Absent',
    AttendanceRecordStatus.onDuty => 'On Duty',
  };
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                '$value',
                key: ValueKey(value),
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(color: color),
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ),
  );
}

class _StatusMenu extends StatelessWidget {
  const _StatusMenu({required this.status, required this.onSelected});
  final AttendanceRecordStatus? status;
  final ValueChanged<AttendanceRecordStatus> onSelected;
  @override
  Widget build(BuildContext context) => PopupMenuButton<AttendanceRecordStatus>(
    tooltip: 'Set attendance status',
    initialValue: status,
    onSelected: onSelected,
    itemBuilder: (context) => AttendanceRecordStatus.values
        .map(
          (value) => PopupMenuItem(
            value: value,
            child: Text(switch (value) {
              AttendanceRecordStatus.present => 'Present',
              AttendanceRecordStatus.absent => 'Absent',
              AttendanceRecordStatus.onDuty => 'On Duty',
            }),
          ),
        )
        .toList(),
    child: Chip(
      label: Text(
        status == null
            ? 'Pending'
            : _LiveAttendancePageState._statusLabel(status!),
      ),
    ),
  );
}

class _InfoState extends StatelessWidget {
  const _InfoState({
    required this.icon,
    required this.title,
    required this.message,
    this.onAction,
    this.actionLabel,
  });
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onAction;
  final String? actionLabel;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    ),
  );
}
