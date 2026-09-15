import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/exam_provider.dart';
import '../../services/api_client.dart';
import '../../services/app_services.dart';

/// Creates an exam by uploading its questions as a spreadsheet.
///
/// The sheet is parsed on the server, per-row errors are reported back rather
/// than aborting the import, and the result screen names the rows that were
/// skipped — a 50-row sheet with one typo should import 49 questions and say
/// which one failed, not reject the whole file.
class UploadExamScreen extends StatefulWidget {
  const UploadExamScreen({super.key});

  @override
  State<UploadExamScreen> createState() => _UploadExamScreenState();
}

class _UploadExamScreenState extends State<UploadExamScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _durationController = TextEditingController(text: '30');
  final _totalMarksController = TextEditingController(text: '40');
  final _passingMarksController = TextEditingController(text: '16');
  final _negativeMarkingController = TextEditingController(text: '0');

  PlatformFile? _sheet;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _busy = false;

  @override
  void dispose() {
    _titleController.dispose();
    _subjectController.dispose();
    _descriptionController.dispose();
    _durationController.dispose();
    _totalMarksController.dispose();
    _passingMarksController.dispose();
    _negativeMarkingController.dispose();
    super.dispose();
  }

  Future<void> _pickSheet() async {
    // file_picker 13 reads the file explicitly rather than taking a `withData`
    // flag, which is what makes the same call work on web, where a picked file
    // has no filesystem path.
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls', 'csv'],
    );

    if (file == null) return;
    setState(() => _sheet = file);
  }

  Future<void> _pickDate({required bool isStart}) async {
    final today = DateTime.now();
    final initial = (isStart ? _startDate : _endDate) ?? today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today.subtract(const Duration(days: 30)),
      lastDate: today.add(const Duration(days: 365)),
    );

    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final sheet = _sheet;
    if (sheet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose the Excel file holding your questions.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    List<int> bytes;
    try {
      bytes = await sheet.readAsBytes();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That file could not be read. Try picking it again.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    // Reading the file back is async, so the widget may be gone by now.
    if (!mounted) return;
    setState(() => _busy = true);

    try {
      final created = await context.read<AppServices>().exams.createExam(
            fileBytes: bytes,
            filename: sheet.name,
            title: _titleController.text.trim(),
            subject: _subjectController.text.trim(),
            description: _descriptionController.text.trim(),
            duration: _durationController.text.trim(),
            totalMarks: _totalMarksController.text.trim(),
            passingMarks: _passingMarksController.text.trim(),
            negativeMarking: _negativeMarkingController.text.trim().isEmpty
                ? '0'
                : _negativeMarkingController.text.trim(),
            startDate: _startDate?.toIso8601String() ?? '',
            endDate: _endDate?.toIso8601String() ?? '',
          );

      if (!mounted) return;

      await context.read<ExamProvider>().loadAdminExams();
      if (!mounted) return;

      await _showResult(created.imported, created.skippedRows);
      if (!mounted) return;

      _resetForm();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: AppTheme.danger),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not create the exam.'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showResult(int imported, List<String> skippedRows) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(imported > 0 ? 'Exam created' : 'No questions imported'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$imported question${imported == 1 ? '' : 's'} imported.'),
                if (skippedRows.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    '${skippedRows.length} row${skippedRows.length == 1 ? '' : 's'} skipped:',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFAEB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFEDF89)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: skippedRows
                          .map(
                            (line) => Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Text(
                                line,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF93370D),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Fix those rows in the sheet and upload it again as a new exam, '
                    'or delete this exam and re-upload the corrected file.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF667085), height: 1.45),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _titleController.clear();
    _subjectController.clear();
    _descriptionController.clear();
    setState(() {
      _sheet = null;
      _startDate = null;
      _endDate = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SheetFormatHint(),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Question sheet',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  _SheetPicker(
                    file: _sheet,
                    onPick: _busy ? null : _pickSheet,
                    onClear: _busy ? null : () => setState(() => _sheet = null),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Exam details',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _titleController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'A title is required.' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _subjectController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Subject'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'A subject is required.' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _numberField(_durationController, 'Duration (min)')),
                      const SizedBox(width: 12),
                      Expanded(child: _numberField(_totalMarksController, 'Total marks')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _numberField(_passingMarksController, 'Passing marks')),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _numberField(
                          _negativeMarkingController,
                          'Negative / wrong',
                          allowDecimal: true,
                          allowZero: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Negative marking is a fraction of one question\'s marks — 0.25 '
                    'deducts a quarter. Leave it at 0 for no penalty.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF667085), height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _DateField(
                          label: 'Opens',
                          value: _startDate,
                          onTap: _busy ? null : () => _pickDate(isStart: true),
                          onClear: () => setState(() => _startDate = null),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DateField(
                          label: 'Closes',
                          value: _endDate,
                          onTap: _busy ? null : () => _pickDate(isStart: false),
                          onClear: () => setState(() => _endDate = null),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Leave the dates empty for an exam that is always available.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF667085)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  )
                : const Icon(Icons.upload_file, size: 19),
            label: Text(_busy ? 'Uploading and parsing...' : 'Create exam'),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    bool allowDecimal = false,
    bool allowZero = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) return 'Required.';
        final parsed = double.tryParse(text);
        if (parsed == null) return 'Numbers only.';
        if (parsed < 0) return 'Cannot be negative.';
        if (!allowZero && parsed == 0) return 'Must be more than 0.';
        if (allowDecimal && parsed >= 1) return 'Use a fraction below 1.';
        return null;
      },
    );
  }
}

