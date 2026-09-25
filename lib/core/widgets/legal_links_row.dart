import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../legal/legal_links.dart';
import '../theme/tokens.dart';

/// «سياسة الخصوصية» و«الشروط» — نفس الصف في شاشة البداية والإعدادات.
///
/// المقاسات من برّه: عند المريض حدّ ١٧ و٥٦، وعند الابن كثافته هو — الويدجت
/// ما بيختارش تدرّج بنفسه.
class LegalLinksRow extends StatelessWidget {
  const LegalLinksRow({
    this.fontSize = F.minTextSize,
    this.minHeight = F.minTapTarget,
    super.key,
  });

  final double fontSize;
  final double minHeight;

  /// بيتبدّل في الاختبارات — الافتراضي بيفتح المتصفّح برّه التطبيق.
  static Future<void> Function(String url) open = _launch;

  static Future<void> _launch(String url) async {
    if (!legalUrlReady(url)) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: F.s8,
    children: [
      _link(
        key: const ValueKey('legal-privacy'),
        label: 'سياسة الخصوصية',
        url: privacyUrl,
      ),
      _link(key: const ValueKey('legal-terms'), label: 'الشروط', url: termsUrl),
    ],
  );

  // Material شفاف: الصف بيتحط في شاشات مالهاش Scaffold فوقه مباشرة
  Widget _link({
    required Key key,
    required String label,
    required String url,
  }) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      key: key,
      onTap: () => open(url),
      borderRadius: BorderRadius.circular(F.radiusCard),
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.symmetric(horizontal: F.s8),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            color: F.ink,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    ),
  );
}
