import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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
Future<bool> Function(BuildContext context, Place place, DateTime today) bookFromPlace =
    (context, place, today) => openBookAppointment(
          context,
          today: today,
          name: place.name,
          doctor: place.name,
          specialty: place.specialties.length == 1 ? place.specialties.single : null,
        );

String distanceText(double meters) => meters < 1000
    ? '${arabicNumber((meters / 10).round() * 10)} متر'
    : '${distanceKm(meters)} كم';

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

/// «قريب منك» (المخطط ١٧) — صيدليات ودكاترة من OpenStreetMap.
///
/// **مفيش تقييمات بالنجوم**: OSM مفيهاش تقييمات، ونجمة متخيّلة على صيدلية
/// حقيقية كذبة على بني آدمين. ومفيش «Concor متوفر» ولا «توصيل» ولا «بيقبل
/// تأمينك» — مالهمش مصدر. «فاتحة/قافلة» بس لو تاج `opening_hours` موجود
/// و**مفهوم بالكامل**؛ غير كده التاج بيتعرض بالحرف أو مفيش حاجة.
///
/// «© مساهمو OpenStreetMap» على الخريطة — شرط الرخصة. البحث استعلام واحد،
/// بكاش، وبيتعاد بالزرار بس. المكان بيتقرّب قبل ما يخرج، والشاشة بتقول إنه
/// خارج. إذن الموقع بيتطلب هنا بس.
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

