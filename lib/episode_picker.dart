import 'package:flutter/material.dart';
import 'api.dart';

class EpisodeChoice {
  final int line, episode;
  const EpisodeChoice(this.line, this.episode);
}

class EpisodePicker extends StatefulWidget {
  final List<PlayLine> lines;
  final String currentUrl, currentLine;
  const EpisodePicker(
      {super.key,
      required this.lines,
      required this.currentUrl,
      required this.currentLine});
  @override
  State<EpisodePicker> createState() => _EpisodePickerState();
}

class _EpisodePickerState extends State<EpisodePicker> {
  late int line;
  @override
  void initState() {
    super.initState();
    final found =
        widget.lines.indexWhere((item) => item.name == widget.currentLine);
    line = found < 0 ? 0 : found;
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(children: [
            Row(children: [
              const SizedBox(width: 16),
              const Expanded(child: Text('选集', style: TextStyle(fontSize: 18))),
              IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
            if (widget.lines.length > 1)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButton<int>(
                      isExpanded: true,
                      value: line,
                      items: [
                        for (var i = 0; i < widget.lines.length; i++)
                          DropdownMenuItem(
                              value: i,
                              child: Text(widget.lines[i].name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis))
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => line = value);
                      })),
            Expanded(
                child: ListView.builder(
              itemCount: widget.lines[line].episodes.length,
              itemBuilder: (context, index) {
                final episode = widget.lines[line].episodes[index];
                final selected = episode.url == widget.currentUrl &&
                    widget.lines[line].name == widget.currentLine;
                return ListTile(
                    selected: selected,
                    title: Text(episode.name,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: selected ? const Icon(Icons.play_arrow) : null,
                    onTap: () =>
                        Navigator.pop(context, EpisodeChoice(line, index)));
              },
            )),
          ]),
        ),
      );
}
