/* LEVÍSSIMA · teste: Chat (editar, apagar, reagir 👍/👎) e sessão (30 min sem uso, app aberto de novo).
 * Pedido de 20/10/2026. Rodar: node testes/chat-sessao-e2e.js   (depois de python3 ferramentas/construir.py --modulos)
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { criar } = require('./banco-fake');

const SHOTS = process.env.SHOTS || path.join(__dirname, 'shots');
fs.mkdirSync(SHOTS, { recursive: true });
let passou = 0, falhou = 0;
function ok(c, msg) { if (c) { passou++; console.log('  ✓ ' + msg); } else { falhou++; console.log('  ✗ FALHOU: ' + msg); } }
const espera = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const amb = await criar();
  const U = Object.fromEntries(amb.USUARIOS.map((u) => [u.ref, u]));
  async function entrar(pag, senha) {
    await pag.goto(amb.url + '/index.html');
    await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
    await pag.fill('#login-senha', senha);
    await pag.click('#btn-login-submit');
    await pag.waitForSelector('#admin-view:not(.hidden)', { timeout: 15000 });
    await pag.waitForTimeout(600);
  }
  const aba = async (pag, t) => { await pag.click('#admin-tabs .seg-btn[data-tab="' + t + '"]'); await pag.waitForTimeout(300); };
  const texto = (pag, sel) => pag.$eval(sel, (e) => e.innerText).catch(() => '');
  const msgs = () => amb.banco.b.chat;
  const idDe = (t) => (msgs().find((m) => m.texto === t) || {}).id;
  const bolha = (box, id) => box + ' .chat-bolha[data-chat-msg="' + id + '"]';
  async function abrirConversa(pag, ref) { await aba(pag, 'chat'); await pag.click('#chat-conteudo [data-chat="abrir"][data-ref="' + ref + '"]'); await pag.waitForTimeout(400); }
  async function enviar(pag, box, t) { await pag.fill('#chat-texto', t); await pag.click(box + ' .chat-escrever button[type=submit]'); await pag.waitForTimeout(400); }

  // ===================== 1. CHAT =====================
  console.log('1. Chat: reagir, editar e apagar');
  const ctxA = await amb.contexto(), ctxB = await amb.contexto();
  const ang = await ctxA.newPage(), and = await ctxB.newPage();
  await entrar(ang, U['escritorio:equipe-angelica'].senha);
  await entrar(and, U['escritorio:equipe-andre'].senha);
  await abrirConversa(ang, 'escritorio:equipe-andre');
  ok(/reagir com 👍 ou 👎, editar ou apagar/.test(await texto(ang, '#chat-conteudo .chat-cab')), 'a conversa explica: toque para reagir, editar ou apagar');
  await enviar(ang, '#chat-conteudo', 'Bom dia, André');
  await abrirConversa(and, 'escritorio:equipe-angelica');
  ok(/Bom dia, André/.test(await texto(and, '#chat-conteudo .chat-msgs')), 'André recebe a mensagem');
  await enviar(and, '#chat-conteudo', 'Bom dia!');
  await ang.waitForTimeout(400);
  const idAnd = idDe('Bom dia!'), idAng = idDe('Bom dia, André');
  ok(!!(await ang.$(bolha('#chat-conteudo', idAnd))), 'Angélica recebe a resposta na hora');

  // reagir na mensagem do outro: só 👍/👎 (sem editar/apagar)
  await ang.click(bolha('#chat-conteudo', idAnd) + ' .chat-txt');
  await ang.waitForTimeout(200);
  const acoesOutro = await texto(ang, bolha('#chat-conteudo', idAnd) + ' .chat-acoes');
  ok(/👍/.test(acoesOutro) && /👎/.test(acoesOutro) && !/Editar|Apagar/.test(acoesOutro), 'na mensagem do outro: só 👍 e 👎 (não edita nem apaga a dos outros)');
  await ang.screenshot({ path: path.join(SHOTS, 'chat-1-acoes-outro.png') });
  await ang.click(bolha('#chat-conteudo', idAnd) + ' .chat-acoes [data-chat-reagir="👍"]');
  await ang.waitForTimeout(500);
  ok(JSON.stringify(msgs().find((m) => m.id === idAnd).reacoes) === JSON.stringify({ 'escritorio:equipe-angelica': '👍' }), 'reação 👍 gravada no banco');
  ok(!!(await ang.$(bolha('#chat-conteudo', idAnd) + ' .chat-reacao.minha')), 'Angélica vê o 👍 marcado como dela');
  ok(!(await ang.$(bolha('#chat-conteudo', idAnd) + ' .chat-acoes')), 'as ações fecham depois de reagir');
  await and.waitForTimeout(300);
  const pillAnd = await and.$eval(bolha('#chat-conteudo', idAnd) + ' .chat-reacao', (e) => e.getAttribute('aria-label')).catch(() => '');
  ok(/👍 de Angélica/.test(pillAnd), 'André vê na hora: 👍 de Angélica (' + pillAnd + ')');
  // André toca no 👍 (reage igual): 👍 2
  await and.click(bolha('#chat-conteudo', idAnd) + ' .chat-reacao');
  await and.waitForTimeout(500);
  ok(/👍 2/.test(await texto(ang, bolha('#chat-conteudo', idAnd) + ' .chat-reacoes')), 'André reage igual: aparece 👍 2 para os dois');
  // Angélica troca para 👎
  await ang.click(bolha('#chat-conteudo', idAnd) + ' .chat-mais');
  await ang.waitForTimeout(150);
  await ang.click(bolha('#chat-conteudo', idAnd) + ' .chat-acoes [data-chat-reagir="👎"]');
  await ang.waitForTimeout(500);
  const rx = msgs().find((m) => m.id === idAnd).reacoes;
  ok(rx['escritorio:equipe-angelica'] === '👎' && rx['escritorio:equipe-andre'] === '👍', 'Angélica troca para 👎 (uma reação por pessoa)');
  // tocar no próprio 👎 tira
  await ang.click(bolha('#chat-conteudo', idAnd) + ' .chat-reacao.minha');
  await ang.waitForTimeout(500);
  ok(!msgs().find((m) => m.id === idAnd).reacoes['escritorio:equipe-angelica'], 'tocar de novo na própria reação tira');
  // aviso de reação com a conversa fechada
  await and.click('#chat-conteudo [data-chat="voltar"]');
  await and.waitForTimeout(300);
  await ang.click(bolha('#chat-conteudo', idAnd) + ' .chat-mais');
  await ang.click(bolha('#chat-conteudo', idAnd) + ' .chat-acoes [data-chat-reagir="👍"]');
  await and.waitForTimeout(600);
  ok(/👍 Angélica.*reagiu à sua mensagem/.test(await texto(and, '#toast')), 'André, fora da conversa, recebe o aviso "👍 Angélica reagiu à sua mensagem"');
  await abrirConversa(and, 'escritorio:equipe-angelica');

  // editar a própria mensagem
  await ang.fill('#chat-texto', 'rascunho que estava escrito');
  await ang.click(bolha('#chat-conteudo', idAng) + ' .chat-txt');
  await ang.waitForTimeout(200);
  const acoesMinha = await texto(ang, bolha('#chat-conteudo', idAng) + ' .chat-acoes');
  ok(/Editar/.test(acoesMinha) && /Apagar/.test(acoesMinha) && /👍/.test(acoesMinha), 'na própria mensagem: 👍 👎, Editar e Apagar');
  await ang.screenshot({ path: path.join(SHOTS, 'chat-2-acoes-minha.png') });
  await ang.click(bolha('#chat-conteudo', idAng) + ' [data-chat-editar]');
  await ang.waitForTimeout(200);
  ok(await ang.$eval('#chat-texto', (e) => e.value) === 'Bom dia, André', 'Editar leva o texto da mensagem para a caixa');
  ok(!(await ang.$('#chat-editando.hidden')) && /Salvar/.test(await texto(ang, '#chat-conteudo .chat-escrever button[type=submit]')), 'aparece "Editando a mensagem" e o botão vira Salvar');
  await ang.screenshot({ path: path.join(SHOTS, 'chat-3-editando.png') });
  // cancelar devolve o rascunho
  await ang.click('#chat-conteudo [data-chat="cancelar-edicao"]');
  await ang.waitForTimeout(200);
  ok(await ang.$eval('#chat-texto', (e) => e.value) === 'rascunho que estava escrito' && /Enviar/.test(await texto(ang, '#chat-conteudo .chat-escrever button[type=submit]')), 'Cancelar volta o rascunho que estava escrito');
  // editar e salvar
  await ang.click(bolha('#chat-conteudo', idAng) + ' .chat-mais');
  await ang.click(bolha('#chat-conteudo', idAng) + ' [data-chat-editar]');
  await ang.fill('#chat-texto', 'Bom dia, André! Tudo bem?');
  await ang.click('#chat-conteudo .chat-escrever button[type=submit]');
  await ang.waitForTimeout(600);
  const mEd = msgs().find((m) => m.id === idAng);
  ok(mEd.texto === 'Bom dia, André! Tudo bem?' && !!mEd.editada_em, 'edição gravada no banco (com a marca de editada)');
  ok(/Tudo bem\?/.test(await texto(ang, bolha('#chat-conteudo', idAng))) && /editada/.test(await texto(ang, bolha('#chat-conteudo', idAng) + ' .chat-hora')), 'Angélica vê o texto novo com "editada"');
  ok(await ang.$eval('#chat-texto', (e) => e.value) === 'rascunho que estava escrito', 'depois de salvar, o rascunho volta para a caixa');
  await and.waitForTimeout(300);
  const tAnd = await texto(and, '#chat-conteudo .chat-msgs');
  ok(/Bom dia, André! Tudo bem\?/.test(tAnd) && /editada/.test(tAnd), 'André vê na hora o texto editado, com "editada"');
  ok(!(await and.$(bolha('#chat-conteudo', idAng) + ' [data-chat-editar]')), 'André não tem Editar na mensagem da Angélica');
  await and.click(bolha('#chat-conteudo', idAng) + ' .chat-txt');
  await and.waitForTimeout(150);
  ok(!/Editar|Apagar/.test(await texto(and, bolha('#chat-conteudo', idAng) + ' .chat-acoes')), 'André, na mensagem da Angélica, só tem as reações');
  await and.click(bolha('#chat-conteudo', idAng) + ' .chat-txt'); // fecha

  // apagar a própria mensagem, mesmo antiga (antes: só até 1 hora)
  const antiga = { id: ++amb.banco.b.seq, tipo: 'chat', conversa: 'escritorio:equipe-andre|escritorio:equipe-angelica', de: 'escritorio:equipe-angelica', de_nome: 'Angélica Souza',
    para: 'escritorio:equipe-andre', texto: 'Mensagem de ontem', criado_em: new Date(Date.now() - 26 * 3600000).toISOString(), lida: true, apagada: false, reacoes: { 'escritorio:equipe-andre': '👍' } };
  amb.banco.b.chat.push(antiga); amb.banco.b.chat.sort((x, y) => x.id - y.id);
  await ang.reload(); await ang.waitForSelector('#admin-view:not(.hidden)'); await ang.waitForTimeout(500);
  await abrirConversa(ang, 'escritorio:equipe-andre');
  await ang.click(bolha('#chat-conteudo', antiga.id) + ' .chat-txt');
  await ang.waitForTimeout(150);
  ok(!!(await ang.$(bolha('#chat-conteudo', antiga.id) + ' [data-chat-apagar]')), 'mensagem de ontem: a dona ainda pode apagar (sem o limite de 1 hora)');
  ok(!!(await ang.$(bolha('#chat-conteudo', antiga.id) + ' [data-chat-editar]')), 'mensagem de ontem: a dona ainda pode editar');
  await ang.click(bolha('#chat-conteudo', antiga.id) + ' [data-chat-apagar]');
  ok(/Tocar de novo/.test(await texto(ang, bolha('#chat-conteudo', antiga.id) + ' [data-chat-apagar]')), 'apagar pede confirmação (tocar de novo)');
  await ang.click(bolha('#chat-conteudo', antiga.id) + ' [data-chat-apagar]');
  await ang.waitForTimeout(600);
  const mAp = msgs().find((m) => m.id === antiga.id);
  ok(mAp.apagada && mAp.texto === '(mensagem apagada)' && Object.keys(mAp.reacoes).length === 0, 'apagada no banco (o texto e as reações somem)');
  await and.waitForTimeout(300);
  ok(/Mensagem apagada/.test(await texto(and, '#chat-conteudo .chat-msgs')) && !/Mensagem de ontem/.test(await texto(and, '#chat-conteudo .chat-msgs')), 'some na hora também para o André');

  // Solicitações: editar e apagar a própria; 👍/👎 também nas solicitações (pedido de 21/10/2026)
  await aba(ang, 'solicitacoes');
  await enviar(ang, '#sol-conteudo', 'Quero um relatório');
  const idSol = idDe('Quero um relatório');
  await ang.click(bolha('#sol-conteudo', idSol) + ' .chat-txt');
  await ang.waitForTimeout(150);
  const acSol = await texto(ang, bolha('#sol-conteudo', idSol) + ' .chat-acoes');
  ok(/Editar/.test(acSol) && /Apagar/.test(acSol) && /👍/.test(acSol) && /👎/.test(acSol), 'Solicitações: edita, apaga e reage 👍/👎');
  await ang.click(bolha('#sol-conteudo', idSol) + ' [data-chat-editar]');
  await ang.fill('#chat-texto', 'Quero um relatório das devoluções');
  await ang.press('#chat-texto', 'Escape');
  await ang.waitForTimeout(200);
  ok(msgs().find((m) => m.id === idSol).texto === 'Quero um relatório' && await ang.$eval('#chat-texto', (e) => e.value) === '', 'Esc cancela a edição sem gravar');
  await ang.click(bolha('#sol-conteudo', idSol) + ' .chat-mais');
  await ang.click(bolha('#sol-conteudo', idSol) + ' [data-chat-editar]');
  await ang.fill('#chat-texto', 'Quero um relatório das devoluções');
  await ang.click('#sol-conteudo .chat-escrever button[type=submit]');
  await ang.waitForTimeout(500);
  ok(msgs().find((m) => m.id === idSol).texto === 'Quero um relatório das devoluções', 'Solicitação editada');
  await ctxB.close();

  // ===================== 2. SESSÃO =====================
  console.log('2. Sessão: 30 min sem uso e app aberto de novo');
  const uso = (pag, minAtras) => pag.evaluate((m) => localStorage.setItem('levissima-ultimo-uso', String(Date.now() - m * 60000)), minAtras);
  const lerUso = (pag) => pag.evaluate(() => Number(localStorage.getItem('levissima-ultimo-uso')));
  const naSenha = async (pag) => !!(await pag.$('#lock-login-form:not(.hidden)'));
  const temLogin = (pag) => pag.evaluate(() => !!localStorage.getItem('levissima-login'));

  await aba(ang, 'inicio');
  await uso(ang, 29);
  await ang.click('#admin-tabs .seg-btn[data-tab="cargas"]');
  await ang.waitForTimeout(300);
  ok(!(await naSenha(ang)) && Date.now() - (await lerUso(ang)) < 5000, '29 min parado e tocou: continua dentro e o relógio de uso recomeça');
  await uso(ang, 31);
  const saidasAntes = amb.banco.b.log.filter((l) => l.evento === 'signOut').length;
  await ang.click('#admin-tabs .seg-btn[data-tab="estoque"]');
  await ang.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 10000 });
  ok(true, '31 min parado e tocou: volta para a tela de senha');
  ok(/30 minutos sem usar/.test(await texto(ang, '#login-aviso')), 'a tela de senha explica: "ficou mais de 30 minutos sem usar"');
  ok(!(await temLogin(ang)) && amb.banco.b.log.filter((l) => l.evento === 'signOut').length > saidasAntes, 'o login foi encerrado (saiu do Supabase)');
  await ang.screenshot({ path: path.join(SHOTS, 'sessao-1-30min.png') });

  // sem tocar: o relógio confere sozinho (a cada 15 s)
  await entrar(ang, U['escritorio:equipe-angelica'].senha);
  ok(await ang.$eval('#login-aviso', (e) => e.classList.contains('hidden')), 'depois de entrar, o aviso some');
  await uso(ang, 31);
  await ang.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 20000 });
  ok(/30 minutos/.test(await texto(ang, '#login-aviso')), 'parado 30 min sem tocar: sai sozinho em até 15 s');

  // recarregar a página (mesma aba) não pede senha
  await entrar(ang, U['escritorio:equipe-angelica'].senha);
  await ang.reload();
  await ang.waitForSelector('#admin-view:not(.hidden)', { timeout: 15000 });
  ok(true, 'recarregar a página (o app continua aberto): não pede a senha');

  // outra aba com o app ainda aberto: entra junto
  const ang2 = await ctxA.newPage();
  await ang2.goto(amb.url + '/index.html');
  await ang2.waitForSelector('#admin-view:not(.hidden), #lock-login-form:not(.hidden)', { timeout: 15000 });
  ok(!(await naSenha(ang2)), 'abrir outra aba com o app aberto: entra direto');
  await ang2.close();

  // fechou o app e abriu de novo: pede a senha
  await ang.close();
  const ang3 = await ctxA.newPage();
  await ang3.goto(amb.url + '/index.html');
  await ang3.waitForSelector('#admin-view:not(.hidden), #lock-login-form:not(.hidden)', { timeout: 15000 });
  ok(await naSenha(ang3), 'fechou o app e abriu de novo: pede a senha');
  ok(/toda vez que é aberto/.test(await texto(ang3, '#login-aviso')) && !(await temLogin(ang3)), 'com o aviso "o app pede a senha toda vez que é aberto" e o login encerrado');
  await ang3.screenshot({ path: path.join(SHOTS, 'sessao-2-reaberto.png') });

  // módulos da fábrica: mesma regra
  console.log('3. Módulos da fábrica');
  const ctxN = await amb.contexto();
  const nic = await ctxN.newPage();
  await entrar(nic, U['mestre'].senha);
  await nic.goto(amb.url + '/modulos/manutencao.html');
  await nic.waitForTimeout(2500);
  ok(/modulos\/manutencao/.test(nic.url()) && !!(await nic.$('#lev-barra')), 'do app para o módulo (mesma aba): entra sem senha');
  await uso(nic, 31);
  await nic.click('#lev-barra .lb-mod').catch(() => nic.mouse.click(200, 400));
  await nic.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  ok(/index\.html/.test(nic.url()) && /30 minutos/.test(await texto(nic, '#login-aviso')), 'no módulo, 30 min parado: volta para a senha com o aviso');
  await nic.fill('#login-senha', U['mestre'].senha);
  await nic.click('#btn-login-submit');
  await nic.waitForURL(/modulos\/manutencao/, { timeout: 15000 });
  ok(true, 'depois da senha, volta para o módulo onde estava');
  await nic.waitForTimeout(1500);
  await nic.close();
  const nic2 = await ctxN.newPage();
  await nic2.goto(amb.url + '/modulos/manutencao.html');
  await nic2.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  ok(/toda vez que é aberto/.test(await texto(nic2, '#login-aviso')), 'módulo aberto direto depois de fechar o app: pede a senha');

  const erros = amb.erros.filter((e) => !/sem storage no teste/.test(e));
  ok(erros.length === 0, 'sem erros de JavaScript nas páginas' + (erros.length ? ': ' + erros.slice(0, 5).join(' | ') : ''));
  await amb.fechar();
  console.log('\n' + passou + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error('ERRO NO TESTE', e); process.exit(2); });
