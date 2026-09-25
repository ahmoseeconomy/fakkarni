import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../../data/care/care_circle_service.dart';
import '../../domain/care/follower_role.dart';

/// **«اللي بيتابعوك»** — المريض بيشوف كل واحد بدوره، ويغيّر الدور، ويفتح
/// «يعدّل الأدوية»، ويشيل. الكتابة كلها دوال على السيرفر للمالك بس (٠٠٢٣).
class FollowersScreen extends StatefulWidget {
  const FollowersScreen({required this.admin, required this.patientUuid, super.key});

  final CareCircleAdmin admin;
  final String patientUuid;

  @override
  State<FollowersScreen> createState() => _FollowersScreenState();
}

class _FollowersScreenState extends State<FollowersScreen> {
  List<FollowerWithPermissions>? _rows;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.admin.followersWithPermissions(widget.patientUuid);
      if (mounted) setState(() => _rows = rows);
    } on CareCircleException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'مقدرناش نكمّل. جرّب تاني.');
    }
  }

  Future<void> _write(Future<void> Function() body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
      await _load();
    } on CareCircleException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'مقدرناش نكمّل. جرّب تاني.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setRole(FollowerWithPermissions f, FollowerRole role) => _write(() => widget.admin.setFollowerPermissions(
        widget.patientUuid,
        f.caregiverId,
        FollowerPermissions(
          role: role,
          // الدور بيجيب صلاحية التأكيد معاه: ممرض بيأكّد، متابع لأ
          canConfirm: role.confirmsByDefault,
          canEditMeds: f.permissions.canEditMeds,
        ),
      ));

  Future<void> _setEditMeds(FollowerWithPermissions f, bool on) => _write(() => widget.admin.setFollowerPermissions(
        widget.patientUuid,
        f.caregiverId,
        FollowerPermissions(
          role: f.permissions.role,
          canConfirm: f.permissions.canConfirm,
          canEditMeds: on,
        ),
      ));

  Future<void> _remove(FollowerWithPermissions f) async {
    final yes = await FSheet.show<bool>(
      context,
      title: 'تشيل ${f.displayName}؟',
      children: [
        Text(
          'مش هيشوف أدويتك ولا يوصله تنبيه تاني. لو غيّرت رأيك، كود جديد بيرجّعه.',
          style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6),
        ),
        const SizedBox(height: F.gap),
        FPrimaryButton(
          key: const ValueKey('follower-remove-confirm'),
          label: 'أيوه، شيله',
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: F.s8),
        FSecondaryButton(label: 'لأ، سيبه', onPressed: () => Navigator.of(context).pop(false)),
      ],
    );
    if (yes != true) return;
    await _write(() => widget.admin.removeFollower(widget.patientUuid, f.caregiverId));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: const Text('عيلتك أو ممرضك')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(F.gap, F.s4, F.gap, F.s30),
        children: [
          Text(
            'المتابع بيشوف وبيتنبّه. الممرض / المرافق بيشوف يومك زي ما إنت بتشوفه وبيقدر يأكّد الجرعة بدالك. '
            'تعديل الأدوية مقفول لحد ما تفتحه إنت.',
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.6),
          ),
          const SizedBox(height: F.gap),
          if (_error case final e?) ...[
            FCard(tone: FCardTone.warm, child: Text(e, style: TextStyle(fontSize: F.minBodySize, color: F.ink))),
            const SizedBox(height: F.s12),
          ],
          if (rows == null && _error == null)
            Center(child: CircularProgressIndicator(color: F.green))
          else if (rows != null && rows.isEmpty)
            Text(
              'مفيش حد من عيلتك أو ممرضك لسه — اعمل كود من «دائرة الرعاية».',
              key: const ValueKey('followers-empty'),
              style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6),
            )
          else
            for (final f in rows ?? const <FollowerWithPermissions>[])
              Padding(
                padding: const EdgeInsets.only(bottom: F.s12),
                child: FCard(
                  key: ValueKey('follower-${f.caregiverId}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        f.profile?.title ?? f.displayName,
                        style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
                      ),
                      const SizedBox(height: F.s10),
                      Row(
                        children: [
                          for (final role in FollowerRole.values) ...[
                            Expanded(
                              child: AnchorChip(
                                key: ValueKey('follower-role-${f.caregiverId}-${role.name}'),
                                label: role.label,
                                selected: f.permissions.role == role,
                                onTap: () {
                                  if (_busy || f.permissions.role == role) return;
                                  _setRole(f, role);
                                },
                              ),
                            ),
                            if (role != FollowerRole.values.last) const SizedBox(width: F.s8),
                          ],
                        ],
                      ),
                      const SizedBox(height: F.s6),
                      Text(
                        f.permissions.canConfirm ? 'بيقدر يأكّد الجرعة بدالك.' : 'ما بيقدرش يأكّد الجرعة بدالك.',
                        style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                      ),
                      const SizedBox(height: F.s6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'يعدّل الأدوية — ${f.permissions.canEditMeds ? 'شغّال' : 'مقفول'}',
                              style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.ink),
                            ),
                          ),
                          Switch(
                            key: ValueKey('follower-edit-meds-${f.caregiverId}'),
                            value: f.permissions.canEditMeds,
                            activeThumbColor: F.gold,
                            onChanged: _busy ? null : (on) => _setEditMeds(f, on),
                          ),
                        ],
                      ),
                      const SizedBox(height: F.s6),
                      FSecondaryButton(
                        key: ValueKey('follower-remove-${f.caregiverId}'),
                        label: 'شيله',
                        onPressed: _busy ? null : () => _remove(f),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
