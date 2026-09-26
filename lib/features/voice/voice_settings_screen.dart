import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/voice/voice_service.dart';
import 'help_button.dart';
import 'voice_intro_screen.dart';

/// «الرفيق الصوتي» في الإعدادات: شغّال/مقفول، السرعة (صوت الموبايل بس)،
/// الصوت، وإعادة المقدمة. شرايح بكلامها — مفيش رقم المستخدم بيشوفه.
class VoiceSettingsScreen extends StatelessWidget {
  const VoiceSettingsScreen({required this.voice, super.key});

  final VoiceService voice;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الرفيق الصوتي')),
        body: ListenableBuilder(
          listenable: voice,
          builder: (context, _) => ListView(
            padding: EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.gap + MediaQuery.paddingOf(context).bottom),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'بيقولّك الشاشة دي بتعمل إيه، وملخص يومك الصبح. بيتكلم بس — مفيش مايك.',
                      style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                    ),
                  ),
                  const SizedBox(width: F.s8),
                  const HelpButton('help_settings_voice'),
                ],
              ),
              const SizedBox(height: F.gap),
              FCard(
                child: FSwitch(
                  key: const ValueKey('voice-enabled'),
                  label: 'الصوت',
                  subtitle: voice.enabled ? 'شغّال' : 'مقفول',
                  value: voice.enabled,
                  onChanged: (on) async {
                    await voice.setEnabled(on);
                    // «ربنا يديك الصحة» — آخر جملة لما يقفله، وبعدها ساكت
                    if (!on) unawaited(voice.speakLine('gen_goodbye', force: true));
                  },
                ),
              ),
              const SizedBox(height: F.gap),
              const FSectionHead('السرعة'),
              Text(
                'لملخص اليوم وصوت الموبايل — التسجيلات بسرعتها.',
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
              ),
              const SizedBox(height: F.s8),
              _Choices<VoiceSpeed>(
                values: VoiceSpeed.values,
                current: voice.speed,
                label: (s) => s.label,
                keyOf: (s) => 'voice-speed-${s.name}',
                onPick: voice.setSpeed,
              ),
              const SizedBox(height: F.gap),
              const FSectionHead('علو الصوت'),
              const SizedBox(height: F.s8),
              _Choices<VoiceVolume>(
                values: VoiceVolume.values,
                current: voice.volume,
                label: (v) => v.label,
                keyOf: (v) => 'voice-volume-${v.name}',
                onPick: voice.setVolume,
              ),
              const SizedBox(height: F.gap),
              FSecondaryButton(
                key: const ValueKey('voice-replay-intro'),
                label: 'اسمع المقدمة تاني',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => VoiceIntroScreen(
                    voice: voice,
                    replay: true,
                    onDone: () => Navigator.of(context).maybePop(),
                  ),
                )),
              ),
            ],
          ),
        ),
      );
}

class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.values,
    required this.current,
    required this.label,
    required this.keyOf,
    required this.onPick,
  });

  final List<T> values;
  final T current;
  final String Function(T) label;
  final String Function(T) keyOf;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (final v in values) ...[
            Expanded(
              child: AnchorChip(
                key: ValueKey(keyOf(v)),
                label: label(v),
                selected: v == current,
                onTap: () => onPick(v),
              ),
            ),
            if (v != values.last) const SizedBox(width: F.s8),
          ],
        ],
      );
}
