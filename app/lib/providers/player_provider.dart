import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// 迷你播放器状态：当前曲目 + 播放状态 + 进度
@immutable
class PlayerStateX {
  final String? title;
  final String? artist;
  final bool playing;
  final bool loading;
  final Duration position;
  final Duration? duration;
  final String? error;

  const PlayerStateX({
    this.title,
    this.artist,
    this.playing = false,
    this.loading = false,
    this.position = Duration.zero,
    this.duration,
    this.error,
  });

  bool get active => title != null;
}

/// 简易播放器：一次一首，点新歌自动切歌
class PlayerController {
  final AudioPlayer _player = AudioPlayer();
  final ValueNotifier<PlayerStateX> state =
      ValueNotifier<PlayerStateX>(const PlayerStateX());

  PlayerController() {
    _player.playerStateStream.listen((ps) {
      final s = state.value;
      state.value = PlayerStateX(
        title: s.title,
        artist: s.artist,
        playing: ps.playing,
        loading: ps.processingState == ProcessingState.loading ||
            ps.processingState == ProcessingState.buffering,
        position: s.position,
        duration: s.duration,
        error: s.error,
      );
    });
    _player.positionStream.listen((p) {
      final s = state.value;
      state.value = PlayerStateX(
        title: s.title,
        artist: s.artist,
        playing: s.playing,
        loading: s.loading,
        position: p,
        duration: _player.duration,
        error: s.error,
      );
    });
    _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e) {
        final s = state.value;
        state.value = PlayerStateX(
            title: s.title, artist: s.artist, error: '播放失败：$e');
      },
    );
  }

  Future<void> play(
      {required String url, required String title, String? artist}) async {
    try {
      state.value = PlayerStateX(title: title, artist: artist, loading: true);
      await _player.setUrl(url);
      await _player.play();
      // setUrl 完成后补 duration
      state.value = PlayerStateX(
        title: title,
        artist: artist,
        playing: true,
        position: Duration.zero,
        duration: _player.duration,
      );
    } catch (e) {
      state.value = PlayerStateX(title: title, artist: artist, error: '播放失败：$e');
    }
  }

  Future<void> toggle() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> stop() async {
    await _player.stop();
    state.value = const PlayerStateX();
  }

  void dispose() => _player.dispose();
}
