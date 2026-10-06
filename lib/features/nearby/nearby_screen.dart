import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'doctor_booking_message.dart';
import '../../domain/health/follow_up.dart';
import '../../core/widgets/f_sheet.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:url_launcher/url_launcher.dart';

import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../app/app_scope.dart';
import '../../data/places/places.dart';
import '../../domain/places/distance.dart';
import '../../domain/places/opening_hours.dart';
import '../../domain/places/place_links.dart';
import '../../domain/places/specialty.dart';
import '../emergency/emergency_widgets.dart' show dialNumber;
import '../medication/pharmacy_sheet.dart' show PharmacyPrefill, editPharmacy;
import '../medication/refill_actions.dart' show openWhatsApp;
import '../records/book_appointment.dart';

/// «الطريق» — جوجل ماب بالاتجاهات (من غير مفتاح)، ولو ما اتفتحتش خرايط أبل.
/// متغيّر عشان الاختبارات.
Future<void> Function(Place place) openDirections = (place) async {
  var opened = false;
  try {
    opened = await launchUrl(googleDirectionsUri(place.lat, place.lon), mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened) await launchUrl(appleDirectionsUri(place.lat, place.lon), mode: LaunchMode.externalApplication);
};

/// «احجز» على كارت دكتور — ورقة «ميعاد جديد» متعبّية باسمه. متغيّر عشان
/// الاختبارات؛ من غير `AppScope` الزرار مش موجود.
///
/// التخصص من المصدر **لو قال تخصص واحد بس** (وسم OSM أو كلمة في اسمه) —
/// أكتر من واحد أو مفيش = الخانة فاضية والشخص بيختار. عمرنا ما بنختار له.
///
/// **وبعد الحفظ، لو رقم الدكتور موبايل**: ورقة فيها رسالة الحجز جاهزة
/// (`doctorBookingMessage` — اليوم والساعة اللي اختارهم، واسم المريض وسنّه)
/// وزرار يفتح واتساب الدكتور عليها — المستخدم بيبعت بنفسه. رقم أرضي أو مفيش
/// رقم = مفيش ورقة ومفيش رقم مخمّن؛ الميعاد اتحفظ زي ما هو.
Future<bool> Function(BuildContext context, Place place, DateTime today) bookFromPlace = (context, place, today) async {
  final saved = await openBookAppointment(
    context,
    today: today,
    name: place.name,
    doctor: place.name,
    specialty: place.specialties.length == 1 ? place.specialties.single : null,
  );
  if (saved == null) return false;
  final wa = place.phone == null ? null : egyptMobileWhatsApp(place.phone!);
  if (wa == null || saved.kind != FollowKind.visit || !context.mounted) return true;
  final services = AppScope.of(context);
  final patient = await services.patients.getPatient(services.patientId);
  if (!context.mounted) return true;
  final message = doctorBookingMessage(day: saved.day, time: saved.time, patientName: patient?.name, age: patient?.age);
  await FSheet.show<void>(
    context,
    title: 'ابعت الميعاد للدكتور؟',
    children: [
      Text(
        'الميعاد اتحفظ عندك. دي الرسالة — هتفتح في واتساب وإنت اللي بتبعتها:',
        style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
      ),
      Container(
        key: const ValueKey('doctor-message'),
        padding: const EdgeInsets.all(F.s12),
        decoration: BoxDecoration(color: F.railGround, borderRadius: BorderRadius.circular(F.radiusCard)),
        child: Text(
          message,
          style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5),
        ),
      ),
      Builder(
        builder: (sheet) => FPrimaryButton(
          key: const ValueKey('send-doctor-whatsapp'),
          label: 'ابعت لـ${(place.name ?? '').trim().isEmpty ? 'الدكتور' : place.name!.trim()} على واتساب',
          onPressed: () async {
            Navigator.of(sheet).pop();
            await openWhatsApp(Uri.https('wa.me', '/$wa', {'text': message}));
          },
        ),
      ),
      Builder(
        builder: (sheet) => FSecondaryButton(
          key: const ValueKey('send-doctor-later'),
          label: 'مش دلوقتي',
          onPressed: () => Navigator.of(sheet).pop(),
        ),
      ),
    ],
  );
  return true;
};

String distanceText(double meters) =>
    meters < 1000 ? '${arabicNumber((meters / 10).round() * 10)} متر' : '${distanceKm(meters)} كم';

/// الرقم الكبير على الكارت بالكيلو: «٠٫٨» — فاصلة عشرية عربية (النقطة جنب
/// الأرقام العربية بتتقري صفر). أقل من ١٠٠ متر = «٠٫١».
String distanceKm(double meters) {
  final km = meters < 100 ? 0.1 : meters / 1000;
  return arabicDigits(km >= 10 ? km.round().toString() : km.toStringAsFixed(1)).replaceAll('.', '٫');
}

enum _Filter { all, pharmacy, doctor, hospital, lab }

/// أيقونة كل نوع ولونها — **نفسها** على الكارت والفلاتر ودبابيس الخريطة.
///
/// الألوان من الموجود وبس (قرار المالك، ٢٨ سبتمبر ٢٠٢٦): **مفيش أحمر**
/// (الطوارئ بس) و**مفيش دهبي** («محتاجاك دلوقتي» بس) ولا لون جديد — الأنواع
/// بتتفرّق بالأيقونة الأول، واللون تاني: صيدلية أخضر مصمت، دكتور أخضر فاتح،
/// مستشفى رمادي بحبر، معمل رمادي هادي.
typedef KindStyle = ({IconData icon, Color fg, Color bg});

