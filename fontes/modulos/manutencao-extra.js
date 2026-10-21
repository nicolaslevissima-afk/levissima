/* =====================================================================
   LEVÍSSIMA · Manutenção, pedidos de 21/10/2026 (inserido pelo montar.py, antes da inicialização)
   - Chamados: só o Nicolas (senha mestre) apaga; ele também atende e conclui, pelo fluxo normal (iniciar → concluir).
   - Equipamento: documentação em PDF (manuais, diagramas elétricos) e etiqueta com QR que abre o histórico da máquina.
   - Materiais usados no atendimento: baixa no estoque na hora (e devolução); no fechamento, as peças da máquina à mão.
   - Estoque de peças por máquina (aba "Por máquina", máquinas no cadastro da peça e na planilha) e fotos da peça.
   - Selecionar vários itens e excluir de uma vez (equipamentos, peças, preventiva, lubrificação, ferramentas;
     chamados só o Nicolas).
   ===================================================================== */
const LEV = { abrirEquip: null, sel: { view: null, ids: new Set() } };
const LEV_URL_MANUT = 'https://nicolaslevissima-afk.github.io/levissima/modulos/manutencao.html';
ICONS.qr = '<path d="M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4z"/><path d="M14 14h2v2h-2zM18 14h2M14 18v2M18 18h2v2"/>';

// o Nicolas entra com a senha mestre (ref "mestre"); a diretoria tem papel mestre, mas outra ref e "só inclui"
function levSouNicolas() { const q = window.LEV_QUEM; return !!(q && q.ref === 'mestre' && !q.soInclui); }

(function levEstilo() {
  const s = document.createElement('style');
  s.textContent = ''
    + '.btn.lev-perigo{color:var(--crit)}'
    + '.lev-selbar{position:fixed;left:12px;right:12px;bottom:calc(var(--nav-h) + 12px + env(safe-area-inset-bottom,0px));z-index:60;display:flex;flex-wrap:wrap;gap:8px;align-items:center;padding:10px 12px;border-radius:var(--r-lg);background:var(--ink);color:var(--surface);box-shadow:var(--shadow-lg)}'
    + '.lev-selbar b{font-size:15px;margin-right:auto}'
    + '.lev-selbar .btn{min-height:40px}'
    + '@media (min-width:1024px){.lev-selbar{left:calc(var(--side-w) + 24px);right:24px;bottom:20px}}'
    + '.lev-sel-on .row[data-lev-sel],.lev-sel-on .tag[data-lev-sel]{cursor:pointer}'
    + '.lev-ck{flex:none;width:24px;height:24px;border-radius:7px;border:2px solid var(--line-2);background:var(--surface);display:inline-flex;align-items:center;justify-content:center;color:transparent;font-weight:800;font-size:15px;line-height:1}'
    + '[data-lev-sel][aria-pressed="true"] .lev-ck{background:var(--accent);border-color:var(--accent);color:var(--accent-ink)}'
    + '.row[data-lev-sel][aria-pressed="true"]{background:var(--accent-soft)}'
    + '.tag[data-lev-sel]{position:relative}.tag[data-lev-sel] .lev-ck{position:absolute;top:8px;right:8px;z-index:2}'
    + '.tag[data-lev-sel][aria-pressed="true"]{outline:3px solid var(--accent);outline-offset:2px}'
    + '.lev-sel-on #view{padding-bottom:96px}'
    + '.lev-sel-on .toasts{bottom:calc(var(--nav-h) + 92px + env(safe-area-inset-bottom,0px))}'
    + '@media (min-width:1024px){.lev-sel-on .toasts{bottom:96px}}'
    + '.lev-docs .row .lev-doc-ico{flex:none;width:34px;height:40px;border-radius:6px;background:color-mix(in srgb,var(--crit) 12%,var(--surface));color:var(--crit);font:700 11px/40px var(--f-mono);text-align:center}'
    + '.lev-mini{flex:none;width:44px;height:44px;border-radius:8px;object-fit:cover;border:1px solid var(--line);background:var(--surface-2)}'
    + '.lev-chips-maq{display:flex;flex-wrap:wrap;gap:6px;margin:2px 0 4px}'
    + '.lev-chips-maq .chip{font-size:13px}'
    + '.lev-maqs{max-height:220px;overflow:auto;border:1px solid var(--line);border-radius:var(--r-md);padding:6px 10px;background:var(--surface)}'
    + '.lev-maqs .lev-maq-l{font-size:11px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);font-weight:700;margin:8px 0 2px}'
    + '.lev-maqs label{display:flex;gap:8px;align-items:center;padding:5px 0;font-size:14px}'
    + '.lev-mat{display:flex;gap:10px;align-items:center;padding:8px 0;border-top:1px solid var(--line)}'
    + '.lev-mat:first-child{border-top:0}'
    + '.lev-mat .grow{min-width:0}';
  document.head.appendChild(s);
})();

