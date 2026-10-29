#!/usr/bin/env python3
"""Monta as páginas dos módulos do LEVÍSSIMA a partir dos programas originais.

Uso: python3 montar.py <pasta de saída (www)> [url anonKey]

- Manutenção, Uniformes e EPI e Estoque de garrafões: o programa original, sem mudar o funcionamento,
  com a "ponte" (login + banco do LEVÍSSIMA) carregada antes de tudo e os textos que falavam do Claude
  trocados por textos do LEVÍSSIMA.
- Checklist de empilhadeiras: módulo novo (empilhadeiras.html), escrito para o LEVÍSSIMA.
- ponte.js: com a configuração do Supabase preenchida (se informada).
- Fundo claro sempre (pedido de 16/10/2026): o tema escuro automático dos módulos fica desligado.
"""
import os
import re
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
SUPABASE_JS = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js'

# Manutenção, pedido de 17/10/2026:
# - quem abre o chamado é identificado pelo próprio acesso ao LEVÍSSIMA (nome, função e turno, via ponte.js →
#   window.LEV_QUEM); não pede mais nome e setor (sem acesso identificado, continua pedindo como antes);
# - opção de tirar até 3 fotos do ocorrido ao abrir o chamado (bucket privado "modulos-fotos"); as fotos aparecem no
#   chamado e o cartão do kanban mostra 📷.
TROCAS_MANUTENCAO_1710 = [
    ("function perfil() { return Perfil.get() || { setor: '', nome: '' }; }",
     "function perfil() { const q = window.LEV_QUEM; if (q && q.nome) return { nome: q.nome, setor: q.setor || q.funcao || '', funcao: q.funcao || '', turno: q.turno || '', auto: true }; return Perfil.get() || { setor: '', nome: '' }; }"),
    ("""      + '<div class="step"><div class="step-h"><span class="n">5</span>Quem está abrindo</div><div class="frow">'
      + fSel('ab-setor', 'Setor', opts(SETORES, s.setor, 'Escolha'), { name: 'setor', req: true })
      + fText('ab-nome', 'Nome', s.nome, { name: 'nome', req: true, ph: 'Seu nome', attrs: 'autocomplete="name"' }) + '</div></div>'""",
     """      + '<div class="step"><div class="step-h"><span class="n">5</span>Foto do ocorrido <span class="small ink2" style="font-weight:400">(opcional, até 3)</span></div><div class="lev-ab-fotos" id="ab-fotos">' + this.fotosHtml() + '</div></div>'
      + (perfil().auto
        ? '<div class="step"><div class="step-h"><span class="n">6</span>Quem está abrindo</div><div class="lev-quem"><b>' + esc(perfil().nome) + '</b>' + (perfil().funcao ? '<span>' + esc(perfil().funcao) + '</span>' : '') + (perfil().turno ? '<span>Turno: ' + esc(perfil().turno) + '</span>' : '') + '<span class="small">identificado pelo seu acesso</span></div></div>'
        : '<div class="step"><div class="step-h"><span class="n">6</span>Quem está abrindo</div><div class="frow">'
          + fSel('ab-setor', 'Setor', opts(SETORES, s.setor, 'Escolha'), { name: 'setor', req: true })
          + fText('ab-nome', 'Nome', s.nome, { name: 'nome', req: true, ph: 'Seu nome', attrs: 'autocomplete="name"' }) + '</div></div>')"""),
    ("    this.el = el; this.ok = null;", "    this.el = el; this.ok = null; this.fotos = [];"),
    ("  hintPrio() {\n",
     """  fotosHtml() {
    const f = this.fotos || [];
    return f.map((x, i) => '<span class="lev-ft"><img src="' + x.url + '" alt="Foto ' + (i + 1) + '"><button type="button" class="lev-ft-x" data-act="ab-foto-del" data-i="' + i + '" aria-label="Tirar a foto ' + (i + 1) + '">×</button></span>').join('')
      + (f.length < 3 ? '<label class="btn lev-ft-add">📷 ' + (f.length ? 'Outra foto' : 'Tirar foto') + '<input type="file" accept="image/*" capture="environment" data-ch="ab-foto" hidden></label>' : '');
  },
  renderFotos() { const b = $('#ab-fotos', this.el); if (b) b.innerHTML = this.fotosHtml(); },
  hintPrio() {
"""),
    ("INP['ab-outro'] = el => { const v = VIEWS.abrir; v.st.outro = el.value; v.salvarRascunho(); };",
     """INP['ab-outro'] = el => { const v = VIEWS.abrir; v.st.outro = el.value; v.salvarRascunho(); };
INP['ab-foto'] = async el => {
  const v = VIEWS.abrir, arq = el.files && el.files[0];
  if (!arq || !window.LEVISSIMA || !LEVISSIMA.fotos) return;
  try {
    const blob = await LEVISSIMA.fotos.preparar(arq);
    v.fotos = (v.fotos || []).concat([{ blob, url: URL.createObjectURL(blob) }]).slice(0, 3);
    v.renderFotos();
  } catch (e) { console.error('foto', e); toast('Não foi possível usar essa foto.', 'crit'); }
};
ACT['ab-foto-del'] = el => { const v = VIEWS.abrir, i = +el.dataset.i, x = (v.fotos || [])[i]; if (x) { URL.revokeObjectURL(x.url); v.fotos.splice(i, 1); } v.renderFotos(); };"""),
    ("  s.descricao = d.descricao; s.setor = d.setor; s.nome = d.nome; if (d.outro != null) s.outro = d.outro;",
     "  const q = perfil(); s.descricao = d.descricao; if (q.auto) { s.nome = q.nome; s.setor = q.setor || q.funcao || 'Não informado'; } else { s.setor = d.setor; s.nome = d.nome; } if (d.outro != null) s.outro = d.outro;"),
    ("""  await ocupado(btn, async () => {
    const c = await OS.abrir({
      linha: s.linha, equipId: s.equipId === '__outro' ? null : s.equipId, equipNome: s.equipId === '__outro' ? s.outro : null,
      prioridade: +s.prioridade, parada: s.parada, tipo: s.tipo || 'Outro', descricao: s.descricao, nome: s.nome, setor: s.setor
    });
    v.ok = c; LS.del('lev.rascunho'); v.render(); window.scrollTo(0, 0);
    toast('Chamado #' + num4(c.n) + ' aberto.');""",
     """  await ocupado(btn, async () => {
    const fotos = []; let semFoto = false;
    for (const x of (v.fotos || [])) { try { fotos.push({ caminho: await LEVISSIMA.fotos.enviar(x.blob, 'chamados'), em: Date.now(), por: s.nome }); } catch (e) { semFoto = true; console.error('foto', e); } }
    const c = await OS.abrir({
      linha: s.linha, equipId: s.equipId === '__outro' ? null : s.equipId, equipNome: s.equipId === '__outro' ? s.outro : null,
      prioridade: +s.prioridade, parada: s.parada, tipo: s.tipo || 'Outro', descricao: s.descricao, nome: s.nome, setor: s.setor,
      funcao: q.funcao || '', turno: q.turno || '', fotos
    });
    (v.fotos || []).forEach(x => URL.revokeObjectURL(x.url)); v.fotos = [];
    v.ok = c; LS.del('lev.rascunho'); v.render(); window.scrollTo(0, 0);
    toast('Chamado #' + num4(c.n) + ' aberto.' + (fotos.length ? ' Com ' + fotos.length + (fotos.length === 1 ? ' foto.' : ' fotos.') : ''));
    if (semFoto) toast('Uma foto não foi enviada (sem internet?). O chamado foi aberto sem ela.', 'crit');"""),
    ("      solicitante: { nome: d.nome || '', setor: d.setor || '' }, abertoEm: agora, abertoPorId: Store.uid || null,",
     "      solicitante: { nome: d.nome || '', setor: d.setor || '', funcao: d.funcao || '', turno: d.turno || '' }, abertoEm: agora, abertoPorId: Store.uid || null, fotos: d.fotos || [],"),
    ("""  h += '<div class="blk"><h3>Problema relatado</h3><div class="quote">' + esc(c.descricao) + '</div><p class="small ink2" style="margin-top:6px">Por ' + esc((c.solicitante && c.solicitante.nome) || '—') + (c.solicitante && c.solicitante.setor ? ' · ' + esc(c.solicitante.setor) : '') + (c.tecnico ? ' · Técnico: ' + esc(c.tecnico) : '') + '</p></div>';""",
     """  h += '<div class="blk"><h3>Problema relatado</h3><div class="quote">' + esc(c.descricao) + '</div>' + ((c.fotos || []).length ? '<div class="lev-fotos">' + c.fotos.map((f, i) => '<img data-lev-foto="' + esc(f.caminho) + '" alt="Foto ' + (i + 1) + ' do ocorrido">').join('') + '</div>' : '') + '<p class="small ink2" style="margin-top:6px">Por ' + esc((c.solicitante && c.solicitante.nome) || '—') + (c.solicitante && c.solicitante.funcao ? ' · ' + esc(c.solicitante.funcao) : (c.solicitante && c.solicitante.setor ? ' · ' + esc(c.solicitante.setor) : '')) + (c.solicitante && c.solicitante.turno ? ' · turno ' + esc(c.solicitante.turno) : '') + (c.tecnico ? ' · Técnico: ' + esc(c.tecnico) : '') + '</p></div>';"""),
    ("""'<span class="meta">' + esc(eqTag(c) || 'sem tag') + ' · ' + esc(c.tipo || '') + '</span>'""",
     """'<span class="meta">' + esc(eqTag(c) || 'sem tag') + ' · ' + esc(c.tipo || '') + ((c.fotos || []).length ? ' · 📷 ' + c.fotos.length : '') + '</span>'"""),
    ("""'<dl class="kv"><dt>Quem usa</dt><dd>' + (p.nome ? esc(p.nome) + ' · ' + esc(p.setor) : 'não identificado') + ' <button type="button" class="btn sm ghost" data-act="perfil">Trocar</button></dd>'""",
     """'<dl class="kv"><dt>Quem usa</dt><dd>' + (p.nome ? esc(p.nome) + ' · ' + esc(p.setor) : 'não identificado') + (p.auto ? ' <span class="small muted">(pelo acesso ao LEVÍSSIMA)</span>' : ' <button type="button" class="btn sm ghost" data-act="perfil">Trocar</button>') + '</dd>'"""),
]

