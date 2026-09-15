import 'dart:convert';

import 'package:http/http.dart' as http;
import 'service.dart';

const apiEndpoint = String.fromEnvironment('API_ENDPOINT',
    defaultValue: 'https://xbxx.pro/api.php/provide/vod/');
const posterProxy = String.fromEnvironment('POSTER_PROXY');

class ApiFailure implements Exception {
  final String message;
  ApiFailure(this.message);
  @override
  String toString() => message;
}

class Film {
  final Map<String, dynamic> data;
  Film(this.data);
  String get id => '${data['vod_id'] ?? ''}';
  String get name => '${data['vod_name'] ?? '未命名影片'}';
  String get poster => Uri.parse('https://xbxx.pro/')
      .resolve('${data['vod_pic'] ?? ''}')
      .toString();
  String get remark => '${data['vod_remarks'] ?? ''}';
  String get summary => '${data['vod_content'] ?? data['vod_blurb'] ?? ''}'
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ');
  List<PlayLine> get lines => parseLines(
        '${data['vod_play_from'] ?? ''}',
        '${data['vod_play_url'] ?? ''}',
      );
}

class Episode {
  final String name, url;
  Episode(this.name, this.url);
}

class PlayLine {
  final String name;
  final List<Episode> episodes;
  PlayLine(this.name, this.episodes);
}

List<PlayLine> parseLines(String names, String urls) {
  if (urls.isEmpty) return [];
  final labels = names.split(r'$$$');
  return urls
      .split(r'$$$')
      .asMap()
      .entries
      .map((line) {
        final episodes = <Episode>[];
        for (final item in line.value.split('#')) {
          final split = item.indexOf(r'$');
          if (split < 0) continue;
          final url = item.substring(split + 1).trim();
          final uri = Uri.tryParse(url);
          if (uri != null &&
              (uri.scheme == 'https' || uri.scheme == 'http') &&
              uri.host.isNotEmpty) {
            episodes.add(Episode(item.substring(0, split), url));
          }
        }
        return PlayLine(
          line.key < labels.length ? labels[line.key] : '线路 ${line.key + 1}',
          episodes,
        );
      })
      .where((line) => line.episodes.isNotEmpty)
      .toList();
}

class Catalog {
  final List<Film> films;
  final int pages;
  Catalog(this.films, this.pages);
}

class FilmApi {
  final http.Client client;
  FilmApi({http.Client? client}) : client = client ?? http.Client();
  Future<Map<String, dynamic>> request(Map<String, String> query, {String endpoint = apiEndpoint}) async {
    try {
      final uri = Uri.parse(endpoint).replace(queryParameters: query);
      final response =
          await client.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw ApiFailure('服务器暂时不可用，请稍后重试');
      if (response.body.trim() == 'closed') {
        throw ApiFailure('影片接口尚未开启，请在网站后台开启视频 API 后重试');
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) throw ApiFailure('影片接口数据格式不正确');
      if ('${body['code']}' != '1') throw ApiFailure('影片接口未返回成功状态');
      return body;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw ApiFailure('连接失败或数据无法读取，请检查网络后重试');
    }
  }

  Future<List<Map<String, dynamic>>> categories() async {
    final data = await request({'ac': 'list'});
    return (data['class'] as List? ?? [])
        .map((v) => Map<String, dynamic>.from(v))
        .toList();
  }

  Future<Catalog> list({
    int page = 1,
    String keyword = '',
    String type = '',
    String genre = '',
    String year = '',
    String area = '',
    String lang = '',
    String letter = '',
    String sort = 'time',
  }) async {
    final params = {
      'ac': 'detail',
      'pg': '$page',
      if (keyword.isNotEmpty) 'wd': keyword,
      if (type.isNotEmpty) 't': type,
      if (genre.isNotEmpty) 'class': genre,
      if (year.isNotEmpty) 'year': year,
      if (area.isNotEmpty) 'area': area,
      if (lang.isNotEmpty) 'lang': lang,
      if (letter.isNotEmpty) 'letter': letter,
      'by': sort,
    };
    // The built-in Apple CMS V10 provider endpoint is the canonical catalogue.
    // The Xingbo extension remains responsible for accounts, progress and danmaku.
    final filtered = type.isNotEmpty || genre.isNotEmpty || year.isNotEmpty ||
        area.isNotEmpty || lang.isNotEmpty || letter.isNotEmpty || sort != 'time';
    final data = filtered
        ? await request({...params, 'sort': sort}, endpoint: Uri.parse(extensionEndpoint).resolve('catalog').toString())
        : await request(params);
    return Catalog(
      (data['list'] as List? ?? [])
          .map((v) => Film(Map<String, dynamic>.from(v)))
          .toList(),
      int.tryParse('${data['pagecount']}') ?? 1,
    );
  }

  Future<Film> detail(String id) async {
    final data = await request({'ac': 'detail', 'ids': id});
    final list = data['list'] as List? ?? [];
    if (list.isEmpty) throw ApiFailure('影片已下架或不存在');
    return Film(Map<String, dynamic>.from(list.first));
  }
}
