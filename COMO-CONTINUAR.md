# LEVÍSSIMA — como continuar em outro login do Claude

Pacote completo do app LEVÍSSIMA, situação em **14/10/2026**. Tem tudo o que foi feito: o app, os módulos da fábrica, os fontes, o banco de dados, a publicação automática, os textos e imagens das lojas e o histórico de alterações (pasta `.git`).

## Situação hoje

| Parte | Situação |
|---|---|
| App de cargas, entregas, paletes e chapatex | Pronto e testado |
| Módulos da fábrica (Manutenção, Checklist de empilhadeiras, Uniformes e EPI, Estoque de garrafões) | Prontos e testados, no mesmo login do app |
| Logo novo | Aplicado no app, nos ícones, na abertura e nos documentos |
| Banco de dados (Supabase) | No ar e configurado, com os dados dos módulos já copiados |
| Senha mestre | Criada no banco, guardada só como código (hash), nunca em texto |
| Site e módulos no ar | Feito em 14/10/2026: `https://nicolaslevissima-afk.github.io/levissima/` (repositório `nicolaslevissima-afk/levissima`) |
| App Android | APK de teste gerado pelo GitHub. Para o APK/AAB assinados da Google Play faltam os 4 segredos `ANDROID_*` (ver "Para pôr no ar") |
| Cores da marca | Verde 361 C, roxo 2603 C, azul Reflex Blue C e laranja 1645 C (equivalentes em tela no início do `<style>` do app) |
| Fretes dos motoristas | Tabela de fretes 29/09/2026 no banco (aba Fretes); destino do frete por cliente na carga (preenchido pela nota fiscal); página de cada motorista com Dados e acesso, Fretes (a pagar, confirmar proporcional, pago, relatório PDF) e Documentos (Storage privado) |
| Empilhadeiras | 6 máquinas (EMP-01 a EMP-06) e checklist pedido todo dia às 12:30 |
| Força de vendas | Portal dos representantes (9 cadastrados, sem senha ainda): cada um entra com a própria senha e lança pedidos. Pedido de representante só carrega com o **ok do financeiro** e o **ok da logística** (Equipe com senha, funções novas). Documentos e contratos de cada representante em Cadastros › Força de vendas |
| Estoque | Três cartões (Entrada de produção, Saldo em estoque, Saldo futuro), saldo por produto em paletes agrupado por marca, **saldo futuro por dia** depois das cargas programadas e **alerta de estoque mínimo** (selo na aba). Mínimos combinados em 14/10/2026: Levíssima copo 200ml 20, copo 300ml 10, 350ml natural 15, 350ml gás 10, 510ml natural 100, 510ml gás 70, 1,5L natural 100, 1,5L gás 50, 6L 30, 10L 12; outras marcas 510ml natural 30, 510ml gás 20, 1,5L natural 20, 1,5L gás 12, 6L 10. Cada produto pode ter mínimo próprio em Cadastros › Produtos |
| Aba Fretes | Aba própria (só senha mestre): a pagar por motorista e a tabela de fretes |
| Motoristas | Campo **Vínculo** (terceiro contratado a serviço da Levíssima ou próprio). Terceiros cadastrados em 14/10/2026: Renan França, Silvestre Pereira, Sérgio Félix e Guilherme Lourençon (sem senha ainda) |
| Google Play e App Store | Falta — roteiro em `loja/PUBLICAR-NAS-LOJAS.md` |

## Passo a passo para o Nicolas (no outro login)

1. **Crie o repositório no GitHub** (1 minuto): entre em **github.com/new** na conta **nicolasMoraes1**, nome **levissima**, marque **Public** e clique em **Create repository** (sem README).
2. **No outro login do Claude, ligue os conectores** em Configurações › Conectores:
   - **GitHub**, com a conta nicolasMoraes1;
   - **Supabase**, com a mesma conta do Supabase onde está o projeto `levissima`.
3. **Abra uma conversa nova**, anexe o `levissima-completo.zip` e o `chave-android-levissima.zip` e mande a mensagem abaixo.

> Este é o meu app LEVÍSSIMA, completo (leia o COMO-CONTINUAR.md do pacote primeiro). Já criei o repositório nicolasMoraes1/levissima no GitHub. Coloque o site, os módulos da fábrica e o app Android no ar e me mande o endereço do site e o APK. A chave do Android está no outro arquivo. Responda sempre em português.

