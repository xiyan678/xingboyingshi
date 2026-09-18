import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'ad_free_source_model.dart';
import 'hls_ad_filter.dart';
import 'local_hls_server.dart';

Future<AdFreeSource> prepareAdFreeSource(Uri source) async {
  if (!Platform.isAndroid && !Platform.isIOS) return AdFreeSource(source);
  return prepareLocalAdFreeSource(source, useLoopback: Platform.isIOS);
}

/// Only playlist text is downloaded. Media remains on the original CDN.
Future<AdFreeSource> prepareLocalAdFreeSource(Uri source,
    {http.Client? client,
    Directory? temporaryDirectory,
    bool useLoopback = false}) async {
  if (!canInspectHls(source)) return AdFreeSource(source);
  final transport = client ?? http.Client();
  Directory? directory;
  try {
    final loaded = await _loadMediaPlaylist(transport, source)
        .timeout(const Duration(seconds: 12));
    final filtered = filterHlsAds(loaded.$2, loaded.$1);
    if (filtered == null) return AdFreeSource(source);
    if (useLoopback) {
      final server = await LocalHlsServer.start(filtered.text);
      return AdFreeSource(server.uri,
          playlist: filtered, cleanup: server.close);
    }
    final created = await (temporaryDirectory ?? Directory.systemTemp)
        .createTemp('xingbo_hls_');
    directory = created;
    final file = File('${created.path}/filtered.m3u8');
    await file.writeAsString(filtered.text, flush: true);
    return AdFreeSource(file.uri, playlist: filtered, cleanup: () async {
      try {
        await created.delete(recursive: true);
      } on FileSystemException {
        // Android may already have reclaimed the application's temporary cache.
      }
    });
  } catch (_) {
    if (directory != null) {
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        // A failed preparation must not prevent the original stream playing.
      }
    }
    return AdFreeSource(source);
  } finally {
    if (client == null) transport.close();
  }
}

Future<(Uri, String)> _loadMediaPlaylist(http.Client client, Uri source) async {
  var uri = source;
  final visited = <Uri>{};
  for (var depth = 0; depth < 6; depth++) {
    if (!canInspectHls(uri) || !visited.add(uri)) {
      throw const FormatException('Unsupported playlist target');
    }
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await client.send(request);
    if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
      await response.stream.listen(null).cancel();
      final location = response.headers['location'];
      if (location == null) throw const FormatException('Missing redirect');
      uri = uri.resolve(location);
      continue;
    }
    if (response.statusCode != 200) {
      await response.stream.listen(null).cancel();
      throw HttpException('Playlist request failed', uri: uri);
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > 2 * 1024 * 1024) {
        throw const FormatException('Playlist exceeds size limit');
      }
      bytes.addAll(chunk);
    }
    final text = utf8.decode(bytes).replaceFirst('\uFEFF', '');
    final lines = text.split(RegExp(r'\r?\n')).map((s) => s.trim()).toList();
    if (lines.first != '#EXTM3U') throw const FormatException('Not HLS');
    if (!lines.any((line) => line.startsWith('#EXT-X-STREAM-INF:'))) {
      return (uri, text);
    }
    // Separate audio and adaptive variants need synchronized edits across tracks.
    // Preserve their original playback until that synchronization is supported.
    if (lines.where((line) => line.startsWith('#EXT-X-STREAM-INF:')).length !=
            1 ||
        lines.any((line) =>
            line.startsWith('#EXT-X-MEDIA:') ||
            line.startsWith('#EXT-X-SESSION-KEY:'))) {
      throw const FormatException('Unsupported master playlist');
    }
    final index =
        lines.indexWhere((line) => line.startsWith('#EXT-X-STREAM-INF:'));
    final targets = lines
        .skip(index + 1)
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList();
    if (targets.length != 1) throw const FormatException('Invalid variant');
    uri = uri.resolve(targets.single);
  }
  throw const FormatException('Playlist nesting limit');
}
