/* LEVÍSSIMA · teste: CD Renan e fretes das fontes (26/11/2026), na aba Produções externas.
 * Entrada no CD vinda de uma fonte (baixa o estoque da fonte; frete por palete perguntado e guardado para a cidade),
 * a próxima já vem com o valor; frete sem valor fica pendente e é informado depois; entrada da fábrica puxando uma
 * carga concluída; saída para cliente (não deixa sair mais do que há); saldo de paletes e chapas por freteiro; acerto;
 * relatórios e planilha; saída da fonte com frete para outra cidade; cancelar um lançamento devolve o saldo.
 * Rodar: python3 ferramentas/construir.py && node testes/cd-renan-e2e.js
 */
'use strict';
const fake = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }

(async () => {
  const amb = await fake.criar();
  const b = amb.banco.b;
  const agora = Date.now();
  const ontem = new Date(agora - 27 * 3600e3).toISOString().slice(0, 10);
  doc(b, 'produtos', 'p510', { nome: 'Água 510ml natural', unidade: 'fardos', unidadesPorPalete: 150, ordem: 1 });
  doc(b, 'motoristas', 'm1', { nome: 'Freteiro Um' });
  doc(b, 'motoristas', 'm2', { nome: 'Freteiro Três' });
  doc(b, 'prodext-movs', 'pm-prod1', { fonteId: 'atibaia', tipo: 'producao', data: ontem, itens: [{ item: 'p:510-natural', qtd: 100 }], efeitos: [{ item: 'p:510-natural', local: 'fonte', qtd: 100 }], por: 'Teste', em: new Date(agora - 26 * 3600e3).toISOString() });
  doc(b, 'cargas', 'cFab', { status: 'concluida', motorista: 'Freteiro Dois', data: ontem, concluidoEm: new Date(agora - 20 * 3600e3).toISOString(),
    clientes: [{ cliente: 'CD Renan', destino: 'Bragança Paulista', itens: [{ produtoId: 'p510', produtoNome: 'Água 510ml natural', quantidade: 50, unidade: 'fardos', paletes: 2, chapatex: 2 }] }],
    totalPaletes: 2, totalChapatex: 2, criadoEm: new Date(agora - 30 * 3600e3).toISOString() });

  const erros = [];
  const ctx = await amb.contexto({ viewport: { width: 1100, height: 1000 }, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo', acceptDownloads: true });
  const pag = await ctx.newPage();
  pag.on('pageerror', (e) => erros.push(String(e)));
  await pag.goto(amb.url + '/index.html');
  await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  await pag.fill('#login-senha', 'teste-nicolas');
  await pag.click('#btn-login-submit');
  await pag.waitForTimeout(1800);
  await pag.evaluate(() => document.querySelector('#admin-tabs [data-tab="prodexternas"]').click());
  await pag.waitForTimeout(500);

  const movs = () => Array.from(b.docs.values()).filter((d) => d.colecao === 'prodext-movs').map((d) => Object.assign({ id: d.id }, d.data));
  const ultimo = (tipo) => movs().filter((m) => m.tipo === tipo).sort((a, c) => String(c.em).localeCompare(String(a.em)))[0];
  const clicar = (sel) => pag.evaluate((s) => document.querySelector(s).click(), sel);
  const salvar = async () => { await pag.click('#btn-ger-submit'); await pag.waitForTimeout(500); };
  const erroForm = () => pag.evaluate(() => { const e = document.getElementById('ger-form-error'); return e && !e.classList.contains('hidden') ? e.textContent : ''; });
  const folhaAberta = () => pag.isVisible('#ger-sheet-overlay');
  const txt = (sel) => pag.textContent(sel);
  const q = (item, v) => pag.fill('#cdm-itens .cdm-q[data-item="' + item + '"]', String(v));

  console.log('Tela do CD:');
  conf(await pag.$('[data-px="fonte"][data-f="cd-renan"]') !== null, 'botão do CD Renan ao lado das fontes');
  await clicar('[data-px="fonte"][data-f="cd-renan"]');
  await pag.waitForTimeout(300);
  conf(/CD Renan · Bragança Paulista/.test(await txt('#px-conteudo')), 'tela do CD com a cidade');

  console.log('Entrada da Fonte Atibaia com frete novo:');
  await clicar('[data-px="cd-entrada"]');
  await pag.waitForSelector('#cdm-origem');
  conf(/Ainda sem valor combinado de Fonte Atibaia para Bragança Paulista/.test(await txt('#pxf-aviso')), 'pergunta o valor do frete (ainda sem valor para a cidade)');
  conf(/na fonte: 100/.test(await txt('#cdm-itens')), 'mostra o estoque da fonte');
  await pag.selectOption('#cdm-fr', 'm1');
  await q('p:510-natural', 40);
  await pag.fill('#cdm-pal-a', '4'); await pag.fill('#cdm-pal-b', '1'); await pag.fill('#cdm-cha-a', '4');
  await pag.fill('#pxf-valor', '35');
  await pag.waitForTimeout(100);
  conf(/Frete: R\$\s?140,00 \(4 paletes\)/.test(await txt('#pxf-total')), 'mostra o total do frete: ' + (await txt('#pxf-total')));
  await salvar();
  let e1 = ultimo('cd-entrada');
  conf(!(await folhaAberta()) && e1 && e1.origem === 'atibaia' && e1.freteiro.id === 'm1' && e1.frete.valorPalete === 35 && e1.frete.total === 140 && e1.frete.cidade === 'Bragança Paulista', 'entrada salva com o frete: ' + JSON.stringify(e1 && e1.frete));
  const fretes = () => ((b.docs.get('prodext-config/fretes') || {}).data || {}).valores || {};
  conf(fretes()['atibaia|bragancapaulista'] && fretes()['atibaia|bragancapaulista'].valor === 35, 'valor guardado para Atibaia → Bragança Paulista');
  conf(JSON.stringify(e1.efeitos.slice().sort((a, c) => a.k.localeCompare(c.k))) === JSON.stringify([{ k: 'cha|cd', qtd: 4 }, { k: 'cha|fr:m:m1', qtd: -4 }, { k: 'e|atibaia|p:510-natural', qtd: 40 }, { k: 'pal|cd', qtd: 3 }, { k: 'pal|fr:m:m1', qtd: -3 }]), 'efeitos: estoque, paletes e chapas no CD e com o freteiro');

  console.log('Segunda entrada: o valor já vem; sem valor fica pendente:');
  await clicar('[data-px="cd-entrada"]');
  await pag.waitForSelector('#cdm-origem');
  conf(await pag.inputValue('#pxf-valor') === '35', 'valor por palete já vem preenchido (35)');
  await pag.selectOption('#cdm-fr', 'm1');
  await q('p:510-natural', 70);
  await pag.fill('#cdm-pal-a', '2');
  await pag.fill('#pxf-valor', '');
  await salvar();
  conf(/Mais do que o estoque da fonte/.test(await erroForm()), 'avisa quando passa do estoque da fonte: ' + (await erroForm()));
  await q('p:510-natural', 20);
  await salvar();
  const e2 = ultimo('cd-entrada');
  conf(!(await folhaAberta()) && e2.id !== e1.id && e2.frete.valorPalete === null && e2.frete.paletes === 2, 'frete sem valor fica pendente');
  conf(/1 sem valor/.test(await txt('#px-conteudo')), 'cartão mostra 1 frete sem valor');
  await clicar('[data-px="cd-area"][data-f="fretes"]');
  await pag.waitForTimeout(200);
  await clicar('[data-px="frete-valor"][data-id="' + e2.id + '"]');
  await pag.waitForSelector('#pxf-valor');
  await pag.fill('#pxf-valor', '38');
  await pag.uncheck('#pxf-guardar').catch(() => {});
  await salvar();
  const e2b = movs().find((m) => m.id === e2.id);
  conf(e2b.frete.valorPalete === 38 && e2b.frete.total === 76 && fretes()['atibaia|bragancapaulista'].valor === 35, 'valor informado depois (38 × 2 = 76), sem mudar o combinado');
  conf(/Todos os fretes lançados têm valor/.test(await txt('#px-conteudo')), 'nenhum frete pendente');

  console.log('Entrada da fábrica puxando a carga:');
  await clicar('[data-px="cd-area"][data-f="entradas"]');
  await pag.waitForTimeout(200);
  await clicar('[data-px="cd-entrada"]');
  await pag.waitForSelector('#cdm-origem');
  await pag.selectOption('#cdm-origem', 'fabrica');
  await pag.waitForSelector('#cdm-carga');
  await pag.selectOption('#cdm-carga', 'cFab');
  await pag.waitForTimeout(100);
  conf(await pag.inputValue('#cdm-itens .cdm-q[data-item="f:p510"]') === '50' && await pag.inputValue('#cdm-pal-a') === '2' && await pag.inputValue('#cdm-fr') === '_outro' && await pag.inputValue('#cdm-fr-outro') === 'Freteiro Dois', 'preenche produtos, paletes e o freteiro da carga');
  conf(!(await pag.$('#pxf-cidade')), 'entrada da fábrica não tem frete de fonte');
  await salvar();
  const e3 = ultimo('cd-entrada');
  conf(e3.origem === 'fabrica' && e3.cargaId === 'cFab' && e3.freteiro.nome === 'Freteiro Dois' && !e3.frete, 'entrada da fábrica salva com a carga');

  console.log('Saída para cliente:');
  await clicar('[data-px="cd-area"][data-f="estoque"]');
  await pag.waitForTimeout(200);
  const tab = await txt('#px-conteudo .px-tab');
  conf(/Água 510ml natural/.test(tab) && /510ml natural/.test(tab), 'estoque por produto e origem');
  await clicar('[data-px="cd-saida"]');
  await pag.waitForSelector('#cdm-cliente');
  await pag.fill('#cdm-cliente', 'Mercado Exemplo'); await pag.fill('#cdm-cidade', 'Campinas');
  await pag.selectOption('#cdm-fr', 'm1');
  await pag.fill('#cdm-itens .cdm-q[data-k="e|atibaia|p:510-natural"]', '61');
  await salvar();
  conf(/no CD há 60/.test(await erroForm()), 'não deixa sair mais do que há no CD: ' + (await erroForm()));
  await pag.fill('#cdm-itens .cdm-q[data-k="e|atibaia|p:510-natural"]', '30');
  await pag.fill('#cdm-pal-a', '3');
  await salvar();
  const s1 = ultimo('cd-saida');
  conf(!(await folhaAberta()) && s1.cliente === 'Mercado Exemplo' && s1.cidade === 'Campinas' && s1.itens[0].qtd === 30 && s1.paletes.saiu === 3, 'saída salva');

  console.log('Paletes e chapas por freteiro:');
  await clicar('[data-px="cd-area"][data-f="paletes"]');
  await pag.waitForTimeout(200);
  const linhaFr = await pag.evaluate(() => Array.from(document.querySelectorAll('#px-conteudo .px-tab tbody tr')).map((r) => Array.from(r.cells).slice(0, 3).map((c) => c.childNodes[0].textContent.trim()).join('|')));
  // Freteiro Um: entrada (4 chegaram, 1 levou) −3; entrada (2 chegaram) −2; saída (3 saíram) +3 → −2 paletes; chapas −4
  conf(linhaFr.includes('Freteiro Um|-2|-4') && linhaFr.includes('Freteiro Dois|-2|-2'), 'saldo por freteiro: ' + linhaFr.join(' ; '));
  conf(/No CD\s*4 paletes · 6 chapas/.test(await txt('#px-conteudo')), 'no CD: 3 + 2 + 2 − 3 = 4 paletes e 4 + 2 = 6 chapas: ' + (await txt('#px-conteudo .an-lin')));
  await clicar('[data-px="cd-acerto"][data-ch="m:m1"]');
  await pag.waitForSelector('#cdm-lev-pal');
  conf(await pag.inputValue('#cdm-fr') === 'm1', 'acerto já vem com o freteiro');
  await pag.fill('#cdm-lev-pal', '2'); await pag.fill('#cdm-lev-cha', '4');
  await salvar();
  const linhaFr2 = await pag.evaluate(() => Array.from(document.querySelectorAll('#px-conteudo .px-tab tbody tr')).map((r) => r.cells[0].childNodes[0].textContent.trim()));
  conf(!linhaFr2.includes('Freteiro Um'), 'depois do acerto, Freteiro Um sem saldo: ' + linhaFr2.join(', '));

  console.log('Relatórios:');
  await clicar('[data-px="cd-area"][data-f="relatorios"]');
  await pag.waitForTimeout(200);
  await clicar('[data-px="cd-per"][data-f="30"]');
  await pag.waitForTimeout(200);
  const rel = await pag.evaluate(() => Array.from(document.querySelectorAll('#px-conteudo .px-tab tbody tr')).map((r) => Array.from(r.cells).map((c) => c.childNodes[0].textContent.trim()).join('|')));
  conf(rel.includes('510ml natural|0|60|30|0|0|30') && rel.includes('Água 510ml natural|0|50|0|0|0|50'), 'por produto: inicial, entradas, saídas, perdas, ajuste, final: ' + rel.join(' ; '));
  await clicar('[data-px="cd-relat"][data-f="clientes"]');
  await pag.waitForTimeout(200);
  conf(/Mercado Exemplo/.test(await txt('#px-conteudo .px-tab')), 'por cliente');
  await clicar('[data-px="cd-relat"][data-f="freteiros"]');
  await pag.waitForTimeout(200);
  conf(/Freteiro Um/.test(await txt('#px-conteudo .px-tab')) && /R\$\s?216,00/.test(await txt('#px-conteudo .px-tab')), 'por freteiro, com o frete das fontes (140 + 76)');
  const [dl] = await Promise.all([pag.waitForEvent('download', { timeout: 5000 }), clicar('[data-px="cd-csv"][data-f="freteiros"]')]);
  conf(/levissima-cd-renan-freteiros-.*\.csv$/.test(dl.suggestedFilename()), 'planilha baixada: ' + dl.suggestedFilename());

  console.log('Saída da fonte com frete para outra cidade:');
  await clicar('[data-px="fonte"][data-f="atibaia"]');
  await pag.waitForTimeout(200);
  conf(/Enviado para o CD/.test(await txt('#px-conteudo')), 'a fonte mostra o que foi para o CD');
  const naFonte = await pag.evaluate(() => document.querySelector('#px-conteudo .px-tab tbody tr').cells[1].textContent.trim());
  conf(naFonte === '40', 'estoque na fonte baixou o que foi para o CD (100 − 60 = ' + naFonte + ')');
  await clicar('[data-px="mov"][data-tipo="saida"]');
  await pag.waitForSelector('#pxm-frete-box');
  await pag.fill('#pxm-itens .pxm-q[data-item="p:510-natural"]', '10');
  await pag.selectOption('#pxm-fr', 'm2');
  await pag.fill('#pxf-cidade', 'Campinas');
  await pag.waitForTimeout(100);
  conf(/Ainda sem valor combinado de Fonte Atibaia para Campinas/.test(await txt('#pxf-aviso')), 'pergunta o valor para Campinas');
  await salvar();
  conf(/quantos paletes/.test(await erroForm()), 'pede os paletes');
  await pag.fill('#pxm-paletes', '1');
  await pag.fill('#pxf-valor', '50');
  await salvar();
  const sf = ultimo('saida');
  conf(!(await folhaAberta()) && sf.frete && sf.frete.cidade === 'Campinas' && sf.frete.total === 50 && sf.freteiro.id === 'm2' && fretes()['atibaia|campinas'].valor === 50, 'saída da fonte com frete guardado para Campinas');
  await clicar('[data-px="area"][data-f="fretes"]');
  await pag.waitForTimeout(200);
  const ft = await txt('#px-conteudo');
  conf(/Bragança Paulista/.test(ft) && /Campinas/.test(ft) && /Fretes deste mês: R\$\s?266,00/.test(ft), 'Fretes da fonte: tabela por cidade e total do mês (140 + 76 + 50)');

  console.log('Cancelar devolve o saldo:');
  await clicar('[data-px="fonte"][data-f="cd-renan"]');
  await clicar('[data-px="cd-area"][data-f="saidas"]');
  await pag.waitForTimeout(200);
  await clicar('[data-px="mov-cancelar"][data-id="' + s1.id + '"]');
  await pag.waitForSelector('#px-motivo');
  await pag.fill('#px-motivo', 'lançado errado');
  await salvar();
  await clicar('[data-px="cd-area"][data-f="estoque"]');
  await pag.waitForTimeout(200);
  const tot = await pag.evaluate(() => document.querySelector('#px-conteudo .px-tab tfoot tr').lastElementChild.textContent.trim());
  conf(tot === '110', 'estoque do CD volta a 110 fardos (60 + 50): ' + tot);

  conf(!erros.length, 'sem erros de JavaScript' + (erros.length ? ': ' + erros.join(' | ') : ''));
  await ctx.close();
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
