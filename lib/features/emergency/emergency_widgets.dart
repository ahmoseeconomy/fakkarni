import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/emergency_repository.dart';
import '../../data/repositories/medication_repository.dart';

/// رقم الإسعاف في مصر.
const ambulanceNumber = '123';

/// النص اللي بيتقال لحقل فاضي — وبس. مفيش «غير معروف» ولا «لا يوجد».
const notFilled = 'لسه ما اتملاش';

/// بيفتح الاتصال على [number]. متغيّر عشان الاختبارات تسجّل الرقم بدل ما
/// تفتح تليفون — المحاكي أصلاً ما بيتصلش.
///
/// على iOS النظام نفسه بيسأل «تتصل بـ…؟» قبل ما يطلب؛ على أندرويد `tel:`
/// بيفتح لوحة الأرقام من غير ما يطلب. تأكيد الإسعاف بتاعنا فوق الاتنين.
Future<void> Function(String number) dialNumber = (number) async {
  await launchUrl(Uri(scheme: 'tel', path: number));
};

/// كل اللي الشاشتين محتاجينه: بيانات الطوارئ، الاسم والسن، والأدوية الشغّالة.
class EmergencySnapshot {
  const EmergencySnapshot({
    required this.info,
    required this.patient,
    required this.medications,
  });

  final EmergencyInfo info;
  final PatientRow? patient;

  /// أسماء الأدوية الشغّالة — من medications مباشرة، مش نسخة متخزّنة.
  final List<String> medications;

  /// «Concor 5mg · Amaryl 2mg» — الاسم ما بيتقسمش على سطرين، والنقطة
  /// بتفضل في آخر السطر مش أوله.
  String get medicationsLine =>
      [for (final m in medications) m.replaceAll(' ', '\u00A0')]
          .join('\u00A0· ');

  String? get nameAndAge {
    final name = patient?.name;
    if (name == null || name.isEmpty || name == 'أنا') return null;
    final age = patient?.age;
    return age == null ? name : '$name · ${arabicNumber(age)} سنة';
  }
}

/// بيانات الشاشتين من التلات مصادر — اشتراكات عادية بتتلغي في dispose
/// (نفس نمط باقي الشاشات)، و[snapshot] null لحد ما التلاتة يوصلوا.
mixin EmergencyData<T extends StatefulWidget> on State<T> {
  final List<StreamSubscription<Object?>> _subs = [];
  EmergencyInfo? _info;
  PatientRow? _patient;
  bool _patientReady = false;
  List<MedicationSummary>? _meds;

  EmergencySnapshot? get snapshot {
    final info = _info, meds = _meds;
    if (info == null || meds == null || !_patientReady) return null;
    return EmergencySnapshot(
      info: info,
      patient: _patient,
      medications: [for (final m in meds) m.medication.name],
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subs.isNotEmpty) return;
    final services = AppScope.of(context);
    _subs
      ..add(
        EmergencyRepository(services.db).watch(services.patientId).listen((v) {
          if (mounted) setState(() => _info = v);
        }),
      )
      ..add(
        services.routines.watchPatient(services.patientId).listen((v) {
          if (mounted) {
            setState(() {
              _patient = v;
              _patientReady = true;
            });
          }
        }),
      )
      ..add(
        services.medications.watchActiveSummaries(services.patientId).listen((
          v,
        ) {
          if (mounted) setState(() => _meds = v);
        }),
      );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

/// «تتصل بالإسعاف ١٢٣؟» — تأكيد صريح قبل الطلب. واحد عنده ٧٢ سنة ممكن
/// يلمس الزرار بالغلط؛ الغلطة هنا مكالمة إسعاف حقيقية.
Future<void> confirmAmbulance(BuildContext context) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.white,
      title: Text(
        'تتصل بالإسعاف ${arabicNumber(int.parse(ambulanceNumber))}؟',
        style: const TextStyle(
          fontFamily: F.displayFamily,
          fontSize: F.subtitleSize,
          fontWeight: FontWeight.w700,
          color: F.ink,
        ),
      ),
      content: const Text(
        'هيفتح الاتصال على الإسعاف دلوقتي.',
        style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.gap),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: F.primaryButtonHeight,
              child: FilledButton(
                key: const ValueKey('ambulance-confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: F.red,
                  foregroundColor: F.onRed,
                  textStyle: const TextStyle(
                    fontSize: F.minBodySize,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(F.radiusCard),
                  ),
                ),
                child: const Text('أيوه، اتصل'),
              ),
            ),
            const SizedBox(height: F.s8),
            SizedBox(
              height: F.minTapTarget,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: F.ink,
                  side: const BorderSide(color: F.line, width: 1.5),
                  textStyle: const TextStyle(
                    fontSize: F.minBodySize,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(F.radiusCard),
                  ),
                ),
                child: const Text('لأ، رجوع'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  if (yes ?? false) await dialNumber(ambulanceNumber);
}

/// زرار الإسعاف — أحمر، نابض. النبضة قصيرة بتتكرر بمؤقّت (مش حركة لا نهائية)،
/// وبتقف لو الجهاز طالب «تقليل الحركة». المؤقّت بيتلغي في dispose.
class AmbulanceButton extends StatefulWidget {
  const AmbulanceButton({super.key});

  @override
  State<AmbulanceButton> createState() => _AmbulanceButtonState();
}

class _AmbulanceButtonState extends State<AmbulanceButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(const Duration(milliseconds: 2400), (_) {
        if (mounted) _pulse.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        // هالة بتكبر وتختفي — الزرار نفسه ثابت تحت الصباع
        final t = Curves.easeOut.transform(_pulse.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(F.radiusLarge),
            boxShadow: [
              BoxShadow(
                color: F.red.withValues(alpha: 0.55 * (1 - t)),
                spreadRadius: 14 * t,
                blurRadius: 4,
              ),
            ],
          ),
          child: child,
        );
      },
      child: SizedBox(
        width: double.infinity,
        height: F.primaryButtonHeight,
        child: FilledButton.icon(
          key: const ValueKey('ambulance'),
          onPressed: () => confirmAmbulance(context),
          icon: const Icon(Icons.local_hospital, size: 28),
          label: Text(
            'اتصل بالإسعاف ${arabicNumber(int.parse(ambulanceNumber))}',
          ),
          style: FilledButton.styleFrom(
            backgroundColor: F.red,
            foregroundColor: F.onRed,
            textStyle: const TextStyle(
              fontSize: F.subtitleSize,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(F.radiusLarge),
            ),
          ),
        ),
      ),
    );
  }
}

