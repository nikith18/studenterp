import 'package:flutter/material.dart';

enum AdvancedFeatureRole { student, faculty, admin }

class AdvancedFeaturesPage extends StatefulWidget {
  const AdvancedFeaturesPage({super.key, required this.role});
  final AdvancedFeatureRole role;

  @override
  State<AdvancedFeaturesPage> createState() => _AdvancedFeaturesPageState();
}

class _AdvancedFeaturesPageState extends State<AdvancedFeaturesPage> {
  final _items = <_DemoItem>[
    _DemoItem(
      'On Duty request · Data Structures',
      'Academic conference · 28 Oct',
      _Kind.request,
      'Pending',
    ),
    _DemoItem(
      'Attendance dispute · Database Systems',
      'Present on 24 Oct was recorded absent',
      _Kind.dispute,
      'Pending',
    ),
    _DemoItem(
      'Guardian access · R. Sharma',
      'Read-only attendance access request',
      _Kind.guardian,
      'Pending',
    ),
  ];
  bool guardianConsent = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isStudent = widget.role == AdvancedFeatureRole.student;
    final visible = isStudent
        ? _items.where(
            (item) =>
                item.kind != _Kind.guardian || item.title.contains('R. Sharma'),
          )
        : _items.where((item) => item.kind != _Kind.guardian);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Advanced features', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          isStudent
              ? 'Requests, disputes, and guardian consent.'
              : 'Review requests and attendance disputes.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        const _DemoBanner(),
        const SizedBox(height: 20),
        if (isStudent) ...[
          Text('Your requests', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _createRequest,
            icon: const Icon(Icons.add),
            label: const Text('New OD / leave request'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _createDispute,
            icon: const Icon(Icons.report_gmailerrorred_outlined),
            label: const Text('Dispute attendance'),
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              value: guardianConsent,
              onChanged: (value) => setState(() => guardianConsent = value),
              title: const Text('Guardian read-only access'),
              subtitle: Text(
                guardianConsent
                    ? 'Demo consent is active · tap to revoke'
                    : 'Allow a linked guardian to view attendance',
              ),
              secondary: const Icon(Icons.family_restroom_outlined),
            ),
          ),
        ] else ...[
          Text(
            widget.role == AdvancedFeatureRole.admin
                ? 'All demo review items'
                : 'Assigned review queue',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Tap a pending item to record an approve or reject decision with a reason.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 8),
        if (visible.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No requests yet. Create a demo request to see it here.',
              ),
            ),
          )
        else
          ...visible.map(
            (item) => _ItemCard(
              item: item,
              onTap: () => isStudent ? _showDetails(item) : _review(item),
            ),
          ),
        if (!isStudent) ...[
          const SizedBox(height: 8),
          Text(
            'Sample data is provided for demonstrations. Decisions stay on this device and do not modify real attendance.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Future<void> _createRequest() async {
    final result = await _submissionDialog(
      'New On Duty / leave request',
      'Reason and date range',
    );
    if (result == null) return;
    setState(
      () => _items.insert(
        0,
        _DemoItem(
          'Leave request · Data Structures',
          result,
          _Kind.request,
          'Pending',
        ),
      ),
    );
    _confirm('Demo request submitted.');
  }

  Future<void> _createDispute() async {
    final result = await _submissionDialog(
      'Dispute attendance',
      'Subject and explanation',
    );
    if (result == null) return;
    setState(
      () => _items.insert(
        0,
        _DemoItem(
          'Attendance dispute · Data Structures',
          result,
          _Kind.dispute,
          'Pending',
        ),
      ),
    );
    _confirm('Demo dispute submitted.');
  }

  Future<String?> _submissionDialog(String title, String hint) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.length >= 4) Navigator.pop(context, text);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _review(_DemoItem item) async {
    final reason = TextEditingController();
    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.detail),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration: const InputDecoration(
                labelText: 'Decision reason',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (reason.text.trim().length >= 4) {
                Navigator.pop(context, 'Rejected');
              }
            },
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().length >= 4) {
                Navigator.pop(context, 'Approved');
              }
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    reason.dispose();
    if (decision == null) return;
    setState(() => item.status = decision);
    _confirm('Demo decision recorded: $decision.');
  }

  Future<void> _showDetails(_DemoItem item) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.title),
        content: Text('${item.detail}\n\nStatus: ${item.status}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _confirm(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.secondaryContainer,
      child: ListTile(
        leading: Icon(
          Icons.science_outlined,
          color: colors.onSecondaryContainer,
        ),
        title: Text(
          'Local demo mode',
          style: TextStyle(
            color: colors.onSecondaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          'Sample data and actions are simulated on this device. Nothing is sent to a server.',
          style: TextStyle(color: colors.onSecondaryContainer),
        ),
      ),
    );
  }
}

enum _Kind { request, dispute, guardian }

class _DemoItem {
  _DemoItem(this.title, this.detail, this.kind, this.status);
  final String title;
  final String detail;
  final _Kind kind;
  String status;
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.onTap});
  final _DemoItem item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final icon = switch (item.kind) {
      _Kind.request => Icons.event_note_outlined,
      _Kind.dispute => Icons.fact_check_outlined,
      _Kind.guardian => Icons.family_restroom_outlined,
    };
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(item.title),
        subtitle: Text('${item.detail}\nStatus · ${item.status}'),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
