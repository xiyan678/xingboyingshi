import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingbo_app/playback_session.dart';
import 'package:xingbo_app/player.dart';
import 'player_gestures_test.dart' show GesturePlayer;

void main() {
  testWidgets('phone controls fit and locking hides episode actions',
      (tester) async {
    final controller = GesturePlayer();
    final session = PlaybackSession.instance;
    session.controller = controller;
    addTearDown(() {
      session.controller = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    for (final size in [const Size(320, 568), const Size(740, 360)]) {
      tester.view.physicalSize = size;
      final fullscreen = size.width > size.height;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: size.width,
                  height: fullscreen ? size.height : size.width * 9 / 16,
                  child: VideoSurface(
                      key: ValueKey(fullscreen),
                      fullscreen: fullscreen,
                      onNext: () {},
                      onSelectEpisode: (line, episode) {},
                      onFullscreen: () {})))));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('选集'), findsOneWidget);
      expect(tester.getCenter(find.byTooltip('选集')).dy,
          greaterThan((fullscreen ? size.height : size.width * 9 / 16) / 2));
      if (fullscreen) {
        await tester.tap(find.byTooltip('锁定屏幕'));
        await tester.pump();
        expect(find.byTooltip('选集'), findsNothing);
        await tester.tap(find.byTooltip('解锁'));
        await tester.pump();
        expect(find.byTooltip('选集'), findsOneWidget);
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}
