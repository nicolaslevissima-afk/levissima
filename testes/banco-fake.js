/* LEVÍSSIMA · testes: banco em memória (o "Supabase" dos testes) + servidor do site (www/) + navegador.
 *
 * Uso (Node, com o Playwright instalado):
 *   const amb = await require('./banco-fake').criar();   // sobe o site em http://127.0.0.1:<porta>
 *   const ctx = await amb.contexto();                   // um navegador (cada pessoa num contexto)
 *   const pag = await ctx.newPage(); await pag.goto(amb.url + '/index.html');
 *   ...
 *   await amb.fechar();
 * Senhas de teste (só existem aqui): ver USUARIOS abaixo.
 */
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
let playwright;
try { playwright = require('playwright'); } catch (e) { playwright = require('/opt/npm-tools/node_modules/playwright'); }

const RAIZ = path.resolve(__dirname, '..');
const WWW = path.join(RAIZ, 'www');
const FAKE = fs.readFileSync(path.join(__dirname, 'fake-supabase.js'), 'utf8');

const USUARIOS = [
  { senha: 'teste-nicolas', papel: 'mestre', nome: 'Nicolas Moraes', ref: 'mestre' },
  { senha: 'teste-angelica', papel: 'equipe', nome: 'Angélica Souza', ref: 'escritorio:equipe-angelica' },
  { senha: 'teste-andre', papel: 'equipe', nome: 'André Lima', ref: 'escritorio:equipe-andre' },
  { senha: 'teste-motorista', papel: 'motorista', nome: 'Motorista Teste', ref: 'motorista:teste' }
];

