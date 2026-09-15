import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'service.dart';

class WatchRecord {
  final Film film;
  final String url, episode, lineName;
  final int seconds, episodeIndex, updatedAt;
  WatchRecord(this.film, this.url, this.episode, this.seconds,
      {this.lineName = '', this.episodeIndex = 1, int? updatedAt})
      : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
  Map<String, dynamic> toJson() => {
        'film': film.data,
        'url': url,
        'episode': episode,
        'seconds': seconds,
        'line_name': lineName,
        'episode_index': episodeIndex,
        'updated_at': updatedAt
      };
  factory WatchRecord.fromJson(Map<String, dynamic> j) => WatchRecord(
      Film(Map<String, dynamic>.from(j['film'])),
      j['url'] as String,
      j['episode'] as String,
      j['seconds'] as int,
      lineName: j['line_name'] ?? '',
      episodeIndex: j['episode_index'] ?? 1,
      updatedAt: j['updated_at'] ?? 0);
}

class Library extends ChangeNotifier {
  final SharedPreferences prefs;
  final Map<String, Film> favorites = {};
  final Map<String, WatchRecord> history = {};
  AppService? _service;
  String? _userId;
  String? get accountId => _userId;
  int _epoch = 0;
  DateTime? _lastUpload;
  String syncMessage = '未登录，观看记录保存在本机';
  String get _suffix => _userId == null ? '' : ':user:$_userId';
  Library(this.prefs) {
    _load();
  }
  void attach(AppService service) {
    _service?.removeListener(_accountChanged);
    _service = service;
    service.addListener(_accountChanged);
    _accountChanged();
  }

  void _accountChanged() {
    final id = _service?.userId;
    if (id == _userId) return;
    _userId = id;
    _epoch++;
    _lastUpload = null;
    _load();
    syncMessage = id == null ? '未登录，观看记录保存在本机' : '正在同步观看记录…';
    notifyListeners();
    if (id != null) unawaited(syncFromAccount());
  }

  void _load() {
    favorites.clear();
    history.clear();
    for (final raw in prefs.getStringList('favorites$_suffix') ?? <String>[]) {
      try {
        final f = Film(Map<String, dynamic>.from(jsonDecode(raw)));
        favorites[f.id] = f;
      } catch (_) {}
    }
    for (final raw in prefs.getStringList('history$_suffix') ?? <String>[]) {
      try {
        final r =
            WatchRecord.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
        history[r.film.id] = r;
      } catch (_) {}
    }
  }

  Future<void> toggle(Film film) async {
    favorites.containsKey(film.id)
        ? favorites.remove(film.id)
        : favorites[film.id] = film;
    await prefs.setStringList('favorites$_suffix',
        favorites.values.map((f) => jsonEncode(f.data)).toList());
    notifyListeners();
  }

  Future<void> remember(WatchRecord record, {bool forceSync = false}) async {
    final epoch = _epoch;
    history.remove(record.film.id);
    history[record.film.id] = record;
    while (history.length > 100) {
      history.remove(history.keys.first);
    }
    await prefs.setStringList('history$_suffix',
        history.values.map((r) => jsonEncode(r.toJson())).toList());
    notifyListeners();
    final service = _service;
    if (epoch != _epoch || service == null || !service.loggedIn) return;
    if (!forceSync &&
        _lastUpload != null &&
        DateTime.now().difference(_lastUpload!).inSeconds < 15) {
      return;
    }
    _lastUpload = DateTime.now();
    var line = record.lineName;
    var index = record.episodeIndex;
    if (line.isEmpty) {
      for (final l in record.film.lines) {
        final found = l.episodes.indexWhere((e) => e.url == record.url);
        if (found >= 0) {
          line = l.name;
          index = found + 1;
          break;
        }
      }
    }
    if (line.isEmpty) return;
    try {
      await service.call('progress', body: {
        'vod_id': record.film.id,
        'line_name': line,
        'episode': '$index',
        'position_ms': '${record.seconds * 1000}'
      });
      if (epoch == _epoch) {
        syncMessage = '观看进度已同步到账号';
        notifyListeners();
      }
    } catch (_) {
      if (epoch == _epoch) {
        syncMessage = '网络未同步，进度已保存在本机';
        notifyListeners();
      }
    }
  }

  Future<void> syncFromAccount() async {
    final service = _service, epoch = _epoch;
    if (service == null || !service.loggedIn) return;
    try {
      final result = await service.call('progress');
      if (epoch != _epoch) return;
      for (final item in result['list'] as List? ?? []) {
        final f = Film(Map<String, dynamic>.from(item['film']));
        final lines = f.lines;
        if (lines.isEmpty) continue;
        final line = lines.firstWhere((l) => l.name == item['line_name'],
            orElse: () => lines.first);
        final index = int.tryParse('${item['episode']}') ?? 1;
        if (index < 1 || index > line.episodes.length) continue;
        final e = line.episodes[index - 1];
        final updated = (int.tryParse('${item['updated_at']}') ?? 0) * 1000;
        if ((history[f.id]?.updatedAt ?? -1) > updated) continue;
        history[f.id] = WatchRecord(f, e.url, e.name,
            (int.tryParse('${item['position_ms']}') ?? 0) ~/ 1000,
            lineName: line.name, episodeIndex: index, updatedAt: updated);
      }
      final ordered = history.values.toList()
        ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      history.clear();
      for (final r
          in ordered.skip(ordered.length > 100 ? ordered.length - 100 : 0)) {
        history[r.film.id] = r;
      }
      await prefs.setStringList('history$_suffix',
          history.values.map((r) => jsonEncode(r.toJson())).toList());
      if (epoch == _epoch) {
        syncMessage = '观看记录已同步';
        notifyListeners();
      }
    } catch (_) {
      if (epoch == _epoch) {
        syncMessage = '同步失败，本机记录仍保留';
        notifyListeners();
      }
    }
  }

  Future<void> clearHistory() async {
    final epoch = _epoch;
    if (_service?.loggedIn == true) {
      await _service!.call('clear_progress', body: {});
    }
    if (epoch != _epoch) return;
    history.clear();
    await prefs.remove('history$_suffix');
    notifyListeners();
  }

  @override
  void dispose() {
    _service?.removeListener(_accountChanged);
    super.dispose();
  }
}
