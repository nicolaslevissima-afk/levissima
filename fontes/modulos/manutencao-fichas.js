/* =====================================================================
   Fichas de manutenção preventiva em planilha (pedido de 20/10/2026)
   Modelo de referência: a ficha da Enchedora da Linha 1 —
   - cabeçalho com LINHA, EQUIPAMENTO, FABRICANTE, MODELO, APROVADO, VERIFICADO e Nº CONTROLE;
   - tabela Nº · ITEM · FREQUÊNCIA · MÉTODO com uma coluna por mês (data no topo) e "NA" onde o item não se aplica;
   - legenda O = Normal, X = Anormal, NA = Não aplicável;
   - aba "Lista" com o que usar em cada item (descrição, fornecedor e quantidade).
   Cada item da ficha vira (ou atualiza) uma tarefa do plano de Preventiva do equipamento. A tela "Fichas de
   preventiva" mostra a ficha como no papel: os meses, NA, O/X das execuções, o que está atrasado e o próximo.
   Este trecho é inserido no programa original pelo montar.py (antes da inicialização).
   ===================================================================== */
const FI_MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
const FI = { st: null, m: null };

(function fiEstilo() {
  const s = document.createElement('style');
  s.textContent = ''
    + '.fi-grid{border-collapse:separate;border-spacing:0;font-size:13px;width:100%}'
    + '.fi-grid th,.fi-grid td{border-bottom:1px solid var(--line);padding:6px 5px;text-align:center;white-space:nowrap;background:var(--surface);vertical-align:middle}'
    + '.fi-grid th{background:var(--surface-2);font-size:11.5px;color:var(--ink-2);font-weight:700;letter-spacing:.02em}'
    + '.fi-grid th.fi-hoje{color:var(--ink);box-shadow:inset 0 -3px 0 var(--warn)}'
    + '.fi-grid tr:last-child td{border-bottom:0}'
    + '.fi-grid .fi-it{text-align:left;white-space:normal;min-width:150px;max-width:240px;position:sticky;left:0;z-index:1;box-shadow:1px 0 0 var(--line)}'
    + '.fi-grid th.fi-it{z-index:2}'
    + '.fi-grid .fi-n{color:var(--muted);font-family:var(--f-mono);width:26px}'
    + '.fi-it-t{display:block;font:inherit;font-weight:650;color:var(--ink);background:none;border:0;padding:0;text-align:left;cursor:pointer;line-height:1.3}'
    + 'button.fi-it-t:hover{text-decoration:underline}'
    + '.fi-it-s{display:block;font-size:11.5px;color:var(--muted);margin-top:2px;line-height:1.3}'
    + '.fi-c{display:inline-flex;align-items:center;justify-content:center;width:34px;height:30px;border-radius:7px;border:1px solid var(--line);background:var(--surface);font:inherit;font-weight:700;font-size:13px;color:var(--ink);padding:0}'
    + 'button.fi-c{cursor:pointer}'
    + '.fi-c.na{border-color:transparent;background:var(--sunken);color:var(--muted);font-weight:500;font-size:11px}'
    + '.fi-c.o{background:color-mix(in srgb,var(--ok) 15%,var(--surface));border-color:color-mix(in srgb,var(--ok) 60%,var(--surface));color:#0a6b0a}'
    + '.fi-c.x{background:color-mix(in srgb,var(--crit) 13%,var(--surface));border-color:var(--crit);color:var(--crit)}'
    + '.fi-c.atr{border:2px solid var(--crit);color:var(--crit)}'
    + '.fi-c.prox{border:2px solid var(--warn);color:#8a5a00}'
    + '.fi-c.sem{color:var(--muted);border-style:dashed;font-weight:500}'
    + '.fi-leg{display:flex;flex-wrap:wrap;gap:6px 14px;font-size:12.5px;color:var(--ink-2);margin:12px 0 8px}'
    + '.fi-leg span{display:inline-flex;align-items:center;gap:6px}'
    + '.fi-leg .fi-c{width:26px;height:22px;font-size:11px}'
    + '.fi-prev td,.fi-prev th{font-size:12.5px}'
    + '.fi-tag{display:inline-block;font-size:11.5px;font-weight:700;padding:1px 7px;border-radius:999px;border:1px solid var(--line);color:var(--ink-2);white-space:nowrap}'
    + '.fi-tag.nova{border-color:color-mix(in srgb,var(--ok) 55%,var(--surface));color:#0a6b0a}'
    + '.fi-tag.atu{border-color:color-mix(in srgb,var(--violet) 50%,var(--surface));color:var(--violet)}'
    + '.fi-tag.erro{border-color:var(--crit);color:var(--crit)}'
    + '.fi-card{border:1px solid var(--line);border-radius:var(--r-lg,14px);padding:12px;margin-top:12px;background:var(--surface)}'
    + '.fi-card h3{margin:0 0 4px;font-size:15px}';
  document.head.appendChild(s);
})();

