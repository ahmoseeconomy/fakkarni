import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../ai/pharmacy_card_reader.dart';
import '../../core/diagnostics.dart';
import '../../ai/prescription_reader.dart' show PrescriptionReadException;
import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart' show arabicDigits;
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../../data/places/places.dart';
import '../../domain/billing/family_plan.dart';
import '../../domain/medication/stock.dart' show whatsappNumber;
import '../../domain/places/pharmacy_numbers.dart';
import '../billing/feature_gate.dart';
import '../nearby/nearby_screen.dart';
import '../scan/scan_prescription_screen.dart' show PickImage, pickWithSystemCamera;

/// اللي جاي متعبّي من برّه الورقة — كارت في «القريب مني».
class PharmacyPrefill {
  const PharmacyPrefill({this.name, this.phone});
  final String? name;
  final String? phone;

  factory PharmacyPrefill.fromPlace(Place p) => PharmacyPrefill(name: p.name, phone: p.phone);
}

/// «اختار من القريب مني» — بيفتح الشاشة على الصيدليات، والكارت بيرجّع مكانه.
/// متغيّر عشان الاختبارات.
Future<Place?> Function(BuildContext context) pickPharmacyFromNearby = (context) =>
    Navigator.of(context).push<Place>(MaterialPageRoute(
      builder: (c) => NearbyScreen(
        initialKind: PlaceKind.pharmacy,
        onPickPharmacy: (place) => Navigator.of(c).pop(place),
      ),
    ));

/// صورة الكارت: نفس كاميرا/معرض الروشتة، والملف المؤقت بيتمسح — الصورة ما
/// بتتخزّنش. متغيّر عشان الاختبارات.
PickImage pickPharmacyCard = (source) => pickWithSystemCamera(source, deleteFile: true);

/// «صيدليتي» — تلات طرق: من «القريب مني»، من صورة الكارت، أو بالإيد. **مفيش
/// حاجة بتتحفظ غير بزرار «احفظ»**. true = اتحفظت.
Future<bool?> editPharmacy(BuildContext context, {PharmacyPrefill? prefill}) async {
  final prefs = AppScope.of(context).preferences;
  final current = await prefs.pharmacy();
  if (!context.mounted) return null;
  return editPharmacyWith(
    context,
    current: (name: current.name, whatsapp: current.whatsapp, call: current.call),
    prefill: prefill,
    onSave: (p) => prefs.setPharmacy(name: p.name, whatsapp: p.whatsapp, call: p.call ?? '', clearCall: p.call == null),
  );
}

/// نفس الورقة بمكان حفظ تاني — الممرض بيبعت «صيدليتي» لموبايل المريض (0035).
Future<bool?> editPharmacyWith(
  BuildContext context, {
  required SavedPharmacy current,
  required Future<void> Function(SavedPharmacy pharmacy) onSave,
  PharmacyPrefill? prefill,
  Future<Place?> Function(BuildContext context)? pickNearby,
}) =>
    FSheet.show<bool>(
      context,
      title: 'صيدليتي',
      children: [PharmacyBody(current: current, prefill: prefill, onSave: onSave, pickNearby: pickNearby)],
    );

typedef SavedPharmacy = ({String? name, String? whatsapp, String? call});

class PharmacyBody extends StatefulWidget {
  const PharmacyBody({required this.current, required this.onSave, this.prefill, this.pickNearby, super.key});
  final SavedPharmacy current;
  final PharmacyPrefill? prefill;
  final Future<void> Function(SavedPharmacy pharmacy) onSave;

  /// «اختار من القريب مني» — الافتراضي [pickPharmacyFromNearby].
  final Future<Place?> Function(BuildContext context)? pickNearby;

  @override
  State<PharmacyBody> createState() => _PharmacyBodyState();
}

class _PharmacyBodyState extends State<PharmacyBody> {
  late final _name = TextEditingController(text: widget.current.name ?? '');
  late final _call = TextEditingController(text: widget.current.call ?? '');
  late final _whatsapp = TextEditingController(text: widget.current.whatsapp ?? '');
  final _whatsappFocus = FocusNode();

  List<String> _choices = const [];
  bool _askWhatsApp = false;
  bool _review = false;
  bool _reading = false;
  String? _error;

