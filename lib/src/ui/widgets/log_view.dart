import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../run_state.dart';

class LogView extends StatefulWidget {
  const LogView({super.key});

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  final _scrollController = ScrollController();
  int _lastLineCount = 0;
  bool _lastIsFinished = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.select<RunState, (List<String>, bool)>(
      (s) => (s.logLines, s.isFinished),
    );
    final lines = state.$1;
    final isFinished = state.$2;

    // Scroll to bottom when new lines arrive or when the run finishes
    // (finishing reshuffles the layout so maxScrollExtent changes).
    if (lines.length != _lastLineCount || isFinished != _lastIsFinished) {
      _lastLineCount = lines.length;
      _lastIsFinished = isFinished;
      _scrollToBottom();
    }

    return SelectionArea(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(12),
        child: ListView.builder(
          controller: _scrollController,
          itemCount: lines.length,
          itemBuilder: (ctx, i) {
            final line = lines[i];
            Color color = const Color(0xFFCDD6F4); // default text
            if (line.startsWith('ERROR:')) {
              color = const Color(0xFFF38BA8); // red
            } else if (line.startsWith('WARNING:')) {
              color = const Color(0xFFFAB387); // orange
            } else if (line.startsWith('  ')) {
              color = const Color(0xFFA6E3A1); // green for items
            }
            return Text(
              line,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: color,
              ),
            );
          },
        ),
      ),
    );
  }
}