/* ---------- Leitura da planilha ---------- */
function fiTexto(v) { return txtCel(v).replace(/\s+/g, ' ').trim(); }
function fiChave(s) { return norm(s).replace(/[^a-z0-9]+/g, ' ').trim(); }
function fiSemelhanca(a, b) {
  const A = new Set(fiChave(a).split(' ').filter(w => w.length > 2)), B = new Set(fiChave(b).split(' ').filter(w => w.length > 2));
  if (!A.size || !B.size) return 0;
  let i = 0; A.forEach(w => { if (B.has(w)) i++; });
  return i / Math.max(A.size, B.size);
}
function fiMesCurto(iso) { const d = parseISODate(iso); return d ? FI_MESES[d.getMonth()] + '/' + String(d.getFullYear()).slice(2) : '—'; }
function fiData(v, ctx) {
  const d = parseDataBR(v); if (d) return d;
  const s = norm(txtCel(v)).replace(/\s+/g, ' ').trim(); if (!s) return null;
  let m = /^(\d{1,2})[\/.\-](\d{4})$/.exec(s);
  if (m && +m[1] >= 1 && +m[1] <= 12) return m[2] + '-' + pad(+m[1]) + '-01';
  m = /^(jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)[a-z]*\.?[\s\/\-]*(\d{2}|\d{4})?$/.exec(s);
  if (!m) return null;
  const mes = FI_MESES.indexOf(m[1]);
  let ano = m[2] ? +m[2] : null;
  if (ano != null && ano < 100) ano += 2000;
  if (ano == null && ctx) { if (ctx.ultMes != null && mes < ctx.ultMes) ctx.ano++; ctx.ultMes = mes; ano = ctx.ano; }
  return ano == null ? null : ano + '-' + pad(mes + 1) + '-01';
}
function fiMarca(v) {
  const s = norm(txtCel(v)).replace(/[\s.]/g, '');
  if (!s) return '';
  if (/^(na|n\/a|naoaplicavel|nao|-|—|–)$/.test(s)) return 'NA';
  if (/^(o|ok|0|normal|✓|✔)$/.test(s)) return 'O';
  if (/^(x|anormal)$/.test(s)) return 'X';
  return '?';
}
function fiRotulo(t) {
  const n = norm(t).trim();
  if (/^linha\b/.test(n)) return 'linha';
  if (/^equipamento\b/.test(n)) return 'equipamento';
  if (/^fabricante\b/.test(n)) return 'fabricante';
  if (/^modelo\b/.test(n)) return 'modelo';
  if (/^(n[^a-z0-9]{0,2}|no\.?\s|num(ero)?\.?\s)\s*(de\s+)?controle\b|^controle\b/.test(n)) return 'controle';
  if (/^aprovad/.test(n)) return 'aprovado';
  if (/^verificad/.test(n)) return 'verificado';
  if (/^legenda\b/.test(n)) return 'legenda';
  if (/^\d{4}(\s*(e|a|ate|-|\/)\s*\d{4})?$/.test(n)) return 'periodo';
  return '';
}
function fiDepoisDoRotulo(t) { const i = t.indexOf(':'); return i >= 0 ? t.slice(i + 1).trim() : ''; }
function fiAcharCab(rows) {
  for (let r = 0; r < Math.min(rows.length, 40); r++) {
    const cn = (rows[r] || []).map(normCab);
    const ci = cn.findIndex(h => /^(item|itens|atividade|tarefa|componente|descricao do item)$/.test(h));
    const cf = cn.findIndex(h => /^(frequencia|periodicidade|intervalo)/.test(h));
    if (ci >= 0 && cf >= 0) return { r, ci, cf, cn };
  }
  return null;
}
function fiLerCabecalho(rows, ate) {
  const o = { linhaTxt: '', equipamento: '', fabricante: '', modelo: '', controle: '', aprovado: '', verificado: '', legenda: '', periodo: '' };
  for (let r = 0; r < ate; r++) {
    const row = rows[r] || [];
    for (let c = 0; c < row.length; c++) {
      const t = fiTexto(row[c]); if (!t) continue;
      const k = fiRotulo(t); if (!k) continue;
      if (k === 'periodo') { if (!o.periodo) o.periodo = t; continue; }
      if (k === 'legenda') { o.legenda = fiDepoisDoRotulo(t).replace(/\s{2,}/g, ' · ') || t; continue; }
      let v = fiDepoisDoRotulo(t);
      if (!v && (k === 'controle' || k === 'aprovado' || k === 'verificado')) {
        const abaixo = fiTexto((rows[r + 1] || [])[c]);
        if (abaixo && !fiRotulo(abaixo)) v = abaixo;
      }
      if (!v && k !== 'aprovado' && k !== 'verificado') {
        for (let j = c + 1; j < Math.min(row.length, c + 6); j++) { const t2 = fiTexto(row[j]); if (!t2) continue; if (!fiRotulo(t2) && !/:\s*$/.test(t2)) v = t2; break; }
      }
      const campo = k === 'linha' ? 'linhaTxt' : k;
      if (v && !o[campo]) o[campo] = v;
    }
  }
  return o;
}
function fiLerLista(rows) {
  for (let r = 0; r < Math.min(rows.length, 15); r++) {
    const cn = (rows[r] || []).map(normCab);
    const ci = cn.findIndex(h => /^(item|n|no|numero|nr)$/.test(h));
    const cd = cn.findIndex(h => /^(descricao|material|materiais|componente|procedimento)/.test(h));
    if (ci < 0 || cd < 0) continue;
    const cf = cn.findIndex(h => /^fornecedor/.test(h)), cq = cn.findIndex(h => /^(quantidade|qtd|quant|qtde)/.test(h));
    const mapa = {};
    for (let k = r + 1; k < rows.length; k++) {
      const row = rows[k] || [], n = parseNumBR(row[ci]), desc = fiTexto(row[cd]);
      if (n == null || (!desc && !(cf >= 0 && fiTexto(row[cf])))) continue;
      const qn = cq >= 0 ? parseNumBR(row[cq]) : null, qt = cq >= 0 ? fiTexto(row[cq]) : '';
      mapa[n] = { descricao: desc, fornecedor: cf >= 0 ? fiTexto(row[cf]) : '', quantidade: qn != null && /^[\d.,\s]+$/.test(qt) ? qn : (qt || null) };
    }
    return mapa;
  }
  return null;
}
function fiInferirFreq(meses, marcas) {
  const prog = meses.filter((m, j) => marcas[j] !== 'NA');
  if (prog.length < 2) return null;
  const difs = [];
  for (let i = 1; i < prog.length; i++) difs.push(diffDays(prog[i - 1], prog[i]));
  const md = difs.sort((a, b) => a - b)[Math.floor(difs.length / 2)];
  const tab = [[7, 7], [15, 15], [30, 30], [61, 60], [91, 90], [122, 120], [183, 180], [365, 365]];
  for (const [lim, d] of tab) if (Math.abs(md - lim) <= Math.max(3, lim * 0.12)) return { tipo: 'dias', dias: d, inferida: true };
  return md > 0 ? { tipo: 'dias', dias: md, inferida: true } : null;
}
function fiLerAba(rows, nomeAba) {
  const cab = fiAcharCab(rows); if (!cab) return null;
  const head = fiLerCabecalho(rows, cab.r);
  const cN = cab.cn.findIndex(h => /^(n|no|num|numero|nr|item n)$/.test(h));
  const cM = cab.cn.findIndex(h => /^(metodo|tipo|acao|servico)/.test(h));
  const ini = Math.max(cab.ci, cab.cf, cM, cN) + 1;
  const anos = /(\d{4})/.exec(head.periodo || '');
  const ctx = { ano: anos ? +anos[1] : new Date().getFullYear(), ultMes: null };
  let meses = [];
  for (const rr of [cab.r, cab.r - 1, cab.r + 1]) {
    const row = rows[rr] || []; const achados = [];
    for (let c = ini; c < row.length; c++) { const d = fiData(row[c], ctx); if (d) achados.push({ c, d }); }
    if (achados.length >= 2) { meses = achados; if (rr === cab.r + 1) cab.r1 = cab.r + 1; break; }
  }
  const avisos = [];
  if (!meses.length) avisos.push('Não achei as datas dos meses no cabeçalho da tabela (aba ' + nomeAba + ').');
  const itens = [];
  let seq = 0;
  for (let r = (cab.r1 || cab.r) + 1; r < rows.length; r++) {
    const row = rows[r] || [];
    const titulo = fiTexto(row[cab.ci]);
    if (!titulo) continue;
    if (/^(responsavel|assinatura|observac|elaborado|aprovado|verificado|legenda)\b/.test(norm(titulo))) break;
    seq++;
    const n = cN >= 0 && parseNumBR(row[cN]) != null ? parseNumBR(row[cN]) : seq;
    const frequencia = fiTexto(row[cab.cf]);
    const marcas = meses.map(m => fiMarca(row[m.c]));
    const estranhas = meses.filter((m, j) => marcas[j] === '?').map(m => fiTexto(row[m.c]));
    if (estranhas.length) avisos.push('Item ' + n + ': marca "' + estranhas[0] + '" não reconhecida (use O, X ou NA) — ficou em branco.');
    const mk = marcas.map(x => x === '?' ? '' : x);
    let freq = parseFreq(frequencia);
    if (!freq) { freq = fiInferirFreq(meses.map(m => m.d), mk); if (freq) avisos.push('Item ' + n + ': frequência "' + (frequencia || 'em branco') + '" deduzida pelos meses da ficha (' + freqTexto({ freqTipo: 'dias', freqDias: freq.dias }) + ').'); }
    itens.push({ n, titulo, frequencia, freq, metodo: cM >= 0 ? fiTexto(row[cM]) : '', marcas: mk });
  }
  if (!itens.length) avisos.push('Nenhum item encontrado na aba ' + nomeAba + '.');
  return Object.assign(head, { aba: nomeAba, linha: parseLinha(head.linhaTxt), meses: meses.map(m => m.d), itens, avisos });
}
async function fiLerArquivo(file) {
  const X = await carregarXLSX();
  const wb = X.read(await file.arrayBuffer(), { type: 'array', cellDates: true });
  const fichas = [], listas = [];
  for (const nome of wb.SheetNames) {
    const rows = X.utils.sheet_to_json(wb.Sheets[nome], { header: 1, raw: true, defval: '' });
    const f = fiLerAba(rows, nome);
    if (f) { fichas.push(f); continue; }
    const l = fiLerLista(rows);
    if (l) listas.push({ nome, mapa: l });
  }
  fichas.forEach((f, i) => {
    let l = null;
    if (listas.length === 1 && fichas.length === 1) l = listas[0];
    else l = listas.find(x => fiChave(x.nome).includes(fiChave(f.aba)) || (f.equipamento && fiChave(x.nome).includes(fiChave(f.equipamento)))) || (listas.length === fichas.length ? listas[i] : null);
    f.lista = l ? l.nome : '';
    f.itens.forEach(it => { it.lista = l && l.mapa[it.n] ? l.mapa[it.n] : null; });
  });
  return { fichas, arquivo: file.name || 'planilha' };
}

