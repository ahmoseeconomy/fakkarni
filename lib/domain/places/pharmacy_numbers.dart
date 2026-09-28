// أرقام «صيدليتي» — دارت نقية: إزاي رقم مكتوب بأي شكل يبقى رقم اتصال، وإمتى
// يبقى رقم واتساب. **واتساب على رقم أرضي باب مقفول**، فعمرنا ما نختاره.

/// الرقم بصيغته المحلية: أرقام لاتيني، من غير مسافات ولا شرط، و+٢٠ / ٠٠٢٠
/// بتبقى ٠. الأرضي بيفضل زي ما هو. أقل من ٧ أرقام = مش رقم (null).
String? normalizeEgyptPhone(String raw) {
  var d = _western(raw).replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('0020')) {
    d = '0${d.substring(4)}';
  } else if (d.startsWith('20') && (d.length == 12 || d.length == 11)) {
    // ٢٠١٠١٢٣٤٥٦٧٨ (موبايل) أو ٢٠٢٢٣٤٥٦٧٨٩ (أرضي القاهرة) من غير +
    d = '0${d.substring(2)}';
  } else if (d.length == 10 && d.startsWith('1')) {
    d = '0$d'; // ١٠١٢٣٤٥٦٧٨ — الصفر اتنسى
  }
  return d.length < 7 ? null : d;
}

/// موبايل مصري: ٠١٠ / ٠١١ / ٠١٢ / ٠١٥ وبعدها ٨ أرقام.
bool isEgyptMobile(String local) => RegExp(r'^01[0125]\d{8}$').hasMatch(local);

/// اللي بيتعبّى في الورقة من رقم أو أكتر.
class PharmacyNumbers {
  const PharmacyNumbers({this.call, this.whatsapp, this.mobileChoices = const []});

  /// رقم الاتصال — أول رقم (موبايل أو أرضي).
  final String? call;

  /// رقم الواتساب لو اتحدد لوحده — موبايل دايماً.
  final String? whatsapp;

  /// أكتر من موبايل ومفيش واحد مكتوب عليه «واتساب» → الإنسان بيختار بشريحة.
  final List<String> mobileChoices;

  /// مفيش واتساب ومفيش اختيار → الورقة بتسأل «عندك رقم واتساب…؟».
  bool get needsWhatsAppQuestion => whatsapp == null && mobileChoices.isEmpty;
}

/// القاعدة: الرقم اللي عليه «واتساب» لو موجود (ولو موبايل)؛ غير كده موبايل
/// واحد بالظبط؛ أكتر من موبايل = شرايح؛ **أرضي عمره ما يبقى واتساب**.
PharmacyNumbers choosePharmacyNumbers({String? whatsapp, List<String> phones = const []}) {
  final all = <String>[];
  for (final p in phones) {
    final n = normalizeEgyptPhone(p);
    if (n != null && !all.contains(n)) all.add(n);
  }
  final marked = whatsapp == null ? null : normalizeEgyptPhone(whatsapp);
  final markedMobile = marked != null && isEgyptMobile(marked) ? marked : null;
  final mobiles = [for (final n in all) if (isEgyptMobile(n)) n];

  // رقم الاتصال: أرضي لو فيه (الواتساب هيبقى الموبايل)، وإلا أول رقم
  final landlines = [for (final n in all) if (!isEgyptMobile(n)) n];
  final call = landlines.isNotEmpty ? landlines.first : (all.isNotEmpty ? all.first : markedMobile);

  if (markedMobile != null) return PharmacyNumbers(call: call, whatsapp: markedMobile);
  if (mobiles.length == 1) return PharmacyNumbers(call: call, whatsapp: mobiles.single);
  if (mobiles.length > 1) return PharmacyNumbers(call: call, mobileChoices: mobiles);
  return PharmacyNumbers(call: call);
}

String _western(String s) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  return s.split('').map((c) {
    final i = arabic.indexOf(c);
    if (i >= 0) return '$i';
    final j = persian.indexOf(c);
    return j >= 0 ? '$j' : c;
  }).join();
}
