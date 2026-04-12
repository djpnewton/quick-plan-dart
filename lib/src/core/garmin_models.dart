/// Holds the OAuth2 bearer token for an authenticated Garmin Connect session.
class GarminSession {
  const GarminSession(this.accessToken);
  final String accessToken;
}

/// A workout that exists on Garmin Connect, identified by its name and server-assigned ID.
class GarminWorkout {
  const GarminWorkout(this.name, this.id);
  final String name;
  final int id;

  @override
  String toString() => '$name (#$id)';
}
