// LEVÍSSIMA · função "acesso": confere a senha digitada no app e devolve um login do Supabase.
// As senhas ficam só no banco (hash bcrypt) e nunca vão para o app. Cada senha (mestre, equipe do
// escritório, cada motorista, cada setor) tem um usuário próprio no Supabase Auth; o papel e os módulos
// dele vão no token e o banco libera os dados de acordo (políticas de 0002_acesso.sql e 0003_modulos.sql).
//
// Ações (POST, JSON):
//   { acao: 'entrar', senha }                                     -> { access_token, refresh_token, papel, nome, modulos }
//   { acao: 'conferir', senha }                                    -> { ok, papel }      (precisa estar logado)
//   { acao: 'definir', ref, nome, senha, senhaAtual?, modulos? }   -> { ok }             (só a senha mestre)
//   { acao: 'ajustar', ref, nome?, modulos }                       -> { ok }             (só a senha mestre; sem trocar a senha)
//   { acao: 'remover', ref }                                       -> { ok }             (só a senha mestre)
//   { acao: 'lista' }                                              -> { senhas: [...] }  (só a senha mestre)
//   { acao: 'bio_exigir', ref, exige }                             -> { ok }             (só a senha mestre: exige o rosto)
//   { acao: 'bio_apagar', ref }                                    -> { ok }             (só a senha mestre: apaga os rostos cadastrados)
// Segurança (29/10/2026, migração 0037):
//   'entrar' da senha mestre com o código ligado -> { segundoFator, ticket, rosto } (ainda sem login)
//   { acao: 'entrar_codigo', ticket, codigo }                      -> login              (código do autenticador ou de emergência)
//   { acao: 'bio_ticket_proprio', senha }                          -> { ticket, nome }   (logado: cadastra o rosto no aparelho)
//   { acao: 'totp_estado' } / 'totp_iniciar' (senha) / 'totp_confirmar' (codigo) / 'totp_codigos_novos' (senha, codigo)
//   / 'totp_desligar' (senha, codigo)                                                     (só a senha mestre)
//   { acao: 'sair_aparelhos', ref }                                -> { ok }             (só a senha mestre: derruba os logins)
//   { acao: 'aparelhos', ref }                                     -> { aparelhos }      (só a senha mestre)
//   'entrar' guarda o aparelho (corpo.dispositivo) e avisa a senha mestre de aparelho novo; trocar a senha derruba os
//   logins abertos daquela senha. Senha nova: 8 caracteres e sem as fáceis (acesso_definir).
// Entrar com o rosto (passkey do aparelho; verificação em webauthn.js):
//   'entrar' com a senha de quem exige o rosto: sem rosto cadastrado -> { cadastrarRosto, ticket, nome } (ainda sem login);
//                                               com rosto cadastrado -> erro 'biometria' (a senha sozinha não entra)
//   { acao: 'bio_registro_opcoes', ticket }                        -> { opcoes }         (cadastro do rosto no 1º acesso)
//   { acao: 'bio_registro', ticket, credencial, aparelho }         -> login              (rosto cadastrado: entra)
//   { acao: 'bio_entrar_opcoes' }                                  -> { opcoes }
//   { acao: 'bio_entrar', credencial }                             -> login
// 'diretoria:<id>' (diretoria: vê tudo como a senha mestre, mas só inclui; não altera nem apaga — regras em 0014).
// 'escritorio:<id>' (pessoa do escritório com a própria senha: papel 'equipe', com o nome dela; a permissão 'canhotos'
// abre o controle de canhotos e as fotos do caminhão — regras em 0015; 'liberar_carga' libera carga sem leitura e
// sem fotos — regras em 0016; 'aba:<id>' escolhe as abas que ela vê; 'ver:<aba>' ou 'inclui:<aba>', o nível em cada aba:
// só visualiza ou só inclui — com o mesmo nível em todas, o token leva so_ver ou so_inclui e o banco segura, regras em 0021).
// Senhas: 'mestre' (tudo), 'equipe' (escritório de cargas + módulos marcados), 'motorista:<id>' (app do motorista)
// 'setor:<id>' (só os módulos marcados: Manutenção, Empilhadeiras, Uniformes e EPI, Garrafões)
// e 'representante:<id>' (Força de vendas: lança as cargas dos clientes dele; regras em 0005_forca_de_vendas.sql).
// Cada módulo pode ser "usado" ('manutencao') ou "gerenciado" ('manutencao:gerir').
import { createClient } from 'npm:@supabase/supabase-js@2';
import { verificarRegistro, verificarEntrada, desafioNovo, desafioDaCredencial, b64urlEnc } from './webauthn.js';

const URL_SB = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICO = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const DOMINIO = 'acesso.levissima.app.br'; // só identifica os logins internos; nenhum e-mail é enviado
// passkeys valem para o site do app (o iPhone e o computador usam o app pelo navegador)
const RP_ID = 'nicolaslevissima-afk.github.io';
const ORIGENS = ['https://nicolaslevissima-afk.github.io'];

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

type Ident = { ref: string; papel: string; nome: string; usuario: string | null; modulos?: string[] };
type Quem = { papel: string; ref: string; soInclui: boolean };