# Manutenção, pedido de 20/10/2026: fichas de manutenção preventiva em planilha (modelo: a ficha da Enchedora da
# Linha 1). O código novo fica em manutencao-fichas.js (inserido antes da inicialização) e estas trocas ligam a
# ficha ao resto do módulo:
# - coleção "fichas" e a tela "Fichas de preventiva" no menu (seção Planos);
# - equipamento e tarefa do plano mostram a ficha (método, fornecedor, quantidade, nº de controle);
# - a execução da preventiva grava o resultado O (normal) ou X (anormal), como na ficha (X pede a observação);
# - registrar uma execução antiga (ex.: mês passado, pela ficha) não faz a "última execução" voltar no tempo;
# - "a cada 2 anos" na periodicidade.
TROCAS_MANUTENCAO_FICHAS = [
    ("const COLS = ['equipamentos', 'elementos', 'chamados', 'preventivas', 'lubrificacao', 'pecas', 'movimentos', 'ferramentas', 'config'];",
     "const COLS = ['equipamentos', 'elementos', 'chamados', 'preventivas', 'lubrificacao', 'pecas', 'movimentos', 'ferramentas', 'config', 'fichas'];"),
    ("  { id: 'preventiva', nome: 'Preventiva', ico: 'calendar', sec: 'Planos' },",
     "  { id: 'preventiva', nome: 'Preventiva', ico: 'calendar', sec: 'Planos' },\n"
     "  { id: 'fichas', nome: 'Fichas de preventiva e lubrificação', curto: 'Fichas', ico: 'list', sec: 'Planos' },"),
    ("  h += '<div class=\"blk\"><div class=\"blk-h\"><h3>Preventiva · ' + prev.length",
     "  h += fichasDoEquipHtml(e);\n  h += '<div class=\"blk\"><div class=\"blk-h\"><h3>Preventiva · ' + prev.length"),
    ("      if (p.descricao || p.obs) h += '<div class=\"blk\"><h3>Instruções</h3>",
     "      h += fichaBlocoPlano(p, col);\n      if (p.descricao || p.obs) h += '<div class=\"blk\"><h3>Instruções</h3>"),
    ("  hist.push({ data: d.data, horas: d.horas == null ? null : d.horas, por: d.por || nomeUsuario(), obs: d.obs || '', pecas: d.pecas || [], prevista: st.proxima || null, t: Date.now(), checklist: d.checklist || null });",
     "  hist.push({ data: d.data, horas: d.horas == null ? null : d.horas, por: d.por || nomeUsuario(), obs: d.obs || '', pecas: d.pecas || [], prevista: st.proxima || null, t: Date.now(), checklist: d.checklist || null, resultado: d.resultado || null });\n"
     "  hist.sort((a, b) => String(a.data || '').localeCompare(String(b.data || '')) || (a.t || 0) - (b.t || 0));\n"
     "  const maisNova = !item.ultimaData || d.data >= item.ultimaData;"),
    ("  const patch = { ultimaData: d.data, proximaData: null, historico: hist.slice(-40), atualizadoEm: Date.now() };",
     "  const patch = { ultimaData: maisNova ? d.data : item.ultimaData, proximaData: maisNova ? null : (item.proximaData || null), historico: hist.slice(-40), atualizadoEm: Date.now() };"),
    ("fDate('ex-data', 'Data da execução', hoje(), { name: 'data', req: true })",
     "fDate('ex-data', 'Data da execução', el.dataset.data && el.dataset.data <= hoje() ? el.dataset.data : hoje(), { name: 'data', req: true })"),
    ("      + ((p.checklist || []).length ? '<div class=\"field\"><span class=\"flabel\">Checklist</span>'",
     "      + (col === 'preventivas' || p.fichaId ? fChips('resultado', 'Resultado (como na ficha)', [{ v: 'O', l: 'O = Normal' }, { v: 'X', l: 'X = Anormal' }], 'O', { hint: 'Anormal: descreva nas observações o que foi encontrado.' }) : '')\n"
     "      + ((p.checklist || []).length ? '<div class=\"field\"><span class=\"flabel\">Checklist</span>'"),
    ("  if (!d.por) return toast('Informe quem executou.', 'crit');",
     "  if (!d.por) return toast('Informe quem executou.', 'crit');\n"
     "  const resultado = col === 'preventivas' || p.fichaId ? (d.resultado === 'X' ? 'X' : 'O') : null;\n"
     "  if (resultado === 'X' && !d.obs) return toast('Anormal (X): descreva nas observações o que foi encontrado.', 'crit');"),
    ("    const r = await executarPlano(col, p, { data: d.data, horas, por: d.por, obs, pecas, checklist: d.ck || null });",
     "    const r = await executarPlano(col, p, { data: d.data, horas, por: d.por, obs, pecas, checklist: d.ck || null, resultado });\n"
     "    if (resultado === 'X') toast('Registrado como anormal (X). Se precisar de conserto, abra um chamado.', 'crit');"),
    ("180: 'semestral', 365: 'anual' }[n]", "180: 'semestral', 365: 'anual', 730: 'a cada 2 anos' }[n]"),
    # 28/10/2026: ficha de lubrificação (o mesmo modelo); a importação de planilha da Preventiva/Lubrificação aceita a
    # ficha e a manda para Fichas; o método que veio da ficha e não está na lista continua no formulário
    ("""' Frequência aceita "mensal", "trimestral", "30 dias", "500 h" e parecidos.' : '')""",
     """' Frequência aceita "mensal", "trimestral", "30 dias", "500 h" e parecidos. A ficha no modelo da ficha de preventiva (LINHA, EQUIPAMENTO e Nº CONTROLE no topo e uma coluna por mês) também é aceita: ela entra em Fichas.' : '')"""),
    ("fSel('pf-met', 'Método', opts(METODOS_LUB, p.metodo, 'Escolha')",
     "fSel('pf-met', 'Método', opts(METODOS_LUB.concat(p.metodo && METODOS_LUB.indexOf(p.metodo) < 0 ? [p.metodo] : []), p.metodo, 'Escolha')"),
    ("fSel('pf-un', 'Unidade', opts(['g', 'ml', 'kg', 'L', 'bombadas', 'gotas'], p.unidade || 'g')",
     "fSel('pf-un', 'Unidade', opts(['g', 'ml', 'kg', 'L', 'bombadas', 'gotas'].concat(p.unidade && ['g', 'ml', 'kg', 'L', 'bombadas', 'gotas'].indexOf(p.unidade) < 0 ? [p.unidade] : []), p.unidade || 'g')"),
    ("'<div class=\"ev\"><div class=\"w\">' + fmtData(x.data) + (x.horas != null ?",
     "'<div class=\"ev\"><div class=\"w\">' + fmtData(x.data) + (x.resultado === 'X' ? ' · <b style=\"color:var(--crit)\">X anormal</b>' : x.resultado === 'O' ? ' · O normal' : '') + (x.horas != null ?"),
]

