#!/usr/bin/env python3
"""Coloca o LEVÍSSIMA no ar pelo GitHub (o repositório precisa existir e estar liberado para quem roda).

Uso (na pasta do projeto, com o `gh` logado na conta dona do repositório):
    python3 ferramentas/publicar.py                       # todas as etapas
    python3 ferramentas/publicar.py codigo pages situacao # só algumas etapas

Etapas:
  codigo    envia o código para a branch main
  pages     liga o GitHub Pages publicado pelo Actions (site.yml)
  segredos  grava a chave de assinatura do Android nos segredos do repositório
            (o conteúdo de chave-android-levissima.zip — levissima-upload.jks e senha-da-chave.txt —
            na pasta ./chave-android, ou na pasta indicada em LEVISSIMA_CHAVE_ANDROID)
  disparar  roda os fluxos do site e do Android
  situacao  lista as últimas execuções do Actions

Variáveis opcionais: LEVISSIMA_DONO (padrão nicolaslevissima-afk), LEVISSIMA_REPO (padrão levissima).
"""
import base64
import json
import os
import subprocess
import sys
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)

PASTA = os.path.dirname(AQUI)
DONO = os.environ.get('LEVISSIMA_DONO', 'nicolaslevissima-afk')
REPO = os.environ.get('LEVISSIMA_REPO', 'levissima')
R = f'repos/{DONO}/{REPO}'
CHAVE = os.environ.get('LEVISSIMA_CHAVE_ANDROID', os.path.join(PASTA, 'chave-android'))


def gh(*args, dados=None, ok_erro=False):
    cmd = ['gh', 'api', *args]
    if dados is not None:
        cmd += ['--input', '-']
    r = subprocess.run(cmd, input=json.dumps(dados) if dados is not None else None, capture_output=True, text=True)
    if r.returncode and not ok_erro:
        raise SystemExit(f'erro em {args}: {r.stdout} {r.stderr}')
    try:
        return json.loads(r.stdout) if r.stdout.strip() else {}
    except json.JSONDecodeError:
        return {'bruto': r.stdout, 'erro': r.stderr}


def passo(t):
    print('==', t, flush=True)


def enviar_codigo():
    passo('enviando o código')
    remotos = subprocess.run(['git', '-C', PASTA, 'remote'], capture_output=True, text=True).stdout.split()
    url = f'https://github.com/{DONO}/{REPO}.git'
    acao = 'set-url' if 'origin' in remotos else 'add'
    subprocess.run(['git', '-C', PASTA, 'remote', acao, 'origin', url], check=True)
    r = subprocess.run(['git', '-C', PASTA, 'push', '-u', 'origin', 'main'])
    if r.returncode:
        # repositório criado com README/licença: se só tem o commit inicial do GitHub, o nosso substitui
        commits = gh(f'{R}/commits?per_page=5', ok_erro=True)
        if isinstance(commits, list) and len(commits) <= 1:
            subprocess.run(['git', '-C', PASTA, 'push', '-f', '-u', 'origin', 'main'], check=True)
        else:
            raise SystemExit('o repositório já tem outros commits; não vou sobrescrever')


def ligar_pages():
    passo('ligando o GitHub Pages (publicação pelo Actions)')
    atual = gh(f'{R}/pages', ok_erro=True)
    if atual.get('html_url'):
        if atual.get('build_type') != 'workflow':
            gh('-X', 'PUT', f'{R}/pages', dados={'build_type': 'workflow'}, ok_erro=True)
    else:
        print(gh('-X', 'POST', f'{R}/pages', dados={'build_type': 'workflow'}, ok_erro=True))
    print(gh(f'{R}/pages', ok_erro=True).get('html_url'))


def gravar_segredos():
    passo('gravando a chave de assinatura do Android nos segredos')
    from selar import selar  # precisa do libsodium (pacote libsodium23)
    jks_path = os.path.join(CHAVE, 'levissima-upload.jks')
    if not os.path.exists(jks_path):
        print('  pulei: não achei', jks_path)
        return
    pub = gh(f'{R}/actions/secrets/public-key')
    arq_senha = next(p for p in (os.path.join(CHAVE, n) for n in ('senha-da-chave.txt', 'senha.txt')) if os.path.exists(p))
    senha = open(arq_senha).read().strip()
    jks = base64.b64encode(open(jks_path, 'rb').read()).decode()
    segredos = {
        'ANDROID_KEYSTORE_BASE64': jks,
        'ANDROID_KEYSTORE_PASSWORD': senha,
        'ANDROID_KEY_ALIAS': 'levissima',
        'ANDROID_KEY_PASSWORD': senha,
    }
    for nome, valor in segredos.items():
        gh('-X', 'PUT', f'{R}/actions/secrets/{nome}', dados={'encrypted_value': selar(pub['key'], valor), 'key_id': pub['key_id']})
        print('  ok', nome)


def disparar():
    passo('rodando o site e o app Android')
    for wf in ('site.yml', 'android.yml'):
        gh('-X', 'POST', f'{R}/actions/workflows/{wf}/dispatches', dados={'ref': 'main'}, ok_erro=True)


def situacao():
    runs = gh(f'{R}/actions/runs?per_page=10').get('workflow_runs', [])
    for r in runs:
        print(f"  {r['name']:<12} {r['status']:<11} {r.get('conclusion') or '':<10} {r['html_url']}")
    return runs


if __name__ == '__main__':
    etapas = sys.argv[1:] or ['codigo', 'pages', 'segredos', 'disparar', 'situacao']
    if 'codigo' in etapas:
        enviar_codigo()
    if 'pages' in etapas:
        ligar_pages()
    if 'segredos' in etapas:
        gravar_segredos()
    if 'disparar' in etapas:
        time.sleep(5)
        disparar()
    if 'situacao' in etapas:
        time.sleep(10)
        situacao()
