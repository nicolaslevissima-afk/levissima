/* LEVÍSSIMA · teste: turnos da produção puxados do cadastro do RH (23/11/2026).
 * O RH edita os turnos (dias, entrada, saída, refeição) e o PCP usa esses horários nas linhas (a refeição não para a
 * linha). O editor da linha escolhe o turno do RH; a disponibilidade da semana sai das faixas do RH.
 * Rodar: python3 ferramentas/construir.py && node testes/turnos-e2e.js
 */
'use strict';
const { criar } = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }

(async () => {
  const amb = await criar();
  const b = amb.banco.b;
  doc(b, 'mp-config', 'turnos', { turnos: [
    { id: 'desc1', nome: 'Desc 1 (6x1)', faixas: [{ dias: [1], entrada: '03:06', saida: '13:15', refeicaoDe: '07:00', refeicaoAte: '08:00' }, { dias: [2, 3, 4, 5, 6], entrada: '05:20', saida: '13:15', refeicaoDe: '10:00', refeicaoAte: '11:00' }] },
    { id: 'desc2', nome: 'Desc 2 (6x1)', faixas: [{ dias: [1, 2, 3, 4, 5], entrada: '12:10', saida: '21:00' }] },
    { id: 'galao-dia', nome: 'Galão · turno dia', faixas: [{ dias: [1, 2, 3, 4, 5], entrada: '05:00', saida: '15:00' }] },
    { id: 'galao-noite', nome: 'Galão · turno noite', faixas: [{ dias: [1, 2, 3, 4, 5], entrada: '11:00', saida: '21:00' }] }
  ] });
  doc(b, 'mp-config', 'linhas-producao', { linhas: [
    { id: 'l1', nome: 'Linha 1', un: 'fardos', porHora: 400, op: true, produtos: [], maquinas: [], turnos: [{ nome: 'DESC 1', rhId: 'desc1' }] },
    { id: 'g10', nome: 'Linha 10 L', un: 'galões', porHora: 90, op: true, produtos: [], maquinas: [], turnos: [{ nome: 'Galão · turno dia', rhId: 'galao-dia' }, { nome: 'Galão · turno noite', rhId: 'galao-noite' }] },
    { id: 'copo', nome: 'Copos', un: 'caixas', porHora: 50, op: true, produtos: [], maquinas: [], turnos: [{ nome: 'Manhã', inicio: '06:00', fim: '14:00', dias: [1, 2, 3, 4, 5], pausa: 0 }] }
  ], excecoes: [] });
  const ctx = await amb.contexto({ viewport: { width: 1280, height: 1400 }, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' });
  const pag = await ctx.newPage();
  const erros = []; pag.on('pageerror', (e) => erros.push(String(e)));
  await pag.goto(amb.url + '/index.html');
  await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  await pag.fill('#login-senha', 'teste-nicolas');
  await pag.click('#btn-login-submit');
  await pag.waitForTimeout(1800);
  const txt = (sel) => pag.$eval(sel, (e) => e.innerText).catch(() => '');
  const cartao = (nome) => pag.evaluate((nome) => { const c = Array.from(document.querySelectorAll('#pcp-linhas .pcp-lcard')).find((x) => x.querySelector('b') && x.querySelector('b').textContent === nome); return c ? c.innerText : ''; }, nome);
  async function abrirLinhas() {
    await pag.click('#admin-tabs .seg-btn[data-tab="pcp"]'); await pag.waitForTimeout(500);
    await pag.click('#pcp-sub-tabs .seg-btn[data-pcp="linhas"]'); await pag.waitForTimeout(500);
  }

  // 1) PCP mostra o horário do RH
  await abrirLinhas();
  let l1 = await cartao('Linha 1');
  conf(/DESC 1\s*\(do RH: Desc 1 \(6x1\)\)/.test(l1) && /seg 03:06 às 13:15; ter a sáb 05:20 às 13:15/.test(l1), 'Linha 1: DESC 1 com o horário do RH (segunda diferente)');
  conf(/a refeição não para a linha/.test(l1), 'a refeição não para a linha');
  conf(/seg: 10,2 h · ter a sáb: 7,9 h · dom: sem produção/.test(l1), 'disponibilidade da Linha 1 pelas faixas do RH: ' + (l1.match(/Disponível para produzir nesta semana: [^\n]*/) || [''])[0]);
  let g10 = await cartao('Linha 10 L');
  conf(/seg a sex: 16 h/.test(g10), 'Linha 10 L: Galão dia (5h–15h) + noite (11h–21h) = 16 h por dia: ' + (g10.match(/Disponível para produzir nesta semana: [^\n]*/) || [''])[0]);

  // 2) editor da linha: escolhe o turno do RH
  await pag.click('#pcp-linhas [data-mp="pl-editar"][data-linha="l1"]'); await pag.waitForTimeout(400);
  let form = await txt('#ger-form-body');
  conf(/Horário do RH: Seg 03:06–13:15 · Ter a sáb 05:20–13:15/.test(form) && (await pag.$eval('#lp-trh-0', (e) => e.value)) === 'desc1' && !(await pag.$('#lp-ti-0')), 'editor: turno do RH sem campos de horário (vem do RH)');
  await pag.selectOption('#lp-add-rh', 'galao-noite');
  await pag.click('#ger-form-body [data-ger="lp-turno-rh"]'); await pag.waitForTimeout(300);
  await pag.click('#btn-ger-submit'); await pag.waitForTimeout(600);
  let linhas = b.docs.get('mp-config/linhas-producao').data.linhas;
  conf(JSON.stringify(linhas.find((x) => x.id === 'l1').turnos) === JSON.stringify([{ nome: 'DESC 1', rhId: 'desc1' }, { nome: 'Galão · turno noite', rhId: 'galao-noite' }]), 'salva só o nome e o turno do RH: ' + JSON.stringify(linhas.find((x) => x.id === 'l1').turnos));
  // turno próprio da linha passa a puxar do RH
  await pag.click('#pcp-linhas [data-mp="pl-editar"][data-linha="copo"]'); await pag.waitForTimeout(400);
  conf(!!(await pag.$('#lp-ti-0')), 'turno próprio continua com os campos de horário');
  await pag.selectOption('#lp-trh-0', 'desc2'); await pag.waitForTimeout(300);
  form = await txt('#ger-form-body');
  conf(/Horário do RH: Seg a sex 12:10–21:00/.test(form) && !(await pag.$('#lp-ti-0')), 'trocar para "do RH" mostra o horário do RH');
  await pag.click('#btn-ger-submit'); await pag.waitForTimeout(600);
  linhas = b.docs.get('mp-config/linhas-producao').data.linhas;
  conf(JSON.stringify(linhas.find((x) => x.id === 'copo').turnos) === JSON.stringify([{ nome: 'Manhã', rhId: 'desc2' }]), 'Copos: o turno Manhã puxa o Desc 2 do RH');

  // 3) RH edita os turnos
  await pag.click('#admin-tabs .seg-btn[data-tab="rh"]'); await pag.waitForTimeout(800);
  const rh = await txt('#rh-turnos');
  conf(/O PCP puxa daqui/.test(rh) && /Galão · turno dia\s*Seg a sex 05:00–15:00\s*PCP: Linha 10 L/.test(rh) && /Seg 03:06–13:15 \(refeição 07:00–08:00\)/.test(rh), 'RH › Turnos: horários, refeição e as linhas do PCP que usam');
  await pag.click('#rh-turnos [data-rh="turnos"]'); await pag.waitForTimeout(400);
  conf(/usado no PCP: Linha 10 L/i.test(await txt('#ger-form-body')) && !(await pag.$('#ger-form-body [data-ger="tr-x"][data-i="2"]')), 'turno usado por uma linha não tem "Tirar o turno"');
  await pag.fill('#tr-e-2-0', '06:00');
  await pag.click('#ger-form-body [data-ger="tr-novo"]'); await pag.waitForTimeout(200);
  await pag.fill('#tr-n-4', 'Extra de sábado');
  for (let d = 1; d <= 5; d++) await pag.uncheck('#tr-d-4-0-' + d);
  await pag.check('#tr-d-4-0-6');
  await pag.fill('#tr-e-4-0', '07:00'); await pag.fill('#tr-s-4-0', '11:00');
  // mesmo dia em dois horários: recusa
  await pag.click('#ger-form-body [data-ger="tr-faixa"][data-i="4"]'); await pag.waitForTimeout(200);
  await pag.check('#tr-d-4-1-6'); await pag.fill('#tr-e-4-1', '12:00'); await pag.fill('#tr-s-4-1', '14:00');
  await pag.click('#btn-ger-submit'); await pag.waitForTimeout(400);
  conf(/o mesmo dia está em dois horários/.test(await txt('#ger-form-error')), 'recusa o mesmo dia em dois horários');
  await pag.click('#ger-form-body [data-ger="tr-faixa-x"][data-i="4"][data-k="1"]'); await pag.waitForTimeout(200);
  await pag.click('#btn-ger-submit'); await pag.waitForTimeout(700);
  const reg = b.docs.get('mp-config/turnos').data;
  const extra = reg.turnos.find((t) => t.nome === 'Extra de sábado');
  conf(reg.turnos.length === 5 && reg.turnos[2].faixas[0].entrada === '06:00' && extra && extra.id === 'extra-de-sabado' && JSON.stringify(extra.faixas) === JSON.stringify([{ dias: [6], entrada: '07:00', saida: '11:00' }]) && !!reg.atualizadoPor,
    'salva o cadastro (Galão dia às 06:00 e o turno novo): ' + JSON.stringify(extra));
  // 4) o PCP acompanha
  await abrirLinhas();
  g10 = await cartao('Linha 10 L');
  conf(/seg a sex: 15 h/.test(g10), 'PCP acompanha o RH: Linha 10 L com 15 h por dia: ' + (g10.match(/Disponível para produzir nesta semana: [^\n]*/) || [''])[0]);

  conf(!erros.length, 'sem erros de JavaScript' + (erros.length ? ': ' + erros.join(' | ') : ''));
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
