import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xingbo_app/api.dart';
import 'package:xingbo_app/library.dart';

void main() {
  test(
    'favorites and resume record survive reload and can be cleared',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final lib = Library(prefs), film = Film({'vod_id': 1, 'vod_name': '测试'});
      await lib.toggle(film);
      await lib.remember(
        WatchRecord(film, 'https://example.com/1.m3u8', '第一集', 35),
      );
      final loaded = Library(prefs);
      expect(loaded.favorites['1']?.name, '测试');
      expect(loaded.history['1']?.seconds, 35);
      await loaded.clearHistory();
      expect(Library(prefs).history, isEmpty);
      await loaded.toggle(film);
      expect(Library(prefs).favorites, isEmpty);
    },
  );
}
