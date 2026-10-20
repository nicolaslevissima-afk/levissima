// LEVÍSSIMA · função "identificar-peca" (pedido de 19/10/2026): no pedido de compra, quem não sabe o nome da peça tira
// uma foto e a IA (Claude, da Anthropic) devolve o nome, uma descrição curta e termos para procurar e comprar.
// Só para quem está logado no escritório (senha mestre, diretoria e equipe). A chave da IA fica no segredo
// ANTHROPIC_API_KEY do projeto (Supabase › Edge Functions › Secrets) e nunca vai para o app. Sem a chave, responde
// { erro: 'sem_chave' } e o app avisa que a IA ainda não está ligada.
//
// POST { imagem: <base64>, tipo: 'image/jpeg' | 'image/png' | 'image/webp', contexto?: 'onde vai aplicar' }
//   -> { nome, descricao, termos: [...], confianca: 'alta' | 'media' | 'baixa' }
import { createClient } from 'npm:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICO = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const CHAVE_IA = Deno.env.get('ANTHROPIC_API_KEY') ?? '';
const MODELO = Deno.env.get('LEVISSIMA_MODELO_IA') ?? 'claude-sonnet-5-5';
const TIPOS = ['image/jpeg', 'image/png', 'image/webp'];
const LIMITE_HORA = 20; // fotos por hora por acesso

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
function resposta(corpo: unknown, status = 200) {
  return new Response(JSON.stringify(corpo), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
}
function erro(codigo: string, status: number) { return resposta({ erro: codigo }, status); }

const admin = createClient(URL_SB, SERVICO, { auth: { persistSession: false, autoRefreshToken: false } });
const usos = new Map<string, number[]>();

const SISTEMA = 'Você ajuda a equipe de compras de uma fábrica de água mineral (Levíssima, no Brasil) a descobrir o nome de peças e ' +
  'materiais a partir de uma foto: manutenção industrial, envase, elétrica, hidráulica, pneumática, rolamentos, correias, ' +
  'vedações, sensores, ferramentas e embalagens. Leia códigos, marcas e medidas visíveis na foto e, se ajudar, pesquise na ' +
  'internet. Responda SOMENTE com um objeto JSON, em português do Brasil, neste formato: ' +
  '{"nome": "nome comercial curto da peça, com medida, código ou modelo quando der para ver", ' +
  '"descricao": "uma frase dizendo o que é e para que serve", "termos": ["2 a 4 termos para procurar e comprar"], ' +
  '"confianca": "alta" | "media" | "baixa"}. Se não der para identificar com segurança, use "baixa" e diga no nome o que parece ser.';

async function quemChamou(req: Request): Promise<{ ref: string; papel: string } | null> {
  const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!token || token.split('.').length !== 3) return null;
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) return null;
  const m = (data.user.app_metadata || {}) as Record<string, unknown>;
  const papel = String(m.papel || '');
  return papel === 'mestre' || papel === 'equipe' ? { ref: String(m.ref || data.user.id), papel } : null;
}

function jsonDoTexto(t: string): Record<string, unknown> | null {
  const ini = t.indexOf('{'), fim = t.lastIndexOf('}');
  if (ini < 0 || fim <= ini) return null;
  try { return JSON.parse(t.slice(ini, fim + 1)); } catch { return null; }
}

async function perguntar(imagem: string, tipo: string, contexto: string, comBusca: boolean) {
  const corpo: Record<string, unknown> = {
    model: MODELO,
    max_tokens: 800,
    system: SISTEMA,
    messages: [{ role: 'user', content: [
      { type: 'image', source: { type: 'base64', media_type: tipo, data: imagem } },
      { type: 'text', text: 'Que peça ou material é este? ' + (contexto ? 'Vai ser aplicado em: ' + contexto + '. ' : '') + 'Responda só com o JSON.' },
    ] }],
  };
  if (comBusca) corpo.tools = [{ type: 'web_search_20250305', name: 'web_search', max_uses: 3 }];
  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'x-api-key': CHAVE_IA, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
    body: JSON.stringify(corpo),
  });
  const j = await r.json().catch(() => ({}));
  return { ok: r.ok, status: r.status, j: j as { content?: { type: string; text?: string }[]; error?: { message?: string } } };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return erro('metodo', 405);
  try {
    const quem = await quemChamou(req);
    if (!quem) return erro('login', 401);
    if (!CHAVE_IA) return erro('sem_chave', 503);
    let corpo: Record<string, unknown>;
    try { corpo = await req.json(); } catch { return erro('dados', 400); }
    const imagem = String(corpo.imagem || ''), tipo = String(corpo.tipo || 'image/jpeg');
    const contexto = String(corpo.contexto || '').replace(/\s+/g, ' ').trim().slice(0, 200);
    if (!imagem || imagem.length > 7_000_000 || !/^[A-Za-z0-9+/=]+$/.test(imagem.slice(0, 200)) || !TIPOS.includes(tipo)) return erro('dados', 400);
    const agora = Date.now(), lista = (usos.get(quem.ref) || []).filter((t) => agora - t < 3600000);
    if (lista.length >= LIMITE_HORA) return erro('limite', 429);
    lista.push(agora); usos.set(quem.ref, lista);

    let r = await perguntar(imagem, tipo, contexto, true);
    // sem a busca na internet liberada na conta da IA: pergunta de novo só com a foto
    if (!r.ok && r.status === 400 && /tool|web_search/i.test(String(r.j.error && r.j.error.message))) r = await perguntar(imagem, tipo, contexto, false);
    if (!r.ok) { console.error('identificar-peca: IA respondeu', r.status, r.j.error && r.j.error.message); return erro(r.status === 401 ? 'sem_chave' : 'ia', 502); }
    const texto = (r.j.content || []).filter((b) => b.type === 'text' && b.text).map((b) => b.text).join('\n');
    const d = jsonDoTexto(texto);
    if (!d || !d.nome) return erro('sem_resposta', 502);
    const conf = ['alta', 'media', 'baixa'].includes(String(d.confianca)) ? String(d.confianca) : 'baixa';
    return resposta({
      nome: String(d.nome).slice(0, 120),
      descricao: String(d.descricao || '').slice(0, 300),
      termos: Array.isArray(d.termos) ? d.termos.slice(0, 4).map((x) => String(x).slice(0, 80)) : [],
      confianca: conf === 'media' ? 'média' : conf,
    });
  } catch (e) {
    console.error('identificar-peca', e);
    return erro('interno', 500);
  }
});
