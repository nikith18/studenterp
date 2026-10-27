// ignore_for_file: constant_identifier_names
import 'package:flutter/material.dart';

import 'features/predictor/student_prediction_section.dart';
import 'features/notifications/notifications_controller.dart';
import 'features/notifications/notifications_page.dart';
import 'features/live_attendance/live_attendance_page.dart';
import 'features/advanced/advanced_features_page.dart';
import 'features/demo/demo_repositories.dart';

import 'dart:convert';

import 'package:flutter/services.dart';

void main() => runApp(const AttendanceApp());

const blue = Color(0xFF476CFA);
const contentMaxWidth = 840.0;
const loginMaxWidth = 480.0;

ThemeData _attendanceTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: blue, brightness: brightness);
  final base = ThemeData.from(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: base.textTheme.apply(
      fontFamily: 'Roboto',
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(color: scheme.onSurfaceVariant),
      ),
    ),
  );
}

class AttendanceApp extends StatefulWidget {
  const AttendanceApp({super.key});
  @override
  State<AttendanceApp> createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp> {
  ThemeMode mode = ThemeMode.light;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Attendly',
    debugShowCheckedModeBanner: false,
    themeMode: mode,
    theme: _attendanceTheme(Brightness.light),
    darkTheme: _attendanceTheme(Brightness.dark),
    home: Home(
      onTheme: (dark) =>
          setState(() => mode = dark ? ThemeMode.dark : ThemeMode.light),
    ),
  );
}

enum Role { Student, Faculty, Admin }

enum Status { Present, Absent, OnDuty }

class Learner {
  Learner(this.name, this.roll, this.status);
  final String name, roll;
  Status status;
}

class Home extends StatefulWidget {
  const Home({super.key, required this.onTheme});
  final ValueChanged<bool> onTheme;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Role role = Role.Student;
  int tab = 0;
  bool signedIn = true;
  bool dark = false;
  String subject = 'Data Structures';
  final students = <Learner>[
    Learner('Aarav Sharma', 'CS23001', Status.Present),
    Learner('Aditi Rao', 'CS23002', Status.Present),
    Learner('Arjun Patel', 'CS23003', Status.Absent),
    Learner('Diya Nair', 'CS23004', Status.Present),
    Learner('Ishaan Das', 'CS23005', Status.OnDuty),
    Learner('Meera Shah', 'CS23006', Status.Present),
  ];
  final history = <String>[];
  late final NotificationsController notificationsController;
  int get present => students.where((s) => s.status != Status.Absent).length;

