/* LEVÍSSIMA · teste: módulo Garrafões refeito (pedido de 17/11/2026), no celular, contra as funções reais da 0056.
 * Usa um Postgres local (sem Supabase): a página do módulo roda no Chromium com uma "ponte" de teste que chama as
 * funções do banco como o usuário logado (claims do JWT), e lê modulo_docs com as regras de leitura (RLS).
 * Confere: perfis (consulta, entradas, entregas, gestão), contagem inicial com lote encontrado, entrada (lote novo e
 * existente, fabricação diferente), clique duplo sem duplicar, saída dividida por lote com sugestão do que vence
 * primeiro, troca com dois fabricantes e motivos (5:1 só sugestão), retirada com contrapartida, recebimento vinculado,
 * exclusão (efeitos, conjunto, bloqueio de negativo), exportação CSV, parâmetros e tela sem rolagem lateral.
 * Rodar (com Postgres local em PGHOST/PGPORT, usuário postgres):
 *   python3 ferramentas/construir.py --modulos && node testes/garrafoes-e2e.js
 */
'use strict';
const path = require('path');
const fs = require('fs');
const http = require('http');
const { execFileSync } = require('child_process');
const { chromium, devices } = require('playwright');

const PGHOST = process.env.PGHOST || '/var/tmp/pgtest', PGPORT = process.env.PGPORT || '55432', BANCO = 'garrafoes_e2e';
const RAIZ = path.join(__dirname, '..');
const SHOTS = process.env.SHOTS || path.join(__dirname, 'shots');
fs.mkdirSync(SHOTS, { recursive: true });
let passou = 0, falhou = 0;
function ok(c, msg) { if (c) { passou++; console.log('  ✓ ' + msg); } else { falhou++; console.log('  ✗ FALHOU: ' + msg); } }

