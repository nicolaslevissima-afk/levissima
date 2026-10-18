// LEVÍSSIMA · verificação de passkeys (WebAuthn): entrar com o rosto (Face ID no iPhone, biometria do computador).
// Sem bibliotecas: só WebCrypto, que existe igual no Deno (função do Supabase) e no Node (testes).
// O aparelho confere o rosto e assina um desafio com uma chave que nunca sai dele; aqui conferimos a assinatura
// com a chave pública guardada no cadastro. Nenhuma foto do rosto passa pelo app.
//
// Aceita chaves ES256 (iPhone, Mac, Android), RS256 (Windows Hello) e Ed25519. Exige "presença" e "verificação"
// do usuário (rosto, digital ou senha do aparelho) em todo cadastro e entrada.

const te = new TextEncoder(), td = new TextDecoder();

export function b64urlEnc(bytes) {
  const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let s = '';
  for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
export function b64urlDec(str) {
  const s = String(str == null ? '' : str).replace(/-/g, '+').replace(/_/g, '/');
  if (!/^[A-Za-z0-9+/]*$/.test(s)) throw erroW('formato');
  const bin = atob(s + '==='.slice((s.length + 3) % 4));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
export function desafioNovo() { return b64urlEnc(crypto.getRandomValues(new Uint8Array(32))); }

function erroW(codigo) { const e = new Error('webauthn: ' + codigo); e.codigo = codigo; return e; }
function iguais(a, b) {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}
async function sha256(bytes) { return new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)); }
function juntar(a, b) { const o = new Uint8Array(a.length + b.length); o.set(a, 0); o.set(b, a.length); return o; }

// CBOR (RFC 8949), só o necessário para o objeto de atestação e a chave COSE. Devolve { valor, fim }.
export function cborDecode(bytes) {
  const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
  let p = 0;
  function precisa(n) { if (p + n > b.length) throw erroW('cbor'); }
  function tamanho(ai) {
    if (ai < 24) return ai;
    if (ai === 24) { precisa(1); return b[p++]; }
    if (ai === 25) { precisa(2); const v = dv.getUint16(p); p += 2; return v; }
    if (ai === 26) { precisa(4); const v = dv.getUint32(p); p += 4; return v; }
    if (ai === 27) { precisa(8); const hi = dv.getUint32(p), lo = dv.getUint32(p + 4); p += 8; if (hi > 0x1fffff) throw erroW('cbor'); return hi * 4294967296 + lo; }
    throw erroW('cbor'); // tamanho indefinido não é usado em WebAuthn
  }
  function item(nivel) {
    if (nivel > 16) throw erroW('cbor');
    precisa(1);
    const ib = b[p++], mt = ib >> 5, ai = ib & 31;
    if (mt === 0) return tamanho(ai);
    if (mt === 1) return -1 - tamanho(ai);
    if (mt === 2) { const n = tamanho(ai); precisa(n); const v = b.slice(p, p + n); p += n; return v; }
    if (mt === 3) { const n = tamanho(ai); precisa(n); const v = td.decode(b.subarray(p, p + n)); p += n; return v; }
    if (mt === 4) { const n = tamanho(ai); if (n > 1024) throw erroW('cbor'); const a = []; for (let i = 0; i < n; i++) a.push(item(nivel + 1)); return a; }
    if (mt === 5) { const n = tamanho(ai); if (n > 1024) throw erroW('cbor'); const m = new Map(); for (let i = 0; i < n; i++) { const k = item(nivel + 1); m.set(k, item(nivel + 1)); } return m; }
    if (mt === 6) { tamanho(ai); return item(nivel + 1); } // etiqueta: ignora
    if (mt === 7) {
      if (ai === 20) return false;
      if (ai === 21) return true;
      if (ai === 22 || ai === 23) return null;
      if (ai === 26) { precisa(4); const v = dv.getFloat32(p); p += 4; return v; }
      if (ai === 27) { precisa(8); const v = dv.getFloat64(p); p += 8; return v; }
    }
    throw erroW('cbor');
  }
  const valor = item(0);
  return { valor, fim: p };
}