# Manutenção, pedidos de 21/10/2026 (código novo em manutencao-extra.js):
# - só o Nicolas (senha mestre) apaga chamado (regra também no banco, 0029); ele atende e conclui pelo fluxo normal;
# - documentação do equipamento em PDF e etiqueta com QR que abre a máquina (histórico);
# - materiais usados no atendimento com baixa no estoque; no fechamento, as peças da máquina à mão;
# - estoque de peças por máquina (aba, cadastro da peça e planilha) e fotos da peça;
# - selecionar vários itens e excluir de uma vez.
TROCAS_MANUTENCAO_2110 = [
    # no app do Android, o seletor de arquivos só mostra o que bate com o tipo (MIME): ".xlsx" sozinho deixava as
    # planilhas apagadas (23/10/2026)
    ('''accept=".xlsx,.xls,.csv,.txt" data-ch="imp-arq"''',
     '''accept=".xlsx,.xls,.csv,.txt,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel,text/csv,text/plain" data-ch="imp-arq"'''),
    ("function ehManutencao() { const s = perfil().setor; return s === 'Manutenção' || s === 'Gestão'; }",
     "function ehManutencao() { const s = perfil().setor; return s === 'Manutenção' || s === 'Gestão' || levSouNicolas(); }"),
    ("  if (fechado(c) && man) out.push(b('os-reabrir', '', 'refresh', 'Reabrir'));\n  return out.join('');",
     "  if (fechado(c) && man) out.push(b('os-reabrir', '', 'refresh', 'Reabrir'));\n  levRodapeChamado(c, out, b);\n  return out.join('');"),
    ("  if (c.status === 'cancelado') h += '<div class=\"blk\"><h3>Motivo do cancelamento</h3>",
     "  h += levMateriaisHtml(c);\n  if (c.status === 'cancelado') h += '<div class=\"blk\"><h3>Motivo do cancelamento</h3>"),
    ("      + pecasEditor('cc', [])\n",
     "      + levMateriaisJa(c) + levChipsPecas(c.equipId, 'cc') + pecasEditor('cc', [])\n"),
    ("solucao: { causa: s.causa || '', acao: s.acao, intervencao: s.intervencao || '', pecas: s.pecas || [],",
     "solucao: { causa: s.causa || '', acao: s.acao, intervencao: s.intervencao || '', pecas: levMateriaisDoChamado(c).concat(s.pecas || []),"),
    ("  const novoEl = podeEscrever() ?", "  h += levDocsHtml(e);\n  const novoEl = podeEscrever() ?"),
    ("  h += fichasDoEquipHtml(e);\n", "  h += levPecasMaquinaHtml(e);\n  h += fichasDoEquipHtml(e);\n"),
    ("[['saldo', 'Saldo'], ['mov', 'Movimentações'], ['compras', 'Compras']]",
     "[['saldo', 'Saldo'], ['maquina', 'Por máquina'], ['mov', 'Movimentações'], ['compras', 'Compras']]"),
    ("    body.innerHTML = this.f.aba === 'mov' ? this.movs() : this.f.aba === 'compras' ? this.compras() : this.saldo();",
     "    body.innerHTML = this.f.aba === 'mov' ? this.movs() : this.f.aba === 'compras' ? this.compras() : this.f.aba === 'maquina' ? levPecasPorMaquina(this) : this.saldo();"),
    ("&& (!q || norm([p.codigo, p.descricao, p.fabricante, p.modelo, p.local, p.fornecedor, p.categoria].join(' ')).includes(q)));",
     "&& (!q || norm([p.codigo, p.descricao, p.fabricante, p.modelo, p.local, p.fornecedor, p.categoria, levNomesMaquinas(p)].join(' ')).includes(q)));"),
    ('placeholder="Buscar código, descrição, modelo ou local"', 'placeholder="Buscar código, descrição, modelo, local ou máquina"'),
    ("'<div class=\"row clickable wrap-sm\" data-act=\"peca\" data-id=\"' + p.id + '\" role=\"button\" tabindex=\"0\"><span class=\"grow\">",
     "'<div class=\"row clickable wrap-sm\" data-act=\"peca\" data-id=\"' + p.id + '\" role=\"button\" tabindex=\"0\">' + levFotoMini(p) + '<span class=\"grow\">"),
    ("  h += '<div class=\"blk\"><h3>Onde é usada · ' + u.n", "  h += levFotosPecaHtml(p);\n  h += '<div class=\"blk\"><h3>Onde é usada · ' + u.n"),
    ("      + fArea('pc-obs', 'Observações', p.obs, { name: 'obs', rows: 2 })",
     "      + levCampoMaquinas(p)\n      + fArea('pc-obs', 'Observações', p.obs, { name: 'obs', rows: 2 })"),
    ("    ativo: antigo ? d.ativo === '1' : true, atualizadoEm: Date.now()\n  });",
     "    ativo: antigo ? d.ativo === '1' : true, maquinas: Array.isArray(d.maquinas) ? d.maquinas : [], atualizadoEm: Date.now()\n  });"),
    ("    { k: 'custo', l: 'Custo unitário', s: ['custo', 'valor unitario', 'preco', 'valor'] }\n  ] },",
     "    { k: 'custo', l: 'Custo unitário', s: ['custo', 'valor unitario', 'preco', 'valor'] },\n"
     "    { k: 'maquina', l: 'Máquina(s) onde é usada', s: ['maquina', 'maquinas', 'equipamento', 'equipamentos', 'aplicacao', 'onde usa'] }\n  ] },"),
    ("custo: parseNumBR(r.custo) != null ? parseNumBR(r.custo) : (ex ? ex.custo : null), atualizadoEm: agora",
     "custo: parseNumBR(r.custo) != null ? parseNumBR(r.custo) : (ex ? ex.custo : null), maquinas: levMaquinasDaCelula(r.maquina, ex), atualizadoEm: agora"),
]

