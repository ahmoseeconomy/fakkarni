import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/core/images/med_photo.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/files/attachment_store.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/features/medication/circle_med_photo.dart';
import 'package:fakkarni/features/medication/med_photo.dart';
import 'package:fakkarni/features/records/attachment_viewer.dart';

import '../../core/med_photo_prepare_test.dart' show photoWithExif;
import '../scan/scan_test_support.dart' show RecordingSink;

/// مفيش صورة، أو الملف راح، أو بايظ → الأيقونة اللي كانت موجودة. **عمرها
/// ما بتعرض صورة مكسورة.**
void main() {
  late AppDatabase db;
  late Directory dir;
  late AppServices services;
  const icon = Icon(Icons.medication_outlined, key: ValueKey('fallback-icon'));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('thumb');
    final routines = RoutineRepository(db);
    final meds = MedicationRepository(db);
    final patientId = await routines.ensurePatient();
    services = AppServices(
      db: db,
      routines: routines,
      medications: meds,
      events: DoseEventRepository(db),
      scheduler: ReminderScheduler(
        routines: routines,
        medications: meds,
        events: DoseEventRepository(db),
        patientId: patientId,
        sink: RecordingSink(),
      ),
      patientId: patientId,
      medPhotoStore: DirectoryAttachmentStore(root: dir, subfolder: DirectoryAttachmentStore.medPhotoFolder),
    );
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester, String? path) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(AppScope(
        services: services,
        child: MaterialApp(
          theme: F.light,
          home: Scaffold(body: Center(child: MedPhotoThumb(path: path, name: 'Concor', fallback: icon))),
        ),
      ));
      // الملف بيتقرا والصورة بتتفكّ على الـevent loop الحقيقي
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    // فكّ الصورة (أو فشله) بياخد كام دورة على الـevent loop الحقيقي
    for (var i = 0; i < 6; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    }
    await tester.pump();
  }

  testWidgets('من غير صورة → الأيقونة', (tester) async {
    await pump(tester, null);
    expect(find.byKey(const ValueKey('fallback-icon')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('الملف راح → الأيقونة، مش مربع فاضي', (tester) async {
    await pump(tester, 'med-photos/gone.jpg');
    expect(find.byKey(const ValueKey('fallback-icon')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('ملف بايظ → الأيقونة، مش صورة مكسورة', (tester) async {
    await tester.runAsync(() async {
      final f = File('${dir.path}/med-photos/bad.jpg');
      await f.parent.create(recursive: true);
      await f.writeAsBytes([1, 2, 3, 4, 5]);
    });
    await pump(tester, 'med-photos/bad.jpg');
    expect(find.byKey(const ValueKey('fallback-icon')), findsOneWidget);
  });

  testWidgets('صورة سليمة → بتتعرض، والدوسة بتفتحها كبيرة', (tester) async {
    late String path;
    await tester.runAsync(() async {
      path = await services.medPhotoStore.save(prepareMedPhoto(photoWithExif())!);
    });
    await pump(tester, path);
    expect(find.byKey(ValueKey('med-photo-$path')), findsOneWidget);
    expect(find.byKey(const ValueKey('fallback-icon')), findsNothing);

    await tester.tap(find.byKey(ValueKey('med-photo-$path')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AttachmentViewerScreen), findsOneWidget);
    expect(find.text('اقفل'), findsOneWidget, reason: 'زرار بكلمة، مش أيقونة لوحدها');
  });

  testWidgets('من غير AppScope (شاشة لوحدها) → الأيقونة', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MedPhotoThumb(path: 'x.jpg', name: 'x', fallback: icon)));
    expect(find.byKey(const ValueKey('fallback-icon')), findsOneWidget);
  });

  testWidgets('العيلة والممرض: من غير كاش صور (مفيش سحابة) → الأيقونة', (tester) async {
    await tester.pumpWidget(AppScope(
      services: services,
      child: const MaterialApp(
        home: CircleMedPhotoThumb(patientUuid: 'p', medicationUuid: 'm', name: 'x', fallback: icon),
      ),
    ));
    expect(find.byKey(const ValueKey('fallback-icon')), findsOneWidget);
  });
}
