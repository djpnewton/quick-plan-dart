import 'measurement_system.dart';
import 'target.dart';
import 'workout_duration.dart';

/// A single step inside a workout definition.
sealed class Step {
  const Step();

  String get type;
  int get typeId;

  Map<String, dynamic> toJson(int order);
}

/// A step that runs for a given duration with an optional training target.
abstract base class DurationStep extends Step {
  const DurationStep();

  WorkoutDuration get duration;
  Target? get target;

  @override
  Map<String, dynamic> toJson(int order) {
    final base = <String, dynamic>{
      'type': 'ExecutableStepDTO',
      'stepId': null,
      'stepOrder': order,
      'childStepId': null,
      'description': null,
      'stepType': {'stepTypeId': typeId, 'stepTypeKey': type},
    };
    final merged = {...base, ...duration.toJson()};
    final targetJson = target?.toJson() ?? NoTarget.instance.toJson();
    return {...merged, ...targetJson};
  }
}

/// A warmup step.
final class WarmupStep extends DurationStep {
  const WarmupStep(this.duration, [this.target]);

  @override
  final WorkoutDuration duration;
  @override
  final Target? target;

  @override
  String get type => 'warmup';
  @override
  int get typeId => 1;
}

/// A cooldown step.
final class CooldownStep extends DurationStep {
  const CooldownStep(this.duration, [this.target]);

  @override
  final WorkoutDuration duration;
  @override
  final Target? target;

  @override
  String get type => 'cooldown';
  @override
  int get typeId => 2;
}

/// An active work interval (run / bike / go).
final class IntervalStep extends DurationStep {
  const IntervalStep(this.duration, [this.target]);

  @override
  final WorkoutDuration duration;
  @override
  final Target? target;

  @override
  String get type => 'interval';
  @override
  int get typeId => 3;
}

/// A recovery step.
final class RecoverStep extends DurationStep {
  const RecoverStep(this.duration, [this.target]);

  @override
  final WorkoutDuration duration;
  @override
  final Target? target;

  @override
  String get type => 'recovery';
  @override
  int get typeId => 4;
}

/// A repeated block of sub-steps.
final class RepeatStep extends Step {
  const RepeatStep(this.count, this.steps);

  final int count;
  final List<Step> steps;

  @override
  String get type => 'repeat';
  @override
  int get typeId => 6;

  @override
  Map<String, dynamic> toJson(int order) => {
    'stepId': null,
    'stepOrder': order,
    'stepType': {'stepTypeId': typeId, 'stepTypeKey': 'repeat'},
    'numberOfIterations': count,
    'smartRepeat': false,
    'childStepId': 1,
    'workoutSteps': [
      for (var i = 0; i < steps.length; i++) steps[i].toJson(i + 1),
    ],
    'type': 'RepeatGroupDTO',
  };
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

class StepParser {
  StepParser(this.msys);

  final MeasurementSystem msys;

  /// Parses a step text block (possibly multi-line for repeat steps).
  Step parse(String text) => _loop(0, text);

  Step _loop(int depth, String x) {
    final indent = depth * 2;
    final stepRx = _buildStepRx(indent);
    final headerRx = _buildHeaderRx(indent);
    final paramsRx = RegExp(r'^([\w\-\.:\s]+)\s*(?:@(.*))?$');

    DurationStep parseDurationStep(String raw) {
      final hm = headerRx.firstMatch(raw);
      if (hm == null) {
        throw ArgumentError('Cannot parse duration step: $raw');
      }
      final name = hm.group(1)!;
      final params = hm.group(2)!;
      final (dur, tgt) = _expect(params, paramsRx);
      return switch (name) {
        'warmup' => WarmupStep(dur, tgt),
        'run' || 'bike' || 'go' => IntervalStep(dur, tgt),
        'recover' => RecoverStep(dur, tgt),
        'cooldown' => CooldownStep(dur, tgt),
        _ => throw ArgumentError("'$name' is not a duration step type"),
      };
    }

    final sm = stepRx.firstMatch(x);
    if (sm == null) throw ArgumentError('Cannot parse step: $x');

    final header = sm.group(1)!;
    final subdef = sm.group(2) ?? '';

    if (subdef.isNotEmpty) {
      final hm = headerRx.firstMatch(header);
      if (hm == null) throw ArgumentError('Cannot parse repeat step $header');
      final name = hm.group(1)!;
      final params = hm.group(2)!;
      if (name != 'repeat') {
        throw ArgumentError(
          "'$name' cannot contain sub-steps, it must be 'repeat'",
        );
      }
      final nextIndent = indent + 2;
      final nextText = subdef.replaceFirst(RegExp(r'^[\r\n]*'), '');
      // Split on newlines followed by the next indent level's dash
      final raw = nextText.split(RegExp('[\r\n]{1,2}\\s{$nextIndent}-'));
      final parts = raw.isNotEmpty
          ? [raw.first, ...raw.skip(1).map((s) => '${' ' * nextIndent}-$s')]
          : raw;
      return RepeatStep(int.parse(params.trim()), [
        for (final p in parts) _loop(depth + 1, p),
      ]);
    }

    return parseDurationStep(header);
  }

  (WorkoutDuration, Target?) _expect(String raw, RegExp paramsRx) {
    final m = paramsRx.firstMatch(raw.trim());
    if (m == null) {
      throw ArgumentError('Cannot parse step parameters $raw');
    }
    final durationStr = m.group(1)!.trim();
    final targetStr = m.group(2)?.trim();
    final tgt = (targetStr != null && targetStr.isNotEmpty)
        ? Target.parse(targetStr, msys)
        : null;
    return (WorkoutDuration.parse(durationStr), tgt);
  }

  static RegExp _buildStepRx(int indent) {
    final i = RegExp.escape(' ' * indent);
    return RegExp(
      r'^(' + i + r'-\s\w*:\s.*)(([\r\n]+\s{1,}-\s.*)*)$',
      dotAll: false,
    );
  }

  static RegExp _buildHeaderRx(int indent) {
    final i = RegExp.escape(' ' * indent);
    return RegExp(r'^\s*' + i + r'-\s*(\w*):(.*)$');
  }
}
