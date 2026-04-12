import 'package:quick_plan/src/core/model/measurement_system.dart';
import 'package:quick_plan/src/core/model/step.dart';
import 'package:test/test.dart';

void main() {
  final parser = StepParser(MeasurementSystem.metric);

  group('Simple steps', () {
    test('warmup step', () {
      final s = parser.parse('- warmup: 10:00 @ z2');
      expect(s, isA<WarmupStep>());
      final ws = s as WarmupStep;
      expect(ws.type, 'warmup');
      expect(ws.typeId, 1);
    });

    test('run → interval step', () {
      final s = parser.parse('- run: 3200m @ 5:05-4:50');
      expect(s, isA<IntervalStep>());
    });

    test('bike → interval step', () {
      final s = parser.parse('- bike: 15 km @ 20.0-30.0 kph');
      expect(s, isA<IntervalStep>());
    });

    test('go → interval step', () {
      final s = parser.parse('- go: 05:00');
      expect(s, isA<IntervalStep>());
    });

    test('recover step', () {
      final s = parser.parse('- recover: 800m @ z2');
      expect(s, isA<RecoverStep>());
      expect(s.typeId, 4);
    });

    test('cooldown step with lap-button', () {
      final s = parser.parse('- cooldown: lap-button');
      expect(s, isA<CooldownStep>());
    });

    test('step without target', () {
      final s = parser.parse('- run: 1km');
      expect(s, isA<IntervalStep>());
      expect((s as IntervalStep).target, isNull);
    });
  });

  group('RepeatStep', () {
    test('parses basic 3-rep block', () {
      final text =
          '- repeat: 3\n  - run: 3200m @ 5:05-4:50\n  - recover: 800m @ z2';
      final s = parser.parse(text);
      expect(s, isA<RepeatStep>());
      final rs = s as RepeatStep;
      expect(rs.count, 3);
      expect(rs.steps.length, 2);
      expect(rs.steps[0], isA<IntervalStep>());
      expect(rs.steps[1], isA<RecoverStep>());
    });

    test('repeat toJson has RepeatGroupDTO', () {
      final text = '- repeat: 2\n  - run: 1km\n  - recover: 500m';
      final s = parser.parse(text) as RepeatStep;
      final j = s.toJson(1);
      expect(j['type'], 'RepeatGroupDTO');
      expect(j['numberOfIterations'], 2);
      final steps = j['workoutSteps'] as List;
      expect(steps.length, 2);
    });
  });

  group('toJson order', () {
    test('stepOrder is set from parameter', () {
      final s = parser.parse('- run: 1km');
      final j = s.toJson(3);
      expect(j['stepOrder'], 3);
    });
  });
}
