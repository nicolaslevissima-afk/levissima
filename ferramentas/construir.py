#!/usr/bin/env python3
"""Monta o site/app (www/) a partir dos fontes.

Uso (na pasta do projeto):
    python3 ferramentas/construir.py            # só o app principal (www/index.html)
    python3 ferramentas/construir.py --modulos  # app principal + módulos da fábrica (www/modulos/)

- App principal: fontes/app/levissima.html -> www/index.html, com o endereço e a chave pública do Supabase.
- Módulos: fontes/modulos/ -> www/modulos/ (pelo montar.py).
A chave abaixo é a pública (anon) do Supabase: ela não dá acesso a dados sem login.
"""
import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URL = 'https://lzsvtwwpthjncrhznfez.supabase.co'
CHAVE = ('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx6c3Z0d3dwdGhqbmNyaHpuZmV6Iiwicm9sZSI6'
         'ImFub24iLCJpYXQiOjE3OTE3NTQ5MjgsImV4cCI6MjEwNzMzMDkyOH0.W446lxCtvIVPn45yQqgr8Gj77s_n-t5E1Q-YYeWFN2E')


def app_principal():
    fonte = os.path.join(RAIZ, 'fontes', 'app', 'levissima.html')
    s = open(fonte, encoding='utf-8').read()
    i0 = s.index('var supabaseConfig = {')
    i1 = s.index('};', i0)
    bloco = s[i0:i1]
    assert bloco.count('"COLE_AQUI"') == 2, 'o fonte deve ficar com COLE_AQUI na configuração do Supabase'
    bloco = bloco.replace('url: "COLE_AQUI"', 'url: "' + URL + '"').replace('anonKey: "COLE_AQUI"', 'anonKey: "' + CHAVE + '"')
    s = s[:i0] + bloco + s[i1:]
    destino = os.path.join(RAIZ, 'www', 'index.html')
    open(destino, 'w', encoding='utf-8').write(s)
    print('www/index.html ok', len(s))


def modulos():
    sys.path.insert(0, os.path.join(RAIZ, 'fontes', 'modulos'))
    import montar
    print(montar.montar(os.path.join(RAIZ, 'www'), URL, CHAVE))


if __name__ == '__main__':
    app_principal()
    if '--modulos' in sys.argv:
        modulos()
