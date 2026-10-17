# LEVÍSSIMA — como continuar em outro login do Claude

Pacote completo do app LEVÍSSIMA, situação em **16/10/2026**. Tem tudo o que foi feito: o app, os módulos da fábrica, os fontes, o banco de dados, a publicação automática, os textos e imagens das lojas e o histórico de alterações (pasta `.git`).

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
| Empilhadeiras | 6 máquinas (EMP-01 a EMP-06), checklist pedido todo dia às 12:30 e **horímetro obrigatório**. Troca de óleo e filtro a cada 250 h nas máquinas a combustão (intervalo próprio por máquina; 0 = não controla; a elétrica fica de fora), com aviso faltando 25 h, no painel, no fim do checklist e com selo no menu Fábrica do app. A troca é registrada em *Máquinas › Troca de óleo* |
| Força de vendas | Portal dos representantes (9 cadastrados, sem senha ainda): cada um entra com a própria senha e lança pedidos. Pedido de representante só carrega com o **ok do financeiro** e o **ok da logística** (Equipe com senha, funções novas). Documentos e contratos de cada representante em Cadastros › Força de vendas |
| Estoque | Três cartões (Entrada de produção, Saldo em estoque, Saldo futuro), saldo por produto em paletes agrupado por marca, **saldo futuro por dia** depois das cargas programadas e **alerta de estoque mínimo** (selo na aba). Mínimos combinados em 14/10/2026: Levíssima copo 200ml 20, copo 300ml 10, 350ml natural 15, 350ml gás 10, 510ml natural 100, 510ml gás 70, 1,5L natural 100, 1,5L gás 50, 6L 30, 10L 12; outras marcas 510ml natural 30, 510ml gás 20, 1,5L natural 20, 1,5L gás 12, 6L 10. Cada produto pode ter mínimo próprio em Cadastros › Produtos |
| Produção e matéria-prima | Aba **Produção** (equipe e senha mestre): ordem de produção com a quantidade de cada produto; o app calcula a matéria-prima pela ficha técnica, confere o estoque (as ordens abertas reservam na ordem da fila) e, ao concluir, a produção entra no estoque de produtos e a matéria-prima sai. Aba **Matéria-prima**: saldo de cada insumo (contagem + recebimentos − perdas − consumo), mínimo e alerta; área própria para os **garrafões 10L e 20L** (Levíssima, Americana, Colina Azul), sem ordem de produção, com **fechamento do dia** do que foi vendido. 54 insumos e 31 fichas carregados em 15/10/2026 com as medidas do Nicolas (caixa de copo 48, tabuleiro no copo 300ml, shrink 0,025 kg/fardo, stretch 0,003 kg/fardo, CO₂ 0,25 kg/fardo 1,5L e 0,15 kg/fardo 510ml, rosca e detergente nos garrafões). Insumos e fichas só a senha mestre altera |
| Rastreio das cargas | No app Android, ao tocar em "Saí para entrega" o celular liga o GPS em segundo plano (aviso fixo na barra) e manda a posição a cada minuto direto para a função `rastreio` do Supabase, mesmo com a tela desligada ou o app fechado, até a última entrega. A função confere a chave da viagem (só o hash fica no banco). No navegador continua só com o app aberto |
| Dupla conferência do carregamento | Na carga (cartão e detalhes), **conferência por código de barras**: a câmera (ou um leitor USB/Bluetooth, que funciona como teclado) lê cada palete e o app compara com o pedido; duas conferências por pessoas diferentes, com a senha de conferente. Os códigos ficam em *Cadastros › Produtos* (código desconhecido pode ser vinculado na hora). A dupla conferência é **obrigatória** para concluir (desde 16/10/2026) e precisa ser refeita se a carga mudar depois. Códigos de barras de todos os produtos (PDF de 15/10/2026) já cadastrados. Sem leitor nativo (iPhone/computador), usa a biblioteca ZXing do jsDelivr |
| Cores e logos dos produtos | Cada produto aparece com o **logo da marca** na frente e, quando lançado, na **cor do produto** (lançamento da carga, quadro, conclusão do carregamento, dupla conferência e ordem de carregamento): Levíssima natural verde, Levíssima com gás roxo, Colina Azul natural azul, Colina Azul com gás laranja, Betel rosa, New Mania azul-esverdeado, Casa de Mãe natural azul clarinho e com gás laranja clarinho, Bom Coração natural azul-claro e com gás roxo-claro; Bulnez em branco. Sem logo enviado (Cadastros › Marcas, coleção `marcas`), aparecem as iniciais (Levíssima: LV) |
| Agenda dos retornáveis | Aba **Agenda** (equipe e senha mestre): semana de segunda a domingo, das 4h às 18h de 30 em 30 min, como a planilha AGENDA 2026. Fixos que se repetem toda semana (coleção `agenda-fixos`, com pulos e fim), agendamentos de um dia (`agenda-itens`), feriados (`agenda-dias`) e observações da semana (`agenda-semanas`). No celular, um dia por vez, com envio pelo WhatsApp. A agenda fixa tirada das planilhas de set./out. só entra se alguém tocar em "Carregar a agenda fixa sugerida" |
| RH | Aba **RH** (só senha mestre), com os funcionários da planilha RELAÇÃO FUNCIONÁRIOS (atualizada em 16/10/2026: 11 novos, 3 que saíram da planilha marcados como desligados, mudanças de função/turno/situação), gravados no módulo Uniformes e EPI (`modulo_docs`, modulo `uniformes`, caminho `funcionarios`, campo `rh`). Vê por função, turno ou situação; experiência de **30 + 30 dias** (avisos aos 30 e aos 60); férias, atestado e NRs; ficha com treinamento, efetivar e desligar. Os dados pessoais **não** vão para o GitHub |
| Início | Primeira aba: o dia num olhar (cargas, estoque, produção, matéria-prima, qualidade, salas, fretes aguardando aprovação, agenda) e atalhos (+ Nova carga, + Entrada de produção, + Ordem de produção, + Reservar sala…). Visual de 16/10/2026: **fundo branco sempre** (o tema escuro automático foi desligado, também nos módulos), abas com ícones; no celular a faixa de abas fica presa no topo; no computador vira menu lateral |
| Salas de reunião | Aba **Salas** (equipe e senha mestre): **Levíssima Protein** (só diretoria e gestão: senha mestre ou senha de 4 números de quem tem "Diretoria / gestão" em Cadastros › Equipe) e **PH+8** (todos os setores). Agenda das 24 horas em blocos de 30 minutos, reserva mais longa e repetição (todo dia, dias úteis, toda semana). Coleção `salas-reservas`; cancelar não apaga |
| Qualidade | Aba **Qualidade** (equipe e senha mestre): Hoje (pendências), Recebimento (inspeção de cada insumo com amostra NBR 5426; aprovado dá entrada na matéria-prima; reprovado abre NC), Linha (pré-operacional, verificação de processo a cada 2 h, garrafões retornáveis), Análises (RDC 275/2005 e faixa físico-química no Plano; frequência de cada análise), NCs (contenção, causa, ação corretiva, eficácia) e Plano (só a senha mestre altera). Assinatura com a senha de 4 números de quem tem "Qualidade" em Cadastros › Equipe. Base: RDC 173/2006 e RDC 275/2005 |
| Aprovação de frete | O valor do frete vem da tabela. Se for editado (ou a carga não tiver valor na tabela), o lançamento fica salvo mas o frete fica **aguardando aprovação**: não dá para pagar até o Nicolas aprovar com a senha de 4 números dele (função "Aprova frete com valor editado" em Cadastros › Equipe) |
| Estoque por local | Na contagem do Estoque, escolha o local (Expedição, Galpão Fonte Priscilla, Galpão Skimoni 1 e 2) e digite o que há em cada um (pode ser meio palete). O saldo do produto é a soma; o quadro **Estoque por local** mostra a última contagem de cada local. Locais em `mp-config/estoque-locais` (só a senha mestre edita). Inventário de 16/10 (manhã) já lançado |
| Cronograma de saída | Aba **Estoque › Cronograma de saída**: o que cada marca carrega em cada período, em paletes (palete padrão ou com outra quantidade, ex.: 6 c/ 175). Entra no saldo futuro no 1º dia do período; carga do mesmo produto no período abate a programação. Cor: verde atende, laranja abaixo do mínimo, vermelho falta (com "Criar OP"). Coleção `saidas-programadas`; a planilha de 16/10 já está lançada |
| Fornecedores, laudos e recebimentos | Aba **Matéria-prima**: **Fornecedores** (insumos que entregam, prazo, situação), **Laudos** (PDF ou foto no bucket `fornecedores-laudos`, com validade e aviso 30 dias antes; renovar manda o antigo para o histórico; só a senha mestre exclui) e **Recebimentos** (agendar entrega → chegou → conferir a carga com assinatura do conferente → inspeção da Qualidade → entrada no estoque). Especificação técnica e "exige certificado do lote" no cadastro do insumo. Sugestão de compra pelo que falta produzir no cronograma de saída |
| Produto comprado pronto | Cadastros › Produtos: "Comprado pronto de terceiro" (ex.: 350ml da Fonte de Atibaia): sem ficha técnica e sem ordem de produção; no cronograma aparece "comprar" |
| Recado em destaque | Cadastros › Recado em destaque: aparece no alto do app para todos os acessos (doc `mural/atual`); hoje: "PARABÉNS PELO RECORDE DE PRODUÇÃO…" |
| Convites das salas | Na reserva de sala dá para **adicionar participantes** (da equipe, ou nome de fora): cada um recebe o convite **dentro do app** (selo na aba Salas e cartão no Início) e aceita ou recusa com a própria senha de 4 números; quem reservou vê as respostas |
| Ordem de compras | Aba **Compras** (equipe e senha mestre), coleção `compras-ordens`. Fluxo com assinatura (senha de 4 números) em cada etapa: **Pedido** (qualquer pessoa da equipe: item, quantidade e onde vai aplicar) → **Aprovação do coordenador do setor** → **Cotação** (assistente de compras; até 3 fornecedores, o menor preço fica marcado) → **Aprovação do Nicolas** (pode pedir nova cotação) → **Compra registrada** → **Fechamento da entrega** por quem pediu. Funções em Cadastros › Equipe: "Coordenador de setor" (com os setores), "Assistente de compras" e "Aprova compras" |
| Criar a minha senha (opção B) | Atalho no Início e botão na tela do setor: a pessoa informa nome, matrícula, **CPF** (conferido), tira **foto do RG/CNH** e uma **selfie**, cria a própria senha de 4 números (duas vezes) e aceita o aviso da LGPD. O pedido vai para *Cadastros › Pedidos de senha*: a senha mestre compara as fotos lado a lado e aprova (escolhendo as funções) ou recusa. Ao decidir, as fotos são apagadas e o CPF fica mascarado. A senha só vale depois da aprovação. Opção A (reconhecimento facial automático) fica para depois |
| Agendamento on-line | Na aba **Agenda**, seção "Agendamento on-line dos clientes": cada cliente recebe um **link pessoal** (`https://nicolaslevissima-afk.github.io/levissima/agendar.html#t=<chave>`), vê só os dias e horários livres (sem o nome de ninguém) e agenda sozinho; o horário entra na agenda com 🌐. Na véspera, a seção lista os **lembretes de amanhã**: um toque abre o WhatsApp com a mensagem e o link para o cliente confirmar ou cancelar (vira ✓ na agenda). Regras ajustáveis (vagas por horário, antecedência, dias). Envio **automático** do lembrete depende de contratar um serviço de WhatsApp (Z-API ou API oficial da Meta). Função `agendamento`, página `fontes/app/agendar.html` |
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
- `fontes/app/agendar.html`: página pública do agendamento on-line dos clientes (vira `www/agendar.html`).
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
- Migrações em `supabase/migrations/` (0001 a 0011), **já aplicadas**. Detalhes em `supabase/README.md`.
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
  - na tabela `docs` há 2 registros da coleção `z-teste-implantacao` e o `rastreio/z-teste-rastreio` (teste da função de rastreio, já desativado), que podem ser apagados.
- Os testes automáticos (Playwright, com um Supabase simulado) ficaram no ambiente do primeiro login e **não** vieram neste pacote. Para mudanças grandes, vale recriar testes antes.
