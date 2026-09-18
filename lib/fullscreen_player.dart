import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FullscreenPlayer extends StatefulWidget {
  final WidgetBuilder builder;
  const FullscreenPlayer({super.key, required this.builder});
  @override
  State<FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<FullscreenPlayer> {
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
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    // Keep the detail page portrait after an explicit fullscreen exit. If all
    // orientations are restored while the phone is still held sideways, the
    // metrics listener immediately opens fullscreen again.
    unawaited(SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(child: widget.builder(context)));
}
