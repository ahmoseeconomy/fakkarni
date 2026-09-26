/// «بيسمع» — متعرّف الكلام بتاع الموبايل نفسه، ورا واجهة. التنفيذ الحقيقي في
/// `speech_to_text_listener.dart` (الملف الوحيد اللي بيستورد `speech_to_text`).
///
/// **مفيش تسجيل ولا رفع**: الصوت بيروح لمتعرّف النظام وبيرجع كلام مكتوب،
/// والكلام ده بيتفهم على الموبايل ([answer_parser]) وبيتنسي — ولا بيتخزّن.
/// المايك شغّال **بس** وهو داوس على الزرار، وبيقف لوحده بعد سكوت قصير.
abstract interface class SpeechListener {
  /// الإذن موجود؟ — من غير ما يطلبه.
  Future<bool> hasPermission();

  /// بيطلب الإذن من النظام لو لسه، وبيجهّز المتعرّف. null = جاهز؛ غير كده
  /// السبب — [ListenFailed.permission] لو الإذن اترفض، وإلا عطل تقني
  /// (الموبايل مفيهوش تعرّف كلام، اللغة مش موجودة، …).
  Future<ListenFailed?> prepare();

  /// بيسمع لحد [silence] سكوت أو [maxLength] كله. **ثلاث نتايج مختلفة**:
  /// اتقال كلام ([ListenHeard])، سكوت أو ما اتفهمش ([ListenSilence])، أو
  /// **السماع نفسه ما بدأش أو وقع** ([ListenFailed]) — والتالتة عمرها ما
  /// تتقال للمريض على إنها «مافهمتش».
  Future<ListenResult> listen({Duration silence, Duration maxLength});

  /// بيوقّف السماع فوراً — [listen] بترجّع [ListenSilence].
  Future<void> stop();

  /// آخر سماع اتعمل على الموبايل نفسه ولا اتبعت لأبل/جوجل؟ null = لسه
  /// ما سمعناش. الفرق ده بيتكتب في سجل التشخيص، وسياسة الخصوصية بتقوله.
  bool? get lastOnDevice;
}

/// نتيجة سماع واحد.
sealed class ListenResult {
  const ListenResult();
}

/// اتقال كلام واتكتب.
final class ListenHeard extends ListenResult {
  const ListenHeard(this.text);
  final String text;
}

/// المايك اتفتح وسمع، بس مفيش كلام (سكوت، أو المتعرّف ما لقاش كلام).
final class ListenSilence extends ListenResult {
  const ListenSilence();
}

/// السماع ما بدأش أو وقع في نصه — **مش** «مافهمتش». [reason] تقني، للسجل
/// وللأدمن بس؛ [permission] = الإذن هو السبب.
final class ListenFailed extends ListenResult {
  const ListenFailed(this.reason, {this.permission = false});
  final String reason;
  final bool permission;

  @override
  String toString() => 'ListenFailed($reason${permission ? ', permission' : ''})';
}
