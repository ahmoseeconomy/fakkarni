import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('تهيئة الإشعار والسحابة تبدأ تحت الـSplash لا قبله', () {
    final source = File('lib/main.dart').readAsStringSync();
    final local = source.indexOf('final local = await buildServices(db);');
    final run = source.indexOf(
      'runApp(FakkarniApp(services: activeServices));',
    );
    final notification = source.indexOf('await NotificationService.init(');
    final cloud = source.indexOf('final cloud = await initSupabaseAuth();');

    expect(local, greaterThanOrEqualTo(0));
    expect(run, greaterThan(local));
    expect(notification, greaterThan(run));
    expect(cloud, greaterThan(run));
  });
}
