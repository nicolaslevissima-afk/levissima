// LEVÍSSIMA · função "backup": entrega os dados para o backup diário (migração 0039).
// Quem chama é só o GitHub Actions do repositório privado levissima-backups, com o token OIDC do próprio GitHub
// (assinado pelo GitHub e válido por poucos minutos). Não existe senha nem chave guardada para isso: a função confere
// a assinatura com as chaves públicas do GitHub e exige o repositório, o ramo e o arquivo do backup certos.
//
// Ações (POST, JSON; cabeçalho Authorization: Bearer <token OIDC do GitHub>):
//   { acao: 'tabelas' }                          -> { tabelas: [nomes] }
//   { acao: 'pagina', tabela, offset }           -> { linhas: [...] }       (até 500 por vez)
//   { acao: 'arquivos', desde? }                 -> { arquivos: [{ bucket, nome, tamanho, atualizado, url }] }
//                                                   (links válidos por 2 horas; sem "desde", todos)
//   { acao: 'concluido', tipo, tag, tamanho, tabelas, linhas, arquivos } -> { ok }   (registra para a senha mestre ver)
import { createClient } from 'npm:@supabase/supabase-js@2';

const URL_SB = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICO = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const EMISSOR = 'https://token.actions.githubusercontent.com';
const PUBLICO = 'levissima-backup';
const REPOSITORIO = 'nicolaslevissima-afk/levissima-backups';
const FLUXO = REPOSITORIO + '/.github/workflows/backup.yml@refs/heads/main';
const POR_PAGINA = 500;

const admin = createClient(URL_SB, SERVICO, { auth: { persistSession: false, autoRefreshToken: false } });

function resposta(corpo: unknown, status = 200) {
  return new Response(JSON.stringify(corpo), { status, headers: { 'Content-Type': 'application/json' } });
}
function erro(codigo: string, status: number) { return resposta({ erro: codigo }, status); }

function b64urlBytes(s: string) {
  const t = s.replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(t + '==='.slice((t.length + 3) % 4));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}
function b64urlJson(s: string) { return JSON.parse(new TextDecoder().decode(b64urlBytes(s))); }

let chaves: { em: number; keys: JsonWebKey[] } | null = null;
async function chavesGithub(forcar = false): Promise<JsonWebKey[]> {
  if (!forcar && chaves && Date.now() - chaves.em < 3600000) return chaves.keys;
  const r = await fetch(EMISSOR + '/.well-known/jwks');
  if (!r.ok) throw new Error('jwks ' + r.status);
  const j = await r.json();
  chaves = { em: Date.now(), keys: (j.keys || []) as JsonWebKey[] };
  return chaves.keys;
}

// confere o token OIDC do GitHub: assinatura RS256, emissor, público, prazo, repositório, ramo e arquivo do fluxo
async function tokenValido(token: string): Promise<boolean> {
  const partes = token.split('.');
  if (partes.length !== 3) return false;
  let cab: Record<string, unknown>, dados: Record<string, unknown>;
  try { cab = b64urlJson(partes[0]); dados = b64urlJson(partes[1]); } catch { return false; }
  if (cab.alg !== 'RS256' || typeof cab.kid !== 'string') return false;
  let lista = await chavesGithub();
  let jwk = lista.find((k) => (k as { kid?: string }).kid === cab.kid);
  if (!jwk) { lista = await chavesGithub(true); jwk = lista.find((k) => (k as { kid?: string }).kid === cab.kid); }
  if (!jwk) return false;
  const chave = await crypto.subtle.importKey('jwk', { kty: 'RSA', n: (jwk as { n: string }).n, e: (jwk as { e: string }).e, alg: 'RS256', ext: true },
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', chave, b64urlBytes(partes[2]), new TextEncoder().encode(partes[0] + '.' + partes[1]));
  if (!ok) return false;
  const agora = Math.floor(Date.now() / 1000);
  const aud = Array.isArray(dados.aud) ? dados.aud : [dados.aud];
  return dados.iss === EMISSOR && aud.includes(PUBLICO)
    && typeof dados.exp === 'number' && dados.exp > agora && typeof dados.nbf === 'number' && dados.nbf <= agora + 60
    && dados.repository === REPOSITORIO && dados.ref === 'refs/heads/main' && dados.workflow_ref === FLUXO;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return erro('metodo', 405);
  const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  try {
    if (!token || !(await tokenValido(token))) return erro('login', 401);
  } catch (e) {
    console.error('backup: token', e);
    return erro('login', 401);
  }
  let corpo: Record<string, unknown>;
  try { corpo = await req.json(); } catch { return erro('dados', 400); }
  const acao = String(corpo.acao || '');
  try {
    if (acao === 'tabelas') {
      const { data, error } = await admin.rpc('backup_tabelas_0039');
      if (error) throw error;
      return resposta({ tabelas: data || [], porPagina: POR_PAGINA });
    }
    if (acao === 'pagina') {
      const { data, error } = await admin.rpc('backup_pagina_0039', { p_tabela: String(corpo.tabela || ''), p_offset: Number(corpo.offset) || 0, p_limite: POR_PAGINA });
      if (error) throw error;
      return resposta({ linhas: data || [] });
    }
    if (acao === 'arquivos') {
      const desde = corpo.desde ? new Date(String(corpo.desde)) : null;
      const { data, error } = await admin.rpc('backup_arquivos_0039', { p_desde: desde && !isNaN(desde.getTime()) ? desde.toISOString() : null });
      if (error) throw error;
      const lista = (data || []) as { bucket: string; nome: string; tamanho: number; atualizado: string }[];
      const porBucket: Record<string, typeof lista> = {};
      lista.forEach((a) => { (porBucket[a.bucket] = porBucket[a.bucket] || []).push(a); });
      const saida: Record<string, unknown>[] = [];
      for (const bucket of Object.keys(porBucket)) {
        const itens = porBucket[bucket];
        for (let i = 0; i < itens.length; i += 200) {
          const lote = itens.slice(i, i + 200);
          const { data: urls, error: e2 } = await admin.storage.from(bucket).createSignedUrls(lote.map((a) => a.nome), 7200);
          if (e2) throw e2;
          lote.forEach((a, j) => { const u = urls && urls[j]; saida.push({ ...a, url: u && u.signedUrl ? u.signedUrl : null }); });
        }
      }
      return resposta({ arquivos: saida });
    }
    if (acao === 'concluido') {
      const n = (v: unknown) => Math.max(0, Math.floor(Number(v) || 0));
      const { error } = await admin.from('backup_execucoes').insert({ tipo: String(corpo.tipo || 'diario').slice(0, 20), tag: String(corpo.tag || '').slice(0, 80),
        tamanho: n(corpo.tamanho), tabelas: n(corpo.tabelas), linhas: n(corpo.linhas), arquivos: n(corpo.arquivos) });
      if (error) throw error;
      // guarda os registros dos últimos 400 dias
      admin.from('backup_execucoes').delete().lt('em', new Date(Date.now() - 400 * 86400000).toISOString()).then(() => {}, () => {});
      return resposta({ ok: true });
    }
    return erro('acao', 400);
  } catch (e) {
    console.error('backup', acao, e);
    return erro('interno', 500);
  }
});