  /// البيانات جت من برّه (القريب مني / الكارت) → الاستبدال بيتسأل.
  bool _fromOutside = false;
  bool _confirmReplace = false;

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    if (p != null) _applyPlace(p.name, p.phone, notify: false);
  }

  @override
  void dispose() {
    _name.dispose();
    _call.dispose();
    _whatsapp.dispose();
    _whatsappFocus.dispose();
    super.dispose();
  }

  /// كارت من «القريب مني»: الاسم والرقم. موبايل = اتصال وواتساب؛ أرضي أو
  /// مفيش = اتصال بس، والورقة بتسأل عن الواتساب.
  void _applyPlace(String? name, String? phone, {bool notify = true}) {
    void apply() {
      _fromOutside = true;
      _confirmReplace = false;
      _error = null;
      _choices = const [];
      _name.text = name ?? '';
      final numbers = choosePharmacyNumbers(phones: [?phone]);
      _call.text = numbers.call ?? '';
      _whatsapp.text = numbers.whatsapp ?? '';
      _askWhatsApp = numbers.needsWhatsAppQuestion;
      _review = true;
    }

    notify ? setState(apply) : apply();
  }

  Future<void> _fromNearby() async {
    final place = await (widget.pickNearby ?? pickPharmacyFromNearby)(context);
    if (place == null || !mounted) return;
    _applyPlace(place.name, place.phone);
  }

  /// [missingOnly]: من سؤال الواتساب — الاسم ورقم الاتصال اللي موجودين
  /// بيفضلوا، والكارت بيملا الناقص بس.
  Future<void> _fromCard(ImageSource source, {bool missingOnly = false}) async {
    final reader = AppScope.of(context).pharmacyCardReader;
    if (reader == null || _reading) return;
    if (!await ensureFamilyFeature(context, AppFeature.scans) || !mounted) return;
    final image = await pickPharmacyCard(source);
    if (image == null || !mounted) return;
    setState(() {
      _reading = true;
      _error = null;
    });
    PharmacyCardReading? reading;
    String? failure;
    try {
      reading = await reader.read(image);
    } on Exception catch (e) {
      // النص اللي اتقرا عمره ما يتسجّل — نوع العطل بس
      diag('Pharmacy: قراية الكارت وقعت — ${e.runtimeType}');
      // زحمة أو مهلة بتقول جملتها هي (نفس الروشتة) — غير كده «مش قادر أقرا»
      failure = e is PrescriptionReadException ? e.message : null;
    }
    if (!mounted) return;
    setState(() {
      _reading = false;
      if (reading == null || reading.unreadable) {
        _error = failure ?? pharmacyCardUnreadable;
        return;
      }
      _fillFromCard(reading, missingOnly: missingOnly);
    });
  }

  void _fillFromCard(PharmacyCardReading r, {required bool missingOnly}) {
    _fromOutside = true;
    _confirmReplace = false;
    final numbers = choosePharmacyNumbers(whatsapp: r.whatsapp, phones: r.phones);
    void put(TextEditingController c, String? value) {
      if (value == null || value.isEmpty) return;
      if (missingOnly && c.text.trim().isNotEmpty) return;
      c.text = value;
    }

    put(_name, r.name);
    put(_call, numbers.call);
    put(_whatsapp, numbers.whatsapp);
    _choices = _whatsapp.text.trim().isEmpty ? numbers.mobileChoices : const [];
    _askWhatsApp = _whatsapp.text.trim().isEmpty && _choices.isEmpty;
    _review = true;
  }

  String? get _callNumber => _call.text.trim().isEmpty ? null : normalizeEgyptPhone(_call.text);
  bool get _whatsappOk => _whatsapp.text.trim().isEmpty || whatsappNumber(_whatsapp.text) != null;
  bool get _canSave =>
      _whatsappOk && (_callNumber != null || (_whatsapp.text.trim().isNotEmpty && whatsappNumber(_whatsapp.text) != null));

  String _label(String? name, String? number) =>
      (name != null && name.trim().isNotEmpty) ? name.trim() : arabicDigits(number ?? '');

  bool get _replacing {
    final old = widget.current;
    final oldLabel = _label(old.name, old.call ?? old.whatsapp);
    if (!_fromOutside || oldLabel.isEmpty) return false;
    return oldLabel != _label(_name.text, _callNumber ?? _whatsapp.text);
  }

  Future<void> _save() async {
    if (_replacing && !_confirmReplace) {
      setState(() => _confirmReplace = true);
      return;
    }
    final navigator = Navigator.of(context);
    await widget.onSave((
      name: _name.text.trim().isEmpty ? null : _name.text.trim(),
      whatsapp: _whatsapp.text.trim().isEmpty ? null : normalizeEgyptPhone(_whatsapp.text),
      call: _callNumber,
    ));
    navigator.pop(true);
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: F.fieldGround,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
      );

  Widget _field(String key, TextEditingController c, String hint,
          {bool phone = false, FocusNode? focus, TextInputAction action = TextInputAction.next}) =>
      TextField(
        key: ValueKey(key),
        controller: c,
        focusNode: focus,
        keyboardType: phone ? TextInputType.phone : TextInputType.text,
        textInputAction: action,
        textDirection: phone ? TextDirection.ltr : null,
        onChanged: (_) => setState(() => _confirmReplace = false),
        style: TextStyle(fontSize: F.minBodySize, color: F.ink),
        decoration: _decoration(hint),
      );

  Text _line(String text, {Key? key, Color? color, FontWeight? weight}) => Text(text,
      key: key, style: TextStyle(fontSize: F.minBodySize, color: color ?? F.ink, height: 1.5, fontWeight: weight));

  @override
  Widget build(BuildContext context) {
    final canRead = AppScope.of(context).pharmacyCardReader != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FSecondaryButton(
          key: const ValueKey('pharmacy-from-nearby'),
          label: 'اختار من القريب مني',
          onPressed: _reading ? null : _fromNearby,
        ),
        if (canRead) ...[
          const SizedBox(height: F.s8),
          Row(children: [
            Expanded(
              child: FSecondaryButton(
                key: const ValueKey('pharmacy-card-camera'),
                label: 'صوّر كارت الصيدلية',
                onPressed: _reading ? null : () => _fromCard(ImageSource.camera),
              ),
            ),
            const SizedBox(width: F.s8),
            Expanded(
              child: FSecondaryButton(
                key: const ValueKey('pharmacy-card-gallery'),
                label: 'من الصور',
                onPressed: _reading ? null : () => _fromCard(ImageSource.gallery),
              ),
            ),
          ]),
        ],
        if (_reading) ...[
          const SizedBox(height: F.s8),
          _line('بيقرا الكارت…', key: const ValueKey('pharmacy-card-reading'), color: F.mutedDark),
        ],
        if (_error != null) ...[
          const SizedBox(height: F.s8),
          GoldNote(_error!, key: const ValueKey('pharmacy-card-error')),
        ],
        const SizedBox(height: F.gap),
        if (_review) ...[
          GoldNote('راجع البيانات قبل الحفظ', key: const ValueKey('pharmacy-review-note')),
          const SizedBox(height: F.s8),
        ],
        _field('pharmacy-name', _name, 'اسم الصيدلية'),
        const SizedBox(height: F.s8),
        _field('pharmacy-call', _call, 'رقم الاتصال', phone: true),
        const SizedBox(height: F.s8),
        _field('pharmacy-number', _whatsapp, 'رقم الواتساب — زي 01012345678',
            phone: true, focus: _whatsappFocus, action: TextInputAction.done),
        if (_choices.isNotEmpty) ...[
          const SizedBox(height: F.s8),
          _line('أنهي رقم عليه واتساب؟', key: const ValueKey('pharmacy-wa-choices')),
          const SizedBox(height: F.s4),
          Wrap(spacing: F.s8, runSpacing: F.s8, children: [
            for (final n in _choices)
              AnchorChip(
                key: ValueKey('pharmacy-wa-choice-$n'),
                label: arabicDigits(n),
                selected: normalizeEgyptPhone(_whatsapp.text) == n,
                onTap: () => setState(() {
                  _whatsapp.text = n;
                  _confirmReplace = false;
                }),
              ),
          ]),
        ],
        if (_askWhatsApp && _whatsapp.text.trim().isEmpty) ...[
          const SizedBox(height: F.gap),
          _line('عندك رقم واتساب للصيدلية دي؟', key: const ValueKey('pharmacy-wa-question'), weight: FontWeight.w700),
          const SizedBox(height: F.s8),
          Row(children: [
            if (canRead) ...[
              Expanded(
                child: FSecondaryButton(
                  key: const ValueKey('pharmacy-wa-photo'),
                  label: 'صوّر الكارت',
                  onPressed: _reading ? null : () => _fromCard(ImageSource.camera, missingOnly: true),
                ),
              ),
              const SizedBox(width: F.s8),
            ],
            Expanded(
              child: FSecondaryButton(
                key: const ValueKey('pharmacy-wa-type'),
                label: 'اكتبه',
                onPressed: () => _whatsappFocus.requestFocus(),
              ),
            ),
          ]),
        ],
        const SizedBox(height: F.gap),
        if (_confirmReplace) ...[
          _line(
            'تغيّر صيدليتك من ${_label(widget.current.name, widget.current.call ?? widget.current.whatsapp)} '
            'لـ ${_label(_name.text, _callNumber ?? _whatsapp.text)}؟',
            key: const ValueKey('pharmacy-replace-confirm'),
            weight: FontWeight.w700,
          ),
          const SizedBox(height: F.s8),
          FPrimaryButton(key: const ValueKey('pharmacy-replace-yes'), label: 'أيوه، غيّرها', onPressed: _save),
          const SizedBox(height: F.s8),
          FSecondaryButton(
            key: const ValueKey('pharmacy-replace-no'),
            label: 'لأ، خلّي القديمة',
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ] else
          FPrimaryButton(
            key: const ValueKey('pharmacy-save'),
            label: 'احفظ',
            onPressed: _canSave && !_reading ? _save : null,
          ),
      ],
    );
  }
}
