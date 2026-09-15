import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xingbo_app/service.dart';
import 'package:xingbo_app/library.dart';
import 'package:xingbo_app/api.dart';
import 'package:xingbo_app/danmaku.dart';

class MemoryTokens implements TokenStore {
  String? value;
  MemoryTokens([this.value]);
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async {
    value = v;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

http.Response reply(Map<String, dynamic> data) =>
    http.Response(jsonEncode(data), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('restores token, sends bearer, clears expired session', () async {
    final tokens = MemoryTokens('existing');
    var expired = false;
    final service = AppService(
        tokens: tokens,
        client: MockClient((r) async {
          if (r.url.path.endsWith('health')) return reply({'code': 1});
          expect(r.headers['Authorization'], 'Bearer existing');
          return reply(expired
              ? {'code': 401, 'msg': 'expired'}
              : {
                  'code': 1,
                  'user': {'id': 7, 'name': 'alice'}
                });
        }));
    await service.initialize();
    expect(service.loggedIn, isTrue);
    expired = true;
    await expectLater(service.call('me'), throwsA(isA<ServiceError>()));
    expect(service.loggedIn, isFalse);
    expect(tokens.value, isNull);
  });
  test('captcha cookie is carried into login and password is never stored',
      () async {
    final tokens = MemoryTokens();
    final service = AppService(
        tokens: tokens,
        client: MockClient((r) async {
          if (r.url.path.endsWith('captcha')) {
            return http.Response('image', 200, headers: {
              'content-type': 'image/png',
              'set-cookie': 'PHPSESSID=captcha123; Path=/; HttpOnly'
            });
          }
          expect(r.headers['Cookie'], 'PHPSESSID=captcha123');
          expect(r.bodyFields['password'], 'secret-password');
          return reply({
            'code': 1,
            'token': 'opaque-session',
            'user': {'id': 8}
          });
        }));
    await service.captcha();
    await service.login('alice', 'secret-password', '1234');
    expect(tokens.value, 'opaque-session');
  });
  test('guest and separate accounts retain isolated local records', () async {
    SharedPreferences.setMockInitialValues({});
    final library = Library(await SharedPreferences.getInstance());
    final service = AppService(
        tokens: MemoryTokens(),
        client: MockClient((r) async {
          if (r.url.path.endsWith('login')) {
            return reply({
              'code': 1,
              'token': 'token-${r.bodyFields['name']}',
              'user': {'id': r.bodyFields['name']}
            });
          }
          return reply({'code': 1, 'list': []});
        }));
    library.attach(service);
    final film = Film({'vod_id': 1, 'vod_name': 'test'});
    await library.remember(WatchRecord(film, 'https://example.com/v', '1', 10));
    await service.login('alice', 'password', '');
    expect(library.history, isEmpty);
    await library.remember(WatchRecord(film, 'https://example.com/v', '1', 20));
    await service.login('bob', 'password', '');
    expect(library.history, isEmpty);
    await service.login('alice', 'password', '');
    expect(library.history['1']!.seconds, 20);
    await service.forget();
    expect(library.history['1']!.seconds, 10);
    await Future<void>.delayed(Duration.zero);
    library.dispose();
    service.dispose();
  });
  test('late cloud response cannot populate another account', () async {
    SharedPreferences.setMockInitialValues({});
    final pending = Completer<http.Response>();
    final service = AppService(
        tokens: MemoryTokens(),
        client: MockClient((r) async {
          if (r.url.path.endsWith('login')) {
            return reply({
              'code': 1,
              'token': 'token',
              'user': {'id': 1}
            });
          }
          return pending.future;
        }));
    final library = Library(await SharedPreferences.getInstance())
      ..attach(service);
    await service.login('alice', 'password', '');
    await service.forget();
    pending.complete(reply({
      'code': 1,
      'list': [
        {
          'film': {
            'vod_id': 5,
            'vod_play_from': 'm3u8',
            'vod_play_url': 'ep\$https://example.com/v'
          },
          'line_name': 'm3u8',
          'episode': 1,
          'position_ms': 90000,
          'updated_at': 9999999999
        }
      ]
    }));
    await Future<void>.delayed(Duration.zero);
    expect(library.history, isEmpty);
    library.dispose();
    service.dispose();
  });
  test('danmaku follows media time including seek back and expiry', () {
    final notes = [
      DanmakuNote(1, 1000, 'hello'),
      DanmakuNote(2, 10000, 'later')
    ];
    expect(visibleDanmaku(notes, 999, 8000), isEmpty);
    expect(visibleDanmaku(notes, 1000, 8000).single.id, 1);
    expect(visibleDanmaku(notes, 9000, 8000), isEmpty);
    expect(visibleDanmaku(notes, 11000, 8000).single.id, 2);
    expect(visibleDanmaku(notes, 2000, 8000).single.id, 1);
  });
}
