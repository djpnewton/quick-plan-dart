import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../run_state.dart';
import '../widgets/log_view.dart';

class RunScreen extends StatelessWidget {
  const RunScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RunState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          state.mode == RunMode.import ? 'Importing…' : 'Scheduling…',
        ),
        automaticallyImplyLeading: false,
        actions: [
          if (state.isFinished)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status bar
            Row(
              children: [
                if (state.isRunning) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 10),
                  const Text('Running — do not close this window.'),
                ] else if (state.isFinished) ...[
                  Icon(
                    _hasErrors(state)
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
                    color: _hasErrors(state) ? Colors.red : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _hasErrors(state) ? 'Finished with errors.' : 'Done!',
                    style: TextStyle(
                      color: _hasErrors(state) ? Colors.red : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            // Log output
            Expanded(child: const LogView()),
            const SizedBox(height: 12),
            // Bottom action
            if (state.isFinished)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to home'),
              ),
          ],
        ),
      ),
    );
  }

  bool _hasErrors(RunState state) =>
      state.logLines.any((l) => l.startsWith('ERROR:'));
}
