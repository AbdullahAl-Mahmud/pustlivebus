import {createServer} from 'node:http';
import {readFile, stat, mkdir} from 'node:fs/promises';
import {resolve, extname, sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {chromium} from '@playwright/test';

const root = fileURLToPath(new URL('../../build/driver-preview/', import.meta.url));
const screenshots = fileURLToPath(new URL('./screenshots/', import.meta.url));
const mime = {'.js':'application/javascript', '.json':'application/json', '.wasm':'application/wasm', '.html':'text/html', '.ttf':'font/ttf', '.png':'image/png'};
await mkdir(screenshots, {recursive:true});
const server = createServer(async (request, response) => {
  try {
    const name = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname);
    let file = resolve(root, `.${name}`);
    if (file !== resolve(root) && !file.startsWith(resolve(root) + sep)) {response.writeHead(403).end(); return;}
    if ((await stat(file)).isDirectory()) file = resolve(file, 'index.html');
    response.writeHead(200, {'Content-Type':mime[extname(file)] || 'application/octet-stream'}).end(await readFile(file));
  } catch {response.writeHead(404).end();}
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
let browser;
try {
  browser = await chromium.launch({headless:true, executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
  const context = await browser.newContext({viewport:{width:390, height:844}});
  await context.route(/firebasedatabase\.app|firebaseio\.com/, route => route.abort());
  await context.routeWebSocket(/firebasedatabase\.app|firebaseio\.com/, socket => socket.close());
  const page = await context.newPage();
  const errors = [], tileResponses = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('response', response => {if (response.url().includes('tile.openstreetmap.org')) tileResponses.push(response.status());});
  await page.goto(`http://127.0.0.1:${server.address().port}`, {waitUntil:'networkidle'});
  await page.waitForSelector('flt-glass-pane', {state:'attached', timeout:60000});
  const semantics = page.locator('flt-semantics-placeholder');
  if (await semantics.count()) await semantics.evaluate(element => element.click());
  await page.getByRole('button', {name:'Map দেখুন', exact:true}).waitFor();
  assert.equal(await page.getByRole('button', {name:/GPS auto-follow/}).count(), 0);
  await page.getByRole('button', {name:'Map দেখুন', exact:true}).click();
  await page.getByRole('button', {name:/GPS auto-follow/}).waitFor();
  await page.screenshot({path:resolve(screenshots, 'driver-map-mobile.png')});
  await page.getByRole('button', {name:'Back', exact:true}).click();
  await page.getByRole('button', {name:'Map দেখুন', exact:true}).waitFor();
  await page.waitForTimeout(500);
  let tree = await page.locator('body').ariaSnapshot();
  assert.match(tree, /Demo GPS preview/);
  assert.match(tree, /পরের stop:/);
  assert.match(tree, /সম্ভাব্য arrival:/);
  await page.mouse.move(380, 30);
  await page.screenshot({path:resolve(screenshots, 'driver-mobile.png')});
  await page.mouse.move(190, 700);
  await page.mouse.wheel(0, 650);
  await page.waitForTimeout(400);
  tree = await page.locator('body').ariaSnapshot();
  assert.match(tree, /Stop ও আনুমানিক সময়/);
  await page.screenshot({path:resolve(screenshots, 'driver-stops-mobile.png')});
  await page.setViewportSize({width:1280, height:1100});
  await page.mouse.wheel(0, -1500);
  await page.waitForTimeout(400);
  await page.screenshot({path:resolve(screenshots, 'driver-desktop.png')});
  assert.deepEqual(errors, []);
  console.log(JSON.stringify({driverPanel:'passed', pageErrors:errors.length, tileResponses:tileResponses.length,
    successfulTiles:tileResponses.filter(status => status===200).length, screenshots:'driver-mobile / driver-stops-mobile / driver-desktop'}));
} finally {await browser?.close(); await new Promise(resolve => server.close(resolve));}
