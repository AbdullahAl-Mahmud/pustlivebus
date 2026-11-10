// Owner-only deployment. Default is a read-only plan. Changes rules, not data.
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const auth = require('firebase-tools/lib/auth');
const scopes = require('firebase-tools/lib/scopes');

const canonical = (value) => value && typeof value === 'object'
  ? Array.isArray(value) ? value.map(canonical) : Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]))
  : value;
const digest = (value) => crypto.createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');

async function main() {
  const args = process.argv.slice(2);
  const expectedArg = args.find((arg) => arg.startsWith('--expected='));
  if (args.some((arg) => arg !== '--apply' && arg !== expectedArg) || (args.includes('--apply') && !expectedArg)) {
    throw new Error('Usage: node deploy-database-rules.cjs [--expected=BACKUP_FILE] [--apply]');
  }
  if (process.env.FIREBASE_DATABASE_EMULATOR_HOST) throw new Error('Refusing a production deployment with emulator environment set.');
  const proposed = JSON.parse(await fs.readFile(path.resolve('database.rules.json'), 'utf8'));
  const account = auth.getProjectDefaultAccount(process.cwd());
  if (!account?.tokens?.refresh_token) throw new Error('Firebase project-owner login is required.');
  const token = await auth.getAccessToken(account.tokens.refresh_token,
    [scopes.CLOUD_PLATFORM, scopes.FIREBASE_PLATFORM, scopes.USERINFO_EMAIL]);
  const endpoint = 'https://pustlivebus-default-rtdb.asia-southeast1.firebasedatabase.app/.settings/rules.json';
  const headers = {Authorization: `Bearer ${token.access_token}`};
  async function readRules() {
    const response = await fetch(endpoint, {headers: {...headers, 'X-Firebase-ETag': 'true'}, signal: AbortSignal.timeout(20000)});
    if (!response.ok) throw new Error(`Cannot read rules: HTTP ${response.status}`);
    return {rules: await response.json(), etag: response.headers.get('etag')};
  }
  const current = await readRules();
  if (expectedArg) {
    const expected = JSON.parse(await fs.readFile(expectedArg.slice('--expected='.length), 'utf8'));
    if (digest(current.rules) !== digest(expected)) throw new Error('Deployed rules changed since review. Read and review the new rules before applying.');
  }
  const stamp = new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-');
  const backup = path.resolve('artifacts', `firebase-rules-before-deploy-${stamp}.json`);
  await fs.mkdir(path.dirname(backup), {recursive: true});
  await fs.writeFile(backup, JSON.stringify(current.rules, null, 2) + '\n', {flag: 'wx'});
  const plan = {
    project: 'pustlivebus', backup, mode: args.includes('--apply') ? 'apply' : 'read-only-plan',
    currentSha256: digest(current.rules), proposedSha256: digest(proposed),
    changedNodes: Object.keys(proposed.rules).filter((key) => digest(proposed.rules[key]) !== digest(current.rules.rules?.[key] ?? null)),
  };
  if (args.includes('--apply')) {
    const result = await fetch(endpoint, {
      method: 'PUT', headers: {...headers, 'Content-Type': 'application/json', ...(current.etag ? {'If-Match': current.etag} : {})},
      body: JSON.stringify(proposed), signal: AbortSignal.timeout(20000),
    });
    if (!result.ok) throw new Error(`Rules deployment failed: HTTP ${result.status}. Read deployed rules before retrying.`);
    const verified = await readRules();
    if (digest(verified.rules) !== digest(proposed)) throw new Error('Deployed rules verification did not match. Inspect the current rules.');
    plan.verified = true;
    await fs.writeFile(path.resolve('artifacts', `firebase-rules-deployment-${stamp}.json`), JSON.stringify(plan, null, 2) + '\n', {flag: 'wx'});
  }
  console.log(JSON.stringify(plan, null, 2));
}
const timeout = setTimeout(() => {console.error('Rules operation timed out. Read the deployed rules before retrying.'); process.exit(1);}, 90000);
main().catch((e) => {console.error(e.name === 'FirebaseError' ? 'Firebase owner login failed.' : e.message); process.exitCode = 1;})
  .finally(() => clearTimeout(timeout));
