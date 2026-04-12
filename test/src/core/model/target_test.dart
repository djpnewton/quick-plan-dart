import 'package:quick_plan/src/core/model/measurement_system.dart';
import 'package:quick_plan/src/core/model/target.dart';
import 'package:test/test.dart';

void main() {
  const metric = MeasurementSystem.metric;
  const imperial = MeasurementSystem.imperial;

  group('Target.parse', () {
    test('HR zone z2', () {
      final t = Target.parse('z2', metric);
      expect(t, isA<HrZoneTarget>());
      expect((t as HrZoneTarget).zone, 2);
    });

    test('HR custom bpm', () {
      final t = Target.parse('130-140 bpm', metric);
      final h = t as HrCustomTarget;
      expect(h.from, 130);
      expect(h.to, 140);
    });

    test('pace range default metric', () {
      final t = Target.parse('5:10-4:40', metric);
      expect(t, isA<PaceTarget>());
    });

    test('pace range explicit mpk', () {
      final t = Target.parse('5:05-4:50 mpk', metric);
      expect(t, isA<PaceTarget>());
    });

    test('pace range explicit mpm → imperial', () {
      final t = Target.parse('8:00-7:30 mpm', imperial);
      final pt = t as PaceTarget;
      expect(pt.from.uom.shortName, 'mi');
    });

    test('speed range kph', () {
      final t = Target.parse('20.0-30.0 kph', metric);
      expect(t, isA<SpeedTarget>());
      final st = t as SpeedTarget;
      expect(st.from.unit.shortName, 'km');
    });

    test('power W', () {
      final t = Target.parse('200-250 W', metric);
      final p = t as PowerCustomTarget;
      expect(p.from, 200);
      expect(p.to, 250);
    });

    test('cadence rpm', () {
      final t = Target.parse('85-95 rpm', metric);
      final c = t as CadenceCustomTarget;
      expect(c.from, 85);
      expect(c.to, 95);
    });

    test('throws on unknown target', () {
      expect(() => Target.parse('nonsense', metric), throwsArgumentError);
    });
  });

  group('Target.toJson type ids', () {
    test('NoTarget → typeId 1', () {
      final j = NoTarget.instance.toJson();
      expect((j['targetType'] as Map)['workoutTargetTypeId'], 1);
    });

    test('HrZoneTarget → typeId 4', () {
      final j = HrZoneTarget(2).toJson();
      expect((j['targetType'] as Map)['workoutTargetTypeId'], 4);
    });

    test('PaceTarget → typeId 6', () {
      final t = Target.parse('5:10-4:40', metric) as PaceTarget;
      final j = t.toJson();
      expect((j['targetType'] as Map)['workoutTargetTypeId'], 6);
    });

    test('SpeedTarget → typeId 5', () {
      final t = Target.parse('20.0-30.0 kph', metric) as SpeedTarget;
      expect((t.toJson()['targetType'] as Map)['workoutTargetTypeId'], 5);
    });
  });
}
