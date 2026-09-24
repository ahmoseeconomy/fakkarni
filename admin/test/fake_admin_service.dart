import 'package:fakkarni_admin/data/admin_models.dart';
import 'package:fakkarni_admin/data/admin_service.dart';

/// مزيّف بالواجهة — نفس شكل `FakeCaregiverRemote` في التطبيق. مفيش
/// `supabase_flutter` في أي اختبار.
class FakeAdminService implements AdminService {
  FakeAdminService({
    this.counts_ = AdminCounts.empty,
    this.accounts_ = const [],
    this.followers_ = const [],
    this.escalations_ = const [],
    this.devices_ = const [],
  });

  AdminCounts counts_;
  List<AdminAccount> accounts_;
  List<AdminFollower> followers_;
  List<AdminEscalation> escalations_;
  List<AdminDevice> devices_;

  AdminException? signInFailure;
  AdminException? countsFailure;
  AdminException? panelFailure;

  String? email;
  int signInCalls = 0;
  int signOutCalls = 0;
  int countsCalls = 0;
  int accountCalls = 0;
  final List<String> opened = [];

  @override
  String? get currentEmail => email;

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    final failure = signInFailure;
    if (failure != null) throw failure;
    this.email = email;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    email = null;
  }

  @override
  Future<AdminCounts> counts() async {
    countsCalls++;
    final failure = countsFailure;
    if (failure != null) throw failure;
    return counts_;
  }

  @override
  Future<List<AdminAccount>> accounts() async {
    accountCalls++;
    final failure = countsFailure;
    if (failure != null) throw failure;
    return accounts_;
  }

  @override
  Future<List<AdminDevice>> devices() async {
    final failure = countsFailure;
    if (failure != null) throw failure;
    return devices_;
  }

  @override
  Future<List<AdminFollower>> followers(String patientUuid) async {
    opened.add(patientUuid);
    final failure = panelFailure;
    if (failure != null) throw failure;
    return followers_;
  }

  @override
  Future<List<AdminEscalation>> escalations(String patientUuid, {int limit = 20}) async {
    final failure = panelFailure;
    if (failure != null) throw failure;
    return escalations_;
  }
}

/// حساب بأقل قدر من الكتابة — كل اختبار بيغيّر حاجة واحدة.
AdminAccount account({
  String uuid = 'p1',
  String name = 'الحاج عاشور',
  DateTime? seenAt,
  DateTime? lastSyncAt,
  int missed = 0,
  int pending = 0,
  int week = 0,
  int followers = 0,
  int invites = 0,
  String? battery = 'unrestricted',
  bool horizonOk = true,
  String? platform = 'android',
  String? appVersion = '1.0.0+1',
}) =>
    AdminAccount(
      patientUuid: uuid,
      patientName: name,
      createdAt: DateTime(2026, 9, 1),
      followersCount: followers,
      pendingInvites: invites,
      lastSyncAt: lastSyncAt,
      missedDoses24h: missed,
      pendingEscalations: pending,
      escalations7d: week,
      platform: platform,
      appVersion: appVersion,
      batteryState: battery,
      reminderHorizonOk: horizonOk,
      seenAt: seenAt,
    );

AdminDevice device({
  String uuid = 'p1',
  String name = 'الحاج عاشور',
  String install = 'install-a',
  DateTime? checkedAt,
  List<String> codes = const [],
  DateTime? lastSyncAt,
  String? platform = 'android',
  String? appVersion = '1.0.0+1',
}) =>
    AdminDevice(
      patientUuid: uuid,
      patientName: name,
      installId: install,
      checkedAt: checkedAt,
      failingCodes: codes,
      lastSyncAt: lastSyncAt,
      platform: platform,
      appVersion: appVersion,
    );
