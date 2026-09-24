// **قرارات ٢٢ سبتمبر ٢٠٢٦، مقفولة بالاختبار مش بالتعليق.**
//
//   ١. (اتغيّر ٢٤ سبتمبر بقرار المالك) اشتراك عيلة واحد على المريض بيغطّيه
//      هو ولحد ٥ متابعين — مش «كل واحد بيدفع».
//   ٢. مفيش علامة «دوا مهم» — اتشالت في ٢ سبتمبر (القاعدة ٦).
//   ٣. الهدوء للمواعيد والملخصات بس؛ **الجرعة الفايتة بتعدّي في أي وقت**.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/care/caregiver_preferences.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('١ — «Pricing» في الدليل', () {
    final guide = _read('CLAUDE.md');
    final flat = guide.replaceAll('\n', ' ').replaceAll(RegExp(r' +'), ' ');

    test('**سطر الابن مابقاش بيقول إنه بيدفع — لا لأبوه ولا لنفسه**', () {
      expect(guide, isNot(contains('checks briefly, pays for the subscription')),
          reason: 'الجملة الأصلية لسه مكتوبة');
      expect(guide, isNot(contains('pays for his\n  own subscription')),
          reason: 'نموذج ٢٢ سبتمبر («كل متابع بيدفع») لسه مكتوب كأنه الحالي');
      expect(flat, contains('**one family subscription** on the patient'));
    });

    test('والقسم موجود بتاريخ ٢٤ سبتمبر وبالقرار — اشتراك واحد للعيلة', () {
      expect(guide, contains('## Pricing'));
      expect(guide, contains('24 Sep 2026'));
      expect(flat, contains('ONE family subscription per patient covers the patient and up to 5'));
      expect(flat, contains('Not «each person pays»'));
      expect(flat, contains('Anyone in the circle may buy it'));
    });

    test('**وقاعدتا السلامة مكتوبين** — دول اللي بيمنعوا الدفع يسكّت التذكير', () {
      // ١: الدفع عمره ما يوقف تذكير المريض
      expect(flat, contains("The patient's own reminders never stop"));
      // ٢: التحقق المش واصل = آخر حالة معروفة، مش قفل
      expect(flat, contains('Unreachable verification = last known state'));
      // والدائرة بتتقال لها قبل ما التنبيهات تقف وبعدها
      expect(flat, contains('The circle is told before the alerts stop, and after'));
    });

    test('**والحد مكتوب: ٥ ناس، مش متابع مجاني من غير سقف**', () {
      expect(flat, contains('`redeem_invite` returns `circle_full` at `follower_cap()` (5)'));
    });
  });

  group('٢ — مفيش علامة «دوا مهم»، ومفيش اختيار بيسكت', () {
    test('نطاق التنبيه ليه قيمة واحدة النهارده', () {
      expect(AlertScope.values, [AlertScope.everyMissedDose]);
    });

    test('**والعلامة مش موجودة في أي مكان** — ما اترجعتش من ورا الباب', () {
      for (final dir in ['lib', 'supabase']) {
        for (final file in Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart') || f.path.endsWith('.sql'))) {
          final text = file.readAsStringSync();
          for (final banned in ['isCritical', 'is_critical', 'criticalMedication']) {
            expect(text.contains(banned), isFalse,
                reason: '${file.path} فيه «$banned» — العلامة اتشالت عن قصد');
          }
        }
      }
    });

    test('والقيمة المخزّنة المش معروفة بترجع للافتراضي الآمن', () {
      expect(AlertScope.fromStored(null), AlertScope.everyMissedDose);
      expect(AlertScope.fromStored('importantOnly'), AlertScope.everyMissedDose);
    });
  });

  group('٣ — الهدوء ما بيلمسش اختيار التصعيد على السيرفر', () {
    final migration = _read('supabase/migrations/0020_caregiver_preferences.sql');

    test('**`due_escalations` ما بتقراش ساعات الهدوء**', () {
      // الاختيار كله في الدالة دي؛ لو الهدوء دخلها، جرعة فايتة ممكن
      // تتأجّل لحد الصبح — وده بالظبط اللي السلّم موجود عشان يمنعه.
      final body = migration.substring(migration.indexOf('create or replace function private.due_escalations'));
      final selection = body.substring(0, body.indexOf(r'$$;'));
      for (final banned in ['quiet_from_minute', 'quiet_to_minute', 'caregiver_preferences']) {
        expect(selection.contains(banned), isFalse,
            reason: 'الهدوء دخل اختيار التصعيد — «$banned»');
      }
    });

    test('وبتنده سكّة الاشتراك بالاسم', () {
      expect(migration, contains('private.follower_subscription_active'));
      expect(migration, contains('and private.follower_subscription_active(cr.caregiver_id)'));
    });

    test('والسكّة بترجّع true النهارده — مفيش بوابة دفع اتبنت', () {
      final seam = migration.substring(
          migration.indexOf('create or replace function private.follower_subscription_active'));
      expect(seam.substring(0, seam.indexOf(r'$$;')), contains('select true'));
    });

    test('والسيم بيشاور على «Pricing» — عشان اللي هيبنيه يلاقي القرار', () {
      expect(migration, contains('Pricing'));
    });
  });

  group('التفضيلات في السحابة، والأب بيقرا الاسم والصلة بس', () {
    final migration = _read('supabase/migrations/0020_caregiver_preferences.sql');

    test('RLS مفعّل، والسياسات على عمود الصف نفسه (قاعدة ٠٠٠٥)', () {
      expect(migration, contains('alter table public.caregiver_preferences enable row level security'));
      expect(migration, contains('using (caregiver_id = (select auth.uid()))'));
    });

    test('**والأب بيعدّي على دالة، مش على سياسة**', () {
      // سياسات بوستجرس على الصف مش على العمود: لو الأب اتسمح له بالصف
      // كان هيقرا ساعات هدوء ابنه كمان.
      expect(migration, contains('create or replace function public.followers_of_patient'));
      expect(migration, contains('select cp.display_name, cp.relation, cp.relation_other'));
      expect(migration, contains('private.owns_patient(p_patient_uuid)'));
      final fn = migration.substring(
          migration.indexOf('create or replace function public.followers_of_patient'));
      final body = fn.substring(0, fn.indexOf(r'$$;'));
      expect(body.contains('quiet_from_minute'), isFalse,
          reason: 'الأب بيقرا ساعات هدوء ابنه');
      expect(body.contains('alert_scope'), isFalse);
    });

    test('والمالك بيتعمل في auth.users قبل المريض في الفحص الذاتي', () {
      final check = migration.substring(migration.indexOf(r'do $$'));
      expect(check.indexOf('insert into auth.users'),
          lessThan(check.indexOf('insert into public.patients')));
    });
  });
}
