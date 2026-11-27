/* LEVÍSSIMA · teste: Painel de permissões em Cadastros (26/11/2026).
 * Tabela pessoas × funções (abas e nível, módulos, assinaturas, Compras, laboratório, permissões especiais), com o que vem
 * do cargo em itálico; mudar pela célula (acesso ao app e marcas do perfil), sem acesso ao app não muda aba, líder de
 * produção trava as abas; título da coluna mostra quem tem; filtros e busca; outros acessos; alertas; histórico (painel e
 * perfil) e planilhas. Só a senha mestre vê.
 * Rodar: python3 ferramentas/construir.py && node testes/permissoes-e2e.js
 */
'use strict';
const fake = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }
const agora = Date.now();
fake.USUARIOS.push(
  { senha: 'teste-ana-p', papel: 'equipe', nome: 'Ana Exemplo', ref: 'escritorio:ana-p', modulos: ['abas', 'aba:cargas', 'aba:estoque', 'ver:estoque', 'manutencao:gerir'], em: '2026-10-01T10:00:00Z', aparelhos: 2, usadoEm: new Date(agora - 864e5).toISOString() },
  { senha: 'teste-bia-p', papel: 'equipe', nome: 'Bia Exemplo', ref: 'escritorio:bia-p', modulos: ['abas', 'aba:cargas'], em: '2026-01-01T10:00:00Z', aparelhos: 1, usadoEm: '2026-01-05T10:00:00Z' },
  { senha: 'teste-tab-p', papel: 'setor', nome: 'Tablet Envase', ref: 'setor:tab-p', modulos: ['manutencao'], em: '2026-11-01T10:00:00Z', usadoEm: new Date(agora - 3600e3).toISOString() }
);
const USU = (ref) => fake.USUARIOS.find((u) => u.ref === ref);

