import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/garmin_api.dart';
import '../core/garmin_auth.dart';
import '../core/garmin_models.dart';
import '../core/model/measurement_system.dart';
import '../core/model/weekly_plan.dart';
import '../core/model/workout.dart';

enum RunMode { import, schedule }

/// Operation state shared between HomeScreen and RunScreen.
/// Holds only what RunScreen needs to display; config is passed into run().
class RunState extends ChangeNotifier {
  // The mode is stored here so RunScreen can read it for its title.
  RunMode mode = RunMode.import;

  bool isRunning = false;
  bool isFinished = false;
  final List<String> logLines = [];

  void log(String line) {
    logLines.add(line);
    notifyListeners();
  }

  void reset() {
    isRunning = false;
    isFinished = false;
    logLines.clear();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Main execute — all config is passed as parameters
  // ---------------------------------------------------------------------------

  Future<void> run({
    required String email,
    required String password,
    required Uint8List csvBytes,
    required RunMode runMode,
    required bool deleteExisting,
    required bool autoCooldown,
    required MeasurementSystem measurementSystem,
    required DateTime? startDate,
    required DateTime? endDate,
  }) async {
    mode = runMode;
    isRunning = true;
    isFinished = false;
    logLines.clear();
    notifyListeners();

    try {
      await _execute(
        email: email,
        password: password,
        csvBytes: csvBytes,
        runMode: runMode,
        deleteExisting: deleteExisting,
        autoCooldown: autoCooldown,
        measurementSystem: measurementSystem,
        startDate: startDate,
        endDate: endDate,
      );
    } catch (e) {
      log('ERROR: $e');
    } finally {
      isRunning = false;
      isFinished = true;
      notifyListeners();
    }
  }

  Future<void> _execute({
    required String email,
    required String password,
    required Uint8List csvBytes,
    required RunMode runMode,
    required bool deleteExisting,
    required bool autoCooldown,
    required MeasurementSystem measurementSystem,
    required DateTime? startDate,
    required DateTime? endDate,
  }) async {
    final plan = WeeklyPlan(csvBytes, measurementSystem);

    if (plan.invalid.isNotEmpty) {
      for (final item in plan.invalid) {
        log('WARNING: $item');
      }
    }

    log(
      'Plan loaded: ${plan.workouts.length} workout(s) defined, '
      '${plan.schedule.length} day(s) scheduled.',
    );

    var workouts = plan.workouts;
    if (autoCooldown) {
      workouts = workouts.map((w) => w.withAutoCooldown()).toList();
    }

    final client = http.Client();
    try {
      final auth = GarminAuth(email, password, client);
      final api = GarminApi(client);

      log('Logging in to Garmin Connect\u2026');
      final session = await auth.login();
      log('Login successful.');

      if (deleteExisting) {
        final deleteCount = await api.deleteWorkouts(
          workouts.map((w) => w.name).toList(),
          session,
          onLog: log,
        );
        log('$deleteCount workout(s) deleted.');
      }

      final garminWorkouts = await api.createWorkouts(
        workouts,
        session,
        onLog: log,
      );
      log('${garminWorkouts.length} workout(s) imported.');

      if (runMode == RunMode.schedule) {
        final scheduleSpec = _buildScheduleSpec(
          plan,
          garminWorkouts,
          startDate: startDate,
          endDate: endDate,
        );
        final scheduleCount = await api.schedule(
          scheduleSpec,
          session,
          onLog: log,
        );
        log('$scheduleCount day(s) scheduled.');
      }

      log('\nDone.');
    } finally {
      client.close();
    }
  }

  List<(DateTime, GarminWorkout)> _buildScheduleSpec(
    WeeklyPlan plan,
    List<GarminWorkout> garminWorkouts, {
    required DateTime? startDate,
    required DateTime? endDate,
  }) {
    final DateTime start;
    if (startDate != null) {
      start = startDate;
    } else if (endDate != null) {
      start = endDate.subtract(Duration(days: plan.schedule.length - 1));
    } else {
      throw Exception('Either start or end date must be set for scheduling.');
    }

    final woMap = {for (final gw in garminWorkouts) gw.name: gw};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final spec = <(DateTime, GarminWorkout)>[];
    for (var i = 0; i < plan.schedule.length; i++) {
      final ref = plan.schedule[i];
      if (ref == null) continue;
      final date = start.add(Duration(days: i));
      if (date.isBefore(today)) continue;
      final gw = woMap[ref.name];
      if (gw != null) spec.add((date, gw));
    }
    return spec;
  }
}
