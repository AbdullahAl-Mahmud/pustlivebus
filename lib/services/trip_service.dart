import 'package:firebase_database/firebase_database.dart';

import '../models/transit.dart';

class TripService {
  TripService(this.database);
  final FirebaseDatabase database;

  Future<String> start({
    required String busId,
    required String driverUid,
    required String routeId,
    required Map<String, Object?> position,
  }) async {
    final tripId = database.ref('trips/$busId').push().key!;
    final active = database.ref('activeTrips/$busId');
    final lease = await active.runTransaction((current) {
      if (current != null) return Transaction.abort();
      return Transaction.success({
        'tripId': tripId,
        'driverUid': driverUid,
        'routeId': routeId,
        'startedAt': ServerValue.timestamp,
      });
    }, applyLocally: false);
    if (!lease.committed) {
      throw StateError(
        'This bus already has an open trip. End or recover it before starting another.',
      );
    }
    await database.ref().update({
      'trips/$busId/$tripId': {
        'driverUid': driverUid,
        'routeId': routeId,
        'startedAt': ServerValue.timestamp,
        'status': 'open',
      },
      'live/$busId': {
        ...position,
        'driverUid': driverUid,
        'tripId': tripId,
        'routeId': routeId,
        'sharing': true,
        'ts': ServerValue.timestamp,
      },
    });
    // Including the old trip ID lets server rules reject an obsolete disconnect
    // operation if a newer trip has since taken over this bus.
    await database.ref('live/$busId').onDisconnect().update({
      'sharing': false,
      'tripId': tripId,
    });
    return tripId;
  }

  Future<void> finish({required String busId, required String tripId}) async {
    final active = await database.ref('activeTrips/$busId').get();
    final value = active.value;
    if (value is! Map || value['tripId'] != tripId) {
      throw StateError(
        'This trip is no longer the active session. Reload before making changes.',
      );
    }
    final history = database.ref('trips/$busId/$tripId');
    final existing = await history.get();
    if (objectMap(existing.value)['status'] != 'ended') {
      final lease = objectMap(value)..remove('tripId');
      await history.update({
        if (!existing.exists) ...lease,
        'status': 'ended',
        'endedAt': ServerValue.timestamp,
      });
    }
    await database.ref('live/$busId').runTransaction((value) {
      if (value is! Map || value['tripId'] != tripId) {
        return Transaction.abort();
      }
      return Transaction.success({...value, 'sharing': false});
    }, applyLocally: false);
    await database.ref('activeTrips/$busId').runTransaction((value) {
      if (value is! Map || value['tripId'] != tripId) {
        return Transaction.abort();
      }
      return Transaction.success(null);
    }, applyLocally: false);
    await database.ref('live/$busId').onDisconnect().cancel();
  }
}
