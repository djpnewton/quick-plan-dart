/// Unit of distance measurement understood by the workout notation.
enum DistanceUnit {
  km('km', 'kilometer', _kmToMeters),
  mi('mi', 'mile', _miToMeters),
  m('m', 'meter', _mToMeters);

  const DistanceUnit(this.shortName, this.fullName, this._toMeters);

  final String shortName;
  final String fullName;
  final double Function(double) _toMeters;

  double toMeters(double v) => _toMeters(v);

  static double _kmToMeters(double v) => v * 1000.0;
  static double _miToMeters(double v) => v * 1609.344;
  static double _mToMeters(double v) => v * 1.0;

  static DistanceUnit named(String name) {
    return DistanceUnit.values.firstWhere(
      (u) => u.shortName == name,
      orElse: () => throw ArgumentError('No distance unit: $name'),
    );
  }

  static DistanceUnit withPaceUOM(String paceUom) => switch (paceUom) {
    'mpk' => DistanceUnit.km,
    'mpm' => DistanceUnit.mi,
    _ => throw ArgumentError("No such pace unit of measurement: '$paceUom'"),
  };

  static DistanceUnit withSpeedUOM(String speedUom) => switch (speedUom) {
    'kph' => DistanceUnit.km,
    'mph' => DistanceUnit.mi,
    _ => throw ArgumentError("No such speed unit of measurement: '$speedUom'"),
  };
}
