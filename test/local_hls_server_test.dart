import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xingbo_app/ad_free_source_io.dart';
import 'package:xingbo_app/local_hls_server.dart';

void main() {
  test('loopback serves only the private playlist, supports HEAD and closes',
      () async {
    const playlist = '#EXTM3U\n#EXT-X-ENDLIST\n';
    final server = await LocalHlsServer.start(playlist);
    addTearDown(server.close);
    expect(server.uri.host, '127.0.0.1');
    final client = http.Client();
    addTearDown(client.close);
    final response = await client.get(server.uri);
    expect(response.statusCode, 200);
    expect(response.body, playlist);
    expect(response.headers['content-type'],
        contains('application/vnd.apple.mpegurl'));
    final head = await client.head(server.uri);
    expect(head.statusCode, 200);
    expect(head.body, isEmpty);
    expect(head.headers['content-length'], '${playlist.length}');
    expect((await client.get(server.uri.replace(path: '/'))).statusCode, 404);
    expect(
        (await client.get(server.uri.replace(query: 'url=https://example.com')))
            .statusCode,
        404);
    expect((await client.post(server.uri)).statusCode, 405);
    await server.close();
    await expectLater(
        client.get(server.uri), throwsA(isA<http.ClientException>()));
  });

  test('iOS preparation serves filtered HLS and preserves the source clock',
      () async {
    const fixture = '#EXTM3U\n'
        '#EXT-X-TARGETDURATION:10\n'
        '#EXTINF:10,\nmain0.ts\n'
        '#EXT-X-CUE-OUT:20\n'
        '#EXTINF:10,\nad0.ts\n'
        '#EXTINF:10,\nad1.ts\n'
        '#EXT-X-CUE-IN\n'
        '#EXTINF:10,\nmain1.ts\n'
        '#EXT-X-ENDLIST\n';
    final source = Uri.parse('https://example.com/video/mixed.m3u8');
    final transport = MockClient((_) async => http.Response(fixture, 200));
    final prepared = await prepareLocalAdFreeSource(source,
        client: transport, useLoopback: true);
    addTearDown(prepared.dispose);
    addTearDown(transport.close);
    expect(prepared.uri.host, '127.0.0.1');
    expect(prepared.playlist?.removedSegments, 2);
    final response = await http.get(prepared.uri);
    expect(response.body, prepared.playlist!.text);
    expect(response.body, contains('https://example.com/video/'));
    expect(prepared.toSource(const Duration(seconds: 10)),
        const Duration(seconds: 30));
    await prepared.dispose();
    await prepared.dispose();
  });
}
