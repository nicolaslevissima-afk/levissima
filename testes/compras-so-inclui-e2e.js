/* LEVÍSSIMA · teste: Compras (19/11/2026)
 * 1. Aba Compras "só inclui": quem pediu confirma a entrega (o caso da Renata) e compras lança a cotação. Desde a tarde de
 *    19/11/2026 quem fez o pedido também cancela (com motivo) o próprio; o pedido de outra pessoa continua barrado.
 *    Também com todas as abas "só inclui" (so_inclui no login, caso do Gabriel).
 * 2. Sem a etapa "Quem pediu confere": a cotação vai direto para a diretoria; ordem antiga em "revisao" aparece como
 *    aguardando a diretoria.
 * Rodar: python3 ferramentas/construir.py --modulos && node testes/compras-so-inclui-e2e.js
 */
'use strict';
const fake = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }
const ABAS_RENATA = ['abas', 'aba:compras', 'aba:qualidade', 'inclui:compras'];
fake.USUARIOS.push(
  { senha: 'teste-renata', papel: 'equipe', nome: 'Renata', ref: 'escritorio:equipe-renata', modulos: ABAS_RENATA },
  { senha: 'teste-rita', papel: 'equipe', nome: 'Rita', ref: 'escritorio:equipe-rita', modulos: ['abas', 'aba:compras', 'aba:estoque', 'inclui:compras'] },
  { senha: 'teste-gabriel', papel: 'equipe', nome: 'Gabriel', ref: 'escritorio:equipe-gabriel', modulos: ['abas', 'aba:compras', 'aba:estoque', 'inclui:compras', 'inclui:estoque'], so_inclui: true }
);

