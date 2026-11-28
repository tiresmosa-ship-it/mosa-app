const CACHE_NAME = "mosa-system-shell-v75";
const APP_SHELL = [
  "./",
  "./index.html",
  "./offline.html",
  "./mecanico.html",
  "./admin.html",
  "./superadmin.html",
  "./cliente.html",
  "./cliente-operativo.html",
  "./cliente-gerencia.html",
  "./js/supabase.js",
  "./js/ui-components.js",
  "./manifest.json",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/icon-192-maskable.png",
  "./icons/icon-512-maskable.png",
  "./icons/apple-touch-icon.png"
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
  const req = event.request;
  let url;
  try { url = new URL(req.url); } catch (e) { return; }

  // Nunca cachear ni interceptar llamadas a Supabase (API, auth, storage,
  // realtime): siempre red. Se deja pasar el request sin respondWith.
  if (url.hostname === "supabase.co" || url.hostname.endsWith(".supabase.co")) return;

  if (req.method !== "GET" || (url.protocol !== "http:" && url.protocol !== "https:")) return;

  // Estrategia: cache-first con actualizacion en segundo plano (stale-while-revalidate).
  // Si no hay red ni cache: en navegaciones se muestra offline.html.
  event.respondWith(
    caches.open(CACHE_NAME).then(async (cache) => {
      const cached = await cache.match(req);
      const networkFetch = fetch(req)
        .then((response) => {
          if (response && response.status === 200) cache.put(req, response.clone());
          return response;
        })
        .catch(async () => {
          if (cached) return cached;
          if (req.mode === "navigate") {
            const offline = await cache.match("./offline.html");
            if (offline) return offline;
          }
          return new Response("Sin conexiÃ³n", { status: 503, statusText: "Offline", headers: { "Content-Type": "text/plain; charset=utf-8" } });
        });
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
