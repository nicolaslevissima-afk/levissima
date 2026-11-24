/* LEVÍSSIMA · teste do leitor do app (ZXing) com a biblioteca de verdade (roda no GitHub Actions, que tem internet).
 * Gera os códigos dos produtos (DUN-14 em ITF-14 e EAN-13) com o bwip-js e lê do jeito que o app lê na câmera:
 * tons de cinza (77/150/29), RGBLuminanceSource, HybridBinarizer, MultiFormatReader com os mesmos formatos e dicas.
 * Rodar: npm i --no-save @zxing/library@0.20.0 bwip-js@4 pngjs@7 && node testes/leitor-zxing.js
 */
'use strict';
const Z = require('@zxing/library');
const bwip = require('bwip-js');
const { PNG } = require('pngjs');
let ok = 0, falhou = 0;
function conf(c, m) { if (c) { ok++; console.log('  ✓ ' + m); } else { falhou++; console.log('  ✗ FALHOU: ' + m); } }
const F = Z.BarcodeFormat, H = Z.DecodeHintType, dicas = new Map();
dicas.set(H.POSSIBLE_FORMATS, [F.ITF, F.EAN_13, F.EAN_8, F.UPC_A, F.UPC_E, F.CODE_128]);
dicas.set(H.TRY_HARDER, true);
dicas.set(H.ALLOWED_LENGTHS, [14]);
const leitor = new Z.MultiFormatReader();
leitor.setHints(dicas);
function ler(png, margem) {
  // como a câmera: o código no meio de uma imagem maior, com margem branca
  const W = png.width + 2 * margem, Hh = png.height + 2 * margem, lum = new Uint8ClampedArray(W * Hh).fill(255);
  for (let y = 0; y < png.height; y++) for (let x = 0; x < png.width; x++) {
    const i = (y * png.width + x) * 4, px = png.data;
    lum[(y + margem) * W + x + margem] = (px[i] * 77 + px[i + 1] * 150 + px[i + 2] * 29) >> 8;
  }
  try { const r = leitor.decodeWithState(new Z.BinaryBitmap(new Z.HybridBinarizer(new Z.RGBLuminanceSource(lum, W, Hh)))); return r ? r.getText() : null; }
  catch (e) { return 'ERRO ' + (e && (e.name || e.constructor.name)) + ' ' + (e && e.message); }
  finally { try { leitor.reset(); } catch (e) {} }
}
(async () => {
  conf(typeof Z.MultiFormatReader === 'function' && typeof Z.RGBLuminanceSource === 'function' && typeof Z.HybridBinarizer === 'function' && typeof Z.BinaryBitmap === 'function', 'a biblioteca tem as peças que o app usa');
  const casos = [['itf14', '1789734510511', '17897345105114'], ['ean13', '789734510511', '7897345105117'], ['itf14', '1789870130821', '17898701308217']];
  for (const [bcid, texto, esperado] of casos) {
    for (const escala of [2, 3]) {
      const buf = await bwip.toBuffer({ bcid, text: texto, scale: escala, height: 12, includetext: false, backgroundcolor: 'FFFFFF' });
      const png = PNG.sync.read(buf);
      const lido = ler(png, 40);
      conf(lido === esperado, bcid + ' ' + esperado + ' (escala ' + escala + ', ' + png.width + '×' + png.height + '): ' + lido);
    }
  }
  console.log('\n' + ok + ' ok, ' + falhou + ' falhas');
  process.exit(falhou ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