/* ---------- Ligação com equipamentos e com o plano de Preventiva ---------- */
function fiAcharEquip(f) {
  const ix = Store.all('equipamentos');
  const e = acharEquip(ix, f.equipamento, f.linha);
  if (e) return e;
  const t = fiChave(f.equipamento); if (!t) return null;
  const cand = ix.filter(x => !f.linha || x.linha === f.linha);
  const porTipo = cand.filter(x => fiChave(x.tipo) === t); if (porTipo.length === 1) return porTipo[0];
  const cont = cand.filter(x => fiChave(x.nome + ' ' + (x.tipo || '')).includes(t)); if (cont.length === 1) return cont[0];
  return null;
}
function fiFichaExistente(dr) {
  const todas = Store.all('fichas');
  if (dr.controle) return todas.find(f => fiChave(f.controle) === fiChave(dr.controle)) || null;
  return todas.find(f => !f.controle && f.equipId === dr.equipId && fiChave(f.periodo) === fiChave(dr.periodo)) || null;
}
function fiCasar(dr) {
  const ex = dr.equipId && dr.equipId !== '__novo' ? fiFichaExistente(dr) : (dr.controle ? fiFichaExistente(dr) : null);
  dr.existente = ex ? ex.id : null;
  const usados = new Set();
  const atuais = dr.equipId && dr.equipId !== '__novo' ? Store.all('preventivas').filter(p => p.equipId === dr.equipId) : [];
  dr.itens.forEach(it => { it.alvo = null; });
  if (ex) dr.itens.forEach(it => {
    const ant = (ex.itens || []).find(x => x.n === it.n), p = ant && ant.prevId ? Store.get('preventivas', ant.prevId) : null;
    if (p && p.equipId === dr.equipId && !usados.has(p.id)) { it.alvo = p.id; usados.add(p.id); }
  });
  dr.itens.forEach(it => { if (it.alvo) return; const p = atuais.find(x => !usados.has(x.id) && fiChave(x.titulo) === fiChave(it.titulo)); if (p) { it.alvo = p.id; usados.add(p.id); } });
  dr.itens.forEach(it => {
    if (it.alvo) return;
    let best = null, bs = 0;
    for (const x of atuais) { if (usados.has(x.id)) continue; const sc = fiSemelhanca(x.titulo, it.titulo); if (sc > bs) { bs = sc; best = x; } }
    if (best && bs >= 0.6) { it.alvo = best.id; usados.add(best.id); }
  });
}
function fiMesesDeDias(d) { return { 30: 1, 60: 2, 90: 3, 120: 4, 180: 6, 365: 12, 730: 24 }[d] || null; }
function fiSomarMeses(iso, n) {
  const d = parseISODate(iso); if (!d) return null;
  const dia = d.getDate(); d.setDate(1); d.setMonth(d.getMonth() + n);
  d.setDate(Math.min(dia, new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate()));
  return toISODate(d);
}
function fiProximaProgramada(meses, marcas, fq) {
  const h = hoje();
  const prog = meses.filter((m, j) => marcas[j] !== 'NA');
  const fut = prog.find(m => m >= h); if (fut) return fut;
  if (!prog.length || !fq || fq.tipo !== 'dias' || !(fq.dias > 0)) return null;
  const mm = fiMesesDeDias(fq.dias);
  let d = prog[prog.length - 1];
  for (let i = 0; i < 400 && d < h; i++) d = mm ? fiSomarMeses(d, mm) : addDays(d, fq.dias);
  return d;
}
function fiExecsDaFicha(dr, it) {
  return dr.meses.map((m, j) => ({ m, k: it.marcas[j] })).filter(x => x.k === 'O' || x.k === 'X');
}
// marcas O/X da planilha que ainda não estão no app: a execução que já existe perto daquele mês (a mesma regra da
// grade) conta como a mesma; marca num mês que ainda não chegou vale com a data de hoje
function fiMarcasNovas(dr, it, p) {
  const fd = (it.freq && it.freq.tipo === 'dias' && it.freq.dias) || (p && p.freqDias) || 30;
  const tol = Math.max(10, Math.min(45, Math.round(fd / 2)));
  const ja = ((p && p.historico) || []).map(h => h.data).concat(p && p.ultimaData ? [p.ultimaData] : []).filter(x => parseISODate(x));
  const h0 = hoje();
  return fiExecsDaFicha(dr, it).filter(x => !ja.some(d => Math.abs(diffDays(d, x.m)) <= tol)).map(x => ({ m: x.m > h0 ? h0 : x.m, k: x.k }));
}
function fiMudancas(dr, it, p) {
  const out = [];
  const fq = it.freq;
  if (fq && fq.tipo === 'dias' && (p.freqTipo === 'horas' || p.freqDias !== fq.dias)) out.push('frequência: ' + freqTexto(p) + ' → ' + freqTexto({ freqTipo: 'dias', freqDias: fq.dias }));
  if (fq && fq.tipo === 'horas' && (p.freqTipo !== 'horas' || p.freqHoras !== fq.horas)) out.push('frequência: ' + freqTexto(p) + ' → a cada ' + fmtNum(fq.horas) + ' h');
  if (it.metodo && it.metodo !== (p.metodo || '')) out.push('método: ' + it.metodo);
  const l = it.lista || {};
  if (l.fornecedor && l.fornecedor !== (p.fornecedor || '')) out.push('fornecedor: ' + l.fornecedor);
  if (l.quantidade != null && String(l.quantidade) !== String(p.quantidade == null ? '' : p.quantidade)) out.push('quantidade: ' + l.quantidade);
  if (!p.descricao && l.descricao) out.push('instruções da Lista');
  const ex = fiMarcasNovas(dr, it, p);
  if (ex.length) out.push(ex.length + ' ' + plural(ex.length, 'execução marcada', 'execuções marcadas') + ' na ficha');
  return out;
}

/* ---------- Grade da ficha: NA, O/X das execuções, atrasado e próximo ---------- */
function fiCelulas(f, it, p) {
  const h = hoje();
  const meses = f.meses || [], marcas = it.marcas || [];
  const freqDias = (p && p.freqDias) || it.freqDias || 30;
  const tol = Math.max(10, Math.min(45, Math.round(freqDias / 2)));
  const execs = ((p && p.historico) || []).filter(x => x && parseISODate(x.data)).map(x => ({ data: x.data, res: x.resultado === 'X' ? 'x' : 'o', por: x.por || '', obs: x.obs || '' }));
  if (p && p.ultimaData && !execs.some(x => x.data === p.ultimaData)) execs.push({ data: p.ultimaData, res: 'o', por: '', obs: 'última execução informada no plano' });
  execs.sort((a, b) => String(a.data).localeCompare(String(b.data)));
  const cel = meses.map((m, j) => marcas[j] === 'NA' ? { e: 'na' } : { e: '' });
  for (const x of execs) {
    let bj = -1, bd = Infinity;
    meses.forEach((m, j) => { if (cel[j].e === 'na') return; const d = Math.abs(diffDays(m, x.data)); if (d < bd) { bd = d; bj = j; } });
    if (bj >= 0 && bd <= tol) cel[bj] = { e: x.res, x };
  }
  const ult = execs.length ? execs[execs.length - 1].data : '';
  let proxMarcada = false;
  meses.forEach((m, j) => {
    const c = cel[j]; if (c.e) return;
    if (m >= h) { if (!proxMarcada && p && p.ativo !== false) { c.e = 'prox'; proxMarcada = true; } else c.e = 'fut'; return; }
    if (!ult || m > ult) {
      // o mês passou e não há execução depois dele: atrasada (até 7 dias depois ainda conta como a próxima)
      if (diffDays(m, h) <= Math.min(7, tol) && !proxMarcada && p && p.ativo !== false) { c.e = 'prox'; proxMarcada = true; } else c.e = 'atr';
    } else c.e = 'sem';
  });
  return cel;
}
function fiResumo(f) {
  const mes = hoje().slice(0, 7);
  let atr = 0, noMes = 0, fora = 0;
  for (const it of f.itens || []) {
    const p = it.prevId ? Store.get('preventivas', it.prevId) : null;
    if (!p) { fora++; continue; }
    const cel = fiCelulas(f, it, p);
    cel.forEach((c, j) => { if (c.e === 'atr') atr++; if ((c.e === 'prox' || c.e === 'fut' || c.e === 'atr') && (f.meses[j] || '').slice(0, 7) === mes) noMes++; });
  }
  return { atr, noMes, fora };
}
function fiEqNome(f) { const e = eqDe(f.equipId); return e ? e.nome : (f.equipamento || 'Equipamento'); }
function fiCelHtml(c, mes, p, it) {
  const txt = { na: 'NA', o: 'O', x: 'X', atr: '!', prox: '•', fut: '', sem: '—' }[c.e];
  const quando = fmtData(mes);
  if (c.e === 'na') return '<span class="fi-c na" title="' + esc(quando + ': não aplicável') + '">NA</span>';
  if (c.e === 'o' || c.e === 'x') {
    const tit = quando + ': ' + (c.e === 'o' ? 'normal' : 'anormal') + ' — feito em ' + fmtData(c.x.data) + (c.x.por ? ' por ' + c.x.por : '') + (c.x.obs ? ' · ' + c.x.obs : '');
    return p ? '<button type="button" class="fi-c ' + c.e + '" data-act="plano" data-col="preventivas" data-id="' + p.id + '" title="' + esc(tit) + '">' + txt + '</button>' : '<span class="fi-c ' + c.e + '" title="' + esc(tit) + '">' + txt + '</span>';
  }
  const tit = quando + ': ' + ({ atr: 'atrasada (sem registro)', prox: 'próxima', fut: 'programada', sem: 'sem registro no app' }[c.e]);
  const podeReg = p && podeEscrever() && p.ativo !== false && mes <= addDays(hoje(), 31);
  if (podeReg) return '<button type="button" class="fi-c ' + c.e + '" data-act="pl-exec" data-col="preventivas" data-id="' + p.id + '" data-data="' + (mes < hoje() ? mes : hoje()) + '" title="' + esc(tit + ' — toque para registrar a execução') + '" aria-label="' + esc('Registrar ' + (it ? it.titulo : '') + ' de ' + quando) + '">' + txt + '</button>';
  return '<span class="fi-c ' + c.e + '" title="' + esc(tit) + '">' + txt + '</span>';
}
function fiGradeHtml(f) {
  const mesAtual = hoje().slice(0, 7);
  let h = '<div class="tbl-wrap"><table class="fi-grid"><thead><tr><th class="fi-n">Nº</th><th class="fi-it">Item · frequência · método</th>'
    + (f.meses || []).map(m => '<th title="' + esc(fmtData(m)) + '"' + (m.slice(0, 7) === mesAtual ? ' class="fi-hoje"' : '') + '>' + fiMesCurto(m) + '</th>').join('') + '</tr></thead><tbody>';
  for (const it of f.itens || []) {
    const p = it.prevId ? Store.get('preventivas', it.prevId) : null;
    const cel = fiCelulas(f, it, p);
    h += '<tr><td class="fi-n">' + esc(it.n) + '</td><td class="fi-it">'
      + (p ? '<button type="button" class="fi-it-t" data-act="plano" data-col="preventivas" data-id="' + p.id + '">' + esc(p.titulo || it.titulo) + '</button>' : '<span class="fi-it-t">' + esc(it.titulo) + '</span>')
      + '<span class="fi-it-s">' + esc([it.frequencia, it.metodo].filter(Boolean).join(' · ')) + (p ? (p.ativo === false ? ' · pausada' : '') : ' · <b style="color:var(--crit)">fora do plano</b>') + '</span></td>'
      + cel.map((c, j) => '<td>' + fiCelHtml(c, f.meses[j], p, it) + '</td>').join('') + '</tr>';
  }
  return h + '</tbody></table></div>';
}
function fiLegendaHtml() {
  return '<div class="fi-leg"><span><span class="fi-c o">O</span>Normal</span><span><span class="fi-c x">X</span>Anormal</span><span><span class="fi-c na">NA</span>Não aplicável</span>'
    + '<span><span class="fi-c prox">•</span>Próxima</span><span><span class="fi-c atr">!</span>Atrasada</span><span><span class="fi-c sem">—</span>Sem registro no app</span><span><span class="fi-c"></span>Programada</span></div>';
}
function fiListaHtml(f) {
  const its = (f.itens || []).filter(it => it.descricao || it.fornecedor || it.quantidade != null);
  if (!its.length) return '';
  return '<div class="blk"><h3>Componentes e materiais (aba Lista)</h3><div class="tbl-wrap"><table class="tbl"><thead><tr><th>Item</th><th>Descrição</th><th>Fornecedor</th><th>Qtd.</th></tr></thead><tbody>'
    + its.map(it => '<tr><td class="mono">' + esc(it.n) + '</td><td style="white-space:normal;min-width:220px">' + esc(it.descricao || '') + '</td><td>' + esc(it.fornecedor || '—') + '</td><td>' + esc(it.quantidade == null ? '—' : typeof it.quantidade === 'number' ? fmtNum(it.quantidade) : it.quantidade) + '</td></tr>').join('')
    + '</tbody></table></div></div>';
}

