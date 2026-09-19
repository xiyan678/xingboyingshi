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

bool _consecutive(_Segment left, _Segment right) {
  final a = _sequence(left.uri), b = _sequence(right.uri);
  return a != null && b != null && a.$1 == b.$1 && a.$2 + 1 == b.$2;
}

bool _continuousRange(List<_Segment> segments, int start, int end) {
  for (var i = start + 1; i < end; i++) {
    if (!_consecutive(segments[i - 1], segments[i])) return false;
  }
  return true;
}

Set<int> _detectNumberedSplices(List<_Segment> segments) {
  final removed = <int>{};
  if (segments.length < 80) return removed;

  final boundaries = <int>[
    0,
    for (var i = 1; i < segments.length; i++)
      if (segments[i].discontinuity) i,
    segments.length,
  ];
  for (var group = 1; group < boundaries.length - 1; group++) {
    final start = boundaries[group];
    if (start < 8) continue;
    for (var last = group + 1;
        last < boundaries.length - 1 && last <= group + 3;
        last++) {
      final end = boundaries[last];
      final count = end - start;
      if (end + 8 > segments.length || count > 24) break;
      if (count < 3 ||
          !_continuousRange(segments, start - 8, start) ||
          !_continuousRange(segments, start, end) ||
          !_continuousRange(segments, end, end + 8) ||
          !_consecutive(segments[start - 1], segments[end])) {
        continue;
      }

      final main = _sequence(segments[start - 1].uri)!;
      final splice = _sequence(segments[start].uri)!;
      if (splice.$1 == main.$1 && (splice.$2 - main.$2).abs() < 1000) {
        continue;
      }
      final duration = segments
          .sublist(start, end)
          .fold(Duration.zero, (sum, segment) => sum + segment.duration);
      if (duration < const Duration(seconds: 8) ||
          duration > const Duration(seconds: 90)) {
        continue;
      }
      removed.addAll(List.generate(count, (index) => start + index));
      break;
    }
  }

  final total = segments.fold<int>(
      0, (sum, segment) => sum + segment.duration.inMicroseconds);
  final cut = removed.fold<int>(
      0, (sum, index) => sum + segments[index].duration.inMicroseconds);
  if (removed.length > segments.length * 0.08 || cut > total * 0.08) {
    return <int>{};
  }
  return removed;
}

/// Removes explicit ad cues and short numbered splices that are surrounded by
/// a long main sequence which resumes at exactly the next segment. Unknown,
/// encrypted, live and unsupported structures remain untouched.
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
  final splices = _detectNumberedSplices(segments);
  final output = <String>[...headers];
  final cuts = <AdCut>[];
  var position = Duration.zero;
  var removed = 0, kept = 0;
  var resetDecoder = false;
  for (var index = 0; index < segments.length; index++) {
    final segment = segments[index];
    final end = position + segment.duration;
    if (segment.markedAd || splices.contains(index)) {
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
