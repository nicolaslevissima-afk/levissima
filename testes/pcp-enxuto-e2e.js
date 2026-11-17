/* LEVÍSSIMA · teste: PCP enxuto (pedido de 17/11/2026, parte 1).
 * Cartões com o saldo em destaque, OP longa sem repetir a quantidade, contadores separados (pausada não é
 * "em execução"), concluídas no período, ficha da OP com os detalhes, só o PCP administra a OP, turnos de
 * referência, disponibilidade da linha e PDF por linha e sequência.
 * Rodar: node testes/pcp-enxuto-e2e.js   (depois de python3 ferramentas/construir.py --modulos)
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { execFileSync } = require('child_process');
const { criar } = require('./banco-fake');

const SHOTS = process.env.SHOTS || path.join(__dirname, 'shots');
fs.mkdirSync(SHOTS, { recursive: true });
let passou = 0, falhou = 0;
function ok(c, msg) { if (c) { passou++; console.log('  ✓ ' + msg); } else { falhou++; console.log('  ✗ FALHOU: ' + msg); } }
const PDFLIB = ['/opt/npm-tools/node_modules/pdf-lib/dist/pdf-lib.min.js', path.join(process.env.HOME || '/root', '.npm-global/lib/node_modules/pdf-lib/dist/pdf-lib.min.js')].find((f) => fs.existsSync(f));

function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }
const TURNOS = [
  { nome: 'DESC 1', inicio: '05:15', fim: '13:15', dias: [1, 2, 3, 4, 5, 6], pausa: 0 },
  { nome: 'DESC 2', inicio: '12:15', fim: '21:00', dias: [1, 2, 3, 4, 5, 6], pausa: 0 },
  { nome: 'DESC 3', inicio: '20:55', fim: '05:20', dias: [1, 2, 3, 4, 5, 6], pausa: 0 }
];

(async () => {
  const amb = await criar();
  const b = amb.banco.b;
  const agora = Date.now(), iso = (ms) => new Date(ms).toISOString();
  const hojeSP = new Date(agora - 3 * 3600e3).toISOString().slice(0, 10);
  [['padrao-05-510ml-natural', '510ml natural', 150, 5], ['padrao-07-1500ml-natural', '1,5L natural', 112, 7], ['padrao-03-350ml-natural', '350ml natural', 200, 3]]
    .forEach(([id, nome, upp, ordem]) => doc(b, 'produtos', id, { nome, unidade: 'fardos', unidadesPorPalete: upp, ordem, tipoChapatex: 'fileira', unidadesPorFileira: 25 }));
  doc(b, 'mp-config', 'linhas-producao', { linhas: [
    { id: 'l1', nome: 'Linha 1', un: 'fardos', porHora: 400, op: true, turnos: TURNOS, produtos: [], maquinas: [] },
    { id: 'linha2', nome: 'Linha 2', un: 'fardos', porHora: 500, op: true, turnos: TURNOS, produtos: [], maquinas: [] },
    { id: 'g6', nome: 'Galão 6L', un: 'galões', porHora: 0, op: true, turnos: [{ nome: 'DESC 1' }], produtos: [], maquinas: [] }
  ], excecoes: [] });
  const op = (id, numero, linha, seq, qtd, pid, extra) => doc(b, 'producao-ordens', id, Object.assign({ numero, status: 'aberta', linha, seq, data: hojeSP, itens: [{ produtoId: pid, quantidade: qtd, unidade: 'fardos' }], finalidade: 'estoque', urgencia: 3, obs: '' }, extra || {}));
  op('op101', 101, 'linha2', 10, 30000, 'padrao-05-510ml-natural', { obs: 'Trocar o rótulo no início' });
  op('op102', 102, 'linha2', 20, 6000, 'padrao-07-1500ml-natural');
  op('op103', 103, 'l1', 10, 4000, 'padrao-03-350ml-natural');
  op('op104', 104, 'l1', 5, 2000, 'padrao-03-350ml-natural', { status: 'concluida', dataProducao: hojeSP, concluidoEm: iso(agora - 3600e3), concluidoPor: { nome: 'Nicolas Moraes' }, produzido: [{ produtoId: 'padrao-03-350ml-natural', quantidade: 1980, unidade: 'fardos' }] });
  const ev = (id, opId, numero, linha, tipo, em, motivo) => doc(b, 'producao-eventos', id, { opId, numero, linha, tipo, motivo: motivo || '', em: iso(em), por: { nome: 'Nicolas Moraes', ref: 'mestre' } });
  ev('e1', 'op101', 101, 'linha2', 'iniciar', agora - 2 * 864e5);
  ev('e2', 'op103', 103, 'l1', 'iniciar', agora - 5 * 3600e3);
  ev('e3', 'op103', 103, 'l1', 'pausar', agora - 4 * 3600e3, 'Falta de insumo');

  const ctx = await amb.contexto({ viewport: { width: 1440, height: 1500 }, acceptDownloads: true });
  const pag = await ctx.newPage();
  if (PDFLIB) await pag.route(/pdf-lib\/1\.17\.1\/pdf-lib\.min\.js/, (r) => r.fulfill({ status: 200, contentType: 'text/javascript', body: fs.readFileSync(PDFLIB, 'utf8') }));
  await pag.goto(amb.url + '/index.html');
  await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  await pag.fill('#login-senha', 'teste-nicolas');
  await pag.click('#btn-login-submit');
  await pag.waitForSelector('#admin-view:not(.hidden)', { timeout: 15000 });
  await pag.waitForTimeout(800);
  await pag.click('#admin-tabs .seg-btn[data-tab="pcp"]');
  await pag.waitForTimeout(800);
  const txt = (sel) => pag.$eval(sel, (e) => e.innerText).catch(() => '');

  console.log('1. Contadores');
  const kpis = await pag.$$eval('#pcp-kpis .pcp-kpi', (els) => els.map((e) => [e.dataset.f, e.innerText.replace(/\s+/g, ' ').trim()]));
  console.log('   ' + kpis.map((k) => k[1]).join(' | '));
  const kv = Object.fromEntries(kpis.map(([f, t]) => [f, Number(t.split(' ')[0])]));
  ok(kv.execucao === 1, 'em execução agora: 1 (a pausada não conta)');
  ok(kv.pausada === 1, 'pausadas: 1');
  ok(kv.planejada === 1, 'planejadas no período: 1');
  ok(kv.concluida === 1, 'concluídas no período: 1');
  ok(!kpis.some((k) => /em produção agora/.test(k[1])), 'não existe mais "em produção agora"');

  console.log('2. Cartões e OP longa');
  await pag.screenshot({ path: path.join(SHOTS, 'pcp-enxuto-semana.png'), fullPage: false });
  const cards = await pag.$$eval('#pcp-corpo .pcp-card', (els) => els.map((e) => ({ op: e.dataset.op, cont: e.classList.contains('is-cont'), t: e.innerText.replace(/\s+/g, ' ') })));
  const de101 = cards.filter((c) => c.op === 'op101');
  ok(de101.filter((c) => !c.cont).length === 1, 'OP 101 tem um cartão completo só na semana (' + de101.length + ' dias)');
  ok(de101.filter((c) => c.cont).length >= 1 && de101.filter((c) => c.cont).every((c) => !/Saldo|30\.000/.test(c.t)), 'os outros dias mostram só a continuidade, sem repetir a quantidade');
  const c101 = (de101.find((c) => !c.cont) || {}).t || '';
  ok(/Saldo 30\.000 fardos/.test(c101) && /200 pal/.test(c101), 'cartão: saldo a produzir com paletes (' + c101.slice(0, 120) + ')');
  ok(/Começou/.test(c101) && /término/.test(c101), 'cartão: começou e término previstos');
  ok(!/Prog\.|Reposição de estoque|Finalidade/.test(c101), 'cartão sem quantidade original, produzido e finalidade (ficam na ficha)');
  ok(/Em execução/.test(c101), 'situação da OP: Em execução');
  const c103 = (cards.find((c) => c.op === 'op103' && !c.cont) || {}).t || '';
  ok(/Pausada: Falta de insumo/.test(c103) && /se retomar agora/.test(c103), 'OP pausada: motivo e previsão "se retomar agora"');

  console.log('3. Filtros');
  await pag.click('#pcp-kpis .pcp-kpi[data-f="execucao"]'); await pag.waitForTimeout(400);
  let ops = await pag.$$eval('#pcp-corpo [data-op]', (els) => Array.from(new Set(els.map((e) => e.dataset.op))));
  ok(ops.length === 1 && ops[0] === 'op101', 'filtro "em execução": só a OP 101 (' + ops.join(',') + ')');
  await pag.click('#pcp-kpis .pcp-kpi[data-f="pausada"]'); await pag.waitForTimeout(400);
  ops = await pag.$$eval('#pcp-corpo [data-op]', (els) => Array.from(new Set(els.map((e) => e.dataset.op))));
  ok(ops.length === 1 && ops[0] === 'op103', 'filtro "pausadas": só a OP 103');
  await pag.click('#pcp-kpis .pcp-kpi[data-f="concluida"]'); await pag.waitForTimeout(400);
  const concl = await txt('#pcp-corpo');
  ok(/OP nº 104/.test(concl) && /1\.980 fardos/.test(concl), 'concluídas no período: tabela com a OP 104 e o produzido');
  await pag.click('#pcp-kpis .pcp-kpi[data-f="concluida"]'); await pag.waitForTimeout(300);
  await pag.click('#pcp-barra [data-pcpa="modo"][data-v="tabela"]'); await pag.waitForTimeout(400);
  const cab = await pag.$$eval('#pcp-corpo thead th', (els) => els.map((e) => e.innerText.trim()));
  ok(cab.includes('Saldo a produzir') && !cab.includes('Finalidade') && !cab.includes('Prog. / Prod. / Saldo'), 'tabela enxuta: ' + cab.join(' | '));
  await pag.click('#pcp-barra [data-pcpa="modo"][data-v="cartoes"]'); await pag.waitForTimeout(300);

  for (const v of ['dia', 'mes', 'semana']) { await pag.click('#pcp-barra [data-pcpa="vis"][data-v="' + v + '"]'); await pag.waitForTimeout(350); }
  ok(!amb.erros.length, 'visões dia, mês e semana sem erro');
  console.log('4. Ficha da OP');
  await pag.click('#pcp-corpo .pcp-card[data-op="op101"]:not(.is-cont)'); await pag.waitForTimeout(400);
  const ficha = await txt('#ger-form-body');
  ok(/programado 30\.000 fardos/.test(ficha) && /produzido 0/.test(ficha) && /saldo 30\.000/.test(ficha), 'ficha: programado, produzido e saldo');
  ok(/Reposição de estoque/.test(ficha) && /Trocar o rótulo no início/.test(ficha), 'ficha: finalidade e instruções');
  ok(/parada de máquina não muda a situação da OP/.test(ficha), 'ficha: situação da OP separada do estado das máquinas');
  ok(!!(await pag.$('#ger-form-body [data-ger="pcp-pausar"]')) && !!(await pag.$('#ger-form-body [data-ger="pcp-concluir"]')), 'senha mestre (PCP): pausar e concluir na ficha');
  await pag.screenshot({ path: path.join(SHOTS, 'pcp-enxuto-ficha.png') });
  await pag.click('#btn-ger-cancel').catch(() => pag.keyboard.press('Escape'));
  await pag.waitForTimeout(300);

  console.log('5. Linhas e turnos');
  await pag.click('#pcp-sub-tabs .seg-btn[data-pcp="linhas"]'); await pag.waitForTimeout(500);
  const lin = await txt('#pcp-linhas');
  ok(/Pendências de configuração/.test(lin) && /Galão 6L/.test(lin) && /sem capacidade de planejamento|turnos sem horário/.test(lin), 'pendências de configuração juntas no topo (Galão 6L)');
  ok(/seg a sex: 24 h/.test(lin), 'disponibilidade da linha pela união dos turnos (sem somar a troca de turno): ' + ((lin.match(/Disponível para produzir nesta semana: [^\n]*/) || [''])[0]));
  ok(/Escala das pessoas/.test(lin), 'turnos apresentados como escala das pessoas');
  await pag.click('#pcp-linhas [data-mp="pl-editar"][data-linha="g6"]'); await pag.waitForTimeout(400);
  const form = await txt('#ger-form-body');
  ok(/Turnos de referência, a confirmar/.test(form) && /DESC 1 05:15–13:15/.test(form) && /DESC 3 20:55–05:20/.test(form), 'turnos de referência novos (05:15–13:15 · 12:15–21:00 · 20:55–05:20)');
  ok(!!(await pag.$('#lp-copiar-de')), 'dá para copiar os turnos de outra linha');
  await pag.selectOption('#lp-copiar-de', 'linha2');
  await pag.click('#ger-form-body [data-ger="lp-copiar"]'); await pag.waitForTimeout(300);
  ok((await pag.$eval('#lp-ti-0', (e) => e.value)) === '05:15', 'copiar os turnos da Linha 2 preenche os horários');
  await pag.click('#btn-ger-cancel').catch(() => pag.keyboard.press('Escape'));
  await pag.waitForTimeout(300);

  console.log('6. PDF');
  await pag.click('#pcp-sub-tabs .seg-btn[data-pcp="prog"]'); await pag.waitForTimeout(400);
  await pag.click('#pcp-barra [data-pcpa="pdf"]'); await pag.waitForTimeout(300);
  const [down] = await Promise.all([pag.waitForEvent('download', { timeout: 20000 }).catch(() => null), pag.click('#btn-ger-submit')]);
  if (!down) ok(false, 'PDF gerado'); else {
    const f = path.join(SHOTS, 'pcp-enxuto.pdf');
    await down.saveAs(f);
    const t = execFileSync('pdftotext', ['-layout', f, '-']).toString();
    fs.writeFileSync(path.join(SHOTS, 'pcp-enxuto.txt'), t);
    ok(/Programação de Produção/.test(t) && /Linha 2/.test(t), 'PDF: cabeçalho e Linha 2');
    ok(/Saldo a produzir/.test(t) && /30\.000 fardos/.test(t), 'PDF: saldo a produzir em destaque');
    ok(!/Nada programado/.test(t) && !/Resumo por linha/.test(t) && !/Galão 6L/.test(t), 'PDF: sem "Nada programado", sem resumo repetido e sem linha vazia');
    ok((t.match(/\b101\b/g) || []).length === 1, 'PDF: a OP longa aparece uma vez (não repete por dia)');
    ok(/em execução desde/.test(t), 'PDF: OP em continuidade com "em execução desde"');
    ok(/Trocar o rótulo no início/.test(t), 'PDF: instruções da OP');
  }

  console.log('7. Quem administra a OP');
  const ctx2 = await amb.contexto({ viewport: { width: 1280, height: 1000 } });
  const p2 = await ctx2.newPage();
  await p2.goto(amb.url + '/index.html');
  await p2.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  await p2.fill('#login-senha', 'teste-angelica');
  await p2.click('#btn-login-submit');
  await p2.waitForSelector('#admin-view:not(.hidden)', { timeout: 15000 });
  await p2.waitForTimeout(800);
  const temPcp = await p2.$('#admin-tabs .seg-btn[data-tab="producao"]:not(.hidden)');
  if (temPcp) {
    await p2.click('#admin-tabs .seg-btn[data-tab="producao"]'); await p2.waitForTimeout(600);
    ok(!(await p2.$('[data-mp="op-iniciar"]')) && !(await p2.$('[data-mp="op-pausar"]')) && !(await p2.$('[data-mp="op-retomar"]')), 'equipe sem "Configura o PCP": não inicia, pausa nem retoma OP');
  } else ok(true, 'equipe sem a aba Produção (nada a administrar)');

  const errs = amb.erros.filter((e) => !/favicon|manifest/.test(e));
  ok(!errs.length, 'sem erros no console' + (errs.length ? ': ' + errs.slice(0, 3).join(' | ') : ''));
  await amb.fechar();
  console.log('\n' + passou + ' ok, ' + falhou + ' falha(s)');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
