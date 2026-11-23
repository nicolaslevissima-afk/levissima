/* LEVÍSSIMA · teste: Compras — cada um vê só o seu (23/11/2026, banco 0063).
 * Supervisor, coordenador e gerente: os pedidos do setor deles (setores marcados ou a área) e os que fizeram ou
 * assinaram. Os demais: só os próprios pedidos (a compra feita não aparece mais para todos em "Para receber").
 * Compras e diretoria: tudo. Setor sem gestor (Expedição): só diretoria e compras.
 * Rodar: python3 ferramentas/construir.py && node testes/compras-setor-e2e.js
 */
'use strict';
const fake = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }
const ABAS = ['abas', 'aba:compras'];
fake.USUARIOS.push(
  { senha: 'teste-gerente', papel: 'equipe', nome: 'Gerente Q', ref: 'escritorio:gerente-q', modulos: ABAS },
  { senha: 'teste-lider', papel: 'equipe', nome: 'Líder P', ref: 'escritorio:lider-p', modulos: ABAS },
  { senha: 'teste-compras', papel: 'equipe', nome: 'Compras A', ref: 'escritorio:compras-a', modulos: ABAS }
);

(async () => {
  const amb = await fake.criar();
  const b = amb.banco.b;
  const agora = new Date().toISOString();
  doc(b, 'equipe', 'gerente-q', { nome: 'Gerente Q', cargo: 'gerente', area: 'Qualidade' });
  doc(b, 'equipe', 'lider-p', { nome: 'Líder P', cargo: 'lider', area: 'Produção' });
  doc(b, 'equipe', 'compras-a', { nome: 'Compras A', cargo: 'assistente', area: 'Compras', compras: true });
  doc(b, 'equipe', 'analista-q', { nome: 'Analista Q', cargo: 'analista', area: 'Qualidade' });
  const itens = [{ descricao: 'Luvas', quantidade: 2, unidade: 'cx' }];
  const ped = (id, nome) => ({ id, nome, ref: 'escritorio:' + id, em: agora });
  const oc = (id, numero, status, setor, pedido, extra) => doc(b, 'compras-ordens', id, Object.assign({ numero, status, setor, urgencia: 'normal', itens, pedido, criadoEm: agora, atualizadoEm: agora }, extra || {}));
  oc('a1', 1, 'pedido', 'Expedição', ped('lider-p', 'Líder P'));
  oc('a2', 2, 'pedido', 'Qualidade', ped('analista-q', 'Analista Q'));
  oc('a3', 3, 'comprado', 'Produção', ped('analista-q', 'Analista Q'), { compra: { nome: 'Compras A', id: 'compras-a', fornecedor: 'Loja', valor: 10, em: agora } });
  oc('a4', 4, 'pedido', 'Manutenção', ped('analista-q', 'Analista Q'));
  oc('a5', 5, 'comprado', 'Qualidade', ped('analista-q', 'Analista Q'), { compra: { nome: 'Compras A', id: 'compras-a', fornecedor: 'Loja', valor: 10, em: agora } });

  async function vistos(senha) {
    const ctx = await amb.contexto({ viewport: { width: 1100, height: 900 } });
    const pag = await ctx.newPage();
    await pag.goto(amb.url + '/index.html');
    await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
    await pag.fill('#login-senha', senha);
    await pag.click('#btn-login-submit');
    await pag.waitForTimeout(1800);
    await pag.evaluate(() => document.querySelector('#admin-tabs .seg-btn[data-tab="compras"]').click());
    await pag.waitForTimeout(600);
    const ids = new Set();
    for (const f of ['abertas', 'comprado']) {
      await pag.evaluate((f) => { const e = document.querySelector('[data-oc="filtro"][data-f="' + f + '"]'); if (e) e.click(); }, f);
      await pag.waitForTimeout(300);
      (await pag.$$eval('#oc-conteudo [data-id]', (l) => l.map((e) => e.dataset.id))).forEach((x) => { if (/^a\d$/.test(x)) ids.add(x); });
    }
    const hint = await pag.textContent('#oc-conteudo .oc-so-meus').catch(() => '');
    await ctx.close();
    return { ids: Array.from(ids).sort().join(','), hint: hint || '' };
  }
  let r = await vistos('teste-gerente');
  conf(r.ids === 'a2,a5', 'gerente da Qualidade vê só a Qualidade (não vê Expedição, Manutenção nem Produção): ' + r.ids);
  conf(/pedidos do seu setor \(Qualidade\)/.test(r.hint), 'aviso diz o setor: ' + r.hint.trim());
  r = await vistos('teste-lider');
  conf(r.ids === 'a1', 'líder vê só o próprio pedido (sem as compras dos outros em "Para receber"): ' + r.ids);
  conf(/Você vê os pedidos que fez\./.test(r.hint), 'aviso para quem não é gestor: ' + r.hint.trim());
  r = await vistos('teste-compras');
  conf(r.ids === 'a1,a2,a3,a4,a5', 'Compras vê tudo: ' + r.ids);
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
