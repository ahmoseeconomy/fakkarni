import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/dark_mode_toggle.dart';
import '../../data/care/caregiver_remote.dart';
import '../../domain/health/follow_display.dart';
import '../../domain/health/follow_up.dart';
import '../../domain/adherence/adherence.dart';
import '../adherence/adherence_dots.dart';
import '../adherence/circle_adherence.dart';
import 'caregiver_status.dart';
import 'caregiver_ui.dart';
import 'caregiver_snapshot_holder.dart';
import 'family_notice_card.dart';
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
                // ٠ — **التنبيهات واقفة (أو هتقف).** فوق الإجابة: «كله
                // تمام» تحت سكوت السيرفر بتبقى كدبة بالسكوت.
                CareFamilyNotice(patientName: snapshot.patient.name, now: _now),
                // ١ — **الإجابة الأول.** الابن بيفتح الشاشة عشان سؤال
                // واحد، فأول حاجة يشوفها هي الرد عليه: كله تمام، ولا فيه
                // حاجة محتاجاه. وتحتها آخر جرعة مؤكَّدة وإمتى — دي اللي
                // بتخلّي «تمام» تبقى مصدّقة بدل ما تبقى كلمة.
                _StatusCard(status: status, when: _when),
                // ٢ — التنبيهات المفتوحة. تنبيه مفتوح معناه جرعة فايتة
                // **دلوقتي**، وده أعجل من أي حاجة تانية على الشاشة.
                if (snapshot.alerts.where((a) => a.open).toList() case final open
                    when open.isNotEmpty) ...[
                  CareHead('تنبيهات', accent: F.careAlertInk),
                  for (final alert in open) _AlertCard(alert: alert, when: _when),
                ],
                // ٣ — المواعيد الجاية. تحت سطر الحالة على طول لما مفيش
                // تنبيه مفتوح — والتنبيه المفتوح بيفضل فوقها، لأنه جرعة
                // بتفوت **دلوقتي** وده قرار مكتوب من جولة ٢٨.
                ..._upcomingSection(snapshot),
                // ٤ — اليوم في أقسام بترتيب طلب المالك: اللي ما اتأكدتش ←
                // جاية ← اتاخدت. **وكل قسم فاضي بيختفي** — سطر الحالة فوق
                // قال خلاص إن كل حاجة تمام، فعنوان فوق فراغ زيادة بتشغل
                // شاشة الهدف منها الكثافة.
                ..._doseSections(snapshot),
                // ٤ — المتابعات: زيارات، وبعدين تحاليل.
                ..._followSections(snapshot),
                // ٥ — الأسبوع في سطر واحد. الشبكة القديمة كانت سبع أعمدة
                // كسور، والابن مكانش بيقرا منها حاجة (جولة ٣٠ شالتها).
                // «ماشي إزاي» — العدّ ونقط الأسبوع (قراية بس). أول يومين
                // لسه مفيش حاجة تتقال، فبيفضل سطر الأسبوع القديم.
                if (circleAdherence(snapshot, _now) case final a?)
                  ..._adherence(a)
                else
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
  List<Widget> _adherence(Adherence a) {
    final missed = a.missed.length;
    return [
      CareHead(circleAdherenceTitle, accent: F.careAccentTaken),
      CareCard(
        key: const ValueKey('care-adherence'),
        border: F.careAccentTaken,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              streakLine(a.currentStreak, atLeast: a.currentAtLeast),
              key: const ValueKey('care-adherence-streak'),
              style: TextStyle(
                fontFamily: F.displayFamily,
                fontSize: F.careTitleSize,
                fontWeight: FontWeight.w800,
                color: a.currentStreak > 0 ? F.green : F.ink,
              ),
            ),
            const SizedBox(height: F.s8),
            AdherenceDots(week: a.week, today: a.today, dotSize: 22, labelSize: F.careMicroSize),
            const SizedBox(height: F.s8),
            Text(takenPercentLine(a.takenPercent),
                style: TextStyle(fontSize: F.careTextSize, color: F.ink, height: 1.4)),
            Text(
              missed == 0
                  ? 'مفيش ولا جرعة فاتت في آخر ٧ أيام.'
                  : missed == 1
                      ? 'جرعة واحدة ما اتأكدتش في آخر ٧ أيام.'
                      : '${arabicNumber(missed)} جرعات ما اتأكدتش في آخر ٧ أيام.',
              style: TextStyle(fontSize: F.careTextSize, color: F.mutedDark, height: 1.4),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _week(CareStatus status) {
    if (status.daysWithDoses == 0) return const [];
    return [
      const CareHead('آخر أسبوع'),
      CareCard(
        key: const ValueKey('care-week'),
        border: status.completeDays == status.daysWithDoses
            ? F.careAccentTaken
            : F.careAccentSkipped,
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
      CareHead('الجديد', count: items.length, accent: F.careAccentSkipped),
      CareCard(
        key: const ValueKey('newest'),
        border: F.careAccentSkipped,
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

  /// **ما اتأكدتش ← جاية ← اتاخدت** — وقسم رابع صغير للي اتخطّى.
  ///
  /// أول قسم فوق خالص لأنه السبب اللي الابن فاتح التطبيق عشانه؛ دفنه بين
  /// «اتاخدت» و«جاية» بيخلّيه يدوّر على اللي جاي يدوّر عليه.
  ///
  /// **والعنوان بعدّاده بين قوسين، مش بنقطة وسطية** — «جاية · ٣» ممنوعة
  /// في التطبيق كله: «٠» العربية *هي* نقطة، فـ«جاية · ٣» بتتقري «جاية ٠٣»
  /// جنب الأرقام العربية. فيه اختبار بيقرا كل نص في `lib/` ويوقع عليها.
  List<Widget> _doseSections(CaregiverSnapshot snapshot) {
    final s = careDoseSections(snapshot, _now);
    final nothingAtAll = s.missed.isEmpty &&
        s.upcomingToday.isEmpty &&
        s.tomorrow.isEmpty &&
        s.taken.isEmpty &&
        s.skipped.isEmpty;
    if (nothingAtAll) {
      return const [CarePanel(text: 'مفيش جرعات متسجّلة النهارده لسه.')];
    }

    final todayEmpty =
        s.missed.isEmpty && s.upcomingToday.isEmpty && s.taken.isEmpty && s.skipped.isEmpty;

    return [
      // **العنوان «ما اتأكدتش» مش «فاتت» — وده الحتة الوحيدة اللي خرجت
      // عن نص المالك في الملحق، عن قصد.** القاعدة المكتوبة في CLAUDE.md:
      // جرعة عدّى وقتها من غير تأكيد بتتقال «لسه ما اتأكدتش» — عمرها ما
      // تبقى «فاتت» ولا حمرا، «إحنا بنبلّغ مش بنحكم». وفيه اختبار بيقرا
      // الشاشة ويوقع على كلمة «فاتت» بالسبب ده مكتوب جواه. وعنوان «فاتت»
      // فوق صف بيقول «لسه ما اتأكدتش» بيناقض نفسه على شاشة واحدة.
      // لو المالك عايز «فاتت» فعلاً، دي كلمة واحدة هنا وسطر في الاختبار.
      if (s.missed.isNotEmpty) ...[
        CareHead('ما اتأكدتش', count: s.missed.length, accent: F.careAccentDue),
        for (final e in s.missed) _DoseRow(event: e, now: _now, accent: F.careAccentDue),
      ],
      if (s.upcomingToday.isNotEmpty || s.tomorrow.isNotEmpty) ...[
        if (s.upcomingToday.isNotEmpty)
          CareHead('جاية', count: s.upcomingToday.length, accent: F.careAccentUpcoming),
        // أب ظبّط أدويته بالليل: النهارده فاضي وبكرة مليان. «مفيش حاجة»
        // كانت هتبقى صح بالحرف وغلط في المعنى — بنقول اللي جاي.
        if (todayEmpty && s.tomorrow.isNotEmpty)
          CarePanel(
            key: const ValueKey('tomorrow-first'),
            text: 'مفيش جرعات النهارده — أول جرعة بكرة الساعة '
                '${spokenTime(s.tomorrow.first.scheduledAt)}',
          ),
        // **مفيش صفوف بكرة** (طلب المالك). الشاشة بقت عن النهارده وبس؛
        // اللي فاضل من بكرة هو الجملة اللي فوق لما النهارده يبقى فاضي —
        // دي بتقول «ليه الشاشة فاضية» مش بتعرض جدول بكرة.
        for (final e in s.upcomingToday)
          _DoseRow(event: e, now: _now, ahead: true, accent: F.careAccentUpcoming),
      ],
      if (s.taken.isNotEmpty) ...[
        CareHead('اتاخدت', count: s.taken.length, accent: F.careAccentTaken),
        for (final e in s.taken) _DoseRow(event: e, now: _now, accent: F.careAccentTaken),
      ],
      if (s.skipped.isNotEmpty) ...[
        CareHead('متخطّية', count: s.skipped.length, accent: F.careAccentSkipped),
        for (final e in s.skipped) _DoseRow(event: e, now: _now, accent: F.careAccentSkipped),
      ],
    ];
  }

  /// **زيارات** و**تحاليل** — المتابعات المفتوحة، كل نوع في قسمه.
  ///
  /// دي قراية لصف الأب زي كل حاجة هنا: المرحلة اللي هو واقف عندها،
  /// وميعادها لو حطّه. **ومفيش حساب من عندنا** — لا بنقول التحليل ياخد
  /// قد إيه ولا بنحكم على تأخير؛ «واقفة من أسبوع» واقعة عن الشاشة،
  /// بنفس الحساب اللي على موبايل الأب بالظبط (`followIsStalled`).
  /// **المواعيد الجاية فوق.** ميعاد قدّام الأب دلوقتي حاجة الابن عايز
  /// يشوفها أول ما يفتح، مش في آخر الشاشة جنب حاجات عدّت. ذهبي لأنه
  /// «ده محتاج انتباهك»، وبنفس العدّ اللي الأب بيشوفه بالحرف.
  List<Widget> _upcomingSection(CaregiverSnapshot snapshot) {
    final upcoming = careUpcoming(careFollowUps(snapshot, _now), _now);
    if (upcoming.isEmpty) return const [];
    return [
      CareHead('مواعيده الجاية', count: upcoming.length, accent: F.gold),
      for (final f in upcoming) _FollowRow(follow: f, now: _now, accent: F.gold),
    ];
  }

  List<Widget> _followSections(CaregiverSnapshot snapshot) {
    // اللي فوق مش بيتعاد هنا — تكرار بيخلّي الواحد يعدّ الميعاد مرتين.
    final all = careRemaining(careFollowUps(snapshot, _now), _now);
    if (all.isEmpty) return const [];
    final visits = [for (final f in all) if (f.kind == FollowKind.visit) f];
    final labs = [for (final f in all) if (f.kind == FollowKind.lab) f];
    return [
      if (visits.isNotEmpty) ...[
        CareHead('زيارات', count: visits.length, accent: F.careAccentVisit),
        for (final f in visits)
          _FollowRow(follow: f, now: _now, accent: F.careAccentVisit),
      ],
      if (labs.isNotEmpty) ...[
        CareHead('تحاليل', count: labs.length, accent: F.careAccentLab),
        for (final f in labs) _FollowRow(follow: f, now: _now, accent: F.careAccentLab),
      ],
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
        // **تبويب واحد، لون واحد.** القايمة دي **مرجع** («هو بياخد إيه»)
        // مش حالة، فمفيش أقسام تتفرّق بينها. ولون لكل دوا كان هيبقى
        // تلوين **بالدور** — اللون بيتغيّر لما دوا يتضاف أو يتوقف، يعني
        // بيدّي معنى مش موجود. الأخضر هنا معناه معنى «اتاخدت» نفسه:
        // الدوا اللي بيتاخد.
        border: F.careAccentTaken,
        edge: F.careAccentTaken,
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
            // المخزون — قراية بس (٠٠٢٨). «قرب يخلص» بعلامة ذهبي والنص بلون المتن
            if (medication.stockLine case final line?)
              Padding(
                padding: const EdgeInsets.only(top: F.s4),
                child: Row(
                  children: [
                    if (medication.stockLow) ...[
                      Icon(Icons.inventory_2_outlined, size: 16, color: F.gold),
                      const SizedBox(width: F.s4),
                    ],
                    Expanded(
                      child: Text(
                        line,
                        key: ValueKey('care-stock-${medication.uuid}'),
                        style: TextStyle(fontSize: F.careTextSize, color: F.ink, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({
    required this.event,
    required this.now,
    required this.accent,
    this.ahead = false,
  });

  /// لون القسم اللي الصف ده جواه — على الحد والشريط الجانبي.
  final Color accent;

  /// جرعة جاية — بدل كلمة الحالة بنكتب «كمان ٤٠ دقيقة»، وده اللي الابن
  /// بيقراه فعلاً. اليوم نفسه بيتقال في عنوان القسم مش في كل سطر.
  final bool ahead;

  final CaregiverDoseEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    // الحالة بالحرف زي ما جهاز الأب كتبها — بنترجم للعربي، مش بنحكم
    final look = doseLook(event, now);
    final label = switch (event.state) {
      // **وقت التأكيد الحقيقي، مش وقت الجدولة** — وده اللي المالك طلبه
      // في القسم ده: «الدوا، ميعاده، والوقت اللي اتأكّد فيه». والساعة
      // المجدولة موجودة في عمود الوقت على أول الصف. و«اتأكّدت» مش
      // «اتاخد»: العنوان فوق اسمه «اتاخدت» خلاص، والتكرار زحمة.
      'taken' => 'اتأكّدت ${event.actedAt == null ? '' : arabicTime(event.actedAt!)}',
      'skipped' => 'قال مش هياخده',
      // جهاز الأب هو اللي قال «اتنست» بعد المهلة — إحنا بننقل، مش بنحكم
      'missed' => 'اتنست — لسه ما اتأكدتش',
      _ when event.scheduledAt.isBefore(now) => 'لسه ما اتأكدتش',
      _ => 'جاي ${arabicTime(event.scheduledAt)}',
    };

    return CareCard(
      border: accent,
      edge: accent,
      padding: const EdgeInsets.symmetric(horizontal: F.carePad, vertical: F.s10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: F.careTapTarget - 2 * F.s10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 64,
              child: Text(
                arabicTime(event.scheduledAt),
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
            if (ahead)
              // القسم اسمه «جاية» خلاص، فالسطر ما بيكرّرش الحالة —
              // بيقول **قد إيه فاضل**، وده الرقم اللي بيتقري.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule, size: 16, color: F.mutedDark),
                  const SizedBox(width: F.s4),
                  Text(
                    timeAhead(now, event.scheduledAt),
                    style: TextStyle(
                      fontSize: F.careTextSize,
                      fontWeight: FontWeight.w700,
                      color: F.ink,
                      height: 1.4,
                    ),
                  ),
                ],
              )
            else
              CareStateMark(look: look, label: label.trim()),
          ],
        ),
      ),
    );
  }
}

/// متابعة مفتوحة — **قراية لصف الأب، ومفيش حكم**.
///
/// السطر بيقول: اسم المتابعة، المرحلة اللي هو واقف عندها، وميعادها لو
/// حطّه — ومعاه «كمان ٣ أيام». مفيش ميعاد؟ بنقول كده بالحرف بدل ما
/// نخترع تاريخ. وواقفة من أسبوع؟ بنقول إنها واقفة — دي واقعة عن الشاشة
/// مش عن الجسم ولا عن المعمل، وبنفس الحساب اللي على موبايل الأب.
class _FollowRow extends StatelessWidget {
  const _FollowRow({required this.follow, required this.now, required this.accent});

  final Color accent;

  final CareFollowUp follow;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final date = follow.stageDate;
    final doctor = follow.record.doctor?.trim();
    return CareCard(
      // متابعة واقفة بتاخد الدهبي بدل لون قسمها — «دي محتاجاك» بتغلب
      // الهوية، ودي نفس القاعدة اللي الدهبي موجود عشانها.
      border: follow.stalled ? F.gold : accent,
      edge: follow.stalled ? F.gold : accent,
      padding: const EdgeInsets.symmetric(horizontal: F.carePad, vertical: F.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  followDisplayTitle(follow.kind, follow.record.title),
                  style: TextStyle(
                    fontSize: F.careBodySize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: F.s8),
              CareStateMark(look: DoseLook.upcoming, label: follow.stage.label),
            ],
          ),
          const SizedBox(height: F.s4),
          Text(
            // **نفس السطر اللي الأب بيشوفه، من نفس الدالة.** نسختين
            // من نفس الجملة معناها شاشتين يقدروا يختلفوا في صمت — وده
            // العطل اللي الجولة دي عن: الأب شاف «بكرة» والابن شاف تاريخ
            // ورقة من ٢٠٢٣.
            [
              if (doctor != null && doctor.isNotEmpty) doctor,
              followDateFull(date, now),
            ].join(' — '),
            style: TextStyle(fontSize: F.careMicroSize, color: F.mutedDark, height: 1.4),
          ),
          if (follow.stalled)
            Padding(
              padding: const EdgeInsets.only(top: F.s4),
              child: Text(
                'واقفة عند «${follow.stage.label}» '
                '${timeSince(now, follow.record.checkupStageSince!)}',
                style: TextStyle(
                  fontSize: F.careMicroSize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                  height: 1.4,
                ),
              ),
            ),
        ],
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
      // كارت الحالة بياخد لون حالته — دهبي لما فيه حاجة محتاجاه، أخضر
      // لما كله تمام. الأيقونة والكلمة فوق اللون زي أي حالة تانية.
      border: colour,
      edge: colour,
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
      // **أحمر، بقرار المالك — وبنفس حدود استثناء جولة ٢١**: حد وشريط
      // وأيقونة، **من غير أي حشو**. الحبّاية الحمرا المليانة فاضلة
      // للطوارئ لوحدها، وده اللي بيخلّي معناها محفوظ.
      border: F.careAlertInk,
      edge: F.careAlertInk,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 18, color: F.careAlertInk),
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