/* ---------- QR da máquina: #equip=<id> abre o equipamento (com o histórico) ---------- */
(function levQrEntrada() {
  let h = '';
  try { h = decodeURIComponent((location.hash || '').slice(1)); } catch (e) { h = ''; }
  const m = /^equip=([A-Za-z0-9_-]{1,80})$/.exec(h);
  if (!m) return;
  LEV.abrirEquip = m[1];
  try { history.replaceState(null, '', location.pathname + location.search + '#equipamentos'); } catch (e) { /* opcional */ }
  const t0 = Date.now();
  const tentar = () => {
    if (!LEV.abrirEquip) return;
    if (Store.loaded.has('equipamentos') && Store.isReady()) {
      const id = LEV.abrirEquip; LEV.abrirEquip = null;
      if (eqDe(id)) abrirEquip(id); else toast('A máquina deste QR não está mais no cadastro.', 'crit');
      return;
    }
    if (Date.now() - t0 < 25000) setTimeout(tentar, 200);
  };
  setTimeout(tentar, 300);
})();
function levLinkEquip(id) {
  const base = /^https?:$/.test(location.protocol) && !/^(localhost|127\.|10\.|192\.168\.)/.test(location.hostname) ? location.origin + location.pathname : LEV_URL_MANUT;
  return base + '#equip=' + encodeURIComponent(id);
}
let _levQrP = null;
function levCarregarQR() {
  if (window.qrcode) return Promise.resolve(window.qrcode);
  if (!_levQrP) _levQrP = new Promise((ok, falha) => {
    const s = document.createElement('script');
    s.src = 'https://cdnjs.cloudflare.com/ajax/libs/qrcode-generator/1.4.4/qrcode.min.js';
    s.onload = () => (window.qrcode ? ok(window.qrcode) : falha(new Error('qr')));
    s.onerror = () => { _levQrP = null; falha(new Error('qr')); };
    document.head.appendChild(s);
  });
  return _levQrP;
}
ACT['lev-qr'] = async el => {
  const e = eqDe(el.dataset.id); if (!e) return;
  let qrcode;
  try { qrcode = await levCarregarQR(); } catch (x) { return toast('Não foi possível gerar o QR agora (sem internet?).', 'crit'); }
  const qr = qrcode(0, 'M'); qr.addData(levLinkEquip(e.id)); qr.make();
  const n = qr.getModuleCount(), W = 900, H = 1200, cel = Math.floor(600 / n), tam = cel * n, x0 = (W - tam) / 2, y0 = 360;
  const c = document.createElement('canvas'); c.width = W; c.height = H;
  const g = c.getContext('2d');
  const corta = (t, max) => { t = String(t || ''); let r = t; while (r.length > 3 && g.measureText(r).width > max) r = r.slice(0, -1); return r === t ? r : r.slice(0, -1) + '…'; };
  g.fillStyle = '#ffffff'; g.fillRect(0, 0, W, H);
  g.fillStyle = '#122657'; g.fillRect(0, 0, W, 16);
  g.textAlign = 'center';
  g.fillStyle = '#122657'; g.font = '700 44px Barlow, Arial, sans-serif'; g.fillText('MANUTENÇÃO · HISTÓRICO DA MÁQUINA', W / 2, 92);
  // nome da máquina: uma linha grande ou até duas menores
  g.font = '700 64px Barlow, Arial, sans-serif';
  if (g.measureText(e.nome || '').width <= W - 80) g.fillText(e.nome || '', W / 2, 192);
  else {
    g.font = '700 50px Barlow, Arial, sans-serif';
    const pal = String(e.nome || '').split(/\s+/); let l1 = '';
    while (pal.length && g.measureText((l1 ? l1 + ' ' : '') + pal[0]).width <= W - 80) l1 += (l1 ? ' ' : '') + pal.shift();
    if (!l1) l1 = pal.shift() || '';
    g.fillText(corta(l1, W - 80), W / 2, 168); g.fillText(corta(pal.join(' '), W - 80), W / 2, 226);
  }
  g.fillStyle = '#41505d'; g.font = '500 38px "IBM Plex Mono", Menlo, monospace'; g.fillText(corta([e.tag || 'sem TAG', linhaNome(e.linha)].join(' · '), W - 80), W / 2, 290);
  g.fillStyle = '#000000';
  for (let r = 0; r < n; r++) for (let k = 0; k < n; k++) if (qr.isDark(r, k)) g.fillRect(x0 + k * cel, y0 + r * cel, cel, cel);
  g.fillStyle = '#122657'; g.font = '600 36px Barlow, Arial, sans-serif';
  g.fillText('Aponte a câmera: histórico, planos e abrir chamado', W / 2, y0 + tam + 76);
  g.fillStyle = '#5d6b78'; g.font = '500 28px Barlow, Arial, sans-serif';
  g.fillText('É preciso entrar com a senha do LEVÍSSIMA.', W / 2, y0 + tam + 122);
  g.fillStyle = '#59C251'; g.font = '700 40px Barlow, Arial, sans-serif'; g.fillText('LEVÍSSIMA', W / 2, H - 50);
  const url = c.toDataURL('image/png');
  const nome = 'etiqueta-' + norm(e.tag || e.nome).replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40) + '.png';
  LEV.etiqueta = { nome, canvas: c };
  Modal.open({
    title: 'Etiqueta da máquina',
    html: '<p class="ink2">Imprima e cole na máquina. O QR abre esta máquina no módulo Manutenção, com o histórico de chamados e os planos.</p>'
      + '<img src="' + url + '" alt="Etiqueta com QR de ' + esc(e.nome) + '" style="width:100%;max-width:360px;display:block;margin:10px auto;border:1px solid var(--line);border-radius:8px">'
      + '<p class="small muted mono" style="word-break:break-all">' + esc(levLinkEquip(e.id)) + '</p>',
    foot: '<button type="button" class="btn" data-close>Fechar</button><button type="button" class="btn pri" data-act="lev-qr-baixar">' + ico('download', 'sm') + ' Baixar imagem</button>'
  });
};
ACT['lev-qr-baixar'] = el => {
  const e = LEV.etiqueta; if (!e) return;
  e.canvas.toBlob(blob => { if (blob) salvarArquivo(e.nome, blob, 'image/png'); }, 'image/png');
};

