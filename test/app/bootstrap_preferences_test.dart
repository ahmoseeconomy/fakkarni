import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/bootstrap.dart';
import 'package:fakkarni/data/db/app_database.dart';

void main() {
  // التطبيق وعزلة «أخدته» الاتنين بيبنوا الخدمات من هنا. لو الجدولة اتبنت
  // من غير التفضيلات، أول «أخدته» من شاشة القفل كان هيرجّع الدرجات اللي
  // المستخدم قفلها — في صمت.
  test('buildServices بيدّي الجدولة تفضيلات الجهاز', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final services = await buildServices(db);
    expect(services.scheduler.preferences, isNotNull);
    await db.close();
  });
}
