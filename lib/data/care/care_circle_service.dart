/// دائرة الرعاية — أول كتابة من التطبيق للسحابة.
///
/// الأدوار بتطلع من البيانات، مش من نوع الحساب: اللي استبدل كوداً بقى
/// مقدّم رعاية للمريض ده، واللي عنده صف مريض محلي هو المريض. مفيش عمود
/// «دور» في أي مكان.
library;

import '../../domain/care/follower_profile.dart';
import '../../domain/care/follower_role.dart';

/// كود دعوة حي — ٦ أرقام، صالح ربع ساعة.
class InviteCode {
  const InviteCode({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;
}

enum CareCircleFailure {
  /// غلط أو محروق أو خلّص وقته — رسالة واحدة عشان ما نساعدش التخمين.
  invalidOrExpiredCode,

  /// بيحاول يستبدل كود نفسه.
  ownCode,

  alreadyLinked,
  offline,
  other,
}

class CareCircleException implements Exception {
  const CareCircleException(this.failure, [this.cause]);

  final CareCircleFailure failure;
  final Object? cause;

  /// عربي محدد — رمز السيرفر عمره ما يوصل للشاشة.
  String get message => switch (failure) {
        CareCircleFailure.invalidOrExpiredCode =>
          'الكود مش مضبوط أو خلّص وقته',
        CareCircleFailure.ownCode =>
          'ده الكود بتاعك انت — الكود ده يكتبه ابنك على موبايله هو.',
        CareCircleFailure.alreadyLinked => 'انتو مربوطين خلاص. كله تمام.',
        CareCircleFailure.offline =>
          'مفيش نت. التطبيق شغّال عادي، بس الربط محتاج اتصال.',
        CareCircleFailure.other => 'مقدرناش نكمّل. جرّب تاني.',
      };

  @override
  String toString() => 'CareCircleException($failure${cause == null ? '' : '، $cause'})';
}

/// العقد — Supabase في lib/data/care/ والشاشات ما تعرفش غير ده.
abstract interface class CareCircleService {
  /// بيرفع صف المريض وبس — uuid واسم. أول وآخر مزامنة في الجولة دي؛
  /// الأدوية والباقي جولة 3.4.
  Future<void> upsertPatient({required String uuid, required String name});

  /// بيطلب كوداً جديداً — القديم غير المستخدم بيموت على السيرفر.
  Future<InviteCode> createInvite(String patientUuid);

  /// بيستبدل الكود وبيرجّع **اسم** المريض اللي اتربط بيه — للشاشة.
  Future<String> redeemInvite(String code);
}

/// متابع واحد بدوره وصلاحياته — من `followers_with_permissions` (للمالك بس).
class FollowerWithPermissions {
  const FollowerWithPermissions({
    required this.caregiverId,
    required this.profile,
    required this.permissions,
    this.linkedAt,
  });

  final String caregiverId;

  /// null = ما كتبش اسمه لسه.
  final FollowerProfile? profile;
  final FollowerPermissions permissions;
  final DateTime? linkedAt;

  String get displayName => profile?.name.trim().isNotEmpty == true ? profile!.name.trim() : 'من غير اسم لسه';
}

/// إدارة الدائرة من موبايل المريض (٠٠٢٣): كود بدور، والأدوار والصلاحيات
/// والشيل. واجهة لوحدها عشان الفيكات القديمة لـ[CareCircleService] ما تتكسرش.
abstract interface class CareCircleAdmin {
  Future<InviteCode> createRoleInvite(String patientUuid, FollowerRole role);

  Future<List<FollowerWithPermissions>> followersWithPermissions(String patientUuid);

  Future<void> setFollowerPermissions(
    String patientUuid,
    String caregiverId,
    FollowerPermissions permissions,
  );

  Future<void> removeFollower(String patientUuid, String caregiverId);
}
