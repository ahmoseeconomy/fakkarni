import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **`moddatetime` بتتكتب من غير سكيما — وده مش ذوق.**
///
/// `0020` اتكتبت `execute function extensions.moddatetime (updated_at)`،
/// والمشروع الحقيقي ردّ **`function extensions.moddatetime() does not
/// exist`**: الامتداد متركّب في سكيما تانية عنده، والاسم المؤهَّل بيشاور
/// على مكان مش موجود. كل الملفات اللي قبلها (`0004`، `0006`، `0012`،
/// `0018`) بتكتبها من غير سكيما وبتشتغل.
///
/// **الغلطة دي ما بتظهرش غير على مشروع حقيقي**: الملف شكله سليم، و
/// `flutter test` عمره ما هيشغّل بوستجرس. الاختبار بيقرا نص الـSQL نفسه
/// عشان الغلطة تتمسك هنا بدل ما تتمسك بعد ما الوقت يتضيّع — نفس منطق
/// `migration_selfcheck_owner_test`.
void main() {
  final files = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('فيه ملفات هجرة تتقرا أصلاً', () {
    expect(files, isNotEmpty, reason: 'لو المسار اتغيّر، الاختبار ده بيبقى بيمرّ على فاضي');
  });

  for (final file in files) {
    final name = file.path.split(Platform.pathSeparator).last;
    final source = file.readAsStringSync().toLowerCase();

    test('$name: مفيش `extensions.moddatetime`', () {
      expect(
        source.contains('extensions.moddatetime'),
        isFalse,
        reason: '$name بينده moddatetime باسم مؤهَّل — المشروع الحقيقي بيرد '
            '«function extensions.moddatetime() does not exist». '
            'اكتبها `execute procedure moddatetime (updated_at)` زي 0004/0012/0018.',
      );
    });
  }

  test('**والحارس شاف الحالة فعلاً**: فيه ملفات بتستعمل الشكل الصح', () {
    // حارس شرطه عمره ما يتحقّق مش حارس. لو ولا ملف بينده moddatetime
    // خالص، الاختبار فوق بيعدّي على فراغ — والسطر ده هو اللي بيمنع ده.
    final using = [
      for (final f in files)
        if (f.readAsStringSync().contains('moddatetime (updated_at)')) f.path,
    ];
    expect(using, isNotEmpty, reason: 'ولا ملف بينده moddatetime — الحارس بيمرّ على فاضي');
  });
}