// Módulos da fábrica ("usar" ou "gerir"). Nos acessos individuais do escritório vão também as permissões
// ('canhotos': controle de canhotos e fotos do caminhão; 'liberar_carga': libera carga sem leitura e sem fotos)
// e as abas que a pessoa vê ('aba:<id>', com a marca 'abas' quando a lista de abas foi escolhida).
const MODULOS = ['manutencao', 'empilhadeiras', 'uniformes', 'garrafoes'];
// 'lider_producao' (21/10/2026): o acesso só lança a produção hora a hora (o app mostra só essa tela)
const PERMISSOES = ['canhotos', 'liberar_carga', 'abas', 'lider_producao'];
const ABAS = ['cargas', 'paletes', 'estoque', 'producao', 'materia', 'agenda', 'salas', 'qualidade', 'metas', 'compras', 'trocas'];
// nível de cada aba marcada (19/10/2026): 'ver:<aba>' = só visualiza, 'inclui:<aba>' = só inclui; sem nada = edita
const NIVEIS = ['ver', 'inclui'];

function papelDaRef(ref: string): string | null {
  if (ref === 'mestre') return 'mestre';
  if (ref === 'equipe') return 'equipe';
  if (/^motorista:[A-Za-z0-9_-]{1,64}$/.test(ref)) return 'motorista';
  if (/^setor:[A-Za-z0-9_-]{1,64}$/.test(ref)) return 'setor';
  if (/^representante:[A-Za-z0-9_-]{1,64}$/.test(ref)) return 'representante';
  if (/^diretoria:[A-Za-z0-9_-]{1,64}$/.test(ref)) return 'diretoria';
  // acesso individual de uma pessoa do escritório: vê o mesmo que a senha da equipe, com o próprio nome e permissões
  if (/^escritorio:[A-Za-z0-9_-]{1,64}$/.test(ref)) return 'equipe';
  return null;
}

// Lista válida: só os módulos conhecidos ("usar" ou "gerir", sem repetir: gerir vale mais que usar), as permissões
// e as abas conhecidas.
function limparModulos(v: unknown): string[] {
  const lista = Array.isArray(v) ? v.map((x) => String(x)) : [];
  const nivel = new Map<string, string>();
  const extras = new Set<string>();
  for (const item of lista) {
    if (PERMISSOES.includes(item)) { extras.add(item); continue; }
    if (item.startsWith('aba:')) { if (ABAS.includes(item.slice(4))) extras.add(item); continue; }
    const nv = item.split(':');
    if (nv.length === 2 && NIVEIS.includes(nv[0]) && ABAS.includes(nv[1])) { extras.add(item); continue; }
    const [m, g] = item.split(':');
    if (!MODULOS.includes(m) || (g !== undefined && g !== 'gerir')) continue;
    if (g === 'gerir' || !nivel.has(m)) nivel.set(m, g === 'gerir' ? m + ':gerir' : m);
  }
  return [...MODULOS.filter((m) => nivel.has(m)).map((m) => nivel.get(m) as string),
    ...PERMISSOES.filter((p) => extras.has(p)), ...ABAS.filter((a) => extras.has('aba:' + a)).map((a) => 'aba:' + a),
    // o nível só vale para aba marcada; se vier "ver" e "inclui" para a mesma aba, fica o mais restrito (ver)
    ...ABAS.filter((a) => extras.has('aba:' + a) && (extras.has('ver:' + a) || extras.has('inclui:' + a)))
      .map((a) => (extras.has('ver:' + a) ? 'ver:' : 'inclui:') + a)];
}
// Nível igual em todas as abas marcadas: o banco também segura (so_ver: não grava nada; so_inclui: não altera nem apaga).
// Com níveis diferentes por aba, quem segura é o app (a aba aberta decide).
function nivelGeral(modulos: string[]): '' | 'ver' | 'inclui' {
  if (!modulos.includes('abas')) return '';
  const abas = ABAS.filter((a) => modulos.includes('aba:' + a));
  if (!abas.length) return '';
  if (abas.every((a) => modulos.includes('ver:' + a))) return 'ver';
  if (abas.every((a) => modulos.includes('ver:' + a) || modulos.includes('inclui:' + a))) return 'inclui';
  return '';
}

async function linhaDe(ref: string): Promise<{ modulos: string[]; biometria: boolean; papel: string; nome: string; usuario: string | null } | null> {
  const { data } = await admin.from('acesso_senhas').select('modulos, biometria, papel, nome, usuario').eq('ref', ref).maybeSingle();
  if (!data) return null;
  const l = data as { modulos?: unknown; biometria?: boolean; papel: string; nome: string; usuario: string | null };
  return { modulos: limparModulos(l.modulos), biometria: !!l.biometria, papel: l.papel, nome: l.nome || '', usuario: l.usuario || null };
}
// o que vai no token: a diretoria entra com papel 'mestre' (vê tudo) e so_inclui (o banco não deixa alterar nem apagar)
function metaDe(id: { ref: string; papel: string; nome: string }, modulos: string[], biometria: boolean) {
  const dir = id.papel === 'diretoria';
  const geral = id.papel === 'equipe' ? nivelGeral(modulos) : '';
  return { papel: dir ? 'mestre' : id.papel, nome: id.nome, ref: id.ref, modulos, so_inclui: dir || geral === 'inclui', so_ver: geral === 'ver', biometria };
}
function emailDe(ref: string) { return ref.toLowerCase().replace(/[^a-z0-9]+/g, '-') + '@' + DOMINIO; }