MODULOS = {
    'manutencao': {
        'titulo': ('<title>Manutenção Levíssima</title>', '<title>Manutenção · LEVÍSSIMA</title>'),
        'trocas': [
            ("'Sem conexão com o banco compartilhado. Abra o app pelo link do Claude com sua conta.'",
             "'Sem conexão com o banco do LEVÍSSIMA. Verifique a internet e abra o módulo de novo.'"),
            ("'Seu acesso é somente leitura. Peça ao dono do app acesso de edição.'",
             "'Seu acesso é somente leitura. Peça à diretoria acesso a este módulo.'"),
            ("'Sem permissão para gravar. Peça ao dono do app acesso de edição.'",
             "'Sem permissão para gravar. Peça à diretoria acesso a este módulo.'"),
            ("Nada pode ser registrado agora. Abra o app pelo link do Claude, entrando com sua conta.",
             "Nada pode ser registrado agora. Verifique a internet e entre de novo pelo LEVÍSSIMA."),
            ("Para a equipe trabalhar junta, use o app pelo link do Claude.",
             "Para a equipe trabalhar junta, entre pelo LEVÍSSIMA."),
            ("'<span class=\"small muted\">A IA fica disponível ao usar o app pelo Claude com sua conta.</span>'", "''"),
            ("'Banco compartilhado: todos que usam este app pelo link do Claude veem os mesmos dados, ao vivo.'",
             "'Banco do LEVÍSSIMA: todos com acesso ao módulo Manutenção veem os mesmos dados, ao vivo.'"),
        ] + TROCAS_MANUTENCAO_1710 + TROCAS_MANUTENCAO_FICHAS + TROCAS_MANUTENCAO_2110,
        'inserir_antes': ('/* =====================================================================\n   Inicialização', ['manutencao-fichas.js', 'manutencao-extra.js']),
    },
    'uniformes': {
        'titulo': ('<title>Levíssima Uniformes e EPI</title>', '<title>Uniformes e EPI · LEVÍSSIMA</title>'),
        'trocas': [
            ('"Você não tem permissão para alterar estes dados. Peça a quem administra o app acesso de colaborador."',
             '"Você não tem permissão para alterar estes dados. Peça à diretoria acesso a este módulo."'),
            ('"O download não está disponível nesta visualização. Abra o app pelo link do Claude."',
             '"O download não está disponível neste aparelho."'),
            ('"Para que alguém registre entregas, compartilhe com permissão de colaborador ou editor. Quem só visualiza não altera nada."',
             '"Para que alguém registre entregas, a diretoria cria uma senha de setor com o módulo Uniformes e EPI (LEVÍSSIMA › Cadastros › Acesso ao app)."'),
            ('Abra pelo link do Claude com sua conta.', 'Verifique a internet e entre de novo pelo LEVÍSSIMA.'),
            ('peça acesso de colaborador a quem administra o app.', 'peça acesso à diretoria.'),
            # o cadastro de funcionários é o mesmo da aba RH do LEVÍSSIMA: guarda o campo "rh" ao salvar por aqui
            ('nrsExtras: Array.isArray(f.nrsExtras) ? f.nrsExtras.filter(Boolean) : [],',
             'nrsExtras: Array.isArray(f.nrsExtras) ? f.nrsExtras.filter(Boolean) : [],\n        rh: f.rh && typeof f.rh === "object" ? f.rh : null,'),
        ],
    },
    'garrafoes': {
        'titulo': ('<title>Estoque de garrafões novos</title>', '<title>Estoque de garrafões · LEVÍSSIMA</title>'),
        'trocas': [
            ('"Dados salvos com segurança e sincronizados entre seus dispositivos."',
             '"Dados no banco do LEVÍSSIMA, sincronizados entre todos os aparelhos com acesso a este módulo."'),
            ('msg.textContent="O download não está disponível nesta visualização.";',
             'msg.textContent="O download não está disponível neste aparelho.";'),
        ],
    },
}