/* ---------- Tela: Fichas de preventiva ---------- */
VIEWS.fichas = {
  mount(el) {
    this.el = el; this.f = { linha: '' };
    el.innerHTML = '<div class="page-head"><div><h1>Fichas de preventiva</h1><p class="sub">A ficha em planilha de cada equipamento, no mesmo modelo da ficha da Enchedora da Linha 1: itens, frequência, método e os meses com NA. Cada item é uma tarefa do plano de Preventiva; ao registrar a execução, a ficha marca O (normal) ou X (anormal) no mês.</p></div><div class="btn-row" id="fi-acoes"></div></div>'
      + '<div id="fi-tiles"></div><div class="toolbar" style="margin-top:14px"><select class="inp" style="width:auto;min-width:150px" aria-label="Linha" data-ch="fi-linha">' + opts(LINHAS.map(l => ({ v: l.id, l: l.nome })), '', 'Todas as linhas') + '</select></div><div id="fi-body"></div>';
    this.update();
  },
  update() {
    if (!this.el || !this.el.isConnected) return;
    const body = $('#fi-body', this.el), tiles = $('#fi-tiles', this.el), acoes = $('#fi-acoes', this.el);
    const ref = Store.all('fichas').find(f => f.referencia);
    acoes.innerHTML = (ref ? '<button type="button" class="btn" data-act="fi-modelo">' + ico('download') + ' Ficha modelo em branco</button>' : '')
      + (podeEscrever() ? '<button type="button" class="btn pri" data-act="fi-importar">' + ico('upload') + ' Importar ficha</button>' : '');
    if (!Store.isReady()) { body.innerHTML = carregando(); tiles.innerHTML = ''; return; }
    const todas = Store.all('fichas').filter(f => !this.f.linha || f.linha === this.f.linha)
      .sort((a, b) => ordemLinha(a.linha) - ordemLinha(b.linha) || byText(fiEqNome(a), fiEqNome(b)) || byText(b.controle || '', a.controle || ''));
    if (!Store.all('fichas').length) {
      tiles.innerHTML = '';
      body.innerHTML = vazio('Nenhuma ficha importada', 'Importe a planilha da ficha de manutenção preventiva (.xlsx). O app lê o cabeçalho (linha, equipamento, fabricante, modelo, nº de controle), a tabela de itens com frequência, método e os meses (com NA onde não se aplica) e a aba "Lista" com materiais, fornecedor e quantidade. Cada item vira uma tarefa no plano de Preventiva do equipamento.',
        podeEscrever() ? '<button type="button" class="btn pri" data-act="fi-importar">' + ico('upload') + ' Importar ficha</button>' : '');
      return;
    }
    const res = todas.map(f => ({ f, r: fiResumo(f) }));
    const tAtr = res.reduce((s, x) => s + x.r.atr, 0), tMes = res.reduce((s, x) => s + x.r.noMes, 0), tItens = todas.reduce((s, f) => s + (f.itens || []).length, 0);
    tiles.innerHTML = '<div class="tiles"><div class="tile"><span class="lbl">Fichas</span><span class="val">' + todas.length + '</span></div>'
      + '<div class="tile"><span class="lbl">Itens</span><span class="val">' + tItens + '</span></div>'
      + '<div class="tile' + (tMes ? ' warn' : '') + '"><span class="lbl">Programados neste mês</span><span class="val">' + tMes + '</span></div>'
      + '<div class="tile' + (tAtr ? ' crit' : '') + '"><span class="lbl">Atrasados</span><span class="val">' + tAtr + '</span></div></div>';
    if (!todas.length) { body.innerHTML = '<p class="ink2" style="margin-top:12px">Nenhuma ficha nesta linha.</p>'; return; }
    let h = '<div class="list" style="margin-top:12px">', lin = null;
    for (const { f, r } of res) {
      if (f.linha !== lin) { lin = f.linha; h += '<div class="group-h">' + esc(linhaNome(lin)) + '</div>'; }
      const e = eqDe(f.equipId);
      h += '<div class="row clickable wrap-sm" data-act="fi-abrir" data-id="' + f.id + '" role="button" tabindex="0"><span class="grow">'
        + '<span class="t1" style="display:block">' + ltag(f.linha) + ' ' + esc(fiEqNome(f)) + (f.referencia ? ' <span class="fi-tag atu">modelo de referência</span>' : '') + '</span>'
        + '<span class="t2" style="display:block">' + esc(['Nº controle ' + (f.controle || '—'), f.periodo, (f.itens || []).length + ' itens', [f.fabricante, f.modelo].filter(Boolean).join(' · ')].filter(Boolean).join(' · ')) + (e ? '' : ' · <b style="color:var(--crit)">equipamento não encontrado</b>') + '</span></span>'
        + '<span class="side-r"><span class="acts">' + (r.atr ? stPill({ cls: 'crit', txt: r.atr + ' ' + plural(r.atr, 'atrasado') }) : '') + (r.noMes ? stPill({ cls: 'warn', txt: r.noMes + ' neste mês' }) : '') + (!r.atr && !r.noMes ? stPill({ cls: 'ok', txt: 'Em dia' }) : '') + '</span></span></div>';
    }
    body.innerHTML = h + '</div>';
  }
};
INP['fi-linha'] = el => { const v = VIEWS.fichas; v.f.linha = el.value; v.update(); };

