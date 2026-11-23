/* LEVÍSSIMA · teste: leitura do código de barras pela câmera na conferência do carregamento (23/11/2026).
 * Sem câmera de verdade: a câmera é uma imagem de teste e os leitores são simulados, para conferir o caminho:
 *  · navegador: BarcodeDetector que não lê EAN/ITF → usa o leitor do app (ZXing) com os formatos e o tamanho do DUN-14;
 *    leitura pela metade (dígito verificador errado) é descartada;
 *  · app Android: leitor do Google (função "Leitor"): lê, registra e abre de novo; "Voltar" encerra; código da etiqueta
 *    GS1 do palete vira o código do produto; código desconhecido para a leitura; se o leitor não abre, usa a câmera do app.
 * Rodar: python3 ferramentas/construir.py && node testes/camera-leitor-e2e.js
 */
'use strict';
const { criar } = require('./banco-fake');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
function doc(b, col, id, data) { b.docs.set(col + '/' + id, { colecao: col, id, data }); }
function gtinOk(s) { let soma = 0; for (let i = s.length - 2, k = 0; i >= 0; i--, k++) soma += Number(s[i]) * (k % 2 === 0 ? 3 : 1); return (10 - soma % 10) % 10 === Number(s[s.length - 1]); }
const DUN = '17897345105114', EAN = '7897345105117';

