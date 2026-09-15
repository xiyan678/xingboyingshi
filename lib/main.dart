import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'library.dart';
import 'player.dart';
import 'service.dart';
import 'account.dart';
import 'playback_session.dart';
import 'danmaku.dart';
import 'advertising.dart';
import 'dart:async';

const gold = Color(0xFFFFD16A);
const ink = Color(0xFF0C101A);
const panel = Color(0xFF171D2A);
final appNavigator = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final library = Library(await SharedPreferences.getInstance());
  library.attach(AppService.instance);
  runApp(XingboApp(api: FilmApi(), library: library));
  unawaited(AppService.instance.initialize());
  unawaited(DanmakuSettings.instance.load());
}

class XingboApp extends StatelessWidget {
  final FilmApi api;
  final Library library;
  const XingboApp({super.key, required this.api, required this.library});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '星播影院',
        navigatorKey: appNavigator,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: ink,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF458BFF),
            brightness: Brightness.dark,
            surface: panel,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: ink,
            surfaceTintColor: Colors.transparent,
          ),
          navigationBarTheme: const NavigationBarThemeData(
            backgroundColor: panel,
            indicatorColor: Color(0xFF244269),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: panel,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        home: Shell(api: api, library: library),
      );
}

class Shell extends StatefulWidget {
  final FilmApi api;
  final Library library;
  const Shell({super.key, required this.api, required this.library});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  void open(Film f) => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              DetailPage(api: widget.api, library: widget.library, id: f.id),
        ),
      );
  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(
          index: tab,
          children: [
            CatalogPage(api: widget.api, onOpen: open),
            CatalogPage(api: widget.api, onOpen: open, discover: true),
            AnimatedBuilder(
              animation: widget.library,
              builder: (context, _) => SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const SizedBox(height: 24),
                    const Brand(),
                    const SizedBox(height: 16),
                    AccountPanel(library: widget.library),
                    const SizedBox(height: 12),
                    const Text(
                      '把喜欢的故事，留在这里',
                      style: TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '观看记录',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (widget.library.history.isNotEmpty)
                          TextButton(
                            onPressed: () async {
                              final yes = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('清空观看记录？'),
                                  content: const Text('清空后将无法从原来的进度继续播放。'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('取消'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('清空'),
                                    ),
                                  ],
                                ),
                              );
                              if (yes == true) {
                                try {
                                  await widget.library.clearHistory();
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('清空失败，请联网后重试')));
                                  }
                                }
                              }
                            },
                            child: const Text('清空'),
                          ),
                      ],
                    ),
                    if (widget.library.history.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          '看过的影片会出现在这里',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ...widget.library.history.values.toList().reversed.map(
                          (r) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: SizedBox(
                                width: 44, child: Poster(film: r.film)),
                            title: Text(
                              r.film.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle:
                                Text('${r.episode} · 已看 ${r.seconds ~/ 60} 分钟'),
                            trailing: const Icon(Icons.play_circle_outline),
                            onTap: () => open(r.film),
                          ),
                        ),
                    const SizedBox(height: 24),
                    const Text(
                      '我的收藏',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    if (widget.library.favorites.isEmpty)
                      const Text(
                        '在影片详情页点收藏，方便下次找到',
                        style: TextStyle(color: Colors.white54),
                      ),
                    FilmGrid(
                      films: widget.library.favorites.values
                          .toList()
                          .reversed
                          .toList(),
                      onOpen: open,
                    ),
                    const SizedBox(height: 32),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('关于星播影院'),
                      subtitle: const Text('0.1.0 · 收藏和记录保存在本机'),
                      trailing: const Icon(Icons.info_outline),
                      onTap: () => showAboutDialog(
                        context: context,
                        applicationName: '星播影院',
                        applicationVersion: '0.1.0',
                        children: [
                          const Text(
                              '影片数据来自 xbxx.pro。收藏与观看记录保存在当前设备，不上传账号服务器。'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: '首页',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: '找片',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '我的',
            ),
          ],
        ),
      );
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Image.asset('assets/brand.png', width: 34, height: 34),
          const SizedBox(width: 8),
          const Text(
            '星播影院',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
        ],
      );
}