/* ---------- Detalhe da ficha ---------- */
ACT['fi-abrir'] = el => fiAbrir(el.dataset.id);
function fiAbrir(id) {
  Modal.closeAll();
  Modal.open({
    wide: true, live: true,
    title: () => { const f = Store.get('fichas', id); return f ? 'Ficha de preventiva · ' + fiEqNome(f) : 'Ficha de preventiva'; },
    render: () => {
      const f = Store.get('fichas', id);
      if (!f) return vazio('Ficha removida', 'Esta ficha não existe mais.');
      const e = eqDe(f.equipId), r = fiResumo(f);
      let h = '<div class="tk-head">' + ltag(f.linha) + pill('', '', 'Nº controle ' + (f.controle || '—')) + (f.referencia ? '<span class="fi-tag atu">modelo de referência</span>' : '')
        + (r.atr ? stPill({ cls: 'crit', txt: r.atr + ' ' + plural(r.atr, 'atrasado') }) : '') + (r.noMes ? stPill({ cls: 'warn', txt: r.noMes + ' neste mês' }) : '') + '</div>';
      h += '<dl class="kv" style="margin-top:10px"><dt>Equipamento</dt><dd>' + (e ? '<button type="button" class="oslink" style="font-family:var(--f-body)" data-act="equip" data-id="' + e.id + '">' + esc(e.nome) + '</button> <span class="mono small muted">' + esc(e.tag || '') + '</span>' : '<b style="color:var(--crit)">não encontrado</b>')
        + (f.equipamento && e && fiChave(f.equipamento) !== fiChave(e.nome) ? ' <span class="small muted">(na ficha: ' + esc(f.equipamento) + ')</span>' : '') + '</dd>'
        + '<dt>Linha</dt><dd>' + esc(linhaNome(f.linha)) + '</dd>'
        + (f.fabricante || f.modelo ? '<dt>Fabricante / modelo</dt><dd>' + esc([f.fabricante, f.modelo].filter(Boolean).join(' · ')) + '</dd>' : '')
        + (f.periodo ? '<dt>Período</dt><dd>' + esc(f.periodo) + ((f.meses || []).length ? ' · ' + fiMesCurto(f.meses[0]) + ' a ' + fiMesCurto(f.meses[f.meses.length - 1]) : '') + '</dd>' : '')
        + (f.aprovado || f.verificado ? '<dt>Aprovado / verificado</dt><dd>' + esc([f.aprovado || '—', f.verificado || '—'].join(' / ')) + '</dd>' : '')
        + '<dt>Planilha</dt><dd>' + esc(f.arquivo || '—') + (f.importadoEm ? ' · importada em ' + fmtData(msToISO(f.importadoEm)) : '') + (f.importadoPor ? ' por ' + esc(f.importadoPor) : '') + '</dd></dl>';
      h += fiLegendaHtml() + fiGradeHtml(f);
      h += '<p class="small ink2" style="margin-top:8px">' + (podeEscrever() ? 'Toque no mês (• próxima, ! atrasada) para registrar a execução com O ou X. ' : '') + 'Toque no item para ver a tarefa no plano de Preventiva, com o histórico.</p>';
      h += fiListaHtml(f);
      return h;
    },
    footer: () => {
      const f = Store.get('fichas', id); if (!f) return '';
      return (podeEscrever() ? '<button type="button" class="btn ghost" data-act="fi-excluir" data-id="' + id + '">' + ico('trash', 'sm') + ' Excluir</button>'
        + '<button type="button" class="btn" data-act="fi-equip" data-id="' + id + '">' + ico('swap', 'sm') + ' Equipamento</button>'
        + (f.referencia ? '' : '<button type="button" class="btn" data-act="fi-ref" data-id="' + id + '">Usar como modelo</button>') : '')
        + '<button type="button" class="btn pri" data-act="fi-baixar" data-id="' + id + '">' + ico('download', 'sm') + ' Baixar planilha</button>';
    }
  });
}
ACT['fi-ref'] = async el => {
  const id = el.dataset.id;
  await ocupado(el, async () => {
    for (const f of Store.all('fichas')) if (f.referencia && f.id !== id) await Store.update('fichas', f.id, { referencia: false });
    await Store.update('fichas', id, { referencia: true });
    toast('Esta ficha é agora o modelo de referência.');
  });
};
ACT['fi-excluir'] = async el => {
  const f = Store.get('fichas', el.dataset.id); if (!f) return;
  if (!await confirmar({ titulo: 'Excluir a ficha?', texto: 'A ficha ' + esc(f.controle || '') + ' de ' + esc(fiEqNome(f)) + ' sai da lista. As tarefas continuam no plano de Preventiva, com o histórico de execuções.', ok: 'Excluir', perigo: true })) return;
  await ocupado(null, async () => {
    for (const it of f.itens || []) { const p = it.prevId ? Store.get('preventivas', it.prevId) : null; if (p && p.fichaId === f.id) await Store.update('preventivas', p.id, { fichaId: null }); }
    await Store.del('fichas', f.id);
    Modal.closeAll(); toast('Ficha excluída. As tarefas continuam no plano.');
  });
};
ACT['fi-equip'] = el => {
  const f = Store.get('fichas', el.dataset.id); if (!f) return;
  Modal.open({
    title: 'Equipamento da ficha',
    html: '<form class="form" data-form="fi-equip" id="f-fi-equip" data-id="' + f.id + '"><p class="ink2">Na planilha: <b>' + esc(f.equipamento || '—') + '</b> · ' + esc(linhaNome(f.linha)) + '</p>'
      + fSel('fi-eq', 'Equipamento', eqOptions(f.equipId, { vazio: 'Escolha o equipamento', todos: true }), { name: 'equipId', req: true })
      + '<p class="small ink2">As tarefas desta ficha passam para o equipamento escolhido.</p></form>',
    foot: '<button type="button" class="btn" data-close>Voltar</button><button type="submit" class="btn pri" form="f-fi-equip">Salvar</button>'
  });
};
FORMS['fi-equip'] = async (form, btn) => {
  const f = Store.get('fichas', form.dataset.id), d = dadosForm(form), e = eqDe(d.equipId);
  if (!f || !e) return toast('Escolha o equipamento.', 'crit');
  await ocupado(btn, async () => {
    for (const it of f.itens || []) { const p = it.prevId ? Store.get('preventivas', it.prevId) : null; if (p && p.equipId !== e.id) await Store.update('preventivas', p.id, { equipId: e.id, atualizadoEm: Date.now() }); }
    await Store.update('fichas', f.id, { equipId: e.id, linha: e.linha, atualizadoEm: Date.now() });
    Modal.close(); toast('Ficha ligada a ' + e.nome + '.');
  });
};

