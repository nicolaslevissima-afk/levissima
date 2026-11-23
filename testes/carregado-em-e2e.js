/* LEVÍSSIMA · teste: "Carregado em" ao concluir a carga depois que ela saiu (23/11/2026).
 * A carga concluída no app depois de uma contagem do estoque, mas que saiu ANTES da contagem, não pode ser
 * descontada de novo: o estoque usa carregadoEm (quando informado) no lugar de concluidoEm.
 * Rodar: python3 ferramentas/construir.py && node testes/carregado-em-e2e.js
 */
'use strict';
const { criar } = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }
function local(ms) { // valor de <input type="datetime-local"> no fuso de São Paulo
  const d = new Date(ms - 3 * 3600e3);
  return d.toISOString().slice(0, 16);
}

(async () => {
  const amb = await criar();
  const b = amb.banco.b;
  const agora = Date.now();
  const hoje = new Date(agora - 3 * 3600e3).toISOString().slice(0, 10);
  doc(b, 'produtos', 'p510', { nome: 'Água 510ml natural', unidade: 'fardos', unidadesPorPalete: 150, codigosBarras: ['7890000000017'], ordem: 1 });
  doc(b, 'motoristas', 'm1', { nome: 'Motorista Teste' });
  doc(b, 'estoque', 'cont1', { tipo: 'contagem', produtoId: 'p510', produtoNome: 'Água 510ml natural', quantidade: 1500, unidade: 'fardos',
    em: new Date(agora - 2 * 3600e3).toISOString(), data: hoje, locais: [] });
  function carga(id) {
    doc(b, 'cargas', id, { status: 'pendente', motorista: 'Motorista Teste', data: hoje, hora: '07:00',
      clientes: [{ cliente: 'Mercado Exemplo', destino: 'Campinas', itens: [{ produtoId: 'p510', produtoNome: 'Água 510ml natural', quantidade: 150, unidade: 'fardos', paletes: 1, chapatex: 1 }] }],
      totalPaletes: 1, totalChapatex: 1, numeroPager: id === 'cargaANTES' ? '7' : '8', excecao: { semConferencia: true, por: 'Teste', motivo: 'teste sem leitura', em: new Date(agora - 4 * 3600e3).toISOString() }, criadoEm: new Date(agora - 5 * 3600e3).toISOString() });
  }
  carga('cargaANTES'); carga('cargaAGORA');
  const ctx = await amb.contexto({ viewport: { width: 1200, height: 900 }, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' });
  const pag = await ctx.newPage();
  const erros = []; pag.on('pageerror', (e) => erros.push(String(e)));
  await pag.goto(amb.url + '/index.html');
  await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  await pag.fill('#login-senha', 'teste-nicolas');
  await pag.click('#btn-login-submit');
  await pag.waitForTimeout(1800);

  async function estoqueTexto() {
    if (await pag.isVisible('#btn-close-doc')) { await pag.click('#btn-close-doc'); await pag.waitForTimeout(300); }
    await pag.click('#admin-tabs [data-tab="estoque"]');
    await pag.waitForTimeout(600);
    return pag.evaluate(() => {
      const tr = Array.from(document.querySelectorAll('#tab-estoque tr, #tab-estoque .card')).find((x) => /Água 510ml natural/.test(x.textContent));
      return tr ? tr.textContent.replace(/\s+/g, ' ') : '';
    });
  }
  async function concluir(id, carregado) {
    await pag.click('#admin-tabs [data-tab="cargas"]');
    await pag.waitForTimeout(600);
    await pag.evaluate((id) => document.querySelector('[data-action="concluir-carga"][data-id="' + id + '"]').click(), id);
    await pag.waitForSelector('#carga-conclude-overlay:not(.hidden)');
    const padrao = await pag.inputValue('#cgc-carregado-em');
    if (carregado !== undefined) await pag.fill('#cgc-carregado-em', carregado);
    await pag.fill('#cgc-conferente', 'Conferente Teste');
    for (const cv of ['#cgc-sig-motorista-canvas', '#cgc-sig-conferente-canvas']) {
      await pag.locator(cv).scrollIntoViewIfNeeded();
      const r = await pag.locator(cv).boundingBox();
      await pag.mouse.move(r.x + 20, r.y + 20); await pag.mouse.down();
      await pag.mouse.move(r.x + 80, r.y + 50, { steps: 5 }); await pag.mouse.move(r.x + 140, r.y + 30, { steps: 5 }); await pag.mouse.up();
    }
    await pag.click('#carga-conclude-form button[type="submit"]');
    await pag.waitForTimeout(900);
    return padrao;
  }

  const t0 = await estoqueTexto();
  conf(/1\.500/.test(t0) || /10 pal/.test(t0), 'estoque começa com a contagem (1.500 fardos): ' + t0.slice(0, 120));

  // 1) data no futuro: recusa
  await concluir('cargaANTES', local(agora + 3 * 3600e3));
  conf(/não pode ser depois de agora/.test(await pag.textContent('#carga-conclude-error')) && b.docs.get('cargas/cargaANTES').data.status !== 'concluida', 'carregado no futuro é recusado');
  await pag.fill('#cgc-carregado-em', local(agora - 3 * 3600e3));
  await pag.click('#carga-conclude-form button[type="submit"]');
  await pag.waitForTimeout(900);
  const cA = b.docs.get('cargas/cargaANTES').data;
  conf(cA.status === 'concluida' && cA.carregadoEm && Math.abs(new Date(cA.carregadoEm).getTime() - (agora - 3 * 3600e3)) < 120e3, 'grava carregadoEm (saiu 3 h antes): ' + cA.carregadoEm);
  const t1 = await estoqueTexto();
  conf(/1\.500/.test(t1) || /10 pal/.test(t1), 'carga que saiu antes da contagem não desconta de novo: ' + t1.slice(0, 120));

  // 2) concluída na hora (valor padrão = agora): sem carregadoEm, desconta
  const padrao = await concluir('cargaAGORA');
  conf(Math.abs(new Date(padrao + ':00-03:00').getTime() - Date.now()) < 5 * 60e3, 'campo já vem com a hora de agora (' + padrao + ')');
  const cB = b.docs.get('cargas/cargaAGORA').data;
  conf(cB.status === 'concluida' && !cB.carregadoEm, 'concluída na hora não grava carregadoEm');
  const t2 = await estoqueTexto();
  conf(/1\.350/.test(t2) || /9 pal/.test(t2), 'carga carregada depois da contagem desconta (1.350): ' + t2.slice(0, 120));

  conf(!erros.length, 'sem erros de JavaScript' + (erros.length ? ': ' + erros.join(' | ') : ''));
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
