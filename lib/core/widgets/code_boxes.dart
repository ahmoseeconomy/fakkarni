import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format/arabic_time.dart' show arabicDigits;
import '../theme/tokens.dart';

/// **الكود في ست خانات** — نفس الشكل وهو بيتكتب ووهو بيتعرض.
///
/// **حقل واحد مخفي ورا ست خانات ظاهرة**, مش ست حقول: ده اللي بيخلّي
/// الكيبورد والرجوع واللصق وملء «الكود من الرسايل» على iOS يشتغلوا زي ما
/// النظام عارفهم — الانتقال للخانة الجاية والرجوع بالمسح بيحصلوا لوحدهم
/// لأن المؤشر دايماً في آخر النص، ولصق ٦ أرقام بيملا الست مرة واحدة.
///
/// - الأرقام **من الشمال لليمين** حتى في الواجهة العربية — الكود بيتقرا
///   رقم رقم في التليفون، والترتيب لازم يبقى واحد عند الاتنين.
/// - بيقبل الأرقام العربي والغربي؛ اللي بيطلع لـ[onChanged] غربي دايماً
///   (السيرفر عايز 0-9)، واللي بيتعرض عربي زي باقي التطبيق.
/// - [onCompleted] بيتنده مع الرقم السادس — الإرسال من غير دوسة زيادة.
/// - [readOnly]: الكود اللي المريض عمله، في نفس الخانات.
class CodeBoxes extends StatefulWidget {
  const CodeBoxes({
    this.value,
    this.onChanged,
    this.onCompleted,
    this.readOnly = false,
    this.autofocus = true,
    this.enabled = true,
    super.key,
  });

  static const length = 6;

  /// للعرض بس ([readOnly]) — الكود بأرقام غربية.
  final String? value;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final bool readOnly;
  final bool autofocus;
  final bool enabled;

  /// العربي-الهندي → غربي، وأي حاجة مش رقم بتتشال.
  static String normalize(String raw) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final out = StringBuffer();
    for (final rune in raw.runes) {
      final ch = String.fromCharCode(rune);
      final i = arabic.indexOf(ch);
      if (i >= 0) {
        out.write(i);
      } else if (rune >= 0x30 && rune <= 0x39) {
        out.write(ch);
      }
    }
    return out.toString();
  }

  @override
  State<CodeBoxes> createState() => _CodeBoxesState();
}

class _CodeBoxesState extends State<CodeBoxes> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _completedFor;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _digits => widget.readOnly ? CodeBoxes.normalize(widget.value ?? '') : _controller.text;

  void _changed(String raw) {
    final digits = CodeBoxes.normalize(raw);
    final clipped = digits.length > CodeBoxes.length ? digits.substring(0, CodeBoxes.length) : digits;
    if (clipped != raw) {
      _controller.value = TextEditingValue(text: clipped, selection: TextSelection.collapsed(offset: clipped.length));
    }
    setState(() {});
    widget.onChanged?.call(clipped);
    if (clipped.length == CodeBoxes.length) {
      if (_completedFor != clipped) {
        _completedFor = clipped;
        widget.onCompleted?.call(clipped);
      }
    } else {
      _completedFor = null;
    }
  }

  /// ضغطة طويلة على الخانات = لصق — الحقل المخفي مالوش قايمة لصق ظاهرة.
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null) return;
    _controller.text = text;
    _changed(text);
  }

  @override
  Widget build(BuildContext context) {
    final digits = _digits;
    final active = widget.readOnly || !_focus.hasFocus ? -1 : digits.length.clamp(0, CodeBoxes.length - 1);
    final boxes = LayoutBuilder(
      builder: (context, constraints) {
        const spacing = F.s8;
        final width = ((constraints.maxWidth - spacing * (CodeBoxes.length - 1)) / CodeBoxes.length).clamp(36.0, 60.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < CodeBoxes.length; i++) ...[
              if (i > 0) const SizedBox(width: spacing),
              Container(
                key: ValueKey('code-box-$i'),
                width: width,
                height: width * 1.2,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: F.fieldGround,
                  borderRadius: BorderRadius.circular(F.s10),
                  border: Border.all(
                    color: i == active ? F.green : F.line,
                    width: i == active ? 2.5 : 1.5,
                  ),
                ),
                // الرقم بيكبر لحد حجم الخانة وبيصغر معاها — تكبير الخط ما يفيضش
                child: Padding(
                  padding: const EdgeInsets.all(F.s4),
                  child: FittedBox(
                    child: Text(
                      i < digits.length ? arabicDigits(digits[i]) : '',
                      style: TextStyle(
                        fontSize: F.bigTimeSize,
                        fontWeight: FontWeight.w700,
                        color: widget.readOnly ? F.greenDeep : F.ink,
                        fontFamily: F.monoFamily,
                        fontFamilyFallback: F.monoFallback,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );

    final readable = Semantics(
      label: widget.readOnly ? 'الكود ${arabicDigits(digits)}' : 'خانات الكود',
      value: arabicDigits(digits),
      excludeSemantics: true,
      child: boxes,
    );

    if (widget.readOnly) {
      return Directionality(textDirection: TextDirection.ltr, child: readable);
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? () => _focus.requestFocus() : null,
        onLongPress: widget.enabled ? _paste : null,
        child: Stack(
          alignment: Alignment.center,
          children: [
            readable,
            // الحقل الحقيقي — شفّاف، والخانات هي اللي بتتشاف
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  key: const ValueKey('code-field'),
                  controller: _controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  autofocus: widget.autofocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  showCursor: false,
                  enableInteractiveSelection: false,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩]'))],
                  onChanged: _changed,
                  decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