/* ---------- Planilha: baixar a ficha preenchida ou o modelo em branco ---------- */
function fiMesesModelo(ref) {
  const n = Math.max(12, (ref.meses || []).length || 15);
  const d0 = parseISODate((ref.meses || [])[0] || hoje());
  const dia = d0 ? d0.getDate() : 1;
  let ini = hoje().slice(0, 8) + pad(Math.min(dia, 28));
  if (ini < hoje()) ini = fiSomarMeses(ini, 1);
  const out = [ini];
  for (let i = 1; i < n; i++) out.push(fiSomarMeses(ini, i));
  return out;
}
async function fiExportar(f, vazia) {
  const X = await carregarXLSX();
  const meses = vazia ? fiMesesModelo(f) : (f.meses || []);
  const M = meses.length, c0 = 5, cl = c0 + Math.max(M, 1) - 1, cr = Math.max(cl, 19), W = cr + 1;
  const nova = () => new Array(W).fill('');
  const aoa = [];
  aoa.push(nova());
  const r2 = nova(); r2[1] = 'FICHA DE MANUTENÇÃO PREVENTIVA'; r2[cr - 2] = 'APROVADO'; r2[cr - 1] = 'VERIFICADO'; r2[cr] = 'Nº CONTROLE'; aoa.push(r2);
  const r3 = nova(); if (!vazia) { r3[cr - 2] = f.aprovado || ''; r3[cr - 1] = f.verificado || ''; r3[cr] = f.controle || ''; } aoa.push(r3);
  const e = eqDe(f.equipId);
  const r4 = nova();
  r4[1] = 'LINHA: ' + (vazia ? '' : (f.linhaTxt || linhaCurto(f.linha)));
  r4[3] = 'EQUIPAMENTO: ' + (vazia ? '' : (f.equipamento || (e && e.nome) || ''));
  r4[6] = 'FABRICANTE: ' + (vazia ? '' : (f.fabricante || (e && e.fabricante) || ''));
  r4[11] = 'MODELO: ' + (vazia ? '' : (f.modelo || (e && e.modelo) || ''));
  r4[15] = 'LEGENDA:   O = Normal   X = Anormal   NA = Não aplicável';
  aoa.push(r4);
  aoa.push(nova());
  const r6 = nova(); r6[c0] = vazia ? [...new Set(meses.map(m => m.slice(0, 4)))].join(' e ') : (f.periodo || ''); aoa.push(r6);
  const r7 = nova(); r7[1] = 'Nº'; r7[2] = 'ITEM'; r7[3] = 'FREQUÊNCIA'; r7[4] = 'MÉTODO'; meses.forEach((m, j) => { r7[c0 + j] = fmtData(m); }); aoa.push(r7);
  const itens = vazia ? Array.from({ length: 12 }, (x, i) => ({ n: i + 1 })) : (f.itens || []);
  for (const it of itens) {
    const r = nova(); r[1] = it.n;
    if (!vazia) {
      const p = it.prevId ? Store.get('preventivas', it.prevId) : null;
      r[2] = (p && p.titulo) || it.titulo || ''; r[3] = it.frequencia || ''; r[4] = it.metodo || '';
      const cel = fiCelulas(f, it, p);
      cel.forEach((c, j) => { r[c0 + j] = c.e === 'na' ? 'NA' : c.e === 'o' ? 'O' : c.e === 'x' ? 'X' : ''; });
    }
    aoa.push(r);
  }
  const rr = nova(); rr[4] = 'RESPONSÁVEL:'; aoa.push(rr);
  const ra = nova(); ra[4] = 'ASSINATURA:'; aoa.push(ra);
  const ws = X.utils.aoa_to_sheet(aoa);
  ws['!merges'] = [{ s: { r: 5, c: c0 }, e: { r: 5, c: cl } }, { s: { r: 3, c: 15 }, e: { r: 3, c: cr } }, { s: { r: 1, c: 1 }, e: { r: 2, c: cr - 3 } }];
  ws['!cols'] = Array.from({ length: W }, (x, i) => ({ wch: i === 0 ? 2 : i === 1 ? 5 : i === 2 ? 42 : i === 3 ? 13 : i === 4 ? 14 : 11 }));
  const lista = [['Lista de Componentes e Materiais para Preventiva', '', '', ''], ['Item', 'Descrição', 'Fornecedor', 'Quantidade']];
  if (vazia) for (let i = 1; i <= 12; i++) lista.push([i, '', '', '']);
  else for (const it of f.itens || []) lista.push([it.n, it.descricao || '', it.fornecedor || '', it.quantidade == null ? '' : it.quantidade]);
  const wl = X.utils.aoa_to_sheet(lista);
  wl['!merges'] = [{ s: { r: 0, c: 0 }, e: { r: 0, c: 3 } }];
  wl['!cols'] = [{ wch: 6 }, { wch: 70 }, { wch: 22 }, { wch: 12 }];
  const wb = X.utils.book_new();
  const nomeAba = vazia ? 'Ficha' : cap(String(f.equipamento || (e && e.nome) || 'Ficha').replace(/[\[\]:*?\/\\]+/g, ' ').trim() || 'Ficha', 31);
  X.utils.book_append_sheet(wb, ws, nomeAba);
  X.utils.book_append_sheet(wb, wl, 'Lista');
  const buf = X.write(wb, { bookType: 'xlsx', type: 'array' });
  const nome = (vazia ? 'Ficha de preventiva - modelo em branco' : 'Ficha de preventiva - ' + fiEqNome(f) + ' - ' + linhaCurto(f.linha) + (f.controle ? ' - ' + f.controle : '')).replace(/[\\\/:*?"<>|]+/g, '-') + '.xlsx';
  return salvarArquivo(nome, new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }));
}
ACT['fi-baixar'] = async el => { const f = Store.get('fichas', el.dataset.id); if (f) await ocupado(el, () => fiExportar(f, false), 'Gerando…'); };
ACT['fi-modelo'] = async el => {
  const ref = Store.all('fichas').find(f => f.referencia) || Store.all('fichas')[0];
  if (!ref) return toast('Importe uma ficha primeiro: ela vira o modelo.', 'crit');
  await ocupado(el, () => fiExportar(ref, true), 'Gerando…');
};

