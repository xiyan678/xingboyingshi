import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xingbo_app/api.dart';
import 'package:xingbo_app/library.dart';
import 'package:xingbo_app/main.dart';

void main() {
  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('catalog and navigation fit width $width', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final api = FilmApi(
          client: MockClient((request) async => http.Response(
              request.url.queryParameters['ac'] == 'list'
                  ? '{"code":1,"class":[{"type_id":1,"type_pid":0,"type_name":"Movies"}]}'
                  : '{"code":1,"pagecount":1,"list":[{"vod_id":1,"vod_name":"Example movie","vod_pic":"https://example.com/poster.jpg"}]}',
              200)));
      await tester.pumpWidget(XingboApp(api: api, library: Library(prefs)));
      await tester.pumpAndSettle();
      expect(find.text('最近更新'), findsOneWidget);
      await tester.tap(find.text('找片'));
      await tester.pumpAndSettle();
      expect(find.text('发现好故事'), findsOneWidget);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('我的收藏'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