/* ---------- Documentação do equipamento (PDF) ---------- */
const LEV_TIPOS_DOC = [{ v: 'manual', l: 'Manual' }, { v: 'diagrama', l: 'Diagrama elétrico' }, { v: 'outro', l: 'Outro' }];
function levTamanho(b) { return !b ? '' : b < 1048576 ? Math.max(1, Math.round(b / 1024)) + ' KB' : fmtNum(b / 1048576, 1) + ' MB'; }
function levDocsHtml(e) {
  const docs = Array.isArray(e.docs) ? e.docs : [];
  const ordem = { manual: 0, diagrama: 1, outro: 2 };
  const l = docs.slice().sort((a, b) => (ordem[a.tipo] || 9) - (ordem[b.tipo] || 9) || byText(a.nome, b.nome));
  return '<div class="blk lev-docs"><div class="blk-h"><h3>Documentação · ' + docs.length + '</h3><span class="btn-row">'
    + '<button type="button" class="btn sm" data-act="lev-qr" data-id="' + e.id + '">' + ico('qr', 'sm') + ' Etiqueta QR</button>'
    + (podeEscrever() ? '<button type="button" class="btn sm" data-act="lev-doc-novo" data-id="' + e.id + '">' + ico('plus', 'sm') + ' PDF</button>' : '') + '</span></div>'
    + (l.length ? '<div class="list">' + l.map(d => {
      const tipo = (LEV_TIPOS_DOC.find(t => t.v === d.tipo) || LEV_TIPOS_DOC[2]).l;
      return '<div class="row wrap-sm"><span class="lev-doc-ico" aria-hidden="true">PDF</span><span class="grow"><span class="t1" style="display:block">' + esc(d.nome || 'Documento') + '</span>'
        + '<span class="t2" style="display:block">' + esc(tipo) + (d.tamanho ? ' · ' + levTamanho(d.tamanho) : '') + (d.por ? ' · ' + esc(d.por) : '') + (d.em ? ' · ' + fmtDHc(d.em) : '') + '</span></span>'
        + '<span class="side-r"><span class="acts"><button type="button" class="btn sm pri" data-act="lev-doc-abrir" data-id="' + e.id + '" data-d="' + esc(d.id) + '">Abrir</button>'
        + (podeEscrever() ? '<button type="button" class="btn sm ghost" data-act="lev-doc-tirar" data-id="' + e.id + '" data-d="' + esc(d.id) + '" aria-label="Tirar ' + esc(d.nome || 'documento') + '">' + ico('trash', 'sm') + '</button>' : '') + '</span></span></div>';
    }).join('') + '</div>'
      : '<p class="small ink2">Nenhum manual ou diagrama ainda. Toque em “+ PDF” para guardar os manuais e os diagramas elétricos desta máquina (até 30 MB cada).</p>')
    + '</div>';
}
ACT['lev-doc-novo'] = el => {
  const e = eqDe(el.dataset.id); if (!e) return;
  if (!window.LEVISSIMA || !LEVISSIMA.docs) return toast('Os documentos funcionam pelo LEVÍSSIMA (com internet).', 'crit');
  Modal.open({
    title: 'Documento de ' + e.nome,
    html: '<form class="form" data-form="lev-doc" id="f-lev-doc" data-id="' + e.id + '">'
      + '<div class="field"><label for="lev-doc-arq">Arquivo PDF *</label><input class="inp" id="lev-doc-arq" type="file" accept="application/pdf,.pdf" data-ch="lev-doc-arq" required><span class="hint">Até 30 MB.</span></div>'
      + fChips('tipo', 'Tipo', LEV_TIPOS_DOC, 'manual', { req: true })
      + fText('lev-doc-nome', 'Nome', '', { name: 'nome', req: true, ph: 'Ex.: Manual de operação da enchedora' }) + '</form>',
    foot: '<button type="button" class="btn" data-close>Voltar</button><button type="submit" class="btn pri" form="f-lev-doc">' + ico('upload', 'sm') + ' Guardar PDF</button>'
  });
};
INP['lev-doc-arq'] = el => {
  const f = el.files && el.files[0], n = $('#lev-doc-nome');
  if (f && n && !n.value) n.value = f.name.replace(/\.pdf$/i, '').replace(/[_]+/g, ' ').trim().slice(0, 120);
};
FORMS['lev-doc'] = async (f, btn) => {
  const e = eqDe(f.dataset.id); if (!e) return;
  const arq = $('#lev-doc-arq', f).files[0], d = dadosForm(f);
  if (!arq) return toast('Escolha o arquivo PDF.', 'crit');
  if (!(/pdf$/i.test(arq.type || '') || /\.pdf$/i.test(arq.name || ''))) return toast('O arquivo precisa ser PDF.', 'crit');
  if (arq.size > 30 * 1048576) return toast('O PDF tem mais de 30 MB. Diminua o arquivo e tente de novo.', 'crit');
  const nome = (d.nome || arq.name.replace(/\.pdf$/i, '')).slice(0, 120);
  await ocupado(btn, async () => {
    const caminho = await LEVISSIMA.docs.enviar(arq, 'equipamentos');
    const atual = eqDe(e.id) || e;
    const doc = { id: uid(), nome, tipo: LEV_TIPOS_DOC.some(t => t.v === d.tipo) ? d.tipo : 'outro', caminho, tamanho: arq.size, por: nomeUsuario() || '', em: Date.now() };
    await Store.update('equipamentos', e.id, { docs: (Array.isArray(atual.docs) ? atual.docs : []).concat([doc]), atualizadoEm: Date.now() });
    Modal.close(); toast('PDF guardado em ' + e.nome + '.');
  }, 'Enviando…');
};
ACT['lev-doc-abrir'] = el => {
  const e = eqDe(el.dataset.id), d = e && (e.docs || []).find(x => x.id === el.dataset.d);
  if (!d || !window.LEVISSIMA || !LEVISSIMA.docs) return;
  // abre a janela já no toque (senão o navegador bloqueia) e depois coloca o endereço do PDF (vale 1 hora)
  let w = null; try { w = window.open('', '_blank'); } catch (x) { w = null; }
  LEVISSIMA.docs.url(d.caminho).then(url => {
    if (w && !w.closed) { try { w.location.href = url; return; } catch (x) { /* abre pelo link */ } }
    Modal.open({ title: d.nome || 'Documento', html: '<p class="ink2">O PDF está pronto. O link vale por 1 hora.</p><p style="margin-top:12px"><a class="btn pri" href="' + esc(url) + '" target="_blank" rel="noopener">Abrir o PDF</a></p>', foot: '<button type="button" class="btn" data-close>Fechar</button>' });
  }, x => { if (w) try { w.close(); } catch (y) { /* nada */ } erro(x); });
};
ACT['lev-doc-tirar'] = async el => {
  const e = eqDe(el.dataset.id), d = e && (e.docs || []).find(x => x.id === el.dataset.d);
  if (!d) return;
  if (!await confirmar({ titulo: 'Tirar o documento?', texto: '<b>' + esc(d.nome) + '</b> sai da documentação de ' + esc(e.nome) + '.', ok: 'Tirar', perigo: true })) return;
  await ocupado(null, async () => {
    await Store.update('equipamentos', e.id, { docs: (e.docs || []).filter(x => x.id !== d.id), atualizadoEm: Date.now() });
    if (levSouNicolas() && LEVISSIMA.docs) LEVISSIMA.docs.apagar(d.caminho);
    toast('Documento tirado.');
  });
};

