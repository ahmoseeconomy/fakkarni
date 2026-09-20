import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/care/caregiver_remote.dart';
import 'caregiver_snapshot_holder.dart';
import 'caregiver_words.dart';

// السؤال الدوري وشرطه عايشين في CaregiverSnapshotHolder (صورة واحدة للتبويبين).
export 'caregiver_snapshot_holder.dart' show refreshEvery;

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
  const CaregiverScreen({
    required this.remote,
    this.now,
    this.onNotLinked,
    this.active = true,
    this.holder,
    super.key,
  });

  final CaregiverRemote remote;

  /// D4: الشاشة دي بقت الصفحة الرئيسية للابن. لو السحابة ردّت «مفيش مريض
  /// مربوط» (ربط فشل وقفل التطبيق)، الجذر بيرجّعه لشاشة البداية بدل ما يفضل
  /// واقف على شاشة فاضية. أوفلاين **مش** «مش مربوط» — ده بيطلع استثناء
  /// والجملة الموجودة بتتقال.
  final VoidCallback? onNotLinked;

  /// للاختبارات.
  final DateTime? now;

  /// التبويب ده قدام عينه؟ بيتقرا بس لما الشاشة ماسكة صورتها لوحدها (من
  /// شاشة الربط). في `CaregiverShell` الشِل هو اللي بيقرر من [holder].
  final bool active;

  /// صورة الشِل المشتركة (D5.2). null = الشاشة بتعمل صورتها بنفسها.
  final CaregiverSnapshotHolder? holder;

  @override
  State<CaregiverScreen> createState() => _CaregiverScreenState();
}

class _CaregiverScreenState extends State<CaregiverScreen> {
  CaregiverSnapshotHolder? _own;

