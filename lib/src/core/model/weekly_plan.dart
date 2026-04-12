import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';

import 'measurement_system.dart';
import 'workout.dart';

/// Parses a CSV training plan and resolves workout references across weeks.
///
/// CSV format: row 0 is a header (skipped). Each data row begins with a week
/// number in column 0; columns 1–7 represent the 7 days of that week.
/// A cell may contain:
///   - a workout definition (e.g. "running: run-fast - warmup: …")
///   - a workout reference (name of a previously defined workout)
///   - "rest" or blank (no workout)
class WeeklyPlan {
  WeeklyPlan(Uint8List csvBytes, this.msys)
    : _processed = _buildPlan(csvBytes, msys);

  final MeasurementSystem msys;
  final List<Workout?> _processed;

  /// All [WorkoutDef]s defined in this plan (unique definitions only).
  List<WorkoutDef> get workouts =>
      _processed.whereType<WorkoutDef>().fold<List<WorkoutDef>>([], (acc, w) {
        if (!acc.any((x) => x.name == w.name)) acc.add(w);
        return acc;
      });

  /// The schedule as [(WorkoutRef|null)] — one entry per day across all weeks.
  /// WorkoutDef cells are returned as their corresponding [WorkoutRef].
  List<WorkoutRef?> get schedule => _processed.map((w) {
    if (w is WorkoutDef) return w.toRef();
    if (w is WorkoutRef) return w;
    return null;
  }).toList();

  /// Workout entries that failed to parse.
  /// Workout entries that failed to parse.
  List<Workout> get invalid =>
      _processed.whereType<Workout>().where((w) => !w.isValid).toList();

  // ---------------------------------------------------------------------------

  static List<Workout?> _buildPlan(Uint8List csvBytes, MeasurementSystem msys) {
    final content = utf8.decode(csvBytes, allowMalformed: true);
    final rows = const CsvToListConverter(eol: '\n').convert(content);
    final validWeeks = rows.where(_isValidWeek).toList();
    final parser = WorkoutParser(msys);

    final result = <Workout?>[];
    for (final week in validWeeks) {
      result.addAll(_processWeek(week, result, parser));
    }
    return result;
  }

  static List<Workout?> _processWeek(
    List<dynamic> week,
    List<Workout?> previous,
    WorkoutParser parser,
  ) {
    final dayResults = <Workout?>[];

    for (var dayNo = 0; dayNo < 7; dayNo++) {
      final cellIndex = dayNo + 1; // col 0 = week number
      final rawCell = cellIndex < week.length ? week[cellIndex].toString() : '';
      final text = rawCell.trim();

      if (text.isEmpty) {
        dayResults.add(null);
        continue;
      }

      final parsed = parser.parse(text);
      if (parsed is WorkoutNote) {
        // Try to resolve as a reference to a previously defined workout
        final hasMatch = _onlyDefs([
          ...previous,
          ...dayResults,
        ]).any((d) => d.name == text);
        dayResults.add(hasMatch ? WorkoutRef(text) : parsed);
      } else {
        dayResults.add(parsed);
      }
    }
    return dayResults;
  }

  static bool _isValidWeek(List<dynamic> row) {
    if (row.isEmpty) return false;
    final first = row[0].toString().trim();
    return first.isNotEmpty && first.split('').every((c) => _isDigit(c));
  }

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  static Iterable<WorkoutDef> _onlyDefs(Iterable<Workout?> days) =>
      days.whereType<WorkoutDef>();
}