/* ---------- Peças ligadas a cada máquina ---------- */
// peça → máquinas: as marcadas no cadastro da peça, os elementos do equipamento e os planos (preventiva e lubrificação)
// o índice é refeito a cada gravação no banco (Store.on) e reaproveitado entre as linhas de uma mesma tela
Store.on(() => { LEV.ix = null; });
function levIndiceMaquinas() {
  if (LEV.ix) return LEV.ix;
  const ix = new Map();
  const add = (pid, eid) => { if (!pid || !eid) return; if (!ix.has(pid)) ix.set(pid, new Set()); ix.get(pid).add(eid); };
  for (const p of Store.all('pecas')) for (const eid of (Array.isArray(p.maquinas) ? p.maquinas : [])) add(p.id, eid);
  for (const x of Store.all('elementos')) add(x.pecaId, x.equipId);
  for (const x of Store.all('preventivas')) for (const it of (x.pecas || [])) add(it.pecaId, x.equipId);
  for (const x of Store.all('lubrificacao')) add(x.pecaId, x.equipId);
  LEV.ix = ix;
  return ix;
}
function levMaquinasDaPeca(p, ix) { return Array.from(((ix || levIndiceMaquinas()).get(p.id)) || []).map(eqDe).filter(Boolean); }
function levPecasDaMaquina(equipId, ix) {
  if (!equipId) return [];
  ix = ix || levIndiceMaquinas();
  return Store.all('pecas').filter(p => p.ativo !== false && ix.has(p.id) && ix.get(p.id).has(equipId)).sort((a, b) => byText(a.descricao, b.descricao));
}
function levNomesMaquinas(p) {
  return levMaquinasDaPeca(p).map(e => [e.nome, e.tag, linhaCurto(e.linha), linhaNome(e.linha)].join(' ')).join(' ');
}
function levFotoMini(p) {
  const f = (p.fotos || [])[0];
  return f ? '<img class="lev-mini" data-lev-foto="' + esc(f.caminho) + '" alt="">' : '';
}
function levPecaRow(p, ix) {
  const st = statusPeca(p);
  const maqs = levMaquinasDaPeca(p, ix);
  return '<div class="row clickable wrap-sm" data-act="peca" data-id="' + p.id + '" role="button" tabindex="0">' + levFotoMini(p) + '<span class="grow"><span class="t1" style="display:block">' + esc(p.descricao) + '</span>'
    + '<span class="t2" style="display:block"><span class="mono">' + esc(p.codigo || 'sem código') + '</span>' + [p.categoria, p.local].filter(Boolean).map(x => ' · ' + esc(x)).join('')
    + (maqs.length > 1 ? ' · em ' + maqs.length + ' máquinas' : '') + '</span></span>'
    + '<span class="side-r"><span class="saldo-n"><b>' + fmtNum(p.saldo) + '</b> ' + esc(p.unidade || '') + '</span><span class="tiny muted">mín ' + fmtNum(p.minimo || 0) + '</span>'
    + '<span class="acts">' + (st.cls !== 'ok' ? stPill(st) : '')
    + (podeEscrever() && p.ativo !== false ? '<button type="button" class="btn sm" data-act="mov" data-tipo="saida" data-id="' + p.id + '" aria-label="Saída de ' + esc(p.descricao) + '">− Saída</button><button type="button" class="btn sm" data-act="mov" data-tipo="entrada" data-id="' + p.id + '" aria-label="Entrada de ' + esc(p.descricao) + '">+ Entrada</button>' : '') + '</span></span></div>';
}
// Estoque › Por máquina: cada máquina com as peças dela (filtros e busca da tela valem aqui também)
function levPecasPorMaquina(v) {
  const ix = levIndiceMaquinas();
  const pecas = v.filtrar(Store.all('pecas'));
  const eqs = Store.all('equipamentos').sort((a, b) => ordemLinha(a.linha) - ordemLinha(b.linha) || (a.ordem || 999) - (b.ordem || 999) || byText(a.nome, b.nome));
  const comPecas = eqs.filter(e => Store.all('pecas').some(p => ix.has(p.id) && ix.get(p.id).has(e.id)));
  const sel = v.f.maq || '';
  let h = '<div class="toolbar"><select class="inp" style="width:auto;min-width:220px;max-width:100%" aria-label="Máquina" data-ch="lev-pc-maq">'
    + '<option value="">Todas as máquinas</option>'
    + LINHAS.map(l => { const g = comPecas.filter(e => e.linha === l.id); return g.length ? '<optgroup label="' + esc(l.nome) + '">' + g.map(e => '<option value="' + e.id + '"' + (e.id === sel ? ' selected' : '') + '>' + esc(e.nome + (e.tag ? ' · ' + e.tag : '')) + '</option>').join('') + '</optgroup>' : ''; }).join('')
    + '<option value="__sem"' + (sel === '__sem' ? ' selected' : '') + '>Peças sem máquina ligada</option></select>'
    + '<span class="small ink2">A máquina vem do cadastro da peça, dos elementos do equipamento e dos planos.</span></div>';
  let n = 0;
  for (const e of comPecas) {
    if (sel && sel !== e.id) continue;
    const g = pecas.filter(p => ix.has(p.id) && ix.get(p.id).has(e.id)).sort((a, b) => statusPeca(a).ord - statusPeca(b).ord || byText(a.descricao, b.descricao));
    if (!g.length) continue;
    n += g.length;
    h += '<div class="list" style="margin-bottom:14px"><div class="group-h">' + ltag(e.linha) + ' <button type="button" class="oslink" data-act="equip" data-id="' + e.id + '">' + esc(e.nome) + '</button>' + (e.tag ? ' <span class="mono small muted">' + esc(e.tag) + '</span>' : '') + ' · ' + g.length + ' ' + plural(g.length, 'peça') + '</div>'
      + g.map(p => levPecaRow(p, ix)).join('') + '</div>';
  }
  if (!sel || sel === '__sem') {
    const sem = pecas.filter(p => !ix.has(p.id)).sort((a, b) => byText(a.descricao, b.descricao));
    if (sem.length) { n += sem.length; h += '<div class="list" style="margin-bottom:14px"><div class="group-h">Sem máquina ligada · ' + sem.length + '</div>' + sem.slice(0, 200).map(p => levPecaRow(p, ix)).join('') + '</div>'; }
  }
  return h + (n ? '' : '<p class="ink2">Nenhuma peça ' + (sel ? 'ligada a esta máquina' : 'encontrada') + ' com esses filtros. Abra a peça › Editar › “Máquinas onde é usada” para ligar.</p>');
}
INP['lev-pc-maq'] = el => { const v = VIEWS.estoque; v.f.maq = el.value; v.update(); };
// bloco do equipamento: as peças do estoque desta máquina, com o saldo
function levPecasMaquinaHtml(e) {
  const l = levPecasDaMaquina(e.id);
  if (!l.length) return '';
  return '<div class="blk"><div class="blk-h"><h3>Peças do estoque desta máquina · ' + l.length + '</h3><button type="button" class="btn sm ghost" data-act="lev-ver-pecas" data-id="' + e.id + '">Ver no estoque</button></div><div class="list">'
    + l.slice(0, 30).map(p => { const st = statusPeca(p); return '<button type="button" class="row" data-act="peca" data-id="' + p.id + '">' + levFotoMini(p) + '<span class="grow"><span class="t1" style="display:block">' + esc(p.descricao) + '</span><span class="t2" style="display:block"><span class="mono">' + esc(p.codigo || 'sem código') + '</span>' + (p.local ? ' · ' + esc(p.local) : '') + '</span></span><span class="side-r">' + stPill({ cls: st.cls, txt: 'Saldo ' + fmtNum(p.saldo) + ' ' + (p.unidade || '') }) + '</span></button>'; }).join('')
    + '</div>' + (l.length > 30 ? '<p class="small muted" style="margin-top:6px">Mostrando 30 de ' + l.length + '.</p>' : '') + '</div>';
}
ACT['lev-ver-pecas'] = el => { Modal.closeAll(); go('estoque', { aba: 'maquina' }); const v = VIEWS.estoque; v.f.maq = el.dataset.id; v.update(); };
// cadastro da peça: máquinas onde é usada
function levCampoMaquinas(p) {
  const marc = new Set(Array.isArray(p.maquinas) ? p.maquinas : []);
  const eqs = Store.all('equipamentos').filter(e => e.ativo !== false || marc.has(e.id));
  if (!eqs.length) return '';
  return '<div class="field"><span class="flabel">Máquinas onde é usada <span class="small muted" style="font-weight:400">(' + marc.size + ' marcada' + (marc.size === 1 ? '' : 's') + ')</span></span>'
    + '<input class="inp" type="search" placeholder="Filtrar máquinas" data-in="lev-maq-busca" aria-label="Filtrar máquinas" style="margin-bottom:6px"><div class="lev-maqs">'
    + LINHAS.map(l => {
      const g = eqs.filter(e => e.linha === l.id).sort((a, b) => (a.ordem || 999) - (b.ordem || 999) || byText(a.nome, b.nome));
      return g.length ? '<div class="lev-maq-g"><div class="lev-maq-l">' + esc(l.nome) + '</div>' + g.map(e => '<label data-txt="' + esc(norm(e.nome + ' ' + (e.tag || '') + ' ' + l.nome + ' ' + l.curto)) + '"><input type="checkbox" name="maquinas[]" value="' + e.id + '"' + (marc.has(e.id) ? ' checked' : '') + '> ' + esc(e.nome) + (e.tag ? ' <span class="mono small muted">' + esc(e.tag) + '</span>' : '') + '</label>').join('') + '</div>' : '';
    }).join('') + '</div><span class="hint">Com a máquina marcada, a peça aparece em Estoque › Por máquina e na tela do equipamento.</span></div>';
}
INP['lev-maq-busca'] = el => {
  const q = norm(el.value), box = el.parentElement.querySelector('.lev-maqs'); if (!box) return;
  $$('label[data-txt]', box).forEach(l => { l.hidden = !!q && !l.dataset.txt.includes(q); });
  $$('.lev-maq-g', box).forEach(g => { g.hidden = !$$('label[data-txt]', g).some(l => !l.hidden); });
};
// planilha de peças: coluna "Máquina" (uma ou mais, separadas por vírgula, ponto e vírgula ou /)
function levMaquinasDaCelula(v, ex) {
  const ids = new Set(ex && Array.isArray(ex.maquinas) ? ex.maquinas : []);
  const ix = Store.all('equipamentos');
  String(txtCel(v) || '').split(/[;,\/|\n]+/).map(s => s.trim()).filter(Boolean).forEach(t => { const e = acharEquip(ix, t, null); if (e) ids.add(e.id); });
  return Array.from(ids);
}

