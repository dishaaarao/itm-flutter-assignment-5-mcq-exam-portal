import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/attempt_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/exam_provider.dart';
import '../auth/login_screen.dart';
import 'exam_list_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';

/// Shell around the three student areas.
class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  int _tab = 0;

  /// The tabs live in an [IndexedStack], so the history would keep whatever it
  /// read the first time it was built. Reaching into it here is what lets a
  /// paper submitted a moment ago show up on the Results tab.
  final GlobalKey<HistoryViewState> _historyKey = GlobalKey<HistoryViewState>();

  static const List<String> _titles = ['Available exams', 'My results', 'Profile'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExamProvider>().loadStudentExams();
    });
  }

  /// Refreshes whichever tab is on screen. The profile tab reads nothing from
  /// the server, so it has nothing to reload.
  void _refreshCurrentTab() {
    switch (_tab) {
      case 0:
        context.read<ExamProvider>().loadStudentExams();
      case 1:
        _historyKey.currentState?.reload();
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to take an exam.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Drop any half-finished session so the next sign-in starts clean.
    context.read<AttemptProvider>().reset();
    await context.read<AuthProvider>().logout();

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_titles[_tab]),
            if (_tab == 0 && user != null)
              Text(
                'Hello, ${user.name.split(' ').first}',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF667085)),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshCurrentTab,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          const ExamListView(),
          HistoryView(key: _historyKey),
          const ProfileView(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) {
          setState(() => _tab = index);
          _refreshCurrentTab();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Exams',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Results',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
