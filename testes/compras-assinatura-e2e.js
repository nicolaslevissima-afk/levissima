/* LEVÍSSIMA · teste: Compras assina pelo usuário logado, sem a senha de 4 números (pedido de 19/11/2026).
 * Autorização, aprovação da diretoria, recebido e pedido saem no nome de quem entrou, em um toque; a janela da senha
 * de 4 números nunca abre; quem não pode a etapa recebe o motivo e nada é gravado.
 * Rodar: python3 ferramentas/construir.py && node testes/compras-assinatura-e2e.js
 */
'use strict';
const { criar } = require('./banco-fake');
let passou = 0, falhou = 0;
function ok(c, m) { if (c) { passou++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }

(async () => {
  const amb = await criar();
  const b = amb.banco.b;
  const U = Object.fromEntries(amb.USUARIOS.map((u) => [u.ref, u]));
  const agora = new Date().toISOString();
  doc(b, 'equipe', 'equipe-angelica', { nome: 'Angélica', nomeCompleto: 'Angélica Souza', cargo: 'coordenador', area: 'Produção', setores: 'Produção, Manutenção' });
  doc(b, 'equipe', 'equipe-andre', { nome: 'André', nomeCompleto: 'André Lima', cargo: 'diretor', area: 'Gestão' });
  doc(b, 'equipe', 'equipe-paulo', { nome: 'Paulo', nomeCompleto: 'Paulo Teste', area: 'Manutenção' });
  const itens = [{ descricao: 'Rolamento 6205', quantidade: 4, unidade: 'un', aplicacao: 'Esteira da linha 1' }];
  const pedidoPaulo = { nome: 'Paulo', id: 'equipe-paulo', ref: 'escritorio:equipe-paulo', em: agora };
  const cot = { cotacoes: [{ fornecedor: 'Loja A', valor: 100 }, { fornecedor: 'Loja B', valor: 120 }, { fornecedor: 'Loja C', valor: 130 }], escolhida: 0, nome: 'Rita', em: agora };
  doc(b, 'compras-ordens', 'oc1', { numero: 1, status: 'pedido', setor: 'Manutenção', urgencia: 'normal', itens, pedido: pedidoPaulo, criadoEm: agora, atualizadoEm: agora });
  doc(b, 'compras-ordens', 'oc2', { numero: 2, status: 'aprovacao', setor: 'Manutenção', urgencia: 'normal', itens, pedido: pedidoPaulo, coord: { nome: 'Angélica', id: 'equipe-angelica', em: agora, decisao: 'aprovado' }, cotacao: cot, revisao: { nome: 'Paulo', id: 'equipe-paulo', em: agora, decisao: 'de-acordo' }, criadoEm: agora, atualizadoEm: agora });
  doc(b, 'compras-ordens', 'oc3', { numero: 3, status: 'comprado', setor: 'Manutenção', urgencia: 'normal', itens, pedido: pedidoPaulo, cotacao: cot, compra: { nome: 'André', id: 'equipe-andre', fornecedor: 'Loja A', valor: 100, em: agora }, criadoEm: agora, atualizadoEm: agora });
  doc(b, 'compras-ordens', 'oc4', { numero: 4, status: 'conferido', setor: 'Manutenção', urgencia: 'normal', itens, pedido: pedidoPaulo, cotacao: cot, compra: { nome: 'André', id: 'equipe-andre', fornecedor: 'Loja A', valor: 100, em: agora }, conferencia: { nome: 'André', id: 'equipe-andre', resultado: 'ok', em: agora }, criadoEm: agora, atualizadoEm: agora });
  const oc = (id) => (b.docs.get('compras-ordens/' + id) || {}).data || {};

  async function entrar(senha) {
    const ctx = await amb.contexto();
    const pag = await ctx.newPage();
    await pag.goto(amb.url + '/index.html');
    await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
    await pag.fill('#login-senha', senha);
    await pag.click('#btn-login-submit');
    await pag.waitForSelector('#admin-view:not(.hidden)', { timeout: 15000 });
    await pag.waitForTimeout(700);
    // a janela da senha de 4 números não pode abrir em nenhum momento
    await pag.evaluate(() => {
      window.__pinAbriu = 0;
      const el = document.getElementById('pin-overlay');
      new MutationObserver(() => { if (!el.classList.contains('hidden')) window.__pinAbriu++; }).observe(el, { attributes: true, attributeFilter: ['class'] });
    });
    await pag.evaluate(() => { if (typeof switchTab === 'function') switchTab('compras'); });
    await pag.waitForTimeout(500);
    return { ctx, pag };
  }
  async function tocar(pag, sel) { await pag.waitForSelector(sel, { state: 'attached', timeout: 8000 }); await pag.evaluate((s) => document.querySelector(s).click(), sel); await pag.waitForTimeout(400); }
  const texto = (pag, sel) => pag.$eval(sel, (e) => e.innerText).catch(() => '');

  console.log('Coordenadora (Angélica, acesso pessoal)');
  let s = await entrar(U['escritorio:equipe-angelica'].senha);
  await tocar(s.pag, '[data-oc="coord"][data-id="oc1"]');
  ok(/Assina como Angélica/.test(await texto(s.pag, '.oc-assina-como')), 'a tela da autorização mostra quem assina (Angélica)');
  await tocar(s.pag, '#ger-sheet-overlay [data-ger="aprovado"]');
  await s.pag.waitForTimeout(500);
  ok(oc('oc1').status === 'cotacao' && oc('oc1').coord && oc('oc1').coord.id === 'equipe-angelica' && oc('oc1').coord.ref === 'escritorio:equipe-angelica', 'Autorizar grava na hora, no nome de Angélica (sem senha de 4 números)');
  await tocar(s.pag, '[data-oc="filtro"][data-f="comprado"]');
  await tocar(s.pag, '[data-oc="recebido"][data-id="oc3"]');
  await s.pag.check('#oc-rc-conf');
  await s.pag.click('#btn-ger-submit');
  await s.pag.waitForTimeout(500);
  ok(oc('oc3').status === 'recebido' && oc('oc3').recebimento && oc('oc3').recebimento.id === 'equipe-angelica', 'Dar o recebido assina como Angélica');
  // pedido novo: sai no nome dela, sem senha
  await tocar(s.pag, '[data-oc="novo"]');
  const campoNome = await s.pag.$eval('#oc-nome', (e) => ({ ro: e.readOnly, v: e.value }));
  ok(campoNome.ro && /^Angélica/.test(campoNome.v), 'novo pedido já vem no nome de quem entrou' + (campoNome.ro && /^Angélica/.test(campoNome.v) ? '' : ' ' + JSON.stringify(campoNome)));
  await s.pag.selectOption('#oc-setor', { index: 1 });
  await s.pag.fill('#oc-itens .oc-desc', 'Correia');
  await s.pag.fill('#oc-itens .oc-qtd', '2');
  await s.pag.fill('#oc-itens .oc-ap', 'Sopradora');
  await s.pag.click('#btn-ger-submit');
  await s.pag.waitForTimeout(700);
  const nova = [...b.docs.values()].find((d) => d.colecao === 'compras-ordens' && d.data.itens && d.data.itens[0] && d.data.itens[0].descricao === 'Correia');
  ok(nova && nova.data.pedido && nova.data.pedido.id === 'equipe-angelica', 'pedido gravado no nome de Angélica, sem senha');
  ok(await s.pag.evaluate(() => window.__pinAbriu) === 0, 'a janela da senha de 4 números não abriu');
  await s.ctx.close();

  console.log('Diretoria (André, acesso pessoal)');
  s = await entrar(U['escritorio:equipe-andre'].senha);
  await tocar(s.pag, '[data-oc="nicolas"][data-id="oc2"]');
  ok(/Assina como André/.test(await texto(s.pag, '.oc-assina-como')), 'a tela da aprovação mostra quem assina (André)');
  await s.pag.evaluate(() => { const b = document.querySelector('#ger-sheet-overlay [data-ger="aprovado"]'); b.click(); b.click(); }); // toque duplo
  await s.pag.waitForTimeout(600);
  ok(oc('oc2').status === 'compra' && oc('oc2').aprovacao && oc('oc2').aprovacao.id === 'equipe-andre', 'Aprovar grava na hora, no nome de André');
  // André não fez o pedido da OC 4: o app explica e não grava
  await tocar(s.pag, '[data-oc="entrega"][data-id="oc4"]');
  await s.pag.check('#oc-conf');
  await s.pag.click('#btn-ger-submit');
  await s.pag.waitForTimeout(400);
  ok(/Só Paulo \(quem fez o pedido\)/.test(await texto(s.pag, '#ger-form-error')) && oc('oc4').status === 'conferido', 'quem não pode a etapa recebe o motivo e nada é gravado');
  ok(await s.pag.evaluate(() => window.__pinAbriu) === 0, 'a janela da senha de 4 números não abriu');
  await s.ctx.close();

  console.log('Coordenadora tenta aprovar pela diretoria');
  doc(b, 'compras-ordens', 'oc5', { numero: 5, status: 'aprovacao', setor: 'Manutenção', urgencia: 'normal', itens, pedido: { nome: 'Angélica', id: 'equipe-angelica', em: agora }, cotacao: cot, criadoEm: agora, atualizadoEm: agora });
  s = await entrar(U['escritorio:equipe-angelica'].senha);
  const temBotao = await s.pag.$('[data-oc="nicolas"][data-id="oc5"]');
  if (temBotao) {
    await tocar(s.pag, '[data-oc="nicolas"][data-id="oc5"]');
    await tocar(s.pag, '#ger-sheet-overlay [data-ger="aprovado"]');
    const avisoDir = await texto(s.pag, '#ger-form-error');
    ok(/Você entrou como Angélica, que não aprova compras/.test(avisoDir) && oc('oc5').status === 'aprovacao', 'coordenadora não aprova pela diretoria: aviso claro, nada gravado (' + avisoDir + ' / ' + oc('oc5').status + ')');
  } else ok(oc('oc5').status === 'aprovacao', 'coordenadora não vê o botão de aprovar da diretoria');
  ok(await s.pag.evaluate(() => window.__pinAbriu) === 0, 'a janela da senha de 4 números não abriu');
  await s.ctx.close();

  ok(!amb.erros.length, 'sem erros de JavaScript' + (amb.erros.length ? ': ' + amb.erros.slice(0, 3).join(' | ') : ''));
  await amb.fechar();
  console.log('\n' + passou + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
