import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ImmersiveControls extends StatefulWidget {
  final ValueListenable<VideoPlayerValue> playback;
  final Widget Function(BuildContext, bool visible, VoidCallback toggle)
      builder;
  const ImmersiveControls(
      {super.key, required this.playback, required this.builder});
  @override
  State<ImmersiveControls> createState() => _ImmersiveControlsState();
}

class _ImmersiveControlsState extends State<ImmersiveControls> {
  Timer? timer;
  bool visible = true;
  bool playing = false;
  int pointers = 0;

  @override
  void initState() {
    super.initState();
    playing = widget.playback.value.isPlaying;
    widget.playback.addListener(changed);
    arm();
  }

  @override
  void didUpdateWidget(covariant ImmersiveControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playback != widget.playback) {
      oldWidget.playback.removeListener(changed);
      widget.playback.addListener(changed);
      playing = widget.playback.value.isPlaying;
      visible = true;
      arm();
    }
  }

  void changed() {
    final next =
        widget.playback.value.isPlaying && !widget.playback.value.hasError;
    if (next == playing) return;
    playing = next;
    if (!playing) setState(() => visible = true);
    arm();
  }

  void arm() {
    timer?.cancel();
    if (!playing || !visible || pointers > 0) return;
    timer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          playing &&
          pointers == 0 &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        setState(() => visible = false);
      } else if (mounted) {
        arm();
      }
    });
  }

  void toggle() {
    setState(() => visible = !visible);
    arm();
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.playback.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
      onPointerDown: (_) {
        pointers++;
        timer?.cancel();
      },
      onPointerUp: (_) {
        pointers = (pointers - 1).clamp(0, 100);
        arm();
      },
      onPointerCancel: (_) {
        pointers = (pointers - 1).clamp(0, 100);
        arm();
      },
      child: widget.builder(context, visible, toggle));
}
