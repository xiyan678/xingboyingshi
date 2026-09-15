import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xingbo_app/api.dart';

void main() {
  test('parses multiple lines and preserves dollar signs in signed URLs', () {
    final lines = parseLines(
      r'线路A$$$线路B',
      r'第1集$https://cdn.example/a.m3u8?token=a$b#第2集$https://cdn.example/b.m3u8$$$正片$https://cdn.example/c.mp4',
    );
    expect(lines.length, 2);
    expect(lines.first.episodes.length, 2);
    expect(
      lines.first.episodes.first.url,
      r'https://cdn.example/a.m3u8?token=a$b',
    );
    expect(lines.last.name, '线路B');
  });
  test('ignores empty and executable addresses', () {
    expect(parseLines('', ''), isEmpty);
    expect(parseLines('a', r'坏地址$javascript:alert(1)#坏地址$file:///a'), isEmpty);
  });
  test('closed API has useful error', () async {
    final api = FilmApi(
      client: MockClient((_) async => http.Response('closed', 200)),
    );
    await expectLater(
      api.categories(),
      throwsA(
        isA<ApiFailure>().having((e) => e.message, 'message', contains('尚未开启')),
      ),
    );
  });
  test('encodes search and pagination parameters', () async {
    final api = FilmApi(
      client: MockClient((request) async {
        expect(request.url.queryParameters['wd'], '星 & 播');
        expect(request.url.queryParameters['pg'], '2');
        expect(request.url.queryParameters['t'], '6');
        return http.Response(
          '{"code":1,"pagecount":3,"list":[{"vod_id":7,"vod_name":"Example"}]}',
          200,
        );
      }),
    );
    final result = await api.list(page: 2, type: '6', keyword: '星 & 播');
    expect(result.pages, 3);
    expect(result.films.single.id, '7');
  });
  test('rejects malformed and failed responses', () async {
    for (final response in [
      '<html>maintenance</html>',
      '[]',
      '{"code":0,"msg":"error"}',
    ]) {
      final api = FilmApi(
        client: MockClient((_) async => http.Response(response, 200)),
      );
      await expectLater(api.categories(), throwsA(isA<ApiFailure>()));
    }
  });
}
