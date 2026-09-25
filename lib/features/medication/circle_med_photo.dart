import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../records/attachment_viewer.dart';

/// صورة الدوا عند العيلة والممرض — من الكاش (`CircleMedPhotoCache`)،
/// بتنزل أول ما الصف يتبني وبتتجدد لما النسخة في السحابة تتغيّر. أي عطل أو
/// مفيش صورة = [fallback]. الدوسة بتفتحها ملء الشاشة زي عند المريض.
class CircleMedPhotoThumb extends StatefulWidget {
  const CircleMedPhotoThumb({
    required this.patientUuid,
    required this.medicationUuid,
    required this.name,
    required this.fallback,
    this.size = 48,
    super.key,
  });

  final String patientUuid;
  final String medicationUuid;
  final String name;
  final Widget fallback;
  final double size;

  @override
  State<CircleMedPhotoThumb> createState() => _CircleMedPhotoThumbState();
}

class _CircleMedPhotoThumbState extends State<CircleMedPhotoThumb> {
  Future<File?>? _file;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _file ??= AppScope.maybeOf(context)?.circleMedPhotos?.fileFor(widget.patientUuid, widget.medicationUuid);
  }

  @override
  Widget build(BuildContext context) {
    final future = _file;
    if (future == null) return widget.fallback;
    return FutureBuilder<File?>(
      future: future,
      builder: (context, snap) {
        final file = snap.data;
        if (file == null) return widget.fallback;
        return Semantics(
          button: true,
          label: 'صورة ${widget.name} — افتحها كبيرة',
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('circle-med-photo-${widget.medicationUuid}'),
            borderRadius: BorderRadius.circular(F.radiusChip),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => AttachmentViewerScreen(file: file, title: widget.name),
            )),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(F.radiusChip),
              child: Image.file(
                file,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
                cacheWidth: (widget.size * 3).round(),
                errorBuilder: (_, _, _) => widget.fallback,
              ),
            ),
          ),
        );
      },
    );
  }
}
