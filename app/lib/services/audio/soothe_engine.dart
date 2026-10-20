import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

/// 哄睡声音（#38）。四种都是 `tool/soothe_sounds/generate.py` 自己生成的 10 秒无缝循环，CC0。
enum SootheSound {
  white('白噪音', 'assets/soothe/white.wav'),
  pink('粉噪音', 'assets/soothe/pink.wav'),
  brown('棕噪音', 'assets/soothe/brown.wav'),
  shush('嘘声', 'assets/soothe/shush.wav');

  const SootheSound(this.label, this.asset);
  final String label;
  final String asset;
}

/// 不是 App 自己发起的播放状态变化
enum SootheEngineEvent {
  /// 锁屏 / 通知栏 / 耳机按了播放
  remotePlay,

  /// 锁屏 / 通知栏 / 耳机按了暂停
  remotePause,

  /// 来电、别的 App 抢占音频、拔耳机：已经暂停，结束后**不**自动继续
  interrupted,

  /// 短暂的提示音（比如微信消息）只要求调低音量：调低，不暂停（QA #38 第 2 条）
  duck,

  /// 提示音结束，音量恢复
  unduck,

  /// 播放过程中出错（解码失败、输出设备没了等）：不能显示"播放中"却没有声音（QA #38 第 4 条）
  failed,
}

/// 系统不给音频焦点（比如正在通话）
class SootheFocusDenied implements Exception {
  @override
  String toString() => 'audio focus denied';
}

/// 播放器的最小接口，方便测试换成假的
abstract interface class SootheEngine {
  /// 每次开始 / 继续播放前调用：重新设成播放类别并申请音频焦点，拿不到返回 false（QA #38 第 4 条）。
  /// iOS 上录过音以后，录音插件会把音频类别改成 playAndRecord（声音从听筒出来），这里切回播放类别（QA #38 第 7 条）。
  Future<bool> activate();

  /// 换声音（循环播放）。失败时抛异常
  Future<void> load(SootheSound sound);
  Future<void> play();
  Future<void> pause();

  /// 停止并去掉锁屏/通知栏控件
  Future<void> stop();

  /// 0–1，直接作用在播放器上，不做增益（不会比系统音量更大）
  Future<void> setVolume(double v);
  Stream<SootheEngineEvent> get events;
}

/// 后台播放只在手机上初始化（`main()` 里、`runApp` 之前）
Future<void> initSootheBackgroundAudio() async {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS) || Platform.environment.containsKey('FLUTTER_TEST')) return;
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.honghong.honghong.soothe',
      androidNotificationChannelName: '哄睡声音',
      androidNotificationOngoing: true,
    );
  } catch (e) {
    debugPrint('soothe background audio init failed: $e');
  }
}

/// just_audio + audio_session + just_audio_background 的实现。
/// - Android：mediaPlayback 前台服务 + 锁屏控件；iOS：UIBackgroundModes audio。
/// - 自己处理打断（`handleInterruptions: false`）和会话激活（`handleAudioSessionActivation: false`），
///   这样打断结束后不会自动继续播放，拿不到焦点时也能知道。
class JustAudioSootheEngine implements SootheEngine {
  AudioPlayer? _player;
  final _events = StreamController<SootheEngineEvent>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  SootheSound? _loaded;

  /// App 自己期望的播放状态；和播放器实际状态不一致说明是锁屏 / 耳机按的
  bool _expectPlaying = false;

  @override
  Stream<SootheEngineEvent> get events => _events.stream;

  Future<AudioPlayer> _ensure() async {
    final p = _player;
    if (p != null) return p;
    final session = await AudioSession.instance;
    final player = AudioPlayer(handleInterruptions: false, handleAudioSessionActivation: false);
    _subs
      ..add(
        player.playingStream.listen((playing) {
          if (playing == _expectPlaying) return;
          _expectPlaying = playing;
          _events.add(playing ? SootheEngineEvent.remotePlay : SootheEngineEvent.remotePause);
        }),
      )
      ..add(player.playbackEventStream.listen((_) {}, onError: (Object e, StackTrace _) => _fail(e)))
      ..add(
        session.interruptionEventStream.listen((e) {
          // 只要求调低音量的（提示音）：调低，结束后恢复；要求暂停的（来电等）：暂停且不自动继续
          if (e.type == AudioInterruptionType.duck) {
            _events.add(e.begin ? SootheEngineEvent.duck : SootheEngineEvent.unduck);
          } else if (e.begin && _expectPlaying) {
            _interrupt();
          }
        }),
      )
      ..add(
        session.becomingNoisyEventStream.listen((_) {
          if (_expectPlaying) _interrupt();
        }),
      );
    return _player = player;
  }

  void _interrupt() {
    _expectPlaying = false;
    _player?.pause();
    _events.add(SootheEngineEvent.interrupted);
  }

  void _fail(Object e) {
    debugPrint('soothe playback error: $e');
    if (!_expectPlaying) return;
    _expectPlaying = false;
    _player?.pause();
    _events.add(SootheEngineEvent.failed);
  }

  @override
  Future<bool> activate() async {
    await _ensure();
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    return session.setActive(true);
  }

  @override
  Future<void> load(SootheSound sound) async {
    final player = await _ensure();
    if (_loaded == sound) return;
    await player.setAudioSource(
      AudioSource.asset(
        sound.asset,
        tag: MediaItem(id: 'soothe-${sound.name}', title: sound.label, album: '哄哄 · 哄睡'),
      ),
    );
    await player.setLoopMode(LoopMode.one);
    _loaded = sound;
  }

  @override
  Future<void> play() async {
    final player = await _ensure();
    _expectPlaying = true;
    // play() 要到暂停时才返回，不能 await；出错时通知控制器显示「声音没能播放」
    unawaited(player.play().catchError((Object e) => _fail(e)));
  }

  @override
  Future<void> pause() async {
    _expectPlaying = false;
    await _player?.pause();
  }

  @override
  Future<void> stop() async {
    _expectPlaying = false;
    await _player?.stop();
    _loaded = null; // stop 会释放音源，下次重新加载
    (await AudioSession.instance).setActive(false).ignore();
  }

  @override
  Future<void> setVolume(double v) async => _player?.setVolume(v.clamp(0, 1));
}