  @override
  void initState() {
    super.initState();
    notificationsController = NotificationsController(
      repository: DemoRepositories.instance,
      userId: DemoRepositories.studentId,
    )..start();
    LocalStore.read()
        .then((saved) {
          if (mounted && saved.isNotEmpty) {
            setState(() => history.addAll(saved));
          }
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    notificationsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!signedIn) {
      return Login(
        onLogin: (r) => setState(() {
          role = r;
          signedIn = true;
          tab = 0;
        }),
      );
    }
    final pages = [
      Dashboard(
        role: role,
        present: present,
        total: students.length,
        unreadCount: notificationsController.state.errorMessage == null
            ? notificationsController.state.unreadCount
            : null,
        onMark: () => setState(() => tab = 1),
        onNotifications: () => setState(() => tab = 2),
        onMonitor: () => setState(() => tab = 3),
        onAdvanced: () => setState(() => tab = 4),
      ),
      role == Role.Faculty
          ? AttendancePage(
              students: students,
              onChanged: () => setState(() {}),
              onSave: _save,
            )
          : role == Role.Admin
          ? ManagementPage(students: students)
          : HistoryPage(history: history),
      Column(
        children: [
          const _LocalDemoNotice(),
          Expanded(
            child: NotificationsPage(controller: notificationsController),
          ),
        ],
      ),
      Column(
        children: [
          const _LocalDemoNotice(),
          Expanded(
            child: LiveAttendancePage(
              userId: role == Role.Faculty
                  ? DemoRepositories.facultyId
                  : role == Role.Admin
                  ? DemoRepositories.adminId
                  : DemoRepositories.studentId,
              canEdit: role == Role.Faculty,
              repository: DemoRepositories.instance,
            ),
          ),
        ],
      ),
      AdvancedFeaturesPage(
        role: switch (role) {
          Role.Student => AdvancedFeatureRole.student,
          Role.Faculty => AdvancedFeatureRole.faculty,
          Role.Admin => AdvancedFeatureRole.admin,
        },
      ),
      ProfilePage(
        role: role,
        dark: dark,
        onDark: (v) {
          setState(() => dark = v);
          widget.onTheme(v);
        },
        onLogout: () => setState(() => signedIn = false),
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: contentMaxWidth),
            child: SizedBox.expand(
              child: IndexedStack(index: tab, children: pages),
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(
              role == Role.Faculty
                  ? Icons.fact_check_outlined
                  : role == Role.Admin
                  ? Icons.groups_outlined
                  : Icons.calendar_month_outlined,
            ),
            label: role == Role.Faculty
                ? 'Attendance'
                : role == Role.Admin
                ? 'People'
                : 'History',
          ),
          const NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            label: 'Notifications',
          ),
          const NavigationDestination(
            icon: Icon(Icons.sensors_outlined),
            label: 'Live',
          ),
          const NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            label: 'Advanced',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final date =
        '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';
    final entry = '$date · $subject · $present/${students.length} present';
    final existing = history.indexWhere(
      (item) => item.startsWith('$date · $subject · '),
    );
    setState(() {
      if (existing >= 0) {
        history[existing] = entry;
      } else {
        history.insert(0, entry);
      }
    });
    try {
      await LocalStore.write(history);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              existing >= 0
                  ? 'Attendance updated on this device'
                  : 'Attendance saved on this device',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save attendance on this device'),
          ),
        );
      }
    }
  }
}

class LocalStore {
  static const _channel = MethodChannel('studenterp/local_store');
  static Future<List<String>> read() async {
    final raw = await _channel.invokeMethod<String>('read');
    return (jsonDecode(raw ?? '[]') as List).cast<String>();
  }

  static Future<void> write(List<String> items) async =>
      _channel.invokeMethod<void>('write', {'value': jsonEncode(items)});
}