(async () => {
  const amb = await fake.criar();
  const b = amb.banco.b;
  const agora = new Date().toISOString();
  doc(b, 'equipe', 'equipe-renata', { nome: 'Renata', cargo: 'gerente', area: 'Qualidade' });
  doc(b, 'equipe', 'equipe-rita', { nome: 'Rita', cargo: 'assistente', area: 'Compras', compras: true });
  doc(b, 'equipe', 'equipe-gabriel', { nome: 'Gabriel', cargo: 'analista', area: 'Manutenção' });
  const itens = [{ descricao: 'Teste 1', quantidade: 1, unidade: 'un', aplicacao: 'teste 1' }, { descricao: 'teste 2', quantidade: 2, unidade: 'un', aplicacao: 'teste 2' }];
  const ren = { nome: 'Renata · Gerente', id: 'equipe-renata', ref: 'escritorio:equipe-renata', em: agora };
  const gab = { nome: 'Gabriel · Analista', id: 'equipe-gabriel', ref: 'escritorio:equipe-gabriel', em: agora };
  const coord = { nome: 'Renata · Gerente', id: 'equipe-renata', em: agora, decisao: 'aprovado', automatica: true };
  const rec = { nome: 'Janize · Assistente', id: '', em: agora, conforme: true, nf: '123' };
  const cf = { nome: 'Janize · Assistente', id: '', em: agora, resultado: 'ok' };
  doc(b, 'compras-ordens', 'oc9', { numero: 9, status: 'conferido', setor: 'Qualidade', itens, pedido: ren, coord, recebimento: rec, conferencia: cf, criadoEm: agora });
  doc(b, 'compras-ordens', 'oc10', { numero: 10, status: 'cotacao', setor: 'Qualidade', itens, pedido: ren, coord, criadoEm: agora });
  doc(b, 'compras-ordens', 'oc11', { numero: 11, status: 'conferido', setor: 'Manutenção', itens, pedido: gab, coord, recebimento: rec, conferencia: cf, criadoEm: agora });
  doc(b, 'compras-ordens', 'oc12', { numero: 12, status: 'pedido', setor: 'Qualidade', itens, pedido: ren, criadoEm: agora });
  doc(b, 'compras-ordens', 'oc13', { numero: 13, status: 'revisao', setor: 'Qualidade', itens, pedido: ren, coord, criadoEm: agora,
    cotacao: { nome: 'Rita', id: 'equipe-rita', em: agora, escolhida: 0, cotacoes: [{ fornecedor: 'A', valor: 10 }, { fornecedor: 'B', valor: 11 }, { fornecedor: 'C', valor: 12 }] } });
  doc(b, 'compras-ordens', 'oc14', { numero: 14, status: 'pedido', setor: 'Manutenção', itens, pedido: gab, criadoEm: agora });
  doc(b, 'compras-ordens', 'oc15', { numero: 15, status: 'pedido', setor: 'Manutenção', itens, pedido: gab, criadoEm: agora });
  const st = (id) => (b.docs.get('compras-ordens/' + id) || {}).data || {};

  async function entrar(senha) {
    const ctx = await amb.contexto({ viewport: { width: 1100, height: 900 } });
    const pag = await ctx.newPage();
    await pag.goto(amb.url + '/index.html');
    await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
    await pag.fill('#login-senha', senha);
    await pag.click('#btn-login-submit');
    await pag.waitForTimeout(1800);
    await pag.evaluate(() => document.querySelector('#admin-tabs .seg-btn[data-tab="compras"]').click());
    conf(await pag.isVisible('#tab-compras'), senha.replace('teste-', '') + ': aba Compras aberta');
    await pag.waitForTimeout(700);
    return { ctx, pag };
  }
  const toast = (pag) => pag.evaluate(() => (document.getElementById('toast') || {}).textContent || '');
  async function clicar(pag, sel) { await pag.evaluate((s) => { const e = document.querySelector(s); if (!e) throw new Error('não achou ' + s); e.click(); }, sel); await pag.waitForTimeout(300); }
  async function confirmarEntrega(pag, id) {
    await clicar(pag, '[data-oc="entrega"][data-id="' + id + '"]');
    await pag.check('#oc-conf');
    await pag.click('#btn-ger-submit'); // assina como quem entrou (sem a senha de 4 números, desde 19/11/2026)
    await pag.waitForTimeout(700);
  }
  async function tentarCancelar(pag, id) {
    await clicar(pag, '[data-oc="cancelar"][data-id="' + id + '"]');
    await pag.fill('#oc-canc-motivo', 'teste de cancelamento');
    await pag.click('#btn-ger-submit');
    await pag.waitForTimeout(600);
    await pag.evaluate(() => { if (typeof gerFechar === 'function') gerFechar(); });
  }

  // ---------- Renata: aba Compras "só inclui", outras abas editam ----------
  console.log('Renata (aba Compras "só inclui"):');
  let { ctx, pag } = await entrar('teste-renata');
  const tela = await pag.textContent('#oc-conteudo');
  conf(!/Quem pediu confere/.test(tela) && /4 · aprovação da diretoria/.test(tela) && /8 · entregue/.test(tela), 'fluxo com 8 etapas, sem "Quem pediu confere" (passos, filtros e texto)');
  const card13 = await pag.evaluate(() => { const b = document.querySelector('[data-oc="ver"][data-id="oc13"]'); return b ? b.closest('.oc-card').textContent : ''; });
  conf(/Aguardando diretoria/.test(card13) && !/quem pediu confere/i.test(card13), 'OC antiga em "revisao" aparece como "Aguardando diretoria"');
  await confirmarEntrega(pag, 'oc9');
  conf(st('oc9').status === 'fechada' && /Renata/.test((st('oc9').fechamento || {}).nome || ''), 'Renata confirma a entrega da OC nº 9 (status ' + st('oc9').status + ')');
  conf(!/só inclui/.test(await toast(pag)), 'sem o aviso "só inclui" na entrega (' + (await toast(pag)).trim() + ')');
  await tentarCancelar(pag, 'oc12');
  conf(st('oc12').status === 'cancelada' && (st('oc12').cancelamento || {}).motivo === 'teste de cancelamento', 'quem pediu cancela o próprio pedido com "só inclui", com o motivo (aviso: ' + (await toast(pag)).trim() + ')');
  // 23/11/2026 (0063): a gerente da Qualidade não vê mais os pedidos de outros setores esperando autorização
  conf(!(await pag.$('[data-id="oc15"]')) && !(await pag.$('[data-id="oc14"]')), 'pedido de outra pessoa de outro setor (Manutenção) nem aparece para a gerente da Qualidade');
  await ctx.close();

  // ---------- Rita (compras, aba "só inclui"): a cotação vai direto para a diretoria ----------
  console.log('Rita (compras, aba "só inclui"):');
  ({ ctx, pag } = await entrar('teste-rita'));
  await clicar(pag, '[data-oc="cotar"][data-id="oc10"]');
  conf(/Enviar para a diretoria/.test(await pag.textContent('#btn-ger-submit')), 'botão da cotação: "Enviar para a diretoria"');
  const forn = [['Loja A', '100,00'], ['Loja B', '90,00'], ['Loja C', '120,00']];
  for (let i = 0; i < 3; i++) { await pag.fill('.oc-cf[data-i="' + i + '"]', forn[i][0]); await pag.fill('.oc-cv[data-i="' + i + '"]', forn[i][1]); }
  await pag.click('#btn-ger-submit');
  await pag.waitForTimeout(800);
  const o10 = st('oc10');
  conf(o10.status === 'aprovacao' && o10.cotacao && o10.cotacao.cotacoes.length === 3 && o10.cotacao.escolhida === 1, 'cotação lançada com "só inclui" e a OC nº 10 vai direto para a diretoria (status ' + o10.status + ')');
  conf(/segue para a diretoria/.test(await toast(pag)), 'aviso: "segue para a diretoria"');
  await ctx.close();

  // ---------- Gabriel: todas as abas "só inclui" (so_inclui no login) ----------
  console.log('Gabriel (todas as abas "só inclui"):');
  ({ ctx, pag } = await entrar('teste-gabriel'));
  await confirmarEntrega(pag, 'oc11');
  conf(st('oc11').status === 'fechada', 'Gabriel confirma a entrega do pedido dele (status ' + st('oc11').status + ')');
  await tentarCancelar(pag, 'oc14');
  conf(st('oc14').status === 'cancelada', 'todas as abas "só inclui": quem pediu cancela o próprio pedido, com o motivo (aviso: ' + (await toast(pag)).trim() + ')');
  await ctx.close();

  const erros = amb.erros.filter((e) => !/favicon|manifest|service worker/i.test(e));
  conf(!erros.length, 'sem erros de JavaScript' + (erros.length ? ': ' + erros.slice(0, 3).join(' | ') : ''));
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
