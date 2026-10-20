import 'dart:async';

import 'package:honghong/services/audio/soothe_engine.dart';

/// 假的播放器：记下每次调用和音量，可以模拟锁屏按键、来电打断和加载失败
class FakeSootheEngine implements SootheEngine {
  final calls = <String>[];
  final volumes = <double>[];
  SootheSound? loaded;
  bool playing = false;
  bool failLoad = false;

  /// false = 系统不给音频焦点
  bool grantFocus = true;
  final _events = StreamController<SootheEngineEvent>.broadcast(sync: true);

  double get volume => volumes.isEmpty ? 0 : volumes.last;

  @override
  Stream<SootheEngineEvent> get events => _events.stream;

  /// 模拟系统事件（锁屏按钮、来电打断）
  void emit(SootheEngineEvent e) {
    if (e == SootheEngineEvent.interrupted || e == SootheEngineEvent.remotePause) playing = false;
    if (e == SootheEngineEvent.remotePlay) playing = true;
    _events.add(e);
  }

  @override
  Future<bool> activate() async {
    calls.add('activate');
    return grantFocus;
  }

  @override
  Future<void> load(SootheSound sound) async {
    calls.add('load:${sound.name}');
    if (failLoad) throw Exception('decode failed');
    loaded = sound;
  }

  @override
  Future<void> play() async {
    calls.add('play');
    playing = true;
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playing = false;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    playing = false;
    loaded = null;
  }

  @override
  Future<void> setVolume(double v) async => volumes.add(v);
}