class CatalogPage extends StatefulWidget {
  final FilmApi api;
  final ValueChanged<Film> onOpen;
  final bool discover;
  const CatalogPage({
    super.key,
    required this.api,
    required this.onOpen,
    this.discover = false,
  });
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final search = TextEditingController();
  List<Film> films = [];
  List<Map<String, dynamic>> categories = [];
  String type = '',
      keyword = '',
      genre = '',
      year = '',
      area = '',
      lang = '',
      letter = '',
      sort = 'time';
  List<String> years = [], areas = [], languages = [];
  bool extended = AppService.instance.available;
  int page = 1, pages = 1, ticket = 0;
  bool busy = true, moreBusy = false;
  String? error, categoryError;
  @override
  void initState() {
    super.initState();
    load();
    loadCategories();
    AppService.instance.addListener(serviceChanged);
    if (extended) loadFilters();
  }

  void serviceChanged() {
    if (!mounted) return;
    final next = AppService.instance.available;
    if (extended != next) {
      setState(() => extended = next);
      if (next) {
        loadFilters();
        load();
      }
    }
  }

  Future<void> loadFilters() async {
    try {
      final r = await AppService.instance.call('filters');
      if (!mounted) return;
      final f = Map<String, dynamic>.from(r['filters']);
      setState(() {
        years = (f['year'] as List).map((v) => '$v').toSet().toList();
        areas = (f['area'] as List).map((v) => '$v').toSet().toList();
        languages = (f['lang'] as List).map((v) => '$v').toSet().toList();
      });
    } catch (e) {
      if (mounted) setState(() => categoryError = '筛选项加载失败，可重试');
    }
  }

