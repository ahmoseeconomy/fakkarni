import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import 'emergency_info_screen.dart';
import 'emergency_widgets.dart';

/// «بطاقة الطوارئ» (المخطط ٣٢) — **شاشة كاملة جوّه التطبيق**، بلمسة واحدة
/// من الشريط العلوي.
///
/// التصميم بيرسمها على شاشة القفل. ده محتاج WidgetKit extension بـSwift
/// و App Group — مش مبني (مكتوب في المؤجَّل). عشان كده ولا نص هنا بيقول
/// «شاشة القفل» ولا «من غير فك الموبايل»: الشاشة دي بتتفتح من جوّه
/// التطبيق، والكلام لازم يقول كده.
///
/// الساعة بتتحدّث بمؤقّت بيتلغي في dispose. «مشاركة سريعة» مش مبنية.
class EmergencyCardScreen extends StatefulWidget {
  const EmergencyCardScreen({this.now, super.key});

  /// للاختبارات.
  final DateTime Function()? now;

  @override
  State<EmergencyCardScreen> createState() => _EmergencyCardScreenState();
}

class _EmergencyCardScreenState extends State<EmergencyCardScreen>
    with EmergencyData {
  Timer? _clock;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final clock =
        '${arabicNumber(h)}:${arabicDigits(now.minute.toString().padLeft(2, '0'))}';

    // ساعة الموبايل بالأبيض فوق الأحمر
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [F.redDeep, F.greenDark, F.inkDeep],
              stops: [0, 0.55, 1],
            ),
          ),
          child: SafeArea(
            child: Builder(
              builder: (context) {
                final data = snapshot;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: F.s8),
                      child: Row(
                        children: [
                          SizedBox(
                            height: F.minTapTarget,
                            child: TextButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const EmergencyInfoScreen(),
                                ),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: F.onRed,
                                textStyle: const TextStyle(
                                  fontSize: F.minBodySize,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: const Text('كل المعلومات'),
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            height: F.minTapTarget,
                            child: TextButton(
                              onPressed: () => Navigator.of(context).maybePop(),
                              style: TextButton.styleFrom(
                                foregroundColor: F.onRed,
                                textStyle: const TextStyle(
                                  fontSize: F.minBodySize,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: const Text('إغلاق'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      clock,
                      key: const ValueKey('emergency-clock'),
                      style: const TextStyle(
                        fontFamily: F.displayFamily,
                        fontSize: F.display1,
                        fontWeight: FontWeight.w700,
                        color: F.onRed,
                      ),
                    ),
                    const Text(
                      'بطاقة الطوارئ',
                      style: TextStyle(
                        fontSize: F.minTextSize,
                        color: F.onRedMuted,
                      ),
                    ),
                    const SizedBox(height: F.s12),
                    Expanded(
                      child: data == null
                          ? const SizedBox.shrink()
                          : ListView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: F.gap,
                              ),
                              children: [
                                _WhiteCard(data: data),
                                const SizedBox(height: F.s12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: F.s14,
                                    vertical: F.s8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: F.onRed.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(
                                      F.radiusCard,
                                    ),
                                  ),
                                  child: data.info.contacts.isEmpty
                                      ? const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: F.s8,
                                          ),
                                          child: Text(
                                            'جهات الاتصال: $notFilled',
                                            style: TextStyle(
                                              fontSize: F.minBodySize,
                                              color: F.onRedMuted,
                                            ),
                                          ),
                                        )
                                      : Column(
                                          children: [
                                            for (final c in data.info.contacts)
                                              ContactRow(
                                                contact: c,
                                                buttonColor: F.greenOk,
                                                buttonText: F.onRed,
                                              ),
                                          ],
                                        ),
                                ),
                                const SizedBox(height: F.gap),
                              ],
                            ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.s12),
                      child: AmbulanceButton(),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.data});

  final EmergencySnapshot data;

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(fontSize: F.minTextSize, color: F.mutedDark);
    const value = TextStyle(
      fontSize: F.minBodySize,
      fontWeight: FontWeight.w700,
      color: F.ink,
      height: 1.4,
    );
    const empty = TextStyle(
      fontSize: F.minBodySize,
      color: F.mutedDark,
      height: 1.4,
    );
    // الحساسية بالأحمر جوّه الكارت — زي التصميم، وجوّه شاشة الطوارئ بس
    final allergy = value.copyWith(color: F.redDeep);
    final info = data.info;

    Widget field(String name, Widget child) => Padding(
      padding: const EdgeInsets.only(top: F.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: label),
          child,
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(F.gap),
      decoration: BoxDecoration(
        color: F.onRed,
        borderRadius: BorderRadius.circular(F.radiusLarge),
        boxShadow: F.shadowModalDark,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldValue(
            data.nameAndAge,
            style: const TextStyle(
              fontFamily: F.displayFamily,
              fontSize: F.subtitleSize,
              fontWeight: FontWeight.w700,
              color: F.ink,
            ),
            emptyStyle: empty,
          ),
          field(
            'فصيلة الدم',
            FieldValue(
              info.bloodType,
              style: allergy.copyWith(
                fontFamily: F.monoFamily,
                fontFamilyFallback: F.monoFallback,
              ),
              emptyStyle: empty,
            ),
          ),
          field(
            'الحساسية',
            FieldValue(info.allergies, style: allergy, emptyStyle: empty),
          ),
          field(
            'الأمراض المزمنة',
            FieldValue(info.chronicConditions, style: value, emptyStyle: empty),
          ),
          field(
            'الأدوية الحالية',
            data.medications.isEmpty
                ? const Text('مفيش أدوية متسجّلة', style: empty)
                : Text(
                    data.medicationsLine,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.right,
                    style: value.copyWith(
                      fontFamily: F.monoFamily,
                      fontFamilyFallback: F.monoFallback,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
