import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/emergency_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';

void main() {
  late AppDatabase db;
  late EmergencyRepository repo;
  late int patientId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = EmergencyRepository(db);
    patientId = await RoutineRepository(db).ensurePatient();
  });
  tearDown(() => db.close());

  test('من غير صف → كل حقل null («لسه ما اتملاش») ومفيش جهات اتصال', () async {
    final info = await repo.get(patientId);
    expect(info.bloodType, isNull);
    expect(info.allergies, isNull);
    expect(info.chronicConditions, isNull);
    expect(info.contacts, isEmpty);
  });

  test('بيتحفظ بالحرف، والفاضي والمسافات بيبقوا null — مش «لا يوجد»', () async {
    await repo.save(
      patientId,
      const EmergencyInfo(
        bloodType: 'O+',
        allergies: ' بنسلين — سلفا ',
        chronicConditions: '   ',
        contacts: [
          EmergencyContact(name: 'محمد', phone: '01001234567', relation: 'ابني'),
          EmergencyContact(name: '', phone: '0100', relation: 'ناقص'),
        ],
      ),
    );
    final info = await repo.get(patientId);
    expect(info.bloodType, 'O+');
    expect(info.allergies, 'بنسلين — سلفا');
    expect(info.chronicConditions, isNull);
    expect(info.contacts, [const EmergencyContact(name: 'محمد', phone: '01001234567', relation: 'ابني')]);
    expect(await db.select(db.emergencyProfile).get(), hasLength(1));
  });

  test('الحفظ التاني بيعدّل نفس الصف (نفس uuid) والتريجر بيحرّك updated_at_ms', () async {
    await repo.save(patientId, const EmergencyInfo(bloodType: 'A+'));
    final first = (await db.select(db.emergencyProfile).get()).single;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.save(patientId, const EmergencyInfo(bloodType: 'A-'));
    final second = (await db.select(db.emergencyProfile).get()).single;
    expect(second.uuid, first.uuid);
    expect(second.bloodType, 'A-');
    expect(second.updatedAtMs, greaterThan(first.updatedAtMs));
  });

  test('فصيلة مش من القايمة بترفض — مفيش حاجة بتتكتب غلط في صمت', () async {
    expect(() => repo.save(patientId, const EmergencyInfo(bloodType: 'O positive')), throwsArgumentError);
    expect(await db.select(db.emergencyProfile).get(), isEmpty);
  });

  test('صف JSON بايظ ما بيوقّعش الشاشة — جهات الاتصال بتبان فاضية', () async {
    await db.customStatement(
      "INSERT INTO emergency_profile (uuid, updated_at_ms, patient_id, contacts_json) VALUES ('e-1', 1, $patientId, 'not json')",
    );
    expect((await repo.get(patientId)).contacts, isEmpty);
  });
}