class _LocalDemoNotice extends StatelessWidget {
  const _LocalDemoNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.science_outlined, color: colors.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Local demo · sample data is not synced and resets when the app closes.',
                style: TextStyle(color: colors.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Login extends StatefulWidget {
  const Login({super.key, required this.onLogin});
  final ValueChanged<Role> onLogin;
  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final pass = TextEditingController();
  Role role = Role.Student;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: loginMaxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(26),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome_rounded, color: blue, size: 42),
                const SizedBox(height: 22),
                Text(
                  'Welcome back',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontSize: 30, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 7),
                const Text('Sign in to your attendance workspace'),
                const SizedBox(height: 28),
                DropdownButtonFormField<Role>(
                  initialValue: role,
                  decoration: const InputDecoration(
                    labelText: 'Continue as',
                    border: OutlineInputBorder(),
                  ),
                  items: Role.values
                      .map(
                        (r) => DropdownMenuItem(value: r, child: Text(r.name)),
                      )
                      .toList(),
                  onChanged: (r) => setState(() => role = r!),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: email,
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: Icon(Icons.mail_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || !v.contains('@')
                      ? 'Enter a valid email address'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: pass,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.length < 4
                      ? 'Enter at least 4 characters'
                      : null,
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () {
                      if (form.currentState!.validate()) widget.onLogin(role);
                    },
                    child: const Text('Sign in'),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    'Demo mode · local device storage',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class Dashboard extends StatelessWidget {
  const Dashboard({
    super.key,
    required this.role,
    required this.present,
    required this.total,
    required this.unreadCount,
    required this.onMark,
    required this.onNotifications,
    required this.onMonitor,
    required this.onAdvanced,
  });
  final Role role;
  final int present, total;
  final int? unreadCount;
  final VoidCallback onMark;
  final VoidCallback onNotifications;
  final VoidCallback onMonitor;
  final VoidCallback onAdvanced;
  @override
  Widget build(BuildContext context) {
    final isStudent = role == Role.Student, isFaculty = role == Role.Faculty;
    final percent = total == 0 ? 0.0 : present / total;
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: colors.primaryContainer,
              child: Icon(
                Icons.school_rounded,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GOOD MORNING',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.3,
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    isStudent
                        ? 'Hi, Ananya 👋'
                        : isFaculty
                        ? 'Hello, Dr. Mehta'
                        : 'Welcome, Admin',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: unreadCount == null
                  ? 'Notifications'
                  : '$unreadCount unread notifications',
              onPressed: onNotifications,
              icon: Badge(
                isLabelVisible: (unreadCount ?? 0) > 0,
                label: Text('${unreadCount ?? 0}'),
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
          ],
        ),
        const SizedBox(height: 25),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isStudent
                    ? 'YOUR ATTENDANCE'
                    : isFaculty
                    ? 'TODAY’S ATTENDANCE'
                    : 'CAMPUS OVERVIEW',
                style: TextStyle(
                  color: colors.onPrimaryContainer,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isStudent ? '—' : '$present',
                    style: TextStyle(
                      color: colors.onPrimaryContainer,
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Text(
                      isStudent ? '' : '/ $total present',
                      style: TextStyle(
                        color: colors.onPrimaryContainer,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (!isStudent)
                    SizedBox(
                      width: 55,
                      height: 55,
                      child: CircularProgressIndicator(
                        value: percent,
                        strokeWidth: 5,
                        backgroundColor: colors.onPrimaryContainer.withValues(
                          alpha: 0.2,
                        ),
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                isStudent
                    ? 'Attendance is calculated from recorded sessions.'
                    : isFaculty
                    ? 'Students checked in for today'
                    : 'Active student records',
                style: TextStyle(color: colors.onPrimaryContainer),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: isStudent ? 'Present days' : 'Present',
                value: isStudent ? '—' : '$present',
                icon: Icons.check_circle_outline,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: isStudent ? 'Absent days' : 'Absent',
                value: isStudent ? '—' : '${total - present}',
                icon: Icons.event_busy_outlined,
                color: colors.error,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: 'Classes',
                value: isStudent ? '—' : '$total',
                icon: Icons.menu_book_outlined,
                color: colors.tertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 25),
        Row(
          children: [
            Expanded(
              child: Text(
                'Quick access',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
            ),
            if (isFaculty)
              TextButton(
                onPressed: onMark,
                child: const Text('Mark attendance'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (isStudent)
          StudentPredictionSection(
            studentId: DemoRepositories.studentId,
            repository: DemoRepositories.instance,
          ),
        if (isFaculty)
          ActionTile(
            icon: Icons.fact_check_outlined,
            title: 'Mark attendance',
            subtitle: 'CSE · Semester 5 ·  students',
            onTap: onMark,
          ),
        if (isFaculty)
          ActionTile(
            icon: Icons.sensors_outlined,
            title: 'Live classroom monitor',
            subtitle: 'Track attendance as it is marked',
            onTap: onMonitor,
          ),
        if (role == Role.Admin)
          ActionTile(
            icon: Icons.groups_2_outlined,
            title: 'Manage people',
            subtitle: 'Open the campus directory',
            onTap: onMark,
          ),
        ActionTile(
          icon: Icons.auto_awesome_outlined,
          title: 'Advanced workflows',
          subtitle: 'Requests, attendance disputes, and guardian consent',
          onTap: onAdvanced,
        ),
      ],
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label, value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 19),
            const SizedBox(height: 10),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: colors.primaryContainer,
          child: Icon(icon, color: colors.onPrimaryContainer),
        ),
        title: Text(title, style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text(subtitle),
        trailing: onTap == null
            ? null
            : const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class AttendancePage extends StatefulWidget {
  const AttendancePage({
    super.key,
    required this.students,
    required this.onChanged,
    required this.onSave,
  });
  final List<Learner> students;
  final VoidCallback onChanged, onSave;
  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  String subject = 'Data Structures';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Take attendance',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(
          'CSE · Semester 5 · Today',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          initialValue: subject,
          decoration: const InputDecoration(
            labelText: 'Subject',
            border: OutlineInputBorder(),
          ),
          items: [
            'Data Structures',
            'Database Systems',
            'Computer Networks',
          ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: (v) => setState(() => subject = v!),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                '${widget.students.length} students',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                for (final student in widget.students) {
                  student.status = Status.Present;
                }
                setState(() {});
                widget.onChanged();
              },
              icon: const Icon(Icons.done_all),
              label: const Text('All present'),
            ),
          ],
        ),
        ...widget.students.map(
          (student) => Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: colors.primaryContainer,
                    child: Text(
                      student.name[0],
                      style: TextStyle(color: colors.onPrimaryContainer),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          student.roll,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<Status>(
                    tooltip: 'Change status',
                    onSelected: (value) => setState(() {
                      student.status = value;
                      widget.onChanged();
                    }),
                    itemBuilder: (_) => Status.values
                        .map(
                          (value) => PopupMenuItem(
                            value: value,
                            child: Text(value.name),
                          ),
                        )
                        .toList(),
                    child: Chip(
                      label: Text(student.status.name),
                      backgroundColor: student.status == Status.Present
                          ? colors.primaryContainer
                          : student.status == Status.Absent
                          ? colors.errorContainer
                          : colors.tertiaryContainer,
                      labelStyle: TextStyle(
                        color: student.status == Status.Present
                            ? colors.onPrimaryContainer
                            : student.status == Status.Absent
                            ? colors.onErrorContainer
                            : colors.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: widget.onSave,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save attendance'),
          ),
        ),
      ],
    );
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.history});
  final List<String> history;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Attendance history',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        if (history.isEmpty)
          Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.calendar_month_outlined,
                    size: 38,
                    color: colors.primary,
                  ),
                  SizedBox(height: 12),
                  Text('No recent attendance yet'),
                  Text(
                    'Your latest updates will show here.',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ...history.map(
          (h) => ActionTile(
            icon: Icons.event_available_outlined,
            title: h.split(' · ').elementAt(1),
            subtitle: h,
          ),
        ),
      ],
    );
  }
}

class ManagementPage extends StatelessWidget {
  const ManagementPage({super.key, required this.students});
  final List<Learner> students;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('People', style: Theme.of(context).textTheme.headlineSmall),
        Text(
          'Manage campus directory',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: InputDecoration(
            hintText: 'Search name or roll number',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 12),
        ActionTile(
          icon: Icons.person_add_alt_1,
          title: 'Add student',
          subtitle: 'Create a student profile',
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Local demo directory is read-only')),
          ),
        ),
        const ActionTile(
          icon: Icons.badge_outlined,
          title: 'Faculty members',
          subtitle: 'Manage faculty accounts',
        ),
        const SizedBox(height: 14),
        ...students.map(
          (s) => ListTile(
            leading: CircleAvatar(child: Text(s.name[0])),
            title: Text(s.name),
            subtitle: Text(s.roll),
            trailing: const Icon(Icons.more_horiz),
          ),
        ),
      ],
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    required this.role,
    required this.dark,
    required this.onDark,
    required this.onLogout,
  });
  final Role role;
  final bool dark;
  final ValueChanged<bool> onDark;
  final VoidCallback onLogout;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'ACCOUNT',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.primary,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Profile & settings',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text(
          'Manage your account and appearance preferences.',
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: colors.primary,
                child: Icon(Icons.person, color: colors.onPrimary, size: 34),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role == Role.Student
                          ? 'Ananya Sharma'
                          : role == Role.Faculty
                          ? 'Dr. R. Mehta'
                          : 'Campus Admin',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      role == Role.Student
                          ? 'CS23018  ·  CSE  ·  Semester 5'
                          : '${role.name} account',
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: colors.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.verified_user_outlined,
                color: colors.onPrimaryContainer,
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'PREFERENCES',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.onSurfaceVariant,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            title: const Text('Dark appearance'),
            subtitle: Text(
              dark ? 'Dark theme is enabled' : 'Light theme is enabled',
            ),
            value: dark,
            onChanged: onDark,
            secondary: Icon(
              dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              color: colors.primary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'ABOUT',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.onSurfaceVariant,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        const ActionTile(
          icon: Icons.info_outline,
          title: 'About Attendly',
          subtitle: 'Student Attendance · Local demo',
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ),
      ],
    );
  }
}
