/* LEVÍSSIMA · teste: quem autoriza o pedido de compra altera o pedido que espera a autorização, mesmo com a aba Compras
 * "só inclui", sempre com o motivo (solicitação 29, 27/11/2026: a Ana pediu 1, a gestora mudou para 2 e o app barrava).
 * Rodar: python3 ferramentas/construir.py && node testes/compras-revisao-e2e.js
 */
'use strict';
const fake = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }
fake.USUARIOS.push({ senha: 'teste-gq', papel: 'equipe', nome: 'Gestora Qualidade', ref: 'escritorio:gq-t', modulos: ['abas', 'aba:compras', 'inclui:compras'] });

(async () => {
  const amb = await fake.criar();
  const b = amb.banco.b;
  const agora = new Date().toISOString();
  doc(b, 'equipe', 'gq-t', { nome: 'Gestora Qualidade', cargo: 'gerente', area: 'Qualidade' });
  doc(b, 'equipe', 'ana-t', { nome: 'Ana Exemplo', cargo: 'analista', area: 'Qualidade' });
  const itens = [{ descricao: 'Capa de chuva', quantidade: 1, unidade: 'un', aplicacao: 'Para a equipe da Qualidade' }];
  const ana = { nome: 'Ana', id: 'ana-t', ref: 'escritorio:ana-t', em: agora };
  doc(b, 'compras-ordens', 'oc30', { numero: 30, status: 'pedido', setor: 'Qualidade', urgencia: 'normal', itens, pedido: ana, criadoEm: agora, atualizadoEm: agora });
  doc(b, 'compras-ordens', 'oc31', { numero: 31, status: 'cotacao', setor: 'Qualidade', urgencia: 'normal', itens, pedido: ana, coord: { nome: 'Gestora', id: 'gq-t', em: agora, decisao: 'aprovado' }, criadoEm: agora, atualizadoEm: agora });
  const st = (id) => (b.docs.get('compras-ordens/' + id) || {}).data || {};

  const ctx = await amb.contexto();
  const pag = await ctx.newPage();
  const erros = [];
  pag.on('pageerror', (e) => erros.push(String(e)));
  await pag.goto(amb.url + '/index.html');
  await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  await pag.fill('#login-senha', 'teste-gq');
  await pag.click('#btn-login-submit');
  await pag.waitForSelector('#admin-view:not(.hidden)', { timeout: 15000 });
  await pag.waitForTimeout(700);
  await pag.evaluate(() => document.querySelector('#admin-tabs .seg-btn[data-tab="compras"]').click());
  await pag.waitForTimeout(500);
  const clicar = async (sel) => { await pag.waitForSelector(sel, { state: 'attached', timeout: 8000 }); await pag.evaluate((s) => document.querySelector(s).click(), sel); await pag.waitForTimeout(400); };
  const erroTela = () => pag.$eval('#ger-form-error', (e) => e.classList.contains('hidden') ? '' : e.textContent).catch(() => '');
  const toast = () => pag.$eval('#toast', (e) => e.textContent).catch(() => '');

  console.log('Gestora do setor, com a aba Compras "só inclui":');
  await clicar('[data-oc="editar"][data-id="oc30"]');
  conf(await pag.$('#oc-edit-motivo') !== null, 'abre a edição com o motivo');
  await pag.fill('#oc-itens .oc-qtd', '2');
  await pag.click('#btn-ger-submit'); await pag.waitForTimeout(300);
  conf(/motivo da alteração/.test(await erroTela()) && st('oc30').itens[0].quantidade === 1, 'sem motivo não altera');
  await pag.fill('#oc-edit-motivo', 'necessário duas unidades para atender a equipe toda');
  await pag.click('#btn-ger-submit'); await pag.waitForTimeout(800);
  conf(st('oc30').itens[0].quantidade === 2 && (st('oc30').edicao || {}).motivo === 'necessário duas unidades para atender a equipe toda' && (st('oc30').edicao || {}).id === 'gq-t', 'alterou para 2, com o motivo e o nome dela (' + JSON.stringify(st('oc30').edicao || {}) + ')');
  conf(!/só inclui/.test(await toast()), 'sem o aviso "só inclui" (' + (await toast()).trim() + ')');
  conf(st('oc30').pedido.id === 'ana-t' && st('oc30').status === 'pedido', 'quem pediu e a etapa não mudam');
  conf(!(await pag.$('[data-oc="editar"][data-id="oc31"]')), 'depois da autorização (em cotação) não aparece "editar"');
  conf(!erros.length, 'sem erros de JavaScript' + (erros.length ? ': ' + erros.join(' | ') : ''));
  await ctx.close();
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
