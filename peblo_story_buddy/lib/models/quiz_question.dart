// lib/models/quiz_question.dart
// Data model for quiz questions — fully data-driven, no hardcoded UI logic.
// Handles any number of options (3, 4, 5+) without code changes.

class QuizQuestion {
  final String question;
  final List<String> options;
  final String answer;

  const QuizQuestion({
    required this.question,
    required this.options,
    required this.answer,
  });

  /// Parse from JSON as if served by Peblo's backend.
  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    return QuizQuestion(
      question: json['question'] as String,
      options: List<String>.from(json['options'] as List),
      answer: json['answer'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'question': question,
        'options': options,
        'answer': answer,
      };

  bool isCorrect(String selectedOption) =>
      selectedOption.trim().toLowerCase() == answer.trim().toLowerCase();
}