  Future<void> loadCategories() async {
    try {
      final result = await widget.api.categories();
      if (mounted) {
        setState(() {
          categories = result;
          categoryError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => categoryError = e.toString());
    }
  }

  Future<void> load({bool more = false}) async {
    if (more && (busy || moreBusy || page >= pages)) return;
    final generation = ++ticket;
    setState(() {
      error = null;
      if (more) {
        moreBusy = true;
      } else {
        busy = true;
        moreBusy = false;
        films = [];
        page = 1;
        pages = 1;
      }
    });
    try {
      final result = await widget.api.list(
        page: more ? page + 1 : 1,
        keyword: keyword,
        type: type,
        genre: genre,
        year: year,
        area: area,
        lang: lang,
        letter: letter,
        sort: sort,
      );
      if (!mounted || generation != ticket) return;
      setState(() {
        films = more ? [...films, ...result.films] : result.films;
        page = more ? page + 1 : 1;
        pages = result.pages;
        busy = false;
        moreBusy = false;
      });
    } catch (e) {
      if (mounted && generation == ticket) {
        setState(() {
          error = e.toString();
          busy = false;
          moreBusy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    AppService.instance.removeListener(serviceChanged);
    search.dispose();
    super.dispose();
  }

  List<String> normalizedFilterValues(List<String> source,
      {int maxLength = 12}) {
    return source
        .expand((value) => value.split(RegExp(r'\s*[/,，、|]\s*')))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && value.length <= maxLength)
        .toSet()
        .toList();
  }

  Widget filterGroup(
    String title,
    List<MapEntry<String, String>> options,
    String selected,
    ValueChanged<String> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((option) {
              final active = selected == option.key;
              return ChoiceChip(
                label: Text(option.value),
                selected: active,
                visualDensity: VisualDensity.compact,
                showCheckmark: false,
                onSelected: (_) => onChanged(option.key),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> showMobileFilters(
    List<MapEntry<String, String>> typeOptions,
    List<String> genreNames,
    List<String> filterAreas,
    List<String> filterYears,
    List<String> filterLanguages,
  ) async {
    var nextType = type;
    var nextGenre = genre;
    var nextArea = area;
    var nextYear = year;
    var nextLang = lang;
    var nextLetter = letter;
    var nextSort = sort;
    var apply = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF111725),
      builder: (context) => StatefulBuilder(
        builder: (context, modalSetState) => FractionallySizedBox(
          heightFactor: 0.92,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '筛选影片',
                        style: TextStyle(
                            fontSize: 21, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                  children: [
                    filterGroup('类型', typeOptions, nextType,
                        (v) => modalSetState(() => nextType = v)),
                    filterGroup(
                      '剧情',
                      [
                        const MapEntry('', '全部'),
                        ...genreNames.map((v) => MapEntry(v, v))
                      ],
                      nextGenre,
                      (v) => modalSetState(() => nextGenre = v),
                    ),
                    filterGroup(
                      '地区',
                      [
                        const MapEntry('', '全部'),
                        ...filterAreas.map((v) => MapEntry(v, v))
                      ],
                      nextArea,
                      (v) => modalSetState(() => nextArea = v),
                    ),
                    filterGroup(
                      '年份',
                      [
                        const MapEntry('', '全部'),
                        ...filterYears.map((v) => MapEntry(v, v))
                      ],
                      nextYear,
                      (v) => modalSetState(() => nextYear = v),
                    ),
                    filterGroup(
                      '语言',
                      [
                        const MapEntry('', '全部'),
                        ...filterLanguages.map((v) => MapEntry(v, v))
                      ],
                      nextLang,
                      (v) => modalSetState(() => nextLang = v),
                    ),
                    filterGroup(
                      '字母',
                      [
                        const MapEntry('', '全部'),
                        ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
                            .split('')
                            .map((v) => MapEntry(v, v)),
                        const MapEntry('0-9', '0-9'),
                      ],
                      nextLetter,
                      (v) => modalSetState(() => nextLetter = v),
                    ),
                    filterGroup(
                      '排序',
                      const [
                        MapEntry('time', '时间'),
                        MapEntry('hits', '人气'),
                        MapEntry('score', '评分'),
                      ],
                      nextSort,
                      (v) => modalSetState(() => nextSort = v),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => modalSetState(() {
                          nextType = '';
                          nextGenre = '';
                          nextArea = '';
                          nextYear = '';
                          nextLang = '';
                          nextLetter = '';
                          nextSort = 'time';
                        }),
                        child: const Text('重置'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () {
                          apply = true;
                          Navigator.pop(context);
                        },
                        child: const Text('应用筛选'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || !apply) return;
    setState(() {
      type = nextType;
      genre = nextGenre;
      area = nextArea;
      year = nextYear;
      lang = nextLang;
      letter = nextLetter;
      sort = nextSort;
    });
    load();
  }

  @override
  Widget build(BuildContext context) {
    final shown = films;
    final currentYear = DateTime.now().year;
    final filterYears = years
        .where((v) {
          final parsed = int.tryParse(v) ?? 0;
          return parsed >= 2010 && parsed <= currentYear;
        })
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    if (filterYears.isEmpty) {
      filterYears.addAll([
        for (var value = currentYear; value >= 2010; value--) '$value',
      ]);
    }
    final filterAreas = areas.isNotEmpty
        ? normalizedFilterValues(areas).take(40).toList()
        : [
            '大陆',
            '香港',
            '台湾',
            '美国',
            '法国',
            '英国',
            '日本',
            '韩国',
            '德国',
            '泰国',
            '印度',
            '其他'
          ];
    final filterLanguages = languages.isNotEmpty
        ? normalizedFilterValues(languages, maxLength: 8).take(30).toList()
        : ['国语', '英语', '粤语', '闽南语', '韩语', '日语', '法语', '德语', '其他'];
    final typeOptions = <MapEntry<String, String>>[
      const MapEntry('', '全部'),
      ...categories
          .where((c) => '${c['type_pid']}' == '0')
          .map((c) => MapEntry('${c['type_id']}', '${c['type_name']}')),
    ];
    const genreNames = [
      '喜剧',
      '爱情',
      '恐怖',
      '动作',
      '科幻',
      '剧情',
      '战争',
      '警匪',
      '犯罪',
      '动画',
      '奇幻',
      '武侠',
      '冒险',
      '枪战',
      '悬疑',
      '惊悚',
      '经典',
      '青春',
      '文艺',
      '微电影',
      '古装',
      '历史',
      '运动',
      '农村',
      '儿童',
      '网络电影',
    ];
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => load(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const Brand(),
            if (!widget.discover) const Advertising(slot: 'home_top'),
            const SizedBox(height: 18),
            TextField(
              controller: search,
              textInputAction: TextInputAction.search,
              onSubmitted: (s) {
                keyword = s.trim();
                year = '';
                area = '';
                load();
              },
              decoration: InputDecoration(
                hintText: '搜索电影、剧集',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: '搜索',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () {
                    keyword = search.text.trim();
                    year = '';
                    area = '';
                    load();
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (!widget.discover)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(widget.discover ? '全部' : '推荐'),
                        selected: type.isEmpty,
                        onSelected: (_) {
                          type = '';
                          year = '';
                          area = '';
                          load();
                        },
                      ),
                    ),
                    ...categories
                        .where(
                          (c) => widget.discover || '${c['type_pid']}' == '0',
                        )
                        .map(
                          (c) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('${c['type_name']}'),
                              selected: type == '${c['type_id']}',
                              onSelected: (_) {
                                type = '${c['type_id']}';
                                year = '';
                                area = '';
                                load();
                              },
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            if (categoryError != null)
              TextButton(
                onPressed: loadCategories,
                child: const Text('分类加载失败，点击重试'),
              ),
            if (widget.discover) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => showMobileFilters(
                        typeOptions,
                        genreNames,
                        filterAreas,
                        filterYears,
                        filterLanguages,
                      ),
                      icon: const Icon(Icons.tune),
                      label: const Text('筛选影片'),
                    ),
                  ),
                  if ([type, genre, area, year, lang, letter]
                          .any((value) => value.isNotEmpty) ||
                      sort != 'time') ...[
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          type = '';
                          genre = '';
                          area = '';
                          year = '';
                          lang = '';
                          letter = '';
                          sort = 'time';
                        });
                        load();
                      },
                      child: const Text('清除'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (genre.isNotEmpty) genre,
                  if (area.isNotEmpty) area,
                  if (year.isNotEmpty) year,
                  if (lang.isNotEmpty) lang,
                  if (letter.isNotEmpty) letter,
                ].isEmpty
                    ? '当前：全部影片'
                    : '当前：${[
                        if (genre.isNotEmpty) genre,
                        if (area.isNotEmpty) area,
                        if (year.isNotEmpty) year,
                        if (lang.isNotEmpty) lang,
                        if (letter.isNotEmpty) letter,
                      ].join(' · ')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
            const SizedBox(height: 20),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(70),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (error != null)
                Failure(
                  message: error!,
                  retry: () => load(more: films.isNotEmpty),
                ),
              if (!widget.discover && keyword.isEmpty && shown.isNotEmpty) ...[
                HeroBanner(
                  films: shown.take(5).toList(),
                  onOpen: widget.onOpen,
                ),
                const SizedBox(height: 28),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      keyword.isNotEmpty
                          ? '搜索结果'
                          : widget.discover
                              ? '发现好故事'
                              : '最近更新',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '第 $page / $pages 页',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (shown.isEmpty && error == null)
                const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(child: Text('暂时没有符合条件的影片')),
                ),
              if (!widget.discover && keyword.isEmpty) ...[
                FilmRail(films: shown.take(10).toList(), onOpen: widget.onOpen),
                if (shown.length > 10) ...[
                  const SizedBox(height: 26),
                  const Text(
                    '更多好片',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  FilmGrid(
                    films: shown.skip(10).toList(),
                    onOpen: widget.onOpen,
                  ),
                ],
              ] else
                FilmGrid(films: shown, onOpen: widget.onOpen),
              if (!widget.discover) const Advertising(slot: 'home_banner'),
              if (page < pages)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: OutlinedButton(
                    onPressed: moreBusy ? null : () => load(more: true),
                    child: Text(moreBusy ? '加载中…' : '加载更多'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class HeroBanner extends StatelessWidget {
  final List<Film> films;
  final ValueChanged<Film> onOpen;
  const HeroBanner({super.key, required this.films, required this.onOpen});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 330,
        child: PageView(
          children: films
              .map(
                (f) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Poster(film: f),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xF508101E)],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 16,
                          left: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '星播精选',
                              style: TextStyle(color: gold),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom: 20,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                f.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                f.remark,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: () => onOpen(f),
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('查看影片'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      );
}

class Poster extends StatelessWidget {
  final Film film;
  const Poster({super.key, required this.film});
  @override
  Widget build(BuildContext context) => Image.network(
        posterProxy.isEmpty
            ? film.poster
            : Uri.parse(posterProxy)
                .replace(queryParameters: {'url': film.poster}).toString(),
        fit: BoxFit.cover,
        errorBuilder: (_, e, s) => Container(
          color: panel,
          child: const Center(
            child: Icon(Icons.movie_outlined, color: Colors.white24, size: 36),
          ),
        ),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : Container(
                color: panel,
                child: const Center(
                  child: Icon(Icons.play_circle_outline, color: Colors.white24),
                ),
              ),
      );
}

class FilmGrid extends StatelessWidget {
  final List<Film> films;
  final ValueChanged<Film> onOpen;
  const FilmGrid({super.key, required this.films, required this.onOpen});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: films.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: c.maxWidth > 700 ? 5 : 3,
            mainAxisExtent:
                (c.maxWidth > 700 ? c.maxWidth / 5 : c.maxWidth / 3) * 1.5 + 58,
            crossAxisSpacing: 10,
            mainAxisSpacing: 14,
          ),
          itemBuilder: (context, i) {
            final f = films[i];
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onOpen(f),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Poster(film: f),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              color: Colors.black54,
                              padding: const EdgeInsets.all(5),
                              child: Text(
                                f.remark,
                                maxLines: 1,
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    f.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
}

class FilmRail extends StatelessWidget {
  final List<Film> films;
  final ValueChanged<Film> onOpen;
  const FilmRail({super.key, required this.films, required this.onOpen});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 230,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: films.length,
          separatorBuilder: (_, i) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            final f = films[i];
            return SizedBox(
              width: 126,
              child: InkWell(
                onTap: () => onOpen(f),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 174,
                      width: 126,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Poster(film: f),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      f.remark,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
}

class Failure extends StatelessWidget {
  final String message;
  final VoidCallback retry;
  const Failure({super.key, required this.message, required this.retry});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_outlined,
                color: Colors.white54, size: 36),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            TextButton(onPressed: retry, child: const Text('重新加载')),
          ],
        ),
      );
}

class DetailPage extends StatefulWidget {
  final FilmApi api;
  final Library library;
  final String id;
  const DetailPage({
    super.key,
    required this.api,
    required this.library,
    required this.id,
  });
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  Film? film;
  String? error;
  int lineIndex = 0, episodeIndex = 0;
  List<Film> related = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => error = null);
    try {
      final result = await widget.api.detail(widget.id);
      if (AppService.instance.loggedIn &&
          PlaybackSession.instance.film?.id != result.id) {
        await widget.library.syncFromAccount();
      }
      if (!mounted) return;
      final record = widget.library.history[result.id];
      lineIndex = 0;
      episodeIndex = 0;
      for (var i = 0; i < result.lines.length; i++) {
        var j = result.lines[i].episodes.indexWhere(
          (e) => e.url == record?.url,
        );
        if (record != null &&
            record.lineName == result.lines[i].name &&
            record.episodeIndex <= result.lines[i].episodes.length) {
          j = record.episodeIndex - 1;
        }
        if (j >= 0) {
          lineIndex = i;
          episodeIndex = j;
          break;
        }
      }
      setState(() => film = result);
      try {
        final list = await widget.api.list(
          type: '${result.data['type_id'] ?? ''}',
        );
        if (mounted) {
          setState(
            () => related =
                list.films.where((f) => f.id != result.id).take(6).toList(),
          );
        }
      } catch (_) {
        /* Related films are optional. */
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = film;
    final lines = f?.lines ?? <PlayLine>[];
    final episode =
        lines.isEmpty ? null : lines[lineIndex].episodes[episodeIndex];
    final record = f == null ? null : widget.library.history[f.id];
    return Scaffold(
      appBar: AppBar(title: Text(f?.name ?? '影片详情', maxLines: 1)),
      body: f == null
          ? (error == null
              ? const Center(child: CircularProgressIndicator())
              : Failure(message: error!, retry: load))
          : ListView(
              children: [
                if (episode != null)
                  Player(
                    key: ValueKey(episode.url),
                    film: f,
                    episode: episode,
                    library: widget.library,
                    lineName: lines[lineIndex].name,
                    episodeIndex: episodeIndex + 1,
                    resumeSeconds: record != null &&
                            (record.url == episode.url ||
                                (record.lineName == lines[lineIndex].name &&
                                    record.episodeIndex == episodeIndex + 1))
                        ? record.seconds
                        : 0,
                    onNext: episodeIndex + 1 < lines[lineIndex].episodes.length
                        ? () => setState(() => episodeIndex++)
                        : null,
                  )
                else
                  const AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Center(child: Text('暂无可用播放线路')),
                  ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Advertising(slot: 'detail'),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              f.name,
                              style: const TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: widget.library,
                            builder: (context, _) => IconButton(
                              tooltip: '收藏',
                              onPressed: () => widget.library.toggle(f),
                              icon: Icon(
                                widget.library.favorites.containsKey(f.id)
                                    ? Icons.bookmark
                                    : Icons.bookmark_border,
                                color: gold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        [
                          f.data['vod_year'],
                          f.data['vod_area'],
                          f.data['type_name'],
                          f.remark,
                        ]
                            .where((v) => v != null && '$v'.isNotEmpty)
                            .join(' · '),
                        style: const TextStyle(color: Colors.white54),
                      ),
                      const SizedBox(height: 20),
                      if (lines.isNotEmpty) ...[
                        const Text(
                          '播放线路',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: List.generate(
                            lines.length,
                            (i) => ChoiceChip(
                              label: Text(lines[i].name),
                              selected: i == lineIndex,
                              onSelected: (_) => setState(() {
                                lineIndex = i;
                                episodeIndex = 0;
                              }),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '选集 · ${lines[lineIndex].episodes.length} 集',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(
                            lines[lineIndex].episodes.length,
                            (i) => ChoiceChip(
                              label: Text(lines[lineIndex].episodes[i].name),
                              selected: i == episodeIndex,
                              onSelected: (_) =>
                                  setState(() => episodeIndex = i),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('剧情简介'),
                        children: [
                          Text(
                            f.summary.isEmpty ? '暂无简介' : f.summary,
                            style: const TextStyle(
                              color: Colors.white70,
                              height: 1.7,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                      if (related.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          '同类影片',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilmGrid(
                          films: related,
                          onOpen: (other) => Navigator.pushReplacement(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => DetailPage(
                                api: widget.api,
                                library: widget.library,
                                id: other.id,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

