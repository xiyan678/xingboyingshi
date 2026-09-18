import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Serves one immutable playlist on loopback, never an arbitrary URL proxy.
class LocalHlsServer {
  final HttpServer _server;
  final Uri uri;
  LocalHlsServer._(this._server, this.uri);

  static Future<LocalHlsServer> start(String playlist) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final random = Random.secure();
    final token = List.generate(
            24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    final path = '/$token/filtered.m3u8';
    final bytes = utf8.encode(playlist);
    server.listen((request) async {
      try {
        if (request.uri.path != path || request.uri.hasQuery) {
          request.response.statusCode = HttpStatus.notFound;
        } else if (request.method != 'GET' && request.method != 'HEAD') {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          request.response.headers.set('Allow', 'GET, HEAD');
        } else {
          request.response.headers.contentType =
              ContentType('application', 'vnd.apple.mpegurl');
          request.response.headers.set('Cache-Control', 'no-store');
          request.response.contentLength = bytes.length;
          if (request.method == 'GET') request.response.add(bytes);
        }
        await request.response.close();
      } on SocketException {
        // Player cancellation and session shutdown can disconnect mid-response.
      } on HttpException {
        // Closing a player must not surface an asynchronous server error.
      }
    });
    return LocalHlsServer._(
        server, Uri.parse('http://127.0.0.1:${server.port}$path'));
  }

  Future<void> close() async {
    await _server.close(force: true);
  }
}
