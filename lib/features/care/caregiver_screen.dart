import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../data/care/caregiver_remote.dart';

/// «متابعة {الاسم}» — نافذة الابن (المخطط 04 + شريط أسبوع 12).
///
/// الشاشة دي **بتبلّغ ولا تحكم**: جرعة عدّى وقتها من غير تأكيد بتتقال
/// بعد قد إيه من غير أي تحديث يبقى التذييل ذهبي.
///
/// يوم كامل: أب فتح التطبيق امبارح لسه عادي، وأب سكت يومين مش عادي —
/// وتغطية السحابة نفسها يومين (شوف `rescheduleAll`). فالتذييل بيولّع
/// قبل ما التغطية تخلص، مش بعدها.
const Duration staleAfter = Duration(hours: 24);

/// «لسه ما اتأكدتش» بالذهبي — مش «فاتت» ولا أحمر. قرار «فاتت» بتاع
/// المرحلة الرابعة بمهلتها. ومفيش هنا ولا سطر جدولة — الأوقات كلها من
/// اللي جهاز الأب كتبه.
class CaregiverScreen extends StatefulWidget {
  const CaregiverScreen({required this.remote, this.now, this.onNotLinked, super.key});

  final CaregiverRemote remote;

  /// D4: الشاشة دي بقت الصفحة الرئيسية للابن. لو السحابة ردّت «مفيش مريض
  /// مربوط» (ربط فشل وقفل التطبيق)، الجذر بيرجّعه لشاشة البداية بدل ما يفضل
  /// واقف على شاشة فاضية. أوفلاين **مش** «مش مربوط» — ده بيطلع استثناء
  /// والجملة الموجودة بتتقال.
  final VoidCallback? onNotLinked;

  /// للاختبارات.
  final DateTime? now;

  @override
  State<CaregiverScreen> createState() => _CaregiverScreenState();
}

