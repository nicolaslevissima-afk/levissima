// LEVÍSSIMA · função "ler-carga" (pedido de 23/10/2026): lançar a carga falando. O app transcreve o áudio (o
// reconhecimento de voz do celular) e manda o texto aqui; a IA (Claude, da Anthropic) devolve a carga montada com os
// produtos do catálogo. O app mostra a carga no formulário para a pessoa conferir antes de salvar.
// Só para quem está logado no escritório ou na força de vendas. A chave da IA fica no segredo ANTHROPIC_API_KEY do
// projeto (Supabase › Edge Functions › Secrets) e nunca vai para o app. Sem a chave, responde { erro: 'sem_chave' } e
// o app monta a carga com a leitura simples que roda no próprio celular.
//
// POST { texto, hoje: 'AAAA-MM-DD', produtos: [{ id, nome, unidade }], clientes: [nome], motoristas: [nome] }
//   -> { clientes: [{ cliente, destino, itens: [{ produtoId, quantidade }] }], motorista, data, hora, obs, duvidas: [] }
import { createClient } from 'npm:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICO = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const CHAVE_IA = Deno.env.get('ANTHROPIC_API_KEY') ?? '';
const MODELO = Deno.env.get('LEVISSIMA_MODELO_IA') ?? 'claude-sonnet-5-5';
const LIMITE_HORA = 60;

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

async function quemChamou(req: Request): Promise<{ ref: string; papel: string } | null> {
  const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!token || token.split('.').length !== 3) return null;
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) return null;
  const m = (data.user.app_metadata || {}) as Record<string, unknown>;
  const papel = String(m.papel || '');
  return ['mestre', 'equipe', 'representante'].includes(papel) ? { ref: String(m.ref || data.user.id), papel } : null;
}
function jsonDoTexto(t: string): Record<string, unknown> | null {
  const ini = t.indexOf('{'), fim = t.lastIndexOf('}');
  if (ini < 0 || fim <= ini) return null;
  try { return JSON.parse(t.slice(ini, fim + 1)); } catch { return null; }
}
const curto = (v: unknown, n: number) => String(v ?? '').replace(/\s+/g, ' ').trim().slice(0, n);

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return erro('metodo', 405);
  try {
    const quem = await quemChamou(req);
    if (!quem) return erro('login', 401);
    if (!CHAVE_IA) return erro('sem_chave', 503);
    let corpo: Record<string, unknown>;
    try { corpo = await req.json(); } catch { return erro('dados', 400); }
    const texto = curto(corpo.texto, 2000);
    const hoje = /^\d{4}-\d{2}-\d{2}$/.test(String(corpo.hoje)) ? String(corpo.hoje) : new Date().toISOString().slice(0, 10);
    const produtos = (Array.isArray(corpo.produtos) ? corpo.produtos : []).slice(0, 200).map((p: Record<string, unknown>) => ({ id: curto(p.id, 80), nome: curto(p.nome, 80), unidade: curto(p.unidade, 20) })).filter((p) => p.id && p.nome);
    const clientes = (Array.isArray(corpo.clientes) ? corpo.clientes : []).slice(0, 600).map((c) => curto(c, 80)).filter(Boolean);
    const motoristas = (Array.isArray(corpo.motoristas) ? corpo.motoristas : []).slice(0, 200).map((c) => curto(c, 60)).filter(Boolean);
    if (!texto || !produtos.length) return erro('dados', 400);
    const agora = Date.now(), lista = (usos.get(quem.ref) || []).filter((t) => agora - t < 3600000);
    if (lista.length >= LIMITE_HORA) return erro('limite', 429);
    lista.push(agora); usos.set(quem.ref, lista);

    const sistema = 'Você monta cargas de uma fábrica de água mineral (Levíssima, no Brasil) a partir do que a pessoa falou ' +
      '(texto vindo do reconhecimento de voz, pode ter erros de transcrição). Use SOMENTE os produtos do catálogo (pelo id). ' +
      'Marcas sem nome falado = Levíssima. "510", "quinhentos e dez", "meio litro" = 510ml; "1,5", "um e meio", "litro e meio" = 1,5L; ' +
      '"sem gás" = natural; "com gás", "gaseificada" = com gás. Quantidade em fardos (ou na unidade do produto); se falar em paletes, ' +
      'deixe a quantidade em paletes e marque "emPaletes": true no item. Para cliente e motorista, prefira o nome igual ao da lista ' +
      'quando parecer o mesmo. Datas relativas ("amanhã", "sexta") contam a partir de hoje = ' + hoje + '. Responda SOMENTE com um ' +
      'objeto JSON: {"clientes":[{"cliente":"nome","destino":"cidade se falou","itens":[{"produtoId":"id do catálogo","quantidade":0,"emPaletes":false}]}],' +
      '"motorista":"nome ou vazio","data":"AAAA-MM-DD ou vazio","hora":"HH:MM ou vazio","obs":"outra informação útil ou vazio",' +
      '"duvidas":["o que não deu para entender"]}.';
    const usuario = 'Catálogo de produtos (id = nome, unidade):\n' + produtos.map((p) => p.id + ' = ' + p.nome + (p.unidade ? ' (' + p.unidade + ')' : '')).join('\n') +
      '\n\nClientes já atendidos: ' + clientes.join('; ') + '\n\nMotoristas: ' + motoristas.join('; ') + '\n\nO que a pessoa falou:\n"' + texto + '"';
    const r = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'x-api-key': CHAVE_IA, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
      body: JSON.stringify({ model: MODELO, max_tokens: 1200, system: sistema, messages: [{ role: 'user', content: usuario }] }),
    });
    const j = await r.json().catch(() => ({})) as { content?: { type: string; text?: string }[]; error?: { message?: string } };
    if (!r.ok) { console.error('ler-carga: IA respondeu', r.status, j.error && j.error.message); return erro(r.status === 401 ? 'sem_chave' : 'ia', 502); }
    const d = jsonDoTexto((j.content || []).filter((b) => b.type === 'text' && b.text).map((b) => b.text).join('\n'));
    if (!d) return erro('sem_resposta', 502);
    const ids = new Set(produtos.map((p) => p.id));
    const cls = (Array.isArray(d.clientes) ? d.clientes : []).slice(0, 12).map((c: Record<string, unknown>) => ({
      cliente: curto(c.cliente, 80), destino: curto(c.destino, 60),
      itens: (Array.isArray(c.itens) ? c.itens : []).slice(0, 40).map((it: Record<string, unknown>) => ({ produtoId: curto(it.produtoId, 80), quantidade: Math.max(0, Math.round(Number(it.quantidade) || 0)), emPaletes: it.emPaletes === true }))
        .filter((it) => ids.has(it.produtoId) && it.quantidade > 0),
    })).filter((c) => c.cliente || c.itens.length);
    return resposta({
      clientes: cls, motorista: curto(d.motorista, 60),
      data: /^\d{4}-\d{2}-\d{2}$/.test(String(d.data)) ? String(d.data) : '', hora: /^\d{2}:\d{2}$/.test(String(d.hora)) ? String(d.hora) : '',
      obs: curto(d.obs, 300), duvidas: (Array.isArray(d.duvidas) ? d.duvidas : []).slice(0, 5).map((x) => curto(x, 160)),
    });
  } catch (e) {
    console.error('ler-carga', e);
    return erro('interno', 500);
  }
});
