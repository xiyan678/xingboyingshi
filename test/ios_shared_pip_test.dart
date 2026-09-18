import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingbo_app/ios_shared_pip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('PiP passes the existing player ID without a URL or seek command',
      () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(IosSharedPip.channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(IosSharedPip.channel, null));
    final pip = IosSharedPip();
    await pip.start(42);
    await pip.close();
    expect(calls.map((call) => call.method), ['start', 'close']);
    expect(calls.first.arguments, {'playerId': 42});
  });
  test('native failures propagate instead of claiming PiP is active', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(IosSharedPip.channel, (_) async {
      throw PlatformException(code: 'PIP_TIMEOUT');
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(IosSharedPip.channel, null));
    await expectLater(
        IosSharedPip().start(42), throwsA(isA<PlatformException>()));
  });
}