/// صف جهة اتصال: الاسم (والصلة)، الرقم، وزرار «اتصال» بكلمة.
class ContactRow extends StatelessWidget {
  const ContactRow({
    required this.contact,
    this.onDark = true,
    this.buttonColor = F.onRed,
    this.buttonText = F.redDeep,
    super.key,
  });

  final EmergencyContact contact;
  final bool onDark;
  final Color buttonColor;
  final Color buttonText;

  @override
  Widget build(BuildContext context) {
    final main = onDark ? F.onRed : F.ink;
    final sub = onDark ? F.onRedMuted : F.mutedDark;
    final relation = contact.relation;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: F.s6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  relation == null
                      ? contact.name
                      : '${contact.name} ($relation)',
                  style: TextStyle(
                    fontSize: F.minBodySize,
                    fontWeight: FontWeight.w700,
                    color: main,
                  ),
                ),
                Text(
                  contact.phone,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: F.minTextSize,
                    color: sub,
                    fontFamily: F.monoFamily,
                    fontFamilyFallback: F.monoFallback,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: F.s8),
          SizedBox(
            height: F.minTapTarget,
            child: FilledButton.icon(
              onPressed: () => dialNumber(contact.phone),
              icon: const Icon(Icons.call, size: 22),
              label: const Text('اتصال'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, F.minTapTarget),
                backgroundColor: buttonColor,
                foregroundColor: buttonText,
                textStyle: const TextStyle(
                  fontSize: F.minTextSize,
                  fontWeight: FontWeight.w700,
                ),
                padding: const EdgeInsets.symmetric(horizontal: F.s14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(F.radiusTile),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// نص قيمة: اللي اتكتب، أو «لسه ما اتملاش». الأسماء اللاتيني بتتقلب LTR.
class FieldValue extends StatelessWidget {
  const FieldValue(
    this.value, {
    required this.style,
    required this.emptyStyle,
    super.key,
  });

  final String? value;
  final TextStyle style;
  final TextStyle emptyStyle;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v == null || v.isEmpty) return Text(notFilled, style: emptyStyle);
    return Text(v, style: style, textDirection: nameDirection(v));
  }
}
