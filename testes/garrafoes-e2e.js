/* LEVÍSSIMA · teste: módulo Garrafões (pedido de 19/11/2026), no celular, contra as funções reais da 0056 + 0057.
 * Usa um Postgres local (sem Supabase): a página do módulo roda no Chromium com uma "ponte" de teste que chama as
 * funções do banco como o usuário logado (claims do JWT), e lê modulo_docs com as regras de leitura (RLS).
 * Confere: cartões Novos AGS | Novos Montico | Sucatas (20 L com rosca: Montico | Angioplast, sem sucata), perfis,
 * contagem (fabricação encontrada e sucata total), entrada com foto da nota pela câmera (sem galeria; câmera negada
 * bloqueia), clique duplo sem duplicar, venda dividida por fabricação com assinatura do cliente na tela (Confirmar só
 * depois da assinatura; assinatura apagada se os itens mudarem; cancelar não grava), troca do exemplo do pedido
 * (15 sucatas de 20 L → 3 novos Montico fab. 11/2026), retirada (AGS, Montico ou Outro), recebimento vinculado,
 * consulta da assinatura e da foto, exclusão (efeitos, conjunto, bloqueio de negativo), CSV, parâmetros e celular.
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
      get: function(){ return window.__pgLer(c, id).then(function(j){ var rows = JSON.parse(j); return { exists: rows.length > 0, id: id, data: function(){ return rows[0] ? rows[0].dados : undefined; } }; }); },
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
function saldos(modelo) { return JSON.parse(psql(BANCO, "select public.garrafoes_saldos_0057(:'m');", { m: modelo }).saida); }
// imagens de apoio para gravar direto pelo banco (o banco confere o formato e o tamanho, não o conteúdo)
const JPG = 'data:image/jpeg;base64,' + '/9j/'.repeat(1600), PNG = 'data:image/png;base64,' + 'iVBO'.repeat(500);
function contar(sql) { return Number(psql(BANCO, sql).saida); }

(async () => {
  // banco do teste: simulação do Supabase + as migrações 0056 e 0057
  psql('postgres', 'drop database if exists ' + BANCO + ';');
  psql('postgres', 'create database ' + BANCO + ';');
  for (const f of ['testes/garrafoes-banco.sql', 'supabase/migrations/0056_garrafoes_estoque.sql', 'supabase/migrations/0057_garrafoes_fabricacao_assinatura.sql']) {
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

  // câmera de teste do Chromium (imagem gerada), sem pedir permissão
  const browser = await chromium.launch({ args: ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream'] });
  const ctx = await browser.newContext(Object.assign({}, devices['Pixel 5'], { locale: 'pt-BR', timezoneId: 'America/Sao_Paulo', permissions: ['camera'] }));
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
  async function tirarFoto(refazer) {
    await page.click('[data-act="foto"]');
    for (let i = 0; i < (refazer ? 2 : 1); i++) {
      await page.waitForFunction(() => { const v = document.getElementById('cam-video'); return v && v.videoWidth > 0; }, null, { timeout: 8000 });
      await page.click('[data-act="cam-foto"]');
      await page.waitForSelector('[data-act="cam-usar"]');
      if (refazer && i === 0) { ok(/Refazer/.test(await page.textContent('#cam-c')), 'prévia da foto com Refazer e Usar esta foto'); await page.click('[data-act="cam-refazer"]'); }
    }
    await page.click('[data-act="cam-usar"]');
    await page.waitForSelector('.foto-prev');
  }
  async function assinar() {
    const cv = page.locator('#assin-cv');
    await cv.scrollIntoViewIfNeeded();
    const b = await cv.boundingBox();
    await page.mouse.move(b.x + 24, b.y + b.height * 0.6);
    await page.mouse.down();
    for (let i = 1; i <= 12; i++) await page.mouse.move(b.x + 24 + i * 18, b.y + b.height * (i % 2 ? 0.35 : 0.7), { steps: 4 });
    await page.mouse.up();
    await page.waitForTimeout(100);
  }
  async function semRolagemLateral(rotulo) { const r = await page.evaluate(() => [document.documentElement.scrollWidth, window.innerWidth]); ok(r[0] <= r[1] + 1, 'sem rolagem lateral no celular: ' + rotulo + ' (' + r[0] + ' ≤ ' + r[1] + ')'); }
  const hoje = new Date(Date.now() - 3 * 3600e3).toISOString().slice(0, 10);

  try {
    console.log('Perfis e cartões');
    await abrirComo('conta');
    ok(await page.locator('.so-consulta').count() === 1, 'acesso sem perfil escolhido fica só com consulta');
    ok(await page.locator('[data-act="abrir"]').count() === 0, 'consulta não vê botões de registro');
    ok(await page.locator('[data-aba="config"]').count() === 0, 'consulta não vê a aba Gestão');
    const cartoes = await page.$$eval('#area-topo .cards3 .marca .nome', (e) => e.map((x) => x.textContent));
    ok(cartoes.join('|') === 'Novos AGS|Novos Montico|Sucatas', '20 L: três cartões lado a lado (' + cartoes.join(' | ') + ')');
    ok(await page.locator('#area-topo .bloco').count() === 1 && !/fabricante/i.test(await page.textContent('#principal')), 'sem bloco separado de sucata e sem "fabricante"');
    await semRolagemLateral('consulta');

    await abrirComo('gestora');
    ok(await page.locator('[data-act="abrir"]').count() === 5, 'gestão vê as 5 operações no 20 L');
    await page.click('[data-act="modelo"][data-m="20LR"]');
    await page.waitForFunction(() => /20 L com rosca/.test(document.querySelector('#area-topo').textContent));
    const cartoesR = await page.$$eval('#area-topo .cards3 .marca .nome', (e) => e.map((x) => x.textContent));
    ok(cartoesR.join('|') === 'Novos Montico|Novos Angioplast', '20 L com rosca: Novos Montico | Novos Angioplast, sem sucata (' + cartoesR.join(' | ') + ')');
    const botoesR = await page.$$eval('[data-act="abrir"]', (b) => b.map((x) => x.dataset.tipo));
    ok(botoesR.join(',') === 'entrada,saida,contagem', '20 L com rosca: só entrada, venda e contagem (' + botoesR + ')');
    ok(await page.locator('[data-aba="sucata"]').count() === 0, '20 L com rosca: sem histórico de sucata');
    await page.click('[data-act="abrir"][data-tipo="contagem"]');
    ok(await page.locator('[data-seg="alvo"]').count() === 0, '20 L com rosca: contagem só de novos');
    await page.click('[data-act="fechar"]');
    await page.screenshot({ path: path.join(SHOTS, 'garrafoes-20lr.png') });
    await page.click('[data-act="modelo"][data-m="10L"]');
    await page.waitForFunction(() => /10 L/.test(document.querySelector('#area-topo').textContent));
    ok((await page.$$eval('#area-topo .cards3 .marca .nome', (e) => e.map((x) => x.textContent))).join('|') === 'Novos AGS|Novos Montico|Sucatas', '10 L: Novos AGS | Novos Montico | Sucatas');
    await page.click('[data-act="modelo"][data-m="20L"]');
    await page.waitForFunction(() => /Novos · 20 L</.test(document.querySelector('#area-topo').innerHTML));
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
    await campo('achados.0.fab', '2026-09');
    await campo('achados.0.contado', '200');
    await page.click('[data-act="revisar"]');
    ok(/justificativa/i.test(await page.textContent('#painel-form .erro-caixa')), 'contagem com diferença pede justificativa');
    await campo('just', 'Saldo inicial pela contagem do depósito');
    await page.click('[data-act="revisar"]');
    const resumoCont = await page.textContent('.resumo');
    ok(/Registrado/.test(resumoCont) && /AGS · fab\. 09\/2026/.test(resumoCont) && /ajuste de \+200/.test(resumoCont), 'resumo da contagem mostra marca, fabricação, registrado, contado e efeito');
    await page.click('[data-act="confirmar"]');
    await page.waitForFunction(() => !document.querySelector('[data-act="confirmar"]'));
    await esperarTexto('#area-topo', '200');
    ok(saldos('20L')['N|AGS|2026-09'] === 200, 'contagem criou AGS fab. 09/2026 com 200 no banco');

    await page.click('[data-act="abrir"][data-tipo="contagem"]');
    await page.click('[data-seg="alvo"][data-v="sucata"]');
    ok(await page.locator('[data-f^="contado."]').count() === 1, 'contagem da sucata: um número só (total da litragem)');
    await campo('contado.S', '91');
    await campo('just', 'Contagem do pátio de sucata');
    await revisarConfirmar();
    ok(saldos('20L').S === 91, 'sucata de 20 L contada: 91');

    console.log('Entrada de novos com foto da nota');
    await page.click('[data-act="abrir"][data-tipo="entrada"]');
    ok(await page.locator('input[type="file"]').count() === 0 && await page.locator('[data-f="obs"]').count() === 0, 'entrada sem campo de arquivo (galeria) e sem Observação');
    await page.click('[data-seg="marca"][data-v="Montico"]');
    await campo('fab', '2026-11');
    await campo('qtd', '100');
    ok(/Validade 11\/2029/.test(await page.textContent('#d-lote')), 'validade calculada na hora: 11/2026 → 11/2029');
    await page.click('[data-act="revisar"]');
    ok(/foto da nota/i.test(await page.textContent('#painel-form .erro-caixa')), 'sem a foto da nota não avança');
    // câmera negada: explica e bloqueia
    await page.evaluate(() => { window.__gum = navigator.mediaDevices.getUserMedia; navigator.mediaDevices.getUserMedia = () => Promise.reject(Object.assign(new Error('negada'), { name: 'NotAllowedError' })); });
    await page.click('[data-act="foto"]');
    await esperarTexto('#cam-c', 'sem permissão');
    ok(/não é concluída/.test(await page.textContent('#cam-c')) && await page.locator('[data-act="cam-usar"]').count() === 0, 'câmera sem permissão: explica e não deixa seguir');
    await page.click('#cam-c [data-act="cam-fechar"]');
    await page.evaluate(() => { navigator.mediaDevices.getUserMedia = window.__gum; });
    await tirarFoto(true);
    ok(await page.locator('.foto-prev').count() === 1, 'foto tirada pela câmera, com prévia e opção de refazer');
    await page.click('[data-act="revisar"]');
    const resEnt = await page.textContent('.resumo');
    ok(/100 unidades novas Montico de 20 L, fabricação 11\/2026 \(validade 11\/2029\)/.test(resEnt) && /Foto da nota/.test(resEnt), 'resumo da entrada: marca, fabricação, validade e foto');
    await page.dblclick('[data-act="confirmar"]');
    await page.waitForFunction(() => !document.querySelector('[data-act="confirmar"]'));
    await page.waitForTimeout(500);
    ok(contar("select count(*) from modulo_docs where caminho='g-ops' and dados->>'tipo'='entrada'") === 1, 'clique duplo no confirmar não duplica a entrada');
    ok(contar("select count(*) from modulo_docs where caminho='g-fotos' and dados->>'imagem' like 'data:image/jpeg;base64,%'") === 1, 'foto da nota gravada junto com a entrada');
    ok(saldos('20L')['N|Montico|2026-11'] === 100, 'saldo Montico fab. 11/2026: 100');
    ok(await page.locator('[data-act="abrir"][data-tipo="saida"]').count() === 0, 'contagem e entradas não registra venda');

    console.log('Venda com assinatura do cliente (perfil Entregas)');
    await abrirComo('entrega');
    const botoesEnt = await page.$$eval('[data-act="abrir"]', (b) => b.map((x) => x.dataset.tipo));
    ok(botoesEnt.join(',') === 'saida,troca,retirada', 'entregas: venda, troca e retirada (' + botoesEnt + ')');
    // segunda fabricação AGS, mais nova, para a sugestão
    quem = 'conta'; const seed = rpc('garrafoes_registrar', { p: { id: 'op-TESTEAGS00000001', tipo: 'entrada', modelo: '20L', data: hoje, linhas: [{ marca: 'AGS', fabricacao: '2026-11', qtd: 50 }], foto: JPG } }); quem = 'entrega';
    ok(!seed.erro, 'entrada de apoio gravada' + (seed.erro ? ': ' + seed.erro : ''));
    await page.waitForTimeout(700);
    await page.click('[data-act="abrir"][data-tipo="saida"]');
    await campo('cliente', 'Mercado Bom Preço');
    await page.click('[data-seg="marca"][data-v="AGS"]');
    const sug = await page.textContent('.tlotes tr.sug');
    ok(/09\/2026/.test(sug) && /vence primeiro/.test(sug) && /09\/2029/.test(sug), 'venda mostra fabricação, validade e saldo, sugerindo a que vence primeiro');
    await campo('saida.N|AGS|2026-09', '30');
    await campo('saida.N|AGS|2026-11', '5');
    ok(/35 unidades/.test(await page.textContent('#d-total')), 'total da venda dividida entre fabricações');
    await page.click('[data-act="revisar"]');
    await page.waitForSelector('#assin-cv');
    ok(await page.$eval('[data-act="confirmar"]', (b) => b.disabled), 'Confirmar travado até o cliente assinar');
    ok(/não é assinatura com certificado digital/.test(await page.textContent('#painel-form')), 'avisa que é assinatura manuscrita na tela, não certificado digital');
    ok(contar("select count(*) from modulo_docs where caminho='g-ops' and dados->>'tipo'='saida'") === 0, 'nada muda no estoque antes da assinatura e da confirmação');
    await assinar();
    ok(!(await page.$eval('[data-act="confirmar"]', (b) => b.disabled)), 'depois da assinatura, Confirmar libera');
    await page.screenshot({ path: path.join(SHOTS, 'garrafoes-venda-assinatura.png'), fullPage: true });
    await semRolagemLateral('venda com assinatura');
    await page.click('[data-act="confirmar"]');
    await page.waitForFunction(() => !document.querySelector('[data-act="confirmar"]'), null, { timeout: 8000 });
    let s20 = saldos('20L');
    ok(s20['N|AGS|2026-09'] === 170 && s20['N|AGS|2026-11'] === 45, 'baixa exatamente nas fabricações escolhidas (170 e 45)');
    const assin = JSON.parse(psql(BANCO, "select dados from modulo_docs where caminho='g-assin'").saida || '{}');
    ok(/^data:image\/png;base64,/.test(assin.imagem || '') && /Mercado Bom Preço/.test(assin.resumo || '') && /35 garrafões novos AGS/.test(assin.resumo || '') && /certificado digital/.test(assin.aviso || ''), 'assinatura guardada com o resumo exato que o cliente assinou');
    // assinatura presa ao resumo: mudou a quantidade, apaga
    await page.click('[data-act="abrir"][data-tipo="saida"]');
    await campo('cliente', 'Padaria Teste');
    await page.click('[data-seg="marca"][data-v="AGS"]');
    await campo('saida.N|AGS|2026-11', '2');
    await page.click('[data-act="revisar"]');
    await page.waitForSelector('#assin-cv');
    await assinar();
    await page.click('[data-act="voltar"]');
    await campo('saida.N|AGS|2026-11', '3');
    await page.click('[data-act="revisar"]');
    await page.waitForSelector('#assin-cv');
    ok(/assinatura anterior foi apagada/.test(await page.textContent('#painel-form')) && await page.$eval('[data-act="confirmar"]', (b) => b.disabled), 'itens mudaram depois de assinar: assinatura apagada, pede de novo');
    await assinar();
    await page.click('[data-act="limpar-assin"]');
    ok(await page.$eval('[data-act="confirmar"]', (b) => b.disabled), 'Limpar apaga a assinatura e trava o Confirmar');
    await page.click('[data-act="fechar"]');
    ok(contar("select count(*) from modulo_docs where caminho='g-ops' and dados->>'tipo'='saida'") === 1, 'cancelar não grava nenhuma movimentação');
    // venda acima do disponível
    await page.click('[data-act="abrir"][data-tipo="saida"]');
    await campo('cliente', 'Cliente X');
    await page.click('[data-seg="marca"][data-v="AGS"]');
    await campo('saida.N|AGS|2026-11', '46');
    await page.click('[data-act="revisar"]');
    ok(/45 unidades disponível/.test(await page.textContent('#painel-form .erro-caixa')), 'venda acima do saldo da fabricação é recusada');
    await page.click('[data-act="fechar"]');

    console.log('Troca: exemplo do pedido (15 sucatas de 20 L → 3 novos Montico fab. 11/2026)');
    await page.click('[data-act="abrir"][data-tipo="troca"]');
    ok(await page.locator('[data-f$=".fabricante"]').count() === 0, 'sucata da troca sem fabricante');
    await campo('cliente', 'Cliente Exemplo');
    await campo('total', '15');
    await escolher('sucata.0.motivo', 'Vencido');
    await campo('sucata.0.qtd', '10');
    await page.click('[data-act="mais"][data-lista="sucata"]');
    await escolher('sucata.1.motivo', 'Quebrado ou trincado');
    await campo('sucata.1.qtd', '5');
    ok(/15 de 15/.test(await page.textContent('#d-soma')), 'quantidade por motivo confere com o total');
    ok(/15 sucatas → 3 unidades/.test(await page.textContent('#d-sugestao')), 'sugestão 5 para 1: 15 → 3 (editável)');
    await escolher('novos.0.marca', 'Montico');
    ok(await page.$eval('[data-f="novos.0.lote"]', (e) => e.value) === 'N|Montico|2026-11' && /val\. 11\/2029/.test(await page.$eval('[data-f="novos.0.lote"]', (e) => e.selectedOptions[0].textContent)), 'fabricação sugerida com validade e saldo');
    await page.click('[data-act="usar-sugestao"]');
    ok(await page.$eval('[data-f="novos.0.qtd"]', (e) => e.value) === '3', 'usar a sugestão preenche 3');
    await page.screenshot({ path: path.join(SHOTS, 'garrafoes-troca.png'), fullPage: true });
    await semRolagemLateral('troca');
    await page.click('[data-act="revisar"]');
    const resumoTroca = await page.textContent('.resumo');
    ok(/Recebimento: 15 sucatas de 20 L \(10 vencido; 5 quebrado ou trincado\)/.test(resumoTroca) && /Entrega: 3 unidades Montico, fab\. 11\/2026/.test(resumoTroca), 'resumo da troca: sucata por litragem e motivo, novos por marca e fabricação');
    ok(await page.$eval('[data-act="confirmar"]', (b) => b.disabled), 'troca também espera a assinatura do cliente');
    await assinar();
    await page.click('[data-act="confirmar"]');
    await page.waitForFunction(() => !document.querySelector('[data-act="confirmar"]'), null, { timeout: 8000 });
    s20 = saldos('20L');
    ok(s20.S === 106, 'sucata de 20 L: +15 (91 → 106)');
    ok(s20['N|Montico|2026-11'] === 97, 'Montico 20 L fab. 11/2026: −3 (100 → 97)');
    ok(s20['N|AGS|2026-09'] === 170 && s20['N|AGS|2026-11'] === 45, 'AGS não muda');
    ok(contar("select count(*) from modulo_docs where caminho='g-ops' and dados->>'tipo'='troca'") === 1 && contar("select count(*) from modulo_docs where caminho='g-assin'") === 2, 'troca é uma operação só, com a assinatura');
    await esperarTexto('#area-topo', '106');

    console.log('Retirada de sucata');
    await page.click('[data-act="abrir"][data-tipo="retirada"]');
    const quemRec = await page.$$eval('[data-seg="recolhido"]', (b) => b.map((x) => x.dataset.v));
    ok(quemRec.join(',') === 'AGS,Montico,Outro', 'marca que recolheu: AGS, Montico ou Outro');
    await page.click('[data-seg="recolhido"][data-v="Outro"]');
    ok(await page.locator('[data-f="recolhidoOutro"]').count() === 1, '"Outro" pede o nome de quem recolheu');
    await page.click('[data-seg="recolhido"][data-v="Montico"]');
    await campo('qtd', '50');
    await page.click('[data-seg="contra"][data-v="novos"]');
    await page.click('[data-act="revisar"]');
    ok(/recolhidas por Montico/.test(await page.textContent('.resumo')) && /106 → 56/.test(await page.textContent('.resumo')), 'retirada baixa o saldo geral da sucata de 20 L');
    await page.click('[data-act="confirmar"]');
    await page.waitForFunction(() => !document.querySelector('[data-act="confirmar"]'));
    s20 = saldos('20L');
    ok(s20.S === 56 && s20['N|Montico|2026-11'] === 97, 'retirada baixou só a sucata, sem mexer nos novos');
    await semRolagemLateral('entregas');
    // 20 L com rosca: sem troca e sem retirada, nem pela tela nem pelo banco
    await page.click('[data-act="modelo"][data-m="20LR"]');
    await page.waitForFunction(() => /20 L com rosca/.test(document.querySelector('#area-topo').textContent));
    ok((await page.$$eval('[data-act="abrir"]', (b) => b.map((x) => x.dataset.tipo))).join(',') === 'saida', '20 L com rosca no perfil Entregas: só venda');
    const trocaR = rpc('garrafoes_registrar', { p: { id: 'op-TESTE20LR0000001', tipo: 'troca', modelo: '20LR', data: hoje, cliente: 'X', totalSucata: 5, linhas: [{ classe: 'sucata', motivo: 'Vencido', qtd: 5 }], assinatura: { imagem: PNG, resumo: 'x' } } });
    ok(trocaR.erro && /não tem troca nem sucata/.test(trocaR.erro), 'banco recusa troca no 20 L com rosca');
    await page.click('[data-act="modelo"][data-m="20L"]');

    console.log('Recebimento vinculado');
    await abrirComo('conta');
    await page.click('[data-act="abrir"][data-tipo="entrada"]');
    const opRet = psql(BANCO, "select id from modulo_docs where caminho='g-ops' and dados->>'tipo'='retirada'").saida;
    await escolher('vinculo', opRet);
    await page.click('[data-seg="marca"][data-v="Montico"]');
    await campo('fab', '2026-11');
    await campo('qtd', '10');
    ok(/soma ao lote existente \(saldo 97\)/.test(await page.textContent('#d-lote')), 'mesma marca e fabricação: soma ao lote existente');
    await tirarFoto(false);
    await revisarConfirmar();
    ok(contar("select count(*) from modulo_docs where caminho='g-ops' and dados->>'vinculo'='" + opRet + "'") === 1 && saldos('20L')['N|Montico|2026-11'] === 107, 'entrada de novos vinculada à retirada, com foto');

    console.log('Consulta, exclusão e exportação (gestão)');
    await abrirComo('gestora');
    await page.click('[data-aba="sucata"]');
    ok(await page.locator('.hi').count() >= 3, 'histórico da sucata (troca, retirada e contagem)');
    await page.click('.hi:has-text("Troca com Cliente Exemplo")');
    await page.waitForSelector('#modal:not([hidden]) .anexo img');
    const modalTroca = await page.textContent('#modal-c');
    ok(/Cliente Exemplo/.test(modalTroca) && /Assinatura do cliente/.test(modalTroca) && /Recebo 3 garrafões novos de 20 L/.test(modalTroca) && /certificado digital/.test(modalTroca), 'detalhe da troca: cliente, itens, assinatura e o resumo assinado');
    await page.screenshot({ path: path.join(SHOTS, 'garrafoes-detalhe-assinatura.png'), fullPage: true });
    await page.click('[data-act="excluir-ini"]');
    const efeitos = await page.textContent('#modal-c');
    ok(/Sucata \(20 L\): 56 → 41/.test(efeitos) && /Novos Montico · fab\. 11\/2026 \(20 L\): 107 → 110/.test(efeitos), 'confirmação mostra o efeito da exclusão nos saldos');
    await page.click('[data-act="excluir-ok"]');
    await page.waitForFunction(() => document.querySelector('#modal').hidden);
    s20 = saldos('20L');
    ok(s20.S === 41 && s20['N|Montico|2026-11'] === 110, 'excluir a troca desfez a sucata recebida e a saída dos novos');
    ok(contar("select count(*) from modulo_docs where caminho='g-excluidas'") === 1 && contar("select count(*) from modulo_docs where caminho='g-assin'") === 2, 'excluído guardado; assinatura continua guardada');
    await page.click('[data-aba="sucata"]');
    await page.click('.hi:has-text("Retirada por Montico")');
    await page.click('[data-act="excluir-ini"]');
    ok(/recebimento\(s\) de novos vinculado/.test(await page.textContent('#modal-c')) && /Excluir o conjunto \(2\)/.test(await page.textContent('[data-act="excluir-ok"]')), 'retirada com recebimento vinculado: exclusão do conjunto');
    await page.click('[data-act="excluir-ok"]');
    await page.waitForFunction(() => document.querySelector('#modal').hidden);
    ok(saldos('20L').S === 91 && saldos('20L')['N|Montico|2026-11'] === 100, 'conjunto excluído: sucata devolvida e novos recebidos retirados');
    await page.click('[data-aba="novos"]');
    await page.click('.hi:has-text("Entrada de novos") >> nth=-1');
    await page.waitForSelector('#modal:not([hidden]) .anexo img.foto');
    ok(/Foto da nota do recebimento/.test(await page.textContent('#modal-c')), 'detalhe da entrada mostra a foto da nota');
    await page.click('[data-act="fechar-modal"]');
    await page.click('.hi:has-text("Ajuste da contagem física")');
    await page.click('[data-act="excluir-ini"]');
    ok(await page.$eval('[data-act="excluir-ok"]', (b) => b.disabled) && /negativo/.test(await page.textContent('#modal-c')), 'exclusão que deixaria saldo negativo fica bloqueada');
    await page.click('[data-act="fechar-modal"]');
    await page.click('[data-aba="lotes"]');
    ok(/Novos AGS · 215/.test(await page.textContent('#area-aba')) && /09\/2026/.test(await page.textContent('#area-aba')), 'lotes e validade por marca e fabricação');
    await page.click('[data-aba="config"]');
    await page.click('[data-act="csv"][data-qual="novos"]');
    await page.click('[data-act="csv"][data-qual="sucata"]');
    await page.click('[data-act="csv"][data-qual="saldos"]');
    await page.waitForFunction(() => (window.__baixados || []).length === 3);
    const csvs = await page.evaluate(() => window.__baixados);
    ok(/^﻿Operação;Data da movimentação;Registrado em;Tipo;Modelo;Marca;Fabricação;Validade/.test(csvs[0].data) && /Assinatura do cliente;Foto da nota/.test(csvs[0].data) && /Contagem Teste/.test(csvs[0].data), 'CSV de novos com marca, fabricação, validade, assinatura e foto');
    ok(/Quem recolheu/.test(csvs[1].data) && /Saldo \(unidades\)/.test(csvs[2].data), 'CSV da sucata e dos saldos');
    await page.fill('#c-validade', '4');
    await page.click('#form-cfg button[type="submit"]');
    await esperarTexto('#msg-cfg', 'salvos');
    ok(psql(BANCO, "select dados->>'validadeAnos' from modulo_docs where caminho='config'").saida === '4', 'gestão salva os parâmetros (validade)');
    await page.fill('#c-validade', '3');
    await page.click('#form-cfg button[type="submit"]');
    await page.waitForTimeout(400);

    await abrirComo('entrega');
    await page.screenshot({ path: path.join(SHOTS, 'garrafoes-celular.png') });
    await page.click('[data-aba="novos"]');
    await page.click('.hi >> nth=0');
    await page.waitForSelector('#modal:not([hidden])');
    ok(await page.locator('[data-act="excluir-ini"]').count() === 0, 'perfil operacional não vê Excluir');
    await page.click('[data-act="fechar-modal"]');
    const direto = rpc('garrafoes_excluir', { p_id: opRet });
    ok(direto.erro && /Só a gestão/.test(direto.erro), 'excluir pelo banco sem ser gestão é recusado');
    const gravaDireto = setDoc('g-ops', 'op-DIRETO0000000001', '{}', false);
    ok(gravaDireto.erro && /row-level security/.test(gravaDireto.erro), 'gravar direto na tabela é recusado');
    ok(errosJs.length === 0, 'sem erros de JavaScript na página' + (errosJs.length ? ': ' + errosJs.join(' | ') : ''));
  } catch (e) {
    falhou++; console.log('  ✗ ERRO: ' + (e && e.stack || e));
    try { await page.screenshot({ path: path.join(SHOTS, 'garrafoes-erro.png'), fullPage: true }); } catch (x) {}
  }
  await browser.close(); srv.close();
  console.log('\n' + passou + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})();
