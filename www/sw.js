// LEVÍSSIMA · guarda a tela do app no aparelho para abrir rápido e aguentar internet fraca.
// Os dados (Supabase/Firebase) sempre vêm da internet; aqui ficam só os arquivos do próprio app.
const CACHE = 'levissima-v3';
const ARQUIVOS = ['./', './index.html', './manifest.webmanifest', './icons/icon-192.png', './icons/icon-512.png', './icons/apple-touch-icon.png',
  './marca/levissima-horizontal.svg', './marca/levissima-horizontal-escuro.svg',
  './modulos/ponte.js', './modulos/manutencao.html', './modulos/empilhadeiras.html', './modulos/uniformes.html', './modulos/garrafoes.html'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ARQUIVOS)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
// Primeiro a internet (para sempre pegar a versão nova); sem internet, a cópia guardada.
self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;
  e.respondWith(
    fetch(req).then((res) => {
      if (res.ok) { const copia = res.clone(); caches.open(CACHE).then((c) => c.put(req, copia)); }
      return res;
    }).catch(() => caches.match(req).then((r) => r || caches.match('./index.html')))
  );
});
