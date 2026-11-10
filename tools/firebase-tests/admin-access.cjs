// Owner-only setup. Uses the existing Firebase CLI login; never prints tokens.
const auth = require('firebase-tools/lib/auth');
const scopes = require('firebase-tools/lib/scopes');

async function main() {
  const args = process.argv.slice(2);
  const uidArg = args.find((arg) => arg.startsWith('--uid='));
  if (!uidArg || args.some((arg) => arg !== uidArg && arg !== '--apply')) {
    throw new Error('Usage: node admin-access.cjs --uid=FIREBASE_USER_UID [--apply]');
  }
  const uid = uidArg.slice(6);
  if (!uid || uid.length > 128 || /[\s/]/.test(uid)) {
    throw new Error('Invalid Firebase user UID.');
  }
  if (process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error('This owner setup targets pustlivebus, not the emulator.');
  }
  const project = 'pustlivebus';
  const account = auth.getProjectDefaultAccount(process.cwd());
  if (!account?.tokens?.refresh_token) {
    throw new Error('Sign in to Firebase CLI as the pustlivebus project owner first.');
  }
  const token = await auth.getAccessToken(account.tokens.refresh_token, [
    scopes.CLOUD_PLATFORM,
    scopes.FIREBASE_PLATFORM,
    scopes.USERINFO_EMAIL,
  ]);
  async function request(action, body) {
    const response = await fetch(
      `https://identitytoolkit.googleapis.com/v1/projects/${project}/accounts:${action}`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token.access_token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(15000),
      },
    );
    const result = await response.json();
    if (!response.ok) {
      throw new Error(`Firebase request failed (${response.status}): ${result.error?.status || 'unknown'}`);
    }
    return result;
  }
  async function lookup() {
    const result = await request('lookup', { localId: [uid] });
    const user = result.users?.find((row) => row.localId === uid);
    if (!user) throw new Error('That UID does not exist in pustlivebus Authentication.');
    if (user.disabled) throw new Error('This account is disabled. No permissions changed.');
    return user;
  }
  const user = await lookup();
  const claims = JSON.parse(user.customAttributes || '{}');
  if (args.includes('--apply') && claims.admin !== true) {
    await request('update', {
      localId: uid,
      customAttributes: JSON.stringify({ ...claims, admin: true }),
    });
  }
  const verified = args.includes('--apply') ? await lookup() : user;
  const admin = JSON.parse(verified.customAttributes || '{}').admin === true;
  console.log(JSON.stringify({ project, uid, admin, mode: args.includes('--apply') ? 'verified' : 'read-only' }));
  if (args.includes('--apply') && !admin) throw new Error('Administrator permission verification failed.');
}

const watchdog = setTimeout(() => {
  console.error('Setup timed out. Run without --apply to check current permission.');
  process.exit(1);
}, 45000);
main().catch((error) => {
  // Do not serialize SDK error objects, which can include authentication details.
  console.error(error.name === 'FirebaseError' ? 'Firebase CLI login failed. Sign in again as the project owner.' : error.message);
  process.exitCode = 1;
}).finally(() => clearTimeout(watchdog));
