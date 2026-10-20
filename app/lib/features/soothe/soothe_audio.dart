import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_clock.dart';
import '../../services/audio/auto_listen.dart';
import '../../services/audio/soothe_engine.dart';

export '../../services/audio/soothe_engine.dart' show SootheSound, SootheEngine, SootheEngineEvent;

/// 哄睡声音的默认值和上限（Liam 2026-10-20 确认：默认粉噪音，30 分钟自动关闭，音量 30%，最高 70%）
const sootheDefaultSound = SootheSound.pink;
const sootheDefaultVolume = 0.30;
const sootheMaxVolume = 0.70;
const sootheTimerOptions = [15, 30, 45, 60];
const sootheDefaultTimer = 30;

/// 定时结束后「再播 15 分钟」
const sootheExtraMinutes = 15;
const sootheFadeIn = Duration(seconds: 3);
const sootheFadeOut = Duration(seconds: 10);

enum SoothePhase {
  /// 还没播
  idle,
  playing,

  /// 被来电等打断、或在锁屏上按了暂停：剩余时间停住，不自动继续
  paused,

  /// 定时到了，已经淡出停止（final-11）
  ended,

  /// 声音没能播放
  error,
}

@immutable
class SootheAudioState {
  const SootheAudioState({
    this.sound = sootheDefaultSound,
    this.volume = sootheDefaultVolume,
    this.timerMinutes = sootheDefaultTimer,
    this.phase = SoothePhase.idle,
    this.remaining = Duration.zero,
    this.playedMinutes = 0,
  });

  final SootheSound sound;

  /// 0–[sootheMaxVolume]
  final double volume;
  final int timerMinutes;
  final SoothePhase phase;

  /// 播放中 / 暂停时离自动关闭还有多久（取整到秒）
  final Duration remaining;

  /// 定时结束时，这一轮一共播了几分钟（「粉噪音播放了 30 分钟」）
  final int playedMinutes;

  bool get active => phase == SoothePhase.playing || phase == SoothePhase.paused;

  SootheAudioState copyWith({SootheSound? sound, double? volume, int? timerMinutes, SoothePhase? phase, Duration? remaining, int? playedMinutes}) =>
      SootheAudioState(
        sound: sound ?? this.sound,
        volume: volume ?? this.volume,
        timerMinutes: timerMinutes ?? this.timerMinutes,
        phase: phase ?? this.phase,
        remaining: remaining ?? this.remaining,
        playedMinutes: playedMinutes ?? this.playedMinutes,
      );
}

/// 淡入淡出系数（0–1）：从这次开始/继续起 3 秒淡入，离结束 10 秒淡出
double sootheFadeGain({required Duration sinceStart, required Duration remaining}) {
  double ratio(Duration a, Duration b) => (a.inMilliseconds / b.inMilliseconds).clamp(0.0, 1.0);
  return math.min(ratio(sinceStart, sootheFadeIn), ratio(remaining, sootheFadeOut));
}

/// 测试换成假的播放器
final sootheEngineProvider = Provider<SootheEngine>((ref) => JustAudioSootheEngine());

/// 哄睡声音控制器。全局保活：离开哄睡页（比如去步骤页、回首页、锁屏）声音照常播放，直到定时结束或点停止。
class SootheAudioController extends Notifier<SootheAudioState> {
  Timer? _ticker;
  StreamSubscription<SootheEngineEvent>? _events;

  /// 这一轮的总时长（开始播放时 = 定时选项；再播 = 15 分钟；播放中改定时 = 从改的那一刻重新算）
  Duration _length = Duration.zero;

  /// 这一轮已经播了多久（不含当前这段）
  Duration _before = Duration.zero;

  /// 这一轮里累计的时长，用于结束时的「播放了 x 分钟」
  Duration _total = Duration.zero;
  DateTime? _since;

  /// 定时器刷新间隔：淡入淡出要平滑，剩余时间按秒显示
  static const tick = Duration(milliseconds: 250);

  @override
  SootheAudioState build() {
    ref.onDispose(() {
      _ticker?.cancel();
      _events?.cancel();
    });
    // 锁屏 / 耳机 / 来电打断的事件从一开始就要听（定时结束后 App 不在前台也要能「再播 15 分钟」）
    _events = ref.read(sootheEngineProvider).events.listen(_onEngine);
    return const SootheAudioState();
  }

  SootheEngine get _engine => ref.read(sootheEngineProvider);

  AutoListenController get _listen => ref.read(autoListenControllerProvider.notifier);

  /// 每次进哄睡页：没在播（或已经播完）就回到默认值（粉噪音、30%、30 分钟、未播放）
  void resetIfNotActive() {
    if (state.active) return;
    _ticker?.cancel();
    state = const SootheAudioState();
  }

  Duration get _elapsed => _before + (_since == null ? Duration.zero : AppClock.now().difference(_since!));

