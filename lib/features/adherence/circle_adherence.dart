import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/care/caregiver_remote.dart';
import '../../domain/adherence/adherence.dart';
import 'adherence_sources.dart';

/// عنوان الكارت عند العيلة والممرض — من غير «إنت»: بيتكلموا عن حد تاني.
const circleAdherenceTitle = 'ماشي إزاي الأسبوع ده';

/// الحساب من الصورة، ومعاه قرار الإخفاء (أول يومين).
Adherence? circleAdherence(CaregiverSnapshot? s, DateTime now) {
  if (s == null) return null;
  final doses = dosesFromSnapshot(s);
  if (!adherenceWorthShowing(firstDoseDay(doses), now)) return null;
  return adherenceFromSnapshot(s, now);
}

/// الحساب وهو بيتحدّث مع كل سحبة — لشاشة التفاصيل.
Stream<Adherence> circleAdherenceUpdates(Listenable holder, CaregiverSnapshot? Function() read) {
  late final StreamController<Adherence> c;
  void changed() {
    final a = circleAdherence(read(), DateTime.now());
    if (a != null) c.add(a);
  }

  c = StreamController<Adherence>.broadcast(
    onListen: () => holder.addListener(changed),
    onCancel: () => holder.removeListener(changed),
  );
  return c.stream;
}