/* ---------- Fotos da peça ---------- */
function levFotosPecaHtml(p) {
  const f = Array.isArray(p.fotos) ? p.fotos : [];
  const maqs = Array.isArray(p.maquinas) ? p.maquinas.map(eqDe).filter(Boolean) : [];
  let h = '<div class="blk"><div class="blk-h"><h3>Fotos · ' + f.length + '</h3></div>'
    + (f.length ? '<div class="lev-fotos">' + f.map((x, i) => '<span class="lev-ft"><img data-lev-foto="' + esc(x.caminho) + '" alt="Foto ' + (i + 1) + ' de ' + esc(p.descricao) + '">'
      + (podeEscrever() ? '<button type="button" class="lev-ft-x" data-act="lev-pc-foto-tirar" data-id="' + p.id + '" data-i="' + i + '" aria-label="Tirar a foto ' + (i + 1) + '">×</button>' : '') + '</span>').join('') + '</div>' : '<p class="small ink2">Sem foto. Uma foto ajuda a achar a peça certa na hora.</p>')
    + (podeEscrever() && f.length < 4 && window.LEVISSIMA && LEVISSIMA.fotos ? '<label class="btn sm lev-ft-add" style="margin-top:8px">📷 ' + (f.length ? 'Outra foto' : 'Tirar ou escolher foto') + '<input type="file" accept="image/*" data-ch="lev-pc-foto" data-id="' + p.id + '" hidden></label>' : '')
    + '</div>';
  if (maqs.length) h += '<div class="blk"><h3>Máquinas marcadas · ' + maqs.length + '</h3><div class="list">' + maqs.map(e => '<button type="button" class="row" data-act="equip" data-id="' + e.id + '">' + ltag(e.linha) + '<span class="grow"><span class="t1" style="display:block">' + esc(e.nome) + '</span><span class="t2 mono" style="display:block">' + esc(e.tag || 'sem TAG') + '</span></span></button>').join('') + '</div></div>';
  return h;
}
INP['lev-pc-foto'] = async el => {
  const arq = el.files && el.files[0], p = Store.get('pecas', el.dataset.id);
  if (!arq || !p || !window.LEVISSIMA || !LEVISSIMA.fotos) return;
  const lbl = el.closest('label'); if (lbl) lbl.classList.add('disabled');
  try {
    const blob = await LEVISSIMA.fotos.preparar(arq);
    const caminho = await LEVISSIMA.fotos.enviar(blob, 'pecas');
    const atual = Store.get('pecas', p.id) || p;
    await Store.update('pecas', p.id, { fotos: (Array.isArray(atual.fotos) ? atual.fotos : []).concat([{ caminho, em: Date.now(), por: nomeUsuario() || '' }]).slice(0, 4), atualizadoEm: Date.now() });
    toast('Foto guardada.');
  } catch (e) { console.error('foto da peça', e); toast((e && e.message) || 'Não foi possível guardar a foto.', 'crit'); }
  finally { el.value = ''; if (lbl) lbl.classList.remove('disabled'); }
};
ACT['lev-pc-foto-tirar'] = async el => {
  const p = Store.get('pecas', el.dataset.id), i = +el.dataset.i; if (!p) return;
  if (!await confirmar({ titulo: 'Tirar a foto?', texto: 'A foto ' + (i + 1) + ' sai do cadastro de ' + esc(p.descricao) + '.', ok: 'Tirar', perigo: true })) return;
  await ocupado(null, () => Store.update('pecas', p.id, { fotos: (p.fotos || []).filter((x, k) => k !== i), atualizadoEm: Date.now() }));
};

