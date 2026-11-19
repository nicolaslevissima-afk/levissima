/* LEVÍSSIMA · teste: carregamento com UMA conferência por código de barras (19/11/2026).
 * A 1ª conferência sem divergência já libera "Concluir carregamento"; não pede 2ª rodada nem outra pessoa.
 * Rodar: python3 ferramentas/construir.py && node testes/conferencia-uma-e2e.js
 */
'use strict';
const { criar } = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }

(async () => {
  const amb = await criar();
  const b = amb.banco.b;
  const hoje = new Date(Date.now() - 3 * 3600e3).toISOString().slice(0, 10);
  doc(b, 'produtos', 'p510', { nome: 'Água 510ml natural', unidade: 'fardos', unidadesPorPalete: 150, codigosBarras: ['7890000000017'], ordem: 1 });
  doc(b, 'motoristas', 'm1', { nome: 'Motorista Teste' });
  doc(b, 'cargas', 'cargaUMA01', { status: 'pendente', motorista: 'Motorista Teste', data: hoje, hora: '07:00',
    clientes: [{ cliente: 'Mercado Exemplo', destino: 'Campinas', itens: [{ produtoId: 'p510', produtoNome: 'Água 510ml natural', quantidade: 300, unidade: 'fardos', paletes: 2, chapatex: 2 }] }],
    totalPaletes: 2, totalChapatex: 2, numeroPager: '7', criadoEm: new Date().toISOString() });
  const ctx = await amb.contexto({ viewport: { width: 1200, height: 900 }, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' });
  const pag = await ctx.newPage();
  const erros = []; pag.on('pageerror', (e) => erros.push(String(e)));
  await pag.goto(amb.url + '/index.html');
  await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  await pag.fill('#login-senha', 'teste-nicolas');
  await pag.click('#btn-login-submit');
  await pag.waitForSelector('#app:not(.hidden), .app-shell, #tabbar', { timeout: 15000 }).catch(() => {});
  await pag.waitForTimeout(1500);
  await pag.evaluate(() => { if (typeof switchTab === 'function') switchTab('cargas'); });
  await pag.waitForTimeout(800);
  const badge = pag.locator('[data-action="conf-barras"][data-id="cargaUMA01"]').first();
  await badge.waitFor({ state: 'attached', timeout: 8000 });
  conf(/Conferência por código de barras/.test(await badge.textContent()) && !/Dupla/.test(await badge.textContent()), 'cartão pede "Conferência por código de barras" (sem "dupla")');
  await pag.evaluate(() => document.querySelector('[data-action="conf-barras"][data-id="cargaUMA01"]').click());
  await pag.waitForSelector('#conf-overlay:not(.hidden)');
  conf(/Conferência por código de barras/.test(await pag.textContent('#conf-title')) && !/2ª|outra pessoa/.test(await pag.textContent('#conf-overlay')), 'folha da conferência sem 2ª rodada nem "outra pessoa"');
  for (let i = 0; i < 2; i++) { await pag.fill('#conf-codigo', '7890000000017'); await pag.click('#btn-conf-lancar'); await pag.waitForTimeout(150); }
  if (await pag.isVisible('#conf-nome-label')) await pag.fill('#conf-nome', 'Conferente Teste');
  await pag.click('#btn-conf-finalizar');
  await pag.waitForSelector('#conf-overlay.hidden', { state: 'attached', timeout: 6000 });
  await pag.waitForTimeout(800);
  const d = b.docs.get('cargas/cargaUMA01').data.dupla || {};
  conf(d.r1 && d.r1.ok && !d.r2, 'grava só a 1ª conferência, sem divergência');
  const badge2 = await pag.locator('[data-action="conf-barras"][data-id="cargaUMA01"]').first().textContent();
  conf(/✓ Conferência: Conferente/.test(badge2) && !/2ª/.test(badge2), 'cartão mostra a conferência ok (' + badge2.trim() + ')');
  // concluir o carregamento abre direto (sem pedir 2ª conferência nem liberação)
  await pag.evaluate(() => { const b = document.querySelector('[data-action="concluir-carga"][data-id="cargaUMA01"]'); if (b) b.click(); });
  await pag.waitForTimeout(800);
  const abriu = await pag.isVisible('#carga-conclude-overlay');
  if (!abriu) console.log('    aviso na tela:', await pag.evaluate(() => (document.getElementById('toast') || {}).textContent), await pag.evaluate(() => !!document.querySelector('[data-action="concluir-carga"][data-id="cargaUMA01"]')));
  const liberacao = await pag.$('#lib-overlay:not(.hidden), #liberacao-overlay:not(.hidden)');
  conf(abriu && !liberacao, 'uma conferência ok já abre "Concluir carregamento"');
  conf(!erros.length, 'sem erros de JavaScript' + (erros.length ? ': ' + erros.join(' | ') : ''));
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
