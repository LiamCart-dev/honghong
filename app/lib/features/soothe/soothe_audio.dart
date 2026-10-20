import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/audio/auto_listen.dart';
import '../../services/audio/soothe_engine.dart';

export '../../services/audio/soothe_engine.dart' show SootheSound, SootheEngine, SootheEngineEvent, SootheFocusDenied;

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

/// 播放中换声音：先在 0.5 秒内淡出旧声音，再换、1 秒淡入新声音（QA #38 第 6 条）
const sootheSwitchOut = Duration(milliseconds: 500);
const sootheSwitchIn = Duration(seconds: 1);

/// 系统只要求调低音量的短暂打断（提示音）期间，音量降到原来的 30%
const sootheDuckFactor = 0.3;

final _monotonic = Stopwatch()..start();

/// 哄睡声音控制器。全局保活：离开哄睡页（比如去步骤页、回首页、锁屏）声音照常播放，直到定时结束或点停止。
class SootheAudioController extends Notifier<SootheAudioState> {
  /// 计时用的单调时钟（不受改系统时间影响，QA #38 第 5 条）；测试里换成跟着假时间走的
  static Duration Function() monotonic = () => _monotonic.elapsed;

  Timer? _ticker;
  StreamSubscription<SootheEngineEvent>? _events;

  /// 这一轮的总时长（开始播放时 = 定时选项；再播 = 15 分钟；播放中改定时 = 从改的那一刻重新算）
  Duration _length = Duration.zero;

  /// 这一轮已经播了多久（不含当前这段）
  Duration _before = Duration.zero;

  /// 这一轮里累计的时长，用于结束时的「播放了 x 分钟」
  Duration _total = Duration.zero;

  /// 当前这段开始播放的时刻（单调时钟）
  Duration? _since;

  /// 换声音：开始淡出的时刻；换好以后开始淡入的时刻
  Duration? _switchOutAt;
  Duration? _switchInAt;
  bool _ducked = false;

  /// 定时器刷新间隔：淡入淡出要平滑，剩余时间按秒显示
  static const tick = Duration(milliseconds: 100);

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

  Duration get _now => monotonic();

  /// 每次进哄睡页：没在播（或已经播完）就回到默认值（粉噪音、30%、30 分钟、未播放）
  void resetIfNotActive() {
    if (state.active) return;
    _ticker?.cancel();
    state = const SootheAudioState();
  }

  Duration get _elapsed => _before + (_since == null ? Duration.zero : _now - _since!);

  /// 换声音。播放中不硬切：先淡出，再换、再淡入
  Future<void> selectSound(SootheSound s) async {
    if (s == state.sound) return;
    state = state.copyWith(sound: s);
    if (state.phase != SoothePhase.playing) return;
    final g = _switchGain();
    // 已经在淡入新声音时又换：从当前音量接着往下淡
    _switchOutAt = _now - sootheSwitchOut * (1 - g);
    _switchInAt = null;
    _applyVolume();
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
    if (state.phase == SoothePhase.playing) _since = _now;
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
    _since = _now;
    _switchOutAt = null;
    _switchInAt = null;
    _ducked = false;
    state = state.copyWith(phase: SoothePhase.playing, remaining: _length - _before);
    await _listen.holdForSoothe();
    try {
      // 每次都重新申请焦点、切回播放类别；拿不到就显示出错，不能"播放中"却没有声音
      if (!await _engine.activate()) throw SootheFocusDenied();
      await _engine.setVolume(0); // 3 秒淡入
      await _engine.load(state.sound);
      await _engine.play();
    } catch (e) {
      _fail(e);
      return;
    }
    if (state.phase != SoothePhase.playing) return; // 等待期间被停止 / 出错
    _ticker?.cancel();
    _ticker = Timer.periodic(tick, (_) => _onTick());
  }

