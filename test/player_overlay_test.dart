import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingbo_app/player.dart';

void main() {
  testWidgets('floating controls have an overlay outside the navigator', (tester) async {
    final key = GlobalKey<TooltipState>();
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => PlayerOverlayRoot(child: Stack(children: [
        child!,
        Material(child: Tooltip(key: key, message: '关闭小窗', child: const Icon(Icons.close))),
      ])),
      home: const Scaffold(),
    ));
    expect(tester.takeException(), isNull);
    key.currentState!.ensureTooltipVisible();
    await tester.pumpAndSettle();
    expect(find.text('关闭小窗'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
