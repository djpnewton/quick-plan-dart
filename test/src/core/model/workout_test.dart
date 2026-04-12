import 'package:quick_plan/src/core/model/measurement_system.dart';
import 'package:quick_plan/src/core/model/step.dart';
import 'package:quick_plan/src/core/model/workout.dart';
import 'package:test/test.dart';

void main() {
  final parser = WorkoutParser(MeasurementSystem.metric);

  group('WorkoutParser', () {
    test('parses a full running workout', () {
      const text =
          'running: run-fast\n'
          '- warmup: 10:00 @ z2\n'
          '- repeat: 3\n'
          '  - run: 1.5km @ 5:10-4:40\n'
          '  - recover: 500m @ z2\n'
          '- cooldown: 05:00';
      final w = parser.parse(text);
      expect(w, isA<WorkoutDef>());
      final wd = w as WorkoutDef;
      expect(wd.sport, 'running');
      expect(wd.name, 'run-fast');
      expect(wd.steps.length, 3);
    });

    test('parses a cycling workout', () {
      const text = 'cycling: cycle-wo\n- bike: 15 km @ 20.0-30.0 kph';
      final w = parser.parse(text) as WorkoutDef;
      expect(w.sport, 'cycling');
    });

    test('auto-detects sport from steps', () {
      const text = ': my-run\n- run: 1km';
      final w = parser.parse(text) as WorkoutDef;
      expect(w.sport, 'running');
    });

    test('reference-like text becomes WorkoutNote', () {
      final w = parser.parse('run-fast');
      expect(w, isA<WorkoutNote>());
    });

    test('"rest" becomes WorkoutNote', () {
      final w = parser.parse('rest');
      expect(w, isA<WorkoutNote>());
    });

    test('invalid step produces WorkoutStepFailure', () {
      const text = 'running: broken\n- notastep: xyz';
      final w = parser.parse(text);
      expect(w, isA<WorkoutStepFailure>());
      expect(w.isValid, false);
    });
  });

  group('WorkoutDef.toJson', () {
    test('contains workoutName', () {
      const text = 'running: my-workout\n- run: 1km';
      final wd = parser.parse(text) as WorkoutDef;
      final j = wd.toJson();
      expect(j['workoutName'], 'my-workout');
    });

    test('sportType id for running is 1', () {
      const text = 'running: r1\n- run: 1km';
      final wd = parser.parse(text) as WorkoutDef;
      final sportType = wd.toJson()['sportType'] as Map;
      expect(sportType['sportTypeId'], 1);
    });

    test('sportType id for cycling is 2', () {
      const text = 'cycling: c1\n- bike: 1km';
      final wd = parser.parse(text) as WorkoutDef;
      final sportType = wd.toJson()['sportType'] as Map;
      expect(sportType['sportTypeId'], 2);
    });

    test('workoutSegments contain steps', () {
      const text = 'running: r2\n- warmup: 05:00\n- run: 1km';
      final wd = parser.parse(text) as WorkoutDef;
      final seg = (wd.toJson()['workoutSegments'] as List).first as Map;
      final steps = seg['workoutSteps'] as List;
      expect(steps.length, 2);
    });
  });

  group('WorkoutDefExt.withAutoCooldown', () {
    test('adds CooldownStep at end', () {
      const text = 'running: r\n- run: 1km';
      final wd = parser.parse(text) as WorkoutDef;
      final extended = wd.withAutoCooldown();
      expect(extended.steps.length, 2);
      expect(extended.steps.last, isA<CooldownStep>());
    });
  });
}
