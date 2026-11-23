/* LEVÍSSIMA · teste: quem atende os chamados de TI assume e atualiza mesmo com o acesso "só inclui" (pedido de 23/11/2026,
 * caso do Pedro). O banco faz a mesma conta na migração 0061.
 * Rodar: python3 ferramentas/construir.py && node testes/chamados-so-inclui-e2e.js
 */
'use strict';
const fake = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }
fake.USUARIOS.push({ senha: 'teste-ti', papel: 'equipe', nome: 'Atendente da TI', ref: 'escritorio:equipe-ti', modulos: ['abas', 'aba:compras', 'inclui:compras'], so_inclui: true });

(async () => {
  const amb = await fake.criar();
  const b = amb.banco.b;
  const agora = new Date().toISOString();
  doc(b, 'equipe', 'equipe-ti', { nome: 'Atendente', nomeCompleto: 'Atendente da TI', atendeTi: true });
  doc(b, 'chamados', 'ch1', { area: 'ti', numero: 7, status: 'aberto', titulo: 'Impressora não imprime', categoria: 'Impressora', prioridade: 'normal', local: 'Faturamento', solicitante: { nome: 'Fulana', ref: 'escritorio:equipe-x' }, criadoEm: agora, atualizadoEm: agora, eventos: [] });
  const st = () => (b.docs.get('chamados/ch1') || {}).data || {};
  const ctx = await amb.contexto();
  const pag = await ctx.newPage();
  await pag.goto(amb.url + '/index.html');
  await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  await pag.fill('#login-senha', 'teste-ti');
  await pag.click('#btn-login-submit');
  await pag.waitForSelector('#admin-view:not(.hidden)', { timeout: 15000 });
  await pag.waitForTimeout(800);
  await pag.evaluate(() => document.querySelector('#admin-tabs [data-tab="ti"]').click());
  await pag.waitForTimeout(600);
  const toast = () => pag.$eval('#toast', (e) => e.textContent).catch(() => '');
  await pag.waitForSelector('[data-ch="assumir"][data-id="ch1"]', { state: 'attached', timeout: 8000 });
  await pag.evaluate(() => document.querySelector('[data-ch="assumir"][data-id="ch1"]').click());
  await pag.waitForTimeout(700);
  conf(st().status === 'atendimento' && (st().responsavel || {}).ref === 'escritorio:equipe-ti', 'com "só inclui", quem atende a TI assume o chamado (' + (await toast()).trim() + ')');
  conf(!/só inclui/.test(await toast()), 'sem o aviso "só inclui"');
  await pag.evaluate(() => document.querySelector('[data-ch="filtro"][data-area="ti"][data-f="andamento"]').click());
  await pag.waitForTimeout(400);
  const atualizar = await pag.$('[data-ch="atualizar"][data-id="ch1"]');
  if (atualizar) {
    await pag.evaluate(() => document.querySelector('[data-ch="atualizar"][data-id="ch1"]').click());
    await pag.waitForSelector('#cha-st', { timeout: 4000 });
    await pag.selectOption('#cha-st', 'aguardando');
    await pag.fill('#cha-txt', 'A peça chega quinta');
    await pag.click('#btn-ger-submit');
    await pag.waitForTimeout(700);
    conf(st().status === 'aguardando', 'atualiza o chamado (situação e recado)');
  } else conf(false, 'botão de atualizar o chamado aparece');
  conf(!amb.erros.length, 'sem erros de JavaScript' + (amb.erros.length ? ': ' + amb.erros.slice(0, 3).join(' | ') : ''));
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
