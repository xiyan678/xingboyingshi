import 'hls_ad_filter.dart';

class AdFreeSource {
  final Uri uri;
  final FilteredPlaylist? playlist;
  final Future<void> Function()? _cleanup;
  Future<void>? _disposing;
  AdFreeSource(this.uri, {this.playlist, Future<void> Function()? cleanup})
      : _cleanup = cleanup;

  Duration toSource(Duration position) =>
      playlist?.toSource(position) ?? position;
  Duration toPlayback(Duration position) =>
      playlist?.toPlayback(position) ?? position;

  Future<void> dispose() => _disposing ??= _cleanup?.call() ?? Future.value();
}