(async () => {
  conf(gtinOk(DUN) && gtinOk(EAN) && !gtinOk('17897345105115'), 'códigos de teste com dígito verificador certo');
  const amb = await criar();
  const b = amb.banco.b;
  const hoje = new Date(Date.now() - 3 * 3600e3).toISOString().slice(0, 10);
  doc(b, 'produtos', 'p510', { nome: 'Água 510ml natural', unidade: 'fardos', unidadesPorPalete: 150, codigosBarras: [EAN, DUN], ordem: 1 });
  doc(b, 'motoristas', 'm1', { nome: 'Motorista Teste' });
  for (const id of ['cWEB', 'cNAT', 'cFALHA']) {
    doc(b, 'cargas', id, { status: 'pendente', motorista: 'Motorista Teste', data: hoje, hora: '07:00',
      clientes: [{ cliente: 'Mercado Exemplo', destino: 'Campinas', itens: [{ produtoId: 'p510', produtoNome: 'Água 510ml natural', quantidade: 450, unidade: 'fardos', paletes: 3, chapatex: 3 }] }],
      totalPaletes: 3, totalChapatex: 3, numeroPager: id === 'cWEB' ? '1' : id === 'cNAT' ? '2' : '3', criadoEm: new Date().toISOString() });
  }
  const ctx = await amb.contexto({ viewport: { width: 1200, height: 900 }, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' });
  await ctx.addInitScript(() => {
    // câmera de teste: uma imagem desenhada
    const cv = document.createElement('canvas'); cv.width = 640; cv.height = 480;
    const g = cv.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, 640, 480); g.fillStyle = '#000';
    for (let x = 100; x < 540; x += 7) g.fillRect(x, 200, 3, 80);
    window.__camAberta = 0;
    navigator.mediaDevices.getUserMedia = () => { window.__camAberta++; setInterval(() => g.fillRect(0, 0, 1, 1), 100); return Promise.resolve(cv.captureStream(10)); };
    // leitor do aparelho que existe mas não lê os códigos dos produtos (o caso do celular do Jean)
    window.BarcodeDetector = class { constructor() { window.__bdCriado = true; } static getSupportedFormats() { return Promise.resolve([]); } detect() { return Promise.resolve([]); } };
    // leitor do app (ZXing) simulado: primeiro uma leitura pela metade, depois o DUN-14, depois uma etiqueta GS1
    window.__zxFila = [];
    window.ZXing = {
      BarcodeFormat: { ITF: 'ITF', EAN_13: 'EAN_13', EAN_8: 'EAN_8', UPC_A: 'UPC_A', UPC_E: 'UPC_E', CODE_128: 'CODE_128' },
      DecodeHintType: { POSSIBLE_FORMATS: 'POSSIBLE_FORMATS', TRY_HARDER: 'TRY_HARDER', ALLOWED_LENGTHS: 'ALLOWED_LENGTHS' },
      MultiFormatReader: class {
        setHints(h) { window.__dicas = Array.from(h.entries()); }
        decodeWithState(bmp) { window.__zxChamadas = (window.__zxChamadas || 0) + 1; window.__zxTam = bmp.w + 'x' + bmp.h; const v = window.__zxFila.shift(); if (!v) throw new Error('NotFoundException'); return { getText: () => v }; }
        reset() {}
      },
      RGBLuminanceSource: class { constructor(l, w, h) { this.w = w; this.h = h; this.ok = l.length === w * h; } },
      HybridBinarizer: class { constructor(s) { this.s = s; } },
      BinaryBitmap: class { constructor(bz) { this.w = bz.s.w; this.h = bz.s.h; } }
    };
  });
  const pag = await ctx.newPage();
  const erros = []; pag.on('pageerror', (e) => erros.push(String(e)));
  await pag.goto(amb.url + '/index.html');
  await pag.waitForSelector('#lock-login-form:not(.hidden)', { timeout: 15000 });
  await pag.fill('#login-senha', 'teste-nicolas');
  await pag.click('#btn-login-submit');
  await pag.waitForTimeout(1800);
  await pag.click('#admin-tabs [data-tab="cargas"]');
  await pag.waitForTimeout(600);
  async function abrir(id) {
    await pag.evaluate((id) => document.querySelector('[data-action="conf-barras"][data-id="' + id + '"]').click(), id);
    await pag.waitForSelector('#conf-overlay:not(.hidden)');
  }
  const status = () => pag.textContent('#conf-cam-status');
  const tabela = () => pag.evaluate(() => document.getElementById('conf-tabela').textContent.replace(/\s+/g, ' '));

  // ---------- navegador ----------
  await abrir('cWEB');
  await pag.evaluate(() => { window.__zxFila = ['17897345105115', '', '', '', '17897345105114']; });
  await pag.click('#btn-conf-camera');
  await pag.waitForTimeout(3500);
  conf(await pag.isVisible('#conf-camera') && /Câmera ligada/.test(await status()) && (await pag.textContent('#btn-conf-camera')) === 'Desligar câmera', 'câmera do app ligada (' + (await status()) + ')');
  const dicas = await pag.evaluate(() => window.__dicas || []);
  const mapa = Object.fromEntries(dicas);
  conf(mapa.POSSIBLE_FORMATS && mapa.POSSIBLE_FORMATS.includes('ITF') && mapa.POSSIBLE_FORMATS.includes('EAN_13') && mapa.TRY_HARDER === true && JSON.stringify(mapa.ALLOWED_LENGTHS) === '[14]',
    'aparelho sem EAN/ITF: usa o leitor do app com ITF (DUN-14) e EAN-13: ' + JSON.stringify(mapa));
  const zx = await pag.evaluate(() => ({ n: window.__zxChamadas || 0, tam: window.__zxTam }));
  conf(zx.n >= 3 && /^\d+x\d+$/.test(zx.tam || ''), 'lê a faixa do meio da imagem (' + zx.n + ' tentativas, ' + zx.tam + ')');
  let t = await tabela();
  conf(/1/.test(t) && await pag.evaluate(() => /palete 1 de 3/.test(document.getElementById('conf-aviso').textContent)), 'DUN-14 lido conta 1 palete (a leitura pela metade foi descartada): ' + (await pag.textContent('#conf-aviso')).trim());
  // etiqueta GS1 do palete: (02) + DUN-14 + lote
  await pag.waitForTimeout(1700); // a pausa de 1,6 s entre um palete e outro
  await pag.evaluate(() => { window.__zxFila = ['0217897345105114\u001d10L2311']; });
  await pag.waitForTimeout(2200);
  conf(await pag.evaluate(() => /palete 2 de 3/.test(document.getElementById('conf-aviso').textContent)), 'etiqueta GS1 (02…) vira o código do produto: ' + (await pag.textContent('#conf-aviso')).trim());
  await pag.click('#btn-conf-camera');
  await pag.waitForTimeout(300);
  conf(!(await pag.isVisible('#conf-camera')) && (await pag.textContent('#btn-conf-camera')) === 'Ligar câmera', 'desligar a câmera fecha a imagem');
  await pag.click('#btn-close-conf');
  await pag.waitForTimeout(300);

  // ---------- app Android: leitor do Google ----------
  await pag.evaluate((args) => {
    const fila = [{ valor: args.DUN }, { valor: '17897345105115' }, { valor: '(02)' + args.DUN + '(37)150' }, { erro: { code: 'CANCELADO', message: 'Leitura cancelada.' } }];
    window.__lerChamadas = 0;
    window.Capacitor = { isNativePlatform: () => true, getPlatform: () => 'android', isPluginAvailable: (n) => n === 'Leitor',
      Plugins: { Leitor: { ler: () => { window.__lerChamadas++; const x = window.__filaNat.shift() || { erro: { code: 'CANCELADO' } }; return x.erro ? Promise.reject(x.erro) : Promise.resolve(x); } } } };
    window.__filaNat = fila;
  }, { DUN });
  const camAntes = await pag.evaluate(() => window.__camAberta);
  await abrir('cNAT');
  await pag.click('#btn-conf-camera');
  await pag.waitForTimeout(4200);
  const nat = await pag.evaluate(() => ({ n: window.__lerChamadas, cam: window.__camAberta }));
  conf(nat.n === 4 && nat.cam === camAntes, 'abre o leitor do Google de novo depois de cada leitura até "Voltar" (' + nat.n + ' vezes), sem a câmera do app');
  conf(await pag.evaluate(() => /palete 2 de 3/.test(document.getElementById('conf-aviso').textContent)), '2 paletes lidos (a leitura pela metade não conta): ' + (await pag.textContent('#conf-aviso')).trim());
  conf(/Leitor encerrado/.test(await status()) && (await pag.textContent('#btn-conf-camera')) === 'Ligar câmera', '"Voltar" encerra o leitor (' + (await status()) + ')');
  // código que não é de nenhum produto: para o leitor para a pessoa decidir
  await pag.evaluate(() => { window.__lerChamadas = 0; window.__filaNat = [{ valor: '7891234567895' }, { valor: '17897345105114' }]; });
  await pag.click('#btn-conf-camera');
  await pag.waitForTimeout(2500);
  conf(await pag.evaluate(() => window.__lerChamadas) === 1 && /não cadastrado/i.test(await status()), 'código desconhecido para o leitor (' + (await status()) + ')');
  await pag.click('#btn-close-conf');
  await pag.waitForTimeout(300);

  // ---------- leitor do Google não abre: usa a câmera do app ----------
  await pag.evaluate(() => { window.__lerChamadas = 0; window.__filaNat = [{ erro: { code: 'FALHA', message: 'Google Play Services indisponível' } }]; window.__zxFila = []; });
  await abrir('cFALHA');
  await pag.click('#btn-conf-camera');
  await pag.waitForTimeout(2500);
  conf(await pag.isVisible('#conf-camera') && (await pag.evaluate(() => window.__camAberta)) > camAntes, 'sem o leitor do Google, liga a câmera dentro do app');
  await pag.click('#btn-close-conf');
  await pag.waitForTimeout(300);
  // e não tenta mais o leitor do Google neste aparelho (até abrir o app de novo)
  await abrir('cFALHA');
  await pag.click('#btn-conf-camera');
  await pag.waitForTimeout(800);
  conf(await pag.evaluate(() => window.__lerChamadas) === 1 && await pag.isVisible('#conf-camera'), 'depois da falha, vai direto para a câmera do app');
  await pag.click('#btn-close-conf');

  conf(!erros.length, 'sem erros de JavaScript' + (erros.length ? ': ' + erros.join(' | ') : ''));
  await amb.fechar();
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
