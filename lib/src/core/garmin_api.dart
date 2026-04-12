import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cors_proxy.dart';
import 'garmin_models.dart';
import 'model/workout.dart';

/// HTTP client for the Garmin Connect workout API.
///
/// All mutating operations are rate-limited to one request per second to
/// avoid overwhelming the service.
class GarminApi {
  GarminApi(this.client);

  final http.Client client;

  static const _workoutApiBase =
      'https://connectapi.garmin.com/workout-service';

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Imports a list of workout definitions into Garmin Connect.
  Future<List<GarminWorkout>> createWorkouts(
    List<WorkoutDef> workouts,
    GarminSession session, {
    void Function(String)? onLog,
  }) async {
    onLog?.call('\nCreating workouts:');
    final results = <GarminWorkout>[];
    for (final workout in workouts) {
      await Future.delayed(const Duration(seconds: 1));
      onLog?.call('  ${workout.name}…');
      final resp = await client.post(
        proxyUri('$_workoutApiBase/workout'),
        headers: {
          ..._sessionHeaders(session),
          'Content-Type': 'application/json',
        },
        body: jsonEncode(workout.toJson()),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final id = data['workoutId'];
        if (id == null) {
          throw Exception('Cannot parse workoutId from response: ${resp.body}');
        }
        final gw = GarminWorkout(workout.name, (id as num).toInt());
        results.add(gw);
      } else {
        throw Exception(
          'Cannot create workout "${workout.name}": HTTP ${resp.statusCode}',
        );
      }
    }
    return results;
  }

  /// Deletes all Garmin Connect workouts whose names appear in [names].
  Future<int> deleteWorkouts(
    List<String> names,
    GarminSession session, {
    void Function(String)? onLog,
  }) async {
    onLog?.call('\nFetching existing workouts\u2026');
    final wsMap = await _getWorkoutsMap(session);
    onLog?.call('Deleting workouts:');

    var count = 0;
    for (final name in names) {
      final ids = wsMap[name] ?? [];
      if (ids.isEmpty) continue;

      await Future.delayed(const Duration(seconds: 1));
      for (final id in ids) {
        onLog?.call('  $name ($id)…');
        await Future.delayed(const Duration(seconds: 1));
        final resp = await client.delete(
          proxyUri('$_workoutApiBase/workout/$id'),
          headers: _sessionHeaders(session),
        );
        if (resp.statusCode == 204) {
          count++;
        } else {
          onLog?.call(
            '  WARNING: could not delete $name ($id): HTTP ${resp.statusCode}',
          );
        }
      }
    }
    return count;
  }

  /// Schedules [spec] entries (date → workout) in the Garmin Connect calendar.
  Future<int> schedule(
    List<(DateTime, GarminWorkout)> spec,
    GarminSession session, {
    void Function(String)? onLog,
  }) async {
    onLog?.call('\nScheduling:');
    var count = 0;
    for (final (date, gw) in spec) {
      final label = '${date.toIso8601String().substring(0, 10)} -> ${gw.name}';
      onLog?.call('  $label…');
      await Future.delayed(const Duration(seconds: 1));
      final body = jsonEncode({
        'date': date.toIso8601String().substring(0, 10),
      });
      final resp = await client.post(
        proxyUri('$_workoutApiBase/schedule/${gw.id}'),
        headers: {
          ..._sessionHeaders(session),
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (resp.statusCode == 200) {
        onLog?.call('  $label');
        count++;
      } else {
        onLog?.call('  Cannot schedule: $label');
      }
    }
    return count;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, List<int>>> _getWorkoutsMap(GarminSession session) async {
    final resp = await client.get(
      proxyUri('$_workoutApiBase/workouts?start=1&limit=9999'),
      headers: _sessionHeaders(session),
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Cannot retrieve workout list from Garmin Connect: HTTP ${resp.statusCode}',
      );
    }
    final list = jsonDecode(resp.body) as List<dynamic>;
    final nameToIds = <String, List<int>>{};
    for (final item in list) {
      final obj = item as Map<String, dynamic>;
      final name = obj['workoutName'] as String?;
      final id = obj['workoutId'];
      if (name != null && id != null) {
        nameToIds.putIfAbsent(name, () => []).add((id as num).toInt());
      }
    }
    return nameToIds;
  }

  static Map<String, String> _sessionHeaders(GarminSession session) => {
    'Authorization': 'Bearer ${session.accessToken}',
    'User-Agent': 'GCM-iOS-5.22.1.4',
  };
}
