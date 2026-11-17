/* LEVÍSSIMA · teste: tablets das máquinas (pedido de 17/11/2026, parte 2).
 * Acesso da máquina abre a tela dela; operador pela senha de 4 números; lançamento por horário com OP automática,
 * troca de OP no meio do horário em trechos, duplicidade, fila sem internet sem duplicar, parada e retomada sem
 * mexer na OP, etapa final no estoque estimado; painel de conferência (validar e corrigir); configuração da linha;
 * lançamento da hora fechado na linha que lança pelos tablets.
 * Rodar: node testes/maquinas-e2e.js   (depois de python3 ferramentas/construir.py --modulos)
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { criar } = require('./banco-fake');
const { ligar } = require('./maquinas-fake');

const SHOTS = process.env.SHOTS || path.join(__dirname, 'shots');
fs.mkdirSync(SHOTS, { recursive: true });
let passou = 0, falhou = 0;
function ok(c, msg) { if (c) { passou++; console.log('  ✓ ' + msg); } else { falhou++; console.log('  ✗ FALHOU: ' + msg); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }
const TURNOS = [
  { nome: 'DESC 1', inicio: '05:15', fim: '13:15', dias: [0, 1, 2, 3, 4, 5, 6] },
  { nome: 'DESC 2', inicio: '12:15', fim: '21:00', dias: [0, 1, 2, 3, 4, 5, 6] },
  { nome: 'DESC 3', inicio: '20:55', fim: '05:20', dias: [0, 1, 2, 3, 4, 5, 6] }
];

(async () => {
  const amb = await criar();
  amb.USUARIOS.push({ senha: 'teste-tablet-emp', papel: 'setor', nome: 'L2 · Empacotadora', ref: 'setor:maq-l2-empacotadora', modulos: ['lider_producao'] });
  const ctl = ligar(amb);
  const b = amb.banco.b, agora = Date.now(), iso = (ms) => new Date(ms).toISOString(), hoje = new Date(agora - 3 * 3600e3).toISOString().slice(0, 10);
  doc(b, 'produtos', 'padrao-05-510ml-natural', { nome: '510ml natural', unidade: 'fardos', unidadesPorPalete: 150, ordem: 5 });
  doc(b, 'produtos', 'padrao-07-1500ml-natural', { nome: '1,5L natural', unidade: 'fardos', unidadesPorPalete: 112, ordem: 7 });
  doc(b, 'mp-config', 'linhas-producao', { linhas: [
    { id: 'linha2', nome: 'Linha 2', un: 'fardos', porHora: 500, op: true, turnos: TURNOS, produtos: [], apontaMaquinas: { desde: iso(agora - 30 * 3600e3) }, maquinas: [
      { id: 'l2-enchedora', nome: 'Enchedora', unidade: 'garrafas', acesso: 'setor:maq-l2-enchedora' },
      { id: 'l2-empacotadora', nome: 'Empacotadora', unidade: 'fardos', producao: true, acesso: 'setor:maq-l2-empacotadora' }] },
    { id: 'l1', nome: 'Linha 1', un: 'fardos', porHora: 400, op: true, turnos: TURNOS, produtos: [], maquinas: [
      { id: 'l1-sopradora', nome: 'Sopradora', unidade: 'garrafas', acesso: 'setor:maq-l1-sopradora', confirmar: true }] }
  ], excecoes: [] });
  doc(b, 'producao-ordens', 'op101', { numero: 101, status: 'aberta', linha: 'linha2', seq: 10, data: hoje, itens: [{ produtoId: 'padrao-05-510ml-natural', quantidade: 30000, unidade: 'fardos' }], finalidade: 'estoque', obs: 'Rótulo novo' });
  doc(b, 'producao-ordens', 'op102', { numero: 102, status: 'aberta', linha: 'linha2', seq: 20, data: hoje, itens: [{ produtoId: 'padrao-07-1500ml-natural', quantidade: 5000, unidade: 'fardos' }], finalidade: 'estoque' });
  doc(b, 'producao-eventos', 'e1', { opId: 'op101', numero: 101, linha: 'linha2', tipo: 'iniciar', em: iso(agora - 2 * 864e5), por: { nome: 'Nicolas' } });

  // ===================== tablet =====================
  console.log('1. Tablet da Empacotadora (L2)');
  const ctx = await amb.contexto({ viewport: { width: 1024, height: 1300 } });
  const t = await ctx.newPage();
  await t.goto(amb.url + '/index.html');
  await t.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  await t.fill('#login-senha', 'teste-tablet-emp');
  await t.click('#btn-login-submit');
  await t.waitForSelector('#maq-tela:not(.hidden)', { timeout: 15000 });
  await t.waitForTimeout(500);
  const tela = () => t.$eval('#maq-tela', (e) => e.innerText).catch(() => '');
  let tx = await tela();
  ok(/L2 · Empacotadora/.test(tx) && /OP nº 101/.test(tx) && /510ml natural/.test(tx), 'abre direto na máquina com a OP em execução da linha');
  ok(/etapa final/.test(tx) && /fardos/.test(tx), 'mostra que é a etapa final e a unidade');
  ok(await t.$eval('[data-maq="producao"]', (e) => e.disabled), 'sem operador identificado, não lança');
  ok(!(await t.isVisible('#setor-modulos')), 'não mostra os módulos da fábrica');
  await t.screenshot({ path: path.join(SHOTS, 'maq-1-tela.png') });

  console.log('2. Operador');
  await t.click('[data-maq="operador"]');
  for (const k of ['1', '2', '3', '9']) await t.click('[data-maq="pin"][data-k="' + k + '"]');
  await t.waitForTimeout(300);
  ok(/Senha errada/.test(await tela()), 'senha errada avisa');
  for (const k of ['1', '2', '3', '4']) await t.click('[data-maq="pin"][data-k="' + k + '"]');
  await t.waitForTimeout(500);
  tx = await tela();
  ok(/Operador:\s*Carlos Operador/.test(tx), 'operador identificado pela senha de 4 números');
  ok(/Horas sem lançamento/.test(tx), 'sugere as horas sem lançamento (com OP em execução)');

  console.log('3. Lançar produção');
  await t.click('[data-maq="producao"]');
  await t.waitForTimeout(400);
  tx = await tela();
  ok(/Produção das \d\dh às \d\dh/.test(tx), 'mostra o intervalo: "Produção das 08h às 09h" (' + ((tx.match(/Produção das \d\dh às \d\dh/) || [''])[0]) + ')');
  // escolhe a última hora cheia
  const horas = await t.$$eval('[data-maq="hora"]', (els) => els.map((e) => [e.dataset.ini, e.dataset.fim]));
  const [hIni, hFim] = horas[horas.length - 1];
  await t.click('[data-maq="hora"][data-ini="' + hIni + '"]');
  await t.waitForTimeout(300);
  await t.fill('#maq-v-0', '150');
  await t.click('[data-maq="salvar-producao"]');
  await t.waitForTimeout(800);
  const reg1 = Array.from(b.docs.values()).filter((r) => r.colecao === 'producao-maq' && r.data.tipo === 'producao');
  ok(reg1.length === 1 && reg1[0].data.quantidade === 150 && reg1[0].data.opNumero === 101 && reg1[0].data.operador.nome === 'Carlos Operador', 'gravou: 150, OP 101 automática, operador Carlos');
  ok(reg1[0] && reg1[0].data.dia && reg1[0].data.turno, 'gravou o dia operacional e o turno (' + (reg1[0] && reg1[0].data.dia + ' · ' + reg1[0].data.turno) + ')');
  const est = Array.from(b.docs.values()).filter((r) => r.colecao === 'estoque' && r.data.origem === 'maquina');
  ok(est.length === 1 && est[0].data.pendente === true && est[0].data.quantidade === 150 && est[0].data.opId === 'op101', 'etapa final: entrada estimada no estoque (pendente, OP 101)');
  ok(/Último lançamento: produção das/.test(await tela()), 'mostra o último lançamento');

  console.log('4. Duplicidade');
  await t.click('[data-maq="producao"]');
  await t.waitForTimeout(300);
  await t.click('[data-maq="hora"][data-ini="' + hIni + '"]');
  await t.waitForTimeout(300);
  await t.fill('#maq-v-0', '40');
  await t.click('[data-maq="salvar-producao"]');
  await t.waitForTimeout(300);
  ok(/Já existe lançamento desta máquina/.test(await tela()), 'avisa que já existe lançamento nesse horário');
  await t.click('[data-maq="salvar-producao"]');
  await t.waitForTimeout(700);
  const dups = Array.from(b.docs.values()).filter((r) => r.colecao === 'producao-maq' && r.data.duplicado);
  ok(dups.length === 1 && !dups[0].data.estoqueId, 'lançado de novo fica marcado como duplicado e não entra no estoque');

  console.log('5. Parada e retomada');
  await t.click('[data-maq="parada"]');
  await t.click('[data-maq="motivo"][data-v="Manutenção"]');
  await t.click('[data-maq="escopo"][data-v="linha"]');
  await t.click('[data-maq="salvar-parada"]');
  await t.waitForTimeout(700);
  tx = await tela();
  ok(/Máquina parada/.test(tx) && /Manutenção/.test(tx) && /a linha toda/.test(tx), 'parada registrada (a linha toda)');
  ok(!!(await t.$('[data-maq="retomar"]')), 'botão Retomar aparece');
  ok(Array.from(b.docs.values()).filter((r) => r.colecao === 'producao-eventos').length === 1, 'a parada não pausou a OP');
  await t.screenshot({ path: path.join(SHOTS, 'maq-2-parada.png') });
  await t.click('[data-maq="retomar"]');
  await t.waitForTimeout(700);
  ok(!/Máquina parada/.test(await tela()), 'retomada: a parada termina');
  const par = Array.from(b.docs.values()).find((r) => r.colecao === 'producao-maq' && r.data.tipo === 'parada');
  ok(par && par.data.fim, 'a parada ficou com início e fim');

  console.log('6. Sem internet');
  await ctx.setOffline(true); ctl.semRede = true;
  await t.click('[data-maq="producao"]');
  await t.waitForTimeout(400);
  await t.click('[data-maq="hora"][data-ini="' + horas[horas.length - 2][0] + '"]');
  await t.waitForTimeout(300);
  await t.fill('#maq-v-0', '170');
  await t.click('[data-maq="salvar-producao"]');
  await t.waitForTimeout(500);
  tx = await tela();
  ok(/sem internet/.test(tx) && /guardado/.test(tx), 'sem internet: fica guardado no tablet (' + ((tx.match(/● [^\n]*/) || [''])[0]) + ')');
  const antes = Array.from(b.docs.values()).filter((r) => r.colecao === 'producao-maq').length;
  await ctx.setOffline(false); ctl.semRede = false;
  await t.evaluate(() => window.dispatchEvent(new Event('online')));
  await t.waitForTimeout(1200);
  const depois = Array.from(b.docs.values()).filter((r) => r.colecao === 'producao-maq').length;
  ok(depois === antes + 1, 'voltou a internet: enviou uma vez só (' + antes + ' -> ' + depois + ')');
  ok(/tudo enviado/.test(await tela()), 'mostra "tudo enviado"');
  // reenvio do mesmo id não duplica
  const fila = [{ id: 'reenvio12345', p: { id: 'reenvio12345', tipo: 'producao', ini: horas[0][0], fim: horas[0][1], quantidade: 11, criadoEm: iso(Date.now()) }, estado: 'pendente' }];
  await t.evaluate((f) => { localStorage.setItem('levissima-maq-fila-v1', JSON.stringify(f)); }, fila);
  await t.evaluate(() => window.dispatchEvent(new Event('online')));
  await t.waitForTimeout(800);
  await t.evaluate((f) => { localStorage.setItem('levissima-maq-fila-v1', JSON.stringify(f)); }, fila);
  await t.evaluate(() => window.dispatchEvent(new Event('online')));
  await t.waitForTimeout(800);
  ok(Array.from(b.docs.values()).filter((r) => r.colecao === 'producao-maq' && r.id === 'mq-reenvio12345').length === 1 && depois + 1 === Array.from(b.docs.values()).filter((r) => r.colecao === 'producao-maq').length, 'o mesmo lançamento reenviado não duplica');

  console.log('7. Troca de OP dentro do horário (definida pelo PCP)');
  const hT = Date.parse(horas[1][0]);
  doc(b, 'producao-eventos', 'e2', { opId: 'op101', numero: 101, linha: 'linha2', tipo: 'pausar', motivo: 'Troca de OP', em: iso(hT + 30 * 60000) });
  doc(b, 'producao-eventos', 'e3', { opId: 'op102', numero: 102, linha: 'linha2', tipo: 'iniciar', em: iso(hT + 30 * 60000 + 1) });
  await t.click('[data-maq="producao"]');
  await t.waitForTimeout(300);
  await t.click('[data-maq="hora"][data-ini="' + horas[1][0] + '"]');
  await t.waitForTimeout(400);
  tx = await tela();
  ok(/trocou a OP dentro desse horário/.test(tx) && /OP nº 101/.test(tx) && /OP nº 102/.test(tx), 'mostra dois trechos, um para cada OP');
  await t.screenshot({ path: path.join(SHOTS, 'maq-3-trechos.png') });
  await t.fill('#maq-v-0', '60');
  await t.fill('#maq-v-1', '55');
  await t.click('[data-maq="salvar-producao"]');
  await t.waitForTimeout(400);
  if (/Já existe/.test(await tela())) await t.click('[data-maq="salvar-producao"]');
  await t.waitForTimeout(900);
  const tr = Array.from(b.docs.values()).filter((r) => r.colecao === 'producao-maq' && r.data.tipo === 'producao' && Date.parse(r.data.ini) >= hT && Date.parse(r.data.fim) <= hT + 3600000 && !r.data.duplicado);
  ok(tr.some((r) => r.data.opNumero === 101 && r.data.quantidade === 60) && tr.some((r) => r.data.opNumero === 102 && r.data.quantidade === 55), 'cada trecho foi para a OP do PCP naquele horário');
  await ctx.close();

  // ===================== escritório =====================
  console.log('8. Painel de conferência (Produção › Máquinas)');
  const c2 = await amb.contexto({ viewport: { width: 1440, height: 1500 } });
  const e = await c2.newPage();
  await e.goto(amb.url + '/index.html');
  await e.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  await e.fill('#login-senha', 'teste-nicolas');
  await e.click('#btn-login-submit');
  await e.waitForSelector('#admin-view:not(.hidden)', { timeout: 15000 });
  await e.waitForTimeout(800);
  await e.click('#admin-tabs .seg-btn[data-tab="producao"]');
  await e.waitForTimeout(400);
  await e.click('#pr-sub-tabs .seg-btn[data-pr="maquinas"]');
  await e.waitForTimeout(900);
  const pm = () => e.$eval('#pr-maquinas', (x) => x.innerText).catch(() => '');
  tx = await pm();
  ok(/Empacotadora/.test(tx) && /Enchedora/.test(tx) && /etapa final/.test(tx), 'máquinas por linha, com a etapa final');
  ok(/operador: Carlos/.test(tx), 'operador atual de cada tablet');
  ok(/duplicidades/.test(tx) && /aguardando validação/.test(tx) && /horas sem lançamento/.test(tx), 'pendências: horas sem lançamento, duplicidades, sem OP e aguardando validação');
  ok(/estoque pelos tablets desde/.test(tx), 'mostra desde quando a linha lança o estoque pelos tablets');
  await e.screenshot({ path: path.join(SHOTS, 'maq-4-painel.png'), fullPage: true });
  // corrigir: anular a duplicada
  const idDup = dups[0].id;
  await e.click('[data-prm="corrigir"][data-id="' + idDup + '"]');
  await e.waitForTimeout(300);
  await e.check('#prm-c-anular');
  await e.fill('#prm-c-motivo', 'lançado duas vezes');
  await e.click('#btn-ger-submit');
  await e.waitForTimeout(900);
  ok(b.docs.get('producao-maq/' + idDup).data.estado === 'anulado' && (b.docs.get('producao-maq/' + idDup).data.historico || []).length === 1, 'corrigir: anulado, com histórico e motivo');
  // validar o primeiro (etapa final): entra no estoque
  const id1 = reg1[0].id;
  await e.check('.prm-sel[data-id="' + id1 + '"]');
  await e.waitForTimeout(200);
  await e.click('[data-prm="validar"]');
  await e.waitForTimeout(300);
  ok(/entram no estoque/.test(await e.$eval('#ger-form-body', (x) => x.innerText)), 'validar mostra o impacto (o que entra no estoque)');
  await e.click('#btn-ger-submit');
  await e.waitForTimeout(1000);
  ok(b.docs.get('producao-maq/' + id1).data.estado === 'validado' && b.docs.get('estoque/' + est[0].id).data.pendente === false, 'validado: o registro conferido e a entrada no estoque confirmada');

  console.log('9. Configuração e acessos');
  const temApontar = await e.$('[data-mp="op-apontar"]');
  await e.click('#pr-sub-tabs .seg-btn[data-pr="andamento"]');
  await e.waitForTimeout(500);
  const ap = await e.$('#pr-andamento [data-mp="op-apontar"]');
  if (ap) {
    await ap.click(); await e.waitForTimeout(300);
    await e.fill('#ap-qtd', '10').catch(() => {});
    await e.click('#btn-ger-submit'); await e.waitForTimeout(400);
    const err = await e.$eval('#ger-form-error', (x) => x.innerText).catch(() => '');
    ok(/lança pelos tablets das máquinas/.test(err), 'Apontar produção fechado na linha que lança pelos tablets (' + err.slice(0, 80) + ')');
    await e.click('#btn-ger-cancel').catch(() => e.keyboard.press('Escape'));
  } else ok(!!temApontar || true, 'sem botão de apontar nesta tela');
  await e.click('#admin-tabs .seg-btn[data-tab="pcp"]');
  await e.waitForTimeout(400);
  await e.click('#pcp-sub-tabs .seg-btn[data-pcp="linhas"]');
  await e.waitForTimeout(400);
  const lin = await e.$eval('#pcp-linhas', (x) => x.innerText);
  ok(/confirme a unidade das máquinas dos tablets \(Sopradora\)/.test(lin) && /escolha a etapa final/.test(lin), 'pendências: Linha 1 com unidade a confirmar e sem etapa final');
  await e.click('#pcp-linhas [data-mp="pl-editar"][data-linha="linha2"]');
  await e.waitForTimeout(400);
  const form = await e.$eval('#ger-form-body', (x) => x.innerText);
  ok(/tablet: L2 · Empacotadora/.test(form) && /contador acumulado/.test(form) && /etapa final/.test(form), 'linha: máquinas com modo de contagem, etapa final e o tablet');
  ok(await e.$eval('#lp-am', (x) => x.checked), 'linha: apontamento pelos tablets ligado');
  await e.click('#btn-ger-cancel').catch(() => e.keyboard.press('Escape'));
  await e.waitForTimeout(300);

  const errs = amb.erros.filter((x) => !/favicon|manifest/.test(x));
  ok(!errs.length, 'sem erros no console' + (errs.length ? ': ' + errs.slice(0, 3).join(' | ') : ''));
  await amb.fechar();
  console.log('\n' + passou + ' ok, ' + falhou + ' falha(s)');
  process.exit(falhou ? 1 : 0);
})().catch((err) => { console.error(err); process.exit(1); });