async function senhaInterna(ref: string): Promise<string> {
  const { data: segredo, error } = await admin.rpc('acesso_segredo_ler');
  if (error || !segredo) throw new Error('segredo indisponível');
  const chave = await crypto.subtle.importKey('raw', new TextEncoder().encode(String(segredo)), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const assin = await crypto.subtle.sign('HMAC', chave, new TextEncoder().encode('levissima:' + ref));
  return Array.from(new Uint8Array(assin)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function acharUsuarioPorEmail(email: string): Promise<string | null> {
  for (let pagina = 1; pagina <= 20; pagina++) {
    const { data, error } = await admin.auth.admin.listUsers({ page: pagina, perPage: 200 });
    if (error) return null;
    const u = data.users.find((x) => (x.email || '').toLowerCase() === email);
    if (u) return u.id;
    if (data.users.length < 200) return null;
  }
  return null;
}

// Garante o usuário do Auth ligado a esta senha (com o papel no token) e abre uma sessão para ele.
async function sessaoPara(id: Ident) {
  const email = emailDe(id.ref);
  const senha = await senhaInterna(id.ref);
  const linha = await linhaDe(id.ref);
  const modulos = await modulosDoToken(id.ref, (id.papel === 'equipe' || id.papel === 'setor') && linha ? linha.modulos : []);
  const meta = metaDe(id, modulos, !!(linha && linha.biometria));
  let uid = id.usuario;
  if (uid) {
    const { error } = await admin.auth.admin.updateUserById(uid, { app_metadata: meta });
    if (error) uid = null; // o usuário foi apagado: cria de novo
  }
  if (!uid) {
    const criado = await admin.auth.admin.createUser({ email, password: senha, email_confirm: true, app_metadata: meta, user_metadata: { nome: id.nome } });
    if (criado.error) {
      uid = await acharUsuarioPorEmail(email); // já existia com esse e-mail (ligação perdida)
      if (!uid) throw criado.error;
      const { error } = await admin.auth.admin.updateUserById(uid, { app_metadata: meta, password: senha, email_confirm: true });
      if (error) throw error;
    } else {
      uid = criado.data.user.id;
    }
    await admin.rpc('acesso_ligar_usuario', { p_ref: id.ref, p_usuario: uid });
  }
  const login = createClient(URL_SB, SERVICO, { auth: { persistSession: false, autoRefreshToken: false } });
  let r = await login.auth.signInWithPassword({ email, password: senha });
  if (r.error) { // senha interna fora de sincronia: acerta e tenta de novo
    await admin.auth.admin.updateUserById(uid as string, { password: senha, email_confirm: true });
    r = await login.auth.signInWithPassword({ email, password: senha });
  }
  const { data, error } = r;
  if (error || !data.session) throw error || new Error('sem sessão');
  return { access_token: data.session.access_token, refresh_token: data.session.refresh_token, papel: meta.papel, nome: id.nome, modulos, soInclui: meta.so_inclui, biometria: meta.biometria };
}

// Grava os módulos (e o nome) de uma senha e já atualiza o login ligado a ela: vale no próximo acesso
// e, para quem está com o app aberto, na próxima renovação do login (até 1 hora).
// pessoa do escritório (escritorio:<id>): o que foi marcado para ela em Cadastros › Equipe com senha. Acesso criado
// antes das caixas de assinalar (sem a marca 'abas'): os módulos da fábrica da senha da equipe, mais as permissões dela.
async function modulosDoToken(ref: string, modulos: string[]): Promise<string[]> {
  if (!ref.startsWith('escritorio:') || modulos.includes('abas')) return modulos;
  const equipe = await linhaDe('equipe');
  return limparModulos([...(equipe ? equipe.modulos.filter((m) => MODULOS.includes(m.split(':')[0])) : []), ...modulos]);
}

async function gravarModulos(ref: string, modulos: string[], nome: string | null): Promise<boolean> {
  const mud: Record<string, unknown> = { modulos };
  if (nome !== null) mud.nome = nome;
  const { data, error } = await admin.from('acesso_senhas').update(mud).eq('ref', ref).select('papel, nome, usuario, biometria');
  if (error) throw error;
  const linha = Array.isArray(data) ? data[0] : null;
  if (!linha) return false;
  if (linha.usuario) {
    await admin.auth.admin.updateUserById(String(linha.usuario), { app_metadata: metaDe({ ref, papel: linha.papel, nome: linha.nome }, await modulosDoToken(ref, modulos), !!linha.biometria) });
  }
  return true;
}

async function conferir(senha: string, origem: string): Promise<Ident | null | 'bloqueado'> {
  const { data, error } = await admin.rpc('acesso_conferir', { p_senha: senha, p_origem: origem });
  if (error) {
    if (String(error.message || '').includes('muitas tentativas')) return 'bloqueado';
    throw error;
  }
  const linha = Array.isArray(data) ? data[0] : null;
  return linha ? { ref: linha.ref, papel: linha.papel, nome: linha.nome || '', usuario: linha.usuario || null } : null;
}

async function quemChamou(req: Request): Promise<Quem | null> {
  const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!token || token.split('.').length !== 3) return null;
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) return null;
  const m = (data.user.app_metadata || {}) as Record<string, unknown>;
  return m.papel ? { papel: String(m.papel), ref: String(m.ref || ''), soInclui: m.so_inclui === true } : null;
}

// ---------- rosto (passkeys) ----------
async function rostosDe(ref: string): Promise<{ cred_id: string; transportes: string[] }[]> {
  const { data } = await admin.from('acesso_biometria').select('cred_id, transportes').eq('ref', ref);
  return (data || []) as { cred_id: string; transportes: string[] }[];
}
async function usuarioDoRosto(ref: string): Promise<string> {
  const h = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode('levissima-rosto:' + ref)));
  return b64urlEnc(h.slice(0, 16));
}
function emMinutos(n: number) { return new Date(Date.now() + n * 60000).toISOString(); }
function limparDesafios() { admin.from('acesso_desafios').delete().lt('expira', new Date().toISOString()).then(() => {}, () => {}); }
async function ticketValido(ticket: string) {
  if (!/^[A-Za-z0-9_-]{30,64}$/.test(ticket)) return null;
  const { data } = await admin.from('acesso_desafios').select('id, ref, desafio, expira').eq('ticket', ticket).eq('tipo', 'cadastro').maybeSingle();
  const t = data as { id: number; ref: string; desafio: string | null; expira: string } | null;
  return t && new Date(t.expira).getTime() > Date.now() ? t : null;
}