/* ---------- Materiais usados no chamado ---------- */
function levMateriaisDoChamado(c) {
  return (Array.isArray(c.materiais) ? c.materiais : []).map(m => ({ pecaId: m.pecaId, codigo: m.codigo || '', descricao: m.descricao || '', qtd: m.qtd, un: m.un || 'un', noAtendimento: true }));
}
function levMatTexto(m) { return fmtNum(m.qtd) + ' ' + (m.un || '') + ' · ' + (m.codigo ? m.codigo + ' ' : '') + (m.descricao || ''); }
function levMateriaisHtml(c) {
  const l = Array.isArray(c.materiais) ? c.materiais : [];
  if (!l.length || c.status === 'concluido') return '';
  return '<div class="blk"><h3>Materiais usados · ' + l.length + '</h3><div>' + l.map(m => '<div class="lev-mat"><span class="grow"><b>' + esc(levMatTexto(m)) + '</b><span class="small muted" style="display:block">' + esc(m.por || '—') + ' · ' + fmtDHc(m.em) + ' · baixado do estoque</span></span></div>').join('') + '</div></div>';
}
// chips "peças desta máquina": um toque põe a peça na lista
function levChipsPecas(equipId, prefix) {
  const l = levPecasDaMaquina(equipId);
  if (!l.length) return '';
  return '<div class="field"><span class="flabel">Peças desta máquina <span class="small muted" style="font-weight:400">(toque para pôr na lista)</span></span><div class="lev-chips-maq">'
    + l.slice(0, 24).map(p => '<button type="button" class="chip" data-act="lev-peca-maq" data-dl="dl-' + prefix + '" data-id="' + p.id + '">+ ' + esc(cap(p.descricao, 34)) + ' <span class="small muted">' + fmtNum(p.saldo) + ' ' + esc(p.unidade || '') + '</span></button>').join('') + '</div></div>';
}
ACT['lev-peca-maq'] = el => {
  const form = el.closest('form'); if (!form) return;
  const box = $('[data-prows]', form); if (!box) return;
  const p = Store.get('pecas', el.dataset.id); if (!p) return;
  const ja = $$('input[name="pecaTxt[]"]', box).find(i => acharPeca(i.value) && acharPeca(i.value).id === p.id);
  if (ja) { const q = ja.closest('[data-prow]').querySelector('input[name="pecaQtd[]"]'); if (q) { q.value = fmtNum((parseNumBR(q.value) || 0) + 1); q.focus(); } return; }
  const vazia = $$('input[name="pecaTxt[]"]', box).find(i => !i.value.trim());
  if (vazia) vazia.closest('[data-prow]').remove();
  box.insertAdjacentHTML('beforeend', pecaRow(el.dataset.dl, { pecaId: p.id, qtd: 1 }));
};
function levMateriaisJa(c) {
  const l = Array.isArray(c.materiais) ? c.materiais : [];
  return l.length ? '<div class="field"><span class="flabel">Já lançados no atendimento</span><div class="small ink2">' + l.map(m => esc(levMatTexto(m))).join('<br>') + '</div><span class="hint">Já saíram do estoque. Abaixo, só o que faltou lançar.</span></div>' : '';
}
ACT['lev-mat'] = el => {
  const c = Store.get('chamados', el.dataset.id); if (!c) return;
  const ll = Array.isArray(c.materiais) ? c.materiais : [];
  const temChips = levPecasDaMaquina(c.equipId).length > 0;
  Modal.open({
    title: 'Materiais · chamado #' + num4(c.n), wide: true,
    html: '<form class="form" data-form="lev-mat" id="f-lev-mat" data-id="' + c.id + '"><p class="ink2"><b>' + esc(eqNome(c)) + '</b> · ' + esc(cap(c.descricao, 120)) + '</p>'
      + '<p class="small ink2">Lance aqui o que for usado no atendimento: a quantidade sai do estoque na hora e o material fica no chamado.</p>'
      + (ll.length ? '<div class="field"><span class="flabel">Já lançados · ' + ll.length + '</span><div>' + ll.map((m, i) => '<div class="lev-mat"><span class="grow"><b>' + esc(levMatTexto(m)) + '</b><span class="small muted" style="display:block">' + esc(m.por || '—') + ' · ' + fmtDHc(m.em) + '</span></span>'
        + (fechado(c) ? '' : '<button type="button" class="btn sm" data-act="lev-mat-devolver" data-id="' + c.id + '" data-i="' + i + '">Devolver ao estoque</button>') + '</div>').join('') + '</div></div>' : '')
      + levChipsPecas(c.equipId, 'mt') + pecasEditor('mt', temChips ? [] : [{ qtd: 1 }]) + '</form>',
    foot: '<button type="button" class="btn" data-close>Fechar</button><button type="submit" class="btn pri" form="f-lev-mat">' + ico('check', 'sm') + ' Lançar e baixar do estoque</button>'
  });
};
FORMS['lev-mat'] = async (f, btn) => {
  const c = Store.get('chamados', f.dataset.id); if (!c) return;
  let pecas; try { pecas = lerPecas(f); } catch (e) { return toast(e.message, 'crit'); }
  if (!pecas.length) return toast('Escolha a peça e a quantidade.', 'crit');
  for (const p of pecas) {
    const pc = Store.get('pecas', p.pecaId);
    if (pc && (+pc.saldo || 0) < p.qtd) {
      const ok = await confirmar({ titulo: 'Saldo insuficiente', texto: esc(pecaLabel(pc)) + ' tem saldo de ' + fmtNum(pc.saldo) + ' ' + esc(pc.unidade || '') + '. Lançar mesmo assim? O saldo fica negativo até a entrada ser lançada.', ok: 'Lançar mesmo assim' });
      if (!ok) return;
    }
  }
  await ocupado(btn, async () => {
    const por = nomeUsuario() || c.tecnico || '', agora = Date.now(), feitos = [], falhas = [];
    for (const p of pecas) {
      try { await Store.moverEstoque({ pecaId: p.pecaId, tipo: 'saida', qtd: p.qtd, por, origem: { tipo: 'chamado', id: c.id, n: c.n }, obs: 'Chamado #' + num4(c.n) }); feitos.push(Object.assign({}, p, { em: agora, por })); }
      catch (e) { falhas.push(p.descricao || p.codigo); }
    }
    if (feitos.length) {
      const atual = Store.get('chamados', c.id) || c;
      await Store.update('chamados', c.id, { materiais: (Array.isArray(atual.materiais) ? atual.materiais : []).concat(feitos), atualizadoEm: Date.now(),
        eventos: comEvento(atual, evento('material', 'Material usado: ' + feitos.map(levMatTexto).join('; '), por)) });
      Modal.close();
      toast(feitos.length + ' ' + plural(feitos.length, 'material lançado', 'materiais lançados') + ' e baixado' + (feitos.length === 1 ? '' : 's') + ' do estoque.');
    }
    if (falhas.length) toast('Não deu para baixar do estoque: ' + falhas.join(', ') + '.', 'crit');
  }, 'Lançando…');
};
ACT['lev-mat-devolver'] = async el => {
  const c = Store.get('chamados', el.dataset.id), i = +el.dataset.i; if (!c) return;
  const m = (c.materiais || [])[i]; if (!m) return;
  if (!await confirmar({ titulo: 'Devolver ao estoque?', texto: esc(levMatTexto(m)) + ' volta para o estoque (entrada) e sai da lista do chamado.', ok: 'Devolver' })) return;
  await ocupado(null, async () => {
    if (Store.get('pecas', m.pecaId)) await Store.moverEstoque({ pecaId: m.pecaId, tipo: 'entrada', qtd: m.qtd, por: nomeUsuario() || '', origem: { tipo: 'chamado', id: c.id, n: c.n }, obs: 'Devolução · chamado #' + num4(c.n) });
    const atual = Store.get('chamados', c.id) || c;
    await Store.update('chamados', c.id, { materiais: (atual.materiais || []).filter((x, k) => k !== i), atualizadoEm: Date.now(), eventos: comEvento(atual, evento('material', 'Material devolvido ao estoque: ' + levMatTexto(m))) });
    Modal.close();
    toast('Devolvido ao estoque.');
    ACT['lev-mat']({ dataset: { id: c.id } });
  });
};

