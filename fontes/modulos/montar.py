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
        ],
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
