import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const extensionEndpoint = String.fromEnvironment('EXTENSION_ENDPOINT',
    defaultValue: 'https://xbxx.pro/api.php/xingbo/');

class ServiceError implements Exception {
  final String message;
  final int code;
  ServiceError(this.message, [this.code = 503]);
  @override
  String toString() => message;
}

abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  final storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => storage.read(key: 'xingbo-session');
  @override
  Future<void> write(String value) =>
      storage.write(key: 'xingbo-session', value: value);
  @override
  Future<void> clear() => storage.delete(key: 'xingbo-session');
}

class AppService extends ChangeNotifier {
  static final instance = AppService();
  final http.Client client;
  final TokenStore tokens;
  String? _token;
  Map<String, dynamic>? user;
  bool available = false, connecting = false;
  String? connectionError;
  Map<String, dynamic> capabilities = {};
  final Map<String, String> _cookies = {};
  int _sessionEpoch = 0;
  AppService({http.Client? client, TokenStore? tokens})
      : client = client ?? http.Client(),
        tokens = tokens ?? SecureTokenStore();
  String? get userId => user == null ? null : '${user!['id']}';
  bool get loggedIn => _token != null && user != null;
  Future<Map<String, dynamic>> call(String action,
      {Map<String, String> query = const {}, Map<String, String>? body}) async {
    final sentToken = _token;
    final uri = Uri.parse(extensionEndpoint)
        .resolve(action)
        .replace(queryParameters: query.isEmpty ? null : query);
    try {
      final headers = <String, String>{
        'Accept': 'application/json',
        if (sentToken != null) 'Authorization': 'Bearer $sentToken',
        if (_cookies.isNotEmpty)
          'Cookie':
              _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ')
      };
      final r = await (body == null
              ? client.get(uri, headers: headers)
              : client.post(uri, headers: headers, body: body))
          .timeout(const Duration(seconds: 15));
      captureCookies(r.headers['set-cookie']);
      if (r.statusCode != 200) throw ServiceError('网站 APP 扩展尚未部署或暂不可用');
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw ServiceError('网站 APP 接口返回格式异常');
      }
      final code = int.tryParse('${decoded['code']}') ?? 503;
      if (code != 1) {
        if (code == 401 && sentToken != null && _token == sentToken) {
          await forget();
        }
        throw ServiceError('${decoded['msg'] ?? '请求失败'}', code);
      }
      return decoded;
    } on ServiceError {
      rethrow;
    } catch (_) {
      throw ServiceError('暂时无法连接网站 APP 服务，请稍后重试');
    }
  }

  void captureCookies(String? header) {
    if (header == null) return;
    for (final m
        in RegExp(r'(?:^|,\s*)([A-Za-z0-9_]+)=([^;,]*)').allMatches(header)) {
      // Only persist captcha session cookies in memory. CMS login cookies are not credentials for this client.
      if (m.group(1)!.toLowerCase().contains('sess')) {
        _cookies[m.group(1)!] = m.group(2)!;
      }
    }
  }

  Future<void> initialize() async {
    final epoch = _sessionEpoch;
    try {
      final saved = await tokens.read();
      if (epoch != _sessionEpoch) return;
      _token = saved;
    } catch (_) {
      _token = null;
    }
    await connect();
    if (_token != null) {
      try {
        final r = await call('me');
        if (epoch != _sessionEpoch) return;
        user = Map<String, dynamic>.from(r['user']);
        notifyListeners();
      } catch (_) {
        /* Keep token for retry if server is offline; no account data exposed. */
      }
    }
  }

  Future<void> connect() async {
    if (connecting) return;
    connecting = true;
    notifyListeners();
    try {
      capabilities = await call('health');
      available = true;
      connectionError = null;
    } catch (e) {
      available = false;
      connectionError = e.toString();
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<Uint8List> captcha() async {
    try {
      final r = await client
          .get(Uri.parse(extensionEndpoint).resolve('captcha'), headers: {
        if (_cookies.isNotEmpty)
          'Cookie':
              _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ')
      }).timeout(const Duration(seconds: 15));
      captureCookies(r.headers['set-cookie']);
      if (r.statusCode != 200 ||
          !(r.headers['content-type'] ?? '').startsWith('image/')) {
        throw ServiceError('验证码加载失败');
      }
      return r.bodyBytes;
    } on ServiceError {
      rethrow;
    } catch (_) {
      throw ServiceError('验证码加载失败，请重试');
    }
  }

  Future<void> login(String name, String password, String captcha) async {
    final epoch = ++_sessionEpoch;
    final r = await call('login',
        body: {'name': name, 'password': password, 'captcha': captcha});
    if (epoch != _sessionEpoch) return;
    final token = r['token'] as String;
    await tokens.write(token);
    if (epoch != _sessionEpoch) {
      await tokens.clear();
      return;
    }
    _token = token;
    user = Map<String, dynamic>.from(r['user']);
    notifyListeners();
  }

  Future<String> register(String name, String password, String captcha) async {
    final r = await call('register',
        body: {'name': name, 'password': password, 'captcha': captcha});
    return '${r['msg']}';
  }

  Future<void> forget() async {
    ++_sessionEpoch;
    _token = null;
    user = null;
    _cookies.clear();
    try {
      await tokens.clear();
    } finally {
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      await call('logout', body: {});
    } finally {
      await forget();
    }
  }
}
