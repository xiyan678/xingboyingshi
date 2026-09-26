import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'danmaku.dart';
import 'library.dart';
import 'playback_session.dart';
import 'player.dart';
import 'service.dart';

const _green = Color(0xFF20E07A);
const _bg = Color(0xFF080B0D);
const _surface = Color(0xFF151A1D);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final library = Library(await SharedPreferences.getInstance());
  library.attach(AppService.instance);
  runApp(TvApp(api: FilmApi(), library: library));
  unawaited(AppService.instance.initialize());
  unawaited(DanmakuSettings.instance.load());
}

class TvApp extends StatelessWidget {
  final FilmApi api;
  final Library library;
  const TvApp({super.key, required this.api, required this.library});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '星播影院 TV',
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: child!,
        ),
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _bg,
          colorScheme: ColorScheme.fromSeed(
              seedColor: _green, brightness: Brightness.dark),
          focusColor: _green,
        ),
        home: TvHome(api: api, library: library),
      );
}

class TvHome extends StatefulWidget {
  final FilmApi api;
  final Library library;
  const TvHome({super.key, required this.api, required this.library});
  @override
  State<TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends State<TvHome> {
  List<Film> films = [];
  bool loading = true;
  String? error;
  int page = 1;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({String keyword = ''}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.api.list(page: page, keyword: keyword);
      if (mounted) setState(() => films = result.films);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> search() async {
    final input = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('搜索影片'),
        content: TextField(
          controller: input,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: '输入电影、电视剧或演员'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, input.text.trim()),
              child: const Text('搜索')),
        ],
      ),
    );
    input.dispose();
    if (value != null && value.isNotEmpty) await load(keyword: value);
  }

  void open(Film film) => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => TvDetail(
              api: widget.api, library: widget.library, filmId: film.id)));

  @override
  Widget build(BuildContext context) {
    final hero = films.isEmpty ? null : films.first;
    return Scaffold(
      body: Row(children: [
        Container(
          width: 104,
          color: const Color(0xFF0D1113),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            Image.asset('assets/brand.png', width: 34, height: 34),
            const SizedBox(height: 8),
            TvNavButton(
                icon: Icons.home_rounded,
                label: '首页',
                selected: true,
                onTap: () => load()),
            TvNavButton(icon: Icons.search_rounded, label: '搜索', onTap: search),
            TvNavButton(
                icon: Icons.favorite_outline, label: '收藏', onTap: () {}),
            TvNavButton(icon: Icons.history_rounded, label: '记录', onTap: () {}),
            const SizedBox(height: 2),
            TvNavButton(icon: Icons.person_outline, label: '我的', onTap: () {}),
          ]),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(error!),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: load, child: const Text('重新加载'))
                    ]))
                  : CustomScrollView(slivers: [
                      SliverToBoxAdapter(
                          child: TvHero(film: hero!, onOpen: () => open(hero))),
                      const SliverToBoxAdapter(
                          child: Padding(
                              padding: EdgeInsets.fromLTRB(34, 26, 34, 14),
                              child: Text('正在热播',
                                  style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800)))),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(34, 0, 34, 40),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 6,
                                  childAspectRatio: .67,
                                  crossAxisSpacing: 18,
                                  mainAxisSpacing: 24),
                          delegate: SliverChildBuilderDelegate(
                              (_, i) => TvPosterCard(
                                  film: films[i], onTap: () => open(films[i])),
                              childCount: films.length),
                        ),
                      )
                    ]),
        )
      ]),
    );
  }
}

class TvNavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  const TvNavButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap,
      this.selected = false});
  @override
  Widget build(BuildContext context) => TvFocusable(
      onTap: onTap,
      builder: (focused) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
              color: selected || focused
                  ? const Color(0xFF163D2D)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
              border: focused ? Border.all(color: _green, width: 2) : null),
          child: Column(children: [
            Icon(icon, color: selected || focused ? _green : Colors.white70),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12))
          ])));
}

class TvHero extends StatelessWidget {
  final Film film;
  final VoidCallback onOpen;
  const TvHero({super.key, required this.film, required this.onOpen});
  @override
  Widget build(BuildContext context) => SizedBox(
      height: 390,
      child: Stack(fit: StackFit.expand, children: [
        Image.network(film.poster,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const ColoredBox(color: _surface)),
        const DecoratedBox(
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [Colors.transparent, Color(0xEE080B0D)],
                    stops: [.25, .86]))),
        Padding(
            padding: const EdgeInsets.fromLTRB(42, 62, 42, 38),
            child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                    width: 560,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('星播影院 TV',
                              style: TextStyle(
                                  color: _green,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2)),
                          const SizedBox(height: 14),
                          Text(film.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 48, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 12),
                          Text(film.remark,
                              style: const TextStyle(
                                  fontSize: 18, color: Colors.white70)),
                          const SizedBox(height: 22),
                          TvFocusable(
                              onTap: onOpen,
                              autofocus: true,
                              builder: (focused) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 140),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 26, vertical: 13),
                                  decoration: BoxDecoration(
                                      color: focused ? _green : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: focused
                                          ? const [
                                              BoxShadow(
                                                  color: Color(0x8820E07A),
                                                  blurRadius: 20)
                                            ]
                                          : null),
                                  child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.play_arrow_rounded,
                                            color: Colors.black),
                                        SizedBox(width: 8),
                                        Text('立即观看',
                                            style: TextStyle(
                                                color: Colors.black,
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800))
                                      ]))),
                        ]))))
      ]));
}