class _CaregiverScreenState extends State<CaregiverScreen>
    with WidgetsBindingObserver {
  CaregiverSnapshot? _snapshot;
  String? _error;
  bool _loading = true;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// رجوع للمقدمة = تحديث — زي ما هو بيعمل لما بيفتح يطمّن.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = _snapshot == null;
      _error = null;
    });
    try {
      final snapshot = await widget.remote.snapshot();
      if (snapshot == null && widget.onNotLinked != null) {
        if (mounted) widget.onNotLinked!();
        return;
      }
      if (mounted) {
        setState(() {
          _snapshot = snapshot ?? _snapshot;
          _loading = false;
          if (snapshot == null) _error = 'مفيش ربط شغّال دلوقتي.';
        });
      }
    } on CareCircleException catch (e) {
      // البيانات القديمة بتفضل معروضة — الجملة فوقها بتقول إنها قديمة
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'مقدرناش نكمّل. جرّب تاني.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;

    return Scaffold(
      appBar: AppBar(
        title: Text(snapshot == null ? 'المتابعة' : 'متابعة ${snapshot.patient.name}'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: F.green,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(F.gap),
            children: [
              if (_error != null) ...[
                _Panel(text: _error!),
                const SizedBox(height: F.gap),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator(color: F.green)),
                )
              else if (snapshot != null) ...[
                // سجل اللي السيرفر عمله — فوق كل حاجة، ومن غير أي بطاقة
                // «مفيش تنبيهات»: السكوت هنا خبر كويس. اللي لسه مفتوح
                // (ذهبي) فوق، واللي اتحلّ تحته — بصّة واحدة تقول إيه
                // اللي لسه محتاجه. جوّه كل مجموعة الأحدث الأول.
                for (final alert in snapshot.alerts)
                  if (!alert.takenLater) _AlertCard(alert: alert, when: _when),
                for (final alert in snapshot.alerts)
                  if (alert.takenLater) _AlertCard(alert: alert, when: _when),
                _WeekStrip(events: snapshot.events, now: _now),
                const SizedBox(height: F.gap),
                const Text(
                  'النهارده',
                  style: TextStyle(
                    fontSize: F.minBodySize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                  ),
                ),
                const SizedBox(height: 8),
                ..._todayList(snapshot),
                const SizedBox(height: F.gap),
                // أدويته وقواعدها — للقراية بس. مفيش «عدّل» ولا «وقّف»: أي
                // زرار بيغيّر بيانات الأب مش موجود هنا خالص، مش متعطّل.
                const Text(
                  'أدويته',
                  style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
                ),
                const SizedBox(height: 8),
                if (snapshot.medications.isEmpty)
                  const _Panel(text: 'مفيش أدوية متسجّلة على موبايل والدك لسه.')
                else
                  for (final m in snapshot.medications) _MedicationRow(medication: m),
                const SizedBox(height: F.gap),
                if (snapshot.lastUpdated != null)
                  () {
                    // تحديث بيانات — مش «آخر ظهور»: مفيش دليل إن الموبايل
                    // عايش، بس إن حاجة اتغيّرت ووصلت.
                    //
                    // عدّى يوم من غير ما يوصل حاجة؟ يبقى ده بالظبط اللي
                    // الابن المفروض يبص له: السحابة بقت قديمة، والتصعيد
                    // بيشتغل على صفوف قديمة أو ما بيشتغلش. الذهبي معناه
                    // «ده محتاج انتباهك دلوقتي» — ومش محتاج معنى تاني هنا.
                    final stale = _now.difference(snapshot.lastUpdated!) > staleAfter;
                    return Text(
                      stale
                          ? 'آخر تحديث من موبايل والدك: '
                              '${_when(snapshot.lastUpdated!)} — عدّى يوم من غير جديد. '
                              'اطمن عليه.'
                          : 'آخر تحديث من موبايل والدك: ${_when(snapshot.lastUpdated!)}',
                      style: TextStyle(
                        fontSize: F.minTextSize,
                        color: stale ? F.gold : F.muted,
                        fontWeight: stale ? FontWeight.w600 : FontWeight.w400,
                        height: 1.6,
                      ),
                    );
                  }(),
              ] else
                const _Panel(
                  text: 'لسه مفيش حاجة وصلت من موبايل والدك. '
                      'أول ما يفتح التطبيق وهو متوصّل بالنت، هتلاقي كل حاجة هنا.',
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _todayList(CaregiverSnapshot snapshot) {
    final today = DateTime(_now.year, _now.month, _now.day);
    final todays = [
      for (final e in snapshot.events)
        if (DateTime(e.scheduledAt.year, e.scheduledAt.month, e.scheduledAt.day) ==
            today)
          e,
    ];
    if (todays.isEmpty) {
      return const [
        _Panel(text: 'مفيش جرعات متسجّلة النهارده لسه.'),
      ];
    }
    return [for (final e in todays) _DoseRow(event: e, now: _now)];
  }

  String _when(DateTime t) {
    final today = DateTime(_now.year, _now.month, _now.day);
    final day = DateTime(t.year, t.month, t.day);
    if (day == today) return 'النهارده ${arabicTime(t)}';
    if (day == today.subtract(const Duration(days: 1))) {
      return 'امبارح ${arabicTime(t)}';
    }
    return 'يوم ${arabicNumber(t.day)}-${arabicNumber(t.month)} الساعة ${arabicTime(t)}';
  }
}

/// شريط الأسبوع: لكل يوم «اتأكد س من ص» — عدّ، مش حكم.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.events, required this.now});

  final List<CaregiverDoseEvent> events;
  final DateTime now;

  static const _dayNames = ['الاتنين', 'التلات', 'الأربع', 'الخميس', 'الجمعة', 'السبت', 'الحد'];

  @override
  Widget build(BuildContext context) {
    final today = DateTime(now.year, now.month, now.day);
    final days = [for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i))];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(F.radiusCard),
        border: Border.all(color: F.line),
      ),
      child: Row(
        children: [
          for (final day in days)
            Expanded(child: _dayCell(day, today)),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime day, DateTime today) {
    final dayEvents = [
      for (final e in events)
        if (DateTime(e.scheduledAt.year, e.scheduledAt.month, e.scheduledAt.day) == day) e,
    ];
    final confirmed = dayEvents.where((e) => e.confirmed).length;
    final pastUnconfirmed = dayEvents.any(
      (e) => !e.confirmed && e.scheduledAt.isBefore(now),
    );
    final isToday = day == today;

    return Column(
      children: [
        // سبع خانات في عرض موبايل: «الخميس» كانت بتتكسر سطرين — سطر واحد
        // بيصغر بس لو ما دخلش، زي شريط التبويبات
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _dayNames[day.weekday - 1],
            maxLines: 1,
            style: TextStyle(
              fontSize: F.minTextSize,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
              // الذهبي = «إنت هنا» — نفس معناه في التطبيق كله
              color: isToday ? F.gold : F.muted,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          dayEvents.isEmpty
              ? '—'
              : '${arabicNumber(confirmed)}/${arabicNumber(dayEvents.length)}',
          style: TextStyle(
            fontSize: F.minTextSize,
            fontWeight: FontWeight.w700,
            color: pastUnconfirmed ? F.gold : F.greenDeep,
          ),
        ),
      ],
    );
  }
}

class _MedicationRow extends StatelessWidget {
  const _MedicationRow({required this.medication});

  final CaregiverMedication medication;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(F.gap),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(F.radius),
          border: Border.all(color: F.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              medication.name,
              style: const TextStyle(
                fontSize: F.minBodySize,
                fontWeight: FontWeight.w700,
                color: F.ink,
                fontFamily: F.monoFamily,
                fontFamilyFallback: F.monoFallback,
                height: 1.4,
              ),
            ),
            if (medication.amountLabel != null || medication.rules.isNotEmpty)
              Text(
                [?medication.amountLabel, ...medication.rules].join(' · '),
                style: const TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
              ),
          ],
        ),
      );
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({required this.event, required this.now});

  final CaregiverDoseEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    // الحالة بالحرف زي ما جهاز الأب كتبها — بنترجم للعربي، مش بنحكم
    final (label, colour) = switch (event.state) {
      'taken' => ('اتاخد ${event.actedAt == null ? '' : arabicTime(event.actedAt!)}', F.greenDeep),
      'skipped' => ('قال مش هياخده', F.muted),
      // جهاز الأب هو اللي قال «اتنست» بعد المهلة — إحنا بننقل، مش بنحكم
      'missed' => ('اتنست — لسه ما اتأكدتش', F.gold),
      _ when event.scheduledAt.isBefore(now) => ('لسه ما اتأكدتش', F.gold),
      _ => ('جاي ${arabicTime(event.scheduledAt)}', F.muted),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(F.gap),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(F.radius),
        border: Border.all(
          color: colour == F.gold ? F.gold : F.line,
          width: colour == F.gold ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.amountLabel == null
                      ? event.medicationName
                      : '${event.medicationName} — ${event.amountLabel}',
                  style: const TextStyle(
                    fontSize: F.minBodySize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                    fontFamily: F.monoFamily,
                    fontFamilyFallback: F.monoFallback,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  arabicTime(event.scheduledAt),
                  style: const TextStyle(fontSize: F.minTextSize, color: F.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label.trim(),
            style: TextStyle(
              fontSize: F.minTextSize,
              fontWeight: FontWeight.w700,
              color: colour,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// تنبيه السيرفر زي ما حصل. البطاقة ما بتتمسحش لما الأب يأكّد بعدين —
/// التنبيه حصل فعلاً، والنتيجة سطر زيادة (القاعدة ٥: التصحيح عرض صحيح،
/// مش حذف). الذهبي بس طول ما الجرعة لسه محتاجة انتباه؛ لما تتاخد بيهدى.
class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.when});

  final CaregiverAlert alert;
  final String Function(DateTime) when;

  @override
  Widget build(BuildContext context) {
    final attention = !alert.takenLater;
    // «بلّغك» بس لما FCM قبل الرسالة فعلاً. no_token مش فشل: السيرفر قرّر
    // وسجّل، والبطاقة دي هي التبليغ — قناة الجهاز بس لسه ما اتفعّلتش.
    // failed فشل حقيقي وبيتقال كده.
    final line = switch (alert.deliveryStatus) {
      'sent' when alert.sentAt != null => 'السيرفر بلّغك ${when(alert.sentAt!)}',
      'no_token' => 'تنبيه داخل التطبيق — إشعار الجهاز محتاج تفعيل',
      _ => 'السيرفر حاول يبلّغك ${when(alert.createdAt)} — الإشعار ما وصلش',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: F.gap),
      padding: const EdgeInsets.all(F.gap),
      // المحلولة بتتراجع: عاجي من غير إطار، عنوان رمادي — نفس المقاسات،
      // لأن الحد الأدنى للخط حد، مش اقتراح. الذهبي هو الوحيد اللي بيبرز.
      decoration: BoxDecoration(
        color: attention ? Colors.white : F.ivory,
        borderRadius: BorderRadius.circular(F.radius),
        border: attention ? Border.all(color: F.gold, width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '⚠ والدك ما أكّدش جرعة ${alert.medicationName} '
            'الساعة ${arabicTime(alert.scheduledAt)}',
            style: TextStyle(
              fontSize: F.minBodySize,
              fontWeight: attention ? FontWeight.w700 : FontWeight.w500,
              color: attention ? F.gold : F.muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            line,
            style: const TextStyle(
              fontSize: F.minTextSize,
              color: F.muted,
              height: 1.5,
            ),
          ),
          if (alert.takenLater) ...[
            const SizedBox(height: 4),
            const Text(
              'أكّدها بعدين ✓',
              style: TextStyle(
                fontSize: F.minTextSize,
                fontWeight: FontWeight.w700,
                color: F.greenDeep,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(F.s14),
        decoration: BoxDecoration(
          color: F.ivoryWarm,
          borderRadius: BorderRadius.circular(F.radiusCard),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6),
        ),
      );
}
