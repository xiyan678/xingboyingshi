import 'package:flutter/material.dart';
import 'playback_rules.dart';

class SkipSettingsSheet extends StatefulWidget {
  final SkipSettings settings;
  const SkipSettingsSheet({super.key, required this.settings});
  @override
  State<SkipSettingsSheet> createState() => _SkipSettingsSheetState();
}

class _SkipSettingsSheetState extends State<SkipSettingsSheet> {
  late bool enabled = widget.settings.enabled;
  late int intro = widget.settings.introSeconds;
  late int outro = widget.settings.outroSeconds;

  Widget durationControl(String title, int value, ValueChanged<int> change) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(child: Text(title)),
          IconButton(
              tooltip: '$title减少5秒',
              onPressed: enabled && value > 0
                  ? () => setState(() => change((value - 5).clamp(0, 300)))
                  : null,
              icon: const Icon(Icons.remove)),
          SizedBox(
              width: 66, child: Text('$value 秒', textAlign: TextAlign.center)),
          IconButton(
              tooltip: '$title增加5秒',
              onPressed: enabled && value < 300
                  ? () => setState(() => change((value + 5).clamp(0, 300)))
                  : null,
              icon: const Icon(Icons.add)),
        ]),
      );

  @override
  Widget build(BuildContext context) => SafeArea(
      child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                title: const Text('片头片尾'),
                subtitle: const Text('仅应用于本部影片'),
                trailing: IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close))),
            SwitchListTile(
                title: const Text('自动跳过'),
                value: enabled,
                onChanged: (value) => setState(() => enabled = value)),
            durationControl('片头', intro, (value) => intro = value),
            durationControl('片尾', outro, (value) => outro = value),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                        onPressed: () => Navigator.pop(
                            context,
                            SkipSettings(
                                enabled: enabled,
                                introSeconds: intro,
                                outroSeconds: outro)),
                        child: const Text('保存')))),
          ])));
}

class SleepTimerSheet extends StatelessWidget {
  final PlaybackSleepTimer timer;
  const SleepTimerSheet({super.key, required this.timer});

  @override
  Widget build(BuildContext context) => SafeArea(
      child: AnimatedBuilder(
          animation: timer,
          builder: (context, _) => SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                    title: const Text('定时关闭'),
                    subtitle: Text(timer.label),
                    trailing: IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close))),
                ListTile(
                    leading: const Icon(Icons.timer_off_outlined),
                    title: const Text('关闭定时'),
                    onTap: () {
                      timer.cancel();
                      Navigator.pop(context);
                    }),
                for (final count in [1, 2])
                  ListTile(
                      leading: const Icon(Icons.playlist_play),
                      title: Text(count == 1 ? '播完本集' : '播完两集（含本集）'),
                      trailing: timer.remainingEpisodes == count
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () {
                        timer.afterEpisodes(count);
                        Navigator.pop(context);
                      }),
                for (final minutes in [15, 30, 60, 90])
                  ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: Text('$minutes 分钟后'),
                      onTap: () {
                        timer.after(Duration(minutes: minutes));
                        Navigator.pop(context);
                      }),
              ]))));
}
