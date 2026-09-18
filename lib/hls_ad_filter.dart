bool canInspectHls(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty &&
    uri.path.toLowerCase().endsWith('.m3u8');

class AdCut {
  final Duration start, end;
  const AdCut(this.start, this.end);
  Duration get duration => end - start;
}

class FilteredPlaylist {
  final String text;
  final List<AdCut> cuts;
  final int removedSegments;
  final Duration originalDuration;
  const FilteredPlaylist(
      this.text, this.cuts, this.removedSegments, this.originalDuration);

  Duration get removedDuration =>
      cuts.fold(Duration.zero, (total, cut) => total + cut.duration);

  // Persist the source clock so old history and server-side danmaku still match.
  Duration toSource(Duration position) {
    var removed = Duration.zero;
    for (final cut in cuts) {
      if (position < cut.start - removed) break;
      removed += cut.duration;
    }
    return position + removed;
  }

  Duration toPlayback(Duration position) {
    var removed = Duration.zero;
    for (final cut in cuts) {
      if (position < cut.start) break;
      if (position < cut.end) return cut.start - removed;
      removed += cut.duration;
    }
    return position - removed;
  }
}

class _Segment {
  final Uri uri;
  final String extinf;
  final Duration duration;
  final bool discontinuity, markedAd;
  const _Segment(
      this.uri, this.extinf, this.duration, this.discontinuity, this.markedAd);
}

String _directory(Uri uri) => '${uri.origin}${uri.resolve('.').path}';

(String, int)? _sequence(Uri uri) {
  final match = RegExp(r'^(.*?)([0-9]+)(\.[a-zA-Z0-9]+)$')
      .firstMatch(uri.pathSegments.last);
  if (match == null) return null;
  final number = int.tryParse(match[2]!);
  if (number == null) return null;
  return ('${_directory(uri)}${match[1]}${match[3]}', number);
}

bool _consecutive(_Segment a, _Segment b) {
  final left = _sequence(a.uri), right = _sequence(b.uri);
  return left != null &&
      right != null &&
      left.$1 == right.$1 &&
      left.$2 + 1 == right.$2;
}

Set<int> _detectInsertions(List<_Segment> segments) {
  final removed = <int>{};
  if (segments.length < 40) return removed;
  var consecutive = 0;
  for (var i = 1; i < segments.length; i++) {
    if (_consecutive(segments[i - 1], segments[i])) consecutive++;
  }
  // A continuous, numbered main sequence must dominate the video.
  if (consecutive / (segments.length - 1) < 0.8) return removed;
  final boundaries = <int>[
    0,
    for (var i = 1; i < segments.length; i++)
      if (segments[i].discontinuity) i,
    segments.length,
  ];
  for (var group = 1; group < boundaries.length - 1; group++) {
    final start = boundaries[group];
    if (start < 3 || removed.contains(start)) continue;
    // Ads may contain several discontinuity groups of their own.
    for (var last = group + 1;
        last < boundaries.length - 1 && last <= group + 4;
        last++) {
      final end = boundaries[last];
      if (end + 2 >= segments.length || end - start > 40) break;
      if (end - start < 2 ||
          !_consecutive(segments[start - 3], segments[start - 2]) ||
          !_consecutive(segments[start - 2], segments[start - 1]) ||
          !_consecutive(segments[start - 1], segments[end]) ||
          !_consecutive(segments[end], segments[end + 1]) ||
          !_consecutive(segments[end + 1], segments[end + 2])) {
        continue;
      }
      final anchor = _sequence(segments[start - 1].uri)!;
      var duration = Duration.zero;
      var foreign = true;
      for (var i = start; i < end; i++) {
        duration += segments[i].duration;
        final sequence = _sequence(segments[i].uri);
        if (sequence == null) {
          foreign &= _directory(segments[i].uri) !=
              _directory(segments[start - 1].uri);
        } else {
          foreign &=
              sequence.$1 != anchor.$1 || (sequence.$2 - anchor.$2).abs() >= 50;
        }
      }
      if (!foreign ||
          duration < const Duration(seconds: 5) ||
          duration > const Duration(seconds: 120)) {
        continue;
      }
      removed.addAll(List.generate(end - start, (i) => start + i));
      break;
    }
  }
  final total = segments.fold<int>(0, (n, s) => n + s.duration.inMicroseconds);
  final cut =
      removed.fold<int>(0, (n, i) => n + segments[i].duration.inMicroseconds);
  // Refuse large structural edits, even if individual groups look suspicious.
  if (removed.length > segments.length * 0.15 || cut > total * 0.15) {
    return <int>{};
  }
  return removed;
}

/// Detects short foreign runs spliced into a continuous main sequence, or
/// explicit CUE-OUT/CUE-IN breaks. Never treats discontinuity alone as an ad.
/// Unknown, encrypted, live and unsupported structures remain untouched.
FilteredPlaylist? filterHlsAds(String text, Uri base) {
  if (!canInspectHls(base)) return null;
  final lines = text.replaceFirst('\uFEFF', '').split(RegExp(r'\r?\n'));
  if (lines.first.trim() != '#EXTM3U') return null;
  final headers = <String>[];
  final segments = <_Segment>[];
  String? extinf;
  Duration? duration;
  var discontinuity = false, ended = false, cueOpen = false;
  const headerTags = {
    '#EXTM3U',
    '#EXT-X-VERSION',
    '#EXT-X-TARGETDURATION',
    '#EXT-X-MEDIA-SEQUENCE',
    '#EXT-X-PLAYLIST-TYPE',
    '#EXT-X-INDEPENDENT-SEGMENTS',
  };
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (!line.startsWith('#')) {
      if (extinf == null || duration == null || ended) return null;
      final uri = base.resolve(line);
      if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) return null;
      segments.add(_Segment(uri, extinf, duration, discontinuity, cueOpen));
      extinf = null;
      duration = null;
      discontinuity = false;
      continue;
    }
    final tag = line.split(':').first;
    if (tag == '#EXTINF') {
      if (extinf != null || ended) return null;
      final seconds = double.tryParse(line.substring(8).split(',').first);
      if (seconds == null || !seconds.isFinite || seconds <= 0) return null;
      extinf = line;
      duration = Duration(microseconds: (seconds * 1000000).round());
    } else if (tag == '#EXT-X-CUE-OUT') {
      if (extinf != null || cueOpen || ended) return null;
      cueOpen = true;
    } else if (tag == '#EXT-X-CUE-IN') {
      if (extinf != null || !cueOpen || ended) return null;
      cueOpen = false;
    } else if (tag == '#EXT-X-CUE-OUT-CONT') {
      if (!cueOpen || ended) return null;
    } else if (tag == '#EXT-X-DISCONTINUITY') {
      if (extinf != null) return null;
      discontinuity = true;
    } else if (tag == '#EXT-X-ENDLIST') {
      if (extinf != null) return null;
      ended = true;
    } else if (headerTags.contains(tag)) {
      if (segments.isNotEmpty || extinf != null) return null;
      headers.add(line);
    } else if (line.startsWith('#EXT')) {
      // This excludes keys/implicit IVs, byte ranges, date ranges and LL-HLS.
      return null;
    }
  }
  if (!ended || cueOpen || extinf != null || segments.isEmpty) return null;
  final insertions = _detectInsertions(segments);
  final output = <String>[...headers];
  final cuts = <AdCut>[];
  var position = Duration.zero;
  var removed = 0, kept = 0;
  var resetDecoder = false;
  for (var index = 0; index < segments.length; index++) {
    final segment = segments[index];
    final end = position + segment.duration;
    if (segment.markedAd || insertions.contains(index)) {
      removed++;
      if (cuts.isNotEmpty && cuts.last.end == position) {
        cuts[cuts.length - 1] = AdCut(cuts.last.start, end);
      } else {
        cuts.add(AdCut(position, end));
      }
      resetDecoder = true;
    } else {
      if (segment.discontinuity || resetDecoder) {
        output.add('#EXT-X-DISCONTINUITY');
      }
      output.addAll([segment.extinf, segment.uri.toString()]);
      resetDecoder = false;
      kept++;
    }
    position = end;
  }
  if (removed == 0 || kept == 0) return null;
  output.add('#EXT-X-ENDLIST');
  return FilteredPlaylist(
      '${output.join('\n')}\n', List.unmodifiable(cuts), removed, position);
}