/* ---------- Rodapé do chamado: materiais (manutenção) e apagar (só o Nicolas) ---------- */
function levRodapeChamado(c, out, b) {
  if (ehManutencao() && (c.status === 'atendimento' || c.status === 'aguardando')) {
    const i = out.findIndex(x => x.indexOf('data-act="os-concluir"') >= 0);
    const n = (c.materiais || []).length;
    const bt = b('lev-mat', '', 'box', 'Materiais' + (n ? ' (' + n + ')' : ''));
    if (i >= 0) out.splice(i, 0, bt); else out.push(bt);
  }
  if (levSouNicolas()) out.unshift(b('os-apagar', 'ghost lev-perigo', 'trash', 'Apagar'));
}
ACT['os-apagar'] = async el => {
  const c = acharChamado(el.dataset.id); if (!c) return;
  if (!levSouNicolas()) return toast('Só a senha mestre apaga chamados.', 'crit');
  const n = (c.materiais || []).length + ((c.solucao && c.solucao.pecas) || []).length;
  const ok = await confirmar({ titulo: 'Apagar o chamado #' + num4(c.n) + '?', perigo: true, ok: 'Apagar de vez',
    texto: 'O chamado <b>#' + num4(c.n) + ' · ' + esc(eqNome(c)) + '</b> sai do sistema de vez: não fica no histórico nem no arquivo.' + (n ? ' As baixas de peças já lançadas no estoque continuam.' : '') + (c.status === 'aberto' ? ' Se foi aberto por engano, “Cancelar” guarda o registro.' : '') });
  if (!ok) return;
  await ocupado(null, async () => { await Store.del('chamados', c.id); Modal.closeAll(); toast('Chamado #' + num4(c.n) + ' apagado.'); });
};

