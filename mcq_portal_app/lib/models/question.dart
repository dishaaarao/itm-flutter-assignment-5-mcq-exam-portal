/// A question as the student receives it.
///
/// The server sends only `{id, questionNo, question, imageUrl, options}` — the
/// correct answer is never in this payload. There is deliberately no
/// `correctAnswer` field here, so a leak would be a compile error rather than a
/// quiet regression.
class Question {
  const Question({
    required this.id,
    required this.questionNo,
    required this.question,
    required this.options,
    this.imageUrl,
  });

  final String id;
  final int questionNo;
  final String question;
  final List<String> options;
  final String? imageUrl;

  static const List<String> optionLetters = ['A', 'B', 'C', 'D'];

  /// Letter for the option at [index], or `?` past the end.
  static String letterFor(int index) =>
      index >= 0 && index < optionLetters.length ? optionLetters[index] : '?';

  /// The option letter for [optionText], or null when it is not one of them.
  String? letterForOption(String? optionText) {
    if (optionText == null) return null;
    final index = options.indexOf(optionText);
    return index == -1 ? null : letterFor(index);
  }

  factory Question.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    return Question(
      id: json['id'] as String? ?? '',
      questionNo: (json['questionNo'] as num?)?.toInt() ?? 0,
      question: json['question'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      options: rawOptions is List
          ? rawOptions.map((option) => option?.toString() ?? '').toList()
          : const <String>[],
    );
  }
}
