import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xingbo_app/ad_free_source_io.dart';
import 'package:xingbo_app/hls_ad_filter.dart';

final media = Uri.parse(
    'https://v.lfthirtytwo.com/20260906/10215_743533c9/2000k/hls/mixed.m3u8');
final master = media.resolve('../../index.m3u8');
final fixture = File('test/fixtures/lfthirtytwo-mixed.m3u8').readAsStringSync();

List<String> segments(String text) => text
    .split(RegExp(r'\r?\n'))
    .where((line) => line.isNotEmpty && !line.startsWith('#'))
    .toList();

String synthetic(
    {int insertAt = 50,
    int adCount = 6,
    int adSeconds = 5,
    String stem = 'episode_',
    bool boundaries = true,
    bool cue = false}) {
  final lines = ['#EXTM3U', '#EXT-X-TARGETDURATION:60'];
  for (var i = 0; i < 180; i++) {
    if (i == insertAt) {
      if (boundaries) lines.add('#EXT-X-DISCONTINUITY');
      if (cue) lines.add('#EXT-X-CUE-OUT:${adCount * adSeconds}');
      for (var j = 0; j < adCount; j++) {
        lines.addAll(['#EXTINF:$adSeconds,', 'sponsor_${9000 + j}.ts']);
      }
      if (cue) lines.add('#EXT-X-CUE-IN');
      if (boundaries) lines.add('#EXT-X-DISCONTINUITY');
    }
    if (i % 10 == 0 && boundaries) lines.add('#EXT-X-DISCONTINUITY');
    lines.addAll(['#EXTINF:5,', '$stem$i.ts']);
  }
  return '${lines.join('\n')}\n#EXT-X-ENDLIST\n';
}

