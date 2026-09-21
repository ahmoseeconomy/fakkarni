import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/dark_mode_toggle.dart';
import '../../data/care/caregiver_remote.dart';
import 'caregiver_status.dart';
import 'caregiver_ui.dart';
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

    final status = snapshot == null ? null : careStatus(snapshot, _now);

    return Scaffold(
      appBar: careAppBar(
        snapshot == null ? 'المتابعة' : 'متابعة ${snapshot.patient.name}',
        // نفس مفتاح الأب بالظبط — **مفيش آلية تانية ولا مفتاح تخزين
        // تاني**: إعداد واحد للموبايل ده، أي دور اشتغل عليه.
        actions: const [DarkModeToggle()],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: F.green,
          onRefresh: _holder.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              F.carePad,
              F.careRowGap,
              F.carePad,
              F.carePad + MediaQuery.of(context).padding.bottom,
            ),
            children: [
              // **الخطأ فوق خالص، ومعاه إعادة السؤال.** «حاول تاني» مش
              // قدرة جديدة — هو نفس السحب اللي في الشاشة أصلاً.
              if (error != null)
                CarePanel(text: error, action: 'حاول تاني', onAction: _holder.refresh),
              if (_holder.loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator(color: F.green)),
                )
              else if (snapshot != null && status != null) ...[
                // ١ — **الإجابة الأول.** الابن بيفتح الشاشة عشان سؤال
                // واحد، فأول حاجة يشوفها هي الرد عليه: كله تمام، ولا فيه
                // حاجة محتاجاه. وتحتها آخر جرعة مؤكَّدة وإمتى — دي اللي
                // بتخلّي «تمام» تبقى مصدّقة بدل ما تبقى كلمة.
                _StatusCard(status: status, when: _when),
                // ٢ — التنبيهات المفتوحة. تنبيه مفتوح معناه جرعة فايتة
                // **دلوقتي**، وده أعجل من أي حاجة تانية على الشاشة.
                if (snapshot.alerts.where((a) => a.open).toList() case final open
                    when open.isNotEmpty) ...[
                  const CareHead('تنبيهات'),
                  for (final alert in open) _AlertCard(alert: alert, when: _when),
                ],
                // ٣ — يوم النهارده في سطور مضغوطة.
                // «جرعات النهارده» مش «النهارده» وبس: كلمة واحدة لحاجتين
                // على نفس الشاشة بتلغبط.
                const CareHead('جرعات النهارده'),
                ..._todayList(snapshot),
                // ٤ — الأسبوع في سطر واحد. الشبكة القديمة كانت سبع أعمدة
                // كسور، والابن مكانش بيقرا منها حاجة (جولة ٣٠ شالتها).
                ..._week(status),
                // ٥ — «الجديد»: تحليل اتضاف مش أعجل من جرعة النهارده.
                ..._newest(snapshot),
                if (snapshot.lastUpdated != null) _freshness(snapshot.lastUpdated!),
              ] else
                const CarePanel(
                  text: 'لسه مفيش حاجة وصلت من موبايل والدك. '
                      'أول ما يفتح التطبيق وهو متوصّل بالنت، هتلاقي كل حاجة هنا.',
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// **سطر الثقة.** الابن لازم يقدر يصدّق اللي قدامه، فبيشوف آخر مرة وصل
  /// فيها جديد من موبايل الأب — ومعاه «حدّث» بدل ما يفضل يسحب ويستنى.
  ///
  /// تحديث بيانات — مش «آخر ظهور»: مفيش دليل إن الموبايل عايش، بس إن حاجة
  /// اتغيّرت ووصلت. وعدّى يوم من غير ما يوصل حاجة؟ ده بالظبط اللي المفروض
  /// يبص له: السحابة بقت قديمة، والتصعيد بيشتغل على صفوف قديمة أو ما
  /// بيشتغلش. الذهبي معناه «ده محتاج انتباهك دلوقتي».
  Widget _freshness(DateTime at) {
    final stale = _now.difference(at) > staleAfter;
    return Padding(
      padding: const EdgeInsets.only(top: F.s6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              stale
                  ? 'آخر تحديث من موبايل والدك: ${_when(at)} — عدّى يوم من غير جديد. اطمن عليه.'
                  : 'آخر تحديث من موبايل والدك: ${_when(at)}',
              style: TextStyle(
                fontSize: F.careMicroSize,
                color: stale ? F.gold : F.mutedDark,
                fontWeight: stale ? FontWeight.w700 : FontWeight.w400,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(width: F.s8),
          CareTextAction(label: 'حدّث', icon: Icons.refresh, onPressed: _holder.refresh),
        ],
      ),
    );
  }

  /// **الأسبوع في سطر يتقرا بنظرة** — «٦ من ٧ أيام كل الجرعات اتقفلت».
  ///
  /// الشبكة القديمة كانت سبع خانات فيها كسور و«—»، والكسر مكانش بيقول
  /// لحد حاجة، والشرطة كانت بتخلط «مفيش جرعات» بـ«مفيش خبر». المالك
  /// شالها في جولة ٣٠. الرجوع بقى **رقم واحد بجملته**، ومن غير أي رسم:
  /// سبع نقط مش بيانات تستاهل رسمة، والجملة أسرع في القراية من أي شكل.
  ///
  /// و«النهارده» **مش** محسوب: اليوم لسه ماشي، وعدّه ناقص بيخلّي كل يوم
  /// يبان مش كامل لحد آخره. مفيش أيام فيها جرعات؟ مفيش سطر خالص.
  List<Widget> _week(CareStatus status) {
    if (status.daysWithDoses == 0) return const [];
    return [
      const CareHead('آخر أسبوع'),
      CareCard(
        key: const ValueKey('care-week'),
        child: Row(
          children: [
            Icon(
              status.completeDays == status.daysWithDoses
                  ? Icons.check_circle_outline
                  : Icons.calendar_today_outlined,
              size: 18,
              color: status.completeDays == status.daysWithDoses ? F.green : F.mutedDark,
            ),
            const SizedBox(width: F.s8),
            Expanded(
              child: Text(
                '${arabicNumber(status.completeDays)} من '
                '${arabicNumber(status.daysWithDoses)} أيام كل الجرعات فيها اتقفلت',
                style: TextStyle(fontSize: F.careTextSize, color: F.ink, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _newest(CaregiverSnapshot snapshot) {
    final items = newestArrivals(snapshot);
    if (items.isEmpty) return const [];
    return [
      const CareHead('الجديد'),
      CareCard(
        key: const ValueKey('newest'),
        padding: const EdgeInsets.symmetric(horizontal: F.carePad, vertical: F.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, item) in items.indexed) ...[
              if (i > 0) Divider(height: F.s10, color: F.lineSoft),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: F.s6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      newItemTitle(item),
                      style: TextStyle(fontSize: F.careTextSize, color: F.ink, height: 1.4),
                    ),
                    Text(
                      arabicDate(item.happenedAt),
                      style: TextStyle(fontSize: F.careMicroSize, color: F.mutedDark),
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
      return const [CarePanel(text: 'مفيش جرعات متسجّلة النهارده لسه.')];
    }
    return [
      CarePanel(
        key: const ValueKey('tomorrow-first'),
        text: 'مفيش جرعات النهارده — أول جرعة بكرة الساعة ${spokenTime(tomorrows.first.scheduledAt)}',
      ),
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
class CaregiverMedicationRow extends StatelessWidget {
  const CaregiverMedicationRow({required this.medication, super.key});

  final CaregiverMedication medication;

  @override
  Widget build(BuildContext context) => CareCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              medication.name,
              style: TextStyle(
                fontSize: F.careBodySize,
                fontWeight: FontWeight.w700,
                color: F.ink,
                fontFamily: F.monoFamily,
                fontFamilyFallback: F.monoFallback,
                height: 1.3,
              ),
            ),
            if (medication.amountLabel != null || medication.rules.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: F.s4),
                child: Text(
                  [?medication.amountLabel, ...medication.rules].join(' — '),
                  style: TextStyle(fontSize: F.careTextSize, color: F.mutedDark, height: 1.4),
                ),
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
    final look = doseLook(event, now);
    final label = switch (event.state) {
      'taken' => 'اتاخد ${event.actedAt == null ? '' : arabicTime(event.actedAt!)}',
      'skipped' => 'قال مش هياخده',
      // جهاز الأب هو اللي قال «اتنست» بعد المهلة — إحنا بننقل، مش بنحكم
      'missed' => 'اتنست — لسه ما اتأكدتش',
      _ when event.scheduledAt.isBefore(now) => 'لسه ما اتأكدتش',
      _ => 'جاي ${arabicTime(event.scheduledAt)}',
    };

    return CareCard(
      edge: look == DoseLook.unconfirmed ? F.gold : null,
      padding: const EdgeInsets.symmetric(horizontal: F.carePad, vertical: F.s10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: F.careTapTarget - 2 * F.s10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 64,
              child: Text(
                tomorrow ? 'بكرة ${arabicTime(event.scheduledAt)}' : arabicTime(event.scheduledAt),
                style: TextStyle(
                  fontSize: F.careMicroSize,
                  fontWeight: FontWeight.w700,
                  color: F.mutedDark,
                  height: 1.3,
                ),
              ),
            ),
            Expanded(
              child: Text(
                event.amountLabel == null
                    ? event.medicationName
                    : '${event.medicationName} — ${event.amountLabel}',
                style: TextStyle(
                  fontSize: F.careBodySize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                  fontFamily: F.monoFamily,
                  fontFamilyFallback: F.monoFallback,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(width: F.s8),
            CareStateMark(look: look, label: label.trim()),
          ],
        ),
      ),
    );
  }
}

/// **الإجابة على «هو كويس؟» — أول حاجة على الشاشة.**
///
/// سطر واحد بيرد، وتحته آخر جرعة مؤكَّدة وإمتى. الجرعة المؤكَّدة هي اللي
/// بتخلّي «كل حاجة تمام» مصدّقة: الجملة لوحدها ممكن تبقى شاشة واقفة،
/// والوقت جنبها بيقول إن فيه حاجة بتحصل فعلاً.
///
/// **الأيقونة والكلمة هما اللي بيشيلوا المعنى**، واللون تأكيد — نفس قاعدة
/// [CareStateMark].
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.when});

  final CareStatus status;
  final String Function(DateTime) when;

  @override
  Widget build(BuildContext context) {
    final (icon, colour, headline) = switch (status.state) {
      CareState.needsAttention => (
          Icons.error_outline,
          F.gold,
          status.openAlerts > 0
              ? 'فيه ${arabicNumber(status.openAlerts)} محتاجة انتباهك'
              : 'فيه ${arabicNumber(status.unconfirmedToday)} جرعة من غير تأكيد',
        ),
      CareState.allGood => (Icons.check_circle_outline, F.green, 'كل حاجة تمام'),
      CareState.noData => (Icons.cloud_off_outlined, F.mutedDark, 'لسه مفيش خبر النهارده'),
    };

    final last = status.lastTaken;
    final second = last == null
        ? 'لسه مفيش جرعة مؤكَّدة'
        : 'آخر جرعة مؤكَّدة — ${last.medicationName} ${when(last.actedAt ?? last.scheduledAt)}';

    return CareCard(
      key: const ValueKey('care-status'),
      edge: status.state == CareState.needsAttention ? F.gold : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colour),
              const SizedBox(width: F.s8),
              Expanded(
                child: Text(
                  headline,
                  style: TextStyle(
                    fontSize: F.careBodySize,
                    fontWeight: FontWeight.w700,
                    // **النص بلون النص، والعلامة هي اللي بتشيل الحالة.**
                    // ده بيخلّي السطر يقرا في الوضعين من غير ما يتعلّق
                    // بلون واحد، وبيسيب الذهبي لحاجة واحدة على الشاشة.
                    color: F.ink,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: F.s4),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 28),
            child: Text(
              second,
              style: TextStyle(fontSize: F.careTextSize, color: F.mutedDark, height: 1.4),
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

    return CareCard(
      edge: F.gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 18, color: F.gold),
              const SizedBox(width: F.s8),
              Expanded(
                child: Text(
                  'والدك ما أكّدش جرعة ${alert.medicationName} '
                  'الساعة ${arabicTime(alert.scheduledAt)}',
                  style: TextStyle(
                    fontSize: F.careBodySize,
                    fontWeight: FontWeight.w700,
                    // **النص بلون النص، والذهبي في العلامة والحد.**
                    // العنوان كان ذهبي — ٢٫٠٦:١ على كارت نهاري، يعني أهم
                    // سطر على الشاشة كان أصعب سطر يتقرا. الانتباه دلوقتي
                    // محمول على الأيقونة والحد الجانبي وعنوان القسم، وهي
                    // تلاتة بتشتغل لحد مش بيفرّق الألوان كمان.
                    color: F.ink,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: F.s4),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 26),
            child: Text(
              line,
              style: TextStyle(fontSize: F.careMicroSize, color: F.mutedDark, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class CaregiverPanel extends StatelessWidget {
  const CaregiverPanel({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => CarePanel(text: text);
}
