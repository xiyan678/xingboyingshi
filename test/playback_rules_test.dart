import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xingbo_app/playback_rules.dart';

void main() {
  testWidgets('sleep deadline fires once and replacement cancels old deadline',
      (tester) async {
    var stops = 0;
    final timer = PlaybackSleepTimer(
        onStop: () => stops++, now: tester.binding.clock.now);
    timer.after(const Duration(minutes: 15));
    timer.after(const Duration(minutes: 30));
    await tester.pump(const Duration(minutes: 15));
    expect(stops, 0);
    await tester.pump(const Duration(minutes: 15));
    expect(stops, 1);
    timer.checkDeadline();
    expect(stops, 1);
    timer.dispose();
  });

  test('two-episode limit includes current episode and stops before third', () {
    var stops = 0;
    final timer = PlaybackSleepTimer(onStop: () => stops++);
    timer.afterEpisodes(2);
    expect(timer.episodeEnded(hasNext: true), isFalse);
    expect(timer.remainingEpisodes, 1);
    expect(timer.episodeEnded(hasNext: true), isTrue);
    expect(stops, 1);
    expect(timer.episodeEnded(hasNext: true), isTrue);
    expect(stops, 1);
    timer.dispose();
  });

  test('last episode stops even if two were requested, cancel disables limit',
      () {
    var stops = 0;
    final timer = PlaybackSleepTimer(onStop: () => stops++);
    timer.afterEpisodes(2);
    expect(timer.episodeEnded(hasNext: false), isTrue);
    expect(stops, 1);
    timer.afterEpisodes(1);
    timer.cancel();
    expect(timer.episodeEnded(hasNext: true), isFalse);
    expect(stops, 1);
    timer.dispose();
  });

  test('resume checks expired deadline before timer callback', () {
    var now = DateTime(2026);
    var stops = 0;
    final timer = PlaybackSleepTimer(onStop: () => stops++, now: () => now);
    timer.after(const Duration(minutes: 15));
    now = now.add(const Duration(minutes: 16));
    expect(timer.episodeEnded(hasNext: true), isTrue);
    expect(stops, 1);
    timer.dispose();
  });

  test('skip settings persist per film/account and reject short episodes',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const settings =
        SkipSettings(enabled: true, introSeconds: 60, outroSeconds: 90);
    await settings.save(prefs, 'one', null);
    expect(SkipSettings.load(prefs, 'one', null).introSeconds, 60);
    expect(SkipSettings.load(prefs, 'two', null).enabled, isFalse);
    expect(SkipSettings.load(prefs, 'one', 'account').enabled, isFalse);
    expect(settings.appliesTo(const Duration(minutes: 2)), isFalse);
    expect(settings.appliesTo(const Duration(minutes: 40)), isTrue);
  });
}