## Para o Claude que continuar

### Regras do dono

- Tudo **100% em português**: respostas, textos e telas.
- O Nicolas quer autonomia: decida e faça, sem perguntar o que dá para resolver sozinho.
- O app tem que ser **seguro, só para pessoas autorizadas**. A senha mestre é a única que abre tudo. **Nunca escreva a senha mestre em código, arquivo, mensagem ou memória**: ela existe só como hash bcrypt no banco. Para trocá-la, o próprio app tem *Cadastros › Acesso ao app*.

### Como o app está montado

- `fontes/app/levissima.html`: fonte do app principal (uma página só, JavaScript puro), com `COLE_AQUI` no lugar da configuração do Supabase.
- `fontes/modulos/`: fontes dos módulos. Os três programas originais ficam em `originais/` e são montados sem mudar o funcionamento. `empilhadeiras.html` é o módulo novo. `ponte.js` liga cada módulo ao login e ao banco.
- `ferramentas/construir.py`: gera `www/` a partir dos fontes. Rode `python3 ferramentas/construir.py --modulos` depois de qualquer mudança nos fontes. Ele preenche o endereço e a chave **pública** do Supabase.
- `www/`: o que vai para o ar. Inclui `index.html`, `modulos/`, `marca/`, `icons/`, `manifest.webmanifest`, `sw.js` (cache `levissima-v3`) e `privacidade.html`.
- `.github/workflows/`: `site.yml` (GitHub Pages), `android.yml` (APK e AAB) e `ios.yml`.
- `capacitor.config.json`, `package.json`, `assets/`, `scripts/ajustar_android.py`: apps nativos (Capacitor).
- `loja/`: textos, ícones e 9 capturas por aparelho para as lojas.

Os módulos são páginas separadas (`www/modulos/*.html`). Por isso só funcionam com o site completo no ar. No app, eles aparecem na linha **Fábrica**, no alto da tela do escritório, para quem tem permissão. Sem login, o módulo manda para a tela de senha, e sem permissão mostra um aviso.

### Banco de dados (Supabase)

- Projeto `levissima`, id **`lzsvtwwpthjncrhznfez`**, região São Paulo. URL `https://lzsvtwwpthjncrhznfez.supabase.co`.
- Tabelas: `docs` (dados do app de cargas) e `modulo_docs` (dados dos módulos; chave `modulo, caminho, id`, dados em `dados jsonb`).
- Acesso: a Edge Function **`acesso`** (v3, publicada **sem** verificação de JWT de propósito, porque ela mesma confere a senha) devolve um login do Supabase com `papel` e `modulos` no `app_metadata`. Ações: `entrar`, `conferir`, `definir`, `ajustar`, `remover`, `lista`.
- Papéis: `mestre` (tudo), `equipe` (cargas e os módulos marcados), `motorista` (só as entregas dele), `setor` (só os módulos marcados; ref `setor:<id>`) e `representante` (Força de vendas: só os pedidos dele; ref `representante:<id>`). Cada módulo vale como `m` (usa) ou `m:gerir` (gerencia). As regras do banco (RLS, função `pode_modulo`) conferem isso em cada leitura e gravação.
- Migrações em `supabase/migrations/` (0001 a 0005), **já aplicadas**. Detalhes em `supabase/README.md`.
- Dados copiados em 13/10/2026:
  - Manutenção: 62 equipamentos, 18 elementos e a configuração.
  - Estoque de garrafões: 13 movimentos e a configuração.
  - Uniformes e EPI: 13 itens, 11 tipos de NR e a configuração.
- Os avisos do Supabase Advisor que restam são intencionais: funções `security definer` e tabelas de segredo sem política, que o app não deve ler mesmo.

### Para pôr no ar

