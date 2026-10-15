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
// Senhas: 'mestre' (tudo), 'equipe' (escritório de cargas + módulos marcados), 'motorista:<id>' (app do motorista)
// 'setor:<id>' (só os módulos marcados: Manutenção, Empilhadeiras, Uniformes e EPI, Garrafões)
// e 'representante:<id>' (Força de vendas: lança as cargas dos clientes dele; regras em 0005_forca_de_vendas.sql).
// Cada módulo pode ser "usado" ('manutencao') ou "gerenciado" ('manutencao:gerir').
import { createClient } from 'npm:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICO = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const DOMINIO = 'acesso.levissima.app.br'; // só identifica os logins internos; nenhum e-mail é enviado

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

const MODULOS = ['manutencao', 'empilhadeiras', 'uniformes', 'garrafoes'];

function papelDaRef(ref: string): string | null {
  if (ref === 'mestre') return 'mestre';
  if (ref === 'equipe') return 'equipe';
  if (/^motorista:[A-Za-z0-9_-]{1,64}$/.test(ref)) return 'motorista';
  if (/^setor:[A-Za-z0-9_-]{1,64}$/.test(ref)) return 'setor';
  if (/^representante:[A-Za-z0-9_-]{1,64}$/.test(ref)) return 'representante';
  return null;
}

// Lista de módulos válida: só os conhecidos, "usar" ou "gerir", sem repetir (gerir vale mais que usar).
function limparModulos(v: unknown): string[] {
  const lista = Array.isArray(v) ? v.map((x) => String(x)) : [];
  const nivel = new Map<string, string>();
  for (const item of lista) {
    const [m, g] = item.split(':');
    if (!MODULOS.includes(m) || (g !== undefined && g !== 'gerir')) continue;
    if (g === 'gerir' || !nivel.has(m)) nivel.set(m, g === 'gerir' ? m + ':gerir' : m);
  }
  return MODULOS.filter((m) => nivel.has(m)).map((m) => nivel.get(m) as string);
}

async function modulosDe(ref: string): Promise<string[]> {
  const { data } = await admin.from('acesso_senhas').select('modulos').eq('ref', ref).maybeSingle();
  return limparModulos(data && (data as { modulos?: unknown }).modulos);
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
  const modulos = id.papel === 'equipe' || id.papel === 'setor' ? await modulosDe(id.ref) : [];
  const meta = { papel: id.papel, nome: id.nome, ref: id.ref, modulos };
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
  return { access_token: data.session.access_token, refresh_token: data.session.refresh_token, papel: id.papel, nome: id.nome, modulos };
}

// Grava os módulos (e o nome) de uma senha e já atualiza o login ligado a ela: vale no próximo acesso
// e, para quem está com o app aberto, na próxima renovação do login (até 1 hora).
async function gravarModulos(ref: string, modulos: string[], nome: string | null): Promise<boolean> {
  const mud: Record<string, unknown> = { modulos };
  if (nome !== null) mud.nome = nome;
  const { data, error } = await admin.from('acesso_senhas').update(mud).eq('ref', ref).select('papel, nome, usuario');
  if (error) throw error;
  const linha = Array.isArray(data) ? data[0] : null;
  if (!linha) return false;
  if (linha.usuario) {
    await admin.auth.admin.updateUserById(String(linha.usuario), { app_metadata: { papel: linha.papel, nome: linha.nome, ref, modulos } });
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

async function quemChamou(req: Request): Promise<{ papel: string; ref: string } | null> {
  const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!token || token.split('.').length !== 3) return null;
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) return null;
  const m = (data.user.app_metadata || {}) as Record<string, string>;
  return m.papel ? { papel: m.papel, ref: m.ref || '' } : null;
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
      const senha = String(corpo.senha || '');
      if (!senha || senha.length > 200) return erro('senha', 401);
      const id = await conferir(senha, origem);
      if (id === 'bloqueado') return erro('tentativas', 429);
      if (!id) return erro('senha', 401);
      return resposta(await sessaoPara(id));
    }

    const quem = await quemChamou(req);
    if (!quem) return erro('login', 401);

    if (acao === 'conferir') {
      const id = await conferir(String(corpo.senha || ''), origem);
      if (id === 'bloqueado') return erro('tentativas', 429);
      return resposta({ ok: !!id && id.ref === quem.ref, papel: id && id !== 'bloqueado' && id.ref === quem.ref ? id.papel : null });
    }

    if (quem.papel !== 'mestre') return erro('permissao', 403);

    if (acao === 'lista') {
      const { data, error } = await admin.from('acesso_senhas').select('ref, papel, nome, atualizado_em, modulos').order('ref');
      if (error) throw error;
      return resposta({ senhas: (data || []).map((l) => ({ ...l, modulos: limparModulos((l as { modulos?: unknown }).modulos) })) });
    }

    const ref = String(corpo.ref || '');
    const papel = papelDaRef(ref);
    if (!papel) return erro('dados', 400);

    if (acao === 'definir') {
      const senha = String(corpo.senha || '');
      const nome = String(corpo.nome || (papel === 'mestre' ? 'Diretoria' : papel === 'equipe' ? 'Equipe do escritório' : '')).slice(0, 80);
      if ((papel === 'motorista' || papel === 'setor' || papel === 'representante') && !nome) return erro('dados', 400);
      const modulos = limparModulos(corpo.modulos);
      if (papel === 'setor' && !modulos.length) return erro('modulos', 400);
      if (papel === 'mestre') {
        const atual = await conferir(String(corpo.senhaAtual || ''), origem);
        if (atual === 'bloqueado') return erro('tentativas', 429);
        if (!atual || atual.ref !== 'mestre') return erro('senha_atual', 403);
      }
      const { error } = await admin.rpc('acesso_definir', { p_ref: ref, p_papel: papel, p_nome: nome, p_senha: senha });
      if (error) {
        const msg = String(error.message || '');
        if (msg.includes('senha em uso')) return erro('senha_em_uso', 409);
        if (msg.includes('senha curta')) return erro('senha_curta', 400);
        throw error;
      }
      if (papel === 'equipe' || papel === 'setor') {
        if (papel === 'setor' || corpo.modulos !== undefined) await gravarModulos(ref, modulos, null);
      }
      return resposta({ ok: true });
    }

    if (acao === 'ajustar') {
      if (papel !== 'equipe' && papel !== 'setor') return erro('dados', 400);
      const modulos = limparModulos(corpo.modulos);
      if (papel === 'setor' && !modulos.length) return erro('modulos', 400);
      const nome = papel === 'setor' ? String(corpo.nome || '').slice(0, 80) : null;
      if (papel === 'setor' && !nome) return erro('dados', 400);
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
