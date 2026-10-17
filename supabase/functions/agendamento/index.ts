// LEVÍSSIMA · função "agendamento": agendamento on-line da linha dos retornáveis (garrafões 10L e 20L) pelo próprio
// cliente, com um link pessoal (agendar.html#t=<chave do cliente>).
//
// POST /functions/v1/agendamento   corpo JSON: { acao, t, ... }
//   horarios  { t }                     → nome do cliente, dias e horários LIVRES (sem nome de ninguém) e os agendamentos dele
//   agendar   { t, data, hora, obs }    → reserva o horário (confere de novo se ainda está livre)
//   confirmar { t, id }                 → o cliente confirma a ida (link da mensagem de 24 horas antes)
//   cancelar  { t, id }                 → o cliente cancela
//
// Segurança: cada cliente tem uma chave aleatória (agenda-online/cli-*.token), criada no app pela equipe. Sem a chave
// não se vê nem se grava nada; com a chave, só os horários livres e os agendamentos do próprio cliente. Publicada SEM
// verificação de JWT (o cliente não tem login); grava com a chave de serviço, só nas coleções da agenda.
import { createClient } from 'npm:@supabase/supabase-js@2';

const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', { auth: { persistSession: false, autoRefreshToken: false } });
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'content-type, apikey, authorization, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const PADRAO = { ativo: true, vagas: 2, antecedenciaHoras: 12, diasAFrente: 14, dias: [1, 2, 3, 4, 5, 6], de: '05:00', ate: '17:30', maxAtivos: 5 };
const HORAS: string[] = [];
for (let m = 4 * 60; m <= 18 * 60; m += 30) HORAS.push(String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(m % 60).padStart(2, '0'));
const DIAS = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];
type Doc = { id: string; data: Record<string, any> };

