/* LEVÍSSIMA · teste: conferente com a permissão "liberar carga" conclui sem a leitura do código de barras (24/11/2026,
 * caso do Jean). Concluir → motivo da liberação → conclusão (conferente pelo acesso, sem senha e sem fotos).
 * Rodar: python3 ferramentas/construir.py && node testes/jean-libera-e2e.js
 */
'use strict';
const fake = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }
fake.USUARIOS.push({ senha: 'teste-jean', papel: 'equipe', nome: 'Jean', ref: 'escritorio:jean-t', modulos: ['abas', 'aba:cargas', 'liberar_carga'] });
(async () => {
  const amb = await fake.criar();
  const b = amb.banco.b;
  const agora = Date.now(), hoje = new Date(agora - 3 * 3600e3).toISOString().slice(0, 10);
  doc(b, 'equipe', 'jean-t', { nome: 'Jean', conferente: true, temPin: true });
  doc(b, 'produtos', 'p510', { nome: 'Água 510ml natural', unidade: 'fardos', unidadesPorPalete: 150, codigosBarras: ['7890000000017'], ordem: 1 });
  doc(b, 'motoristas', 'm1', { nome: 'Motorista Teste' });
  doc(b, 'cargas', 'cJ', { status: 'aberta', motorista: 'Motorista Teste', data: hoje, hora: '06:00',
    clientes: [{ cliente: 'Mercado Exemplo', destino: 'Campinas', itens: [{ produtoId: 'p510', produtoNome: 'Água 510ml natural', quantidade: 300, unidade: 'fardos', paletes: 2, chapatex: 2 }] }],
    totalPaletes: 2, totalChapatex: 2, criadoEm: new Date(agora - 5 * 3600e3).toISOString() });
  const ctx = await amb.contexto({ viewport: { width: 420, height: 900 }, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' });
  const pag = await ctx.newPage();
  const erros = []; pag.on('pageerror', (e) => erros.push(String(e)));
  await pag.goto(amb.url + '/index.html');
  await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  await pag.fill('#login-senha', 'teste-jean'); await pag.click('#btn-login-submit');
  await pag.waitForTimeout(1800);
  await pag.evaluate(() => { const t = document.querySelector('#admin-tabs [data-tab="cargas"]'); if (t) t.click(); });
  await pag.waitForTimeout(600);
  await pag.evaluate(() => document.querySelector('.carga-card[data-id="cJ"] [data-action="concluir-carga"]').click());
  await pag.waitForTimeout(500);
  conf(await pag.isVisible('#lib-motivo') && !(await pag.isVisible('#conf-overlay')), 'Concluir sem leitura: pede o motivo da liberação (não abre a câmera)');
  await pag.fill('#lib-motivo', 'Leitor sem leitura no pátio');
  await pag.click('#btn-ger-submit'); await pag.waitForTimeout(900);
  const c0 = b.docs.get('cargas/cJ').data;
  conf(c0.excecao && c0.excecao.semConferencia && c0.excecao.por === 'Jean' && /Leitor/.test(c0.excecao.motivo), 'liberação registrada no nome do Jean, com o motivo');
  conf(await pag.isVisible('#carga-conclude-overlay') && /✓ Conferente: Jean/.test(await pag.textContent('#cgc-conferente-eu')), 'abre a conclusão com o Jean como conferente (sem senha)');
  for (const cv of ['#cgc-sig-motorista-canvas', '#cgc-sig-conferente-canvas']) {
    await pag.locator(cv).scrollIntoViewIfNeeded();
    const r = await pag.locator(cv).boundingBox();
    await pag.mouse.move(r.x + 20, r.y + 20); await pag.mouse.down();
    await pag.mouse.move(r.x + 90, r.y + 50, { steps: 5 }); await pag.mouse.move(r.x + 150, r.y + 30, { steps: 5 }); await pag.mouse.up();
  }
  await pag.click('#carga-conclude-form button[type="submit"]'); await pag.waitForTimeout(1000);
  const c = b.docs.get('cargas/cJ').data;
  conf(c.status === 'concluida' && c.conferente === 'Jean', 'Jean conclui o carregamento sem leitura e sem fotos (erro na tela: ' + ((await pag.textContent('#carga-conclude-error').catch(() => '')) || '').trim() + ')');
  conf(!erros.length, 'sem erros de JavaScript' + (erros.length ? ': ' + erros.join(' | ') : ''));
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