/// Tells the admin what columns the parser expects, at the moment they need to
/// know it. Without this, a wrong header is only discovered as a failed import.
class _SheetFormatHint extends StatelessWidget {
  const _SheetFormatHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEAECF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.table_chart_outlined, size: 18, color: AppTheme.primary),
              SizedBox(width: 9),
              Text(
                'Sheet format',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'The first row must be a header row. Column names are matched '
            'case-insensitively, so "Question No." and "question no" both work.',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF475467), height: 1.45),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _ColumnChip(label: 'Question No.', optional: true),
              _ColumnChip(label: 'Question'),
              _ColumnChip(label: 'Option A'),
              _ColumnChip(label: 'Option B'),
              _ColumnChip(label: 'Option C'),
              _ColumnChip(label: 'Option D'),
              _ColumnChip(label: 'Correct Answer'),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Correct Answer must be A, B, C or D. A row with a missing option or an '
            'unrecognised answer is skipped and reported — the rest of the sheet '
            'still imports.',
            style: TextStyle(fontSize: 12, color: Color(0xFF667085), height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _ColumnChip extends StatelessWidget {
  const _ColumnChip({required this.label, this.optional = false});

  final String label;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: optional ? const Color(0xFFF9FAFB) : AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: optional ? const Color(0xFFEAECF0) : AppTheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        optional ? '$label (optional)' : label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: optional ? const Color(0xFF667085) : AppTheme.primary,
        ),
      ),
    );
  }
}

class _SheetPicker extends StatelessWidget {
  const _SheetPicker({required this.file, required this.onPick, required this.onClear});

  final PlatformFile? file;
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final picked = file;

    if (picked == null) {
      return _DottedPick(
        onTap: onPick,
        child: Column(
          children: const [
            Icon(Icons.cloud_upload_outlined, size: 36, color: AppTheme.primary),
            SizedBox(height: 10),
            Text(
              'Choose an .xlsx, .xls or .csv file',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            SizedBox(height: 4),
            Text(
              'Up to 10 MB',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF667085)),
            ),
          ],
        ),
      );
    }

    // Native pickers usually report the size with the result; a null here just
    // means it was not known without reading the file, which is not worth an
    // await on this screen.
    final length = picked.lengthSync();
    final sizeLabel = length == null ? 'Ready to upload' : '${(length / 1024).toStringAsFixed(0)} KB';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEAECF0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, color: AppTheme.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  picked.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                Text(
                  sizeLabel,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF667085)),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onClear, child: const Text('Replace')),
        ],
      ),
    );
  }
}

/// Dashed drop-zone look without a dashed-border package: a solid border at low
/// opacity reads the same at this size.
class _DottedPick extends StatelessWidget {
  const _DottedPick({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF9FAFB),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback? onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final chosen = value;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: chosen == null
              ? const Icon(Icons.event_outlined, size: 19)
              : IconButton(
                  icon: const Icon(Icons.close, size: 17),
                  onPressed: onClear,
                  tooltip: 'Clear',
                ),
        ),
        child: Text(
          chosen == null
              ? 'Any time'
              : '${chosen.day}/${chosen.month}/${chosen.year}',
          style: TextStyle(
            fontSize: 14.5,
            color: chosen == null ? const Color(0xFF98A2B3) : const Color(0xFF101828),
          ),
        ),
      ),
    );
  }
}
