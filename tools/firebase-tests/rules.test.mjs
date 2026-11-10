import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { before, beforeEach, after, test } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';

if (!process.env.FIREBASE_DATABASE_EMULATOR_HOST) throw new Error('Local database emulator is required. Never run against production.');
const projectId = 'demo-pustlivebus';
const rules = await readFile(new URL('../../database.rules.json', import.meta.url), 'utf8');
let env;
before(async () => {
  env = await initializeTestEnvironment({ projectId, database: { host: '127.0.0.1', port: 9000, rules } });
});
beforeEach(async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await context.database().ref().set({
      buses: { bus04: { name: 'Padma', number: 4, active: true }, bus05: { name: 'Meghna', number: 5, active: true } },
      routes: { town: { name: 'Town', stops: ['campus', 'terminal'] } },
      stops: { campus: { name: 'Campus' }, terminal: { name: 'Terminal' } },
      schedules: { trip1: { busId: 'bus04', routeId: 'town', departTime: '08:10', dayType: 'regular', audience: 'both' } },
      drivers: { alice: { name: 'Alice', busId: 'bus04', active: true }, bob: { name: 'Bob', busId: 'bus05', active: true } },
    });
  });
});
after(async () => { await env?.cleanup(); });

const db = (uid, claims) => uid ? env.authenticatedContext(uid, claims).database() : env.unauthenticatedContext().database();
const session = (id = 'session1', uid = 'alice') => ({ tripId: id, driverUid: uid, routeId: 'town', startedAt: Date.now() });
const location = (id = 'session1') => ({ lat: 24, lng: 89, accuracy: 12, speedKmh: 30, ts: Date.now(), capturedAt: Date.now(), sharing: true, driverUid: 'alice', routeId: 'town', tripId: id });
const acquire = async (database, id = 'session1') => database.ref('activeTrips/bus04').set(session(id));

test('Public readers can read timetables but cannot edit schedules or GPS', async () => {
  const publicDb = db();
  await assertSucceeds(publicDb.ref('schedules').once('value'));
  await assertSucceeds(publicDb.ref('routes').once('value'));
  await assertFails(publicDb.ref('schedules/trip1/departTime').set('09:00'));
  await assertFails(publicDb.ref('live/bus04').set(location()));
  await assertFails(publicDb.ref('drivers').once('value'));
});
test('A student cannot publish GPS, change assignment or grant admin access', async () => {
  const student = db('student');
  await assertFails(student.ref('live/bus04').set(location()));
  await assertFails(student.ref('drivers/student').set({ name: 'Fake', busId: 'bus04' }));
  await assertFails(student.ref('admins/student').set(true));
  await assertFails(student.ref('buses/bus04/name').set('Fake'));
});
test('Driver can read only their own assignment and assigned bus history', async () => {
  const alice = db('alice');
  await assertSucceeds(alice.ref('drivers/alice').once('value'));
  await assertFails(alice.ref('drivers/bob').once('value'));
  await assertSucceeds(alice.ref('trips/bus04').once('value'));
  await assertFails(alice.ref('trips/bus05').once('value'));
});
test('Only the assigned driver with an active trip can send location', async () => {
  const alice = db('alice'), bob = db('bob');
  await assertFails(alice.ref('live/bus04').set(location()));
  await assertSucceeds(acquire(alice));
  await assertSucceeds(alice.ref('live/bus04').set(location()));
  await assertFails(bob.ref('live/bus04').set(location()));
  await assertFails(alice.ref('live/bus05').set(location()));
});
test('Invalid coordinates, old captured fixes and wrong trip IDs are rejected', async () => {
  const alice = db('alice'); await acquire(alice);
  await assertFails(alice.ref('live/bus04').set({ ...location(), lat: 95 }));
  await assertFails(alice.ref('live/bus04').set({ ...location(), capturedAt: Date.now() - 60000 }));
  await assertFails(alice.ref('live/bus04').set(location('wrong')));
  await assertFails(alice.ref('live/bus04').set({ ...location(), accuracy: 500 }));
});
test('Concurrent trip acquisition allows one session; existing session cannot be replaced', async () => {
  const one = db('alice'), two = env.authenticatedContext('alice', { device: 'other' }).database();
  const claim = (database, id) => database.ref('activeTrips/bus04').transaction((value) => value === null ? session(id) : undefined, undefined, false);
  const results = await Promise.all([claim(one, 'one'), claim(two, 'two')]);
  assert.equal(results.filter((r) => r.committed).length, 1);
  await assertFails(one.ref('activeTrips/bus04').set(session('replacement')));
});
test('Trip ends with history intact and stale disconnect cannot alter a newer trip', async () => {
  const alice = db('alice'); await acquire(alice);
  const startedAt = Date.now();
  await assertSucceeds(alice.ref().update({
    'trips/bus04/session1': { driverUid: 'alice', routeId: 'town', startedAt, status: 'open' },
    'live/bus04': location(),
  }));
  await assertSucceeds(alice.ref('live/bus04').onDisconnect().update({ sharing: false, tripId: 'session1' }));
  await assertSucceeds(alice.ref('trips/bus04/session1').update({ status: 'ended', endedAt: Date.now() }));
  await assertSucceeds(alice.ref('live/bus04').update({ sharing: false }));
  await assertSucceeds(alice.ref('activeTrips/bus04').remove());
  await acquire(alice, 'session2');
  await assertSucceeds(alice.ref('live/bus04').set(location('session2')));
  await assertFails(alice.ref('live/bus04').update({ sharing: false, tripId: 'session1' }));
  await assertFails(alice.ref('trips/bus04/session1/status').set('open'));
  await alice.ref('live/bus04').onDisconnect().cancel();
});
test('Admin claim is required for management; malformed schedules are rejected', async () => {
  const admin = db('admin', { admin: true });
  await assertSucceeds(admin.ref('drivers').once('value'));
  await assertSucceeds(admin.ref('buses/bus04/name').set('Updated Padma'));
  await assertFails(admin.ref('schedules/trip1/departTime').set('25:99'));
  await assertSucceeds(admin.ref('calendar/2026-11-01').set('holiday'));
  await assertFails(admin.ref('calendar/2026-11-01').set('invented'));
});

test('Admin can perform the driver editor read/check/save sequence', async () => {
  const admin = db('transport-admin', { admin: true });
  await assertSucceeds(admin.ref('drivers').once('value'));
  await assertSucceeds(admin.ref('drivers/new-driver').once('value'));
  await assertSucceeds(admin.ref('activeTrips/bus04').once('value'));
  await assertSucceeds(admin.ref('drivers/new-driver').set({name: 'New driver', busId: 'bus04', active: true}));
  assert.equal((await admin.ref('drivers/new-driver/busId').once('value')).val(), 'bus04');
  await assertFails(admin.ref('drivers/invalid-driver').set({name: 'Invalid', busId: 'missing-bus', active: true}));
  await assertFails(db('fake-admin', {admin: 'true'}).ref('drivers/fake').set({name: 'Fake', busId: 'bus04'}));
});
test('Driver reassignment and bus deactivation are blocked while a trip is open', async () => {
  await acquire(db('alice'));
  const admin = db('admin', { admin: true });
  await assertFails(admin.ref('drivers/alice/busId').set('bus05'));
  await assertFails(admin.ref('buses/bus04/active').set(false));
});