function b64u(o) { return Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); }
function tokenDe(u) {
  return b64u({ alg: 'none', typ: 'JWT' }) + '.' + b64u({ sub: 'uid-' + u.ref.replace(/[^a-z0-9]/gi, ''), role: 'authenticated',
    app_metadata: { papel: u.papel, nome: u.nome, ref: u.ref, modulos: u.modulos || [] } }) + '.teste';
}
function lerToken(t) {
  try { return JSON.parse(Buffer.from(String(t).split('.')[1].replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8')); } catch (e) { return {}; }
}
function copia(v) { return v == null ? v : JSON.parse(JSON.stringify(v)); }

function criarBanco() {
  const b = { docs: new Map(), chat: [], seq: 0, log: [], paginas: new Set() };
  function eventos(table, tipo, novo, velho) {
    for (const p of b.paginas) {
      if (p.isClosed()) { b.paginas.delete(p); continue; }
      p.evaluate(([t, e, n, v]) => window.__fakeEvento && window.__fakeEvento(t, e, n, v), [table, tipo, copia(novo), copia(velho)]).catch(() => {});
    }
  }
  function quem(token) { const c = lerToken(token); const m = c.app_metadata || {}; return { papel: m.papel || '', ref: m.ref || '', nome: m.nome || '' }; }
  function gravarDoc(col, id, dados) {
    const k = col + '/' + id, antes = b.docs.get(k);
    const row = { colecao: col, id, data: dados };
    b.docs.set(k, row);
    eventos('docs', antes ? 'UPDATE' : 'INSERT', row, antes);
    return dados;
  }
  function mesclarCaminhos(base, patch) {
    const out = copia(base || {});
    Object.keys(patch || {}).forEach((k) => {
      const partes = k.split('.'); let o = out;
      for (let i = 0; i < partes.length - 1; i++) { if (!o[partes[i]] || typeof o[partes[i]] !== 'object') o[partes[i]] = {}; o = o[partes[i]]; }
      o[partes[partes.length - 1]] = patch[k];
    });
    return out;
  }
  function docSet(op) {
    const k = op.colecao + '/' + op.id, antes = b.docs.get(k);
    let novo = op.mesclar && antes ? Object.assign({}, antes.data, op.dados) : copia(op.dados || {});
    Object.keys(op.uniao || {}).forEach((c) => {
      const l = Array.isArray(novo[c]) ? novo[c].slice() : [];
      (op.uniao[c] || []).forEach((x) => { if (!l.some((y) => JSON.stringify(y) === JSON.stringify(x))) l.push(x); });
      novo[c] = l;
    });
    return gravarDoc(op.colecao, op.id, novo);
  }
  function erro(e) { return { data: null, erro: e }; }
  function chatPode(eu) { return (eu.papel === 'mestre' || eu.papel === 'equipe') && !!eu.ref; }
  function msgAtual(id) { return b.chat.find((m) => m.id === Number(id)); }
  function atualizarMsg(m, mud) { const velho = copia(m); Object.assign(m, mud); eventos('chat_msgs', 'UPDATE', m, velho); return copia(m); }
  function novaMsg(dados) {
    const m = Object.assign({ id: ++b.seq, criado_em: new Date().toISOString(), lida: false, lida_em: null, resolvido: null, resolvido_em: null,
      apagada: false, apagada_em: null, apagada_por: null, editada_em: null, reacoes: {} }, dados);
    b.chat.push(m); eventos('chat_msgs', 'INSERT', m, null); return copia(m);
  }
  // mesmas regras das funções do banco (0019, 0023, 0025)
  const RPC = {
    doc_gravar: (p) => ({ data: docSet({ colecao: p.p_colecao, id: p.p_id, dados: p.p_dados, mesclar: p.p_mesclar, uniao: p.p_uniao }) }),
    doc_atualizar: (p) => { const a = b.docs.get(p.p_colecao + '/' + p.p_id); return { data: gravarDoc(p.p_colecao, p.p_id, mesclarCaminhos(a ? a.data : {}, p.p_dados)) }; },
    docs_lote: (p) => ({ data: (p.p_ops || []).map((o) => {
      if (o.op === 'delete') { const k = o.colecao + '/' + o.id, a = b.docs.get(k); b.docs.delete(k); if (a) eventos('docs', 'DELETE', null, a); return { colecao: o.colecao, id: o.id, data: null }; }
      if (o.op === 'update') { const a = b.docs.get(o.colecao + '/' + o.id); return { colecao: o.colecao, id: o.id, data: gravarDoc(o.colecao, o.id, mesclarCaminhos(a ? a.data : {}, o.dados)) }; }
      return { colecao: o.colecao, id: o.id, data: docSet(o) };
    }) }),
    chat_pessoas: (p, eu) => chatPode(eu) ? { data: USUARIOS.filter((u) => (u.papel === 'mestre' || u.papel === 'equipe') && u.ref !== eu.ref).map((u) => ({ ref: u.ref, nome: u.nome })) } : erro('permissao'),
    chat_enviar: (p, eu) => {
      if (!chatPode(eu)) return erro('permissao');
      const t = String(p.p_texto || '').trim(); if (!t) return erro('texto');
      if (!USUARIOS.some((u) => u.ref === p.p_para) || p.p_para === eu.ref) return erro('destino');
      return { data: novaMsg({ tipo: 'chat', conversa: [eu.ref, p.p_para].sort().join('|'), de: eu.ref, de_nome: eu.nome, para: p.p_para, texto: t }) };
    },
    sol_enviar: (p, eu) => {
      if (!chatPode(eu)) return erro('permissao');
      const t = String(p.p_texto || '').trim(); if (!t) return erro('texto');
      if (eu.ref === 'mestre') return { data: novaMsg({ tipo: 'sol', conversa: p.p_conversa, de: 'mestre', de_nome: eu.nome, para: p.p_conversa, texto: t }) };
      return { data: novaMsg({ tipo: 'sol', conversa: eu.ref, de: eu.ref, de_nome: eu.nome, para: 'mestre', texto: t }) };
    },
    chat_lidas: (p, eu) => { let n = 0; b.chat.forEach((m) => { if (m.para === eu.ref && m.tipo === p.p_tipo && m.conversa === p.p_conversa && !m.lida) { atualizarMsg(m, { lida: true, lida_em: new Date().toISOString() }); n++; } }); return { data: n }; },
    sol_resolvido: (p, eu) => { const m = msgAtual(p.p_id); if (!m || m.tipo !== 'sol' || m.de !== 'mestre' || !(m.para === eu.ref || eu.ref === 'mestre')) return erro('permissao'); return { data: atualizarMsg(m, { resolvido: p.p_resolvido, resolvido_em: new Date().toISOString() }) }; },
    chat_apagar: (p, eu) => {
      if (!chatPode(eu)) return erro('permissao');
      const m = msgAtual(p.p_id); if (!m || !(m.de === eu.ref || m.para === eu.ref)) return erro('permissao');
      if (m.apagada) return { data: copia(m) };
      if (!(eu.ref === 'mestre' || m.de === eu.ref)) return erro('permissao');
      return { data: atualizarMsg(m, { apagada: true, apagada_em: new Date().toISOString(), apagada_por: eu.ref, texto: '(mensagem apagada)', lida: true, resolvido: null, reacoes: {} }) };
    },
    chat_editar: (p, eu) => {
      if (!chatPode(eu)) return erro('permissao');
      const t = String(p.p_texto || '').trim(); if (!t) return erro('texto');
      const m = msgAtual(p.p_id); if (!m || m.de !== eu.ref) return erro('permissao');
      if (m.apagada) return erro('apagada');
      if (m.texto === t) return { data: copia(m) };
      return { data: atualizarMsg(m, { texto: t, editada_em: new Date().toISOString() }) };
    },
    chat_reagir: (p, eu) => {
      if (!chatPode(eu)) return erro('permissao');
      const r = p.p_reacao == null ? null : String(p.p_reacao).trim() || null;
      if (r && r !== '👍' && r !== '👎') return erro('reacao');
      const m = msgAtual(p.p_id); if (!m || m.tipo !== 'chat' || !(m.de === eu.ref || m.para === eu.ref)) return erro('permissao');
      if (m.apagada) return erro('apagada');
      const reacoes = Object.assign({}, m.reacoes); if (r) reacoes[eu.ref] = r; else delete reacoes[eu.ref];
      return { data: atualizarMsg(m, { reacoes }) };
    },
    postit_gravar: (p) => ({ data: { texto: p.p_texto } })
  };
  function handle(source, op, args) {
    args = args || {};
    if (source && source.page) b.paginas.add(source.page);
    if (op === 'log') { b.log.push(Object.assign({ em: Date.now() }, args)); return { data: null }; }
    if (op === 'fn') {
      if (args.nome !== 'acesso') return erro('interno');
      const body = args.body || {};
      if (body.acao === 'entrar') { const u = USUARIOS.find((x) => x.senha === body.senha); return u ? { data: { access_token: tokenDe(u), refresh_token: 'r-' + u.ref } } : erro('senha'); }
      if (body.acao === 'lista') return { data: { senhas: USUARIOS.filter((u) => u.papel !== 'motorista').map((u) => ({ ref: u.ref, nome: u.nome, papel: u.papel, modulos: u.modulos || [] })) } };
      return erro('interno');
    }
    const eu = quem(args.token);
    if (op === 'rpc') { const f = RPC[args.nome]; if (!eu.papel) return erro('permissao'); return f ? f(args.params || {}, eu) : { data: null }; }
    if (op === 'from') {
      const q = args.q;
      if (!eu.papel) return { data: q.single ? null : [], erro: null };
      let rows;
      if (q.table === 'docs') rows = Array.from(b.docs.values());
      else if (q.table === 'chat_msgs') rows = b.chat.filter((m) => chatPode(eu) && (m.de === eu.ref || m.para === eu.ref));
      else rows = [];
      q.filtros.forEach(([c, v]) => { rows = rows.filter((r) => r[c] === v); });
      if (q.op === 'delete') { rows.forEach((r) => { if (q.table === 'docs') { b.docs.delete(r.colecao + '/' + r.id); eventos('docs', 'DELETE', null, r); } }); return { data: null }; }
      if (q.ordem) { const [c, asc] = q.ordem; rows = rows.slice().sort((x, y) => (x[c] > y[c] ? 1 : x[c] < y[c] ? -1 : 0) * (asc ? 1 : -1)); }
      if (q.faixa) rows = rows.slice(q.faixa[0], q.faixa[1] + 1);
      rows = copia(rows);
      return { data: q.single ? (rows[0] || null) : rows };
    }
    return { data: null };
  }
  return { b, handle, eventos };
}

function servidor() {
  const tipos = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.json': 'application/json', '.webmanifest': 'application/manifest+json' };
  const srv = http.createServer((req, res) => {
    let u = decodeURIComponent(req.url.split('?')[0].split('#')[0]);
    if (u.endsWith('/')) u += 'index.html';
    const f = path.join(WWW, path.normalize(u));
    if (!f.startsWith(WWW) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); res.end('não achou'); return; }
    res.writeHead(200, { 'Content-Type': tipos[path.extname(f)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    fs.createReadStream(f).pipe(res);
  });
  return new Promise((ok) => srv.listen(0, '127.0.0.1', () => ok(srv)));
}

async function criar(opcoes) {
  opcoes = opcoes || {};
  const banco = criarBanco();
  const srv = await servidor();
  const url = 'http://127.0.0.1:' + srv.address().port;
  const navegador = await playwright.chromium.launch();
  const erros = [];
  async function contexto(extra) {
    const ctx = await navegador.newContext(Object.assign({ serviceWorkers: 'block', viewport: { width: 420, height: 860 }, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' }, extra || {}));
    await ctx.exposeBinding('__fakeDb', (source, op, args) => banco.handle(source, op, args));
    await ctx.route(/^https?:\/\/(?!127\.0\.0\.1)/, (route) => {
      const r = route.request().url();
      if (/supabase-js@[^/]+\/dist\/umd\/supabase\.js/.test(r)) return route.fulfill({ status: 200, contentType: 'text/javascript', body: FAKE });
      return route.abort();
    });
    ctx.on('page', (p) => {
      p.on('pageerror', (e) => erros.push('pageerror: ' + e.message));
      p.on('console', (m) => { if (m.type() === 'error' && !/net::ERR_FAILED|Failed to load resource|ERR_BLOCKED/.test(m.text())) erros.push('console: ' + m.text()); });
    });
    return ctx;
  }
  async function fechar() { await navegador.close(); await new Promise((ok) => srv.close(ok)); }
  return { url, banco, contexto, fechar, erros, USUARIOS };
}

module.exports = { criar, USUARIOS };
