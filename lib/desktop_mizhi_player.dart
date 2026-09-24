import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:window_manager/window_manager.dart';

import 'api.dart';

class DesktopMizhiPlayer extends StatefulWidget {
  final Film film;
  final Episode episode;
  const DesktopMizhiPlayer({super.key, required this.film, required this.episode});

  @override
  State<DesktopMizhiPlayer> createState() => _DesktopMizhiPlayerState();
}

class _DesktopMizhiPlayerState extends State<DesktopMizhiPlayer> {
  final controller = WebviewController();
  StreamSubscription<bool>? fullscreen;
  String? error;

  Uri get playerUri => Uri.https('player.xbxx.pro', '/', {
        'url': widget.episode.url,
        'title': '${widget.film.name} - ${widget.episode.name}',
        'ids': '${widget.film.id}-${widget.episode.name}',
        'content': widget.film.summary,
      });

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final version = await WebviewController.getWebViewVersion();
      if (version == null) throw PlatformException(code: 'webview2_missing');
      await controller.initialize();
      await controller.setBackgroundColor(Colors.black);
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      fullscreen = controller.containsFullScreenElementChanged.listen((value) {
        unawaited(windowManager.setFullScreen(value));
      });
      await controller.loadUrl(playerUri.toString());
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => error = '播放器启动失败，请安装 Microsoft Edge WebView2 后重试');
    }
  }

  @override
  void didUpdateWidget(covariant DesktopMizhiPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episode.url != widget.episode.url && controller.value.isInitialized) {
      unawaited(controller.loadUrl(playerUri.toString()));
    }
  }

  @override
  void dispose() {
    fullscreen?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: error != null
            ? Center(child: Text(error!, textAlign: TextAlign.center))
            : !controller.value.isInitialized
                ? const Center(child: CircularProgressIndicator())
                : Stack(children: [
                    Webview(controller),
                    const Positioned(
                      left: 10,
                      top: 10,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0x99000000),
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                            child: Text('智能去插播已开启', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                      ),
                    ),
                    StreamBuilder<LoadingState>(
                        stream: controller.loadingState,
                        builder: (_, state) => state.data == LoadingState.loading
                            ? const LinearProgressIndicator(minHeight: 2)
                            : const SizedBox.shrink()),
                  ]),
      );
}
