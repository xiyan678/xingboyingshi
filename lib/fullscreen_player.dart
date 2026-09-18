import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FullscreenPlayer extends StatefulWidget {
  final WidgetBuilder builder;
  const FullscreenPlayer({super.key, required this.builder});
  static Future<void> exit(BuildContext context) async {
    await context.findAncestorStateOfType<_FullscreenPlayerState>()?._exit();
  }

  @override
  State<FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<FullscreenPlayer> {
  bool _exiting = false;

  Future<void> _restorePortrait() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  Future<void> _exit() async {
    if (_exiting) return;
    _exiting = true;
    await _restorePortrait();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();
    unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    unawaited(SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]));
  }

  @override
  void dispose() {
    // Keep the detail page portrait after an explicit fullscreen exit. If all
    // orientations are restored while the phone is still held sideways, the
    // metrics listener immediately opens fullscreen again.
    if (!_exiting) unawaited(_restorePortrait());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_exit());
      },
      child: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.expand(child: Builder(builder: widget.builder))));
}