/* ---------- Importar ficha ---------- */
ACT['fi-importar'] = () => {
  if (!podeEscrever()) return toast('Seu acesso a este módulo é só de leitura.', 'crit');
  FI.st = { etapa: 'arquivo', fichas: [], arquivo: '', erro: '', lendo: false, res: null };
  FI.m = Modal.open({ title: 'Importar ficha de preventiva', wide: true, persist: true, render: fiImpRender, footer: fiImpRodape });
};
function fiImpRender() {
  const st = FI.st;
  if (st.etapa === 'arquivo') {
    const ref = Store.all('fichas').find(f => f.referencia);
    return '<div class="form"><p class="ink2">Escolha a planilha da ficha (.xlsx). Ela deve seguir o modelo da ficha da Enchedora da Linha 1' + (ref ? ' (Nº controle ' + esc(ref.controle || '—') + ')' : '') + ':</p>'
      + '<ul class="small ink2" style="margin:0;padding-left:20px;line-height:1.6"><li>no topo: <b>LINHA:</b>, <b>EQUIPAMENTO:</b>, <b>FABRICANTE:</b>, <b>MODELO:</b> e <b>Nº CONTROLE</b> (com o número na célula de baixo);</li>'
      + '<li>a tabela com as colunas <b>Nº</b>, <b>ITEM</b>, <b>FREQUÊNCIA</b> (ex.: 1 mês, 2 meses, 6 meses, 1 ano, 2 anos), <b>MÉTODO</b> e uma coluna por mês com a data no topo;</li>'
      + '<li>nos meses: <b>NA</b> onde o item não se aplica, vazio onde está programado, e <b>O</b> (normal) ou <b>X</b> (anormal) se já foi feito;</li>'
      + '<li>a aba <b>Lista</b> com Item, Descrição, Fornecedor e Quantidade.</li></ul>'
      + '<p class="small ink2">Se o equipamento já tem tarefas com o mesmo nome no plano de Preventiva, elas são atualizadas (sem duplicar e sem perder o histórico).</p>'
      + '<input class="inp" type="file" accept=".xlsx,.xls,.xlsm,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel,application/vnd.ms-excel.sheet.macroEnabled.12" data-ch="fi-arq" aria-label="Planilha da ficha">'
      + (ref ? '<div><button type="button" class="btn sm ghost" data-act="fi-modelo">' + ico('download', 'sm') + ' Baixar ficha modelo em branco</button></div>' : '')
      + (st.erro ? '<div class="banner crit">' + ico('alert') + '<div class="grow">' + esc(st.erro) + '</div></div>' : '') + (st.lendo ? carregando('Lendo a planilha…') : '') + '</div>';
  }
  if (st.etapa === 'previa') {
    let h = '<p class="ink2">' + esc(st.arquivo) + ': ' + st.fichas.length + ' ' + plural(st.fichas.length, 'ficha encontrada', 'fichas encontradas') + '. Confira o equipamento e os itens antes de importar.</p>';
    st.fichas.forEach((dr, i) => { h += fiPreviaHtml(dr, i, st.fichas.length > 1); });
    return h;
  }
  if (st.etapa === 'gravando') return '<p class="ink2">Gravando a ficha e as tarefas…</p><div class="progress" style="margin-top:10px"><i style="width:' + Math.round((st.feitos || 0) / Math.max(st.total || 1, 1) * 100) + '%"></i></div>';
  const r = st.res || {};
  return '<div class="stack"><div class="banner' + (r.erros && r.erros.length ? ' warn' : '') + '">' + ico(r.erros && r.erros.length ? 'alert' : 'check') + '<div class="grow"><b>Importação concluída.</b> '
    + r.fichas + ' ' + plural(r.fichas, 'ficha') + ' · ' + r.novas + ' ' + plural(r.novas, 'tarefa nova', 'tarefas novas') + ' e ' + r.atualizadas + ' ' + plural(r.atualizadas, 'atualizada', 'atualizadas') + ' no plano de Preventiva'
    + (r.execs ? ' · ' + r.execs + ' ' + plural(r.execs, 'execução registrada', 'execuções registradas') + ' a partir das marcas O/X' : '') + (r.eqCriados ? ' · ' + r.eqCriados + ' ' + plural(r.eqCriados, 'equipamento cadastrado', 'equipamentos cadastrados') : '') + '.</div></div>'
    + ((r.erros || []).length ? '<div class="sec-title">Erros ao gravar</div><div class="list">' + r.erros.map(x => '<div class="row"><span class="grow small">' + esc(x) + '</span></div>').join('') + '</div>' : '') + '</div>';
}
function fiPreviaHtml(dr, i, varias) {
  const ex = dr.existente ? Store.get('fichas', dr.existente) : null;
  const eqSel = '<option value="">Escolha o equipamento</option><option value="__novo"' + (dr.equipId === '__novo' ? ' selected' : '') + '>➕ Cadastrar novo: ' + esc(dr.equipamento || 'equipamento da ficha') + '</option>' + eqOptions(dr.equipId === '__novo' ? '' : dr.equipId, { todos: true });
  let h = '<div class="fi-card">' + (varias ? '<label class="check" style="float:right"><input type="checkbox" data-ch="fi-incluir" data-i="' + i + '"' + (dr.incluir ? ' checked' : '') + '> Importar</label>' : '')
    + '<h3>' + esc(dr.equipamento || 'Ficha sem nome de equipamento') + ' · ' + esc(dr.linhaTxt ? 'Linha ' + dr.linhaTxt : 'linha não informada') + '</h3>'
    + '<p class="small ink2" style="margin:0 0 8px">Aba "' + esc(dr.aba) + '" · Nº controle <b>' + esc(dr.controle || '—') + '</b>' + (dr.fabricante ? ' · Fabricante ' + esc(dr.fabricante) : '') + (dr.modelo ? ' · Modelo ' + esc(dr.modelo) : '') + (dr.periodo ? ' · ' + esc(dr.periodo) : '')
    + ' · ' + dr.meses.length + ' meses' + (dr.meses.length ? ' (' + fiMesCurto(dr.meses[0]) + ' a ' + fiMesCurto(dr.meses[dr.meses.length - 1]) + ')' : '') + (dr.lista ? ' · materiais da aba "' + esc(dr.lista) + '"' : ' · <b>sem aba Lista</b>') + '</p>'
    + '<div class="frow"><label class="field"><span class="flabel">Linha</span><select class="inp" data-ch="fi-dr-linha" data-i="' + i + '">' + opts(LINHAS.map(l => ({ v: l.id, l: l.nome })), dr.linha, 'Escolha a linha') + '</select></label>'
    + '<label class="field"><span class="flabel">Equipamento no app</span><select class="inp" data-ch="fi-dr-eq" data-i="' + i + '">' + eqSel + '</select></label></div>';
  if (dr.equipId && dr.equipId !== '__novo') {
    const e = eqDe(dr.equipId);
    if (e && fiChave(e.nome) !== fiChave(dr.equipamento)) h += '<p class="small ink2" style="margin:2px 0 0">Na ficha está "' + esc(dr.equipamento) + '"; vai para <b>' + esc(e.nome) + '</b> (' + esc(e.tag || linhaNome(e.linha)) + '). Se não for esse, escolha outro acima.</p>';
    if (e && ((!e.fabricante && dr.fabricante) || (!e.modelo && dr.modelo))) h += '<p class="small ink2" style="margin:2px 0 0">O cadastro do equipamento será completado com ' + esc([!e.fabricante && dr.fabricante ? 'fabricante ' + dr.fabricante : '', !e.modelo && dr.modelo ? 'modelo ' + dr.modelo : ''].filter(Boolean).join(' e ')) + '.</p>';
  } else if (!dr.equipId) h += '<div class="banner warn" style="margin-top:8px">' + ico('alert') + '<div class="grow">Não achei esse equipamento' + (dr.linha ? ' na ' + esc(linhaNome(dr.linha)) : '') + '. Escolha um da lista ou cadastre um novo.</div></div>';
  if (ex) h += '<div class="banner" style="margin-top:8px">' + ico('info') + '<div class="grow">A ficha ' + esc(ex.controle || '') + ' já está no app (importada em ' + fmtData(msToISO(ex.importadoEm || Date.now())) + '): ela será atualizada.</div></div>';
  (dr.avisos || []).forEach(a => { h += '<div class="banner warn" style="margin-top:8px">' + ico('alert') + '<div class="grow">' + esc(a) + '</div></div>'; });
  h += '<div class="tbl-wrap" style="margin-top:10px"><table class="tbl fi-prev"><thead><tr><th>Nº</th><th>Item</th><th>Frequência</th><th>Método</th><th>Meses</th><th>No plano</th></tr></thead><tbody>';
  for (const it of dr.itens) {
    const p = it.alvo ? Store.get('preventivas', it.alvo) : null;
    const prog = it.marcas.filter(x => x !== 'NA').length, feitos = it.marcas.filter(x => x === 'O' || x === 'X').length;
    const mud = p ? fiMudancas(dr, it, p) : [];
    const plano = !it.freq ? '<span class="fi-tag erro">frequência não reconhecida — não entra no plano</span>'
      : p ? '<span class="fi-tag atu">atualiza tarefa</span><span class="small muted" style="display:block;white-space:normal">' + esc(p.titulo) + (mud.length ? ' · ' + esc(mud.join(' · ')) : ' · sem mudanças') + '</span>'
        : '<span class="fi-tag nova">nova tarefa</span><span class="small muted" style="display:block">próxima: ' + esc(fmtData(fiProximaProgramada(dr.meses, it.marcas, it.freq))) + '</span>';
    h += '<tr><td class="mono">' + esc(it.n) + '</td><td style="white-space:normal;min-width:180px">' + esc(it.titulo) + (it.lista && it.lista.descricao ? '<span class="small muted" style="display:block">' + esc(cap(it.lista.descricao, 90)) + '</span>' : '') + '</td>'
      + '<td>' + esc(it.frequencia || '—') + (it.freq ? '<span class="small muted" style="display:block">' + esc(it.freq.tipo === 'horas' ? 'a cada ' + fmtNum(it.freq.horas) + ' h' : freqTexto({ freqTipo: 'dias', freqDias: it.freq.dias })) + '</span>' : '') + '</td>'
      + '<td>' + esc(it.metodo || '—') + '</td><td>' + prog + ' de ' + it.marcas.length + (feitos ? '<span class="small muted" style="display:block">' + feitos + ' com O/X</span>' : '') + '</td><td style="white-space:normal;min-width:170px">' + plano + '</td></tr>';
  }
  return h + '</tbody></table></div></div>';
}
function fiImpRodape() {
  const st = FI.st;
  if (st.etapa === 'arquivo') return '<button type="button" class="btn" data-close>Cancelar</button>';
  if (st.etapa === 'previa') {
    const sel = st.fichas.filter(x => x.incluir);
    const falta = sel.some(x => !x.equipId || (x.equipId === '__novo' && !x.linha));
    return '<button type="button" class="btn" data-act="fi-voltar">Outra planilha</button><button type="button" class="btn pri" data-act="fi-gravar"' + (!sel.length || falta ? ' disabled' : '') + '>' + ico('upload', 'sm') + ' Importar' + (sel.length > 1 ? ' ' + sel.length + ' fichas' : ' ficha') + '</button>';
  }
  if (st.etapa === 'gravando') return '';
  const r = st.res || {};
  return '<button type="button" class="btn" data-close>Fechar</button>' + (r.abrir ? '<button type="button" class="btn pri" data-act="fi-abrir" data-id="' + r.abrir + '">Abrir a ficha</button>' : '');
}
INP['fi-arq'] = async el => {
  const st = FI.st, file = el.files && el.files[0];
  if (!file) return;
  st.erro = ''; st.lendo = true; FI.m.refresh();
  try {
    const r = await fiLerArquivo(file);
    st.lendo = false;
    if (!r.fichas.length) { st.erro = 'Não encontrei a tabela da ficha (colunas ITEM e FREQUÊNCIA) em nenhuma aba de "' + r.arquivo + '". Confira se é a planilha no modelo da ficha da Enchedora da Linha 1.'; FI.m.refresh(); return; }
    st.arquivo = r.arquivo;
    st.fichas = r.fichas.map(f => { const e = fiAcharEquip(f); const dr = Object.assign(f, { equipId: e ? e.id : '', incluir: true }); if (!dr.linha && e) dr.linha = e.linha; fiCasar(dr); return dr; });
    st.etapa = 'previa'; FI.m.refresh();
  } catch (e) {
    console.warn('ficha', e);
    st.lendo = false; st.erro = (e && e.message) || 'Não foi possível ler a planilha.'; FI.m.refresh();
  }
};
INP['fi-incluir'] = el => { const dr = FI.st.fichas[+el.dataset.i]; if (dr) { dr.incluir = el.checked; FI.m.refresh(); } };
INP['fi-dr-linha'] = el => {
  const dr = FI.st.fichas[+el.dataset.i]; if (!dr) return;
  dr.linha = el.value;
  if (dr.equipId !== '__novo') { const e = fiAcharEquip(dr); dr.equipId = e ? e.id : ''; }
  fiCasar(dr); FI.m.refresh();
};
INP['fi-dr-eq'] = el => {
  const dr = FI.st.fichas[+el.dataset.i]; if (!dr) return;
  dr.equipId = el.value;
  const e = eqDe(dr.equipId); if (e) dr.linha = e.linha;
  fiCasar(dr); FI.m.refresh();
};
ACT['fi-voltar'] = () => { FI.st.etapa = 'arquivo'; FI.st.fichas = []; FI.st.erro = ''; FI.m.refresh(); };
ACT['fi-gravar'] = async el => {
  const st = FI.st; if (st.etapa !== 'previa') return;
  const sel = st.fichas.filter(x => x.incluir); if (!sel.length) return;
  const agora = Date.now(), por = nomeUsuario() || '';
  const res = { fichas: 0, novas: 0, atualizadas: 0, execs: 0, eqCriados: 0, erros: [], abrir: null };
  st.etapa = 'gravando'; st.total = sel.reduce((s, d) => s + d.itens.length + 1, 0); st.feitos = 0; FI.m.refresh();
  const temRef = Store.all('fichas').some(f => f.referencia);
  for (const dr of sel) {
    try {
      let eqId = dr.equipId;
      if (eqId === '__novo') {
        eqId = uid();
        await Store.set('equipamentos', eqId, {
          nome: dr.equipamento || ('Equipamento da ficha ' + (dr.controle || '')), linha: dr.linha, tag: '', tipo: TIPOS_EQUIP.find(t => fiChave(t) === fiChave(dr.equipamento)) || 'Outro',
          fabricante: dr.fabricante || '', modelo: dr.modelo || '', capacidade: '', local: '', criticidade: '', obs: '', ativo: true, ordem: 900 + Store.all('equipamentos').filter(x => x.linha === dr.linha).length,
          criadoEm: agora, atualizadoEm: agora, origem: 'Ficha de preventiva ' + (dr.controle || '')
        });
        res.eqCriados++;
      } else {
        const e = eqDe(eqId), patch = {};
        if (e && !e.fabricante && dr.fabricante) patch.fabricante = dr.fabricante;
        if (e && !e.modelo && dr.modelo) patch.modelo = dr.modelo;
        if (Object.keys(patch).length) await Store.update('equipamentos', eqId, Object.assign(patch, { atualizadoEm: agora }));
      }
      const ex = dr.existente ? Store.get('fichas', dr.existente) : null;
      const fichaId = ex ? ex.id : uid();
      const itens = [];
      for (const it of dr.itens) {
        const l = it.lista || {};
        const base = { n: it.n, titulo: it.titulo, frequencia: it.frequencia, freqTipo: it.freq ? it.freq.tipo : null, freqDias: it.freq && it.freq.tipo === 'dias' ? it.freq.dias : null, freqHoras: it.freq && it.freq.tipo === 'horas' ? it.freq.horas : null,
          metodo: it.metodo || '', marcas: it.marcas, descricao: l.descricao || '', fornecedor: l.fornecedor || '', quantidade: l.quantidade == null ? null : l.quantidade, prevId: null };
        if (!it.freq) { itens.push(base); st.feitos++; continue; }
        const p = it.alvo ? Store.get('preventivas', it.alvo) : null;
        const marcas = fiMarcasNovas(dr, it, p);
        const novosHist = marcas.map(x => ({ data: x.m, horas: null, por: 'Ficha ' + (dr.controle || ''), obs: 'Marcado ' + (x.k === 'O' ? 'O (normal)' : 'X (anormal)') + ' na ficha importada', pecas: [], prevista: x.m, t: agora, checklist: null, resultado: x.k, fonte: 'ficha' }));
        const ultMarca = marcas.length ? marcas[marcas.length - 1].m : null;
        const comum = {
          freqTipo: it.freq.tipo, freqDias: it.freq.tipo === 'dias' ? it.freq.dias : ((p && p.freqDias) || null), freqHoras: it.freq.tipo === 'horas' ? it.freq.horas : null,
          metodo: it.metodo || '', fornecedor: l.fornecedor || (p && p.fornecedor) || '', quantidade: l.quantidade != null ? l.quantidade : (p && p.quantidade != null ? p.quantidade : null),
          fichaId, fichaItem: it.n, fichaControle: dr.controle || '', atualizadoEm: agora
        };
        let pid;
        if (p) {
          const patch = Object.assign({}, comum);
          if (!p.descricao && l.descricao) patch.descricao = l.descricao;
          if (novosHist.length) {
            patch.historico = (p.historico || []).concat(novosHist).sort((a, b) => String(a.data).localeCompare(String(b.data)) || (a.t || 0) - (b.t || 0)).slice(-40);
            if (!p.ultimaData || ultMarca > p.ultimaData) { patch.ultimaData = ultMarca; patch.proximaData = null; }
          } else if (!p.ultimaData && !p.proximaData) patch.proximaData = fiProximaProgramada(dr.meses, it.marcas, it.freq);
          await Store.update('preventivas', p.id, patch);
          pid = p.id; res.atualizadas++;
        } else {
          pid = uid();
          await Store.set('preventivas', pid, Object.assign({
            equipId: eqId, titulo: it.titulo, descricao: l.descricao || '', checklist: [], responsavel: 'Manutenção', duracaoMin: null,
            requerParada: /substitu|troca|limpeza|desmont|reparo/.test(norm(it.metodo + ' ' + it.titulo)), pecas: [], ativo: true,
            historico: novosHist, ultimaData: ultMarca, proximaData: ultMarca ? null : fiProximaProgramada(dr.meses, it.marcas, it.freq), ultimaHoras: null,
            criadoEm: agora, origem: 'ficha'
          }, comum));
          res.novas++;
        }
        res.execs += novosHist.length;
        base.prevId = pid; itens.push(base);
        st.feitos++; FI.m.refresh();
      }
      await Store.set('fichas', fichaId, {
        equipId: eqId, linha: dr.linha || (eqDe(eqId) && eqDe(eqId).linha) || '', linhaTxt: dr.linhaTxt || '', equipamento: dr.equipamento || '', fabricante: dr.fabricante || '', modelo: dr.modelo || '',
        controle: dr.controle || '', periodo: dr.periodo || '', aprovado: dr.aprovado || '', verificado: dr.verificado || '', legenda: dr.legenda || '', meses: dr.meses, itens,
        arquivo: st.arquivo, aba: dr.aba, listaAba: dr.lista || '', importadoEm: agora, importadoPor: por,
        referencia: ex ? !!ex.referencia : (!temRef && res.fichas === 0), criadoEm: ex ? (ex.criadoEm || agora) : agora, atualizadoEm: agora
      });
      res.fichas++; res.abrir = res.abrir || fichaId; st.feitos++;
    } catch (e) {
      console.warn('ficha', e);
      res.erros.push((dr.equipamento || dr.aba) + ': ' + ((e && e.message) || 'não foi possível gravar'));
    }
  }
  st.res = res; st.etapa = 'fim'; FI.m.refresh();
  if (res.fichas) toast('Ficha importada: ' + res.novas + ' ' + plural(res.novas, 'tarefa nova', 'tarefas novas') + ' e ' + res.atualizadas + ' ' + plural(res.atualizadas, 'atualizada', 'atualizadas') + '.');
};

