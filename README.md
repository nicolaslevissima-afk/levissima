# LEVÍSSIMA

> Continuando em outro login ou com outra pessoa? Leia primeiro o [COMO-CONTINUAR.md](COMO-CONTINUAR.md).

App da Levíssima Água Mineral para **cargas, entregas, paletes e chapatex**: o comercial lança a carga (ou importa a NF), o faturamento dá o ok com a senha de 4 números, a expedição conclui o carregamento com as assinaturas, o motorista acompanha a viagem e conclui cada entrega com a assinatura do cliente, e o escritório vê tudo em tempo real — inclusive o caminhão no mapa.

E os **módulos da fábrica**, no mesmo login:

| Módulo | O que faz |
|---|---|
| **Manutenção** | Chamados das máquinas por linha (L1, L2, L3, Copos, 6L e utilidades), prioridades e prazos, preventiva, lubrificação, estoque de peças e ferramentas, relatórios. |
| **Checklist de empilhadeiras** | Checklist diário (NR-11) de cada máquina, própria ou locada, com assinatura do operador. Item crítico com problema **bloqueia a máquina**; problema em máquina própria abre chamado na Manutenção sozinho; em máquina locada vira ocorrência para avisar a locadora (Santorini, SM) pelo WhatsApp. Histórico, planilha e etiqueta com QR para colar na máquina. |
| **Uniformes e EPI** | Entregas com assinatura, estoque por tamanho, trocas, CA e treinamentos de NR. |
| **Estoque de garrafões** | Entradas, saídas, trocas, contagem, lotes e validade (PEPS) e sucata dos garrafões de 20 L, 20 L rosca e 10 L. |

Funciona no navegador (celular, tablet e notebook, e pode ser instalado na tela inicial) e como app de **Android** e **iPhone/iPad**.

## Como está montado

| Parte | Onde fica |
|---|---|
| O app (uma página só) | `www/index.html` |
| Módulos da fábrica | `www/modulos/` — `manutencao.html`, `empilhadeiras.html`, `uniformes.html`, `garrafoes.html` |
| Ligação dos módulos com o login e o banco | `www/modulos/ponte.js` |
| Logo | `www/marca/` |
| Fonte do app principal | `fontes/app/levissima.html` |
| Fontes dos módulos (para alterar e gerar de novo) | `fontes/modulos/` |
| Gerar o `www/` a partir dos fontes / pôr no ar | `ferramentas/construir.py --modulos` / `ferramentas/publicar.py` |
| Instalar na tela inicial | `www/manifest.webmanifest`, `www/sw.js`, `www/icons/` |
| Política de privacidade | `www/privacidade.html` (endereço público exigido pelas lojas) |
| Banco de dados | Supabase — `supabase/migrations/` |
| Conferência das senhas | Supabase Edge Function — `supabase/functions/acesso/` |
| Apps das lojas | Capacitor — `capacitor.config.json`, `package.json`, `assets/` |
| Publicação automática | GitHub Actions — `.github/workflows/` |
| Textos e imagens das lojas | `loja/` |

## Segurança

- **Ninguém entra sem senha.** A senha digitada é conferida no servidor (função `acesso`); o app recebe só um login do Supabase com o papel da pessoa.
- **O próprio banco bloqueia o resto.** Sem login, o banco não entrega nem aceita nada (políticas em `0002_acesso.sql`). A chave pública do Supabase que está no app não dá acesso a dados.
- **Quatro tipos de senha:**
  - **Senha mestre** (diretoria): tudo, inclusive Cadastros, Pesquisas e todos os módulos.
  - **Senha da equipe do escritório**: Cargas, Paletes e chapatex e Estoque (e os módulos que a diretoria marcar).
  - **Motorista**: só as entregas dele.
  - **Senha de setor** (ex.: Manutenção, Almoxarifado, Operadores de empilhadeira): só os módulos marcados, cada um como **usa** (registra e consulta) ou **gerencia** (também cadastros, configurações e exclusões). O banco confere o módulo em cada leitura e gravação (`0003_modulos.sql`).
- **Senhas só como hash** (bcrypt) numa tabela que o app não consegue ler. A mesma senha não pode servir para duas pessoas. Mais de 20 tentativas erradas em 10 minutos bloqueiam por um tempo.
- **Pesquisas de satisfação** são gravadas criptografadas e só a senha mestre abre (o banco também não deixa ninguém além da senha mestre ler).
- As senhas são trocadas pelo próprio app, em **Cadastros › Acesso ao app** (mestre, equipe e senhas de setor) e **Cadastros › Motoristas**.

## Publicação

Tudo é automático a cada atualização na branch `main`:

- **Site** (GitHub Pages): `.github/workflows/site.yml`.
- **Android**: `.github/workflows/android.yml` gera um APK de teste (baixe em *Actions › App Android › Artifacts* e instale no celular). Com a chave de assinatura nos segredos do repositório, gera o AAB para a Google Play:
  - `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`
  - opcional `PLAY_SERVICE_ACCOUNT_JSON` (envia sozinho para o teste interno da Play)
- **iPhone/iPad**: `.github/workflows/ios.yml` confere que compila. Com a conta Apple Developer e uma chave da App Store Connect nos segredos, assina e envia para o TestFlight:
  - `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`

O passo a passo das lojas (contas, segredos, textos e imagens) está em `loja/PUBLICAR-NAS-LOJAS.md`.

## Banco de dados (Supabase)

Projeto `levissima` (São Paulo) já criado e configurado: tabelas, regras de acesso, função `acesso` e a senha mestre. Detalhes em `supabase/README.md`. O endereço e a chave pública já estão em `www/index.html`.
