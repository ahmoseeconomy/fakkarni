import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/patient_voice.dart';
import '../../core/widgets/primitives.dart';
import '../../data/repositories/preferences_repository.dart';
import '../../domain/escalation/escalation_ladder.dart';

/// «التنبيهات» (المخطط 26) — الصفوف اللي وراها حاجة حقيقية بس.
///
/// **الإلزامي مقفول بـ🔒 «دائمًا»، ومالوش مفتاح أصلاً**: «تفويت جرعة»،
/// التذكير «في الموعد»، و«إشعار لابنك» (من السيرفر، بعد مهلته
/// [serverGraceWindow]). اللي بيتقفل بجد درجتين بس: +١٥ و+٣٠ — والجدولة
/// بتقرا الاختيار وقت ما بتجدول وبتشيل الدرجة المقفولة، والسلّم نفسه ما
/// اتغيّرش.
///
/// مش مبني عن قصد (مكتوب في المؤجَّل): «ساعات الهدوء» (مفيش غير الإلزامي
/// عشان تسكّته)، «نداء الطوارئ» (بييجي مع D3.4)، وصفوف «قراءة سكر» و«نشاط
/// الدائرة» (مفيش إشعار وراهم). مفتاح ما بيعملش حاجة أسوأ من صف مش موجود.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  Stream<DeviceSettings>? _settings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settings ??= AppScope.of(context).preferences.watch();
  }

  Future<void> _set(EscalationRung rung, bool on) async {
    final services = AppScope.of(context);
    await services.preferences.setRung(rung, on);
    // الاختيار بيوصل للإشعارات المتجدولة دلوقتي، مش أول فتحة جاية
    await services.scheduler.rescheduleAll();
  }

  @override
  Widget build(BuildContext context) {
    final say = PatientVoice.of(context);
    String minutes(Duration d) => '+${arabicNumber(d.inMinutes)} د';

    return Scaffold(
      appBar: AppBar(title: const Text('التنبيهات')),
      body: StreamBuilder<DeviceSettings>(
        stream: _settings,
        builder: (context, snap) {
          final settings = snap.data ?? const DeviceSettings();
          return ListView(
            padding: const EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.s30 * 2),
            children: [
              Text(
                'إيه اللي بيرن على الموبايل ده، وإمتى ابنك بيتبلّغ.',
                style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5),
              ),
              const SizedBox(height: F.s12),
              Container(
                padding: const EdgeInsets.all(F.s12),
                decoration: BoxDecoration(
                  color: F.railGround,
                  borderRadius: BorderRadius.circular(F.radiusCard),
                ),
                child: Row(
                  children: [
                    Icon(Icons.phone_iphone, size: 24, color: F.mutedDark),
                    SizedBox(width: F.s8),
                    Expanded(
                      child: Text(
                        'الإعدادات دي على الموبايل ده بس.',
                        style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: F.gap),
              const SectionHead('الجرعات'),
              const SizedBox(height: F.s8),
              FCard(
                child: _LockedRow(
                  label: 'تفويت جرعة',
                  hint: 'لو عدّت ${arabicNumber(serverGraceWindow.inMinutes)} دقيقة من غير تأكيد، '
                      'ابنك بيتبلّغ — ما بيتقفلش',
                ),
              ),
              const SizedBox(height: F.gap),
              const SectionHead('سلّم التذكير'),
              const SizedBox(height: F.s8),
              FCard(
                child: Column(
                  children: [
                    const _LockedRow(label: 'في الموعد', hint: 'التذكير نفسه'),
                    Divider(color: F.lineSoft, height: F.s16),
                    FSwitch(
                      key: const ValueKey('rung-first'),
                      label: minutes(EscalationRung.first.delay),
                      subtitle: 'تذكير تاني ${say.pick('لو ما أكّدتش', 'لو ما أكّدتيش')}',
                      value: settings.rungFirstOn,
                      onChanged: (on) => _set(EscalationRung.first, on),
                    ),
                    Divider(color: F.lineSoft, height: F.s16),
                    FSwitch(
                      key: const ValueKey('rung-second'),
                      label: minutes(EscalationRung.second.delay),
                      subtitle: 'تذكير تالت، وبيهزّ',
                      value: settings.rungSecondOn,
                      onChanged: (on) => _set(EscalationRung.second, on),
                    ),
                    Divider(color: F.lineSoft, height: F.s16),
                    _LockedRow(
                      label: '${minutes(serverGraceWindow)} — إشعار لابنك',
                      hint: 'من السيرفر، لو الموبايل مربوط بابنك',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: F.s10),
              Text(
                '${say.pick('لو قفلت', 'لو قفلتي')} +١٥ و+٣٠، التذكير في الموعد وإشعار ابنك بيفضلوا زي ما هم.',
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// صف إلزامي: كلمة وشرح، و🔒 «دائمًا» مكان المفتاح. مش زرار — مالوش دوسة.
class _LockedRow extends StatelessWidget {
  const _LockedRow({required this.label, required this.hint});

  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: F.minTapTarget),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
                  ),
                  Text(hint, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5)),
                ],
              ),
            ),
            const SizedBox(width: F.s8),
            Icon(Icons.lock_outline, size: 22, color: F.mutedDark),
            const SizedBox(width: F.s4),
            Text(
              'دائمًا',
              style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.mutedDark),
            ),
          ],
        ),
      );
}
