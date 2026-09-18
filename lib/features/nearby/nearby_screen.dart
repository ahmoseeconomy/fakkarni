import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/places/places.dart';
import '../../domain/places/distance.dart';
import '../../domain/places/opening_hours.dart';
import '../emergency/emergency_widgets.dart' show dialNumber;

/// «الطريق» — خرايط الموبايل نفسه. متغيّر عشان الاختبارات.
Future<void> Function(Place place) openDirections = (place) async {
  final uri = Platform.isIOS
      ? Uri.parse('https://maps.apple.com/?daddr=${place.lat},${place.lon}')
      : Uri.parse('geo:${place.lat},${place.lon}?q=${place.lat},${place.lon}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
};

String distanceText(double meters) => meters < 1000
    ? '${arabicNumber((meters / 10).round() * 10)} متر'
    : '${arabicDigits((meters / 1000).toStringAsFixed(1))} كم';

enum _Filter { all, pharmacy, doctor }

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
    super.key,
  });

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
  _Filter _filter = _Filter.all;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

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
          Text(
            'صيدليات ودكاترة متسجّلين على OpenStreetMap في ٢ كم حواليك.',
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
    final shown = [
      for (final p in all)
        if (_filter == _Filter.all ||
            (_filter == _Filter.pharmacy && p.kind == PlaceKind.pharmacy) ||
            (_filter == _Filter.doctor && p.kind == PlaceKind.doctor))
          p,
    ];

    return [
      Wrap(
        spacing: F.s8,
        runSpacing: F.s8,
        children: [
          for (final (f, label) in [(_Filter.all, 'الكل'), (_Filter.pharmacy, 'صيدليات'), (_Filter.doctor, 'دكاترة')])
            AnchorChip(
              key: ValueKey('nearby-filter-${f.name}'),
              label: label,
              selected: _filter == f,
              onTap: () => setState(() => _filter = f),
            ),
        ],
      ),
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
                      width: 30,
                      height: 30,
                      child: Icon(
                        p.kind == PlaceKind.pharmacy ? Icons.local_pharmacy : Icons.medical_services,
                        color: F.greenDeep,
                        size: 28,
                      ),
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
                    style: TextStyle(fontSize: F.minTextSize, color: F.ink),
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
        const _Notice(
          key: ValueKey('nearby-empty'),
          text: 'مفيش حاجة متسجّلة على OpenStreetMap في ٢ كم حواليك. التغطية في مصر لسه ناقصة — خصوصاً الدكاترة.',
        )
      else
        for (final p in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: F.s10),
            child: _PlaceCard(place: p, meters: metersBetween(fix.lat!, fix.lon!, p.lat, p.lon), now: _now),
          ),
    ];
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place, required this.meters, required this.now});

  final Place place;
  final double meters;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = place;
    final kindWord = p.kind == PlaceKind.pharmacy ? 'صيدلية' : 'دكتور';
    final name = p.name ?? '$kindWord من غير اسم على الخريطة';
    final hours = p.openingHours;
    final state = hours == null ? null : openStateAt(hours, now);

    return FCard(
      key: ValueKey('place-${p.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(p.kind == PlaceKind.pharmacy ? Icons.local_pharmacy : Icons.medical_services, color: F.green, size: 26),
              const SizedBox(width: F.s8),
              Expanded(
                child: Text(
                  name,
                  textDirection: nameDirection(name),
                  // الاسم اللاتيني LTR بس لازق يمين زي العربي — مش جنب المسافة
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: F.minBodySize,
                    fontWeight: FontWeight.w700,
                    color: p.name == null ? F.mutedDark : F.ink,
                  ),
                ),
              ),
              Text(distanceText(meters), style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink)),
            ],
          ),
          Text(kindWord, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
          if (state != null)
            Text(
              state == OpenState.open ? 'فاتحة دلوقتي' : 'قافلة دلوقتي',
              key: ValueKey('open-state-${p.id}'),
              style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: state == OpenState.open ? F.greenOk : F.mutedDark),
            ),
          if (hours != null)
            Text(
              'مواعيدها على الخريطة: $hours',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
            ),
          const SizedBox(height: F.s10),
          Row(
            children: [
              if (p.phone != null) ...[
                Expanded(child: FSecondaryButton(key: ValueKey('call-${p.id}'), label: 'اتصل', onPressed: () => dialNumber(p.phone!))),
                const SizedBox(width: F.s10),
              ],
              Expanded(child: FSecondaryButton(key: ValueKey('route-${p.id}'), label: 'الطريق', onPressed: () => openDirections(p))),
            ],
          ),
        ],
      ),
    );
  }
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