function resposta(corpo: unknown, status = 200) {
  return new Response(JSON.stringify(corpo), { status, headers: { ...CORS, 'Content-Type': 'application/json; charset=utf-8' } });
}
// Brasil (São Paulo) sem horário de verão: UTC−3
function agoraSP() { return new Date(Date.now() - 3 * 3600_000); }
function isoDe(d: Date) { return d.toISOString().slice(0, 10); }
function maisDias(iso: string, n: number) { const d = new Date(iso + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return isoDe(d); }
function minDe(h: string) { const p = String(h || '0:0').split(':'); return Number(p[0]) * 60 + Number(p[1]); }
function diaSemana(iso: string) { return new Date(iso + 'T12:00:00Z').getUTCDay(); } // 0 = domingo
function rotulo(iso: string, hoje: string) {
  const dm = iso.slice(8, 10) + '/' + iso.slice(5, 7);
  if (iso === hoje) return 'Hoje, ' + dm;
  if (iso === maisDias(hoje, 1)) return 'Amanhã, ' + dm;
  return DIAS[diaSemana(iso)] + ', ' + dm;
}
function novoId(n = 20) {
  const c = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789', r = crypto.getRandomValues(new Uint8Array(n));
  return Array.from(r).map((x) => c[x % c.length]).join('');
}

async function carregar(t: string) {
  if (!/^[A-Za-z0-9]{16,64}$/.test(t || '')) return null;
  const { data: cli } = await admin.from('docs').select('id,data').eq('colecao', 'agenda-online').eq('data->>token', t).limit(1);
  const c = (cli || [])[0] as Doc | undefined;
  if (!c || !c.id.startsWith('cli-') || c.data.ativo === false) return null;
  const hoje = isoDe(agoraSP());
  const [cfg, fixos, itens, dias] = await Promise.all([
    admin.from('docs').select('id,data').eq('colecao', 'agenda-online').eq('id', 'config').limit(1),
    admin.from('docs').select('id,data').eq('colecao', 'agenda-fixos'),
    admin.from('docs').select('id,data').eq('colecao', 'agenda-itens').gte('data->>data', hoje),
    admin.from('docs').select('id,data').eq('colecao', 'agenda-dias').gte('id', hoje),
  ]);
  const config = Object.assign({}, PADRAO, ((cfg.data || [])[0] as Doc | undefined)?.data || {});
  return { cli: c, config, fixos: (fixos.data || []) as Doc[], itens: (itens.data || []) as Doc[], dias: (dias.data || []) as Doc[], hoje };
}
// Quem está marcado no dia (igual ao app): fixos da semana menos os pulos + agendamentos do dia (sem os cancelados)
function entradas(iso: string, ctx: NonNullable<Awaited<ReturnType<typeof carregar>>>) {
  const fer = ctx.dias.find((d) => d.id === iso && d.data.feriado);
  const wd = ((diaSemana(iso) + 6) % 7) + 1, out: { hora: string; tipo: string }[] = [];
  if (fer) return { fer: true, out };
  for (const f of ctx.fixos) {
    const x = f.data;
    if (!(x.dias || []).includes(wd) || (x.desde && iso < x.desde) || (x.ate && iso > x.ate) || (x.pulos || []).includes(iso)) continue;
    out.push({ hora: x.hora, tipo: x.tipo || 'cliente' });
  }
  for (const it of ctx.itens) { const x = it.data; if (x.data === iso && !x.cancelado) out.push({ hora: x.hora, tipo: x.tipo || 'cliente' }); }
  return { fer: false, out };
}
function livres(iso: string, ctx: NonNullable<Awaited<ReturnType<typeof carregar>>>) {
  const cfg = ctx.config, ag = agoraSP(), limite = ag.getTime() + Number(cfg.antecedenciaHoras || 0) * 3600_000;
  if (!cfg.ativo) return { motivo: 'O agendamento on-line está fechado no momento.', horas: [] as string[] };
  const wd = ((diaSemana(iso) + 6) % 7) + 1;
  if (!(cfg.dias || []).includes(wd)) return { motivo: 'Sem atendimento neste dia.', horas: [] };
  const e = entradas(iso, ctx);
  if (e.fer) return { motivo: 'Fechado (feriado).', horas: [] };
  const horas = HORAS.filter((h) => {
    if (minDe(h) < minDe(cfg.de) || minDe(h) > minDe(cfg.ate)) return false;
    const quando = new Date(iso + 'T' + h + ':00Z').getTime(); // já em "hora de São Paulo"
    if (quando < limite) return false;
    const naHora = e.out.filter((x) => x.hora === h);
    if (naHora.some((x) => x.tipo === 'bloqueio')) return false;
    return naHora.filter((x) => x.tipo !== 'bloqueio').length < Number(cfg.vagas || 1);
  });
  return { motivo: horas.length ? '' : 'Sem horário livre.', horas };
}
function meus(ctx: NonNullable<Awaited<ReturnType<typeof carregar>>>) {
  return ctx.itens.filter((it) => it.data.clienteOnlineId === ctx.cli.id && !it.data.cancelado)
    .map((it) => ({ id: it.id, data: it.data.data, hora: it.data.hora, status: it.data.status || 'agendado', rotulo: rotulo(it.data.data, ctx.hoje) }))
    .sort((a, b) => (a.data + a.hora).localeCompare(b.data + b.hora));
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return resposta({ erro: 'metodo' }, 405);
  let corpo: Record<string, any> = {};
  try { corpo = await req.json(); } catch { return resposta({ erro: 'corpo' }, 400); }
  const ctx = await carregar(String(corpo.t || ''));
  if (!ctx) return resposta({ erro: 'link' }, 404);
  const cfg = ctx.config, acao = String(corpo.acao || 'horarios');
  try {
    if (acao === 'horarios') {
      const dias = [];
      for (let i = 0; i <= Number(cfg.diasAFrente || 14); i++) {
        const iso = maisDias(ctx.hoje, i), l = livres(iso, ctx);
        dias.push({ data: iso, rotulo: rotulo(iso, ctx.hoje), horas: l.horas, motivo: l.motivo });
      }
      return resposta({ ok: true, cliente: { nome: ctx.cli.data.nome }, ativo: !!cfg.ativo, antecedenciaHoras: cfg.antecedenciaHoras, dias, meus: meus(ctx) });
    }
    if (acao === 'agendar') {
      const iso = String(corpo.data || ''), h = String(corpo.hora || '');
      if (!/^\d{4}-\d{2}-\d{2}$/.test(iso) || !HORAS.includes(h)) return resposta({ erro: 'horario' }, 400);
      if (iso > maisDias(ctx.hoje, Number(cfg.diasAFrente || 14))) return resposta({ erro: 'longe' }, 400);
      if (!livres(iso, ctx).horas.includes(h)) return resposta({ erro: 'ocupado' }, 409);
      const ativos = meus(ctx).filter((m) => m.status !== 'cancelado');
      if (ativos.some((m) => m.data === iso && m.hora === h)) return resposta({ erro: 'repetido' }, 409);
      if (ativos.length >= Number(cfg.maxAtivos || 5)) return resposta({ erro: 'limite', max: cfg.maxAtivos }, 409);
      const id = 'on-' + novoId(16), agora = new Date().toISOString();
      const { error } = await admin.from('docs').insert({ colecao: 'agenda-itens', id, data: {
        data: iso, hora: h, cliente: ctx.cli.data.nome, tipo: 'cliente', origem: 'online', clienteOnlineId: ctx.cli.id, telefone: ctx.cli.data.telefone || '',
        status: 'agendado', obs: String(corpo.obs || '').slice(0, 140), criadoEm: agora } });
      if (error) throw error;
      // dois clientes no último lugar ao mesmo tempo: fica quem gravou primeiro
      const fixosNaHora = entradas(iso, { ...ctx, itens: [] }).out.filter((x) => x.hora === h && x.tipo !== 'bloqueio').length;
      const { data: naHora } = await admin.from('docs').select('id,data').eq('colecao', 'agenda-itens').eq('data->>data', iso).eq('data->>hora', h);
      const fila = ((naHora || []) as Doc[]).filter((x) => !x.data.cancelado && (x.data.tipo || 'cliente') !== 'bloqueio')
        .sort((a, b) => String(a.data.criadoEm || '').localeCompare(String(b.data.criadoEm || '')) || a.id.localeCompare(b.id));
      if (fixosNaHora + fila.findIndex((x) => x.id === id) >= Number(cfg.vagas || 1)) {
        await admin.from('docs').delete().eq('colecao', 'agenda-itens').eq('id', id);
        return resposta({ erro: 'ocupado' }, 409);
      }
      return resposta({ ok: true, id, rotulo: rotulo(iso, ctx.hoje), hora: h });
    }
    if (acao === 'confirmar' || acao === 'cancelar') {
      const it = ctx.itens.find((x) => x.id === String(corpo.id || ''));
      if (!it || it.data.clienteOnlineId !== ctx.cli.id || it.data.cancelado) return resposta({ erro: 'agendamento' }, 404);
      const { data: r, error } = await admin.rpc('agenda_online_mudar', { p_id: it.id, p_cliente: ctx.cli.id, p_acao: acao });
      if (error) throw error;
      if (r !== 'ok') return resposta({ erro: 'agendamento' }, 404);
      return resposta({ ok: true, status: acao === 'confirmar' ? 'confirmado' : 'cancelado' });
    }
    return resposta({ erro: 'acao' }, 400);
  } catch (e) {
    console.error('agendamento', e);
    return resposta({ erro: 'interno' }, 500);
  }
});
