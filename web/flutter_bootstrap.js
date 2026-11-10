{{flutter_js}}
{{flutter_build_config}}

// Keep the rendering engine alongside the app instead of loading it from a CDN.
_flutter.loader.load({config: {canvasKitBaseUrl: 'canvaskit/'}});

// Release web builds cache their app shell for reopening offline after one visit.
// Development builds continue to use the live Flutter development server.
if ('serviceWorker' in navigator && _flutter.buildConfig.builds.some((b) => b.compileTarget === 'dart2js')) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register(new URL('offline_service_worker.js', document.baseURI))
      .catch((error) => console.info('Offline app shell not installed:', error.message));
  });
}