KindStyle kindStyle(PlaceKind kind) => switch (kind) {
  PlaceKind.pharmacy => (icon: Icons.medication, fg: F.onGreen, bg: F.green),
  PlaceKind.doctor => (icon: Icons.medical_services, fg: F.greenStrong, bg: F.greenTint),
  PlaceKind.hospital => (icon: Icons.local_hospital, fg: F.ink, bg: F.cardGround),
  PlaceKind.lab => (icon: Icons.science, fg: F.mutedDark, bg: F.railGround),
};

/// بلاطة النوع — مربع مستدير بلونه وأيقونته.
class KindTile extends StatelessWidget {
  const KindTile(this.kind, {this.size = 56, super.key});
  final PlaceKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final st = kindStyle(kind);
    return Container(
      key: ValueKey('kind-tile-${kind.name}'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: st.bg,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: F.line),
      ),
      child: Icon(st.icon, size: size * 0.5, color: st.fg),
    );
  }
}

/// كلمة النوع في الكارت («… من غير اسم على الخريطة»).
String _kindWord(PlaceKind kind) => switch (kind) {
  PlaceKind.pharmacy => 'صيدلية',
  PlaceKind.doctor => 'دكتور',
  PlaceKind.hospital => 'مستشفى',
  PlaceKind.lab => 'معمل تحاليل',
};

/// «قريب منك» (المخطط ١٧، وتصميم المالك ٦ أكتوبر ٢٠٢٦) — الخريطة هي الشاشة.
///
/// فوق: «أماكن قريبة من موقعك»، شريحة «موقعك الحالي» (من غير اسم منطقة —
/// ده المرحلة د)، وسطر الخصوصية. تحتهم فلتر الأنواع بأيقوناتها، والتخصص
/// تحت «دكاترة». الخريطة بدبابيس النتايج ونقطتك، وفوقها «دوّر من مكاني
/// تاني» و«القايمة»؛ وورقة بتتسحب تحت فيها **المكان المختار** بأفعاله،
/// وسحبها لفوق (أو «القايمة») بيوري **باقي الأماكن** صفوف خفيفة.
///
/// **مفيش تقييمات بالنجوم ولا صورة مكان**: OSM مفيهاش تقييمات ولا صور،
/// وأبل ما بتبعتهمش — ونجمة أو صورة متخيّلة على صيدلية حقيقية كذبة على
/// بني آدمين. ومفيش «Concor متوفر» ولا «توصيل» ولا «بيقبل تأمينك» — مالهمش
/// مصدر. «مفتوح الآن» بس لو تاج `opening_hours` موجود و**مفهوم بالكامل**.
///
/// «© مساهمو OpenStreetMap» ظاهر على الخريطة دايماً — شرط الرخصة. البحث
/// استعلام واحد، بكاش، وبيتعاد بالزرار بس. المكان بيتقرّب قبل ما يخرج،
/// والشاشة بتقول إنه خارج. إذن الموقع بيتطلب هنا بس.
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({
    this.location = const DeviceLocation(),
    this.places,
    this.tileProvider,
    this.now,
    this.initialKind,
    this.initialSpecialty,
    this.onPickPharmacy,
    this.onBookPlace,
    super.key,
  });

  /// الممرض (0035): «احجز ميعاد عنده» بيبعت طلب ميعاد لموبايل المريض بدل
  /// ورقة الحجز المحلية. null = الحجز المحلي (المريض).
  final Future<void> Function(Place place)? onBookPlace;

  /// «اختار من القريب مني» من ورقة «صيدليتي»: «خليها صيدليتي» على الكارت
  /// بترجّع المكان للورقة بدل ما تفتح ورقة تانية.
  final void Function(Place place)? onPickPharmacy;

  /// «كلّمني» («أقرب صيدلية») بيفتح الشاشة على النوع ده — null = «الكل».
  final PlaceKind? initialKind;

  /// «أقرب دكتور عيون» — الشاشة بتفتح على الدكاترة والتخصص ده.
  final Specialty? initialSpecialty;

  final LocationSource location;
  final NearbyPlaces? places;

  /// للاختبارات — التطبيق بيستخدم الشبكة (بكاش flutter_map المدمج).
  final TileProvider? tileProvider;
  final DateTime Function()? now;

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

/// الورقة اللي تحت: ارتفاعها وهي مقفولة بيتحسب من المساحة — كفاية للمكان
/// المختار لحد صف الأفعال على آيفون SE — وأقصاها بيسيب شريط من الخريطة فوق
/// فيه الزرارين وحقوق الخريطة، عشان الـ© تفضل ظاهرة حتى في «القايمة».
@visibleForTesting
({double collapsed, double max}) nearbySheetSizes(double height, {bool controlsOnSheet = false}) {
  // فوق الورقة: في الشاشة العادية زرارين عايمين (٥٦) + حقوق الخريطة
  // (~٣٤). القصيرة حطّت الزرارين على الورقة نفسها، فبنحجز حقوق الخريطة
  // بس — وإلا كنا هنسحب مساحة مرتين.
  final overlay = (controlsOnSheet ? 0 : F.minTapTarget) + 34 + 3 * F.s6;
  if (height <= overlay) return (collapsed: 0.5, max: 0.5);
  final maxPx = height - overlay;
  // المقفولة: نص المساحة، مش أقل من ٢٥٠ (الكارت لحد صف الأفعال)، ومش أكتر
  // من المفتوحة ناقص شوية — على شاشة قصيرة جداً الحدود بتتقلب فالأصغر يكسب
  final upper = math.max(maxPx - 60, 0.0);
  // لما صف التحكم يعيش في حافة الورقة، بنحجز ارتفاعه فوق كارت المكان؛
  // كده زر «اتصال» ما يخرجش من شاشة SE.
  final cardWithControls = 250.0 + (controlsOnSheet ? F.minTapTarget + F.s8 : 0);
  final lower = math.min(cardWithControls, upper);
  final collapsedPx = (height * 0.5).clamp(lower, upper);
  final maxF = maxPx / height;
  final collapsed = (collapsedPx / height).clamp(math.min(0.2, maxF), maxF).toDouble();
  return (collapsed: collapsed, max: maxF);
}