  Future<void> selectSound(SootheSound s) async {
    if (s == state.sound) return;
    state = state.copyWith(sound: s);
    if (state.phase != SoothePhase.playing) return;
    try {
      await _engine.load(s);
      await _engine.play();
    } catch (e) {
      _fail(e);
    }
  }

  /// 音量滑块：0–70%，不做增益
  void setVolume(double v) {
    state = state.copyWith(volume: v.clamp(0.0, sootheMaxVolume));
    if (state.phase == SoothePhase.playing) _applyVolume();
  }

  /// 改定时：播放中从现在起重新算
  void setTimer(int minutes) {
    assert(sootheTimerOptions.contains(minutes));
    state = state.copyWith(timerMinutes: minutes);
    if (!state.active) return;
    _total += _elapsed;
    _before = Duration.zero;
    _length = Duration(minutes: minutes);
    if (state.phase == SoothePhase.playing) _since = AppClock.now();
    _publish();
  }

  /// 开始播放（按当前定时）
  Future<void> start() => _begin(Duration(minutes: state.timerMinutes), fresh: true);

  /// 定时结束后「再播 15 分钟」：同一种声音、当前音量，不改定时选项
  Future<void> playExtra() => _begin(const Duration(minutes: sootheExtraMinutes), fresh: true);

  /// 暂停后点继续：剩余时间接着走
  Future<void> resume() => _begin(_length, fresh: false);

  Future<void> _begin(Duration length, {required bool fresh}) async {
    if (state.phase == SoothePhase.playing) return;
    if (fresh) {
      _length = length;
      _before = Duration.zero;
      _total = Duration.zero;
    }
    _since = AppClock.now();
    state = state.copyWith(phase: SoothePhase.playing, remaining: _length - _before);
    await _listen.holdForSoothe();
    try {
      await _engine.setVolume(0); // 3 秒淡入
      await _engine.load(state.sound);
      await _engine.play();
    } catch (e) {
      _fail(e);
      return;
    }
    _ticker?.cancel();
    _ticker = Timer.periodic(tick, (_) => _onTick());
  }

  /// 点停止：马上停，不淡出
  Future<void> stop() async {
    _ticker?.cancel();
    _since = null;
    state = state.copyWith(phase: SoothePhase.idle, remaining: Duration.zero);
    _listen.releaseSoothe();
    try {
      await _engine.stop();
    } catch (_) {}
  }

  void _pauseInternal() {
    if (state.phase != SoothePhase.playing) return;
    _before = _elapsed;
    _since = null;
    _ticker?.cancel();
    state = state.copyWith(phase: SoothePhase.paused, remaining: _length - _before);
    _listen.releaseSoothe();
  }

  void _onEngine(SootheEngineEvent e) {
    switch (e) {
      case SootheEngineEvent.interrupted:
      case SootheEngineEvent.remotePause:
        _pauseInternal();
      case SootheEngineEvent.remotePlay:
        // 锁屏上点播放：播完了 = 再播 15 分钟；暂停中 = 继续；其他情况不认
        switch (state.phase) {
          case SoothePhase.ended:
            playExtra();
          case SoothePhase.paused:
            resume();
          case SoothePhase.playing:
            break;
          case SoothePhase.idle:
          case SoothePhase.error:
            _engine.pause();
        }
    }
  }

  void _onTick() {
    if (state.phase != SoothePhase.playing) return;
    final left = _length - _elapsed;
    if (left <= Duration.zero) {
      _finish();
      return;
    }
    _applyVolume();
    _publish();
  }

  void _publish() {
    final left = _length - _elapsed;
    final secs = Duration(seconds: (left.inMilliseconds / 1000).ceil().clamp(0, 1 << 30));
    if (secs != state.remaining) state = state.copyWith(remaining: secs);
  }

  void _applyVolume() {
    final since = _since == null ? Duration.zero : AppClock.now().difference(_since!);
    final gain = sootheFadeGain(sinceStart: since, remaining: _length - _elapsed);
    _engine.setVolume((state.volume * gain).clamp(0.0, sootheMaxVolume));
  }

  /// 定时到了：已经淡出到 0，暂停（保留锁屏控件，点播放 = 再播 15 分钟），恢复自动听哭声
  void _finish() {
    _ticker?.cancel();
    final played = _total + _elapsed;
    _since = null;
    _before = Duration.zero;
    state = state.copyWith(phase: SoothePhase.ended, remaining: Duration.zero, playedMinutes: (played.inSeconds / 60).round());
    _engine.setVolume(0);
    _engine.pause();
    _listen.releaseSoothe();
  }

  void _fail(Object e) {
    debugPrint('soothe audio failed: $e');
    _ticker?.cancel();
    _since = null;
    state = state.copyWith(phase: SoothePhase.error, remaining: Duration.zero);
    _listen.releaseSoothe();
  }
}

final sootheAudioProvider = NotifierProvider<SootheAudioController, SootheAudioState>(SootheAudioController.new);

/// 「28:41」
String formatRemaining(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
