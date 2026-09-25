import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/patient_voice.dart';
import '../../data/repositories/dose_event_repository.dart';
import '../../domain/adherence/adherence.dart';
import '../today/dose_actions.dart' show confirmGroup;
import 'adherence_card.dart';
import 'adherence_screen.dart';
import 'adherence_sources.dart';

/// أقصى تاريخ بنقرا منه عشان «أحسن مرة» — سنة وشوية، أكتر من كفاية.
const adherenceHistoryDays = 400;

/// «إنت ماشي إزاي» على موبايل المريض: بيقرا أحداثه المحلية (قراية بس)
/// ويرسم الكارت، وبيستخبّى أول يومين بعد أول دوا.
class PatientAdherenceCard extends StatefulWidget {
  const PatientAdherenceCard({required this.routineDay, required this.now, this.elder = false, super.key});

  final DateTime routineDay;
  final DateTime now;
  final bool elder;

  @override
  State<PatientAdherenceCard> createState() => _PatientAdherenceCardState();
}

class _PatientAdherenceCardState extends State<PatientAdherenceCard> {
  StreamSubscription<List<DoseEventView>>? _sub;
  List<DoseEventView> _views = const [];
  bool _loaded = false;
  final _updates = StreamController<Adherence>.broadcast();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return;
    final d = widget.routineDay;
    _sub = AppScope.of(context)
        .events
        .watchRoutineDays(DateTime(d.year, d.month, d.day - adherenceHistoryDays), d)
        .listen((rows) {
      if (!mounted) return;
      setState(() {
        _views = rows;
        _loaded = true;
      });
      _updates.add(_compute());
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _updates.close();
    super.dispose();
  }

  Adherence _compute() => computeAdherence(dosesFromViews(_views), today: widget.routineDay, now: widget.now);

  Future<void> _lateTake(MissedDose m) async {
    final view = _views.where((v) => viewKey(v) == m.id).firstOrNull;
    if (view == null) return;
    // **نفس سكّة «أخدته»** — مفيش كتابة جديدة: الصف، الإلغاءات، والمخزون.
    await confirmGroup(AppScope.of(context), widget.routineDay, [view]);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final doses = dosesFromViews(_views);
    if (!adherenceWorthShowing(firstDoseDay(doses), widget.routineDay)) return const SizedBox.shrink();
    final a = computeAdherence(doses, today: widget.routineDay, now: widget.now);
    final say = PatientVoice.of(context);
    final title = say.pick('إنت ماشي إزاي', 'إنتي ماشية إزاي');
    return Padding(
      padding: const EdgeInsets.only(bottom: F.gap),
      child: AdherenceCard(
        adherence: a,
        title: title,
        elder: widget.elder,
        onOpen: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => AdherenceDetailScreen(
            initial: a,
            title: title,
            updates: _updates.stream,
            // نمط كبار السن: مكان واحد للتأكيد وبس (الكارت اللي فوق) —
            // التفاصيل هناك قراية.
            onLateTake: widget.elder ? null : _lateTake,
          ),
        )),
      ),
    );
  }
}
