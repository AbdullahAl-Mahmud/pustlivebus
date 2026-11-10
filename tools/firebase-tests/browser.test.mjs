import { createServer } from 'node:http';
import { readFile, stat, mkdir } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium, expect } from '@playwright/test';

const root = resolve(fileURLToPath(new URL('../../build/web/', import.meta.url)));
const screenshots = fileURLToPath(new URL('./screenshots/', import.meta.url));
await mkdir(screenshots, { recursive: true });
const types = { '.html': 'text/html', '.js': 'application/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.ttf': 'font/ttf', '.png': 'image/png' };
const server = createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://127.0.0.1').pathname);
    let file = resolve(root, `.${pathname}`);
    if (file !== root && !file.startsWith(root.endsWith(sep) ? root : root + sep)) { res.writeHead(403).end(); return; }
    if ((await stat(file)).isDirectory()) file = resolve(file, 'index.html');
    const bytes = await readFile(file);
    res.writeHead(200, { 'Content-Type': types[extname(file)] ?? 'application/octet-stream' }); res.end(bytes);
  } catch (_) { res.writeHead(404).end(); }
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
let browser, page;
try {
  browser = await chromium.launch({ headless: true, executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe' });
  const context = await browser.newContext({ viewport: { width: 390, height: 844 },
    permissions: ['geolocation'], geolocation: {latitude: 24.0144204, longitude: 89.2792439, accuracy: 15} });
  // Verify the offline app without reading or writing any real bus data.
  await context.route(/firebasedatabase\.app|firebaseio\.com/, (route) => route.abort());
  await context.routeWebSocket(/firebasedatabase\.app|firebaseio\.com/, (socket) => socket.close());
  page = await context.newPage();
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  const appUrl = process.env.PUST_LIVE_URL || `http://127.0.0.1:${server.address().port}`;
  await page.goto(appUrl, { waitUntil: 'networkidle' });
  await page.waitForSelector('flt-glass-pane', { timeout: 60000, state: 'attached' });
  const enableSemantics = async () => {
    const placeholder = page.locator('flt-semantics-placeholder');
    if (await placeholder.count()) await placeholder.evaluate((el) => el.click());
  };
  await enableSemantics();
  await page.screenshot({ path: resolve(screenshots, 'welcome-mobile.png') });
  await page.setViewportSize({width: 1440, height: 1000});
  await page.screenshot({path: resolve(screenshots, 'welcome-desktop.png')});
  await page.setViewportSize({width: 390, height: 844});
  await page.getByRole('button', { name: 'I am a Student', exact: true }).click({ timeout: 30000 });
  await expect(page.getByText(/Included offline timetable · Reference copy/)).toBeVisible();
  await page.screenshot({ path: resolve(screenshots, 'buses-mobile.png') });
  await page.getByRole('group', {name: /বাস-৪ : পদ্মা/}).first().click();
  const arrivalCard = page.getByRole('group', {name: /আমার স্টপে কখন আসবে/});
  await expect(arrivalCard).toBeVisible();
  await page.getByRole('button', {name: 'আমার অবস্থান ব্যবহার করুন', exact: true}).click();
  await expect(arrivalCard).toHaveAccessibleName(/আপনি → নির্বাচিত স্টপ:/);
  await page.screenshot({path: resolve(screenshots, 'arrival-mobile.png')});
  await page.getByRole('button', {name: 'Back', exact: true}).click();
  await page.getByRole('tab', { name: /Routes/ }).click();
  await expect(page.getByText('Fixed Routes', { exact: true })).toBeVisible();
  await page.screenshot({ path: resolve(screenshots, 'routes-mobile.png') });
  await page.getByRole('tab', { name: /Offline/ }).click();
  await page.screenshot({ path: resolve(screenshots, 'offline-mobile.png') });
  await context.setOffline(true);
  await page.getByRole('tab', { name: /Buses/ }).click();
  await page.getByRole('tab', { name: /Routes/ }).click();
  await expect(page.getByText('Fixed Routes', { exact: true })).toBeVisible();
  await context.setOffline(false);
  await page.evaluate(() => navigator.serviceWorker.ready);
  await context.setOffline(true);
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForSelector('flt-glass-pane', { state: 'attached' });
  await enableSemantics();
  await page.getByRole('button', { name: 'I am a Student', exact: true }).click();
  await expect(page.getByText(/Included offline timetable · Reference copy/)).toBeVisible();
  await page.screenshot({ path: resolve(screenshots, 'offline-reopened-mobile.png') });
  await page.getByRole('tab', { name: /Routes/ }).click();
  await context.setOffline(false);
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.screenshot({ path: resolve(screenshots, 'routes-desktop.png') });
  await page.getByRole('tab', {name: /Offline/}).click();
  await page.getByRole('switch', {name: 'Dark mode', exact: true}).click();
  await page.screenshot({path: resolve(screenshots, 'theme-dark-desktop.png')});
  await page.getByRole('button', {name: 'Back', exact: true}).click();
  await page.getByRole('button', {name: 'I am a Student', exact: true}).waitFor();
  await page.mouse.move(1400, 950);
  await page.waitForTimeout(800);
  await page.screenshot({path: resolve(screenshots, 'welcome-dark-desktop.png')});
  if (errors.length) throw new Error(errors.join('\n'));
  console.log('Chrome navigation, student geolocation, arrival planning and offline reopening checks passed. Screenshots saved.');
} catch (error) {
  if (page) {
    await page.screenshot({path: resolve(screenshots, 'failure.png')});
    console.log((await page.locator('body').ariaSnapshot()).slice(0, 5000));
  }
  throw error;
} finally {
  await browser?.close();
  await new Promise((resolve) => server.close(resolve));
}
