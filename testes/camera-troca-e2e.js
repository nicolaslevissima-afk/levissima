/* LEVÍSSIMA · teste: câmera da conferência — escolha da câmera de trás e diagnóstico (24/11/2026).
 * Celular com duas câmeras de trás (Samsung: "camera2 2" grande-angular e "camera2 0" principal): o app prefere a
 * principal, guarda a escolha e mostra "Trocar câmera". O diagnóstico aparece embaixo da imagem e vai para o banco
 * (coleção diag-camera) quando a câmera desliga.
 * Rodar: python3 ferramentas/construir.py && node testes/camera-troca-e2e.js
 */
'use strict';
const { criar } = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }
(async () => {
  const amb = await criar();
  const b = amb.banco.b;
  const hoje = new Date(Date.now() - 3 * 3600e3).toISOString().slice(0, 10);
  doc(b, 'produtos', 'p510', { nome: 'Água 510ml natural', unidade: 'fardos', unidadesPorPalete: 150, codigosBarras: ['7897345105117', '17897345105114'], ordem: 1 });
  doc(b, 'motoristas', 'm1', { nome: 'Motorista Teste' });
  doc(b, 'cargas', 'c1', { status: 'aberta', motorista: 'Motorista Teste', data: hoje, hora: '06:00', numeroPager: '3',
    clientes: [{ cliente: 'Mercado', destino: 'Campinas', itens: [{ produtoId: 'p510', produtoNome: 'Água 510ml natural', quantidade: 300, unidade: 'fardos', paletes: 2, chapatex: 2 }] }],
    totalPaletes: 2, totalChapatex: 2, criadoEm: new Date().toISOString() });
  const ctx = await amb.contexto({ viewport: { width: 420, height: 900 }, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' });
  await ctx.addInitScript(() => {
    const cv = document.createElement('canvas'); cv.width = 640; cv.height = 480; const g = cv.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, 640, 480);
    window.__pedidos = [];
    navigator.mediaDevices.getUserMedia = (c) => { window.__pedidos.push(JSON.stringify(c.video)); setInterval(() => g.fillRect(0, 0, 1, 1), 100); return Promise.resolve(cv.captureStream(10)); };
    navigator.mediaDevices.enumerateDevices = () => Promise.resolve([
      { kind: 'videoinput', deviceId: 'dev-2', label: 'camera2 2, facing back' },
      { kind: 'videoinput', deviceId: 'dev-1', label: 'camera2 1, facing front' },
      { kind: 'videoinput', deviceId: 'dev-0', label: 'camera2 0, facing back' }]);
    window.BarcodeDetector = class { static getSupportedFormats() { return Promise.resolve(['ean_13', 'itf', 'qr_code']); } detect() { const v = window.__fila && window.__fila.shift(); return Promise.resolve(v ? [{ rawValue: v }] : []); } };
    window.__fila = [];
    window.ZXing = { BarcodeFormat: {}, DecodeHintType: {}, MultiFormatReader: class { setHints() {} decodeWithState() { throw new Error('NotFoundException'); } reset() {} }, RGBLuminanceSource: class {}, HybridBinarizer: class {}, BinaryBitmap: class {} };
  });
  const pag = await ctx.newPage();
  const erros = []; pag.on('pageerror', (e) => erros.push(String(e)));
  await pag.goto(amb.url + '/index.html');
  await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  await pag.fill('#login-senha', 'teste-nicolas'); await pag.click('#btn-login-submit');
  await pag.waitForTimeout(1800);
  await pag.click('#admin-tabs [data-tab="cargas"]'); await pag.waitForTimeout(600);
  await pag.evaluate(() => document.querySelector('[data-action="conf-barras"][data-id="c1"]').click());
  await pag.waitForSelector('#conf-overlay:not(.hidden)');
  await pag.click('#btn-conf-camera'); await pag.waitForTimeout(1500);
  const ped = await pag.evaluate(() => window.__pedidos);
  conf(ped.length === 2 && /environment/.test(ped[0]) && /"exact":"dev-0"/.test(ped[1]), 'começa pela câmera de trás padrão e troca sozinha para a principal (camera2 0): ' + ped.join(' | '));
  conf(await pag.evaluate(() => { try { return localStorage.getItem('levissima-cam-conferencia'); } catch (e) { return ''; } }) === 'dev-0', 'guarda a câmera escolhida neste aparelho');
  conf(/Trocar câmera \(\d de 2\)/.test(await pag.textContent('#btn-conf-trocar')) && await pag.isVisible('#btn-conf-trocar'), 'botão "Trocar câmera" com as duas câmeras de trás: ' + (await pag.textContent('#btn-conf-trocar')));
  await pag.evaluate(() => { window.__fila = ['7897345105118', '7897345105117']; });
  await pag.waitForTimeout(1500);
  const diag = await pag.textContent('#conf-cam-diag');
  conf(await pag.isVisible('#conf-cam-diag') && /leitor do aparelho/.test(diag) && /2 códigos vistos/.test(diag) && /último: 7897345105117 \(ok\)/.test(diag), 'diagnóstico na tela: ' + diag);
  await pag.click('#btn-conf-trocar'); await pag.waitForTimeout(800);
  const ped2 = await pag.evaluate(() => window.__pedidos);
  conf(/"exact":"dev-2"/.test(ped2[ped2.length - 1]), 'Trocar câmera passa para a outra de trás (dev-2)');
  await pag.click('#btn-conf-camera'); await pag.waitForTimeout(600);
  const diags = Array.from(b.docs.values()).filter((r) => r.colecao === 'diag-camera').map((r) => r.data);
  const d0 = diags.find((d) => d.vistos >= 2) || {};
  conf(diags.length >= 1 && d0.motor !== undefined && d0.aceitos === 1 && d0.incompletas === 1 && d0.camera !== undefined && d0.carga === 'c1' && d0.formatos.indexOf('itf') >= 0 && d0.quadros > 0, 'diagnóstico gravado no banco ao desligar: ' + JSON.stringify({ n: diags.length, aceitos: d0.aceitos, incompletas: d0.incompletas, quadros: d0.quadros, formatos: d0.formatos }));
  conf(!erros.length, 'sem erros de JavaScript' + (erros.length ? ': ' + erros.join(' | ') : ''));
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
