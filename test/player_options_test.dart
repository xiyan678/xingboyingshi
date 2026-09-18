import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingbo_app/playback_rules.dart';
import 'package:xingbo_app/player_options.dart';

void main() {
  testWidgets('skip sheet saves enabled durations on a small phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SkipSettings? result;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
          onPressed: () async {
            result = await showModalBottomSheet<SkipSettings>(
                context: context,
                isScrollControlled: true,
                builder: (_) =>
                    const SkipSettingsSheet(settings: SkipSettings()));
          },
          child: const Text('Open')),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('片头增加5秒'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result?.enabled, isTrue);
    expect(result?.introSeconds, 95);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sleep options scroll in landscape and select two episodes',
      (tester) async {
    tester.view.physicalSize = const Size(740, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final timer = PlaybackSleepTimer(onStop: () {});
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => SleepTimerSheet(timer: timer)),
          child: const Text('Open')),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('90 分钟后'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('播完两集（含本集）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('播完两集（含本集）'));
    await tester.pumpAndSettle();
    expect(timer.remainingEpisodes, 2);
    timer.dispose();
  });
}