  CaregiverSnapshotHolder get _holder => widget.holder ?? _own!;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.holder == null) {
      _own = CaregiverSnapshotHolder(widget.remote, onNotLinked: widget.onNotLinked)..setActive(widget.active);
    }
    _holder.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(CaregiverScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.holder != widget.holder) {
      (oldWidget.holder ?? _own)?.removeListener(_changed);
      _holder.addListener(_changed);
    }
    if (widget.holder == null && oldWidget.active != widget.active) _own!.setActive(widget.active);
  }

  @override
  void dispose() {
    _holder.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _holder.snapshot;
    final error = _holder.error;

    return Scaffold(
      appBar: AppBar(
        title: Text(snapshot == null ? 'المتابعة' : 'متابعة ${snapshot.patient.name}'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: F.green,
          onRefresh: _holder.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(F.gap, F.gap, F.gap, F.gap + MediaQuery.of(context).padding.bottom),
            children: [
              if (error != null) ...[
                _Panel(text: error),
                const SizedBox(height: F.gap),
              ],
              if (_holder.loading)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator(color: F.green)),
                )
              else if (snapshot != null) ...[
                // **قسم لكل فكرة، وكل قسم بعنوانه.** الابن بيفتح الشاشة دي
                // عشان يجاوب «هو كويس؟» — فجرعات اليوم وحالتها قسم قائم
                // بذاته، مش ذيل قايمة، والأدوية قسم تاني وراه مباشرةً بدل
                // ما تكون آخر حاجة تحت.
                //
                // التنبيهات فاضلة فوق عن قصد: تنبيه مفتوح معناه جرعة
                // فايتة **دلوقتي**، ودي أعجل من أي حاجة تانية على الشاشة.
                // واللي خفّف الزحمة إن الجرعة المقفولة مابقاش ليها بطاقة
                // أصلاً (بتتفلتر من الاستعلام).
                // العنوان بيتحسب من **المفتوحة**، مش من طول القايمة: صف
                // مقفول عدّى (صف قديم، أو حالة مش معروفة) كان هيسيب عنوان
                // قسم فوق فراغ. خط الدفاع التاني ده جنب الفلتر اللي في
                // السحابة — الاتنين بيقولوا نفس الحاجة.
                if (snapshot.alerts.where((a) => a.open).toList() case final open
                    when open.isNotEmpty) ...[
                  const FSectionHead('تنبيهات'),
                  for (final alert in open) _AlertCard(alert: alert, when: _when),
                ],
                const FSectionHead('آخر أسبوع'),
                _WeekStrip(events: snapshot.events, now: _now),
                const SizedBox(height: F.gap),
                // «جرعات النهارده» مش «النهارده» وبس: صف النهارده في لوحة
                // الأسبوع فوق بيقول «النهارده» كمان، وكلمة واحدة لحاجتين
                // على نفس الشاشة بتلغبط.
                const FSectionHead('جرعات النهارده'),
                ..._todayList(snapshot),
                const SizedBox(height: F.gap),
                // «الجديد» (D5.2): تحت اللي بيجاوب «هو كويس؟» — تحليل اتضاف
                // مش أعجل من جرعة النهارده. مترتب بالوصول، وكل سطر بتاريخه.
                ..._newest(snapshot),
                // أدويته وقواعدها — **آخر قسم**: دي مرجع («هو بياخد إيه»)
                // مش حالة («هو كويس النهارده؟»). كانت واقفة بين النهارده
                // و«الجديد»، فبتفصل السؤال عن إجابته.
                // للقراية بس: مفيش «عدّل» ولا «وقّف» — أي زرار بيغيّر بيانات
                // الأب مش موجود هنا خالص، مش متعطّل.
                const FSectionHead('أدويته'),
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
                        color: stale ? F.gold : F.mutedDark,
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

  List<Widget> _newest(CaregiverSnapshot snapshot) {
    final items = newestArrivals(snapshot);
    if (items.isEmpty) return const [];
    return [
      const FSectionHead('الجديد'),
      Container(
        key: const ValueKey('newest'),
        margin: const EdgeInsets.only(bottom: F.gap),
        padding: const EdgeInsets.symmetric(horizontal: F.gap, vertical: F.s8),
        decoration: BoxDecoration(
          color: F.cardGround,
          borderRadius: BorderRadius.circular(F.radius),
          border: Border.all(color: F.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, item) in items.indexed) ...[
              if (i > 0) Divider(height: F.s12, color: F.lineSoft),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: F.s4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      newItemTitle(item),
                      style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.4),
                    ),
                    Text(
                      arabicDate(item.happenedAt),
                      style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  List<Widget> _todayList(CaregiverSnapshot snapshot) {
    final today = DateTime(_now.year, _now.month, _now.day);
    final todays = [
      for (final e in snapshot.events)
        if (DateTime(e.scheduledAt.year, e.scheduledAt.month, e.scheduledAt.day) ==
            today)
          e,
    ];
    if (todays.isNotEmpty) return [for (final e in todays) _DoseRow(event: e, now: _now)];

    // أب ظبّط أدويته بالليل: النهارده فاضي وبكرة مليان. «مفيش حاجة» كانت
    // هتبقى صح بالحرف وغلط في المعنى — نقول اللي جاي. جهاز الأب بينزّل بكرة
    // مقدماً (rescheduleAll)، فالصفوف دي في الصورة أصلاً؛ مفيش سحبة زيادة.
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final tomorrows = [
      for (final e in snapshot.events)
        if (DateTime(e.scheduledAt.year, e.scheduledAt.month, e.scheduledAt.day) == tomorrow) e,
    ]..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    if (tomorrows.isEmpty) {
      return const [_Panel(text: 'مفيش جرعات متسجّلة النهارده لسه.')];
    }
    return [
      _Panel(
        key: const ValueKey('tomorrow-first'),
        text: 'مفيش جرعات النهارده — أول جرعة بكرة الساعة ${spokenTime(tomorrows.first.scheduledAt)}',
      ),
      const SizedBox(height: 8),
      for (final e in tomorrows) _DoseRow(event: e, now: _now, tomorrow: true),
    ];
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
    final days = [for (var i = 6; i >= 0; i--) DateTime(today.year, today.month, today.day - i)];

    // سبع شَرطات بتتقري تطبيق بايظ حتى لو هي الحقيقة — جملة واحدة بتقول ليه.
    final anything = events.any((e) {
      final d = DateTime(e.scheduledAt.year, e.scheduledAt.month, e.scheduledAt.day);
      return !d.isBefore(days.first) && !d.isAfter(today);
    });
    if (!anything) {
      return Container(
        key: const ValueKey('week-empty'),
        width: double.infinity,
        padding: const EdgeInsets.all(F.gap),
        decoration: BoxDecoration(
          color: F.cardGround,
          borderRadius: BorderRadius.circular(F.radiusCard),
          border: Border.all(color: F.line),
        ),
        child: Text(
          'لسه بدري. أول جرعة هتبان هنا أول ما تتسجّل',
          style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5),
        ),
      );
    }

    return Container(
      key: const ValueKey('week-strip'),
      padding: const EdgeInsets.symmetric(vertical: F.s8, horizontal: F.gap),
      decoration: BoxDecoration(
        color: F.cardGround,
        borderRadius: BorderRadius.circular(F.radiusCard),
        border: Border.all(color: F.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final day in days) _dayRow(day, today)],
      ),
    );
  }

  /// يوم واحد **في سطر**، مكتوب بالكلام.
  ///
  /// كان سبع أعمدة فيها «٤/١٦» و«—». الكسر ده محدش بيعرف يقراه: أربعة من
  /// إيه؟ والشَرطة معناها مفيش جرعات ولا مفيش بيانات؟ سبع خانات في عرض
  /// موبايل مفيهاش مكان لجملة، فالشكل اتغيّر للسطر — والسطر فيه مكان
  /// للكلمة كاملة. ده مش لغة بصرية جديدة: هو نفس صف القايمة اللي في
  /// التطبيق كله.
  Widget _dayRow(DateTime day, DateTime today) {
    final dayEvents = [
      for (final e in events)
        if (DateTime(e.scheduledAt.year, e.scheduledAt.month, e.scheduledAt.day) == day) e,
    ];
    final confirmed = dayEvents.where((e) => e.confirmed).length;
    final pastUnconfirmed = dayEvents.any((e) => !e.confirmed && e.scheduledAt.isBefore(now));
    final isToday = day == today;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: F.s6),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              isToday ? 'النهارده' : _dayNames[day.weekday - 1],
              maxLines: 1,
              style: TextStyle(
                fontSize: F.minTextSize,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                // الذهبي = «إنت هنا» — نفس معناه في التطبيق كله
                color: isToday ? F.gold : F.mutedDark,
              ),
            ),
          ),
          Expanded(
            child: Text(
              // **مفيش بيانات ≠ مفيش جرعات.** الشَرطة كانت بتخلط الاتنين،
              // والابن يفتكر إن أبوه ما خدش حاجة وهو أصلاً ما وصلش خبر.
              dayEvents.isEmpty
                  ? 'مفيش بيانات'
                  : '${arabicNumber(confirmed)} من ${arabicNumber(dayEvents.length)} اتأكدت',
              style: TextStyle(
                fontSize: F.minTextSize,
                fontWeight: dayEvents.isEmpty ? FontWeight.w400 : FontWeight.w700,
                color: dayEvents.isEmpty
                    ? F.mutedDark
                    : pastUnconfirmed
                        ? F.gold
                        : F.greenDeep,
              ),
            ),
          ),
        ],
      ),
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
          color: F.cardGround,
          borderRadius: BorderRadius.circular(F.radius),
          border: Border.all(color: F.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              medication.name,
              style: TextStyle(
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
                [?medication.amountLabel, ...medication.rules].join(' — '),
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
              ),
          ],
        ),
      );
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({required this.event, required this.now, this.tomorrow = false});

  /// جرعة بكرة — الوقت بيتكتب «بكرة …» عشان محدش يفتكرها النهارده.
  final bool tomorrow;

  final CaregiverDoseEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    // الحالة بالحرف زي ما جهاز الأب كتبها — بنترجم للعربي، مش بنحكم
    final (label, colour) = switch (event.state) {
      'taken' => ('اتاخد ${event.actedAt == null ? '' : arabicTime(event.actedAt!)}', F.greenDeep),
      'skipped' => ('قال مش هياخده', F.mutedDark),
      // جهاز الأب هو اللي قال «اتنست» بعد المهلة — إحنا بننقل، مش بنحكم
      'missed' => ('اتنست — لسه ما اتأكدتش', F.gold),
      _ when event.scheduledAt.isBefore(now) => ('لسه ما اتأكدتش', F.gold),
      _ => ('جاي ${arabicTime(event.scheduledAt)}', F.mutedDark),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(F.gap),
      decoration: BoxDecoration(
        color: F.cardGround,
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
                  style: TextStyle(
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
                  tomorrow ? 'بكرة ${arabicTime(event.scheduledAt)}' : arabicTime(event.scheduledAt),
                  style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
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

/// تنبيه السيرفر عن جرعة **لسه مفتوحة**.
///
/// جولة ٤.٢ج كانت بتسيب البطاقة بعد ما الأب يأكّد وتزوّد «أكّدها بعدين ✓»
/// — «التنبيه حصل، والنتيجة سطر زيادة». ده اتغيّر (جولة ٢٦) بقرار صاحب
/// المنتج، والسبب أقوى من الاتساق: عنوان البطاقة بيقول «والدك ما أكّدش
/// جرعة …»، وده بيفضل مكتوب بالبنط العريض فوق جرعة **اتاخدت**. الابن
/// بيقرا الجملة، مش الـ✓ اللي تحتها؛ ولما يكتشف إنها مش صح بيبطّل يقرا
/// التنبيهات كلها. الجرعة المقفولة بتتفلتر من الاستعلام نفسه، فالبطاقة
/// دي دايماً مفتوحة ودايماً ذهبية.
class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.when});

  final CaregiverAlert alert;
  final String Function(DateTime) when;

  @override
  Widget build(BuildContext context) {
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
      decoration: BoxDecoration(
        color: F.cardGround,
        borderRadius: BorderRadius.circular(F.radius),
        border: Border.all(color: F.gold, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '⚠ والدك ما أكّدش جرعة ${alert.medicationName} '
            'الساعة ${arabicTime(alert.scheduledAt)}',
            style: TextStyle(
              fontSize: F.minBodySize,
              fontWeight: FontWeight.w700,
              color: F.gold,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            line,
            style: TextStyle(
              fontSize: F.minTextSize,
              color: F.mutedDark,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(F.s14),
        decoration: BoxDecoration(
          color: F.railGround,
          borderRadius: BorderRadius.circular(F.radiusCard),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6),
        ),
      );
}
