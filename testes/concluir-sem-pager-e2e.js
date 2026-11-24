/* LEVÍSSIMA · teste: concluir o carregamento sem o pager (24/11/2026).
 * O cartão da carga de hoje (com motorista) mostra "Concluir carregamento" direto; "Entregar pager" fica ao lado.
 * Sem motorista, continua "Definir motorista". Carga de outro dia: "Ver detalhes".
 * Rodar: python3 ferramentas/construir.py && node testes/concluir-sem-pager-e2e.js
 */
'use strict';
const { criar } = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }
(async () => {
  const amb = await criar();
  const b = amb.banco.b;
  const agora = Date.now(), hoje = new Date(agora - 3 * 3600e3).toISOString().slice(0, 10), amanha = new Date(agora + 21 * 3600e3).toISOString().slice(0, 10);
  doc(b, 'produtos', 'p510', { nome: 'Água 510ml natural', unidade: 'fardos', unidadesPorPalete: 150, ordem: 1 });
  doc(b, 'motoristas', 'm1', { nome: 'Motorista Teste' });
  const carga = (id, extra) => doc(b, 'cargas', id, Object.assign({ status: 'aberta', motorista: 'Motorista Teste', data: hoje, hora: '06:00',
    clientes: [{ cliente: 'Mercado Exemplo', destino: 'Campinas', itens: [{ produtoId: 'p510', produtoNome: 'Água 510ml natural', quantidade: 150, unidade: 'fardos', paletes: 1, chapatex: 1 }] }],
    totalPaletes: 1, totalChapatex: 1, criadoEm: new Date(agora - 5 * 3600e3).toISOString(), excecao: { semConferencia: true, por: 'Teste', motivo: 'teste', em: new Date(agora - 3600e3).toISOString() } }, extra || {}));
  carga('sP');
  carga('sM', { motorista: '' });
  carga('fut', { data: amanha });
  const ctx = await amb.contexto({ viewport: { width: 1100, height: 1000 }, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' });
  const pag = await ctx.newPage();
  const erros = []; pag.on('pageerror', (e) => erros.push(String(e)));
  await pag.goto(amb.url + '/index.html');
  await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  await pag.fill('#login-senha', 'teste-nicolas'); await pag.click('#btn-login-submit');
  await pag.waitForTimeout(1800);
  await pag.click('#admin-tabs [data-tab="cargas"]'); await pag.waitForTimeout(600);
  const acoes = (id) => pag.evaluate((id) => { const c = document.querySelector('.carga-card[data-id="' + id + '"] .carga-actions'); return c ? Array.from(c.querySelectorAll('button')).map((x) => x.dataset.action).join(',') : ''; }, id);
  conf(await acoes('sP') === 'concluir-carga,pager-entregar,detalhes', 'carga de hoje sem pager: Concluir, Entregar pager e Detalhes (' + await acoes('sP') + ')');
  conf((await acoes('sM')).split(',')[0] === 'edit-carga', 'sem motorista: continua "Definir motorista" (' + await acoes('sM') + ')');
  conf((await acoes('fut')).split(',')[0] === 'detalhes', 'carga de outro dia: Ver detalhes (' + await acoes('fut') + ')');
  await pag.evaluate(() => document.querySelector('.carga-card[data-id="sP"] [data-action="concluir-carga"]').click());
  await pag.waitForTimeout(500);
  conf(await pag.isVisible('#carga-conclude-overlay'), 'Concluir sem pager abre a conclusão');
  conf(!erros.length, 'sem erros de JavaScript' + (erros.length ? ': ' + erros.join(' | ') : ''));
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
