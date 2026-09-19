import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/repositories/emergency_repository.dart';

/// «عدّل بيانات الطوارئ» — الطريق الوحيد اللي بيملا الجدول: بإيد إنسان.
///
/// شاشة عادية (عاجي، مش أحمر): دي استمارة، مش طوارئ. فصيلة الدم ٨ شرايح
/// + «مش عارف» (= null). الحساسية والأمراض نص حر زي ما الدكتور قالها.
/// الفاضي بيتحفظ فاضي ويبان «لسه ما اتملاش» — «مفيش» لازم حد يكتبها.
class EmergencyEditScreen extends StatefulWidget {
  const EmergencyEditScreen({this.focusContacts = false, super.key});

  /// جاي من «ضيف جهة اتصال» على شاشة المعلومات: بيفتح على قسم جهات الاتصال
  /// وصف فاضي جاهز. من غير كده المستخدم بيقع على أول الشاشة (فصيلة الدم)
  /// ولازم يدوّر على اللي جه عشانه.
  final bool focusContacts;

  @override
  State<EmergencyEditScreen> createState() => _EmergencyEditScreenState();
}

class _ContactFields {
  bool get isBlank =>
      name.text.trim().isEmpty && phone.text.trim().isEmpty && relation.text.trim().isEmpty;

  _ContactFields([EmergencyContact? c])
    : name = TextEditingController(text: c?.name),
      phone = TextEditingController(text: c?.phone),
      relation = TextEditingController(text: c?.relation);

  final TextEditingController name, phone, relation;

  void dispose() {
    name.dispose();
    phone.dispose();
    relation.dispose();
  }
}

class _EmergencyEditScreenState extends State<EmergencyEditScreen> {
  final _allergies = TextEditingController();
  final _chronic = TextEditingController();
  final List<_ContactFields> _contacts = [];

  /// مكان قسم جهات الاتصال — عشان نبعت الشاشة له لما نيجي منه.
  final _contactsKey = GlobalKey();
  String? _blood;
  bool _loaded = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final services = AppScope.of(context);
    EmergencyRepository(services.db).get(services.patientId).then((info) {
      if (!mounted) return;
      setState(() {
        _blood = info.bloodType;
        _allergies.text = info.allergies ?? '';
        _chronic.text = info.chronicConditions ?? '';
        _contacts.addAll([for (final c in info.contacts) _ContactFields(c)]);
        // جاي يضيف واحدة — فالصف جاهز، مش محتاج يدوس «+» تاني
        if (widget.focusContacts && _contacts.isEmpty) _contacts.add(_ContactFields());
      });
      if (widget.focusContacts) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final target = _contactsKey.currentContext;
          if (target != null) Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 250));
        });
      }
    });
  }

  @override
  void dispose() {
    _allergies.dispose();
    _chronic.dispose();
    for (final c in _contacts) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final services = AppScope.of(context);
    await EmergencyRepository(services.db).save(
      services.patientId,
      EmergencyInfo(
        bloodType: _blood,
        allergies: _allergies.text,
        chronicConditions: _chronic.text,
        contacts: [
          // صف فاضي خالص مش جهة اتصال — بيتشال بدل ما يتحفظ باسم فاضي وزرار
          // «اتصال» بيدوّر على لا حاجة. (نفس قاعدة «ما بنملاش حقل لوحدنا».)
          for (final c in _contacts)
            if (!c.isBlank)
              EmergencyContact(
                name: c.name.text,
                phone: c.phone.text,
                relation: c.relation.text,
              ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  InputDecoration _field(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
    hintStyle: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
    filled: true,
    fillColor: F.fieldGround,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(F.radiusCard),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final body = TextStyle(fontSize: F.minBodySize, color: F.ink);
    return Scaffold(
      appBar: AppBar(title: const Text('بيانات الطوارئ')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.s30),
        children: [
          Text(
            'اكتبها زي ما الدكتور أو التحليل قالها. اللي تسيبه فاضي هيبان «لسه ما اتملاش».',
            style: TextStyle(
              fontSize: F.minTextSize,
              color: F.mutedDark,
              height: 1.5,
            ),
          ),
          const SizedBox(height: F.gap),
          const SectionHead('فصيلة الدم'),
          const SizedBox(height: F.s8),
          Wrap(
            spacing: F.s8,
            runSpacing: F.s8,
            children: [
              for (final t in bloodTypes)
                SizedBox(
                  width: 76,
                  child: AnchorChip(
                    label: t,
                    selected: _blood == t,
                    onTap: () => setState(() => _blood = t),
                  ),
                ),
              AnchorChip(
                label: 'مش عارف',
                selected: _blood == null,
                onTap: () => setState(() => _blood = null),
              ),
            ],
          ),
          const SizedBox(height: F.gap),
          TextField(
            key: const ValueKey('allergies'),
            controller: _allergies,
            style: body,
            maxLines: null,
            decoration: _field('الحساسية', hint: 'مثلاً: بنسلين'),
          ),
          const SizedBox(height: F.s12),
          TextField(
            key: const ValueKey('chronic'),
            controller: _chronic,
            style: body,
            maxLines: null,
            decoration: _field('الأمراض المزمنة', hint: 'مثلاً: سكر، ضغط'),
          ),
          const SizedBox(height: F.gap),
          SectionHead('جهات الاتصال', key: _contactsKey),
          const SizedBox(height: F.s4),
          Text(
            'الأرقام دي على الموبايل ده بس — مش بتتبعت لأي حد.',
            style: TextStyle(
              fontSize: F.minTextSize,
              color: F.mutedDark,
              height: 1.5,
            ),
          ),
          for (final (i, c) in _contacts.indexed)
            FCard(
              key: ValueKey('contact-$i'),
              child: Column(
                children: [
                  TextField(
                    controller: c.name,
                    style: body,
                    decoration: _field('الاسم'),
                  ),
                  const SizedBox(height: F.s8),
                  TextField(
                    controller: c.phone,
                    style: body,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: _field('الرقم'),
                  ),
                  const SizedBox(height: F.s8),
                  TextField(
                    controller: c.relation,
                    style: body,
                    decoration: _field(
                      'صلة القرابة',
                      hint: 'ابني، بنتي، دكتوري…',
                    ),
                  ),
                  const SizedBox(height: F.s8),
                  FSecondaryButton(
                    label: 'شيل جهة الاتصال دي',
                    onPressed: () =>
                        setState(() => _contacts.removeAt(i).dispose()),
                  ),
                ],
              ),
            ),
          const SizedBox(height: F.s8),
          FSecondaryButton(
            label: '+ ضيف جهة اتصال',
            onPressed: () => setState(() => _contacts.add(_ContactFields())),
          ),
          const SizedBox(height: F.gap),
          FPrimaryButton(label: 'احفظ', onPressed: _saving ? null : _save),
        ],
      ),
    );
  }
}
