package com.xso.aggregator

// 后台播放（just_audio_background / audio_service）要求 activity 继承它的基类：
// 锁屏控件、通知点击与媒体按键事件由该类转发给播放服务，
// 换成普通 FlutterActivity 后这条链路会静默失效。
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity()
