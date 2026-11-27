/* LEVÍSSIMA · teste: Novidades para você (Início) somem depois de vistas (27/11/2026).
 * Tocar leva ao lugar; na volta ao Início a novidade não aparece mais — também no outro aparelho (preferências da conta).
 * Se acontecer algo novo no mesmo assunto (o texto muda), ela volta.
 * Rodar: python3 ferramentas/construir.py && node testes/novidades-vistas-e2e.js
 */
'use strict';
const fake = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }

(async () => {
  const amb = await fake.criar();
  const b = amb.banco.b;
  const agora = new Date().toISOString();
  doc(b, 'brindes', 'b1', { titulo: 'Caneca', status: 'aprovacao', criadoEm: agora });
  const erros = [];
  async function entrar() {
    const ctx = await amb.contexto({ viewport: { width: 1100, height: 1000 }, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' });
    const pag = await ctx.newPage();
    pag.on('pageerror', (e) => erros.push(String(e)));
    await pag.goto(amb.url + '/index.html');
    await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
    await pag.fill('#login-senha', 'teste-nicolas'); await pag.click('#btn-login-submit'); await pag.waitForTimeout(1800);
    await pag.evaluate(() => document.querySelector('#admin-tabs .seg-btn[data-tab="inicio"]').click());
    await pag.waitForTimeout(800);
    return { ctx, pag };
  }
  const novTxt = (pag) => pag.evaluate(() => { const e = document.getElementById('ini-novidades'); return e ? e.textContent : ''; });
  const inicio = async (pag) => { await pag.evaluate(() => document.querySelector('#admin-tabs .seg-btn[data-tab="inicio"]').click()); await pag.waitForTimeout(600); };

  console.log('Aparelho 1:');
  const a1 = await entrar();
  conf(/1 brinde ou presente esperando a sua aprovação/.test(await novTxt(a1.pag)), 'a novidade aparece');
  await a1.pag.evaluate(() => { const b = Array.from(document.querySelectorAll('#ini-novidades [data-nov]')).find((x) => /brinde/.test(x.textContent)); b.click(); });
  await a1.pag.waitForTimeout(500);
  conf(await a1.pag.evaluate(() => !document.getElementById('tab-brindes').classList.contains('hidden')), 'tocar leva aos Brindes');
  await inicio(a1.pag);
  conf(!/brinde/.test(await novTxt(a1.pag)), 'na volta ao Início, a novidade não aparece mais');
  const pref = (b.prefs && b.prefs.get('mestre')) || {};
  conf(pref.dados && pref.dados.novidades && Object.keys(pref.dados.novidades).length === 1, 'ficou guardada na conta (preferências)');

  console.log('Aparelho 2 (outro navegador):');
  const a2 = await entrar();
  await a2.pag.waitForTimeout(800);
  conf(!/brinde/.test(await novTxt(a2.pag)), 'no outro aparelho também não aparece');

  console.log('Algo novo no mesmo assunto:');
  doc(b, 'brindes', 'b2', { titulo: 'Agenda', status: 'aprovacao', criadoEm: agora });
  amb.banco.eventos && amb.banco.eventos('docs', 'INSERT', { colecao: 'brindes', id: 'b2', data: b.docs.get('brindes/b2').data }, null);
  await a2.pag.waitForTimeout(800);
  await inicio(a2.pag);
  conf(/2 brindes ou presentes esperando a sua aprovação/.test(await novTxt(a2.pag)), 'com mais um brinde, a novidade volta (' + (await novTxt(a2.pag)).replace(/\s+/g, ' ').slice(0, 120) + ')');

  conf(!erros.length, 'sem erros de JavaScript' + (erros.length ? ': ' + erros.join(' | ') : ''));
  await a1.ctx.close(); await a2.ctx.close();
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