> **Conta do GitHub:** desde 14/10/2026 o projeto está na conta **nicolaslevissima-afk** (repositório `nicolaslevissima-afk/levissima`, público), por escolha do Nicolas. Os passos acima, que falam de `nicolasMoraes1`, ficaram só como histórico. O `publicar.py` já usa a conta nova.
>
> **Segredos da chave Android:** a API de segredos do GitHub fica bloqueada no ambiente do Claude e o Claude não digita senhas em formulários. Por isso, quem grava os 4 segredos é o Nicolas, em *Settings › Secrets and variables › Actions › New repository secret*: `ANDROID_KEYSTORE_BASE64` (o arquivo `levissima-upload.jks` em base64), `ANDROID_KEYSTORE_PASSWORD` e `ANDROID_KEY_PASSWORD` (a senha de `senha-da-chave.txt`) e `ANDROID_KEY_ALIAS` (`levissima`). Depois, é só rodar de novo o fluxo *App Android*.

1. Confira que o repositório `nicolaslevissima-afk/levissima` existe e que o GitHub está liberado para você enviar código.
2. Descompacte `chave-android-levissima.zip` numa pasta `chave-android/` dentro do projeto. Essa pasta já está no `.gitignore` e não vai para o GitHub.
3. Rode `python3 ferramentas/publicar.py`. Ele faz cinco coisas:
   - envia o código;
   - liga o GitHub Pages pelo Actions;
   - grava os 4 segredos da chave Android (precisa do `libsodium`);
   - roda o site e o Android;
   - lista as execuções.
4. Acompanhe a aba Actions. Depois confira `https://nicolaslevissima-afk.github.io/levissima/` e mande ao Nicolas o endereço e o APK (artefato do fluxo *App Android*).

Se o `gh` do seu ambiente não puder gravar segredos ou ligar o Pages, faça só o envio do código e mostre ao Nicolas onde clicar. O roteiro dessa parte está no `README.md`, em Publicação.

### Regras do frete (combinadas com o Nicolas em 14/10/2026)

- 16 paletes = coluna de 16; 18 paletes = coluna de 18 (proporcional aos 16).
- Outra quantidade: o app sugere o proporcional (valor de 16 × paletes ÷ 16) e **só vale depois que a senha mestre confirma** (ou escolhe o valor cheio, ou digita outro).
- Mais de um destino na mesma carga: o frete mais caro + adicional de R$ 300 (uma vez; o valor fica na aba Fretes).
- Palete de 175 fardos (510ml com 7 fileiras): vale a linha "X - COM 175" do destino, quando existe.
- Só entram as cargas com carregamento concluído. O frete fica gravado em `fretes/<id da carga>` quando é confirmado, ajustado ou pago.

### Força de vendas (combinado com o Nicolas em 14/10/2026)

- Cada representante entra com a própria senha (criada pela senha mestre em *Cadastros › Força de vendas › Abrir › Criar senha*) e vê só a tela de pedidos dele.
- Pedido de representante nasce sem motorista e só fica liberado para carregar com o **ok do financeiro** e o **ok da logística**. As outras cargas continuam sem precisar desses oks.
- Os oks são dados com a senha de 4 números da *Equipe com senha*: marque "Dá o ok do financeiro" ou "Programa a logística dos caminhões". O Leonardo é o responsável pela logística; quem cadastra o Leonardo e a senha dele é o Nicolas (o Claude não digita senhas).
- O ok da logística exige motorista escolhido na carga. Depois de qualquer ok, o representante não consegue mais alterar o pedido (regra do banco).

### Cuidados

- **A chave do Android** (`chave-android-levissima.zip`) é a assinatura do app na Google Play. Se for perdida, não dá para atualizar o app na loja. Guarde uma cópia fora do Claude.
- **Os programas antigos** continuam no primeiro login do Claude: as páginas "Manutenção Levíssima", "Levíssima Uniformes e EPI", "Estoque de garrafões novos" e "Controle de Paletes e Chapatex". O que for lançado nelas depois de 13/10/2026 não está no app novo. Quando o app novo estiver no ar, pare de usar as páginas antigas.
- **Limpeza opcional:**
  - em *Cadastros › Acesso ao app* há dois acessos de teste já desativados, que podem ser removidos;
  - na tabela `docs` há 2 registros da coleção `z-teste-implantacao`, que podem ser apagados.
- Os testes automáticos (Playwright, com um Supabase simulado) ficaram no ambiente do primeiro login e **não** vieram neste pacote. Para mudanças grandes, vale recriar testes antes.
