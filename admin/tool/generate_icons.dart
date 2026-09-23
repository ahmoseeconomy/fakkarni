// ignore_for_file: avoid_print
//
// Generates every web icon of the admin dashboard from the official logo tile.
//
//   dart run tool/generate_icons.dart      (from admin/)
//
// Source: assets/branding/logo_tile.png — 1024×1024, used as-is (no recolour,
// no crop, no redraw). Plain icons are straight resizes; the maskable ones
// put the tile in the 80% safe zone on the tile's OWN green (#0A4638), so the
// padding is invisible — a different green, even by four units, draws a
// square inside the circle Android cuts.

import 'dart:io';

import 'package:image/image.dart' as img;

const source = 'assets/branding/logo_tile.png';
const brandGreen = (0x0A, 0x46, 0x38);

void main() {
  final tile = img.decodePng(File(source).readAsBytesSync());
  if (tile == null) {
    stderr.writeln('cannot decode $source');
    exit(1);
  }
  final corner = tile.getPixel(0, 0);
  if ((corner.r, corner.g, corner.b) != brandGreen) {
    stderr.writeln('tile corner is not #0A4638 — the maskable padding would show');
    exit(1);
  }

  void plain(String path, int size) {
    final out = img.copyResize(tile, width: size, height: size,
        interpolation: img.Interpolation.cubic);
    File(path).writeAsBytesSync(img.encodePng(out));
    print('$path  ${size}x$size');
  }

  void maskable(String path, int size) {
    final canvas = img.Image(width: size, height: size, numChannels: 3);
    img.fill(canvas, color: img.ColorRgb8(brandGreen.$1, brandGreen.$2, brandGreen.$3));
    final inner = (size * 0.8).round();
    final scaled = img.copyResize(tile, width: inner, height: inner,
        interpolation: img.Interpolation.cubic);
    final offset = (size - inner) ~/ 2;
    img.compositeImage(canvas, scaled, dstX: offset, dstY: offset);
    File(path).writeAsBytesSync(img.encodePng(canvas));
    print('$path  ${size}x$size (maskable, 80% safe zone)');
  }

  plain('web/favicon.png', 32);
  plain('web/favicon-16.png', 16);
  plain('web/apple-touch-icon.png', 180);
  plain('web/icons/Icon-192.png', 192);
  plain('web/icons/Icon-512.png', 512);
  maskable('web/icons/Icon-maskable-192.png', 192);
  maskable('web/icons/Icon-maskable-512.png', 512);
}
