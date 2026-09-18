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
  test('real source loses only the 14 known ads; all normal URLs stay in order',
      () {
    final result = filterHlsAds(fixture, media)!;
    expect(result.removedSegments, 14);
    expect(result.cuts, hasLength(2));
    expect(result.cuts[0].start.inMilliseconds, 297800);
    expect(result.cuts[0].end.inMilliseconds, 323500);
    expect(result.cuts[1].start.inMilliseconds, 2002660);
    expect(result.cuts[1].end.inMilliseconds, 2028360);
    expect(result.removedDuration.inMilliseconds, 51400);
    final original = segments(fixture);
    final cleaned = segments(result.text);
    expect(original, hasLength(717));
    expect(cleaned, hasLength(703));
    expect(
        cleaned,
        original
            .where((line) =>
                !RegExp(r'51b815aafe805117(0[3-9]|1[0-6])\.ts$').hasMatch(line))
            .map((line) => media.resolve(line).toString())
            .toList());
    expect(RegExp(r'^#EXTINF:', multiLine: true).allMatches(result.text).length,
        703);
    expect(result.text.endsWith('#EXT-X-ENDLIST\n'), isTrue);
    expect(result.text.contains('#EXT-X-DISCONTINUITY\n#EXT-X-DISCONTINUITY'),
        isFalse);
  });

  test('source and cleaned clocks agree before/inside/after both ad blocks',
      () {
    final result = filterHlsAds(fixture, media)!;
    for (final ms in [0, 297799, 323500, 500000, 2002659, 2028360, 2500000]) {
      final position = Duration(milliseconds: ms);
      expect(result.toSource(result.toPlayback(position)), position);
    }
    expect(
        result.toPlayback(const Duration(milliseconds: 307000)).inMilliseconds,
        297800);
    expect(result.toSource(const Duration(milliseconds: 297800)).inMilliseconds,
        323500);
    expect(
        result.toPlayback(const Duration(milliseconds: 2010000)).inMilliseconds,
        1976960);
    expect(
        result.toSource(const Duration(milliseconds: 1976960)).inMilliseconds,
        2028360);
  });

  test('detection is independent of title path, filename prefix and CDN', () {
    for (final uri in [
      media.replace(host: 'another.example'),
      media.replace(port: 444),
      media.replace(path: '/different-title/mixed.m3u8'),
    ]) {
      expect(
          filterHlsAds(fixture.replaceAll('51b815aafe', 'fresh_title_'), uri)
              ?.removedSegments,
          14);
    }
  });

  test('clean, live, encrypted or malformed playlists are untouched', () {
    for (final text in [
      filterHlsAds(fixture, media)!.text,
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
    expect(
        segments(result.text)
            .every((s) => s.endsWith('?token=a%2Bb&expires=123')),
        isTrue);
  });

  test('foreign ad CDN is detected when the main sequence resumes intact', () {
    final external = fixture.replaceAllMapped(
        RegExp(r'^51b815aafe805[^\r\n]+', multiLine: true),
        (match) => 'https://other.example/${match[0]}');
    expect(filterHlsAds(external, media)?.removedSegments, 14);
  });

  test('four real videos have independently computed ad positions', () {
    final cases = [
      ('lfthirtytwo-mixed.m3u8', 297800, 2002660),
      ('sports-mixed.m3u8', 296920, 2004060),
      ('episode1-mixed.m3u8', 299360, 2003740),
      ('episode2-mixed.m3u8', 297880, 2002460),
    ];
    for (final item in cases) {
      final input = File('test/fixtures/${item.$1}').readAsStringSync();
      final result = filterHlsAds(
          input, Uri.parse('https://new-source.example/${item.$1}'))!;
      expect(result.cuts, hasLength(2), reason: item.$1);
      expect(
          result.cuts.map((c) => c.start.inMilliseconds), [item.$2, item.$3]);
      expect(result.removedSegments, 14);
      expect(result.removedDuration.inMilliseconds, 51400);
      final original = segments(input);
      expect(segments(result.text).length, original.length - 14);
    }
  });

  test('ad locations and lengths change freely for each video', () {
    for (final at in [7, 31, 75, 136, 172]) {
      for (final length in [2, 7, 13]) {
        final text = synthetic(
            insertAt: at,
            adCount: length,
            adSeconds: 7,
            stem: 'film${at}part_');
        final result = filterHlsAds(text, media)!;
        expect(result.removedSegments, length);
        expect(result.cuts.single.start.inSeconds, at * 5);
        expect(result.removedDuration.inSeconds, length * 7);
        expect(
            segments(result.text),
            segments(text)
                .where((line) => !line.startsWith('sponsor_'))
                .map((line) => media.resolve(line).toString())
                .toList());
      }
    }
  });

  test(
      'ordinary discontinuities and sequence restarts never suffice for removal',
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
    final file = File.fromUri(prepared.uri);
    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), prepared.playlist!.text);
    await prepared.dispose();
    await prepared.dispose();
    expect(await file.parent.exists(), isFalse);
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