/// زراير التحكم في الخريطة. مكانهم بيتغيّر على الشاشة القصيرة فقط، لكن
/// الكلمات والأفعال نفسها واحدة في الحالتين.
class _NearbyControls extends StatelessWidget {
  const _NearbyControls({required this.listOpen, required this.onResearch, required this.onToggleList});

  final bool listOpen;
  final VoidCallback onResearch;
  final VoidCallback onToggleList;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            flex: 3,
            child: FSecondaryButton(
              key: const ValueKey('nearby-research'),
              label: 'دوّر من مكاني تاني',
              icon: Icons.near_me_outlined,
              onPressed: onResearch,
            ),
          ),
          const SizedBox(width: F.s8),
          Expanded(
            flex: 2,
            child: FSecondaryButton(
              key: const ValueKey('nearby-view-toggle'),
              label: listOpen ? 'الخريطة' : 'القايمة',
              icon: listOpen ? Icons.map_outlined : Icons.list,
              onPressed: onToggleList,
            ),
          ),
        ],
      );
}

class _NearbyScreenState extends State<NearbyScreen> {
  late final NearbyPlaces _places = widget.places ?? NearbyPlaces.forPlatform();
  final _sheet = DraggableScrollableController();
  final _map = MapController();
  ScrollController? _sheetScroll;
  ({double collapsed, double max}) _sizes = (collapsed: 0.5, max: 0.9);

  LocationFix? _fix;
  PlacesResult? _result;
  bool _loading = true;
  bool _offline = false;

  /// المكان المختار في الورقة — null = الأقرب في الفلتر الحالي.
  String? _selectedId;
  late _Filter _filter = widget.initialSpecialty != null
      ? _Filter.doctor
      : switch (widget.initialKind) {
          PlaceKind.pharmacy => _Filter.pharmacy,
          PlaceKind.doctor => _Filter.doctor,
          PlaceKind.hospital => _Filter.hospital,
          PlaceKind.lab => _Filter.lab,
          null => _Filter.all,
        };