// ---------- segurança (0037): aparelhos, revogação, segundo fator ----------
async function aviso(tipo: string, ref: string, nome: string, detalhe: string, origem = '') {
  await admin.from('seguranca_eventos').insert({ tipo, ref, nome: nome.slice(0, 120), detalhe: detalhe.slice(0, 500), origem: origem.slice(0, 80) }).then(() => {}, () => {});
}
function textoCurto(v: unknown, n: number) { return String(v == null ? '' : v).replace(/[\u0000-\u001f]/g, ' ').slice(0, n); }
async function registrarAparelho(id: { ref: string; nome: string }, corpo: Record<string, unknown>, origem: string) {
  const aparelho = textoCurto(corpo.dispositivo, 64);
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(aparelho)) return;
  const descricao = textoCurto(corpo.dispositivoDesc, 80);
  const agora = new Date().toISOString();
  const { data: ja } = await admin.from('acesso_aparelhos').select('aparelho').eq('ref', id.ref).eq('aparelho', aparelho).maybeSingle();
  if (ja) { await admin.from('acesso_aparelhos').update({ ultimo_em: agora, origem: origem.slice(0, 80), descricao }).eq('ref', id.ref).eq('aparelho', aparelho); return; }
  const { count } = await admin.from('acesso_aparelhos').select('aparelho', { count: 'exact', head: true }).eq('ref', id.ref);
  await admin.from('acesso_aparelhos').insert({ ref: id.ref, aparelho, descricao, origem: origem.slice(0, 80), primeiro_em: agora, ultimo_em: agora });
  if ((count || 0) > 0 || id.ref === 'mestre') {
    await aviso('aparelho_novo', id.ref, id.nome, 'Entrada num aparelho novo' + (descricao ? ' (' + descricao + ')' : '') + '. Se não foi quem tem essa senha, use "Sair de todos os aparelhos" e troque a senha.', origem);
  }
}
// derruba todos os logins abertos desta senha: o banco recusa os tokens emitidos antes (papel_atual) e o usuário
// do login é apagado (as sessões e a renovação somem; no próximo login ele é criado de novo)
async function revogar(ref: string, por: string) {
  const em = new Date(Math.floor(Date.now() / 1000) * 1000).toISOString();
  await admin.from('acesso_revogacoes').upsert({ ref, em, por });
  const { data } = await admin.from('acesso_senhas').select('usuario').eq('ref', ref).maybeSingle();
  const usuario = data && (data as { usuario: string | null }).usuario;
  if (usuario) await admin.auth.admin.deleteUser(String(usuario)).then(() => {}, () => {});
}
const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
function b32enc(b: Uint8Array) {
  let bits = 0, val = 0, out = '';
  for (const x of b) { val = (val << 8) | x; bits += 8; while (bits >= 5) { out += B32[(val >>> (bits - 5)) & 31]; bits -= 5; } }
  if (bits > 0) out += B32[(val << (5 - bits)) & 31];
  return out;
}
function b32dec(s: string) {
  const t = s.toUpperCase().replace(/[^A-Z2-7]/g, '');
  let bits = 0, val = 0; const out: number[] = [];
  for (const c of t) { val = (val << 5) | B32.indexOf(c); bits += 5; if (bits >= 8) { out.push((val >>> (bits - 8)) & 255); bits -= 8; } }
  return new Uint8Array(out);
}
async function hotp(segredo: string, passo: number) {
  const chave = await crypto.subtle.importKey('raw', b32dec(segredo), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  const msg = new Uint8Array(8); let x = passo;
  for (let i = 7; i >= 0; i--) { msg[i] = x & 255; x = Math.floor(x / 256); }
  const h = new Uint8Array(await crypto.subtle.sign('HMAC', chave, msg));
  const o = h[h.length - 1] & 15;
  const n = ((h[o] & 127) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
  return String(n % 1000000).padStart(6, '0');
}
// código de 6 números do autenticador (aceita o anterior e o próximo, por diferença de relógio; nunca o mesmo duas vezes)
async function passoDoCodigo(segredo: string, codigo: string, ultimo: number): Promise<number | null> {
  if (!/^\d{6}$/.test(codigo)) return null;
  const agora = Math.floor(Date.now() / 30000);
  for (const d of [0, -1, 1]) { const p = agora + d; if (p > ultimo && await hotp(segredo, p) === codigo) return p; }
  return null;
}
async function sha256hex(t: string) { return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(t)))).map((b) => b.toString(16).padStart(2, '0')).join(''); }
function codigosEmergencia(): string[] {
  const out: string[] = [];
  for (let i = 0; i < 8; i++) { const b = b32enc(crypto.getRandomValues(new Uint8Array(6))).slice(0, 8); out.push(b.slice(0, 4) + '-' + b.slice(4)); }
  return out;
}
async function totpDe(ref: string) {
  const { data } = await admin.from('acesso_totp').select('segredo, ativo, ultimo_passo, recuperacao').eq('ref', ref).maybeSingle();
  return data as { segredo: string; ativo: boolean; ultimo_passo: number; recuperacao: string[] } | null;
}
// confere o código do autenticador ou um código de emergência (que só vale uma vez)
async function conferirSegundo(ref: string, codigoBruto: string): Promise<boolean> {
  const t = await totpDe(ref);
  if (!t || !t.ativo) return false;
  const codigo = codigoBruto.replace(/\s+/g, '');
  const passo = await passoDoCodigo(t.segredo, codigo, Number(t.ultimo_passo) || 0);
  if (passo !== null) { await admin.from('acesso_totp').update({ ultimo_passo: passo }).eq('ref', ref); return true; }
  const norm = codigo.toUpperCase().replace(/[^A-Z2-7]/g, '');
  if (norm.length !== 8) return false;
  const h = await sha256hex(norm);
  const lista = t.recuperacao || [];
  if (!lista.includes(h)) return false;
  await admin.from('acesso_totp').update({ recuperacao: lista.filter((x) => x !== h) }).eq('ref', ref);
  await aviso('codigo_emergencia', ref, '', 'Um código de emergência foi usado para entrar (restam ' + (lista.length - 1) + ').');
  return true;
}
async function segundoBloqueado(ref: string) {
  const { count } = await admin.from('acesso_tentativas').select('id', { count: 'exact', head: true })
    .eq('origem', 'codigo:' + ref).eq('ok', false).gt('em', new Date(Date.now() - 15 * 60000).toISOString());
  return (count || 0) >= 5;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return erro('metodo', 405);
  let corpo: Record<string, unknown>;
  try { corpo = await req.json(); } catch { return erro('dados', 400); }
  const acao = String(corpo.acao || '');
  const origem = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'desconhecida';
  try {
    if (acao === 'entrar') {
      // limpeza das tentativas com mais de um dia (não atrasa o login)
      admin.from('acesso_tentativas').delete().lt('em', new Date(Date.now() - 86400000).toISOString()).then(() => {}, () => {});
      // histórico e avisos têm prazo: auditoria 90 dias, tentativas de PIN 30 dias, avisos de segurança 180 dias
      admin.from('auditoria').delete().lt('em', new Date(Date.now() - 90 * 86400000).toISOString()).then(() => {}, () => {});
      admin.from('pin_tentativas').delete().lt('em', new Date(Date.now() - 30 * 86400000).toISOString()).then(() => {}, () => {});
      admin.from('seguranca_eventos').delete().lt('em', new Date(Date.now() - 180 * 86400000).toISOString()).then(() => {}, () => {});
      const senha = String(corpo.senha || '');
      if (!senha || senha.length > 200) return erro('senha', 401);
      const id = await conferir(senha, origem);
      if (id === 'bloqueado') return erro('tentativas', 429);
      if (!id) return erro('senha', 401);
      // senha mestre com o segundo fator ligado: a senha sozinha não entra (rosto ou código do autenticador)
      if (id.ref === 'mestre') {
        const t = await totpDe('mestre');
        if (t && t.ativo) {
          limparDesafios();
          const ticket = desafioNovo();
          const { error } = await admin.from('acesso_desafios').insert({ tipo: 'segundo', ref: 'mestre', ticket, expira: emMinutos(5) });
          if (error) throw error;
          return resposta({ segundoFator: true, ticket, rosto: (await rostosDe('mestre')).length > 0, nome: id.nome });
        }
      }
      const linha = await linhaDe(id.ref);
      if (linha && linha.biometria) {
        // exige o rosto: com rosto cadastrado, a senha sozinha não entra; sem rosto, cadastra antes de entrar
        if ((await rostosDe(id.ref)).length) return erro('biometria', 403);
        limparDesafios();
        const ticket = desafioNovo();
        const { error } = await admin.from('acesso_desafios').insert({ tipo: 'cadastro', ref: id.ref, ticket, expira: emMinutos(10) });
        if (error) throw error;
        return resposta({ cadastrarRosto: true, ticket, nome: id.nome });
      }
      const sess = await sessaoPara(id);
      await registrarAparelho(id, corpo, origem);
      return resposta(sess);
    }

    if (acao === 'entrar_codigo') {
      const ticket = String(corpo.ticket || '');
      if (!/^[A-Za-z0-9_-]{30,64}$/.test(ticket)) return erro('ticket', 401);
      const { data: tk } = await admin.from('acesso_desafios').select('id, ref, expira').eq('ticket', ticket).eq('tipo', 'segundo').maybeSingle();
      const t = tk as { id: number; ref: string; expira: string } | null;
      if (!t || new Date(t.expira).getTime() < Date.now()) return erro('ticket', 401);
      if (await segundoBloqueado(t.ref)) return erro('tentativas', 429);
      const ok = await conferirSegundo(t.ref, String(corpo.codigo || ''));
      await admin.from('acesso_tentativas').insert({ origem: 'codigo:' + t.ref, ok });
      if (!ok) {
        if (await segundoBloqueado(t.ref)) await aviso('codigo_bloqueio', t.ref, '', '5 códigos do autenticador errados em 15 minutos depois da senha mestre certa: bloqueado por 15 minutos. Se não foi você, troque a senha mestre.', origem);
        return erro('codigo', 401);
      }
      await admin.from('acesso_desafios').delete().eq('id', t.id);
      const linha = await linhaDe(t.ref);
      if (!linha) return erro('ticket', 401);
      const ident = { ref: t.ref, papel: linha.papel, nome: linha.nome, usuario: linha.usuario };
      const sess = await sessaoPara(ident);
      await registrarAparelho(ident, corpo, origem);
      return resposta(sess);
    }

    if (acao === 'bio_registro_opcoes') {
      const t = await ticketValido(String(corpo.ticket || ''));
      if (!t) return erro('ticket', 401);
      const linha = await linhaDe(t.ref);
      if (!linha) return erro('ticket', 401);
      const desafio = desafioNovo();
      const { error } = await admin.from('acesso_desafios').update({ desafio }).eq('id', t.id);
      if (error) throw error;
      const ja = await rostosDe(t.ref);
      return resposta({ opcoes: {
        rp: { id: RP_ID, name: 'LEVÍSSIMA' },
        user: { id: await usuarioDoRosto(t.ref), name: (linha.nome || 'Acesso') + ' · LEVÍSSIMA', displayName: linha.nome || 'Acesso LEVÍSSIMA' },
        challenge: desafio,
        pubKeyCredParams: [{ type: 'public-key', alg: -7 }, { type: 'public-key', alg: -257 }, { type: 'public-key', alg: -8 }],
        timeout: 120000, attestation: 'none',
        authenticatorSelection: { residentKey: 'required', requireResidentKey: true, userVerification: 'required' },
        excludeCredentials: ja.map((c) => ({ type: 'public-key', id: c.cred_id, transports: c.transportes || [] })),
      } });
    }

    if (acao === 'bio_registro') {
      const t = await ticketValido(String(corpo.ticket || ''));
      if (!t || !t.desafio) return erro('ticket', 401);
      let novo;
      try { novo = await verificarRegistro({ credencial: corpo.credencial, desafio: t.desafio, origens: ORIGENS, rpId: RP_ID }); }
      catch (e) { console.warn('rosto: cadastro recusado', (e as { codigo?: string }).codigo || e); return erro('rosto', 400); }
      const { error } = await admin.from('acesso_biometria').insert({ cred_id: novo.credId, ref: t.ref, chave: novo.chave, alg: novo.alg, contador: novo.contador,
        transportes: novo.transportes, aparelho: String(corpo.aparelho || '').slice(0, 80) });
      if (error) throw error;
      await admin.from('acesso_desafios').delete().eq('id', t.id);
      const linha = await linhaDe(t.ref);
      if (!linha) return erro('ticket', 401);
      const identR = { ref: t.ref, papel: linha.papel, nome: linha.nome, usuario: linha.usuario };
      const sessR = await sessaoPara(identR);
      await registrarAparelho(identR, corpo, origem);
      return resposta(sessR);
    }

    if (acao === 'bio_entrar_opcoes') {
      limparDesafios();
      const { count } = await admin.from('acesso_desafios').select('id', { count: 'exact', head: true }).eq('tipo', 'entrar').gt('expira', new Date().toISOString());
      if ((count || 0) > 500) return erro('tentativas', 429);
      const desafio = desafioNovo();
      const { error } = await admin.from('acesso_desafios').insert({ tipo: 'entrar', desafio, expira: emMinutos(5) });
      if (error) throw error;
      return resposta({ opcoes: { challenge: desafio, rpId: RP_ID, timeout: 120000, userVerification: 'required', allowCredentials: [] } });
    }

    if (acao === 'bio_entrar') {
      const credencial = corpo.credencial as { id?: string; rawId?: string } | undefined;
      const desafio = credencial ? desafioDaCredencial(credencial) : '';
      if (!desafio) return erro('rosto', 401);
      // o desafio vale uma vez só: apaga antes de conferir
      const { data: usados } = await admin.from('acesso_desafios').delete().eq('desafio', desafio).eq('tipo', 'entrar').gt('expira', new Date().toISOString()).select('id');
      if (!usados || !usados.length) return erro('rosto', 401);
      const credId = String((credencial && (credencial.rawId || credencial.id)) || '');
      const { data: rc } = await admin.from('acesso_biometria').select('cred_id, ref, chave, contador').eq('cred_id', credId).maybeSingle();
      const cred = rc as { cred_id: string; ref: string; chave: string; contador: number } | null;
      if (!cred) return erro('rosto', 401);
      let r;
      try { r = await verificarEntrada({ credencial, desafio, origens: ORIGENS, rpId: RP_ID, chave: cred.chave, contador: cred.contador }); }
      catch (e) { console.warn('rosto: entrada recusada', (e as { codigo?: string }).codigo || e); return erro('rosto', 401); }
      await admin.from('acesso_biometria').update({ contador: r.contador, usado_em: new Date().toISOString() }).eq('cred_id', cred.cred_id);
      const linha = await linhaDe(cred.ref);
      if (!linha) return erro('rosto', 401);
      const identB = { ref: cred.ref, papel: linha.papel, nome: linha.nome, usuario: linha.usuario };
      const sessB = await sessaoPara(identB);
      await registrarAparelho(identB, corpo, origem);
      return resposta(sessB);
    }

    const quem = await quemChamou(req);
    if (!quem) return erro('login', 401);

    if (acao === 'conferir') {
      const id = await conferir(String(corpo.senha || ''), origem);
      if (id === 'bloqueado') return erro('tentativas', 429);
      return resposta({ ok: !!id && id.ref === quem.ref, papel: id && id !== 'bloqueado' && id.ref === quem.ref ? id.papel : null });
    }

    // cadastrar o rosto no aparelho em que está logado (confirma a própria senha)
    if (acao === 'bio_ticket_proprio') {
      const id = await conferir(String(corpo.senha || ''), origem);
      if (id === 'bloqueado') return erro('tentativas', 429);
      if (!id || id.ref !== quem.ref) return erro('senha', 401);
      limparDesafios();
      const ticket = desafioNovo();
      const { error } = await admin.from('acesso_desafios').insert({ tipo: 'cadastro', ref: quem.ref, ticket, expira: emMinutos(10) });
      if (error) throw error;
      return resposta({ ticket, nome: id.nome });
    }

    if (quem.papel !== 'mestre' || quem.soInclui) return erro('permissao', 403); // a diretoria (só inclui) não mexe em senhas

    if (acao === 'totp_estado') {
      const t = await totpDe('mestre');
      return resposta({ ativo: !!(t && t.ativo), emergencia: t && t.ativo ? (t.recuperacao || []).length : 0, rostos: (await rostosDe('mestre')).length });
    }
    if (acao === 'totp_iniciar' || acao === 'totp_codigos_novos' || acao === 'totp_desligar') {
      const id = await conferir(String(corpo.senha || ''), origem);
      if (id === 'bloqueado') return erro('tentativas', 429);
      if (!id || id.ref !== 'mestre') return erro('senha', 401);
      const t = await totpDe('mestre');
      if (acao === 'totp_iniciar') {
        if (t && t.ativo) return erro('ja_ativo', 409);
        const segredo = b32enc(crypto.getRandomValues(new Uint8Array(20)));
        const { error } = await admin.from('acesso_totp').upsert({ ref: 'mestre', segredo, ativo: false, ultimo_passo: 0, recuperacao: [] });
        if (error) throw error;
        return resposta({ segredo, uri: 'otpauth://totp/LEVISSIMA:Senha%20mestre?secret=' + segredo + '&issuer=LEVISSIMA&digits=6&period=30&algorithm=SHA1' });
      }
      if (!t || !t.ativo) return erro('desligado', 409);
      if (await segundoBloqueado('mestre')) return erro('tentativas', 429);
      const okc = await conferirSegundo('mestre', String(corpo.codigo || ''));
      await admin.from('acesso_tentativas').insert({ origem: 'codigo:mestre', ok: okc });
      if (!okc) return erro('codigo', 401);
      if (acao === 'totp_desligar') {
        await admin.from('acesso_totp').delete().eq('ref', 'mestre');
        await aviso('segundo_fator_desligado', 'mestre', '', 'O código do autenticador da senha mestre foi desligado.', origem);
        return resposta({ ok: true });
      }
      const codigos = codigosEmergencia();
      await admin.from('acesso_totp').update({ recuperacao: await Promise.all(codigos.map((c) => sha256hex(c.replace('-', '')))) }).eq('ref', 'mestre');
      return resposta({ codigos });
    }
    if (acao === 'totp_confirmar') {
      const t = await totpDe('mestre');
      if (!t) return erro('desligado', 409);
      if (t.ativo) return erro('ja_ativo', 409);
      const passo = await passoDoCodigo(t.segredo, String(corpo.codigo || '').replace(/\s+/g, ''), 0);
      if (passo === null) return erro('codigo', 401);
      const codigos = codigosEmergencia();
      const { error } = await admin.from('acesso_totp').update({ ativo: true, ultimo_passo: passo, ativado_em: new Date().toISOString(),
        recuperacao: await Promise.all(codigos.map((c) => sha256hex(c.replace('-', '')))) }).eq('ref', 'mestre');
      if (error) throw error;
      await aviso('segundo_fator_ligado', 'mestre', '', 'A senha mestre passou a pedir o código do autenticador (ou o rosto).', origem);
      return resposta({ codigos });
    }

    if (acao === 'lista') {
      const { data, error } = await admin.from('acesso_senhas').select('ref, papel, nome, atualizado_em, modulos, biometria').order('ref');
      if (error) throw error;
      const { data: rs } = await admin.from('acesso_biometria').select('ref, criado_em, usado_em');
      const porRef: Record<string, { n: number; usadoEm: string | null }> = {};
      ((rs || []) as { ref: string; usado_em: string | null }[]).forEach((x) => { const p = porRef[x.ref] || (porRef[x.ref] = { n: 0, usadoEm: null }); p.n++; if (x.usado_em && (!p.usadoEm || x.usado_em > p.usadoEm)) p.usadoEm = x.usado_em; });
      const { data: aps } = await admin.from('acesso_aparelhos').select('ref, ultimo_em');
      const apRef: Record<string, { n: number; ultimo: string | null }> = {};
      ((aps || []) as { ref: string; ultimo_em: string }[]).forEach((x) => { const a = apRef[x.ref] || (apRef[x.ref] = { n: 0, ultimo: null }); a.n++; if (!a.ultimo || x.ultimo_em > a.ultimo) a.ultimo = x.ultimo_em; });
      return resposta({ senhas: (data || []).map((l) => ({ ...l, modulos: limparModulos((l as { modulos?: unknown }).modulos),
        rostos: (porRef[(l as { ref: string }).ref] || { n: 0 }).n, rostoUsadoEm: (porRef[(l as { ref: string }).ref] || { usadoEm: null }).usadoEm,
        aparelhos: (apRef[(l as { ref: string }).ref] || { n: 0 }).n, aparelhoUsadoEm: (apRef[(l as { ref: string }).ref] || { ultimo: null }).ultimo })) });
    }

    const ref = String(corpo.ref || '');
    const papel = papelDaRef(ref);
    if (!papel) return erro('dados', 400);

    if (acao === 'sair_aparelhos') {
      const { data: l } = await admin.from('acesso_senhas').select('nome').eq('ref', ref).maybeSingle();
      if (!l) return erro('nao_encontrado', 404);
      await revogar(ref, quem.ref);
      await aviso('sair_aparelhos', ref, String((l as { nome?: string }).nome || ''), 'A senha mestre tirou esta senha de todos os aparelhos (os logins abertos caíram).', origem);
      return resposta({ ok: true, eu: ref === quem.ref });
    }
    if (acao === 'aparelhos') {
      const { data } = await admin.from('acesso_aparelhos').select('descricao, origem, primeiro_em, ultimo_em').eq('ref', ref).order('ultimo_em', { ascending: false }).limit(30);
      return resposta({ aparelhos: data || [] });
    }

    if (acao === 'definir') {
      const senha = String(corpo.senha || '');
      const nome = String(corpo.nome || (papel === 'mestre' ? 'Diretoria' : papel === 'equipe' ? 'Equipe do escritório' : '')).slice(0, 80);
      const individual = ref.startsWith('escritorio:');
      if ((papel === 'motorista' || papel === 'setor' || papel === 'representante' || papel === 'diretoria' || individual) && !String(corpo.nome || '').trim()) return erro('dados', 400);
      const modulos = limparModulos(corpo.modulos);
      if (papel === 'setor' && !modulos.length) return erro('modulos', 400);
      if (papel === 'mestre') {
        const atual = await conferir(String(corpo.senhaAtual || ''), origem);
        if (atual === 'bloqueado') return erro('tentativas', 429);
        if (!atual || atual.ref !== 'mestre') return erro('senha_atual', 403);
      }
      const { data: jaExistia } = await admin.from('acesso_senhas').select('ref').eq('ref', ref).maybeSingle();
      const { error } = await admin.rpc('acesso_definir', { p_ref: ref, p_papel: papel, p_nome: nome, p_senha: senha });
      if (error) {
        const msg = String(error.message || '');
        if (msg.includes('senha em uso')) return erro('senha_em_uso', 409);
        if (msg.includes('senha curta')) return erro('senha_curta', 400);
        if (msg.includes('senha fraca')) return erro('senha_fraca', 400);
        throw error;
      }
      // senha trocada: quem estava com a senha antiga sai de todos os aparelhos
      let revogado = false;
      let sessao: unknown = null;
      if (jaExistia) {
        await revogar(ref, quem.ref); revogado = true;
        await aviso('senha_trocada', ref, nome, 'Senha trocada pela senha mestre: os logins abertos com a senha antiga caíram.', origem);
        // quem trocou a própria senha continua logado neste aparelho (login novo); os outros aparelhos saem
        if (ref === quem.ref) { const l2 = await linhaDe(ref); if (l2) sessao = await sessaoPara({ ref, papel: l2.papel, nome: l2.nome, usuario: null }); }
      }
      if (papel === 'equipe' || papel === 'setor') {
        if (papel === 'setor' || individual || corpo.modulos !== undefined) await gravarModulos(ref, modulos, null);
      }
      if (corpo.biometria !== undefined && ref !== 'mestre') {
        const { error: e2 } = await admin.from('acesso_senhas').update({ biometria: corpo.biometria === true }).eq('ref', ref);
        if (e2) throw e2;
      }
      return resposta({ ok: true, revogado, eu: revogado && ref === quem.ref, sessao });
    }

    if (acao === 'bio_exigir') {
      if (ref === 'mestre') return erro('dados', 400);
      const { data, error } = await admin.from('acesso_senhas').update({ biometria: corpo.exige === true }).eq('ref', ref).select('ref');
      if (error) throw error;
      if (!data || !data.length) return erro('nao_encontrado', 404);
      return resposta({ ok: true });
    }

    if (acao === 'bio_apagar') {
      const { error } = await admin.from('acesso_biometria').delete().eq('ref', ref);
      if (error) throw error;
      await admin.from('acesso_desafios').delete().eq('ref', ref);
      return resposta({ ok: true });
    }

    if (acao === 'ajustar' && papel === 'diretoria') {
      const nome = String(corpo.nome || '').slice(0, 80);
      if (!nome) return erro('dados', 400);
      const mud: Record<string, unknown> = { nome };
      if (corpo.biometria !== undefined) mud.biometria = corpo.biometria === true;
      const { data, error } = await admin.from('acesso_senhas').update(mud).eq('ref', ref).select('ref');
      if (error) throw error;
      if (!data || !data.length) return erro('nao_encontrado', 404);
      return resposta({ ok: true });
    }

    if (acao === 'ajustar') {
      if (papel !== 'equipe' && papel !== 'setor') return erro('dados', 400);
      const modulos = limparModulos(corpo.modulos);
      if (papel === 'setor' && !modulos.length) return erro('modulos', 400);
      const comNome = papel === 'setor' || ref.startsWith('escritorio:');
      const nome = comNome ? String(corpo.nome || '').slice(0, 80) : null;
      if (comNome && !nome) return erro('dados', 400);
      const ok = await gravarModulos(ref, modulos, nome);
      if (!ok) return erro('nao_encontrado', 404);
      return resposta({ ok: true });
    }

    if (acao === 'remover') {
      if (ref === 'mestre') return erro('permissao', 403);
      const { data: linhas, error } = await admin.from('acesso_senhas').delete().eq('ref', ref).select('usuario');
      if (error) throw error;
      const usuario = Array.isArray(linhas) && linhas[0] ? linhas[0].usuario : null;
      if (usuario) await admin.auth.admin.deleteUser(String(usuario)); // quem estava com essa senha sai do app
      return resposta({ ok: true });
    }

    return erro('acao', 400);
  } catch (e) {
    console.error('acesso', acao, e);
    return erro('interno', 500);
  }
});
