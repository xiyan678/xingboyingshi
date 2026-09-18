import 'package:flutter/services.dart';

class IosSharedPip {
  static const channel = MethodChannel('xingbo/shared_pip');
  void Function(int playerId, bool restore)? onStopped;

  IosSharedPip() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'stopped') {
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        onStopped?.call(args['playerId'] as int, args['restore'] == true);
      }
    });
  }

  Future<void> start(int playerId) =>
      channel.invokeMethod<void>('start', {'playerId': playerId});
  Future<void> close() => channel.invokeMethod<void>('close');
}
