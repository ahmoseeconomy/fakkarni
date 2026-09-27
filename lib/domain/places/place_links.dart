// روابط كارت «القريب مني» — دارت نقية، من غير أي مفتاح.


/// رقم موبايل مصري بالصيغة الدولية لـ`wa.me` — **موبايل بس**: ٠١٠/٠١١/٠١٢/٠١٥
/// وبعدها ٨ أرقام، بأي شكل كُتب بيه (+٢٠، ٠٠٢٠، ٢٠، مسافات وشرط). أرضي أو
/// رقم مش مصري = null، والزرار ما بيظهرش: واتساب على رقم أرضي باب مقفول.
String? egyptMobileWhatsApp(String raw) {
  var d = _western(raw).replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('0020')) d = d.substring(4);
  if (d.startsWith('20') && d.length == 12) d = d.substring(2);
  if (d.length == 10 && d.startsWith('1')) d = '0$d';
  if (!RegExp(r'^01[0125]\d{8}$').hasMatch(d)) return null;
  return '2$d';
}

Uri whatsAppUri(String number) => Uri.https('wa.me', '/$number');

/// «الطريق» — جوجل ماب بالاتجاهات لنقطة المكان. من غير مفتاح.
Uri googleDirectionsUri(double lat, double lon) =>
    Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lon');

/// البديل لو جوجل ماب ما اتفتحتش — خرايط أبل.
Uri appleDirectionsUri(double lat, double lon) => Uri.parse('https://maps.apple.com/?daddr=$lat,$lon');

String _western(String s) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  return s.split('').map((c) {
    final i = arabic.indexOf(c);
    return i >= 0 ? '$i' : c;
  }).join();
}
