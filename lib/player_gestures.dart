import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class PlayerGestures extends StatefulWidget {
  final VideoPlayerController controller;
  final VoidCallback onTap;
  const PlayerGestures(
      {super.key, required this.controller, required this.onTap});
  @override
  State<PlayerGestures> createState() => _PlayerGesturesState();
}

class _PlayerGesturesState extends State<PlayerGestures> {
  Duration? seekStart, seekTarget;
  double drag = 0;
  double? originalSpeed;
  String? hint;
  Future<void> speedTask = Future.value();

  Future<void> run(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (_) {
      if (mounted) setState(() => hint = '操作失败，请重试');
    }
  }

  void restoreSpeed() {
    final speed = originalSpeed;
    originalSpeed = null;
    final controller = widget.controller;
    if (speed != null) {
      speedTask =
          speedTask.then((_) => run(() => controller.setPlaybackSpeed(speed)));
    }
    if (mounted) setState(() => hint = null);
  }

  @override
  void dispose() {
    final speed = originalSpeed;
    final controller = widget.controller;
    if (speed != null) {
      unawaited(speedTask.then((_) async {
        try {
          await controller.setPlaybackSpeed(speed);
        } catch (_) {}
      }));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, bounds) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onDoubleTap: () => run(() => widget.controller.value.isPlaying
                ? widget.controller.pause()
                : widget.controller.play()),
            onLongPressStart: (_) {
              if (!widget.controller.value.isPlaying) return;
              originalSpeed = widget.controller.value.playbackSpeed;
              final controller = widget.controller;
              speedTask = speedTask
                  .then((_) => run(() => controller.setPlaybackSpeed(3)));
              setState(() => hint = '3.0x');
            },
            onLongPressEnd: (_) => restoreSpeed(),
            onLongPressCancel: restoreSpeed,
            onHorizontalDragStart: (_) {
              seekStart = widget.controller.value.position;
              seekTarget = seekStart;
              drag = 0;
            },
            onHorizontalDragUpdate: (details) {
              if (seekStart == null) return;
              drag += details.delta.dx;
              final end = widget.controller.value.duration.inMilliseconds;
              final target =
                  (seekStart!.inMilliseconds + drag / bounds.maxWidth * 120000)
                      .round()
                      .clamp(0, end);
              seekTarget = Duration(milliseconds: target);
              setState(() => hint =
                  '${seekTarget!.inMinutes}:${(seekTarget!.inSeconds % 60).toString().padLeft(2, '0')}');
            },
            onHorizontalDragEnd: (_) {
              final target = seekTarget;
              seekStart = seekTarget = null;
              setState(() => hint = null);
              if (target != null) {
                unawaited(run(() => widget.controller.seekTo(target)));
              }
            },
            onHorizontalDragCancel: () {
              seekStart = seekTarget = null;
              setState(() => hint = null);
            },
            child: SizedBox.expand(
                child: hint == null
                    ? null
                    : Center(
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(6)),
                            child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Text(hint!,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 20)))))),
          ));
}
