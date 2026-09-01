/// مفتاح Gemini — من `--dart-define` وبس.
///
/// عمره ما بيتكتب في ملف git بيتابعه ولا في الكود. لو مش موجود، التطبيق
/// بيفتح عادي (التذكيرات ما تعتمدش عليه) بس شاشة التصوير بتقول بوضوح إنه
/// ناقص — وعمرنا ما بننده الـAPI بمفتاح فاضي.
class GeminiConfig {
  const GeminiConfig({required this.apiKey, this.model = defaultModel});

  static const defaultModel = 'gemini-2.5-flash';

  static const missingKeyMessage =
      'مفتاح Gemini مش موجود. شغّل التطبيق بـ '
      '--dart-define=GEMINI_API_KEY=... '
      '(أو --dart-define-from-file=secrets.json والملف ده برّه git).';

  /// بيتقرا وقت الترجمة من `--dart-define=GEMINI_API_KEY=...`.
  static const _envKey = String.fromEnvironment('GEMINI_API_KEY');

  final String apiKey;
  final String model;

  /// null لو المفتاح مش متظبط — الشاشة هي اللي بتقول للمستخدم.
  static GeminiConfig? tryFromEnvironment() =>
      _envKey.trim().isEmpty ? null : GeminiConfig(apiKey: _envKey.trim());

  /// بيرمي فوراً برسالة واضحة بدل ما يكمّل بمفتاح فاضي.
  static GeminiConfig fromEnvironment() =>
      tryFromEnvironment() ?? (throw StateError(missingKeyMessage));
}
