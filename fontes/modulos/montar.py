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
        ] + TROCAS_MANUTENCAO_1710,
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