void main() {
  test('real numbered playlist removes only two proven inserted runs', () {
    expect(segments(fixture), hasLength(717));
    final result = filterHlsAds(fixture, media)!;
    expect(result.removedSegments, 14);
    expect(result.cuts, hasLength(2));
    expect(result.removedDuration, const Duration(milliseconds: 51400));
    expect(segments(result.text), hasLength(703));
  });

  test('clean, live, encrypted or malformed playlists are untouched', () {
    for (final text in [
      fixture.replaceAll('#EXT-X-ENDLIST', ''),
      fixture.replaceFirst(
          '#EXTINF:', '#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXTINF:'),
      fixture.replaceFirst('#EXTINF:', '#EXT-X-BYTERANGE:100\n#EXTINF:'),
      fixture.replaceFirst('#EXTINF:', '#EXT-X-MAP:URI="init.mp4"\n#EXTINF:'),
      fixture.replaceFirst('#EXTINF:',
          '#EXT-X-PROGRAM-DATE-TIME:2026-09-06T00:00:00Z\n#EXTINF:'),
      fixture.replaceFirst('#EXTINF:4.000,', '#EXTINF:NaN,'),
      fixture.replaceFirst('#EXTINF:4.000,', '#EXTINF:-1,'),
      '<html>unavailable</html>',
    ]) {
      expect(filterHlsAds(text, media), isNull);
    }
  });

  test('absolute and signed segment URLs retain their query strings', () {
    final signed = fixture.replaceAllMapped(
        RegExp(r'^[^#\r\n]+\.ts$', multiLine: true),
        (match) => '${media.resolve(match[0]!)}?token=a%2Bb&expires=123');
    final result = filterHlsAds(signed, media)!;
    expect(result.removedSegments, 14);
    expect(result.text, contains('?token=a%2Bb&expires=123'));
  });

  test('a different CDN is not enough evidence to delete video', () {
    final external = fixture.replaceAllMapped(
        RegExp(r'^51b815aafe80001[^\r\n]+', multiLine: true),
        (match) => 'https://other.example/${match[0]}');
    final result = filterHlsAds(external, media)!;
    expect(result.removedSegments, 14);
    expect(result.text, contains('https://other.example/'));
  });

  test('ordinary discontinuities and sequence restarts do not prove a splice',
      () {
    expect(filterHlsAds(synthetic(adCount: 0), media), isNull);
    expect(filterHlsAds(synthetic(boundaries: false), media), isNull);
    final brokenMain =
        synthetic().replaceAll('episode_50.ts', 'episode_777.ts');
    expect(filterHlsAds(brokenMain, media), isNull);
    expect(filterHlsAds(synthetic(adCount: 30, adSeconds: 5), media), isNull);
    final differentScene = synthetic()
        .replaceAll('episode_', 'scene_')
        .replaceAll('sponsor_', 'scene_');
    final noRestoredSequence =
        differentScene.replaceAllMapped(RegExp(r'scene_([0-9]+)\.ts'), (match) {
      final number = int.parse(match[1]!);
      return 'scene_${number >= 50 && number < 9000 ? number + 6 : number}.ts';
    });
    expect(filterHlsAds(noRestoredSequence, media), isNull);
  });

  test('a short consecutive island with exact main resumption is removed', () {
    final result = filterHlsAds(synthetic(), media)!;
    expect(result.removedSegments, 6);
    expect(result.removedDuration, const Duration(seconds: 30));
    expect(result.text, isNot(contains('sponsor_9000.ts')));
    expect(result.text, contains('episode_49.ts'));
    expect(result.text, contains('episode_50.ts'));
  });

  test('explicit cue markers cover preroll and do not need numeric filenames',
      () {
    final text = synthetic(insertAt: 0, boundaries: false, cue: true)
        .replaceAllMapped(
            RegExp(r'sponsor_[0-9]+\.ts'), (_) => 'advertisement.ts');
    final result = filterHlsAds(text, media)!;
    expect(result.removedSegments, 6);
    expect(result.cuts.single.start, Duration.zero);
    expect(result.toSource(Duration.zero), const Duration(seconds: 30));
    expect(filterHlsAds(text.replaceAll('#EXT-X-CUE-IN', ''), media), isNull);
  });

  test('single-variant master becomes a private local HLS file and cleans up',
      () async {
    final marked = synthetic(insertAt: 50, cue: true);
    final markedMedia = media.replace(path: '/marked.m3u8');
    final markedMaster = markedMedia.resolve('master.m3u8');
    final markedClient = MockClient((request) async => http.Response(
        request.url == markedMaster
            ? '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000\nmarked.m3u8\n'
            : marked,
        200));
    final prepared =
        await prepareLocalAdFreeSource(markedMaster, client: markedClient);
    expect(prepared.uri.scheme, 'file');
    expect(prepared.playlist?.removedSegments, 6);
    final file = File.fromUri(prepared.uri);
    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), prepared.playlist!.text);
    await prepared.dispose();
    await prepared.dispose();
    expect(await file.parent.exists(), isFalse);
    markedClient.close();
  });

  test('proven numbered splice becomes a private filtered HLS file', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return http.Response(
          request.url == master
              ? '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000\n2000k/hls/mixed.m3u8\n'
              : fixture,
          200);
    });
    final prepared = await prepareLocalAdFreeSource(master, client: client);
    expect(requests, [master, media]);
    expect(prepared.uri.scheme, 'file');
    expect(prepared.playlist?.removedSegments, 14);
    await prepared.dispose();
    client.close();
  });

  test('MP4 sources make no filtering network request', () async {
    final source = Uri.parse('https://other.example/video.mp4');
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('', 500);
    });
    final prepared = await prepareLocalAdFreeSource(source, client: client);
    expect(prepared.uri, source);
    expect(prepared.playlist, isNull);
    expect(calls, 0);
    client.close();
  });

  test('failed request or malformed HLS falls back to the original URL',
      () async {
    for (final response in [
      http.Response('offline', 503),
      http.Response('<html/>', 200)
    ]) {
      final client = MockClient((_) async => response);
      final prepared = await prepareLocalAdFreeSource(master, client: client);
      expect(prepared.uri, master);
      expect(prepared.playlist, isNull);
      client.close();
    }
  });

  test('redirect cannot cause HTTP, credential-bearing or cyclic requests',
      () async {
    for (final location in [
      'http://127.0.0.1/private',
      'https://username:password@other.example/a.m3u8',
      '$master'
    ]) {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('', 302, headers: {'location': location});
      });
      final prepared = await prepareLocalAdFreeSource(master, client: client);
      expect(prepared.uri, master);
      expect(calls, 1);
      client.close();
    }
  });

  test('adaptive or alternate-audio master is preserved', () async {
    final client = MockClient((_) async => http.Response(
        '#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,URI="audio.m3u8"\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=800000\n2000k/hls/mixed.m3u8\n',
        200));
    final prepared = await prepareLocalAdFreeSource(master, client: client);
    expect(prepared.uri, master);
    expect(prepared.playlist, isNull);
    client.close();
  });

  test('oversized playlists are rejected without creating a local file',
      () async {
    final client = MockClient(
        (_) async => http.Response('x' * (2 * 1024 * 1024 + 1), 200));
    final prepared = await prepareLocalAdFreeSource(master, client: client);
    expect(prepared.uri, master);
    expect(prepared.playlist, isNull);
    client.close();
  });
}