  /// تخصص الدكاترة — بيظهر ويشتغل على شريحة «دكاترة» بس.
  late Specialty? _specialty = widget.initialSpecialty;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  String _emptyText(PlaceKind? kind) => _emptyTextFor(kind, _places.sourceName);

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _sheet.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _offline = false;
    });
    final fix = await widget.location.current();
    if (!mounted) return;
    if (fix.status != LocationStatus.granted) {
      setState(() {
        _fix = fix;
        _loading = false;
      });
      return;
    }
    try {
      final result = await _places.search(fix.lat!, fix.lon!, now: _now);
      if (!mounted) return;
      setState(() {
        _fix = fix;
        _result = result;
        _loading = false;
      });
    } on PlacesOffline {
      if (!mounted) return;
      setState(() {
        _fix = fix;
        _offline = true;
        _loading = false;
      });
    }
  }

  double? _fittedFor;

  /// نقطتك وأقرب الأماكن جوّه الحتة اللي **باينة** فوق الورقة والزرارين —
  /// مركز الخريطة كان بيقع تحت الورقة على SE فنقطتك ما كانتش بتبان. الحشو
  /// عمره ما بياكل الخريطة كلها: بيفضل ٤٨ بكسل على الأقل للنقط.
  CameraFit _visibleFit(LatLng here, List<Place> nearest, double height) {
    final covered = height * _sizes.collapsed + F.minTapTarget + 34 + F.s6 * 4;
    // الدبوس طالع فوق نقطته — فالحشو اللي فوق على قد الدبوس، وبيصغر الأول
    // على الشاشة القصيرة قبل ما الحشو اللي تحت يتنازل
    final strip = height - covered;
    final top = math.min(64.0, math.max(0.0, strip - 48));
    final bottom = math.max(0.0, math.min(covered, height - top - 48));
    return CameraFit.coordinates(
      coordinates: [here, for (final p in nearest.take(8)) LatLng(p.lat, p.lon)],
      padding: EdgeInsets.fromLTRB(F.gap * 2, top, F.gap * 2, bottom),
      maxZoom: 16,
      minZoom: 14,
    );
  }

  bool get _listOpen => _sheet.isAttached && _sheet.size > (_sizes.collapsed + _sizes.max) / 2;

  /// على شاشة قصيرة (زي iPhone SE) الصف العايم كان بيغطي تقريباً كل شريط
  /// الخريطة الباقي فوق الورقة. بننقله لحافة الورقة نفسها؛ الشاشات العادية
  /// تفضل زي التصميم الأصلي، والزرارين ما زالوا ظاهرين من غير ما يغطّوا
  /// الخريطة.
  bool _shortScreen(BuildContext context) => MediaQuery.sizeOf(context).height <= 700;

  /// «القايمة» / «الخريطة» — نفس الورقة: مفتوحة لآخرها = كل الأماكن.
  void _toggleList() {
    if (!_sheet.isAttached) return;
    _sheet.animateTo(
      _listOpen ? _sizes.collapsed : _sizes.max,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  /// اختيار مكان (من دبوس أو من صف): بيبقى فوق الورقة بأفعاله، والورقة
  /// بتنزل لمكانها والخريطة بتروح له.
  void _select(Place place, {bool fromList = false}) {
    setState(() => _selectedId = place.id);
    final scroll = _sheetScroll;
    if (scroll != null && scroll.hasClients) scroll.jumpTo(0);
    if (fromList && _sheet.isAttached) {
      _sheet.animateTo(_sizes.collapsed, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    }
    try {
      _map.move(LatLng(place.lat, place.lon), _map.camera.zoom);
    } catch (_) {
      // الخريطة لسه ما اترسمتش — الاختيار نفسه هو اللي يهم
    }
  }

  @override
  Widget build(BuildContext context) {
    final fix = _fix;
    final located = !_loading && fix != null && fix.status == LocationStatus.granted;
    final hasResults = located && !_offline && _result != null;
    return Scaffold(
      appBar: AppBar(title: const Text('قريب منك'), centerTitle: true),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.s6),
            child: Column(
              children: [
                // سطر واحد على عرض الموبايل العادي — كان سطرين فوق بعض وكانوا
                // بياكلوا الخريطة على SE؛ وبيلفّ لوحده لو الخط كبير
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: F.s12,
                  runSpacing: F.s6,
                  children: [
                    Text(
                      'أماكن قريبة من موقعك',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                    ),
                    // «موقعك الحالي» لوحدها — اسم المنطقة جاي في المرحلة د، ومن
                    // غير موقع مفيش شريحة (كانت هتبقى كدبة)
                    if (located)
                      Container(
                        key: const ValueKey('nearby-location-chip'),
                        padding: const EdgeInsets.symmetric(horizontal: F.s12, vertical: F.s6),
                        decoration: BoxDecoration(
                          color: F.greenTint,
                          borderRadius: BorderRadius.circular(F.radiusLarge),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.place, size: 20, color: F.greenStrong),
                            const SizedBox(width: F.s6),
                            Text(
                              'موقعك الحالي',
                              style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: F.s6),
                // اسم اللي الموقع بيروح له **فعلاً** — من المصدر، مش من الشاشة:
                // على iOS ده Apple، وعلى أندرويد OpenStreetMap. ولا جملة تانية
                // هنا بتسمّي مصدر بالحرف — الاستثناء الوحيد حقوق الخريطة.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(Icons.lock_outline, size: 16, color: F.mutedDark),
                    ),
                    const SizedBox(width: F.s4),
                    Flexible(
                      child: Text(
                        'مكانك بيتبعت لـ ${_places.sourceName} عشان يدوّر — التقريبي، مش مكانك بالظبط.',
                        key: const ValueKey('nearby-privacy'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (hasResults) ..._filters(),
          Expanded(child: _content()),
        ],
      ),
    );
  }

  /// فلتر الأنواع — صف أفقي بأيقونة وكلمة، والتخصص تحت «دكاترة».
  List<Widget> _filters() => [
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: F.gap),
      child: Row(
        children: [
          for (final (i, (f, label, kind)) in [
            (_Filter.all, 'الكل', null),
            (_Filter.pharmacy, 'صيدليات', PlaceKind.pharmacy),
            (_Filter.doctor, 'دكاترة', PlaceKind.doctor),
            (_Filter.hospital, 'مستشفيات', PlaceKind.hospital),
            (_Filter.lab, 'معامل', PlaceKind.lab),
          ].indexed) ...[
            if (i > 0) const SizedBox(width: F.s8),
            AnchorChip(
              key: ValueKey('nearby-filter-${f.name}'),
              label: label,
              selected: _filter == f,
              icon: kind == null ? Icons.apps : kindStyle(kind).icon,
              // على الشريحة الأرضية هادية، فالأيقونة بلون الحبر بتاع النوع
              iconColor: kind == null ? F.ink : (kindStyle(kind).bg == F.green ? F.green : kindStyle(kind).fg),
              onTap: () => setState(() {
                _filter = f;
                _selectedId = null;
              }),
            ),
          ],
        ],
      ),
    ),
    if (_filter == _Filter.doctor) ...[
      const SizedBox(height: F.s8),
      SingleChildScrollView(
        key: const ValueKey('nearby-specialties'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: F.gap),
        child: Row(
          children: [
            Text(
              'التخصص',
              style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink),
            ),
            const SizedBox(width: F.s8),
            AnchorChip(
              key: const ValueKey('nearby-specialty-all'),
              label: 'كل التخصصات',
              selected: _specialty == null,
              onTap: () => setState(() {
                _specialty = null;
                _selectedId = null;
              }),
            ),
            for (final sp in Specialty.values) ...[
              const SizedBox(width: F.s8),
              AnchorChip(
                key: ValueKey('nearby-specialty-${sp.name}'),
                label: sp.label,
                selected: _specialty == sp,
                onTap: () => setState(() {
                  _specialty = sp;
                  _selectedId = null;
                }),
              ),
            ],
          ],
        ),
      ),
    ],
    const SizedBox(height: F.s8),
  ];

  Widget _content() {
    if (_loading) {
      return const _StateCard(
        key: ValueKey('nearby-loading'),
        icon: Icons.travel_explore,
        text: 'بندوّر على الأماكن اللي قريبة منك…',
        busy: true,
      );
    }
    final fix = _fix;
    if (fix == null || fix.status != LocationStatus.granted) {
      final (text, settings) = switch (fix?.status) {
        LocationStatus.serviceOff => ('خدمة الموقع مقفولة على الموبايل. افتحها وارجع جرّب تاني.', false),
        LocationStatus.deniedForever => (
          'إذن الموقع مقفول. من غيره مش هنعرف نلاقي اللي قريب منك — تقدر تفتحه من الإعدادات.',
          true,
        ),
        _ => ('من غير إذن الموقع مش هنعرف نلاقي اللي قريب منك.', false),
      };
      return _StateCard(
        key: const ValueKey('nearby-no-location'),
        icon: Icons.location_off_outlined,
        text: text,
        actions: [
          FPrimaryButton(label: 'جرّب تاني', icon: Icons.refresh, onPressed: _search),
          if (settings)
            FSecondaryButton(
              label: 'افتح الإعدادات',
              icon: Icons.settings_outlined,
              onPressed: widget.location.openSettings,
            ),
        ],
      );
    }
    if (_offline) {
      return _StateCard(
        key: const ValueKey('nearby-offline'),
        icon: Icons.wifi_off,
        text: 'مفيش نت دلوقتي — مش قادرين ندوّر. جرّب تاني لما النت يرجع.',
        actions: [FPrimaryButton(label: 'جرّب تاني', icon: Icons.refresh, onPressed: _search)],
      );
    }

    final result = _result!;
    final here = LatLng(fix.lat!, fix.lon!);
    double meters(Place p) => metersBetween(fix.lat!, fix.lon!, p.lat, p.lon);
    final all = [...result.places]..sort((a, b) => meters(a).compareTo(meters(b)));
    final wanted = switch (_filter) {
      _Filter.all => null,
      _Filter.pharmacy => PlaceKind.pharmacy,
      _Filter.doctor => PlaceKind.doctor,
      _Filter.hospital => PlaceKind.hospital,
      _Filter.lab => PlaceKind.lab,
    };
    final specialty = _filter == _Filter.doctor ? _specialty : null;
    final shown = [
      for (final p in all)
        if ((wanted == null || p.kind == wanted) && (specialty == null || p.specialties.contains(specialty))) p,
    ];
    final selected = shown.isEmpty ? null : shown.firstWhere((p) => p.id == _selectedId, orElse: () => shown.first);
    // **كل مكان ظاهر ليه عنصر واحد** في الورقة: المختار هو الكارت الكبير،
    // والباقي صفوف خفيفة — فمفيش اسم بيتكرّر ولا مفتاح `place-…` مرتين.
    final rest = [
      for (final p in shown)
        if (p != selected) p,
    ];

    return LayoutBuilder(
      builder: (context, box) {
        final shortScreen = _shortScreen(context);
        _sizes = nearbySheetSizes(box.maxHeight, controlsOnSheet: shortScreen);
        final fit = _visibleFit(here, all, box.maxHeight);
        // الكاميرا بتتظبط تاني لو مقاس الخريطة اتغيّر (لفّة الموبايل، الخط)
        if (_fittedFor != null && _fittedFor != box.maxHeight) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            try {
              _map.fitCamera(fit);
            } catch (_) {}
          });
        }
        _fittedFor = box.maxHeight;
        return Stack(
          children: [
            Positioned.fill(
              child: FlutterMap(
                mapController: _map,
                // من غير autofocus: الخريطة كانت بتاخد التركيز وتسحب الصفحة
                options: MapOptions(
                  initialCenter: here,
                  initialZoom: 15,
                  // نقطتك وأقرب الأماكن جوّه الحتة اللي **باينة** فوق الورقة
                  // والزرارين — مركز الخريطة كله كان بيقع تحت الورقة على SE
                  initialCameraFit: fit,
                  interactionOptions: const InteractionOptions(keyboardOptions: KeyboardOptions.disabled()),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.fakkarni.fakkarni',
                    tileProvider: widget.tileProvider,
                  ),
                  MarkerLayer(
                    markers: [
                      for (final p in shown)
                        Marker(
                          point: LatLng(p.lat, p.lon),
                          width: p == selected ? 52 : 40,
                          height: p == selected ? 62 : 48,
                          alignment: Alignment.topCenter,
                          child: _Pin(
                            key: ValueKey('pin-${p.id}'),
                            place: p,
                            selected: p == selected,
                            onTap: () => _select(p),
                          ),
                        ),
                      // نقطتك — أخضر التطبيق بهالة هادية. **مش أزرق**: الأزرق
                      // محجوز للمية ولكارت المعلومة
                      Marker(
                        point: here,
                        width: 34,
                        height: 34,
                        child: const _YouDot(key: ValueKey('nearby-you')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // في الشاشة العادية الزرارين وحقوق الخريطة فوق الورقة على طول.
            // في القصيرة الزرارين نفسهم جوّه حافة الورقة (تحت)، عشان ما
            // ياكلوش شريط الخريطة الصغير.
            AnimatedBuilder(
              animation: _sheet,
              builder: (context, _) {
                final size = _sheet.isAttached ? _sheet.size : _sizes.collapsed;
                final above = box.maxHeight * size;
                return Positioned.directional(
                  textDirection: Directionality.of(context),
                  start: F.s8,
                  end: F.s8,
                  bottom: above + F.s6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // عرض محسوب بـExpanded مش IntrinsicWidth: عرض الفقاعة
                      // الذاتي صفر، فـIntrinsicWidth كان بيخفي الزرارين خالص
                      if (!shortScreen) ...[
                        _NearbyControls(listOpen: _listOpen, onResearch: _search, onToggleList: _toggleList),
                        const SizedBox(height: F.s6),
                      ],
                      // شرط رخصة ODbL — ظاهر دايماً. ودجت بتاعنا مش
                      // SimpleAttributionWidget: ده بيحط © تانية وبيقلب العربي.
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Container(
                          key: const ValueKey('osm-attribution'),
                          padding: const EdgeInsets.symmetric(horizontal: F.s8, vertical: F.s4),
                          decoration: BoxDecoration(
                            color: const Color(0xE6FFFFFF),
                            borderRadius: BorderRadius.circular(F.radiusChip),
                          ),
                          child: Text(
                            '© مساهمو OpenStreetMap',
                            textDirection: TextDirection.rtl,
                            // الأرضية بيضا ثابتة فوق الخريطة — النص من نصوعها مش من الوضع
                            style: TextStyle(fontSize: F.minTextSize, color: F.onFill(const Color(0xE6FFFFFF))),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            DraggableScrollableSheet(
              controller: _sheet,
              initialChildSize: _sizes.collapsed,
              minChildSize: _sizes.collapsed,
              maxChildSize: _sizes.max,
              snap: true,
              builder: (context, scroll) {
                _sheetScroll = scroll;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: F.pageGround,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(F.radiusSheet)),
                    boxShadow: [BoxShadow(color: F.bubbleShadow, blurRadius: 18, offset: const Offset(0, -4))],
                  ),
                  child: SingleChildScrollView(
                    controller: scroll,
                    padding: EdgeInsets.only(bottom: F.gap + MediaQuery.of(context).padding.bottom),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // المقبض — السحب لفوق بيوري كل الأماكن
                        Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: F.s10),
                            width: 48,
                            height: 5,
                            decoration: BoxDecoration(color: F.line, borderRadius: BorderRadius.circular(3)),
                          ),
                        ),
                        if (shortScreen) ...[
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(F.gap, 0, F.gap, F.s8),
                            child: _NearbyControls(listOpen: _listOpen, onResearch: _search, onToggleList: _toggleList),
                          ),
                          Divider(height: 1, thickness: 1, color: F.lineSoft),
                        ],
                        if (result.offline)
                          _Notice(
                            key: const ValueKey('nearby-stale'),
                            icon: Icons.history,
                            text:
                                'مفيش نت — دي آخر نتايج من ${arabicDate(result.fetchedAt)} ${arabicTime(result.fetchedAt)}.',
                          ),
                        if (selected == null)
                          _Notice(
                            key: const ValueKey('nearby-empty'),
                            icon: Icons.search_off,
                            text: specialty == null
                                ? _emptyText(wanted)
                                : _emptySpecialtyText(specialty, _places.sourceName),
                          )
                        else ...[
                          _PlacePanel(
                            place: selected,
                            meters: meters(selected),
                            now: _now,
                            onPickPharmacy: widget.onPickPharmacy,
                            onBookPlace: widget.onBookPlace,
                          ),
                          if (rest.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(F.gap, F.s12, F.gap, F.s4),
                              child: Text(
                                'أماكن تانية قريبة — ${arabicNumber(rest.length)}',
                                key: const ValueKey('nearby-rest-head'),
                                style: TextStyle(
                                  fontSize: F.minTextSize,
                                  fontWeight: FontWeight.w700,
                                  color: F.mutedDark,
                                ),
                              ),
                            ),
                            for (final (i, p) in rest.indexed) ...[
                              if (i > 0)
                                Divider(height: 1, thickness: 1, color: F.lineSoft, indent: F.gap, endIndent: F.gap),
                              _PlaceRow(
                                place: p,
                                meters: meters(p),
                                now: _now,
                                onTap: () => _select(p, fromList: true),
                              ),
                            ],
                          ],
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// «الكل» فاضي.
const nearbyEmptyAll = 'مفيش أماكن قريبة دلوقتي — جرّب تكبّر المسافة';

/// تخصص مالوش نتايج — والجملة بتقول **إزاي بنعرف التخصص**، عشان «مفيش» ما
/// تتقريش «مفيش دكاترة عيون في المنطقة».
String _emptySpecialtyText(Specialty s, String source) =>
    'مفيش ${s.doctorWord} ظاهر على $source في ٢ كم حواليك. التخصص بيبان بس لو متسجّل على الخريطة أو مكتوب في اسم العيادة — جرّب «كل التخصصات».';

/// الحالة الفاضية — جملة لكل نوع على نفس النمط، وكلها بتسمّي المصدر من
/// الواجهة (Apple على iOS، OpenStreetMap على أندرويد).
String _emptyTextFor(PlaceKind? kind, String source) => switch (kind) {
  null => nearbyEmptyAll,
  PlaceKind.pharmacy => 'مفيش صيدليات متسجّلة على $source في ٢ كم حواليك.',
  PlaceKind.doctor => 'مفيش دكاترة متسجّلين على $source في ٢ كم حواليك. التغطية في مصر لسه ناقصة — خصوصاً الدكاترة.',
  PlaceKind.hospital => 'مفيش مستشفيات متسجّلة على $source في ٢ كم حواليك.',
  PlaceKind.lab => 'مفيش معامل تحاليل متسجّلة على $source في ٢ كم حواليك.',
};

/// النوع والتخصص: «دكتور عيون»، أو كلمة النوع لوحدها.
String _categoryOf(Place p) {
  final kindWord = _kindWord(p.kind);
  final specialties = p.specialties;
  return specialties.isEmpty ? kindWord : '$kindWord ${specialties.map((s) => s.label).join(' و')}';
}

String _nameOf(Place p) => p.name ?? '${_kindWord(p.kind)} من غير اسم على الخريطة';

/// المكان المختار — فوق الورقة بكل اللي يتعمل فيه.
class _PlacePanel extends StatelessWidget {
  const _PlacePanel({
    required this.place,
    required this.meters,
    required this.now,
    this.onPickPharmacy,
    this.onBookPlace,
  });

  final Place place;
  final void Function(Place place)? onPickPharmacy;
  final Future<void> Function(Place place)? onBookPlace;
  final double meters;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = place;
    final name = _nameOf(p);
    final hours = p.openingHours;
    final state = hours == null ? null : openStateAt(hours, now);
    final whatsApp = p.phone == null ? null : egyptMobileWhatsApp(p.phone!);
    // «احجز» بيسجّل الميعاد وتذكيره عندنا — مش بيكلّم العيادة
    final canBook = p.kind == PlaceKind.doctor && (onBookPlace != null || AppScope.maybeOf(context) != null);
    // «خليها صيدليتي» — بتفتح ورقة «صيدليتي» متعبّية؛ مفيش حفظ قبل «احفظ»
    final canKeep = p.kind == PlaceKind.pharmacy && (onPickPharmacy != null || AppScope.maybeOf(context) != null);

    return Padding(
      key: ValueKey('place-${p.id}'),
      padding: const EdgeInsets.symmetric(horizontal: F.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KindTile(p.kind, size: 52),
              const SizedBox(width: F.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      key: ValueKey('place-name-${p.id}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: nameDirection(name),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: F.subtitleSize,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                        color: p.name == null ? F.mutedDark : F.ink,
                      ),
                    ),
                    const SizedBox(height: F.s4),
                    Text(
                      _categoryOf(p),
                      key: ValueKey('place-category-${p.id}'),
                      style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: F.s10),
              _Distance(
                key: ValueKey('place-distance-${p.id}'),
                meters: meters,
                rating: p.rating,
                ratingKey: ValueKey('place-rating-${p.id}'),
              ),
            ],
          ),
          // «مفتوح الآن» / «مغلق» — **بس** لو مواعيد الخريطة مفهومة كلها
          if (state != null) ...[
            const SizedBox(height: F.s8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _OpenChip(key: ValueKey('open-state-${p.id}'), open: state == OpenState.open),
            ),
          ] else if (hours != null)
            Padding(
              padding: const EdgeInsets.only(top: F.s6),
              child: Text(
                'مواعيدها على الخريطة: $hours',
                textDirection: TextDirection.rtl,
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
              ),
            ),
          // العنوان — لو الخريطة فيها عنوان وبس
          if (p.address case final address?) ...[
            const SizedBox(height: F.s6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.place_outlined, size: 20, color: F.mutedDark),
                ),
                const SizedBox(width: F.s4),
                Expanded(
                  child: Text(
                    address,
                    key: ValueKey('place-address-${p.id}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: F.s12),
          // الأفعال الأساسية في صف واحد — كلهم بنفس الارتفاع (٦٤) عشان
          // الصف ما يبقاش متدرّج، و«اتصال» هو الأساسي الوحيد في الشاشة
          Row(
            children: [
              if (p.phone != null) ...[
                Expanded(
                  flex: 3,
                  child: KeyedSubtree(
                    key: ValueKey('call-${p.id}'),
                    child: FPrimaryButton(label: 'اتصال', icon: Icons.phone, onPressed: () => dialNumber(p.phone!)),
                  ),
                ),
                const SizedBox(width: F.s8),
              ],
              Expanded(
                flex: 3,
                child: KeyedSubtree(
                  key: ValueKey('route-${p.id}'),
                  child: FSecondaryButton(
                    label: 'اتجاهات',
                    icon: Icons.near_me,
                    height: F.primaryButtonHeight,
                    onPressed: () => openDirections(p),
                  ),
                ),
              ),
              if (whatsApp != null) ...[
                const SizedBox(width: F.s8),
                // أصغر — بس بكلمته: مفيش زرار أيقونة لوحده
                Expanded(
                  flex: 2,
                  child: KeyedSubtree(
                    key: ValueKey('whatsapp-${p.id}'),
                    child: FSecondaryButton(
                      label: 'واتساب',
                      icon: Icons.chat_outlined,
                      height: F.primaryButtonHeight,
                      onPressed: () => openWhatsApp(whatsAppUri(whatsApp)),
                    ),
                  ),
                ),
              ],
            ],
          ),
          // الإضافات الهادية تحت الصف — فقاعة ثانوية
          if (canKeep) ...[
            const SizedBox(height: F.s8),
            KeyedSubtree(
              key: ValueKey('keep-pharmacy-${p.id}'),
              child: FSecondaryButton(
                label: 'خليها صيدليتي',
                icon: Icons.bookmark_add_outlined,
                onPressed: () => onPickPharmacy != null
                    ? onPickPharmacy!(p)
                    : editPharmacy(context, prefill: PharmacyPrefill.fromPlace(p)),
              ),
            ),
          ],
          if (canBook) ...[
            const SizedBox(height: F.s8),
            KeyedSubtree(
              key: ValueKey('book-${p.id}'),
              child: FSecondaryButton(
                label: 'احجز ميعاد عنده',
                icon: Icons.event_outlined,
                onPressed: () => onBookPlace != null ? onBookPlace!(p) : bookFromPlace(context, p, now),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// صف خفيف لمكان مش مختار — الدوسة بتختاره.
class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.place, required this.meters, required this.now, required this.onTap});

  final Place place;
  final double meters;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = place;
    final name = _nameOf(p);
    final hours = p.openingHours;
    final state = hours == null ? null : openStateAt(hours, now);
    return InkWell(
      key: ValueKey('place-${p.id}'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: F.primaryButtonHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: F.gap, vertical: F.s8),
          child: Row(
            children: [
              KindTile(p.kind, size: 40),
              const SizedBox(width: F.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      key: ValueKey('place-name-${p.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: nameDirection(name),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: F.minBodySize,
                        fontWeight: FontWeight.w700,
                        color: p.name == null ? F.mutedDark : F.ink,
                      ),
                    ),
                    Wrap(
                      spacing: F.s8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _categoryOf(p),
                          key: ValueKey('place-category-${p.id}'),
                          style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                        ),
                        if (state != null)
                          _OpenChip(key: ValueKey('open-state-${p.id}'), open: state == OpenState.open, small: true),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: F.s8),
              _Distance(key: ValueKey('place-distance-${p.id}'), meters: meters, small: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// المسافة: الرقم بالكيلو كبير و«كم» تحته — والتقييم تحتهم **لو المصدر اداه**.
class _Distance extends StatelessWidget {
  const _Distance({required this.meters, this.rating, this.ratingKey, this.small = false, super.key});

  final double meters;
  final double? rating;
  final Key? ratingKey;
  final bool small;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        distanceKm(meters),
        style: TextStyle(
          fontFamily: F.displayFamily,
          fontSize: small ? F.minBodySize : F.subtitleSize + 4,
          fontWeight: FontWeight.w800,
          color: F.ink,
          height: 1.1,
        ),
      ),
      Text(
        'كم',
        style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
      ),
      if (rating case final r?) ...[
        const SizedBox(height: F.s6),
        Text(
          '★ ${arabicDigits(r.toStringAsFixed(1)).replaceAll('.', '٫')}',
          key: ratingKey,
          style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink),
        ),
      ],
    ],
  );
}

/// دبوس على الخريطة — بلاطة النوع نفسها وتحتها سنّ صغير. المختار أكبر وحواليه
/// حلقة بالحبر (مش دهبي: الدهبي «محتاجك دلوقتي» بس).
class _Pin extends StatelessWidget {
  const _Pin({required this.place, required this.selected, required this.onTap, super.key});

  final Place place;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = selected ? 44.0 : 34.0;
    final st = kindStyle(place.kind);
    return Semantics(
      button: true,
      label: _nameOf(place),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.32),
                border: selected ? Border.all(color: F.ink, width: 2) : null,
                boxShadow: [BoxShadow(color: F.bubbleShadow, blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: KindTile(place.kind, size: size),
            ),
            CustomPaint(size: const Size(12, 8), painter: _TailPainter(st.bg)),
          ],
        ),
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  _TailPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.color != color;
}

/// نقطتك على الخريطة — أخضر التطبيق بحلقة بيضا وهالة هادية.
class _YouDot extends StatelessWidget {
  const _YouDot({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'إنت هنا',
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: F.green.withValues(alpha: 0.22), shape: BoxShape.circle),
        ),
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: F.green,
            shape: BoxShape.circle,
            border: Border.all(color: F.onDark, width: 3),
          ),
        ),
      ],
    ),
  );
}

/// حالة من غير خريطة (بيدوّر، مفيش إذن، الخدمة مقفولة، مفيش نت) — أيقونة
/// كبيرة وجملة وأزرار واضحة. **عمرها ما بتبقى خريطة فاضية من غير كلام.**
class _StateCard extends StatelessWidget {
  const _StateCard({required this.icon, required this.text, this.actions = const [], this.busy = false, super.key});

  final IconData icon;
  final String text;
  final List<Widget> actions;
  final bool busy;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(F.gap),
    child: Container(
      padding: const EdgeInsets.all(F.gap),
      decoration: BoxDecoration(color: F.cardGround, borderRadius: BorderRadius.circular(F.radiusLarge)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: F.greenTint, borderRadius: BorderRadius.circular(F.radiusLarge)),
              child: busy
                  ? Padding(
                      padding: const EdgeInsets.all(F.s20),
                      child: CircularProgressIndicator(strokeWidth: 3, color: F.greenStrong),
                    )
                  : Icon(icon, size: 38, color: F.greenStrong),
            ),
          ),
          const SizedBox(height: F.s12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5),
          ),
          for (final a in actions) ...[const SizedBox(height: F.s10), a],
        ],
      ),
    ),
  );
}

/// «مفتوح الآن» (أخضر فاتح) / «مغلق» (رمادي). [small] للصفوف الخفيفة.
class _OpenChip extends StatelessWidget {
  const _OpenChip({required this.open, this.small = false, super.key});
  final bool open;
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: small ? F.s6 : F.s10, vertical: small ? 0 : F.s4),
    decoration: BoxDecoration(
      color: open ? F.greenOkSoft : F.railGround,
      borderRadius: BorderRadius.circular(F.radiusChip),
      border: Border.all(color: open ? F.greenOk : F.line),
    ),
    child: Text(
      open ? 'مفتوح الآن' : 'مغلق',
      style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: open ? F.greenOk : F.mutedDark),
    ),
  );
}

/// سطر هادي جوّه الورقة (آخر نتايج من غير نت، أو مفيش نتايج) — بأيقونته.
class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.icon, super.key});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(F.gap),
    margin: const EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.s8),
    decoration: BoxDecoration(color: F.railGround, borderRadius: BorderRadius.circular(F.radiusCard)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[Icon(icon, size: 24, color: F.mutedDark), const SizedBox(width: F.s10)],
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5),
          ),
        ),
      ],
    ),
  );
}
