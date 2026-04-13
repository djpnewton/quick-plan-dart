import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/model/measurement_system.dart';
import '../run_state.dart';
import 'run_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Plan'),
        centerTitle: false,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: Text('v0.1')),
          ),
        ],
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: _HomeForm(),
      ),
    );
  }
}

class _HomeForm extends StatefulWidget {
  const _HomeForm();

  @override
  State<_HomeForm> createState() => _HomeFormState();
}

class _HomeFormState extends State<_HomeForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // ── All form state lives here — updated with plain setState() ─────────────
  bool _obscurePassword = true;
  String _csvFileName = '';
  Uint8List? _csvBytes;
  bool _csvMissing = false;
  bool _dateMissing = false;
  RunMode _mode = RunMode.import;
  bool _autoCooldown = false;
  MeasurementSystem _measurementSystem = MeasurementSystem.metric;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email') ?? '';
    final password = prefs.getString('password') ?? '';
    if (email.isNotEmpty || password.isNotEmpty) {
      setState(() {
        _emailController.text = email;
        _passwordController.text = password;
      });
    }
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('email', _emailController.text);
    await prefs.setString('password', _passwordController.text);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Credentials ──────────────────────────────────────────────────
          _SectionHeader('Garmin Connect Credentials'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Email is required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            obscureText: _obscurePassword,
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Password is required' : null,
          ),
          const SizedBox(height: 24),

          // ── CSV File ──────────────────────────────────────────────────────
          _SectionHeader('Training Plan CSV'),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Choose file'),
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['csv'],
                    withData: true,
                  );
                  if (result != null && result.files.isNotEmpty) {
                    final file = result.files.first;
                    setState(() {
                      _csvFileName = file.name;
                      _csvBytes = file.bytes;
                      _csvMissing = false;
                    });
                  }
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _csvFileName.isEmpty ? 'No file selected' : _csvFileName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _csvFileName.isEmpty
                        ? Theme.of(context).hintColor
                        : null,
                  ),
                ),
              ),
            ],
          ),
          if (_csvMissing)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                'Please select a CSV file.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 24),

          // ── Mode ──────────────────────────────────────────────────────────
          _SectionHeader('Command'),
          const SizedBox(height: 4),
          RadioGroup<RunMode>(
            groupValue: _mode,
            onChanged: (v) {
              if (v != null) setState(() => _mode = v);
            },
            child: Column(
              children: [
                RadioListTile<RunMode>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Import workouts'),
                  subtitle: const Text(
                    'Upload workout definitions to Garmin Connect',
                  ),
                  value: RunMode.import,
                ),
                RadioListTile<RunMode>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Schedule plan'),
                  subtitle: const Text(
                    'Upload and schedule workouts on the Garmin calendar',
                  ),
                  value: RunMode.schedule,
                ),
                RadioListTile<RunMode>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Delete workouts'),
                  subtitle: const Text(
                    'Delete all Garmin Connect workouts matching names in the CSV',
                  ),
                  value: RunMode.delete,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Schedule dates (only shown in schedule mode) ──────────────────
          if (_mode == RunMode.schedule) ...[
            _DateField(
              label: 'Start date (first day of first week)',
              value: _startDate,
              onChanged: (d) => setState(() {
                _startDate = d;
                _endDate = null;
                _dateMissing = false;
              }),
            ),
            const SizedBox(height: 8),
            _DateField(
              label: 'End date (last day of last week, used if start not set)',
              value: _endDate,
              onChanged: (d) => setState(() {
                _endDate = d;
                _dateMissing = false;
              }),
            ),
            if (_dateMissing)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  'Please set a start date or end date.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ],

          // ── Options ───────────────────────────────────────────────────────
          _SectionHeader('Options'),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Auto-cooldown: add lap-button cooldown step to each workout',
            ),
            value: _autoCooldown,
            onChanged: (v) => setState(() => _autoCooldown = v ?? false),
          ),
          const SizedBox(height: 12),

          // ── Measurement system ────────────────────────────────────────────
          Row(
            children: [
              const Text('Measurement system:'),
              const SizedBox(width: 12),
              DropdownButton<MeasurementSystem>(
                value: _measurementSystem,
                items: MeasurementSystem.values
                    .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                    .toList(),
                onChanged: (v) => setState(
                  () => _measurementSystem = v ?? _measurementSystem,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // ── Run button ────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text('Run', style: const TextStyle(fontSize: 16)),
              onPressed: _submit,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _submit() {
    if (_csvBytes == null) {
      setState(() => _csvMissing = true);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_mode == RunMode.schedule && _startDate == null && _endDate == null) {
      setState(() => _dateMissing = true);
      return;
    }

    final state = context.read<RunState>();
    if (state.isRunning) return;
    _saveCredentials();
    state.reset();
    state.run(
      email: _emailController.text,
      password: _passwordController.text,
      csvBytes: _csvBytes!,
      runMode: _mode,
      autoCooldown: _autoCooldown,
      measurementSystem: _measurementSystem,
      startDate: _startDate,
      endDate: _endDate,
    );

    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RunScreen()));
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd');
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2015),
          lastDate: DateTime(2040),
        );
        onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(value != null ? fmt.format(value!) : 'Tap to pick a date'),
      ),
    );
  }
}
