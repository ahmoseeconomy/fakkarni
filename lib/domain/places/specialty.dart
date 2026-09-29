// تخصصات الدكاترة في «القريب مني» و«كلّمني» — دارت نقية.
//
// **مفيش مصدر بيقول التخصص بالتأكيد**: OSM عنده وسم اختياري
// `healthcare:speciality` (قيم إنجليزي زي `ophthalmology`، وممكن كذا واحدة
// بـ`;`)، وخرايط أبل ما بتدّيش تخصص خالص. فالمطابقة على الاتنين: الوسم لو
// موجود، **أو** كلمة في الاسم («عيادة د. أحمد للعيون»، «Dental Clinic»).
// دكتور من غير وسم ولا كلمة في اسمه ما بيظهرش تحت أي تخصص — ما بنخمّنش.

import '../voice/nlu/normalize.dart';

enum Specialty {
  eyes('عيون', osm: {'ophthalmology', 'optometry'}, words: {'عنين', 'العنين', 'عيون', 'العيون', 'رمد', 'الرمد', 'بصريات', 'eye', 'eyes', 'ophthalmology', 'optical', 'vision'}),
  internal('باطنة', osm: {'internal', 'general_internal_medicine', 'gastroenterology'}, words: {'بطنه', 'البطنه', 'باطني', 'الباطني', 'بطن', 'البطن', 'هضمي', 'هضم', 'معده', 'المعده', 'باطنه', 'الباطنه', 'باطنيه', 'جهاز هضمي', 'internal', 'gastro'}),
  dental('أسنان', osm: {'dentistry', 'dental_surgery', 'orthodontics', 'dental'}, words: {'ضروس', 'الضروس', 'ضرس', 'تقويم', 'سنانه', 'اسنان', 'الاسنان', 'سنان', 'dental', 'dentist', 'dentistry', 'teeth', 'orthodontic'}),
  children('أطفال', osm: {'paediatrics', 'pediatrics'}, words: {'عيال', 'العيال', 'طفل', 'اطفالي', 'اطفال', 'الاطفال', 'pediatric', 'paediatric', 'kids', 'children'}),
  bones('عظام', osm: {'orthopaedics', 'orthopedics', 'orthopaedic_surgery'}, words: {'عضام', 'العضام', 'العضم', 'عظم', 'كسور', 'الكسور', 'عظام', 'العظام', 'عضم', 'ortho', 'orthopedic', 'orthopaedic', 'bones'}),
  skin('جلدية', osm: {'dermatology', 'dermatovenereology'}, words: {'جلدي', 'الجلد', 'جلديه', 'الجلديه', 'جلد', 'تناسليه', 'derma', 'dermatology', 'skin'}),
  women('نسا وتوليد', osm: {'gynaecology', 'gynecology', 'obstetrics'}, words: {'نسائيه', 'ولاده', 'الولاده', 'حوامل', 'الحوامل', 'نسا', 'النسا', 'نساء', 'توليد', 'التوليد', 'gyn', 'gynecology', 'gynaecology', 'obstetrics', 'women'}),
  heart('قلب', osm: {'cardiology', 'cardiac_surgery'}, words: {'قلبيه', 'قلب', 'القلب', 'اوعيه', 'cardio', 'cardiology', 'heart'}),
  ent('أنف وأذن', osm: {'otolaryngology', 'ent'}, words: {'الاذن', 'ودن', 'الودن', 'ودان', 'الودان', 'زور', 'الزور', 'الحنجره', 'انف', 'الانف', 'اذن', 'حنجره', 'ent', 'otolaryngology'}),
  neuro('مخ وأعصاب', osm: {'neurology', 'neurosurgery'}, words: {'المخ', 'مخ', 'اعصاب', 'الاعصاب', 'neuro', 'neurology', 'neurosurgery'}),
  urology('مسالك', osm: {'urology'}, words: {'بروستاتا', 'البروستاتا', 'مسالك', 'المسالك', 'بوليه', 'uro', 'urology'}),
  kidney('كلى', osm: {'nephrology'}, words: {'كلاوي', 'الكلاوي', 'كلي', 'الكلي', 'nephro', 'nephrology', 'kidney'}),
  chest('صدر', osm: {'pulmonology', 'pneumology'}, words: {'صدر', 'الصدر', 'صدريه', 'chest', 'pulmonology'}),
  diabetes('سكر وغدد', osm: {'endocrinology', 'diabetology'}, words: {'سكري', 'السكري', 'غده', 'سكر', 'السكر', 'غدد', 'الغدد', 'endocrine', 'endocrinology', 'diabetes'}),
  psych('نفسي', osm: {'psychiatry'}, words: {'نفساني', 'النفساني', 'نفسانيه', 'نفسي', 'نفسيه', 'psychiatry', 'psychiatric'}),
  rheumatology('روماتيزم', osm: {'rheumatology'}, words: {'روماتزم', 'الروماتزم', 'روماتيزم', 'الروماتيزم', 'rheumatology'});

  const Specialty(this.label, {required this.osm, required this.words});

  /// الكلمة على الشريحة والكارت.
  final String label;

  /// قيم `healthcare:speciality` في OSM.
  final Set<String> osm;

  /// كلمات بعد التطبيع — في الاسم أو في الكلام.
  final Set<String> words;

  /// «دكتور عيون» — للجمل.
  String get doctorWord => 'دكتور $label';
}

List<String> _tokens(String text) => utteranceTokens(normalizeUtterance(text.toLowerCase()));

/// كلمة اتقالت («رمد»، «أسنان») ← التخصص. null = مش تخصص.
Specialty? specialtyFromWord(String word) {
  final w = normalizeUtterance(word.toLowerCase());
  for (final s in Specialty.values) {
    if (s.words.contains(w)) return s;
  }
  return null;
}

/// أول تخصص في جملة — «أقرب دكتور عيون» ← عيون.
Specialty? specialtyInText(String text) {
  for (final t in _tokens(text)) {
    final s = specialtyFromWord(t);
    if (s != null) return s;
  }
  return null;
}

/// تخصصات المكان: من وسم OSM (`a;b`) **ومن كلمات اسمه**.
Set<Specialty> specialtiesOf({String? osmSpeciality, String? name}) {
  final out = <Specialty>{};
  for (final raw in (osmSpeciality ?? '').toLowerCase().split(RegExp(r'[;,]'))) {
    final v = raw.trim();
    if (v.isEmpty) continue;
    for (final s in Specialty.values) {
      if (s.osm.contains(v)) out.add(s);
    }
  }
  if (name != null) {
    final tokens = _tokens(name.replaceAll(RegExp(r'[-_/()]'), ' '));
    // «للعيون» / «لطب الأسنان» — حرف الجر ملزوق في الكلمة
    final forms = {for (final t in tokens) ...{t, if (t.startsWith('لل')) t.substring(2), if (t.startsWith('لل')) 'ال${t.substring(2)}'}};
    for (final s in Specialty.values) {
      if (forms.any(s.words.contains)) out.add(s);
    }
  }
  return out;
}