(async () => {
  const amb = await fake.criar();
  const b = amb.banco.b;
  doc(b, 'equipe', 'ana-p', { nome: 'Ana Exemplo', cargo: 'gerente', area: 'Qualidade', temPin: true, faturamento: true });
  doc(b, 'equipe', 'bia-p', { nome: 'Bia Exemplo', cargo: 'assistente', area: 'Expedição', temPin: true, conferente: true });
  doc(b, 'equipe', 'caio-p', { nome: 'Caio Exemplo', cargo: 'operador', area: 'Produção', temPin: true, labGerencia: true });

  const erros = [];
  const ctx = await amb.contexto({ viewport: { width: 1200, height: 1000 }, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo', acceptDownloads: true });
  const pag = await ctx.newPage();
  pag.on('pageerror', (e) => erros.push(String(e)));
  async function entrar(senha) {
    await pag.goto(amb.url + '/index.html');
    await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
    await pag.fill('#login-senha', senha);
    await pag.click('#btn-login-submit');
    await pag.waitForTimeout(1800);
  }
  await entrar('teste-nicolas');
  await pag.evaluate(() => document.querySelector('#admin-tabs .seg-btn[data-tab="cadastros"]').click());
  await pag.waitForSelector('#pp-tabela .pp-mat', { timeout: 8000 });

  const cel = (id, col) => pag.evaluate(([id, col]) => { const e = document.querySelector('[data-pp="cel"][data-id="' + id + '"][data-col="' + col + '"]'); return e ? { t: e.textContent, c: e.className } : null; }, [id, col]);
  const clicar = (sel) => pag.evaluate((s) => document.querySelector(s).click(), sel);
  const abrirCel = async (id, col) => { await clicar('[data-pp="cel"][data-id="' + id + '"][data-col="' + col + '"]'); await pag.waitForSelector('#ger-sheet-overlay:not(.hidden)'); };
  const escolher = async (v) => { await pag.check('#ger-form-body input[name="pp-op"][value="' + v + '"]'); await pag.click('#btn-ger-submit'); await pag.waitForTimeout(700); };
  const hist = () => Array.from(b.docs.values()).filter((d) => d.colecao === 'permissoes-historico').map((d) => d.data);

  console.log('Tabela:');
  const topo = await pag.textContent('#pp-topo');
  conf(/2\s*pessoas com acesso ao app/.test(topo) && /1\s*só com a senha de 4 números/.test(topo) && /1\s*tablets e acessos de setor/.test(topo), 'cartões: 2 com acesso, 1 só com a senha de 4 números, 1 tablet');
  let c = await cel('ana-p', 'aba:cargas'); conf(c && c.t === 'E', 'Ana · Cargas: E (edita)');
  c = await cel('ana-p', 'aba:estoque'); conf(c && c.t === 'V', 'Ana · Estoque: V (só vê)');
  c = await cel('ana-p', 'mod:manutencao'); conf(c && c.t === 'G', 'Ana · Manutenção: G (gerencia)');
  c = await cel('ana-p', 'm:atendePredial'); conf(c && c.t === '✓' && /cargo/.test(c.c), 'Ana · Atende predial: vem de gerenciar a Manutenção (itálico)');
  c = await cel('ana-p', 'm:coordenador'); conf(c && c.t === '✓' && /cargo/.test(c.c), 'Ana · Autoriza pedidos: pelo cargo Gerente (itálico)');
  c = await cel('ana-p', 'm:faturamento'); conf(c && c.t === '✓' && !/cargo/.test(c.c), 'Ana · Faturamento: marcado no perfil');
  c = await cel('caio-p', 'aba:cargas'); conf(c && c.t === '·' && /sem/.test(c.c), 'Caio (sem acesso ao app) · Cargas: ·');
  c = await cel('caio-p', 'm:labValida'); conf(c && c.t === '✓' && /cargo/.test(c.c), 'Caio · Valida resultados: pela Gerência da Qualidade');
  const nome = await pag.textContent('[data-pp="pessoa"][data-id="ana-p"]');
  conf(/Gerente · Qualidade/.test(nome) && /app desde 01\/10\/2026 · 2 aparelhos · usou/.test(nome), 'nome com cargo, área e o uso do acesso: ' + nome.replace(/\s+/g, ' '));

  console.log('Alertas e outros acessos:');
  conf(/Acessos parados[^]*Bia Exemplo \(usou 05\/01\/2026\)/.test(topo), 'acesso parado: Bia');
  conf(/sem cadastro na equipe[^]*Angélica Souza/.test(topo), 'acesso sem cadastro na equipe');
  conf(/Funções sem ninguém/.test(topo) && /Aprova frete com valor editado/.test(topo), 'funções sem ninguém');
  const outros = await pag.textContent('#pp-outros');
  conf(/Senha mestre/.test(outros) && /Tablet Envase/.test(outros) && /Módulos: Manutenção/.test(outros) && /Senha da equipe do escritório/.test(outros) && /motorista/.test(outros), 'outros acessos: senha mestre, senha da equipe, tablet, motoristas');

  console.log('Mudar pela célula:');
  await abrirCel('ana-p', 'aba:estoque');
  await escolher('E');
  conf(!USU('escritorio:ana-p').modulos.includes('ver:estoque') && USU('escritorio:ana-p').modulos.includes('aba:estoque'), 'Ana · Estoque passa a Edita no acesso: ' + USU('escritorio:ana-p').modulos.join(','));
  await pag.waitForTimeout(500);
  c = await cel('ana-p', 'aba:estoque'); conf(c && c.t === 'E', 'a célula mostra E');
  let h = hist();
  conf(h.length === 1 && h[0].origem === 'painel' && h[0].porRef === 'mestre' && h[0].pessoa === 'Ana Exemplo' && h[0].mudancas[0].f === 'Aba Estoque' && h[0].mudancas[0].de === 'Só vê' && h[0].mudancas[0].para === 'Edita', 'histórico: ' + JSON.stringify(h[0] && h[0].mudancas));
  await abrirCel('bia-p', 'm:faturamento');
  await escolher('S');
  conf(b.docs.get('equipe/bia-p').data.faturamento === true, 'marca do perfil: Bia passa a dar o ok do faturamento');
  await abrirCel('caio-p', 'aba:cargas');
  conf(/ainda não tem acesso ao app/.test(await pag.textContent('#ger-form-body')) && !(await pag.isVisible('#btn-ger-submit')), 'sem acesso ao app: explica e não muda a aba');
  await pag.click('#btn-ger-cancel');
  await abrirCel('bia-p', 'esp:lider_producao');
  await escolher('S');
  conf(JSON.stringify(USU('escritorio:bia-p').modulos) === JSON.stringify(['abas', 'aba:estoque', 'inclui:estoque', 'lider_producao']), 'líder de produção: só o lançamento da produção');
  await pag.waitForTimeout(400);
  await abrirCel('bia-p', 'aba:cargas');
  conf(/líder de produção/.test(await pag.textContent('#ger-form-body')) && !(await pag.isVisible('#btn-ger-submit')), 'com líder de produção, as abas ficam travadas');
  await pag.click('#btn-ger-cancel');

  console.log('Coluna, filtros e busca:');
  await clicar('[data-pp="col"][data-col="m:faturamento"]');
  await pag.waitForSelector('#ger-sheet-overlay:not(.hidden)');
  const qt = await pag.textContent('#ger-form-body');
  conf(/Quem tem \(2\)/.test(qt) && /Ana Exemplo/.test(qt) && /Bia Exemplo/.test(qt), 'título da coluna: quem tem o faturamento');
  await pag.click('#btn-ger-cancel');
  await clicar('[data-pp="grupo"][data-g="assina"]');
  await pag.waitForTimeout(200);
  conf(await pag.$$eval('#pp-tabela .pp-h', (l) => l.length) === 7, 'filtro Assinaturas: 7 colunas');
  await clicar('[data-pp="grupo"][data-g=""]');
  await pag.fill('#pp-busca', 'conferente');
  await pag.waitForTimeout(200);
  conf(await pag.$$eval('#pp-tabela .pp-h', (l) => l.map((e) => e.dataset.col).join(',')) === 'm:conferente', 'busca acha a função (Conferente)');
  await pag.fill('#pp-busca', 'caio');
  await pag.waitForTimeout(200);
  conf(await pag.$$eval('#pp-tabela [data-pp="pessoa"]', (l) => l.map((e) => e.dataset.id).join(',')) === 'caio-p', 'busca acha a pessoa');
  await pag.fill('#pp-busca', '');
  await pag.check('#pp-so-app');
  await pag.waitForTimeout(200);
  conf(await pag.$$eval('#pp-tabela [data-pp="pessoa"]', (l) => l.map((e) => e.dataset.id).join(',')) === 'ana-p,bia-p', 'só quem tem acesso ao app');
  await pag.uncheck('#pp-so-app');

  console.log('Perfil também registra:');
  await clicar('[data-pp="pessoa"][data-id="caio-p"]');
  await pag.waitForSelector('#equipe-sheet-overlay:not(.hidden)');
  await pag.check('#f-equipe-qual');
  await pag.click('#equipe-form button[type="submit"]');
  await pag.waitForTimeout(900);
  h = hist();
  const hp = h.find((x) => x.origem === 'perfil');
  conf(b.docs.get('equipe/caio-p').data.qualidade === true && hp && hp.pessoa === 'Caio Exemplo' && hp.mudancas.length === 1 && hp.mudancas[0].f === 'Qualidade' && hp.mudancas[0].para === 'Sim', 'salvar o perfil registra só o que mudou: ' + JSON.stringify(hp && hp.mudancas));

  console.log('Histórico e planilhas:');
  await clicar('[data-pp="hist"]');
  await pag.waitForTimeout(600);
  const ht = await pag.textContent('#pp-hist');
  conf(/Ana Exemplo/.test(ht) && /Aba Estoque: Só vê → Edita/.test(ht) && /pelo painel/.test(ht) && /Caio Exemplo/.test(ht) && /pelo perfil/.test(ht), 'histórico na tela');
  let [dl] = await Promise.all([pag.waitForEvent('download', { timeout: 5000 }), clicar('[data-pp="csv"]')]);
  const csv = require('fs').readFileSync(await dl.path(), 'utf8');
  conf(/levissima-permissoes-/.test(dl.suggestedFilename()) && /Ana Exemplo;Gerente;Qualidade/.test(csv) && /Tablet Envase/.test(csv), 'planilha da tabela');
  [dl] = await Promise.all([pag.waitForEvent('download', { timeout: 5000 }), clicar('[data-pp="hist-csv"]')]);
  conf(/levissima-historico-permissoes-/.test(dl.suggestedFilename()), 'planilha do histórico');

  console.log('Só a senha mestre:');
  const ctx2 = await amb.contexto({ viewport: { width: 1200, height: 1000 } });
  const pag2 = await ctx2.newPage();
  pag2.on('pageerror', (e) => erros.push('Ana: ' + String(e)));
  await pag2.goto(amb.url + '/index.html');
  await pag2.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  await pag2.fill('#login-senha', 'teste-ana-p'); await pag2.click('#btn-login-submit'); await pag2.waitForTimeout(1800);
  conf(await pag2.evaluate(() => !document.querySelector('#admin-tabs .seg-btn[data-tab="cadastros"]') || document.querySelector('#admin-tabs .seg-btn[data-tab="cadastros"]').classList.contains('hidden') || document.getElementById('perm-admin').classList.contains('hidden')), 'quem não é a senha mestre não vê o painel');
  await ctx2.close();

  conf(!erros.length, 'sem erros de JavaScript' + (erros.length ? ': ' + erros.join(' | ') : ''));
  await ctx.close();
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
