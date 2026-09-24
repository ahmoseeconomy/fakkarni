import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../data/care/caregiver_remote.dart';
import '../../domain/care/follower_role.dart';
import 'caregiver_snapshot_holder.dart';
import 'caregiver_status.dart';
import 'caregiver_ui.dart';
import 'caregiver_words.dart';

/// **«مرآة»** — تبويب الممرض/المرافق (٠٠٢٣): يوم المريض زي ما هو بيشوفه
/// على «يومك» — اللي دلوقتي، وجدول النهارده بحالاته — من الصورة اللي موبايله
/// رفعها، **ما بنحلّش مراسي** (القاعدة ٣.٥). و«أكّد إنه أخدها» على
/// الجرعة المستحقة أو الفايتة لو الأب سمح له يأكّد.
///
/// التأكيد صف في `proxy_confirmations`؛ موبايل المريض هو اللي بيكتب `taken`
/// ويلغي سلّمه. لحد ما يسحبه، الصف هنا بيقول «أكّدتها ✓ — مستنية موبايله».
class CaregiverMirrorScreen extends StatefulWidget {
  const CaregiverMirrorScreen({required this.holder, this.now, super.key});

  final CaregiverSnapshotHolder holder;
  final DateTime? now;

  static const confirmLabel = 'أكّد إنه أخدها';

  @override
  State<CaregiverMirrorScreen> createState() => _CaregiverMirrorScreenState();
}

class _CaregiverMirrorScreenState extends State<CaregiverMirrorScreen> {
  final _busy = <String>{};
  String? _error;

  DateTime get _now => widget.now ?? DateTime.now();

  Future<void> _confirm(CaregiverSnapshot snapshot, CaregiverDoseEvent event) async {
    final services = AppScope.of(context);
    final proxy = services.proxy;
    if (proxy == null || _busy.contains(event.uuid)) return;
    setState(() {
      _busy.add(event.uuid);
      _error = null;
    });
    try {
      String? me;
      try {
        me = (await services.caregiverPreferences?.load(snapshot.patient.uuid))?.name;
      } catch (_) {}
      await proxy.confirmOnBehalf(
        patientUuid: snapshot.patient.uuid,
        doseEventUuid: event.uuid,
        actorName: me,
      );
      await widget.holder.refresh();
    } on CareCircleException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'مقدرناش نأكّد. جرّب تاني.');
    } finally {
      if (mounted) setState(() => _busy.remove(event.uuid));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.holder,
        builder: (context, _) {
          final snapshot = widget.holder.snapshot;
          final patient = snapshot?.patient;
          return Scaffold(
            appBar: careAppBar('مرآة${patient == null ? '' : ' — ${patient.name}'}'),
            body: snapshot == null
                ? Center(
                    child: widget.holder.loading
                        ? CircularProgressIndicator(color: F.green)
                        : CarePanel(
                            text: widget.holder.error ?? 'لسه مفيش صورة من موبايله.',
                            action: 'حاول تاني',
                            onAction: widget.holder.refresh,
                          ),
                  )
                : _body(snapshot),
          );
        },
      );

  Widget _body(CaregiverSnapshot snapshot) {
    final now = _now;
    final s = careDoseSections(snapshot, now);
    final canConfirm = snapshot.patient.permissions.canConfirm;
    // «الآن» زي «يومك»: اللي عدّى من غير تأكيد الأول (الأقدم)، وبعدين الجاية
    final nowEvent = s.missed.isNotEmpty ? s.missed.first : s.upcomingToday.firstOrNull;

    return RefreshIndicator(
      onRefresh: widget.holder.refresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(F.carePad, F.s8, F.carePad, F.s30 + MediaQuery.of(context).padding.bottom),
        children: [
          if (!canConfirm)
            const CarePanel(
              key: ValueKey('mirror-read-only'),
              text: 'إنت بتشوف يومه بس — التأكيد بداله محتاج المريض يسمح بيه من موبايله.',
            ),
          if (_error case final e?) ...[
            CarePanel(key: const ValueKey('mirror-error'), text: e),
            const SizedBox(height: F.s8),
          ],
          const CareHead('الآن'),
          if (nowEvent == null)
            const CarePanel(text: 'مفيش جرعة دلوقتي — كل حاجة في وقتها.')
          else
            _MirrorRow(
              event: nowEvent,
              now: now,
              proxiedBy: snapshot.proxied[nowEvent.uuid],
              proxied: snapshot.proxied.containsKey(nowEvent.uuid),
              busy: _busy.contains(nowEvent.uuid),
              onConfirm: canConfirm ? () => _confirm(snapshot, nowEvent) : null,
              big: true,
            ),
          const SizedBox(height: F.s12),
          const CareHead('جدول النهارده'),
          if (s.missed.isEmpty && s.upcomingToday.isEmpty && s.taken.isEmpty && s.skipped.isEmpty)
            const CarePanel(text: 'مفيش جرعات متسجّلة النهارده لسه.')
          else
            for (final e in [...s.missed, ...s.upcomingToday, ...s.taken, ...s.skipped]
              ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt)))
              _MirrorRow(
                event: e,
                now: now,
                proxiedBy: snapshot.proxied[e.uuid],
                proxied: snapshot.proxied.containsKey(e.uuid),
                busy: _busy.contains(e.uuid),
                onConfirm: canConfirm ? () => _confirm(snapshot, e) : null,
              ),
          if (snapshot.lastUpdated case final at?) ...[
            const SizedBox(height: F.s12),
            Text(
              'آخر تحديث من موبايله ${timeSince(now, at)}',
              style: TextStyle(fontSize: F.careMicroSize, color: F.mutedDark),
            ),
          ],
        ],
      ),
    );
  }
}

