/* LEVÍSSIMA · teste: quem fez o pedido de compra cancela e edita o próprio pedido, mesmo com a aba Compras "só inclui",
 * sempre com o motivo (pedido de 19/11/2026, tarde). O motivo aparece no histórico da OC.
 * Rodar: python3 ferramentas/construir.py && node testes/compras-dono-e2e.js
 */
'use strict';
const fake = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }
fake.USUARIOS.push({ senha: 'teste-pcp', papel: 'equipe', nome: 'Pessoa do PCP', ref: 'escritorio:equipe-pcp', modulos: ['abas', 'aba:compras', 'aba:producao', 'inclui:compras'] });

(async () => {
  const amb = await fake.criar();
  const b = amb.banco.b;
  const agora = new Date().toISOString();
  doc(b, 'equipe', 'equipe-pcp', { nome: 'Pessoa', nomeCompleto: 'Pessoa do PCP', area: 'PCP' });
  const itens = [{ descricao: 'Etiqueta', quantidade: 10, unidade: 'un', aplicacao: 'Linha 1' }];
  const eu = { nome: 'Pessoa', id: 'equipe-pcp', ref: 'escritorio:equipe-pcp', em: agora };
  doc(b, 'compras-ordens', 'oc20', { numero: 20, status: 'cotacao', setor: 'PCP', urgencia: 'normal', itens, pedido: eu, coord: { nome: 'X', id: 'equipe-x', em: agora, decisao: 'aprovado' }, criadoEm: agora, atualizadoEm: agora });
  doc(b, 'compras-ordens', 'oc21', { numero: 21, status: 'pedido', setor: 'PCP', urgencia: 'normal', itens, pedido: eu, criadoEm: agora, atualizadoEm: agora });
  const st = (id) => (b.docs.get('compras-ordens/' + id) || {}).data || {};

  const ctx = await amb.contexto();
  const pag = await ctx.newPage();
  await pag.goto(amb.url + '/index.html');
  await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  await pag.fill('#login-senha', 'teste-pcp');
  await pag.click('#btn-login-submit');
  await pag.waitForSelector('#admin-view:not(.hidden)', { timeout: 15000 });
  await pag.waitForTimeout(700);
  await pag.evaluate(() => { if (typeof switchTab === 'function') switchTab('compras'); });
  await pag.waitForTimeout(500);
  const clicar = async (sel) => { await pag.waitForSelector(sel, { state: 'attached', timeout: 8000 }); await pag.evaluate((s) => document.querySelector(s).click(), sel); await pag.waitForTimeout(400); };
  const erroTela = () => pag.$eval('#ger-form-error', (e) => e.classList.contains('hidden') ? '' : e.textContent).catch(() => '');
  const toast = () => pag.$eval('#toast', (e) => e.textContent).catch(() => '');

  console.log('Cancelar o próprio pedido (em cotação)');
  await clicar('[data-oc="cancelar"][data-id="oc20"]');
  await pag.click('#btn-ger-submit');
  await pag.waitForTimeout(300);
  conf(/motivo do cancelamento/.test(await erroTela()) && st('oc20').status === 'cotacao', 'sem motivo não cancela');
  await pag.fill('#oc-canc-motivo', 'Comprado pelo fornecedor da matriz');
  await pag.click('#btn-ger-submit');
  await pag.waitForTimeout(600);
  conf(st('oc20').status === 'cancelada' && (st('oc20').cancelamento || {}).motivo === 'Comprado pelo fornecedor da matriz', 'cancelou com o motivo, mesmo com a aba Compras "só inclui"');
  conf(!/só inclui/.test(await toast()), 'sem o aviso "só inclui" (' + (await toast()).trim() + ')');

  console.log('Editar o próprio pedido (aguardando autorização)');
  await clicar('[data-oc="editar"][data-id="oc21"]');
  conf(await pag.$('#oc-edit-motivo') !== null, 'a edição pede o motivo da alteração');
  await pag.fill('#oc-itens .oc-qtd', '25');
  await pag.click('#btn-ger-submit');
  await pag.waitForTimeout(300);
  conf(/motivo da alteração/.test(await erroTela()) && st('oc21').itens[0].quantidade === 10, 'sem motivo não altera');
  await pag.fill('#oc-edit-motivo', 'A quantidade estava errada');
  await pag.click('#btn-ger-submit');
  await pag.waitForTimeout(700);
  conf(st('oc21').itens[0].quantidade === 25 && (st('oc21').edicao || {}).motivo === 'A quantidade estava errada' && ((st('oc21').edicoes || [])[0] || {}).motivo === 'A quantidade estava errada', 'alterou com o motivo guardado na OC (' + JSON.stringify(st('oc21').edicao || {}) + ')');
  conf(st('oc21').pedido.id === 'equipe-pcp' && st('oc21').numero === 21, 'quem pediu e o número não mudam');
  await clicar('[data-oc="ver"][data-id="oc21"]');
  conf(/motivo: A quantidade estava errada/.test(await pag.$eval('#ger-form-body', (e) => e.textContent)), 'o motivo aparece no histórico da OC');
  conf(!amb.erros.length, 'sem erros de JavaScript' + (amb.erros.length ? ': ' + amb.erros.slice(0, 3).join(' | ') : ''));
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
