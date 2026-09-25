import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/data/care/circle_departures.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/sync/departure_pull.dart';
import 'package:fakkarni/data/sync/medication_change_pull.dart';
import 'package:fakkarni/domain/care/circle_departure.dart';
import 'package:fakkarni/domain/care/follower_profile.dart';
import 'package:fakkarni/features/care/caregiver_words.dart';

CircleDeparture dep(String id, {String? name, FollowerRelation? relation, bool nurse = false, int day = 20}) =>
    CircleDeparture(uuid: id, leftAt: DateTime(2026, 9, day), displayName: name, relation: relation, nurse: nurse);

class FakeDepartures implements CircleDepartureRemote {
  List<CircleDeparture> rows = [];
  @override
  Future<List<CircleDeparture>> forPatient(String patientUuid) async => rows;
}

void main() {
  group('الجملة', () {
    test('الفعل بيمشي مع الصلة — «خرجت» للبنت بس', () {
      expect(departureLine(dep('a', name: 'محمد', relation: FollowerRelation.son)), 'محمد خرج من الدايرة');
      expect(departureLine(dep('a', name: 'سارة', relation: FollowerRelation.daughter)), 'سارة خرجت من الدايرة');
      // الاسم ما بيقولش ولد ولا بنت — من غير صلة، المذكّر الافتراضي زي باقي التطبيق
      expect(departureLine(dep('a', name: 'نور')), 'نور خرج من الدايرة');
    });

    test('من غير اسم: مفيش اسم بيتخترع', () {
      expect(departureLine(dep('a', nurse: true)), 'الممرض أو المرافق خرج من الدايرة');
      expect(departureLine(dep('a', name: '  ')), 'حد من اللي بيتابعوك خرج من الدايرة');
    });

    test('الصف من السحابة', () {
      final d = CircleDeparture.fromRow({
        'uuid': 'u',
        'display_name': 'سارة',
        'relation': 'daughter',
        'role': 'nurse',
        'left_at': '2026-09-20T10:00:00Z',
      });
      expect(d.nurse, isTrue);
      expect(d.relation, FollowerRelation.daughter);
    });
  });

  group('موبايل المريض', () {
    late AppDatabase db;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      MedicationChangePuller.notices.value = const [];
      db = AppDatabase(NativeDatabase.memory());
    });
    tearDown(() => db.close());

    test('السطر الجديد بينزل على «يومك» مرة واحدة — السحبة التانية ما بتكرّروش', () async {
      final routines = RoutineRepository(db);
      final pid = await routines.ensurePatient();
      final remote = FakeDepartures()..rows = [dep('1', name: 'محمد', relation: FollowerRelation.son)];
      final puller = CircleDeparturePuller(remote: remote, routines: routines, patientId: pid);

      expect(await puller.pull(), 1);
      expect(MedicationChangePuller.notices.value, ['محمد خرج من الدايرة']);
      expect(await puller.pull(), 0, reason: 'اتشاف خلاص');
      expect(MedicationChangePuller.notices.value, hasLength(1));

      remote.rows = [dep('2', name: 'سارة', relation: FollowerRelation.daughter), ...remote.rows];
      expect(await puller.pull(), 1);
      expect(MedicationChangePuller.notices.value.first, 'سارة خرجت من الدايرة');
    });

    test('السحابة وقعت: ولا سطر ولا رمي', () async {
      final routines = RoutineRepository(db);
      final pid = await routines.ensurePatient();
      final puller = CircleDeparturePuller(remote: _Throwing(), routines: routines, patientId: pid);
      expect(await puller.pull(), 0);
    });
  });

  test('عند الابن: الخروج بيظهر في «الجديد» بنفس الجملة', () {
    final snapshot = CaregiverSnapshot(
      patient: const CaregiverPatient(uuid: 'p', name: 'الحاج أحمد'),
      medications: const [],
      events: const [],
      departures: [dep('1', name: 'سارة', relation: FollowerRelation.daughter)],
    );
    final items = newestArrivals(snapshot);
    expect(items.single.type, NewItemType.departure);
    expect(newItemTitle(items.single), 'سارة خرجت من الدايرة');
  });
}

class _Throwing implements CircleDepartureRemote {
  @override
  Future<List<CircleDeparture>> forPatient(String patientUuid) async => throw StateError('offline');
}