class _MirrorRow extends StatelessWidget {
  const _MirrorRow({
    required this.event,
    required this.now,
    required this.proxied,
    required this.proxiedBy,
    required this.busy,
    required this.onConfirm,
    this.big = false,
  });

  final CaregiverDoseEvent event;
  final DateTime now;
  final bool proxied;
  final String? proxiedBy;
  final bool busy;
  final VoidCallback? onConfirm;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final look = doseLook(event, now);
    final due = !event.confirmed && !event.scheduledAt.isAfter(now.add(const Duration(minutes: 5)));
    final (accent, label) = switch (look) {
      DoseLook.taken => (F.careAccentTaken, 'اتأكّدت ${event.actedAt == null ? '' : arabicTime(event.actedAt!)}'),
      DoseLook.skipped => (F.careAccentSkipped, 'قال مش هياخده'),
      DoseLook.unconfirmed => (F.careAccentDue, 'لسه ما اتأكدتش'),
      DoseLook.upcoming => (F.careAccentUpcoming, 'جاية ${timeAhead(now, event.scheduledAt)}'),
    };
    final showConfirm = due && !proxied && onConfirm != null;
    return CareCard(
      border: accent,
      edge: accent,
      padding: const EdgeInsets.symmetric(horizontal: F.carePad, vertical: F.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  arabicTime(event.scheduledAt),
                  style: TextStyle(fontSize: F.careMicroSize, fontWeight: FontWeight.w700, color: F.mutedDark),
                ),
              ),
              Expanded(
                child: Text(
                  event.amountLabel == null ? event.medicationName : '${event.medicationName} — ${event.amountLabel}',
                  style: TextStyle(
                    fontSize: big ? F.careBodySize + 2 : F.careBodySize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                    fontFamily: F.monoFamily,
                    fontFamilyFallback: F.monoFallback,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: F.s8),
              CareStateMark(look: look, label: proxied && !event.confirmed ? 'أكّدتها ✓' : label.trim()),
            ],
          ),
          if (proxied && !event.confirmed)
            Padding(
              padding: const EdgeInsets.only(top: F.s6),
              child: Text(
                proxiedBy == null || proxiedBy!.trim().isEmpty
                    ? proxyPendingLine
                    : '${proxyConfirmedLine(proxiedBy)} — مستنية موبايله يوصله',
                key: ValueKey('mirror-proxied-${event.uuid}'),
                style: TextStyle(fontSize: F.careTextSize, color: F.mutedDark, height: 1.4),
              ),
            ),
          if (showConfirm)
            Padding(
              padding: const EdgeInsets.only(top: F.s8),
              child: SizedBox(
                height: F.careTapTarget,
                child: FilledButton(
                  key: ValueKey('mirror-confirm-${event.uuid}'),
                  onPressed: busy ? null : onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: F.green,
                    foregroundColor: F.onDark,
                    textStyle: const TextStyle(fontSize: F.careBodySize, fontWeight: FontWeight.w700),
                  ),
                  child: Text(busy ? 'ثواني…' : CaregiverMirrorScreen.confirmLabel),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
