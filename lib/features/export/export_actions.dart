import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

/// اللي بيلمس الجهاز في الاستخراج — واجهة عشان الشاشات تتختبر من غير إضافات.
abstract interface class ExportActions {
  /// صفحات **الملف نفسه** كصور PNG — مش واجهة شبهه.
  Stream<Uint8List> rasterize(Uint8List pdf);

  /// بيحفظ الملف على الموبايل وبيرجّع مساره.
  Future<String> save(Uint8List pdf, String filename);

  /// بيفتح قايمة المشاركة. false = ما اتفتحتش.
  Future<bool> share(Uint8List pdf, String filename);

  Future<bool> print(Uint8List pdf, String name);
}

class DeviceExportActions implements ExportActions {
  const DeviceExportActions();

  @override
  Stream<Uint8List> rasterize(Uint8List pdf) => Printing.raster(pdf, dpi: 110).asyncMap((page) => page.toPng());

  @override
  Future<String> save(Uint8List pdf, String filename) async {
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'exports'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(pdf, flush: true);
    return file.path;
  }

  @override
  Future<bool> share(Uint8List pdf, String filename) => Printing.sharePdf(bytes: pdf, filename: filename);

  @override
  Future<bool> print(Uint8List pdf, String name) => Printing.layoutPdf(onLayout: (_) async => pdf, name: name);
}