class TvPosterCard extends StatelessWidget {
  final Film film;
  final VoidCallback onTap;
  const TvPosterCard({super.key, required this.film, required this.onTap});
  @override
  Widget build(BuildContext context) => TvFocusable(
      onTap: onTap,
      builder: (focused) => AnimatedScale(
          scale: focused ? 1.06 : 1,
          duration: const Duration(milliseconds: 140),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Container(
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: focused ? _green : Colors.transparent,
                            width: 3),
                        boxShadow: focused
                            ? const [
                                BoxShadow(
                                    color: Color(0x6620E07A), blurRadius: 18)
                              ]
                            : null),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(fit: StackFit.expand, children: [
                      Image.network(film.poster,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const ColoredBox(
                              color: _surface,
                              child: Icon(Icons.movie_outlined, size: 42))),
                      Align(
                          alignment: Alignment.bottomRight,
                          child: Container(
                              color: Colors.black87,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 4),
                              child: Text(film.remark,
                                  maxLines: 1,
                                  style: const TextStyle(fontSize: 11))))
                    ]))),
            const SizedBox(height: 8),
            Text(film.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: focused ? FontWeight.w800 : FontWeight.w500,
                    color: focused ? _green : Colors.white))
          ])));
}

class TvFocusable extends StatefulWidget {
  final Widget Function(bool focused) builder;
  final VoidCallback onTap;
  final bool autofocus;
  const TvFocusable(
      {super.key,
      required this.builder,
      required this.onTap,
      this.autofocus = false});
  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => FocusableActionDetector(
      autofocus: widget.autofocus,
      onShowFocusHighlight: (v) => setState(() => focused = v),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent()
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap();
          return null;
        })
      },
      child:
          GestureDetector(onTap: widget.onTap, child: widget.builder(focused)));
}

class TvDetail extends StatefulWidget {
  final FilmApi api;
  final Library library;
  final String filmId;
  const TvDetail(
      {super.key,
      required this.api,
      required this.library,
      required this.filmId});
  @override
  State<TvDetail> createState() => _TvDetailState();
}

class _TvDetailState extends State<TvDetail> {
  Film? film;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final v = await widget.api.detail(widget.filmId);
      if (mounted) setState(() => film = v);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  void play(int line, int episode) {
    final f = film!, l = f.lines[line], e = l.episodes[episode];
    Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => TvPlayer(
                film: f,
                episode: e,
                library: widget.library,
                lineName: l.name,
                episodeIndex: episode + 1)));
  }

  @override
  Widget build(BuildContext context) {
    if (film == null) {
      return Scaffold(
          body: Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : Text(error!)));
    }
    final f = film!, lines = f.lines;
    return Scaffold(
        body: Stack(fit: StackFit.expand, children: [
      Image.network(f.poster,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const ColoredBox(color: _bg)),
      const ColoredBox(color: Color(0xD9080B0D)),
      SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                SizedBox(
                    width: 280,
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(f.poster, fit: BoxFit.cover))),
                const SizedBox(width: 28),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      IconButton(
                          onPressed: () => Navigator.pop(context),
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.arrow_back, size: 30)),
                      Text(f.name,
                          style: const TextStyle(
                              fontSize: 36, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Text(f.remark,
                          style: const TextStyle(color: _green, fontSize: 18)),
                      const SizedBox(height: 10),
                      Text(f.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70,
                              height: 1.4,
                              fontSize: 16)),
                      const SizedBox(height: 14),
                      const Text('选集',
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Expanded(
                          child: lines.isEmpty
                              ? const Text('暂无可播放线路')
                              : GridView.builder(
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 6,
                                          childAspectRatio: 2.5,
                                          crossAxisSpacing: 12,
                                          mainAxisSpacing: 12),
                                  itemCount: lines.first.episodes.length,
                                  itemBuilder: (_, i) => TvFocusable(
                                      autofocus: i == 0,
                                      onTap: () => play(0, i),
                                      builder: (focused) => Container(
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                              color:
                                                  focused ? _green : _surface,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                  color: focused
                                                      ? _green
                                                      : Colors.white12,
                                                  width: 2)),
                                          child: Text(
                                              lines.first.episodes[i].name,
                                              maxLines: 1,
                                              style: TextStyle(
                                                  color: focused ? Colors.black : Colors.white,
                                                  fontWeight: FontWeight.w700))))))
                    ]))
              ])))
    ]));
  }
}

class TvPlayer extends StatefulWidget {
  final Film film;
  final Episode episode;
  final Library library;
  final String lineName;
  final int episodeIndex;
  const TvPlayer(
      {super.key,
      required this.film,
      required this.episode,
      required this.library,
      required this.lineName,
      required this.episodeIndex});
  @override
  State<TvPlayer> createState() => _TvPlayerState();
}

class _TvPlayerState extends State<TvPlayer> {
  final session = PlaybackSession.instance;
  @override
  void initState() {
    super.initState();
    unawaited(session.open(widget.film, widget.episode, widget.library,
        line: widget.lineName, index: widget.episodeIndex));
  }

  @override
  void dispose() {
    unawaited(session.pauseAndSave());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
          animation: session,
          builder: (_, __) {
            if (session.error != null) {
              return Center(child: Text(session.error!));
            }
            if (!session.ready) {
              return const Center(child: CircularProgressIndicator());
            }
            return VideoSurface(
                fullscreen: true, onFullscreen: () => Navigator.pop(context));
          }));
}