def sem_tema_escuro(s):
    """Desliga o tema escuro automático (o app fica sempre com fundo branco/claro)."""
    return re.sub(r'@media\s*\(prefers-color-scheme:\s*dark\)', '@media not all', s)


def cabeca(modulo):
    return ('\n<link rel="icon" type="image/png" sizes="32x32" href="../icons/favicon-32.png">'
            '\n<link rel="apple-touch-icon" href="../icons/apple-touch-icon.png">'
            '\n<script src="' + SUPABASE_JS + '"></script>'
            '\n<script src="ponte.js" data-modulo="' + modulo + '"></script>\n')


def montar(saida, url=None, chave=None):
    pasta = os.path.join(saida, 'modulos')
    os.makedirs(pasta, exist_ok=True)
    for nome, cfg in MODULOS.items():
        s = open(os.path.join(AQUI, 'originais', nome + '.html'), encoding='utf-8').read()
        a, b = cfg['titulo']
        assert s.count(a) == 1, (nome, a)
        s = s.replace(a, b)
        for a, b in cfg['trocas']:
            assert s.count(a) == 1, (nome, a[:70], s.count(a))
            s = s.replace(a, b)
        if cfg.get('inserir_antes'):
            ancora, arquivos = cfg['inserir_antes']
            assert s.count(ancora) == 1, (nome, ancora)
            for arquivo in ([arquivos] if isinstance(arquivos, str) else arquivos):
                extra = open(os.path.join(AQUI, arquivo), encoding='utf-8').read()
                assert '</script' not in extra.lower(), arquivo
                s = s.replace(ancora, extra.rstrip() + '\n\n' + ancora)
        s = sem_tema_escuro(s)
        i = s.lower().index('<head>') + len('<head>')
        s = s[:i] + cabeca(nome) + s[i:]
        open(os.path.join(pasta, nome + '.html'), 'w', encoding='utf-8').write(s)
    # módulo novo
    e = open(os.path.join(AQUI, 'empilhadeiras.html'), encoding='utf-8').read()
    assert '<script src="ponte.js" data-modulo="empilhadeiras"></script>' in e
    open(os.path.join(pasta, 'empilhadeiras.html'), 'w', encoding='utf-8').write(sem_tema_escuro(e))
    # ponte com a configuração
    p = open(os.path.join(AQUI, 'ponte.js'), encoding='utf-8').read()
    if url and chave:
        a = 'var CONFIG = { url: "COLE_AQUI", anonKey: "COLE_AQUI" };'
        assert p.count(a) == 1
        p = p.replace(a, 'var CONFIG = { url: "' + url + '", anonKey: "' + chave + '" };')
    open(os.path.join(pasta, 'ponte.js'), 'w', encoding='utf-8').write(p)
    return sorted(os.listdir(pasta))


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    print(montar(sys.argv[1], *(sys.argv[2:4] if len(sys.argv) >= 4 else [])))
