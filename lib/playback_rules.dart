import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SkipSettings {
  final bool enabled;
  final int introSeconds, outroSeconds;
  const SkipSettings(
      {this.enabled = false, this.introSeconds = 90, this.outroSeconds = 90});

  static String key(String filmId, String? accountId) =>
      'skip:${Uri.encodeComponent(accountId ?? "guest")}:${Uri.encodeComponent(filmId)}';

  static SkipSettings load(
      SharedPreferences prefs, String filmId, String? accountId) {
    final values = prefs.getStringList(key(filmId, accountId));
    if (values == null || values.length != 3) return const SkipSettings();
    return SkipSettings(
        enabled: values[0] == 'true',
        introSeconds: (int.tryParse(values[1]) ?? 90).clamp(0, 300),
        outroSeconds: (int.tryParse(values[2]) ?? 90).clamp(0, 300));
  }

  Future<void> save(
          SharedPreferences prefs, String filmId, String? accountId) =>
      prefs.setStringList(key(filmId, accountId),
          ['$enabled', '$introSeconds', '$outroSeconds']);

  // Ignore settings that would remove all or almost all of a short episode.
  bool appliesTo(Duration sourceDuration) =>
      enabled &&
      introSeconds >= 0 &&
      outroSeconds >= 0 &&
      introSeconds <= 300 &&
      outroSeconds <= 300 &&
      sourceDuration > Duration(seconds: introSeconds + outroSeconds + 10);
}

class PlaybackSleepTimer extends ChangeNotifier {
  final VoidCallback onStop;
  final DateTime Function() now;
  Timer? _timer;
  DateTime? deadline;
  int? remainingEpisodes;
  bool stopped = false;

  PlaybackSleepTimer({required this.onStop, DateTime Function()? now})
      : now = now ?? DateTime.now;

  bool get active => deadline != null || remainingEpisodes != null;
  String get label {
    if (remainingEpisodes != null) return '播完 $remainingEpisodes 集后停止（含本集）';
    final end = deadline;
    if (end == null) return stopped ? '已定时停止' : '未开启';
    return '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')} 停止播放';
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    deadline = null;
    remainingEpisodes = null;
    stopped = false;
    notifyListeners();
  }

  void after(Duration duration) {
    cancel();
    deadline = now().add(duration);
    _timer = Timer(duration, _stop);
    notifyListeners();
  }

  void afterEpisodes(int count) {
    assert(count > 0);
    cancel();
    remainingEpisodes = count;
    notifyListeners();
  }

  void checkDeadline() {
    if (deadline != null && !now().isBefore(deadline!)) _stop();
  }

  // The session calls this once per completed episode, never on manual switches.
  bool episodeEnded({required bool hasNext}) {
    checkDeadline();
    if (stopped) return true;
    final count = remainingEpisodes;
    if (count != null) {
      if (count <= 1 || !hasNext) {
        _stop();
        return true;
      }
      remainingEpisodes = count - 1;
      notifyListeners();
    }
    return false;
  }

  void _stop() {
    if (!active) return;
    _timer?.cancel();
    _timer = null;
    deadline = null;
    remainingEpisodes = null;
    stopped = true;
    onStop();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
