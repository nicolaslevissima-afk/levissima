// LEVÍSSIMA · função "rastreio": recebe a posição do celular do motorista durante a viagem, direto do GPS
// nativo do app Android (plugin de localização em segundo plano), mesmo com a tela desligada ou o app fechado.
//
// POST /functions/v1/rastreio?c=<id da carga>&t=<chave da viagem>
// Corpo (JSON, mandado pelo plugin): { latitude, longitude, accuracy, time, speed, bearing, source }
//
// Segurança: ao sair para a entrega, o app do motorista cria uma chave aleatória só daquela viagem e grava no
// banco apenas o hash dela (rastreio/<carga>.chaveHash). Aqui a função confere a chave e só aceita enquanto a
// viagem está ativa. Publicada SEM verificação de JWT (o login do motorista vence em 1 hora e o celular
// continua mandando em segundo plano); quem não tem a chave da viagem não grava nada.
import { createClient } from 'npm:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICO = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const admin = createClient(URL_SB, SERVICO, { auth: { persistSession: false, autoRefreshToken: false } });

const MAX_PONTOS = 3000;          // trajeto guardado por viagem
const INTERVALO_MIN_MS = 45_000;  // grava no máximo 1 ponto a cada 45 s…
const DISTANCIA_MIN_M = 150;      // …a não ser que o caminhão tenha andado 150 m

function resposta(corpo: unknown, status = 200) {
  return new Response(JSON.stringify(corpo), { status, headers: { 'Content-Type': 'application/json' } });
}
async function sha256Hex(texto: string) {
  const h = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(texto));
  return Array.from(new Uint8Array(h)).map((b) => b.toString(16).padStart(2, '0')).join('');
}
function distanciaM(a: { lat: number; lng: number }, b: { lat: number; lng: number }) {
  const R = 6371000, k = Math.PI / 180;
  const dLat = (b.lat - a.lat) * k, dLng = (b.lng - a.lng) * k;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * k) * Math.cos(b.lat * k) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return resposta({ erro: 'metodo' }, 405);
  const url = new URL(req.url);
  const carga = url.searchParams.get('c') ?? '';
  const chave = url.searchParams.get('t') ?? '';
  if (!/^[A-Za-z0-9_-]{1,80}$/.test(carga) || !/^[a-f0-9]{32,128}$/.test(chave)) return resposta({ erro: 'dados' }, 400);

  let corpo: Record<string, unknown>;
  try { corpo = await req.json(); } catch { return resposta({ erro: 'dados' }, 400); }
  const lat = Number(corpo.latitude), lng = Number(corpo.longitude);
  if (!isFinite(lat) || !isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return resposta({ erro: 'dados' }, 400);
  const quando = Number(corpo.time) > 0 ? new Date(Number(corpo.time)) : new Date();
  const ponto = {
    lat: Math.round(lat * 1e6) / 1e6,
    lng: Math.round(lng * 1e6) / 1e6,
    acc: Math.round(Number(corpo.accuracy) || 0),
    em: (isNaN(quando.getTime()) ? new Date() : quando).toISOString(),
    ...(Number(corpo.speed) >= 0 ? { vel: Math.round(Number(corpo.speed) * 3.6) } : {}), // km/h
  };

  const { data: linha, error } = await admin.from('docs').select('data').eq('colecao', 'rastreio').eq('id', carga).maybeSingle();
  if (error) return resposta({ erro: 'interno' }, 500);
  const doc = (linha?.data ?? null) as Record<string, unknown> | null;
  if (!doc || !doc.chaveHash || doc.chaveHash !== await sha256Hex(chave)) return resposta({ erro: 'chave' }, 403);
  if (doc.ativo !== true) return resposta({ erro: 'encerrada' }, 410); // viagem encerrada: o app para de mandar

  const ultima = doc.ultima as { lat: number; lng: number; em: string } | undefined;
  if (ultima && ultima.em) {
    const dt = Date.parse(ponto.em) - Date.parse(ultima.em);
    if (dt < 0) return resposta({ ok: true, ignorado: 'antigo' });
    if (dt < INTERVALO_MIN_MS && distanciaM(ultima, ponto) < DISTANCIA_MIN_M) return resposta({ ok: true, ignorado: 'perto' });
  }
  const pontos = Array.isArray(doc.pontos) ? (doc.pontos as unknown[]) : [];
  const novo = { ...doc, ultima: ponto, pontos: pontos.concat([ponto]).slice(-MAX_PONTOS), origemUltima: 'app-nativo' };
  const { error: e2 } = await admin.from('docs').update({ data: novo, atualizado_em: new Date().toISOString() }).eq('colecao', 'rastreio').eq('id', carga);
  if (e2) return resposta({ erro: 'interno' }, 500);
  return resposta({ ok: true });
});
