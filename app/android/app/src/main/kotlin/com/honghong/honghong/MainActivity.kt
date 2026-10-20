package com.honghong.honghong

import com.ryanheise.audioservice.AudioServiceActivity

// 哄睡声音（#38）：just_audio_background 要求主 Activity 继承 AudioServiceActivity（它本身就是 FlutterActivity），
// 这样后台播放服务和界面共用同一个 Flutter 引擎。
class MainActivity : AudioServiceActivity()
