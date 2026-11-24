/* LEVÍSSIMA · teste: Cargas sem a senha de 4 números para quem entrou com o próprio acesso (24/11/2026, caso do Jean).
 * Conferente com o próprio acesso: finaliza a conferência e conclui o carregamento com o nome dele, sem senha.
 * Quem não é do faturamento não vê "Dar ok"; quem é dá o ok com um toque. Senha mestre continua com a senha.
 * Rodar: python3 ferramentas/construir.py && node testes/cargas-sem-senha-e2e.js
 */
'use strict';
const fake = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }
fake.USUARIOS.push(
  { senha: 'teste-jean', papel: 'equipe', nome: 'Jean', ref: 'escritorio:jean-t', modulos: ['abas', 'aba:cargas', 'ver:paletes', 'aba:paletes'] },
  { senha: 'teste-fatura', papel: 'equipe', nome: 'Fatura', ref: 'escritorio:fat-t', modulos: ['abas', 'aba:cargas'] }
);

(async () => {
  const amb = await fake.criar();
  const b = amb.banco.b;
  const agora = Date.now();
  const hoje = new Date(agora - 3 * 3600e3).toISOString().slice(0, 10);
  doc(b, 'equipe', 'jean-t', { nome: 'Jean', conferente: true, temPin: true });
  doc(b, 'equipe', 'fat-t', { nome: 'Fatura', faturamento: true, temPin: true });
  doc(b, 'produtos', 'p510', { nome: 'Água 510ml natural', unidade: 'fardos', unidadesPorPalete: 150, codigosBarras: ['7890000000017'], ordem: 1 });
  doc(b, 'motoristas', 'm1', { nome: 'Motorista Teste' });
  const carga = (id, pager, extra) => doc(b, 'cargas', id, Object.assign({ status: 'aberta', motorista: 'Motorista Teste', data: hoje, hora: '05:00',
    clientes: [{ cliente: 'Mercado Exemplo', destino: 'Campinas', itens: [{ produtoId: 'p510', produtoNome: 'Água 510ml natural', quantidade: 150, unidade: 'fardos', paletes: 1, chapatex: 1 }] }],
    totalPaletes: 1, totalChapatex: 1, numeroPager: pager, criadoEm: new Date(agora - 5 * 3600e3).toISOString() }, extra || {}));
  carga('cJ1', '11');
  carga('cJ2', '12', { excecao: { semConferencia: true, por: 'Angélica', motivo: 'teste', em: new Date(agora - 3600e3).toISOString() } });

  async function entrar(senha) {
    const ctx = await amb.contexto({ viewport: { width: 1100, height: 1000 }, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' });
    const pag = await ctx.newPage();
    pag.on('pageerror', (e) => erros.push(senha + ': ' + String(e)));
    await pag.goto(amb.url + '/index.html');
    await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
    await pag.fill('#login-senha', senha);
    await pag.click('#btn-login-submit');
    await pag.waitForTimeout(1800);
    await pag.evaluate(() => { const t = document.querySelector('#admin-tabs [data-tab="cargas"]'); if (t) t.click(); });
    await pag.waitForTimeout(700);
    return { ctx, pag };
  }
  const erros = [];
  const pinAberto = (pag) => pag.isVisible('#pin-overlay');
  const cardTxt = (pag, id) => pag.evaluate((id) => { const e = document.querySelector('[data-action="conf-barras"][data-id="' + id + '"]'); const c = e && e.closest('.carga-card, .frete-item, article, li, div.card'); return c ? c.textContent : ''; }, id);

  // ---------- Jean (conferente, próprio acesso) ----------
  console.log('Jean:');
  let { ctx, pag } = await entrar('teste-jean');
  conf(!(await pag.$('[data-action="fat-ok"][data-id="cJ1"]')), 'Jean não é do faturamento: não aparece "Dar ok"');
  conf(/Sem ok do faturamento/.test(await pag.textContent('#tab-cargas')), 'mas vê que está sem ok do faturamento');
  await pag.evaluate(() => document.querySelector('[data-action="conf-barras"][data-id="cJ1"]').click());
  await pag.waitForSelector('#conf-overlay:not(.hidden)');
  await pag.fill('#conf-codigo', '7890000000017'); await pag.click('#btn-conf-lancar'); await pag.waitForTimeout(200);
  await pag.click('#btn-conf-finalizar'); await pag.waitForTimeout(800);
  const d = (b.docs.get('cargas/cJ1').data.dupla || {}).r1 || {};
  conf(!(await pinAberto(pag)) && d.por === 'Jean' && d.porId === 'jean-t' && d.ok === true, 'conferência finalizada sem senha, no nome do Jean: ' + JSON.stringify({ por: d.por, porId: d.porId, ok: d.ok }));
  // concluir: o conferente já é o Jean
  await pag.evaluate(() => { const e = document.querySelector('[data-action="concluir-carga"][data-id="cJ1"]'); if (e) e.click(); });
  await pag.waitForSelector('#carga-conclude-overlay:not(.hidden)', { timeout: 5000 });
  conf(/✓ Conferente: Jean \(o seu acesso\)/.test(await pag.textContent('#cgc-conferente-eu')) && !(await pag.isVisible('#cgc-conferente-pin')), 'conclusão: conferente é o Jean (o seu acesso), sem o campo de senha');
  await pag.click('#btn-close-carga-conclude').catch(() => pag.keyboard.press('Escape'));
  await pag.evaluate(() => { const o = document.getElementById('carga-conclude-overlay'); if (o && !o.classList.contains('hidden')) o.classList.add('hidden'); });
  await pag.waitForTimeout(300);
  // concluir de verdade (carga liberada, sem fotos)
  await pag.evaluate(() => { const e = document.querySelector('[data-action="concluir-carga"][data-id="cJ2"]'); if (e) e.click(); });
  await pag.waitForSelector('#carga-conclude-overlay:not(.hidden)', { timeout: 5000 });
  for (const cv of ['#cgc-sig-motorista-canvas', '#cgc-sig-conferente-canvas']) {
    await pag.locator(cv).scrollIntoViewIfNeeded();
    const r = await pag.locator(cv).boundingBox();
    await pag.mouse.move(r.x + 20, r.y + 20); await pag.mouse.down();
    await pag.mouse.move(r.x + 90, r.y + 50, { steps: 5 }); await pag.mouse.move(r.x + 150, r.y + 30, { steps: 5 }); await pag.mouse.up();
  }
  await pag.click('#carga-conclude-form button[type="submit"]'); await pag.waitForTimeout(1000);
  const c2 = b.docs.get('cargas/cJ2').data;
  conf(c2.status === 'concluida' && /Jean/.test(c2.conferente || ''), 'Jean conclui o carregamento sem senha (conferente: ' + c2.conferente + ', erro na tela: ' + ((await pag.textContent('#carga-conclude-error').catch(() => '')) || '').trim() + ')');
  await ctx.close();

  // ---------- faturamento com o próprio acesso: um toque ----------
  console.log('Faturamento:');
  ({ ctx, pag } = await entrar('teste-fatura'));
  await pag.evaluate(() => document.querySelector('[data-action="fat-ok"][data-id="cJ1"]').click());
  await pag.waitForTimeout(700);
  const c1 = b.docs.get('cargas/cJ1').data;
  conf(!(await pinAberto(pag)) && c1.faturamentoOk === true && c1.faturamentoPor === 'Fatura' && c1.faturamentoPorId === 'fat-t', 'ok do faturamento com um toque, no nome de quem entrou');
  await ctx.close();

  // ---------- senha mestre: continua com a senha ----------
  console.log('Senha mestre:');
  ({ ctx, pag } = await entrar('teste-nicolas'));
  await pag.evaluate(() => { const e = document.querySelector('[data-action="conf-barras"][data-id="cJ2"]'); });
  const temBotao = await pag.evaluate(() => !!document.querySelector('[data-action="fat-desfazer"], [data-action="fat-ok"]'));
  conf(temBotao, 'senha mestre vê os botões de ok');
  await pag.evaluate(() => { const e = document.querySelector('[data-action="fat-ok"]') || document.querySelector('[data-action="fat-desfazer"]'); if (e) e.click(); });
  await pag.waitForTimeout(400);
  conf(await pinAberto(pag), 'senha mestre: o ok pede a senha de 4 números de quem fatura (como antes)');
  await ctx.close();

  conf(!erros.length, 'sem erros de JavaScript' + (erros.length ? ': ' + erros.join(' | ') : ''));
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
