import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/hh_widgets.dart';
import 'soothe_audio.dart';
import 'soothe_copy.dart';
import 'soothe_widgets.dart';

/// 哄睡页中间的声音设置：声音 2×2、音量、定时关闭（终稿 03 / 03b）
class SoothePlayerControls extends ConsumerWidget {
  const SoothePlayerControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    final s = ref.watch(sootheAudioProvider);
    final ctl = ref.read(sootheAudioProvider.notifier);
    Widget tile(SootheSound v) => Expanded(
      child: _SoundTile(sound: v, selected: s.sound == v, onTap: () => ctl.selectSound(v)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SootheHeading(playerSoundHeading),
        Row(children: [tile(SootheSound.white), const SizedBox(width: 12), tile(SootheSound.pink)]),
        const SizedBox(height: 12),
        Row(children: [tile(SootheSound.brown), const SizedBox(width: 12), tile(SootheSound.shush)]),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                playerVolumeLabel(s.volume),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
              ),
            ),
            Text(playerVolumeMax, style: TextStyle(fontSize: 13, color: c.ink)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: c.peach,
            inactiveTrackColor: c.peachL,
            thumbColor: c.peach,
            overlayColor: c.peach.withValues(alpha: .12),
            trackHeight: 6,
          ),
          child: Slider(
            key: const Key('soothe-volume'),
            value: s.volume,
            max: sootheMaxVolume,
            divisions: 14, // 每格 5%
            semanticFormatterCallback: (v) => '${(v * 100).round()}%，最高 70%',
            onChanged: ctl.setVolume,
          ),
        ),
        const SizedBox(height: 6),
        const SootheHeading(playerTimerHeading, top: 0),
        HhSegmented<int>(
          key: const Key('soothe-timer'),
          values: sootheTimerOptions,
          label: playerTimerOption,
          selected: s.timerMinutes,
          onChanged: ctl.setTimer,
        ),
      ],
    );
  }
}

/// 声音选中态（终稿第 7 条）：日间 peachL 底 + peach 描边；夜间 card 底 + peach2 描边；文字都用 ink
class _SoundTile extends StatelessWidget {
  const _SoundTile({required this.sound, required this.selected, required this.onTap});
  final SootheSound sound;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final isDefault = sound == sootheDefaultSound;
    return Semantics(
      button: true,
      selected: selected,
      label: isDefault ? '${sound.label}，$playerDefaultTag' : sound.label,
      excludeSemantics: true,
      child: InkWell(
        key: Key('sound-${sound.name}'),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.dn(c.peachL, c.card) : c.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? c.dn(c.peach, c.peach2) : c.line, width: selected ? 2 : 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                selected ? '✓ ${sound.label}' : sound.label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: c.ink),
              ),
              if (isDefault) Text(playerDefaultTag, style: TextStyle(fontSize: 12, color: c.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 哄睡页底部固定区的状态行 + 两个按钮（终稿 03 / 11）。
/// 左边是声音按钮（开始播放 / 停止 / 继续 / 再播 15 分钟），右边一直是「睡着了 · 开始记录睡觉」。
class SoothePlayerBar extends ConsumerWidget {
  const SoothePlayerBar({super.key, required this.asleep});

  /// 右边的主按钮（由哄睡页传入，保持 S-2 的行为）
  final Widget asleep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sootheAudioProvider);
    final ctl = ref.read(sootheAudioProvider.notifier);
    final (label, key, onTap) = switch (s.phase) {
      SoothePhase.idle => (playerPlay, 'soothe-play', ctl.start),
      SoothePhase.playing => (playerStop, 'soothe-stop', ctl.stop),
      SoothePhase.paused => (playerResume, 'soothe-resume', ctl.resume),
      SoothePhase.ended => (playerExtra, 'soothe-extra', ctl.playExtra),
      SoothePhase.error => (playerRetry, 'soothe-play', ctl.start),
    };
    final sound = HhButton(
      key: Key(key),
      label: label,
      primary: false,
      onPressed: () {
        HapticFeedback.lightImpact();
        onTap();
      },
    );
    final big = largeText(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Status(state: s),
        if (big) ...[
          sound,
          const SizedBox(height: 10),
          asleep,
        ] else
          Row(
            children: [
              SizedBox(width: 130, child: sound),
              const SizedBox(width: 12),
              Expanded(child: asleep),
            ],
          ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.state});
  final SootheAudioState state;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final style = TextStyle(fontSize: 14, color: c.ink, height: 1.5);
    final name = state.sound.label;
    Widget line(String text, {bool live = true}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        key: const Key('soothe-status'),
        liveRegion: live,
        container: true,
        child: CopyText(text, style: style, textAlign: TextAlign.center),
      ),
    );
    return switch (state.phase) {
      SoothePhase.idle => const SizedBox.shrink(),
      // 倒计时每秒在变，不做 liveRegion，免得读屏一直播报
      SoothePhase.playing => line(playerPlayingStatus(name, formatRemaining(state.remaining)), live: false),
      SoothePhase.paused => line(playerPausedStatus),
      SoothePhase.ended => line(playerEndedStatus(name, state.playedMinutes)),
      SoothePhase.error => const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: AlertBox(playerErrorLine, key: Key('soothe-status')),
      ),
    };
  }
}

/// 步骤页底部的迷你播放条（终稿 04）：播放中 / 暂停时才显示
class SootheMiniPlayer extends ConsumerWidget {
  const SootheMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    final s = ref.watch(sootheAudioProvider);
    if (!s.active) return const SizedBox.shrink();
    final ctl = ref.read(sootheAudioProvider.notifier);
    final playing = s.phase == SoothePhase.playing;
    return Padding(
      key: const Key('steps-mini-player'),
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: !playing,
              container: true,
              child: CopyText(
                playing ? playerMiniStatus(s.sound.label, formatRemaining(s.remaining)) : playerPausedStatus,
                style: TextStyle(fontSize: 14, color: c.ink, height: 1.5),
              ),
            ),
          ),
          SootheLink(
            key: Key(playing ? 'steps-mini-stop' : 'steps-mini-resume'),
            label: playing ? playerStop : playerResume,
            chevron: false,
            onTap: playing ? ctl.stop : ctl.resume,
          ),
        ],
      ),
    );
  }
}
