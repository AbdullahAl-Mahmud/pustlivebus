// Read-only diagnosis. Back up deployed rules; never print credentials/user data.
const fs = require('node:fs/promises');
const path = require('node:path');
const auth = require('firebase-tools/lib/auth');
const scopes = require('firebase-tools/lib/scopes');

async function main() {
  const account = auth.getProjectDefaultAccount(process.cwd());
  if (!account?.tokens?.refresh_token) throw new Error('Firebase owner login is required.');
  const token = await auth.getAccessToken(account.tokens.refresh_token,
    [scopes.CLOUD_PLATFORM, scopes.FIREBASE_PLATFORM, scopes.USERINFO_EMAIL]);
  const base = 'https://pustlivebus-default-rtdb.asia-southeast1.firebasedatabase.app';
  const headers = {Authorization: `Bearer ${token.access_token}`};
  const response = await fetch(`${base}/.settings/rules.json`, {
    headers: {...headers, 'X-Firebase-ETag': 'true'}, signal: AbortSignal.timeout(20000),
  });
  if (!response.ok) throw new Error(`Cannot read deployed rules: HTTP ${response.status}`);
  const rules = await response.json();
  const stamp = new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-');
  const backup = path.resolve('artifacts', `firebase-rules-backup-${stamp}.json`);
  await fs.mkdir(path.dirname(backup), {recursive: true});
  await fs.writeFile(backup, JSON.stringify(rules, null, 2) + '\n', {flag: 'wx'});
  const counts = {};
  for (const node of ['buses', 'drivers', 'activeTrips']) {
    const result = await fetch(`${base}/${node}.json?shallow=true`, {headers, signal: AbortSignal.timeout(20000)});
    if (!result.ok) throw new Error(`Cannot inspect ${node}: HTTP ${result.status}`);
    const values = await result.json();
    counts[node] = values && typeof values === 'object' ? Object.keys(values).length : 0;
  }
  console.log(JSON.stringify({backup, counts, rootRead: rules.rules?.['.read'], rootWrite: rules.rules?.['.write'],
    driverRules: rules.rules?.drivers ?? null, activeTripRules: rules.rules?.activeTrips ?? null}, null, 2));
}
const timeout = setTimeout(() => {console.error('Read-only diagnosis timed out.'); process.exit(1);}, 90000);
main().catch((e) => {console.error(e.name === 'FirebaseError' ? 'Firebase owner login failed.' : e.message); process.exitCode = 1;})
  .finally(() => clearTimeout(timeout));