class _NearbyScreenState extends State<NearbyScreen> {
  late final NearbyPlaces _places = widget.places ?? NearbyPlaces.forPlatform();
  LocationFix? _fix;
  PlacesResult? _result;
  bool _loading = true;
  bool _offline = false;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('قريب منك')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(F.gap, F.s4, F.gap, F.s30),
        children: [
          // ولا جملة هنا بتسمّي مصدر بالحرف — الاسم من الواجهة (Apple على iOS،
          // OpenStreetMap على أندرويد). الاستثناء الوحيد حقوق الخريطة تحت.
          Text(
            'صيدليات ودكاترة متسجّلين على ${_places.sourceName} في ٢ كم حواليك.',
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
          ),
          // اسم اللي الموقع بيروح له **فعلاً** — من المصدر، مش من الشاشة:
          // على iOS ده Apple، وعلى أندرويد OpenStreetMap. الخريطة نفسها OSM
          // على الاتنين، وده سبب الـ© تحت.
          Text(
            'مكانك بيتبعت لـ ${_places.sourceName} عشان يدوّر — التقريبي، مش مكانك بالظبط.',
            key: const ValueKey('nearby-privacy'),
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
          ),
          const SizedBox(height: F.s12),
          ..._body(),
        ],
      ),
    );
  }

  List<Widget> _body() {
    if (_loading) {
      return [
        Padding(
          padding: EdgeInsets.all(F.gap),
          child: Text('بيدوّر…', textAlign: TextAlign.center, style: TextStyle(fontSize: F.minBodySize, color: F.mutedDark)),
        ),
      ];
    }
    final fix = _fix;
    if (fix == null || fix.status != LocationStatus.granted) {
      final (text, settings) = switch (fix?.status) {
        LocationStatus.serviceOff => ('خدمة الموقع مقفولة على الموبايل. افتحها وارجع جرّب تاني.', false),
        LocationStatus.deniedForever => ('إذن الموقع مقفول. من غيره مش هنعرف نلاقي اللي قريب منك — تقدر تفتحه من الإعدادات.', true),
        _ => ('من غير إذن الموقع مش هنعرف نلاقي اللي قريب منك.', false),
      };
      return [
        _Notice(key: const ValueKey('nearby-no-location'), text: text),
        const SizedBox(height: F.s10),
        if (settings) ...[
          FSecondaryButton(label: 'افتح الإعدادات', onPressed: widget.location.openSettings),
          const SizedBox(height: F.s8),
        ],
        FPrimaryButton(label: 'جرّب تاني', onPressed: _search),
      ];
    }
    if (_offline) {
      return [
        const _Notice(
          key: ValueKey('nearby-offline'),
          text: 'مفيش نت دلوقتي — مش قادرين ندوّر. جرّب تاني لما النت يرجع.',
        ),
        const SizedBox(height: F.s10),
        FPrimaryButton(label: 'جرّب تاني', onPressed: _search),
      ];
    }

    final result = _result!;
    final here = LatLng(fix.lat!, fix.lon!);
    final all = [...result.places]
      ..sort((a, b) => metersBetween(fix.lat!, fix.lon!, a.lat, a.lon).compareTo(metersBetween(fix.lat!, fix.lon!, b.lat, b.lon)));
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

    return [
      Wrap(
        spacing: F.s8,
        runSpacing: F.s8,
        children: [
          for (final (f, label, kind) in [
            (_Filter.all, 'الكل', null),
            (_Filter.pharmacy, 'صيدليات', PlaceKind.pharmacy),
            (_Filter.doctor, 'دكاترة', PlaceKind.doctor),
            (_Filter.hospital, 'مستشفيات', PlaceKind.hospital),
            (_Filter.lab, 'معامل تحاليل', PlaceKind.lab),
          ])
            AnchorChip(
              key: ValueKey('nearby-filter-${f.name}'),
              label: label,
              selected: _filter == f,
              icon: kind == null ? null : kindStyle(kind).icon,
              // على الشريحة الأرضية هادية، فالأيقونة بلون الحبر بتاع النوع
              iconColor: kind == null ? null : (kindStyle(kind).bg == F.green ? F.green : kindStyle(kind).fg),
              onTap: () => setState(() => _filter = f),
            ),
        ],
      ),
      if (_filter == _Filter.doctor) ...[
        const SizedBox(height: F.s10),
        Text('التخصص', style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink)),
        const SizedBox(height: F.s6),
        Wrap(
          spacing: F.s8,
          runSpacing: F.s8,
          children: [
            AnchorChip(
              key: const ValueKey('nearby-specialty-all'),
              label: 'كل التخصصات',
              selected: _specialty == null,
              onTap: () => setState(() => _specialty = null),
            ),
            for (final sp in Specialty.values)
              AnchorChip(
                key: ValueKey('nearby-specialty-${sp.name}'),
                label: sp.label,
                selected: _specialty == sp,
                onTap: () => setState(() => _specialty = sp),
              ),
          ],
        ),
      ],
      const SizedBox(height: F.s12),
      ClipRRect(
        borderRadius: BorderRadius.circular(F.radiusCard),
        child: SizedBox(
          height: 260,
          child: FlutterMap(
            // من غير autofocus: الخريطة كانت بتاخد التركيز وتسحب الصفحة لتحت
            // فتستخبّى جملة الخصوصية والفلاتر
            options: MapOptions(
              initialCenter: here,
              initialZoom: 15,
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
                      width: 34,
                      height: 34,
                      // نفس بلاطة الكارت والفلتر
                      child: KindTile(p.kind, size: 34),
                    ),
                  Marker(
                    point: here,
                    width: 22,
                    height: 22,
                    child: Container(
                      decoration: BoxDecoration(
                        color: F.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: F.onDark, width: 3),
                      ),
                    ),
                  ),
                ],
              ),
              // شرط رخصة ODbL — ظاهر على الخريطة دايماً. ودجت بتاعنا مش
              // SimpleAttributionWidget: ده بيحط © تانية وبيقلب ترتيب العربي.
              Align(
                alignment: AlignmentDirectional.bottomStart,
                child: Container(
                  key: const ValueKey('osm-attribution'),
                  margin: const EdgeInsets.all(F.s6),
                  padding: const EdgeInsets.symmetric(horizontal: F.s8, vertical: F.s4),
                  decoration: BoxDecoration(color: const Color(0xE6FFFFFF), borderRadius: BorderRadius.circular(F.radiusChip)),
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
        ),
      ),
      const SizedBox(height: F.s8),
      if (result.offline)
        _Notice(
          key: const ValueKey('nearby-stale'),
          text: 'مفيش نت — دي آخر نتايج من ${arabicDate(result.fetchedAt)} ${arabicTime(result.fetchedAt)}.',
        ),
      FSecondaryButton(label: 'دوّر من مكاني تاني', onPressed: _search),
      const SizedBox(height: F.s12),
      if (shown.isEmpty)
        _Notice(
          key: const ValueKey('nearby-empty'),
          text: specialty == null ? _emptyText(wanted) : _emptySpecialtyText(specialty, _places.sourceName),
        )
      else
        for (final p in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: F.s10),
            child: _PlaceCard(
                place: p,
                meters: metersBetween(fix.lat!, fix.lon!, p.lat, p.lon),
                now: _now,
                onPickPharmacy: widget.onPickPharmacy,
                onBookPlace: widget.onBookPlace),
          ),
    ];
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

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place, required this.meters, required this.now, this.onPickPharmacy, this.onBookPlace});

  final Place place;
  final void Function(Place place)? onPickPharmacy;
  final Future<void> Function(Place place)? onBookPlace;
  final double meters;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = place;
    final kindWord = _kindWord(p.kind);
    final name = p.name ?? '$kindWord من غير اسم على الخريطة';
    final hours = p.openingHours;
    final state = hours == null ? null : openStateAt(hours, now);
    final specialties = p.specialties;
    final category = specialties.isEmpty ? kindWord : '$kindWord ${specialties.map((s) => s.label).join(' و')}';
    final whatsApp = p.phone == null ? null : egyptMobileWhatsApp(p.phone!);
    // «احجز» بيسجّل الميعاد وتذكيره عندنا — مش بيكلّم العيادة
    final canBook = p.kind == PlaceKind.doctor && (onBookPlace != null || AppScope.maybeOf(context) != null);
    // «خليها صيدليتي» — بتفتح ورقة «صيدليتي» متعبّية؛ مفيش حفظ قبل «احفظ»
    final canKeep = p.kind == PlaceKind.pharmacy && (onPickPharmacy != null || AppScope.maybeOf(context) != null);

    return Container(
      key: ValueKey('place-${p.id}'),
      padding: const EdgeInsets.all(F.gap),
      decoration: BoxDecoration(
        color: F.pageGround,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: F.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KindTile(p.kind),
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
                    // النوع والتخصص — والعنوان لو الخريطة فيها عنوان
                    Text(
                      category,
                      key: ValueKey('place-category-${p.id}'),
                      style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4),
                    ),
                    if (p.address case final address?)
                      Text(
                        address,
                        key: ValueKey('place-address-${p.id}'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4),
                      ),
                    // «مفتوح الآن» / «مغلق» — **بس** لو مواعيد الخريطة مفهومة كلها
                    if (state != null) ...[
                      const SizedBox(height: F.s8),
                      _OpenChip(key: ValueKey('open-state-${p.id}'), open: state == OpenState.open),
                    ] else if (hours != null)
                      Text(
                        'مواعيدها على الخريطة: $hours',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: F.s10),
              // المسافة رقم كبير والوحدة تحته، والتقييم تحتهم **لو المصدر اداه**
              Column(
                key: ValueKey('place-distance-${p.id}'),
                children: [
                  Text(
                    distanceKm(meters),
                    style: TextStyle(fontFamily: F.displayFamily, fontSize: F.subtitleSize + 4, fontWeight: FontWeight.w800, color: F.ink, height: 1.1),
                  ),
                  Text('كم', style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
                  if (p.rating case final r?) ...[
                    const SizedBox(height: F.s6),
                    Text(
                      '★ ${arabicDigits(r.toStringAsFixed(1)).replaceAll('.', '٫')}',
                      key: ValueKey('place-rating-${p.id}'),
                      style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: F.s12),
          Row(
            children: [
              if (p.phone != null) ...[
                // مليان في كل كارت — استثناء من «أساسيين بس في الشاشة» بقرار
                // المالك (٢٨ سبتمبر ٢٠٢٦، تصميم «القريب مني»)
                Expanded(
                  child: _ActionButton(
                    key: ValueKey('call-${p.id}'),
                    label: 'اتصال',
                    icon: Icons.phone,
                    filled: true,
                    onPressed: () => dialNumber(p.phone!),
                  ),
                ),
                const SizedBox(width: F.s8),
              ],
              Expanded(
                child: _ActionButton(
                  key: ValueKey('route-${p.id}'),
                  label: 'اتجاهات',
                  icon: Icons.explore_outlined,
                  onPressed: () => openDirections(p),
                ),
              ),
              if (whatsApp != null) ...[
                const SizedBox(width: F.s8),
                // صغير — بس بكلمته: مفيش زرار أيقونة لوحده
                _WhatsAppButton(key: ValueKey('whatsapp-${p.id}'), onPressed: () => openWhatsApp(whatsAppUri(whatsApp))),
              ],
            ],
          ),
          if (canKeep) ...[
            const SizedBox(height: F.s4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: ValueKey('keep-pharmacy-${p.id}'),
                onPressed: () => onPickPharmacy != null
                    ? onPickPharmacy!(p)
                    : editPharmacy(context, prefill: PharmacyPrefill.fromPlace(p)),
                style: TextButton.styleFrom(
                  foregroundColor: F.greenStrong,
                  minimumSize: const Size(F.minTapTarget, F.minTapTarget),
                  textStyle: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700),
                ),
                child: const Text('خليها صيدليتي'),
              ),
            ),
          ],
          if (canBook) ...[
            const SizedBox(height: F.s4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: ValueKey('book-${p.id}'),
                onPressed: () => onBookPlace != null ? onBookPlace!(p) : bookFromPlace(context, p, now),
                style: TextButton.styleFrom(
                  foregroundColor: F.greenStrong,
                  minimumSize: const Size(F.minTapTarget, F.minTapTarget),
                  textStyle: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700),
                ),
                child: const Text('احجز ميعاد عنده'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// «اتصال» (مليان) / «اتجاهات» (محدّد) — ٥٦، أيقونة وكلمة.
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.icon, required this.onPressed, this.filled = false, super.key});

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(F.radiusCard),
      side: BorderSide(color: F.buttonEdge, width: 1.5),
    );
    final text = Text(label, maxLines: 1, style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700));
    return SizedBox(
      height: F.minTapTarget,
      child: filled
          ? FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 22),
              label: text,
              style: FilledButton.styleFrom(
                backgroundColor: F.green,
                foregroundColor: F.onGreen,
                shape: shape,
                padding: const EdgeInsets.symmetric(horizontal: F.s8),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 22),
              label: text,
              style: OutlinedButton.styleFrom(
                foregroundColor: F.ink,
                side: BorderSide(color: F.buttonEdge, width: 1.5),
                shape: shape,
                padding: const EdgeInsets.symmetric(horizontal: F.s8),
              ),
            ),
    );
  }
}

/// واتساب — مربع صغير بأيقونة وكلمة تحتها.
class _WhatsAppButton extends StatelessWidget {
  const _WhatsAppButton({required this.onPressed, super.key});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 72,
        height: F.minTapTarget,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: F.ink,
            padding: EdgeInsets.zero,
            side: BorderSide(color: F.buttonEdge, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.chat_outlined, size: 20),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('واتساب', maxLines: 1, style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, height: 1.1)),
              ),
            ],
          ),
        ),
      );
}

/// «مفتوح الآن» (أخضر فاتح) / «مغلق» (رمادي).
class _OpenChip extends StatelessWidget {
  const _OpenChip({required this.open, super.key});
  final bool open;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: F.s10, vertical: F.s4),
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

class _Notice extends StatelessWidget {
  const _Notice({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(F.gap),
        margin: const EdgeInsets.only(bottom: F.s8),
        decoration: BoxDecoration(color: F.railGround, borderRadius: BorderRadius.circular(F.radiusCard)),
        child: Text(text, style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5)),
      );
}
