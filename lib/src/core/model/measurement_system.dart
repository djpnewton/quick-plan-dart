import 'distance_unit.dart';

/// Defines whether distances/paces are expressed in metric or imperial units.
enum MeasurementSystem {
  metric('metric', DistanceUnit.km),
  imperial('imperial', DistanceUnit.mi);

  const MeasurementSystem(this.name, this.distance);

  final String name;
  final DistanceUnit distance;

  static MeasurementSystem named(String name) {
    return MeasurementSystem.values.firstWhere(
      (s) => s.name == name,
      orElse: () => throw ArgumentError('No measurement system: $name'),
    );
  }
}
