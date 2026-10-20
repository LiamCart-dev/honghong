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
}

/// 播放器的最小接口，方便测试换成假的
abstract interface class SootheEngine {
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
/// - 自己处理打断（`handleInterruptions: false`），这样打断结束后不会自动继续播放。
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
    await session.configure(const AudioSessionConfiguration.music());
    final player = AudioPlayer(handleInterruptions: false);
    _subs
      ..add(
        player.playingStream.listen((playing) {
          if (playing == _expectPlaying) return;
          _expectPlaying = playing;
          _events.add(playing ? SootheEngineEvent.remotePlay : SootheEngineEvent.remotePause);
        }),
      )
      ..add(
        session.interruptionEventStream.listen((e) {
          if (e.begin && _expectPlaying) _interrupt();
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
    (await AudioSession.instance).setActive(true).ignore();
    // play() 要到暂停时才返回，不能 await
    unawaited(player.play().catchError((Object e) => debugPrint('soothe play failed: $e')));
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
  }

  @override
  Future<void> setVolume(double v) async => _player?.setVolume(v.clamp(0, 1));
}