  /// 点停止（或点「睡着了」）：马上停，不淡出
  Future<void> stop() async {
    _ticker?.cancel();
    _since = null;
    _switchOutAt = null;
    _switchInAt = null;
    final was = state.phase;
    state = state.copyWith(phase: SoothePhase.idle, remaining: Duration.zero);
    _listen.releaseSoothe();
    if (was == SoothePhase.idle) return;
    try {
      await _engine.stop();
    } catch (_) {}
  }

  void _pauseInternal() {
    if (state.phase != SoothePhase.playing) return;
    _before = _elapsed;
    _since = null;
    _switchOutAt = null;
    _switchInAt = null;
    _ticker?.cancel();
    state = state.copyWith(phase: SoothePhase.paused, remaining: _length - _before);
    _listen.releaseSoothe();
  }

  void _onEngine(SootheEngineEvent e) {
    switch (e) {
      case SootheEngineEvent.interrupted:
      case SootheEngineEvent.remotePause:
        _pauseInternal();
      case SootheEngineEvent.duck:
        _ducked = true;
        if (state.phase == SoothePhase.playing) _applyVolume();
      case SootheEngineEvent.unduck:
        _ducked = false;
        if (state.phase == SoothePhase.playing) _applyVolume();
      case SootheEngineEvent.failed:
        if (state.active) _fail('playback error');
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
    // 换声音：旧声音淡出到 0 以后才真正换
    final out = _switchOutAt;
    if (out != null && _now - out >= sootheSwitchOut) {
      _switchOutAt = null;
      _switchInAt = _now;
      _engine.setVolume(0);
      () async {
        try {
          await _engine.load(state.sound);
          await _engine.play();
        } catch (e) {
          _fail(e);
        }
      }();
    }
    _applyVolume();
    _publish();
  }

  void _publish() {
    final left = _length - _elapsed;
    final secs = Duration(seconds: (left.inMilliseconds / 1000).ceil().clamp(0, 1 << 30));
    if (secs != state.remaining) state = state.copyWith(remaining: secs);
  }

  /// 换声音时的系数：淡出段 1→0，淡入段 0→1
  double _switchGain() {
    double ratio(Duration a, Duration b) => (a.inMilliseconds / b.inMilliseconds).clamp(0.0, 1.0);
    final out = _switchOutAt;
    if (out != null) return 1 - ratio(_now - out, sootheSwitchOut);
    final inn = _switchInAt;
    if (inn != null) {
      final g = ratio(_now - inn, sootheSwitchIn);
      if (g >= 1) _switchInAt = null;
      return g;
    }
    return 1;
  }

  void _applyVolume() {
    final since = _since == null ? Duration.zero : _now - _since!;
    final gain = sootheFadeGain(sinceStart: since, remaining: _length - _elapsed) * _switchGain() * (_ducked ? sootheDuckFactor : 1);
    _engine.setVolume((state.volume * gain).clamp(0.0, sootheMaxVolume));
  }

  /// 定时到了：已经淡出到 0，暂停（保留锁屏控件，点播放 = 再播 15 分钟），恢复自动听哭声
  void _finish() {
    _ticker?.cancel();
    final played = _total + _elapsed;
    _since = null;
    _before = Duration.zero;
    _switchOutAt = null;
    _switchInAt = null;
    state = state.copyWith(phase: SoothePhase.ended, remaining: Duration.zero, playedMinutes: (played.inSeconds / 60).round());
    _engine.setVolume(0);
    _engine.pause();
    _listen.releaseSoothe();
  }

  void _fail(Object e) {
    debugPrint('soothe audio failed: $e');
    _ticker?.cancel();
    _since = null;
    _switchOutAt = null;
    _switchInAt = null;
    state = state.copyWith(phase: SoothePhase.error, remaining: Duration.zero);
    _listen.releaseSoothe();
    _engine.pause().ignore();
  }
}

final sootheAudioProvider = NotifierProvider<SootheAudioController, SootheAudioState>(SootheAudioController.new);

/// 「28:41」
String formatRemaining(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
