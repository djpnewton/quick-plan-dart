import 'measurement_system.dart';
import 'step.dart';
import 'workout_duration.dart';

/// A workout entry parsed from a CSV cell.
sealed class Workout {
  const Workout();

  Map<String, dynamic> toJson() => {};
  bool get isValid => true;
}

// ---------------------------------------------------------------------------
// Successful parse variants
// ---------------------------------------------------------------------------

/// A complete workout definition with sport type, name, and steps.
final class WorkoutDef extends Workout {
  const WorkoutDef(this.sport, this.name, [this.steps = const []]);

  final String sport;
  final String name;
  final List<Step> steps;

  WorkoutRef toRef() => WorkoutRef(name);

  WorkoutDef withStep(Step step) => WorkoutDef(sport, name, [...steps, step]);

  @override
  Map<String, dynamic> toJson() {
    final (id, key) = sportInfo(sport);
    return {
      'sportType': {'sportTypeId': id, 'sportTypeKey': key},
      'workoutName': name,
      'workoutSegments': [
        {
          'segmentOrder': 1,
          'sportType': {'sportTypeId': id, 'sportTypeKey': sport},
          'workoutSteps': [
            for (var i = 0; i < steps.length; i++) steps[i].toJson(i + 1),
          ],
        },
      ],
    };
  }
}

/// A reference to a previously defined workout (just a name).
final class WorkoutRef extends Workout {
  const WorkoutRef(this.name);
  final String name;
}

/// A non-workout cell that doesn't match any known pattern (e.g. "rest").
final class WorkoutNote extends Workout {
  const WorkoutNote(this.note);
  final String note;
}

// ---------------------------------------------------------------------------
// Parse failure variants
// ---------------------------------------------------------------------------

/// A cell that looked like a workout header but failed to parse.
final class WorkoutDefFailure extends Workout {
  const WorkoutDefFailure(this.type, this.original, this.cause);

  final String type;
  final String original;
  final String cause;

  @override
  bool get isValid => false;

  @override
  String toString() =>
      'Possible workout definition that can\'t be parsed: "$original"\n'
      'Cause: "$cause"\n'
      '-------------------------------------';
}

/// A workout whose step block failed to parse.
final class WorkoutStepFailure extends Workout {
  const WorkoutStepFailure(this.original, this.cause);

  final String original;
  final String cause;

  @override
  bool get isValid => false;

  @override
  String toString() =>
      'Workout steps that can\'t be parsed: "$original"\n'
      'Cause: "$cause"\n'
      '-------------------------------------';
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

class WorkoutParser {
  WorkoutParser(this.msys);

  final MeasurementSystem msys;

  // Matches a full workout header line + optional step lines
  static final _workoutHeaderRx = RegExp(
    r'^(running|cycling|custom)?:\s*([\u0020-\u007F]+)'
    r'(([\r\n]+\s*-\s[a-z]+:.*)*)$',
  );

  // Matches a cell that has a header-shaped beginning (to classify as failure)
  static final _possibleHeaderRx = RegExp(
    r'^\s*(running|cycling|custom)?\s*:\s*.*(([\r\n]+\s*.*)*)$',
  );

  // Matches the next step block + remaining text
  static final _nextStepRx = RegExp(
    r'^((-\s\w*:\s.*)(([\r\n]+\s{1,}-\s.*)*))((\s.*)*)$',
  );

  Workout parse(String text) {
    final hm = _workoutHeaderRx.firstMatch(text);
    if (hm != null) {
      final sportOrNull = hm.group(1);
      final name = hm.group(2)!.trim();
      final stepsText = hm.group(3)!.trim();
      final sport = sportOrNull ?? _detectSport(stepsText);
      return _loop(WorkoutDef(sport, name), stepsText);
    }

    final pm = _possibleHeaderRx.firstMatch(text);
    if (pm != null) {
      return WorkoutDefFailure(
        pm.group(1) ?? '',
        text,
        pm.group(2)?.trim() ?? '',
      );
    }

    return WorkoutNote(text);
  }

  Workout _loop(WorkoutDef w, String steps) {
    if (steps.isEmpty) return w;

    final sm = _nextStepRx.firstMatch(steps);
    if (sm == null) return WorkoutStepFailure(w.name, steps.trim());

    final next = sm.group(1)!;
    final rest = sm.group(5) ?? '';

    try {
      final newWorkout = w.withStep(StepParser(msys).parse(next.trim()));
      if (rest.trim().isEmpty) return newWorkout;
      return _loop(newWorkout, rest.trim());
    } on ArgumentError catch (ex) {
      return WorkoutStepFailure(w.name, ex.message.toString().trim());
    }
  }

  static String _detectSport(String steps) {
    if (steps.contains('- run')) return 'running';
    if (steps.contains('- bike')) return 'cycling';
    return 'custom';
  }
}

// ---------------------------------------------------------------------------
// Sport helpers (shared with WorkoutDef.toJson)
// ---------------------------------------------------------------------------

(int, String) sportInfo(String sport) => (sportId(sport), sportTypeKey(sport));

int sportId(String sport) => switch (sport) {
  'running' => 1,
  'cycling' => 2,
  'custom' => 3,
  _ => throw ArgumentError(
    "Only running, cycling and 'custom' workouts are supported.",
  ),
};

String sportTypeKey(String sport) => sport == 'custom' ? 'other' : sport;

// ---------------------------------------------------------------------------
// Convenience auto-cooldown helper
// ---------------------------------------------------------------------------

extension WorkoutDefExt on WorkoutDef {
  WorkoutDef withAutoCooldown() => WorkoutDef(sport, name, [
    ...steps,
    CooldownStep(LapButtonPressed.instance),
  ]);
}
