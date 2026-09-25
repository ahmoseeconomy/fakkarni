// «فلان خرج من الدايرة» — دارت نقية.
//
// بيتكتب لما متابع أو ممرض يمسح حسابه (0033). الأب بيقراه على «يومك»،
// والباقيين في «الجديد». نفس الجملة في المكانين.

import 'follower_profile.dart';

/// سطر خروج واحد زي ما السحابة كتبته.
class CircleDeparture {
  const CircleDeparture({
    required this.uuid,
    required this.leftAt,
    this.displayName,
    this.relation,
    this.nurse = false,
  });

  final String uuid;
  final DateTime leftAt;

  /// اللي هو كتبه عن نفسه — null لو ما كتبش، ومفيش اسم بيتخترع.
  final String? displayName;
  final FollowerRelation? relation;
  final bool nurse;

  factory CircleDeparture.fromRow(Map<String, dynamic> row) => CircleDeparture(
        uuid: row['uuid'] as String,
        leftAt: DateTime.parse(row['left_at'] as String).toLocal(),
        displayName: row['display_name'] as String?,
        relation: FollowerRelation.fromStored(row['relation'] as String?),
        nurse: row['role'] == 'nurse',
      );
}

/// الجملة. **الفعل بيمشي مع الصلة مش مع الاسم** — «خرجت» للبنت بس، زي
/// `followerLine`: الاسم ما بيقولش ولد ولا بنت.
String departureLine(CircleDeparture d) {
  final name = d.displayName?.trim() ?? '';
  final verb = d.relation == FollowerRelation.daughter ? 'خرجت' : 'خرج';
  if (name.isNotEmpty) return '$name $verb من الدايرة';
  if (d.nurse) return 'الممرض أو المرافق خرج من الدايرة';
  return 'حد من اللي بيتابعوك $verb من الدايرة';
}
