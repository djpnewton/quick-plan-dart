import 'distance_unit.dart';
import 'measurement_system.dart';

/// A training target attached to a workout step.
sealed class Target {
  const Target();

  Map<String, dynamic> toJson();

  static Map<String, dynamic> _targetJson(
    int typeId,
    String typeKey,
    dynamic v1,
    dynamic v2,
    dynamic zone,
  ) => {
    'targetType': {
      'workoutTargetTypeId': typeId,
      'workoutTargetTypeKey': typeKey,
    },
    'targetValueOne': v1,
    'targetValueTwo': v2,
    'zoneNumber': zone,
  };

  // Regex patterns
  static final _cadenceRx = RegExp(r'^(\d{1,3})\s*-\s*(\d{1,3})\s*rpm$');
  static final _hrZoneRx = RegExp(r'^z(\d)$');
  static final _hrCustomRx = RegExp(r'^(\d{1,3})\s*-\s*(\d{1,3})\s*bpm$');
  static final _paceRangeRx = RegExp(
    r'^(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*(mpk|mpm)?$',
  );
  static final _powerCustomRx = RegExp(r'^(\d{1,3})\s*-\s*(\d{1,3})\s*W$');
  static final _speedRangeRx = RegExp(
    r'^(\d{1,3}(?:\.\d{1})?)\s*-\s*(\d{1,3}(?:\.\d{1})?)\s*(kph|mph)?',
  );

  /// Parses a target string such as "z2", "130-140 bpm", "5:10-4:40", "20.0-30kph".
  static Target parse(String x, MeasurementSystem msys) {
    final s = x.trim();

    final cm = _cadenceRx.firstMatch(s);
    if (cm != null) {
      return CadenceCustomTarget(
        int.parse(cm.group(1)!),
        int.parse(cm.group(2)!),
      );
    }

    final hzm = _hrZoneRx.firstMatch(s);
    if (hzm != null) return HrZoneTarget(int.parse(hzm.group(1)!));

    final hcm = _hrCustomRx.firstMatch(s);
    if (hcm != null) {
      return HrCustomTarget(int.parse(hcm.group(1)!), int.parse(hcm.group(2)!));
    }

    final pm = _powerCustomRx.firstMatch(s);
    if (pm != null) {
      return PowerCustomTarget(
        int.parse(pm.group(1)!),
        int.parse(pm.group(2)!),
      );
    }

    final sm = _speedRangeRx.firstMatch(s);
    if (sm != null) {
      final uomStr = sm.group(3);
      final du = uomStr != null
          ? DistanceUnit.withSpeedUOM(uomStr)
          : msys.distance;
      return SpeedTarget(Speed(du, sm.group(1)!), Speed(du, sm.group(2)!));
    }

    final prm = _paceRangeRx.firstMatch(s);
    if (prm != null) {
      final uomStr = prm.group(3);
      final du = uomStr != null
          ? DistanceUnit.withPaceUOM(uomStr)
          : msys.distance;
      return PaceTarget(Pace(du, prm.group(1)!), Pace(du, prm.group(2)!));
    }

    throw ArgumentError("'$s' is not a valid target specification");
  }
}

/// No target attached to the step.
final class NoTarget extends Target {
  const NoTarget._();
  static const instance = NoTarget._();

  @override
  Map<String, dynamic> toJson() =>
      Target._targetJson(1, 'no.target', null, null, null);
}

/// A named heart-rate zone (e.g. "z2" → zone 2).
final class HrZoneTarget extends Target {
  const HrZoneTarget(this.zone);
  final int zone;

  @override
  Map<String, dynamic> toJson() =>
      Target._targetJson(4, 'heart.rate.zone', '', '', zone.toString());
}

/// A custom heart-rate range in bpm (e.g. "130-140 bpm").
final class HrCustomTarget extends Target {
  const HrCustomTarget(this.from, this.to);
  final int from;
  final int to;

  @override
  Map<String, dynamic> toJson() =>
      Target._targetJson(4, 'heart.rate.zone', from, to, null);
}

/// A pace range (e.g. "5:10-4:40" or "5:10-4:40 mpk").
final class PaceTarget extends Target {
  const PaceTarget(this.from, this.to);
  final Pace from;
  final Pace to;

  @override
  Map<String, dynamic> toJson() =>
      Target._targetJson(6, 'pace.zone', from.speedMs, to.speedMs, null);
}

/// A speed range (e.g. "20.0-30 kph").
final class SpeedTarget extends Target {
  const SpeedTarget(this.from, this.to);
  final Speed from;
  final Speed to;

  @override
  Map<String, dynamic> toJson() =>
      Target._targetJson(5, 'speed.zone', from.speedMs, to.speedMs, null);
}

/// A power range in Watts (e.g. "200-250 W").
final class PowerCustomTarget extends Target {
  const PowerCustomTarget(this.from, this.to);
  final int from;
  final int to;

  @override
  Map<String, dynamic> toJson() =>
      Target._targetJson(2, 'power.zone', from, to, null);
}

/// A cadence range in rpm (e.g. "85-95 rpm").
final class CadenceCustomTarget extends Target {
  const CadenceCustomTarget(this.from, this.to);
  final int from;
  final int to;

  @override
  Map<String, dynamic> toJson() =>
      Target._targetJson(3, 'cadence.zone', from, to, null);
}

// ---------------------------------------------------------------------------
// Helper value types
// ---------------------------------------------------------------------------

/// A pace expressed as "M:SS" per [uom] unit.
final class Pace {
  const Pace(this.uom, this.exp);
  final DistanceUnit uom;
  final String exp; // e.g. "5:10"

  int get minutes => int.parse(exp.trim().split(':')[0]);
  int get seconds => int.parse(exp.trim().split(':')[1]);

  /// Speed in m/s.
  double get speedMs => uom.toMeters(1) / (minutes * 60 + seconds);
}

/// A speed expressed numerically per [unit] per hour.
final class Speed {
  const Speed(this.unit, this.exp);
  final DistanceUnit unit;
  final String exp; // e.g. "20.0"

  /// Speed in m/s.
  double get speedMs => unit.toMeters(double.parse(exp)) / 3600;
}
