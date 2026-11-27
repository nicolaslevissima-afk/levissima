/* LEVÍSSIMA · teste: Qualidade sem a senha de 4 números (27/11/2026).
 * Quem é da Qualidade salva com o próprio acesso (sem a caixa da senha); quem não é não vê o botão de salvar e o aviso
 * diz por quê. Na aba Trocas, o destino é anotado por quem é da Qualidade com o próprio acesso; para os outros o botão
 * some. Senha mestre: como antes.
 * Rodar: python3 ferramentas/construir.py && node testes/qualidade-sem-senha-e2e.js
 */
'use strict';
const fake = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }
const ABAS = ['abas', 'aba:qualidade', 'aba:trocas'];
fake.USUARIOS.push(
  { senha: 'teste-quali', papel: 'equipe', nome: 'Quali Exemplo', ref: 'escritorio:quali-t', modulos: ABAS },
  { senha: 'teste-outro', papel: 'equipe', nome: 'Outro Exemplo', ref: 'escritorio:outro-t', modulos: ABAS }
);

(async () => {
  const amb = await fake.criar();
  const b = amb.banco.b;
  doc(b, 'equipe', 'quali-t', { nome: 'Quali Exemplo', cargo: 'analista', area: 'Qualidade', qualidade: true, temPin: true });
  doc(b, 'equipe', 'outro-t', { nome: 'Outro Exemplo', cargo: 'assistente', area: 'Expedição', temPin: true });
  doc(b, 'trocas', 't1', { numero: 1, tipo: 'troca', cliente: 'Mercado Exemplo', itens: [{ produto: 'Água 510ml', quantidade: 2, unidade: 'fardos' }], status: 'aberta', recebidoPor: 'Motorista Teste', criadoEm: new Date().toISOString() });
  const erros = [];
  async function entrar(senha) {
    const ctx = await amb.contexto({ viewport: { width: 1100, height: 1000 }, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' });
    const pag = await ctx.newPage();
    pag.on('pageerror', (e) => erros.push(senha + ': ' + String(e)));
    await pag.goto(amb.url + '/index.html');
    await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
    await pag.fill('#login-senha', senha); await pag.click('#btn-login-submit'); await pag.waitForTimeout(1800);
    return { ctx, pag };
  }
  const aba = (pag, t) => pag.evaluate((t) => document.querySelector('#admin-tabs .seg-btn[data-tab="' + t + '"]').click(), t);
  const ncs = () => Array.from(b.docs.values()).filter((d) => d.colecao === 'qualidade-ncs').map((d) => d.data);

  console.log('Quem é da Qualidade:');
  let { ctx, pag } = await entrar('teste-quali');
  await aba(pag, 'qualidade'); await pag.waitForTimeout(500);
  await pag.evaluate(() => document.querySelector('[data-q="nova-nc"]').click());
  await pag.waitForSelector('#q-sheet-overlay:not(.hidden)');
  conf(/Fica assinado por Quali[^(]*\(o seu acesso\)/.test(await pag.textContent('#q-form-body')) && await pag.isVisible('#btn-q-submit'), 'formulário diz quem assina e mostra o botão de salvar');
  conf(!(await pag.$('#q-resp')), 'sem campo de responsável');
  await pag.fill('#q-desc', 'Teste de NC sem senha');
  await pag.click('#btn-q-submit'); await pag.waitForTimeout(800);
  const n = ncs()[0] || {};
  conf(!(await pag.isVisible('#pin-overlay')) && /^Quali/.test(n.por || ''), 'NC salva sem pedir a senha, assinada por quem entrou');
  await aba(pag, 'trocas'); await pag.waitForTimeout(500);
  conf(!!(await pag.$('[data-troca="destino"][data-id="t1"]')), 'Trocas: vê "Anotar o destino"');
  await pag.evaluate(() => document.querySelector('[data-troca="destino"][data-id="t1"]').click());
  await pag.waitForSelector('#trd-tipo');
  conf(/Fica assinado por Quali/.test(await pag.textContent('#ger-form-body')), 'destino: diz quem assina');
  const op = await pag.$$eval('#trd-tipo option', (l) => l.map((o) => o.value).filter(Boolean));
  const tipo = op.find((v) => v !== 'descarte' && v !== 'outro') || op[0];
  await pag.selectOption('#trd-tipo', tipo); await pag.fill('#trd-obs', 'conferido');
  await pag.click('#btn-ger-submit'); await pag.waitForTimeout(800);
  const t1 = b.docs.get('trocas/t1').data;
  conf(!(await pag.isVisible('#pin-overlay')) && t1.destino && /^Quali/.test(t1.destino.por) && t1.destino.porId === 'quali-t', 'destino anotado sem senha: ' + JSON.stringify(t1.destino));
  await ctx.close();

  console.log('Quem não é da Qualidade:');
  ({ ctx, pag } = await entrar('teste-outro'));
  await aba(pag, 'qualidade'); await pag.waitForTimeout(500);
  await pag.evaluate(() => document.querySelector('[data-q="nova-nc"]').click());
  await pag.waitForSelector('#q-sheet-overlay:not(.hidden)');
  conf(/Só quem é da Qualidade/.test(await pag.textContent('#q-form-body')) && !(await pag.isVisible('#btn-q-submit')), 'aviso e sem o botão de salvar');
  await pag.click('#btn-q-cancel');
  doc(b, 'trocas', 't2', { numero: 2, tipo: 'devolucao', cliente: 'Mercado Dois', itens: [{ produto: 'Água 1,5L', quantidade: 1, unidade: 'fardos' }], status: 'aberta', recebidoPor: 'Motorista Teste', criadoEm: new Date().toISOString() });
  await aba(pag, 'trocas'); await pag.waitForTimeout(500);
  conf(!(await pag.$('[data-troca="destino"]')), 'Trocas: sem o botão de anotar o destino');
  await ctx.close();

  console.log('Senha mestre:');
  ({ ctx, pag } = await entrar('teste-nicolas'));
  await aba(pag, 'qualidade'); await pag.waitForTimeout(500);
  await pag.evaluate(() => document.querySelector('[data-q="nova-nc"]').click());
  await pag.waitForSelector('#q-sheet-overlay:not(.hidden)');
  conf(!!(await pag.$('#q-resp')) && await pag.isVisible('#btn-q-submit'), 'senha mestre: como antes (responsável digitado)');
  await ctx.close();

  conf(!erros.length, 'sem erros de JavaScript' + (erros.length ? ': ' + erros.join(' | ') : ''));
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
