/* LEVÍSSIMA · teste: aviso de versão nova no navegador (pedido de 23/11/2026).
 * A página publicada com outra versão (meta levissima-versao) faz aparecer "Versão nova do LEVÍSSIMA";
 * com a mesma versão, nada aparece; "Depois" esconde o aviso.
 * Rodar: python3 ferramentas/construir.py && node testes/versao-nova-e2e.js
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { criar } = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }

(async () => {
  const amb = await criar();
  const ctx = await amb.contexto();
  const pag = await ctx.newPage();
  const html = fs.readFileSync(path.join(__dirname, '..', 'www', 'index.html'), 'utf8');
  let servir = html;
  await pag.route(/index\.html\?v=/, (r) => r.fulfill({ status: 200, contentType: 'text/html; charset=utf-8', body: servir }));
  await pag.goto(amb.url + '/index.html');
  await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  const minha = await pag.evaluate(() => window.LEV_VERSAO && window.LEV_VERSAO.minha);
  conf(/^[0-9a-f]{12}$/.test(minha || ''), 'a página construída tem a versão (' + minha + ')');
  await pag.evaluate(() => window.LEV_VERSAO.conferir());
  await pag.waitForTimeout(600);
  conf(await pag.locator('.versao-nova').count() === 0, 'mesma versão publicada: sem aviso');
  servir = html.replace('content="' + minha + '"', 'content="abcdef123456"');
  await pag.evaluate(() => window.LEV_VERSAO.conferir());
  await pag.waitForSelector('.versao-nova', { timeout: 4000 }).catch(() => {});
  conf(/Versão nova do LEVÍSSIMA/.test(await pag.textContent('body')), 'versão publicada diferente: aparece "Versão nova do LEVÍSSIMA"');
  await pag.click('.versao-nova [data-vn="depois"]');
  conf(await pag.locator('.versao-nova').count() === 0, '"Depois" esconde o aviso');
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