/* ---------- Selecionar vários e excluir de uma vez ---------- */
const LEV_SEL_CFG = {
  equipamentos: { col: 'equipamentos', row: '#eq-body .row[data-act="equip"][data-id]', um: 'equipamento', varios: 'equipamentos' },
  estoque: { col: 'pecas', row: '#pc-body .row[data-act="peca"][data-id]', um: 'peça', varios: 'peças', abas: ['saldo', 'maquina'] },
  preventiva: { col: 'preventivas', row: '#pl-body .row[data-act="plano"][data-id]', um: 'tarefa', varios: 'tarefas', abas: ['lista'] },
  lubrificacao: { col: 'lubrificacao', row: '#pl-body .row[data-act="plano"][data-id]', um: 'ponto', varios: 'pontos', abas: ['lista'] },
  ferramentas: { col: 'ferramentas', row: '#fr-body .row[data-act="ferr"][data-id]', um: 'ferramenta', varios: 'ferramentas' },
  chamados: { col: 'chamados', row: '#kb-board .tag[data-act="os"][data-id]', um: 'chamado', varios: 'chamados', so: levSouNicolas }
};
function levSelPode(v) { const c = LEV_SEL_CFG[v]; return !!c && podeEscrever() && (!c.so || c.so()); }
function levSelNome(cfg, x) {
  if (cfg.col === 'chamados') return '#' + num4(x.n) + ' · ' + eqNome(x);
  if (cfg.col === 'equipamentos') return x.nome + (x.tag ? ' (' + x.tag + ')' : '');
  if (cfg.col === 'pecas' || cfg.col === 'ferramentas') return (x.codigo ? x.codigo + ' · ' : '') + (x.descricao || '');
  if (cfg.col === 'lubrificacao') return (x.ponto || '') + (eqDe(x.equipId) ? ' · ' + eqDe(x.equipId).nome : '');
  return (x.titulo || '') + (eqDe(x.equipId) ? ' · ' + eqDe(x.equipId).nome : '');
}
function levSelBotao(v, el) {
  if (!levSelPode(v)) return;
  const row = $('.page-head .btn-row', el); if (!row) return;
  const html = '<button type="button" class="btn" data-act="lev-sel" data-v="' + v + '">' + ico('check', 'sm') + ' Selecionar</button>';
  const pri = $('.btn.pri', row);
  if (pri) pri.insertAdjacentHTML('beforebegin', html); else row.insertAdjacentHTML('beforeend', html);
}
function levSelAtivo(v) { return LEV.sel.view === v && UI.view === v; }
function levSelDecorar(v) {
  if (!levSelAtivo(v)) return;
  const cfg = LEV_SEL_CFG[v], V = VIEWS[v];
  document.body.classList.add('lev-sel-on');
  const abaOk = !cfg.abas || cfg.abas.includes(V.f && V.f.aba);
  const vivos = new Set(Store.all(cfg.col).map(x => x.id));
  for (const id of Array.from(LEV.sel.ids)) if (!vivos.has(id)) LEV.sel.ids.delete(id);
  if (abaOk) $$(cfg.row).forEach(r => {
    if (r.hasAttribute('data-lev-sel')) return;
    r.setAttribute('data-lev-sel', r.dataset.id);
    r.setAttribute('aria-pressed', LEV.sel.ids.has(r.dataset.id) ? 'true' : 'false');
    r.insertAdjacentHTML('afterbegin', '<span class="lev-ck" aria-hidden="true">✓</span>');
  });
  levSelBarra(v, abaOk);
}
function levSelBarra(v, abaOk) {
  const cfg = LEV_SEL_CFG[v];
  let bar = $('#lev-selbar');
  if (!bar) { bar = document.createElement('div'); bar.id = 'lev-selbar'; bar.className = 'lev-selbar'; bar.setAttribute('role', 'region'); bar.setAttribute('aria-label', 'Seleção'); $('#view').appendChild(bar); }
  const n = LEV.sel.ids.size;
  bar.innerHTML = '<b>' + (abaOk ? n + ' ' + (n === 1 ? cfg.um + ' selecionad' + (/a$/.test(cfg.um) ? 'a' : 'o') : cfg.varios + ' selecionad' + (/as$/.test(cfg.varios) ? 'as' : 'os')) : 'Seleção só na lista') + '</b>'
    + (abaOk ? '<button type="button" class="btn sm" data-act="lev-sel-todos">Todos da tela</button>' : '')
    + '<button type="button" class="btn sm" data-act="lev-sel-sair">Cancelar</button>'
    + (abaOk ? '<button type="button" class="btn sm danger" data-act="lev-sel-excluir"' + (n ? '' : ' disabled') + '>' + ico('trash', 'sm') + ' Excluir</button>' : '');
}
function levSelSair() {
  LEV.sel.view = null; LEV.sel.ids.clear();
  document.body.classList.remove('lev-sel-on');
  const bar = $('#lev-selbar'); if (bar) bar.remove();
  $$('[data-lev-sel]').forEach(r => { r.removeAttribute('data-lev-sel'); r.removeAttribute('aria-pressed'); const k = $('.lev-ck', r); if (k) k.remove(); });
}
ACT['lev-sel'] = el => {
  const v = el.dataset.v;
  if (LEV.sel.view === v) { levSelSair(); return; }
  levSelSair(); LEV.sel.view = v;
  levSelDecorar(v);
  toast('Toque nos itens para marcar. Depois, “Excluir”.');
};
ACT['lev-sel-sair'] = () => levSelSair();
ACT['lev-sel-todos'] = () => {
  const v = LEV.sel.view; if (!v) return;
  const rs = $$(LEV_SEL_CFG[v].row);
  const todos = rs.length && rs.every(r => LEV.sel.ids.has(r.dataset.id));
  rs.forEach(r => { if (todos) LEV.sel.ids.delete(r.dataset.id); else LEV.sel.ids.add(r.dataset.id); r.setAttribute('aria-pressed', todos ? 'false' : 'true'); });
  levSelBarra(v, true);
};
// no modo seleção, tocar na linha marca/desmarca (não abre o item nem os botões da linha)
document.addEventListener('click', e => {
  const v = LEV.sel.view; if (!v || UI.view !== v) return;
  const r = e.target.closest && e.target.closest('[data-lev-sel]');
  if (!r || e.target.closest('.dlg')) return;
  e.preventDefault(); e.stopPropagation();
  const id = r.dataset.id;
  if (LEV.sel.ids.has(id)) LEV.sel.ids.delete(id); else LEV.sel.ids.add(id);
  r.setAttribute('aria-pressed', LEV.sel.ids.has(id) ? 'true' : 'false');
  levSelBarra(v, true);
}, true);
ACT['lev-sel-excluir'] = async () => {
  const v = LEV.sel.view; if (!v) return;
  const cfg = LEV_SEL_CFG[v];
  const itens = Array.from(LEV.sel.ids).map(id => Store.get(cfg.col, id)).filter(Boolean);
  if (!itens.length) return;
  if (cfg.so && !cfg.so()) return toast('Só a senha mestre apaga chamados.', 'crit');
  let guardar = [], apagar = itens, extra = '';
  if (cfg.col === 'equipamentos') {
    // equipamento com chamados ou planos não some (o histórico fica): vai para "fora de uso"
    const temHist = e => Store.all('preventivas').some(p => p.equipId === e.id) || Store.all('lubrificacao').some(p => p.equipId === e.id) || chamadosTodos().some(c => c.equipId === e.id);
    guardar = itens.filter(temHist); apagar = itens.filter(e => !temHist(e));
    if (guardar.length) extra = ' ' + guardar.length + ' ' + plural(guardar.length, 'tem', 'têm') + ' chamados ou planos e ' + plural(guardar.length, 'fica', 'ficam') + ' como fora de uso, para não perder o histórico.';
  }
  if (cfg.col === 'pecas') { const ix = levIndiceMaquinas(); const lig = itens.filter(p => ix.has(p.id)).length; if (lig) extra = ' ' + lig + ' ' + plural(lig, 'está ligada', 'estão ligadas') + ' a máquinas ou planos e o vínculo será perdido.'; }
  if (cfg.col === 'chamados') extra = ' Os chamados saem de vez (não ficam no histórico nem no arquivo).';
  const lista = itens.slice(0, 8).map(x => '• ' + esc(levSelNome(cfg, x))).join('<br>') + (itens.length > 8 ? '<br>… e mais ' + (itens.length - 8) : '');
  const ok = await confirmar({ titulo: 'Excluir ' + itens.length + ' ' + (itens.length === 1 ? cfg.um : cfg.varios) + '?', perigo: true, ok: 'Excluir ' + itens.length,
    texto: lista + '<br><br>' + (extra ? extra.trim() + ' ' : '') + 'Não dá para desfazer.' });
  if (!ok) return;
  await ocupado(null, async () => {
    const erros = await emLote(apagar, 3, async x => {
      if (cfg.col === 'equipamentos') for (const el of Store.all('elementos').filter(y => y.equipId === x.id)) await Store.del('elementos', el.id);
      await Store.del(cfg.col, x.id);
    });
    const errosG = guardar.length ? await emLote(guardar, 3, x => Store.update('equipamentos', x.id, { ativo: false, atualizadoEm: Date.now() })) : [];
    const nOk = apagar.length - erros.length;
    levSelSair();
    toast((nOk ? nOk + ' ' + (nOk === 1 ? cfg.um + ' excluíd' + (/a$/.test(cfg.um) ? 'a' : 'o') : cfg.varios + ' excluíd' + (/as$/.test(cfg.varios) ? 'as' : 'os')) : 'Nada excluído')
      + (guardar.length - errosG.length ? ' · ' + (guardar.length - errosG.length) + ' fora de uso' : '') + '.', erros.length || errosG.length ? 'crit' : '');
    if (erros.length || errosG.length) toast((erros.length + errosG.length) + ' não ' + plural(erros.length + errosG.length, 'pôde', 'puderam') + ' ser alterados: ' + ((erros[0] || errosG[0]).msg || 'erro'), 'crit');
  }, 'Excluindo…');
};
Object.keys(LEV_SEL_CFG).forEach(v => {
  const V = VIEWS[v]; if (!V) return;
  const m0 = V.mount, u0 = V.update;
  V.mount = function (el, p) { levSelSair(); const r = m0.call(this, el, p); levSelBotao(v, el); return r; };
  V.update = function () { const r = u0.apply(this, arguments); try { levSelDecorar(v); } catch (e) { console.error(e); } return r; };
});
