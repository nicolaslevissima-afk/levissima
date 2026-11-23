/* LEVÍSSIMA · teste: tocar fora da caixa (pedido de 23/11/2026). Com algo digitado, a caixa é minimizada (barra
 * "Pausadas") e volta com tudo; sem nada digitado, fecha como antes.
 * Rodar: python3 ferramentas/construir.py && node testes/fora-minimiza-e2e.js
 */
'use strict';
const { criar } = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }

(async () => {
  const amb = await criar();
  const ctx = await amb.contexto();
  const pag = await ctx.newPage();
  await pag.goto(amb.url + '/index.html');
  await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  await pag.fill('#login-senha', 'teste-nicolas');
  await pag.click('#btn-login-submit');
  await pag.waitForSelector('#admin-view:not(.hidden)', { timeout: 15000 });
  await pag.waitForTimeout(800);
  await pag.evaluate(() => document.querySelector('#admin-tabs [data-tab="compras"]').click());
  await pag.waitForTimeout(500);
  const fora = () => pag.click('#ger-sheet-overlay', { position: { x: 6, y: 6 } });
  // sem nada digitado: fecha
  await pag.evaluate(() => document.querySelector('[data-oc="novo"]').click());
  await pag.waitForSelector('#ger-sheet-overlay:not(.hidden)');
  await fora();
  await pag.waitForTimeout(300);
  conf(await pag.$eval('#ger-sheet-overlay', (e) => e.classList.contains('hidden')) && await pag.$eval('#telas-pausadas', (e) => e.classList.contains('hidden')), 'sem nada digitado: tocar fora fecha, como antes');
  // com algo digitado: minimiza e volta com o texto
  await pag.evaluate(() => document.querySelector('[data-oc="novo"]').click());
  await pag.waitForSelector('#ger-sheet-overlay:not(.hidden)');
  await pag.fill('#oc-itens .oc-desc', 'Rolamento 6205');
  await fora();
  await pag.waitForTimeout(400);
  conf(await pag.$eval('#ger-sheet-overlay', (e) => e.classList.contains('hidden')) && !(await pag.$eval('#telas-pausadas', (e) => e.classList.contains('hidden'))), 'com algo digitado: tocar fora minimiza (barra Pausadas)');
  await pag.click('#telas-pausadas [data-tela-voltar]');
  await pag.waitForTimeout(300);
  conf(!(await pag.$eval('#ger-sheet-overlay', (e) => e.classList.contains('hidden'))) && await pag.$eval('#oc-itens .oc-desc', (e) => e.value) === 'Rolamento 6205', 'tocar na barra volta com o que foi digitado');
  conf(!amb.erros.length, 'sem erros de JavaScript' + (amb.erros.length ? ': ' + amb.erros.slice(0, 3).join(' | ') : ''));
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