/* ---------- Ligações com as outras telas ---------- */
function fichasDoEquipHtml(e) {
  const fs = Store.all('fichas').filter(f => f.equipId === e.id).sort((a, b) => (b.importadoEm || 0) - (a.importadoEm || 0));
  if (!fs.length) return '';
  return '<div class="blk"><div class="blk-h"><h3>Ficha de preventiva · ' + fs.length + '</h3></div><div class="list">'
    + fs.map(f => { const r = fiResumo(f); return '<div class="row clickable" data-act="fi-abrir" data-id="' + f.id + '" role="button" tabindex="0"><span class="grow"><span class="t1" style="display:block">Nº controle ' + esc(f.controle || '—') + (f.periodo ? ' · ' + esc(f.periodo) : '') + '</span><span class="t2" style="display:block">' + (f.itens || []).length + ' itens · ' + esc(f.arquivo || '') + '</span></span><span class="side-r">' + (r.atr ? stPill({ cls: 'crit', txt: r.atr + ' ' + plural(r.atr, 'atrasado') }) : r.noMes ? stPill({ cls: 'warn', txt: r.noMes + ' neste mês' }) : stPill({ cls: 'ok', txt: 'Em dia' })) + '</span></div>'; }).join('')
    + '</div></div>';
}
function fichaBlocoPlano(p) {
  const f = p.fichaId ? Store.get('fichas', p.fichaId) : null;
  if (!f && !p.metodo && !p.fornecedor && p.quantidade == null) return '';
  return '<div class="blk"><div class="blk-h"><h3>Ficha de preventiva</h3>' + (f ? '<button type="button" class="btn sm" data-act="fi-abrir" data-id="' + f.id + '">' + ico('list', 'sm') + ' Abrir ficha</button>' : '') + '</div><dl class="kv">'
    + (f ? '<dt>Nº controle</dt><dd>' + esc(f.controle || '—') + (p.fichaItem != null ? ' · item ' + esc(p.fichaItem) : '') + '</dd>' : '')
    + (p.metodo ? '<dt>Método</dt><dd>' + esc(p.metodo) + '</dd>' : '')
    + (p.fornecedor ? '<dt>Fornecedor</dt><dd>' + esc(p.fornecedor) + '</dd>' : '')
    + (p.quantidade != null && p.quantidade !== '' ? '<dt>Quantidade</dt><dd>' + esc(typeof p.quantidade === 'number' ? fmtNum(p.quantidade) : p.quantidade) + '</dd>' : '')
    + '</dl></div>';
}
