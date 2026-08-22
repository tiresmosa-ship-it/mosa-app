const CACHE_NAME = "mosa-tires-shell-v38";
const APP_SHELL = [
  "./",
  "./index.html",
  "./mecanico.html",
  "./admin.html",
  "./superadmin.html",
  "./cliente.html",
  "./cliente-operativo.html",
  "./cliente-gerencia.html",
  "./js/supabase.js",
  "./js/ui-components.js",
  "./manifest.json",
  "./icon-192.png",
  "./icon-512.png"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const url = event.request.url;

  // Nunca cachear ni interceptar llamadas a Supabase: siempre red.
  if (url.includes("supabase.co")) {
    return; // deja pasar el request tal cual (sin respondWith)
  }

  if (event.request.method !== "GET") return;

  // Estrategia: cache-first con actualizacion en segundo plano (stale-while-revalidate)
  event.respondWith(
    caches.open(CACHE_NAME).then(async (cache) => {
      const cached = await cache.match(event.request);
      const networkFetch = fetch(event.request)
        .then((response) => {
          if (response && response.status === 200) cache.put(event.request, response.clone());
          return response;
        })
        .catch(() => cached);
      return cached || networkFetch;
    })
  );
});

// Background Sync (best-effort): el SW no tiene acceso a localStorage, asi
// que no puede sincronizar la cola offline el mismo. Solo puede avisarle a
// las pestanas abiertas para que reintenten. No soportado en Safari/iOS.
self.addEventListener("sync", (event) => {
  if (event.tag === "mosa-sync") {
    event.waitUntil(self.clients.matchAll().then(clients => clients.forEach(c => c.postMessage({ type: "mosa-sync" }))));
  }
});