// authenticatorData: hash do RP, sinais (presença, verificação, credencial nova), contador e a credencial nova
export function lerAuthData(ad) {
  if (!(ad instanceof Uint8Array) || ad.length < 37) throw erroW('authdata');
  const flags = ad[32];
  const r = {
    rpIdHash: ad.slice(0, 32), flags,
    up: !!(flags & 0x01), uv: !!(flags & 0x04), at: !!(flags & 0x40),
    contador: new DataView(ad.buffer, ad.byteOffset + 33, 4).getUint32(0),
  };
  if (r.at) {
    if (ad.length < 55) throw erroW('authdata');
    const n = (ad[53] << 8) | ad[54];
    if (n < 1 || n > 1023 || 55 + n > ad.length) throw erroW('authdata');
    r.credId = ad.slice(55, 55 + n);
    const resto = ad.subarray(55 + n);
    const { valor, fim } = cborDecode(resto);
    if (!(valor instanceof Map)) throw erroW('chave');
    r.chave = valor;
    r.chaveCose = resto.slice(0, fim);
  }
  return r;
}

// chave pública COSE → chave do WebCrypto
export async function importarChave(cose) {
  const m = cose instanceof Map ? cose : cborDecode(cose).valor;
  if (!(m instanceof Map)) throw erroW('chave');
  const kty = m.get(1), alg = m.get(3);
  if (kty === 2 && alg === -7 && m.get(-1) === 1) {
    const x = m.get(-2), y = m.get(-3);
    if (!(x instanceof Uint8Array) || !(y instanceof Uint8Array) || x.length !== 32 || y.length !== 32) throw erroW('chave');
    return { alg: -7, key: await crypto.subtle.importKey('jwk', { kty: 'EC', crv: 'P-256', x: b64urlEnc(x), y: b64urlEnc(y), ext: true }, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']) };
  }
  if (kty === 3 && alg === -257) {
    const n = m.get(-1), e = m.get(-2);
    if (!(n instanceof Uint8Array) || !(e instanceof Uint8Array) || n.length < 256) throw erroW('chave');
    return { alg: -257, key: await crypto.subtle.importKey('jwk', { kty: 'RSA', n: b64urlEnc(n), e: b64urlEnc(e), alg: 'RS256', ext: true }, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']) };
  }
  if (kty === 1 && alg === -8 && m.get(-1) === 6) {
    const x = m.get(-2);
    if (!(x instanceof Uint8Array) || x.length !== 32) throw erroW('chave');
    return { alg: -8, key: await crypto.subtle.importKey('jwk', { kty: 'OKP', crv: 'Ed25519', x: b64urlEnc(x), ext: true }, { name: 'Ed25519' }, false, ['verify']) };
  }
  throw erroW('chave_nao_suportada');
}

// assinatura ECDSA em DER (SEQUENCE { r, s }) → r||s com 32 bytes cada, como o WebCrypto espera
export function derParaRaw(der, n = 32) {
  let p = 0;
  const ler = () => { if (p >= der.length) throw erroW('assinatura'); return der[p++]; };
  if (ler() !== 0x30) throw erroW('assinatura');
  let len = ler();
  if (len & 0x80) { const k = len & 0x7f; if (k > 2) throw erroW('assinatura'); len = 0; for (let i = 0; i < k; i++) len = (len << 8) | ler(); }
  if (p + len !== der.length) throw erroW('assinatura');
  const inteiro = () => {
    if (ler() !== 0x02) throw erroW('assinatura');
    const l = ler();
    if (l < 1 || p + l > der.length) throw erroW('assinatura');
    let v = der.slice(p, p + l); p += l;
    while (v.length > n && v[0] === 0) v = v.slice(1);
    if (v.length > n) throw erroW('assinatura');
    const out = new Uint8Array(n); out.set(v, n - v.length); return out;
  };
  const r = inteiro(), s = inteiro();
  if (p !== der.length) throw erroW('assinatura');
  const raw = new Uint8Array(2 * n); raw.set(r, 0); raw.set(s, n);
  return raw;
}

function lerClientData(credencial, tipo, desafio, origens) {
  const cdj = b64urlDec(credencial.response.clientDataJSON);
  let cd;
  try { cd = JSON.parse(td.decode(cdj)); } catch { throw erroW('formato'); }
  if (!cd || cd.type !== tipo) throw erroW('tipo');
  if (typeof cd.challenge !== 'string' || cd.challenge !== desafio) throw erroW('desafio');
  if (!origens.includes(cd.origin)) throw erroW('origem');
  if (cd.crossOrigin === true) throw erroW('origem');
  return cdj;
}
// o desafio que o navegador assinou (para achar o pedido de entrada sem saber de quem é)
export function desafioDaCredencial(credencial) {
  try { return String(JSON.parse(td.decode(b64urlDec(credencial.response.clientDataJSON))).challenge || ''); } catch { return ''; }
}
function conferirFormato(credencial) {
  if (!credencial || typeof credencial !== 'object' || credencial.type !== 'public-key' || !credencial.response || typeof credencial.response !== 'object') throw erroW('formato');
}

// Cadastro: devolve o que guardar (id da credencial, chave pública COSE, algoritmo, contador)
export async function verificarRegistro({ credencial, desafio, origens, rpId }) {
  conferirFormato(credencial);
  lerClientData(credencial, 'webauthn.create', desafio, origens);
  const att = cborDecode(b64urlDec(credencial.response.attestationObject)).valor;
  if (!(att instanceof Map) || !(att.get('authData') instanceof Uint8Array)) throw erroW('formato');
  const a = lerAuthData(att.get('authData'));
  if (!iguais(a.rpIdHash, await sha256(te.encode(rpId)))) throw erroW('rp');
  if (!a.up || !a.uv) throw erroW('verificacao');
  if (!a.at || !a.credId) throw erroW('credencial');
  if (!iguais(b64urlDec(credencial.rawId || credencial.id), a.credId)) throw erroW('credencial');
  const k = await importarChave(a.chave);
  const tr = Array.isArray(credencial.response.transports) ? credencial.response.transports.filter((x) => typeof x === 'string').slice(0, 6) : [];
  return { credId: b64urlEnc(a.credId), chave: b64urlEnc(a.chaveCose), alg: k.alg, contador: a.contador, transportes: tr };
}

// Entrada: confere a assinatura com a chave do cadastro. Devolve o contador novo.
export async function verificarEntrada({ credencial, desafio, origens, rpId, chave, contador }) {
  conferirFormato(credencial);
  const cdj = lerClientData(credencial, 'webauthn.get', desafio, origens);
  const ad = b64urlDec(credencial.response.authenticatorData);
  const a = lerAuthData(ad);
  if (!iguais(a.rpIdHash, await sha256(te.encode(rpId)))) throw erroW('rp');
  if (!a.up || !a.uv) throw erroW('verificacao');
  const k = await importarChave(b64urlDec(chave));
  const dados = juntar(ad, await sha256(cdj));
  const sig = b64urlDec(credencial.response.signature);
  let ok = false;
  if (k.alg === -7) ok = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, k.key, derParaRaw(sig), dados);
  else if (k.alg === -257) ok = await crypto.subtle.verify({ name: 'RSASSA-PKCS1-v1_5' }, k.key, sig, dados);
  else ok = await crypto.subtle.verify({ name: 'Ed25519' }, k.key, sig, dados);
  if (!ok) throw erroW('assinatura');
  const antes = Number(contador) || 0;
  if ((a.contador > 0 || antes > 0) && a.contador <= antes) throw erroW('contador'); // possível cópia da chave
  return { contador: a.contador };
}
