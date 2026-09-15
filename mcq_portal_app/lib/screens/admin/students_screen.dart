import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/attempt.dart';
import '../../models/user.dart';
import '../../services/app_services.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/error_view.dart';
import '../../widgets/loading_view.dart';

/// Every registered student, with a drill-down into their attempts.
class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  List<AppUser> _students = const <AppUser>[];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final students = await context.read<AppServices>().attempts.listStudents();
      if (!mounted) return;
      setState(() {
        _students = students;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _students.isEmpty) {
      return const LoadingView(message: 'Loading students...');
    }

    if (_error != null && _students.isEmpty) {
      return ErrorView(message: _error!, onRetry: _load);
    }

    if (_students.isEmpty) {
      return const EmptyView(
        icon: Icons.people_outline,
        title: 'No students yet',
        message: 'Students appear here once they create an account.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _students.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final student = _students[index];
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                child: Text(
                  student.initials,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                    fontSize: 14,
                  ),
                ),
              ),
              title: Text(
                student.name,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              subtitle: Text(
                student.email,
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF667085)),
              ),
              trailing: const Icon(Icons.chevron_right, color: Color(0xFF98A2B3)),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StudentAttemptsScreen(student: student),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One student's attempt history, from the admin's side.
class StudentAttemptsScreen extends StatefulWidget {
  const StudentAttemptsScreen({super.key, required this.student});

  final AppUser student;

  @override
  State<StudentAttemptsScreen> createState() => _StudentAttemptsScreenState();
}

class _StudentAttemptsScreenState extends State<StudentAttemptsScreen> {
  List<AttemptRow> _attempts = const <AttemptRow>[];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await context
          .read<AppServices>()
          .attempts
          .getStudentAttempts(widget.student.id);
      if (!mounted) return;
      setState(() {
        _attempts = result.attempts;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.student.name)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _attempts.isEmpty) {
      return const LoadingView(message: 'Loading attempts...');
    }

    if (_error != null && _attempts.isEmpty) {
      return ErrorView(message: _error!, onRetry: _load);
    }

    if (_attempts.isEmpty) {
      return const EmptyView(
        icon: Icons.assignment_outlined,
        title: 'No attempts',
        message: 'This student has not started an exam yet.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _attempts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _AttemptTile(row: _attempts[index]),
      ),
    );
  }
}

class _AttemptTile extends StatelessWidget {
  const _AttemptTile({required this.row});

  final AttemptRow row;

  @override
  Widget build(BuildContext context) {
    final submitted = row.isSubmitted;
    final colour = !submitted
        ? AppTheme.warning
        : row.isPass
            ? AppTheme.accent
            : AppTheme.danger;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.examTitle?.isNotEmpty == true ? row.examTitle! : 'Exam',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  submitted ? '${_fmt(row.percentage ?? 0)}%' : 'In progress',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colour),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  submitted
                      ? '${_fmt(row.score ?? 0)} / ${_fmt(row.totalMarks ?? 0)} marks'
                      : 'Not submitted',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF475467)),
                ),
                if (submitted && row.grade != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.gradeColor(row.grade!).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      row.grade!,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.gradeColor(row.grade!),
                      ),
                    ),
                  ),
                ],
                if (row.autoSubmitted) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.schedule, size: 14, color: AppTheme.warning),
                ],
              ],
            ),
            if (row.startedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Started ${_humanDate(row.startedAt!)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF98A2B3)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Trims trailing zeros, and renders a missing number as an em dash rather than
/// a misleading zero.
String _fmt(num? value) {
  if (value == null) return '—';
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

String _humanDate(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = parsed.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]} ${local.year}, $hour:$minute';
}
