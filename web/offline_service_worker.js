// Bump this version whenever publishing a changed app shell.
const CACHE = 'pust-livebus-shell-v7';
const CORE = [
  './', 'index.html', 'flutter_bootstrap.js', 'main.dart.js', 'manifest.json',
  'assets/AssetManifest.bin', 'assets/AssetManifest.bin.json', 'assets/FontManifest.json',
  'assets/assets/data/offline_catalog.json', 'assets/assets/fonts/NotoSansBengali.ttf',
  'assets/assets/fonts/OFL.txt', 'assets/fonts/MaterialIcons-Regular.otf',
  'assets/assets/branding/pust-mobility-transparent.png',
  'assets/assets/branding/pust-mobility-white.png', 'icons/pust-mobility.png', 'favicon.png',
  'assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
  'assets/shaders/ink_sparkle.frag', 'assets/shaders/stretch_effect.frag',
  'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.js', 'canvaskit/chromium/canvaskit.wasm',
];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(CORE)));
});
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    // Only remove caches owned by this app.
    const keys = await caches.keys();
    await Promise.all(keys.filter((key) => key.startsWith('pust-livebus-shell-') && key !== CACHE).map((key) => caches.delete(key)));
    await self.clients.claim();
  })());
});
self.addEventListener('fetch', (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin || url.pathname.endsWith('offline_service_worker.js')) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const cached = await cache.match(request);
    if (cached) return cached;
    try {
      const response = await fetch(request);
      if (response.ok) await cache.put(request, response.clone());
      return response;
    } catch (error) {
      const saved = await cache.match(request);
      if (saved) return saved;
      if (request.mode === 'navigate') {
        const index = await cache.match(new URL('index.html', self.registration.scope));
        if (index) return index;
      }
      throw error;
    }
  })());
});