function psql(db, sql, vars) {
  const args = ['-h', PGHOST, '-p', PGPORT, '-U', 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1', '-At', '-q'];
  Object.keys(vars || {}).forEach((k) => args.push('-v', k + '=' + vars[k]));
  try { return { saida: execFileSync('psql', args, { input: sql, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim() }; }
  catch (e) { const m = /ERROR:\s+(.*)/.exec(String(e.stderr || '')); return { erro: m ? m[1].trim() : String(e.stderr || e.message) }; }
}
const ACESSOS = {
  gestora: { papel: 'equipe', ref: 'escritorio:gestora', nome: 'Gestora Teste', modulos: ['garrafoes:gerir', 'abas'] },
  conta: { papel: 'equipe', ref: 'escritorio:conta', nome: 'Contagem Teste', modulos: ['garrafoes', 'abas'] },
  entrega: { papel: 'equipe', ref: 'escritorio:entrega', nome: 'Entregas Teste', modulos: ['garrafoes', 'abas'] }
};
let quem = 'conta';
function claims() { return JSON.stringify({ app_metadata: ACESSOS[quem] }); }
function comoUsuario(sql, vars) {
  return psql(BANCO, "set role authenticated;\nselect set_config('request.jwt.claims', :'claims', false) \\g /dev/null\n" + sql, Object.assign({ claims: claims() }, vars || {}));
}

// ponte de teste: o mesmo contrato que o módulo usa da ponte.js (db, user, downloads)
const PONTE = `(function(){
  var subs = [];
  function snapCol(rows){ return { empty: !rows.length, docs: rows.map(function(r){ return { id: r.id, data: function(){ return JSON.parse(JSON.stringify(r.dados)); } }; }) }; }
  function entregar(s, json){ if (json === s.ultimo) return; s.ultimo = json; var rows = JSON.parse(json);
    if (s.id) s.cb({ exists: rows.length > 0, id: s.id, data: function(){ return rows[0] ? rows[0].dados : undefined; } }); else s.cb(snapCol(rows)); }
  function ler(s){ return window.__pgLer(s.caminho, s.id || '').then(function(j){ entregar(s, j); }); }
  setInterval(function(){ subs.forEach(ler); }, 300);
  function chk(r){ r = JSON.parse(r); if (r.erro) throw { code: 'internal', message: r.erro }; return r.dados; }
  function colRef(c){ return { onSnapshot: function(cb){ var s = { caminho: c, cb: cb }; subs.push(s); ler(s); return function(){}; },
    get: function(){ return window.__pgLer(c, '').then(function(j){ return snapCol(JSON.parse(j)); }); } }; }
  function docRef(p){ var i = p.lastIndexOf('/'), c = p.slice(0, i), id = p.slice(i + 1);
    return { onSnapshot: function(cb){ var s = { caminho: c, id: id, cb: cb }; subs.push(s); ler(s); return function(){}; },
      set: function(d, o){ return window.__pgSet(c, id, JSON.stringify(d), !!(o && o.merge)).then(chk); } }; }
  var db = { collection: colRef, doc: docRef, rpc: function(n, p){ return window.__pgRpc(n, JSON.stringify(p || {})).then(chk); } };
  var user = { nome: function(){ return window.__pgNome(); }, nivel: function(){ return Promise.resolve('usar'); } };
  window.claude = { use: function(n){ return Promise.resolve(n === 'db' ? db : n === 'user' ? user : n === 'downloads' ? { save: function(o){ window.__baixados = (window.__baixados || []).concat([o]); return Promise.resolve(); } } : null); } };
})();`;

function rpc(nome, p) {
  let sql;
  if (nome === 'garrafoes_registrar') sql = "select public.garrafoes_registrar(:'p'::jsonb);";
  else if (nome === 'garrafoes_excluir') sql = "select public.garrafoes_excluir(:'id', nullif(:'mot', ''), :'conj'::boolean);";
  else if (nome === 'garrafoes_perfil_definir') sql = "select public.garrafoes_perfil_definir(:'r', :'pf');";
  else if (nome === 'garrafoes_eu' || nome === 'garrafoes_acessos') sql = 'select public.' + nome + '();';
  else return { erro: 'função desconhecida no teste: ' + nome };
  const r = comoUsuario(sql, { p: JSON.stringify(p.p || {}), id: p.p_id || '', mot: p.p_motivo || '', conj: String(!!p.p_conjunto), r: p.p_ref || '', pf: p.p_perfil || '' });
  return r.erro ? { erro: r.erro } : { dados: JSON.parse(r.saida) };
}
function ler(caminho, id) {
  const r = comoUsuario("select coalesce(json_agg(json_build_object('id', id, 'dados', dados) order by id), '[]') from public.modulo_docs where modulo = 'garrafoes' and caminho = :'c' and (:'i' = '' or id = :'i');", { c: caminho, i: id });
  return r.erro ? '[]' : r.saida;
}
function setDoc(caminho, id, dados, merge) {
  const r = comoUsuario("insert into public.modulo_docs (modulo, caminho, id, dados) values ('garrafoes', :'c', :'i', :'d'::jsonb) on conflict (modulo, caminho, id) do update set dados = " + (merge ? 'public.modulo_docs.dados || excluded.dados' : 'excluded.dados') + ', atualizado_em = now() returning dados;', { c: caminho, i: id, d: dados });
  return r.erro ? { erro: r.erro } : { dados: JSON.parse(r.saida || '{}') };
}
function saldos(modelo) { return JSON.parse(psql(BANCO, "select public.garrafoes_saldos_0056(:'m');", { m: modelo }).saida); }
function lote(modelo, marca, cod) { return 'lt-' + require('crypto').createHash('md5').update(modelo + '|' + marca + '|' + cod).digest('hex'); }
function contar(sql) { return Number(psql(BANCO, sql).saida); }

(async () => {
  // banco do teste: simulação do Supabase + a migração 0056
  psql('postgres', 'drop database if exists ' + BANCO + ';');
  psql('postgres', 'create database ' + BANCO + ';');
  for (const f of ['testes/garrafoes-banco.sql', 'supabase/migrations/0056_garrafoes_estoque.sql']) {
    const r = psql(BANCO, fs.readFileSync(path.join(RAIZ, f), 'utf8'));
    if (r.erro) { console.error('banco:', f, r.erro); process.exit(1); }
  }
  psql(BANCO, "delete from public.acesso_senhas; insert into public.acesso_senhas (ref, papel, nome, modulos) values ('escritorio:gestora','equipe','Gestora Teste','{garrafoes:gerir,abas}'), ('escritorio:conta','equipe','Contagem Teste','{garrafoes,abas}'), ('escritorio:entrega','equipe','Entregas Teste','{garrafoes,abas}');");

  const srv = http.createServer((req, res) => {
    const f = path.join(RAIZ, 'www', decodeURIComponent(req.url.split('?')[0]));
    fs.readFile(f, (e, d) => { if (e) { res.writeHead(404); res.end(); return; } res.writeHead(200, { 'content-type': f.endsWith('.html') ? 'text/html; charset=utf-8' : 'application/octet-stream' }); res.end(d); });
  }).listen(0, '127.0.0.1');
  await new Promise((r) => srv.on('listening', r));
  const URL_ = 'http://127.0.0.1:' + srv.address().port + '/modulos/garrafoes.html';

  const browser = await chromium.launch();
  const ctx = await browser.newContext(Object.assign({}, devices['Pixel 5'], { locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' }));
  await ctx.route('**/*', (route) => {
    const u = route.request().url();
    if (u.endsWith('/modulos/ponte.js')) return route.fulfill({ status: 200, contentType: 'application/javascript', body: PONTE });
    if (!u.startsWith('http://127.0.0.1')) return route.abort();
    return route.continue();
  });
  await ctx.exposeFunction('__pgRpc', (n, p) => JSON.stringify(rpc(n, JSON.parse(p))));
  await ctx.exposeFunction('__pgLer', (c, i) => ler(c, i));
  await ctx.exposeFunction('__pgSet', (c, i, d, m) => JSON.stringify(setDoc(c, i, d, m)));
  await ctx.exposeFunction('__pgNome', () => ACESSOS[quem].nome);
  const page = await ctx.newPage();
  const errosJs = [];
  page.on('pageerror', (e) => errosJs.push(String(e)));
  async function abrirComo(q) { quem = q; await page.goto(URL_); await page.waitForSelector('#area-topo', { timeout: 8000 }); }
  async function esperarTexto(sel, txt, ms) { await page.waitForFunction(([s, t]) => { const e = document.querySelector(s); return e && e.textContent.indexOf(t) >= 0; }, [sel, txt], { timeout: ms || 6000 }); }
  async function campo(f, v) { await page.fill('[data-f="' + f + '"]', String(v)); }
  async function escolher(f, v) { await page.selectOption('[data-f="' + f + '"]', v); }
  async function revisarConfirmar() {
    await page.click('[data-act="revisar"]');
    await page.waitForSelector('[data-act="confirmar"]', { timeout: 4000 });
    await page.click('[data-act="confirmar"]');
    await page.waitForFunction(() => !document.querySelector('[data-act="confirmar"]'), null, { timeout: 8000 });
  }
  async function semRolagemLateral(rotulo) { const r = await page.evaluate(() => [document.documentElement.scrollWidth, window.innerWidth]); ok(r[0] <= r[1] + 1, 'sem rolagem lateral no celular: ' + rotulo + ' (' + r[0] + ' ≤ ' + r[1] + ')'); }
  const hoje = new Date(Date.now() - 3 * 3600e3).toISOString().slice(0, 10);

  try {
    console.log('Perfis');
    await abrirComo('conta');
    ok(await page.locator('.so-consulta').count() === 1, 'acesso sem perfil escolhido fica só com consulta');
    ok(await page.locator('[data-act="abrir"]').count() === 0, 'consulta não vê botões de registro');
    ok(await page.locator('[data-aba="config"]').count() === 0, 'consulta não vê a aba Gestão');
    await semRolagemLateral('consulta');

    await abrirComo('gestora');
    ok(await page.locator('[data-act="abrir"]').count() === 5, 'gestão vê as 5 operações');
    await page.click('[data-aba="config"]');
    await page.waitForSelector('[data-perfil-ref="escritorio:conta"]');
    await page.selectOption('[data-perfil-ref="escritorio:conta"]', 'entradas');
    await esperarTexto('#toast', 'Perfil atualizado');
    await page.selectOption('[data-perfil-ref="escritorio:entrega"]', 'entregas');
    await page.waitForFunction(() => document.querySelector('#toast').textContent.indexOf('Entregas') >= 0);
    ok(/Gestão/.test(await page.textContent('.perfil-l:has-text("Gestora Teste")')), 'quem tem "Gerencia" aparece como Gestão (definido em Cadastros)');
    await semRolagemLateral('gestão');

    console.log('Contagem inicial (perfil Contagem e entradas)');
    await abrirComo('conta');
    const botoesConta = await page.$$eval('[data-act="abrir"]', (b) => b.map((x) => x.dataset.tipo));
    ok(botoesConta.join(',') === 'entrada,contagem', 'contagem e entradas: só entrada de novos e contagem física (' + botoesConta + ')');
    await page.click('[data-act="abrir"][data-tipo="contagem"]');
    await page.click('[data-seg="alvo"][data-v="novos"]');
    await page.click('[data-act="mais"][data-lista="achados"]');
    await escolher('achados.0.marca', 'AGS');
    await campo('achados.0.codigo', 'l-100');
    await campo('achados.0.fabricacao', '2026-09');
    await campo('achados.0.contado', '200');
    await page.click('[data-act="revisar"]');
    ok(/justificativa/i.test(await page.textContent('#painel-form .erro-caixa')), 'contagem com diferença pede justificativa');
    await campo('just', 'Saldo inicial pela contagem do depósito');
    await page.click('[data-act="revisar"]');
    const resumoCont = await page.textContent('.resumo');
    ok(/Registrado/.test(resumoCont) && /ajuste de \+200/.test(resumoCont), 'resumo da contagem mostra registrado, contado, diferença e efeito');
    await page.click('[data-act="confirmar"]');
    await page.waitForFunction(() => !document.querySelector('[data-act="confirmar"]'));
    await esperarTexto('#area-topo', '200');
    ok(saldos('20L')['N|' + lote('20L', 'AGS', 'L-100')] === 200, 'contagem criou o lote L-100 (AGS) com 200 no banco');

    await page.click('[data-act="abrir"][data-tipo="contagem"]');
    await page.click('[data-seg="alvo"][data-v="sucata"]');
    await campo('contado.S|AGS', '91');
    await campo('contado.S|Montico', '0');
    await campo('just', 'Contagem do pátio de sucata');
    await revisarConfirmar();
    ok(saldos('20L')['S|AGS'] === 91 && saldos('20L')['S|Montico'] === 0, 'contagem da sucata por fabricante (zero permitido)');

    console.log('Entrada de novos');
    await page.click('[data-act="abrir"][data-tipo="entrada"]');
    await page.click('[data-seg="marca"][data-v="Montico"]');
    await campo('codigo', 'M-7');
    await campo('fabricacao', '2026-10');
    await campo('qtd', '100');
    await page.click('[data-act="revisar"]');
    ok(/Lote novo/.test(await page.textContent('.resumo')) && /validade 10\/2029/.test(await page.textContent('.resumo')), 'resumo da entrada com validade calculada (3 anos)');
    await page.dblclick('[data-act="confirmar"]');
    await page.waitForFunction(() => !document.querySelector('[data-act="confirmar"]'));
    await page.waitForTimeout(500);
    ok(contar("select count(*) from modulo_docs where caminho='g-ops' and dados->>'tipo'='entrada'") === 1, 'clique duplo no confirmar não duplica a entrada');
    // mesmo lote: fabricação travada; fabricação diferente recusada
    await page.click('[data-act="abrir"][data-tipo="entrada"]');
    await page.click('[data-seg="marca"][data-v="Montico"]');
    await campo('codigo', 'm-7');
    ok(await page.$eval('[data-f="fabricacao"]', (e) => e.readOnly && e.value === '2026-10'), 'lote já cadastrado: fabricação preenchida e travada');
    ok(/já cadastrado/.test(await page.textContent('#d-lote')), 'avisa que o lote já existe e mostra o saldo');
    await campo('qtd', '20');
    await revisarConfirmar();
    ok(saldos('20L')['N|' + lote('20L', 'Montico', 'M-7')] === 120 && contar("select count(*) from modulo_docs where caminho='g-lotes'") === 2, 'nova entrada no mesmo lote soma sem duplicar o cadastro');
    ok(await page.locator('[data-act="abrir"][data-tipo="saida"]').count() === 0, 'contagem e entradas não registra saída');

    console.log('Saída, troca e retirada (perfil Entregas)');
    await abrirComo('entrega');
    const botoesEnt = await page.$$eval('[data-act="abrir"]', (b) => b.map((x) => x.dataset.tipo));
    ok(botoesEnt.join(',') === 'saida,troca,retirada', 'entregas: saída, troca e retirada (' + botoesEnt + ')');
    // segundo lote AGS mais novo, para a sugestão
    quem = 'conta'; rpc('garrafoes_registrar', { p: { id: 'op-TESTEAGS00000001', tipo: 'entrada', modelo: '20L', data: hoje, linhas: [{ marca: 'AGS', codigo: 'L-200', fabricacao: '2026-11', qtd: 50 }] } }); quem = 'entrega';
    await page.waitForTimeout(700);
    await page.click('[data-act="abrir"][data-tipo="saida"]');
    await page.click('[data-seg="marca"][data-v="AGS"]');
    const sug = await page.textContent('.tlotes tr.sug');
    ok(/L-100/.test(sug) && /vence primeiro/.test(sug), 'saída sugere o lote que vence primeiro (L-100)');
    await campo('saida.' + lote('20L', 'AGS', 'L-100'), '30');
    await campo('saida.' + lote('20L', 'AGS', 'L-200'), '5');
    ok(/35 unidades/.test(await page.textContent('#d-total')), 'total da saída dividida entre lotes antes de confirmar');
    await revisarConfirmar();
    ok(saldos('20L')['N|' + lote('20L', 'AGS', 'L-100')] === 170 && saldos('20L')['N|' + lote('20L', 'AGS', 'L-200')] === 45, 'baixa exatamente nos lotes escolhidos');
    // saída acima do disponível
    await page.click('[data-act="abrir"][data-tipo="saida"]');
    await page.click('[data-seg="marca"][data-v="AGS"]');
    await campo('saida.' + lote('20L', 'AGS', 'L-200'), '46');
    await page.click('[data-act="revisar"]');
    ok(/45 unidades disponível/.test(await page.textContent('#painel-form .erro-caixa')), 'saída acima do saldo do lote é recusada');
    await page.click('[data-act="fechar"]');

    await page.click('[data-act="abrir"][data-tipo="troca"]');
    await campo('cliente', 'Mercado Bom Preço');
    await campo('total', '27');
    ok(await page.$eval('[data-f="sucata.0.qtd"]', (e) => e.value) === '27', 'uma linha de sucata acompanha o total');
    await escolher('sucata.0.fabricante', 'AGS');
    await escolher('sucata.0.motivo', 'Vencido');
    await campo('sucata.0.qtd', '20');
    await page.click('[data-act="mais"][data-lista="sucata"]');
    await escolher('sucata.1.fabricante', 'Montico');
    await escolher('sucata.1.motivo', 'Outro');
    await campo('sucata.1.desc', 'Rótulo derretido');
    await campo('sucata.1.qtd', '7');
    ok(/27 de 27/.test(await page.textContent('#d-soma')), 'soma dos motivos confere com o total');
    ok(/5,4/.test(await page.textContent('#d-sugestao')) && await page.locator('[data-act="usar-sugestao"]').count() === 0, 'proporção 5:1 não exata: só informa, não arredonda');
    await escolher('novos.0.marca', 'Montico');
    ok(await page.$eval('[data-f="novos.0.lote"]', (e) => e.value) === lote('20L', 'Montico', 'M-7'), 'ao escolher a marca dos novos, sugere o lote que vence primeiro');
    await campo('novos.0.qtd', '5');
    await page.screenshot({ path: path.join(SHOTS, 'garrafoes-troca.png'), fullPage: true });
    await page.click('[data-act="revisar"]');
    const resumoTroca = await page.textContent('.resumo');
    ok(/Recebimento: 20 sucatas AGS e 7 sucatas Montico de 20 L/.test(resumoTroca) && /Entrega: 5 unidades Montico, lote M-7/.test(resumoTroca), 'resumo da troca: fabricante da sucata e marca do novo independentes');
    await page.click('[data-act="confirmar"]');
    await page.waitForFunction(() => !document.querySelector('[data-act="confirmar"]'));
    let s20 = saldos('20L');
    ok(s20['S|AGS'] === 111 && s20['S|Montico'] === 7 && s20['N|' + lote('20L', 'Montico', 'M-7')] === 115, 'troca gravou a entrada da sucata e a saída dos novos juntas');
    ok(contar("select count(*) from modulo_docs where caminho='g-ops' and dados->>'tipo'='troca'") === 1, 'troca é uma operação só');

    await page.click('[data-act="abrir"][data-tipo="retirada"]');
    await page.click('[data-seg="recolhido"][data-v="Montico"]');
    await escolher('ret.0.fabricante', 'AGS');
    await campo('ret.0.qtd', '50');
    await page.click('[data-seg="contra"][data-v="novos"]');
    await page.click('[data-act="revisar"]');
    ok(/recolhidas por Montico/.test(await page.textContent('.resumo')) && /só muda quando a entrada for registrada/.test(await page.textContent('.resumo')), 'retirada: quem recolheu separado do fabricante; novos só na entrada');
    await page.click('[data-act="confirmar"]');
    await page.waitForFunction(() => !document.querySelector('[data-act="confirmar"]'));
    s20 = saldos('20L');
    ok(s20['S|AGS'] === 61 && s20['N|' + lote('20L', 'Montico', 'M-7')] === 115, 'retirada baixou só a sucata informada, sem mexer nos novos');
    await semRolagemLateral('entregas');

    console.log('Recebimento vinculado');
    await abrirComo('conta');
    await page.click('[data-act="abrir"][data-tipo="entrada"]');
    const opRet = psql(BANCO, "select id from modulo_docs where caminho='g-ops' and dados->>'tipo'='retirada'").saida;
    await escolher('vinculo', opRet);
    await page.click('[data-seg="marca"][data-v="Montico"]');
    await campo('codigo', 'M-8');
    await campo('fabricacao', '2026-11');
    await campo('qtd', '10');
    await revisarConfirmar();
    ok(contar("select count(*) from modulo_docs where caminho='g-ops' and dados->>'vinculo'='" + opRet + "'") === 1, 'entrada de novos vinculada à retirada (identificador comum)');

    console.log('Histórico, exclusão e exportação (gestão)');
    await abrirComo('gestora');
    await page.click('[data-aba="sucata"]');
    ok(await page.locator('.hi').count() >= 4, 'histórico da sucata separado (trocas, retiradas e contagem)');
    await page.click('.hi:has-text("Troca com Mercado Bom Preço")');
    await page.waitForSelector('#modal:not([hidden]) [data-act="excluir-ini"]');
    ok(/Mercado Bom Preço/.test(await page.textContent('#modal-c')), 'detalhe da troca mostra o cliente');
    await page.click('[data-act="excluir-ini"]');
    const efeitos = await page.textContent('#modal-c');
    ok(/Sucata AGS \(20 L\): 61 → 41/.test(efeitos) && /Montico · lote M-7 \(20 L\): 115 → 120/.test(efeitos), 'confirmação mostra o efeito da exclusão nos saldos');
    await page.click('[data-act="excluir-ok"]');
    await page.waitForFunction(() => document.querySelector('#modal').hidden);
    s20 = saldos('20L');
    ok(s20['S|AGS'] === 41 && s20['S|Montico'] === 0 && s20['N|' + lote('20L', 'Montico', 'M-7')] === 120, 'excluir a troca desfez a sucata recebida e a saída dos novos');
    ok(contar("select count(*) from modulo_docs where caminho='g-excluidas'") === 1, 'conteúdo excluído guardado com quem e quando');
    // retirada com recebimento: conjunto
    await page.click('[data-aba="sucata"]');
    await page.click('.hi:has-text("Retirada por Montico")');
    await page.click('[data-act="excluir-ini"]');
    ok(/recebimento\(s\) de novos vinculado/.test(await page.textContent('#modal-c')) && /Excluir o conjunto \(2\)/.test(await page.textContent('[data-act="excluir-ok"]')), 'retirada com recebimento vinculado: exclusão do conjunto');
    await page.click('[data-act="excluir-ok"]');
    await page.waitForFunction(() => document.querySelector('#modal').hidden);
    ok(saldos('20L')['S|AGS'] === 91 && !saldos('20L')['N|' + lote('20L', 'Montico', 'M-8')], 'conjunto excluído: sucata devolvida e novos recebidos retirados');
    // exclusão que deixaria negativo: a contagem inicial do L-100 (já saíram 30)
    await page.click('[data-aba="novos"]');
    await page.click('.hi:has-text("Ajuste da contagem física")');
    await page.click('[data-act="excluir-ini"]');
    ok(await page.$eval('[data-act="excluir-ok"]', (b) => b.disabled) && /negativo/.test(await page.textContent('#modal-c')), 'exclusão que deixaria saldo negativo fica bloqueada');
    await page.click('[data-act="fechar-modal"]');
    // operacional não exclui: sem botão
    await page.click('[data-aba="config"]');
    await page.click('[data-act="csv"][data-qual="novos"]');
    await page.click('[data-act="csv"][data-qual="sucata"]');
    await page.click('[data-act="csv"][data-qual="saldos"]');
    await page.waitForFunction(() => (window.__baixados || []).length === 3);
    const csvs = await page.evaluate(() => window.__baixados);
    ok(/^﻿Operação;Data da movimentação;Registrado em;Tipo;Modelo;Marca;Lote/.test(csvs[0].data) && /Contagem Teste/.test(csvs[0].data), 'CSV de novos com responsável e lote');
    ok(/Quem recolheu/.test(csvs[1].data) && /Saldo \(unidades\)/.test(csvs[2].data), 'CSV da sucata e dos saldos');
    await page.fill('#c-validade', '4');
    await page.click('#form-cfg button[type="submit"]');
    await esperarTexto('#msg-cfg', 'salvos');
    ok(psql(BANCO, "select dados->>'validadeAnos' from modulo_docs where caminho='config'").saida === '4', 'gestão salva os parâmetros (validade)');
    await page.screenshot({ path: path.join(SHOTS, 'garrafoes-gestao.png'), fullPage: true });

    await abrirComo('entrega');
    await page.click('[data-aba="novos"]');
    await page.click('.hi >> nth=0');
    await page.waitForSelector('#modal:not([hidden])');
    ok(await page.locator('[data-act="excluir-ini"]').count() === 0, 'perfil operacional não vê Excluir');
    await page.click('[data-act="fechar-modal"]');
    // tentativa direta pelo banco (fora da tela) também é recusada
    const direto = rpc('garrafoes_excluir', { p_id: opRet });
    ok(direto.erro && /Só a gestão/.test(direto.erro), 'excluir pelo banco sem ser gestão é recusado');
    const gravaDireto = setDoc('g-ops', 'op-DIRETO0000000001', '{}', false);
    ok(gravaDireto.erro && /row-level security/.test(gravaDireto.erro), 'gravar direto na tabela é recusado');
    await page.screenshot({ path: path.join(SHOTS, 'garrafoes-celular.png'), fullPage: true });
    ok(errosJs.length === 0, 'sem erros de JavaScript na página' + (errosJs.length ? ': ' + errosJs.join(' | ') : ''));
  } catch (e) {
    falhou++; console.log('  ✗ ERRO: ' + (e && e.stack || e));
    try { await page.screenshot({ path: path.join(SHOTS, 'garrafoes-erro.png'), fullPage: true }); } catch (x) {}
  }
  await browser.close(); srv.close();
  console.log('\n' + passou + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})();
