import 'dart:convert';

import 'package:quick_plan/src/core/model/measurement_system.dart';
import 'package:quick_plan/src/core/model/weekly_plan.dart';
import 'package:quick_plan/src/core/model/workout.dart';
import 'package:test/test.dart';

// The CSV below matches the README example:
//   Week 1: run-fast definition, rest, rest, run-fast ref, rest, rest, rest
//   Week 2: run-fast ref, cycle-wo definition, rest, run-fast ref, rest, rest, cycle-wo ref
const _csvContent = '''Week,Mon,Tue,Wed,Thu,Fri,Sat,Sun
1,"running: run-fast
- warmup: 10:00 @ z2
- repeat: 3
  - run: 1.5km @ 5:10-4:40
  - recover: 500m @ z2
- cooldown: 05:00",rest,rest,run-fast,rest,rest,rest
2,run-fast,"cycling: cycle-wo
- bike: 15 km @ 20.0-30kph",rest,run-fast,rest,rest,cycle-wo
''';

void main() {
  late WeeklyPlan plan;

  setUp(() {
    plan = WeeklyPlan(utf8.encode(_csvContent), MeasurementSystem.metric);
  });

  test('finds 2 workout definitions', () {
    expect(plan.workouts.length, 2);
    expect(
      plan.workouts.map((w) => w.name),
      containsAll(['run-fast', 'cycle-wo']),
    );
  });

  test('schedule has 14 entries (2 weeks × 7 days)', () {
    expect(plan.schedule.length, 14);
  });

  test('day 0 is run-fast (definition)', () {
    expect(plan.schedule[0]?.name, 'run-fast');
  });

  test('day 1 is null (rest)', () {
    expect(plan.schedule[1], isNull);
  });

  test('day 3 (Thu wk1) is run-fast ref', () {
    expect(plan.schedule[3]?.name, 'run-fast');
  });

  test('day 7 (Mon wk2) is run-fast ref', () {
    expect(plan.schedule[7]?.name, 'run-fast');
  });

  test('day 8 (Tue wk2) is cycle-wo', () {
    expect(plan.schedule[8]?.name, 'cycle-wo');
  });

  test('day 13 (Sun wk2) is cycle-wo ref', () {
    expect(plan.schedule[13]?.name, 'cycle-wo');
  });

  test('no invalid entries', () {
    expect(plan.invalid, isEmpty);
  });

  test('workouts are WorkoutDef instances', () {
    for (final w in plan.workouts) {
      expect(w, isA<WorkoutDef>());
    }
  });
}
