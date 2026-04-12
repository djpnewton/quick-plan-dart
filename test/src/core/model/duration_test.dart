import 'package:quick_plan/src/core/model/distance_unit.dart';
import 'package:quick_plan/src/core/model/workout_duration.dart';
import 'package:test/test.dart';

void main() {
  group('WorkoutDuration.parse', () {
    test('parses km distance', () {
      final d = WorkoutDuration.parse('2km');
      expect(d, isA<DistanceDuration>());
      final dd = d as DistanceDuration;
      expect(dd.distance, 2.0);
      expect(dd.unit, DistanceUnit.km);
    });

    test('parses metres distance', () {
      final d = WorkoutDuration.parse('500m');
      final dd = d as DistanceDuration;
      expect(dd.distance, 500.0);
      expect(dd.unit, DistanceUnit.m);
    });

    test('parses miles distance', () {
      final d = WorkoutDuration.parse('1.5mi');
      final dd = d as DistanceDuration;
      expect(dd.distance, 1.5);
      expect(dd.unit, DistanceUnit.mi);
    });

    test('parses time MM:SS', () {
      final d = WorkoutDuration.parse('10:00');
      final td = d as TimeDuration;
      expect(td.minutes, 10);
      expect(td.seconds, 0);
    });

    test('parses time with seconds', () {
      final d = WorkoutDuration.parse('5:30');
      final td = d as TimeDuration;
      expect(td.minutes, 5);
      expect(td.seconds, 30);
    });

    test('parses lap-button', () {
      final d = WorkoutDuration.parse('lap-button');
      expect(d, same(LapButtonPressed.instance));
    });

    test('throws on invalid input', () {
      expect(() => WorkoutDuration.parse('banana'), throwsArgumentError);
    });
  });

  group('DistanceDuration.toJson', () {
    test('km uses meters correctly', () {
      final d = DistanceDuration(2.0, DistanceUnit.km);
      final j = d.toJson();
      expect((j['endCondition'] as Map)['conditionTypeId'], 3);
      expect(j['endConditionValue'], closeTo(2000.0, 0.01));
      expect((j['preferredEndConditionUnit'] as Map)['unitKey'], 'kilometer');
    });
  });

  group('TimeDuration.toJson', () {
    test('encodes total seconds', () {
      final d = TimeDuration(minutes: 10, seconds: 30);
      final j = d.toJson();
      expect((j['endCondition'] as Map)['conditionTypeId'], 2);
      expect(j['endConditionValue'], 630);
    });
  });

  group('LapButtonPressed.toJson', () {
    test('encodes lap.button condition', () {
      final j = LapButtonPressed.instance.toJson();
      expect((j['endCondition'] as Map)['conditionTypeKey'], 'lap.button');
      expect((j['endCondition'] as Map)['conditionTypeId'], 1);
    });
  });
}
