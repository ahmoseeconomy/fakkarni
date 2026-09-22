// **قرارات ٢٢ سبتمبر ٢٠٢٦، مقفولة بالاختبار مش بالتعليق.**
//
//   ١. صاحب حساب المريض بيدفع اشتراكه، وكل متابع بيدفع اشتراكه هو.
//   ٢. مفيش علامة «دوا مهم» — اتشالت في ٢ سبتمبر (القاعدة ٦).
//   ٣. الهدوء للمواعيد والملخصات بس؛ **الجرعة الفايتة بتعدّي في أي وقت**.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/care/caregiver_preferences.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('١ — «Pricing» في الدليل', () {
    final guide = _read('CLAUDE.md');

    test('**سطر ١٠ مابقاش بيقول إن الابن بيدفع اشتراك الأب**', () {
      expect(guide, isNot(contains('checks briefly, pays for the subscription')),
          reason: 'الجملة القديمة لسه مكتوبة');
      expect(guide, contains('pays for his\n  own subscription'));
    });

    test('والقسم موجود بتاريخه وبالقرار', () {
      expect(guide, contains('## Pricing'));
      expect(guide, contains('22 Sep 2026'));
      expect(guide, contains('a separate subscription'));
    });

    test('**وسؤالا السلامة مكتوبين** — دول اللي بيمنعوا الدفع يسكّت التذكير', () {
      // ١: اشتراك الأب يقف → التذكير يقف؟
      expect(guide, contains("If the father's subscription lapses"));
      // ٢: اشتراك المتابع يقف → الاتنين يتقالهم
      expect(guide, contains("If a follower's subscription lapses"));
      expect(guide, contains('two people must be told'));
    });

    test('**ومكتوب صراحةً إن مفيش متابع مجاني**', () {
      // الحارس بيدوّر على النفي، مش على غياب الكلمة: «مفيش متابع مجاني»
      // فيها «متابع مجاني»، فمنع الكلمة كان هيمنع الجملة اللي بتوضّحها.
      expect(guide, contains('There is **no** free extra follower'));
      expect(guide.replaceAll('\n', ' '), contains('a second son is a second subscription'));
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
