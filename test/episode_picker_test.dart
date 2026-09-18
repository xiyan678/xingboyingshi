import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingbo_app/api.dart';
import 'package:xingbo_app/episode_picker.dart';

void main() {
  testWidgets(
      'picker highlights current episode and returns selected line/index',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    EpisodeChoice? selected;
    final lines = [
      PlayLine('A', [Episode('Episode 1', 'one'), Episode('Episode 2', 'two')]),
      PlayLine('B', [Episode('Alternate 1', 'three')])
    ];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      selected = await showModalBottomSheet<EpisodeChoice>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => EpisodePicker(
                              lines: lines,
                              currentUrl: 'two',
                              currentLine: 'A'));
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Episode 2'))
            .selected,
        isTrue);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alternate 1'));
    await tester.pumpAndSettle();
    expect(selected?.line, 1);
    expect(selected?.episode, 0);
    expect(tester.takeException(), isNull);
  });
}
