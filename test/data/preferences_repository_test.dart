import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/preferences_repository.dart';
import 'package:fakkarni/domain/escalation/escalation_ladder.dart';

void main() {
  late AppDatabase db;
  late PreferencesRepository prefs;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    prefs = PreferencesRepository(db);
  });
  tearDown(() => db.close());

  test('من غير صف → النمط العادي والدرجتين شغّالين', () async {
    final s = await prefs.get();
    expect(s.elderMode, isFalse);
    expect(s.enabledRungs, EscalationRung.values.toSet());
  });

  test('كل مفتاح بيتكتب لوحده من غير ما يمسح التاني، وصف واحد بس', () async {
    await prefs.setElderMode(true);
    await prefs.setRung(EscalationRung.second, false);
    await prefs.setRung(EscalationRung.first, false);
    await prefs.setRung(EscalationRung.first, true);

    final s = await prefs.get();
    expect(s.elderMode, isTrue);
    expect(s.rungFirstOn, isTrue);
    expect(s.rungSecondOn, isFalse);
    expect(await db.select(db.devicePreferences).get(), hasLength(1));
  });
}
