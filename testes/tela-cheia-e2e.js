/* LEVÍSSIMA · teste: tela cheia nos módulos à parte (23/11/2026).
 * Dentro do app: o botão no alto do módulo cobre o app com o módulo (some o menu do app) e pede a tela cheia do
 * aparelho; sai pelo botão, pelo Voltar ou ao minimizar. No app Android: esconde as barras do celular (função "Tela")
 * e o Voltar do celular sai. Página do módulo aberta sozinha: tela cheia do aparelho e Voltar.
 * Rodar: python3 ferramentas/construir.py --modulos && node testes/tela-cheia-e2e.js
 */
'use strict';
const { criar } = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }

(async () => {
  const amb = await criar();
  const ctx = await amb.contexto({ viewport: { width: 900, height: 800 }, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' });
  await ctx.addInitScript(() => {
    window.__fs = 0;
    Element.prototype.requestFullscreen = function () { window.__fs++; return Promise.resolve(); };
  });
  const pag = await ctx.newPage();
  const erros = []; pag.on('pageerror', (e) => erros.push(String(e)));
  await pag.goto(amb.url + '/index.html');
  await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  await pag.fill('#login-senha', 'teste-nicolas');
  await pag.click('#btn-login-submit');
  await pag.waitForTimeout(1800);
  await pag.click('#admin-tabs .mod-tab[data-mod="manutencao"]');
  await pag.waitForSelector('iframe.mod-frame[data-mod="manutencao"]', { timeout: 10000 });
  const fr = pag.frameLocator('iframe.mod-frame[data-mod="manutencao"]');
  const btn = fr.locator('#lev-barra .lb-cheia');
  await btn.waitFor({ timeout: 15000 });
  conf(/Tela cheia/.test(await btn.textContent()), 'botão "Tela cheia" no alto do módulo');
  const estado = () => pag.evaluate(() => {
    const r = document.getElementById('tab-modulo').getBoundingClientRect();
    return { cls: document.body.classList.contains('mod-tela-cheia'), x: r.left, y: r.top, w: r.width, h: r.height, vw: innerWidth, vh: innerHeight,
      hist: !!(history.state && history.state.levTelaCheia), fs: window.__fs };
  });
  const antes = await estado();
  conf(!antes.cls && antes.y > 0, 'antes: o módulo fica abaixo do menu do app (topo em ' + Math.round(antes.y) + ' px)');

  // 1) entra e sai pelo botão
  await btn.click();
  await pag.waitForTimeout(300);
  let e = await estado();
  conf(e.cls && e.x === 0 && e.y === 0 && Math.round(e.w) === e.vw && Math.round(e.h) === e.vh, 'tela cheia: o módulo cobre o app inteiro (' + Math.round(e.w) + '×' + Math.round(e.h) + ')');
  conf(e.fs === 1 && e.hist, 'pede a tela cheia do navegador e guarda um passo para o Voltar');
  conf(/Sair da tela cheia/.test(await btn.textContent()), 'o botão vira "Sair da tela cheia"');
  await btn.click();
  await pag.waitForTimeout(400);
  e = await estado();
  conf(!e.cls && !e.hist && /^Tela cheia$/.test((await btn.textContent()).trim()), 'sai pelo botão (e tira o passo do Voltar)');

  // 2) sai pelo Voltar
  await btn.click();
  await pag.waitForTimeout(300);
  await pag.evaluate(() => history.back());
  await pag.waitForTimeout(500);
  e = await estado();
  conf(!e.cls && /^Tela cheia$/.test((await btn.textContent()).trim()), 'sai pelo Voltar');
  conf(await pag.isVisible('iframe.mod-frame[data-mod="manutencao"]'), 'o módulo continua aberto depois do Voltar');

  // 3) minimizar sai da tela cheia
  await btn.click();
  await pag.waitForTimeout(300);
  await fr.locator('#lev-barra .lb-min').click();
  await pag.waitForTimeout(500);
  e = await estado();
  conf(!e.cls && !e.hist && !(await pag.isVisible('iframe.mod-frame[data-mod="manutencao"]')), 'minimizar sai da tela cheia');

  // 4) app Android: barras do celular e Voltar do celular
  await pag.evaluate(() => {
    window.__tela = []; window.__telaSaiu = null;
    window.Capacitor = { isNativePlatform: () => true, getPlatform: () => 'android', isPluginAvailable: (n) => n === 'Tela',
      Plugins: { Tela: { cheia: (o) => { window.__tela.push(o.ativa); return Promise.resolve(); }, addListener: (ev, fn) => { if (ev === 'saiu') window.__telaSaiu = fn; return Promise.resolve({ remove() {} }); } } } };
  });
  await pag.click('#admin-tabs .mod-tab[data-mod="manutencao"]');
  await pag.waitForTimeout(500);
  const fsAntes = (await estado()).fs;
  await btn.click();
  await pag.waitForTimeout(300);
  e = await estado();
  conf(e.cls && JSON.stringify(await pag.evaluate(() => window.__tela)) === '[true]' && e.fs === fsAntes, 'app Android: esconde as barras do celular (sem a tela cheia do navegador)');
  await pag.evaluate(() => window.__telaSaiu && window.__telaSaiu());
  await pag.waitForTimeout(400);
  e = await estado();
  conf(!e.cls && !e.hist && JSON.stringify(await pag.evaluate(() => window.__tela)) === '[true,false]' && /^Tela cheia$/.test((await btn.textContent()).trim()), 'Voltar do celular sai da tela cheia e mostra as barras de novo');
  await pag.evaluate(() => { delete window.Capacitor; });

  // 5) página do módulo aberta sozinha
  const pag2 = await ctx.newPage();
  pag2.on('pageerror', (x) => erros.push('módulo: ' + String(x)));
  await pag2.goto(amb.url + '/modulos/manutencao.html');
  const b2 = pag2.locator('#lev-barra .lb-cheia');
  await b2.waitFor({ timeout: 15000 });
  await b2.click();
  await pag2.waitForTimeout(300);
  let s2 = await pag2.evaluate(() => ({ fs: window.__fs, hist: !!(history.state && history.state.levTelaCheia) }));
  conf(s2.fs === 1 && s2.hist && /Sair da tela cheia/.test(await b2.textContent()), 'módulo sozinho: tela cheia do aparelho');
  await pag2.evaluate(() => history.back());
  await pag2.waitForTimeout(400);
  conf(/^Tela cheia$/.test((await b2.textContent()).trim()), 'módulo sozinho: sai pelo Voltar');

  conf(!erros.length, 'sem erros de JavaScript' + (erros.length ? ': ' + erros.join(' | ') : ''));
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
