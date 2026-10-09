import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

  test('iOS يسجّل APNs قبل نهاية الإقلاع عشان FCM يقدر يطلع توكن', () {
    final launch = delegate.indexOf('didFinishLaunchingWithOptions launchOptions');
    final register = delegate.indexOf('application.registerForRemoteNotifications()');
    final done = delegate.indexOf('return super.application(application, didFinishLaunchingWithOptions: launchOptions)');

    expect(register, greaterThan(launch));
    expect(register, lessThan(done));
  });
}
