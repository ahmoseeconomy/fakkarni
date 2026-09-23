import 'admin_models.dart';

/// اللي اللوحة محتاجاه من السحابة — **الواجهة، مش الحزمة**. نفس قاعدة
/// `AuthService` في التطبيق: `supabase_flutter` بيتستورد في ملف واحد
/// (`supabase_admin_service.dart`) وبس، والاختبارات بتشتغل على مزيّف.
abstract interface class AdminService {
  /// إيميل الجلسة الحالية — null يعني مفيش دخول.
  String? get currentEmail;

  Future<void> signIn({required String email, required String password});
  Future<void> signOut();

  Future<AdminCounts> counts();
  Future<List<AdminAccount>> accounts();
  Future<List<AdminFollower>> followers(String patientUuid);
  Future<List<AdminEscalation>> escalations(String patientUuid, {int limit = 20});
}

enum AdminFailure {
  /// دخل بحساب حقيقي، بس مش في `private.admins` (أو الجلسة مجهولة).
  notAdmin,
  badCredentials,
  offline,
  other,
}

class AdminException implements Exception {
  const AdminException(this.failure, [this.cause]);

  final AdminFailure failure;
  final Object? cause;

  /// **نص السيرفر عمره ما يتعرض** — أربع جمل متفق عليها وبس.
  String get message => switch (failure) {
        AdminFailure.notAdmin => 'الحساب ده مش أدمن.',
        AdminFailure.badCredentials => 'الإيميل أو الباسورد غلط.',
        AdminFailure.offline => 'مفيش نت. جرّب تاني لما يرجع.',
        AdminFailure.other => 'مقدرناش نكمّل. جرّب تاني.',
      };

  @override
  String toString() => 'AdminException($failure${cause == null ? '' : '، $cause'})';
}
