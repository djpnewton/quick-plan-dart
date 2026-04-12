// Named WorkoutDuration to avoid shadowing dart:core Duration.

import 'distance_unit.dart';

sealed class WorkoutDuration {
  const WorkoutDuration();

  Map<String, dynamic> toJson();

  static final _distanceRx = RegExp(r'^(\d+(?:[.]\d+)?)\s*(km|mi|m)$');
  static final _minutesRx = RegExp(r'^(\d{1,3}):(\d{2})$');

  /// Parses a duration string such as "2km", "500m", "10:00" or "lap-button".
  static WorkoutDuration parse(String x) {
    final s = x.trim();
    final dm = _distanceRx.firstMatch(s);
    if (dm != null) {
      return DistanceDuration(
        double.parse(dm.group(1)!),
        DistanceUnit.named(dm.group(2)!),
      );
    }
    final tm = _minutesRx.firstMatch(s);
    if (tm != null) {
      return TimeDuration(
        minutes: int.parse(tm.group(1)!),
        seconds: int.parse(tm.group(2)!),
      );
    }
    if (s == 'lap-button') return LapButtonPressed.instance;
    throw ArgumentError('Duration cannot be parsed: $x');
  }
}

/// A distance-based end condition (e.g. "2km", "500m", "1.5mi").
final class DistanceDuration extends WorkoutDuration {
  const DistanceDuration(this.distance, this.unit);

  final double distance;
  final DistanceUnit unit;

  @override
  Map<String, dynamic> toJson() => {
    'endCondition': {'conditionTypeKey': 'distance', 'conditionTypeId': 3},
    'preferredEndConditionUnit': {'unitKey': unit.fullName},
    'endConditionValue': unit.toMeters(distance),
    'endConditionCompare': null,
    'endConditionZone': null,
  };

  @override
  bool operator ==(Object other) =>
      other is DistanceDuration &&
      other.distance == distance &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(distance, unit);
}

/// A time-based end condition (e.g. "10:00", "5:30").
final class TimeDuration extends WorkoutDuration {
  const TimeDuration({this.minutes = 0, this.seconds = 0});

  final int minutes;
  final int seconds;

  @override
  Map<String, dynamic> toJson() => {
    'endCondition': {'conditionTypeKey': 'time', 'conditionTypeId': 2},
    'preferredEndConditionUnit': null,
    'endConditionValue': minutes * 60 + seconds,
    'endConditionCompare': null,
    'endConditionZone': null,
  };

  @override
  bool operator ==(Object other) =>
      other is TimeDuration &&
      other.minutes == minutes &&
      other.seconds == seconds;

  @override
  int get hashCode => Object.hash(minutes, seconds);
}

/// The step ends when the athlete presses the lap button.
final class LapButtonPressed extends WorkoutDuration {
  const LapButtonPressed._();
  static const instance = LapButtonPressed._();

  @override
  Map<String, dynamic> toJson() => {
    'endCondition': {'conditionTypeKey': 'lap.button', 'conditionTypeId': 1},
    'preferredEndConditionUnit': null,
    'endConditionValue': null,
    'endConditionCompare': null,
    'endConditionZone': null,
  };

  @override
  bool operator ==(Object other) => other is LapButtonPressed;

  @override
  int get hashCode => 0;
}
