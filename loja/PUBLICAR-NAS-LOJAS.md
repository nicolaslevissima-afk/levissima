# Publicar o LEVÍSSIMA na Google Play e na App Store

O app já é gerado sozinho pelo GitHub a cada atualização (aba **Actions** do repositório). Para ele aparecer nas lojas, faltam as contas de desenvolvedor da empresa e alguns cadastros, que só o dono da conta pode fazer. Este roteiro mostra a ordem.

> Enquanto isso, todo mundo já pode usar: **Android** (instalando o APK de teste ou pelo site, em *Instalar app*) e **iPhone/iPad** (abrir o site no Safari › Compartilhar › *Adicionar à Tela de Início*).

---

## Antes de tudo (vale para as duas lojas)

1. **Conta em nome da empresa.** Nas duas lojas, cadastre como **organização** (Alceu de Moraes Minerais Ltda.). Precisa do **número D-U-N-S** da empresa (grátis, pedido em dnb.com; a Apple também tem um formulário próprio). Na Google Play, conta de organização dispensa o teste fechado obrigatório de 12 testadores por 14 dias que as contas pessoais novas têm.
2. **Login para os revisores.** As lojas testam o app antes de aprovar. Crie em **Cadastros › Motoristas** um motorista chamado "Revisão das lojas", com uma senha só para isso, e informe essa senha no formulário de revisão. Depois da aprovação, remova esse motorista.
3. **Endereços que as lojas pedem:**
   - Política de privacidade: `https://nicolasmoraes1.github.io/levissima/privacidade.html`
   - Site / suporte: `https://nicolasmoraes1.github.io/levissima/`
   - E-mail de contato: um e-mail da empresa.

---

## Google Play (Android)

1. **Conta:** play.google.com/console › criar conta de desenvolvedor (taxa única de US$ 25).
2. **Chave de assinatura do app** (uma vez só): os 4 segredos `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` e `ANDROID_KEY_PASSWORD` em *GitHub › Settings › Secrets and variables › Actions*. Guarde uma cópia da chave e da senha em lugar seguro.
3. **Gerar o app da loja:** aba *Actions › App Android › Run workflow*. Ao terminar, baixe o arquivo `.aab` em *Artifacts*.
4. **Criar o app no Play Console:** nome **LEVÍSSIMA**, idioma Português (Brasil), app, gratuito.
5. **Preencher a ficha** com os textos abaixo, o ícone `loja/icone-512.png`, a imagem de destaque `loja/play-destaque-1024x500.png` e as capturas de `loja/capturas/android/`.
6. **Questionários do Play Console:**
   - *Classificação do conteúdo:* app de trabalho, sem violência, sem conteúdo adulto → Livre.
   - *Público-alvo:* 18 anos ou mais.
   - *Anúncios:* não tem.
   - *Segurança dos dados:* veja a tabela no fim deste arquivo.
   - *Acesso ao app:* "É preciso login" → informe a senha do motorista "Revisão das lojas".
7. **Enviar:** *Testes › Teste interno* com o `.aab` (instala nos celulares da equipe na hora) e, quando estiver tudo certo, *Produção*.
8. Para as próximas versões irem sozinhas para o teste interno, crie uma conta de serviço com acesso ao Play Console e salve o JSON no segredo `PLAY_SERVICE_ACCOUNT_JSON`.

---

## App Store (iPhone e iPad)

1. **Conta:** developer.apple.com › Apple Developer Program como organização (US$ 99 por ano).
2. **Identificador do app:** *Certificates, Identifiers & Profiles › Identifiers › +* › App ID `br.com.levissima.app`.
3. **App Store Connect:** *Apps › +* › Novo app › nome **LEVÍSSIMA**, idioma Português (Brasil), Bundle ID `br.com.levissima.app`.
4. **Chave para o GitHub enviar o app:** *Users and Access › Integrations › App Store Connect API* › gerar chave com acesso **App Manager**. Salve no GitHub os segredos `ASC_KEY_ID` (Key ID), `ASC_ISSUER_ID` (Issuer ID), `ASC_KEY_P8_BASE64` (o arquivo .p8 em base64) e `APPLE_TEAM_ID` (Team ID, em *Membership*).
5. **Gerar e enviar:** aba *Actions › App iOS › Run workflow*. O app aparece no **TestFlight** em alguns minutos: instale nos iPhones da equipe para testar.
6. **Ficha da loja:** textos abaixo, capturas de `loja/capturas/iphone/` e `loja/capturas/ipad/`, ícone (vai dentro do app).
7. **Privacidade do app:** veja a tabela no fim deste arquivo.
8. **Distribuição não listada:** como o app é interno (equipe, motoristas e clientes na entrega), peça a *Unlisted App Distribution* (developer.apple.com/support/unlisted-app-distribution). O app passa pela revisão, mas não aparece na busca: só quem tem o link baixa. Se a Apple pedir, explique que é a ferramenta de cargas e entregas da empresa, com login.
9. **Revisão:** em *App Review Information*, informe a senha do motorista "Revisão das lojas" e envie.

---

## Textos das lojas

**Nome:** LEVÍSSIMA

**Subtítulo (App Store, até 30 caracteres):** Cargas, entregas e paletes

**Descrição curta (Google Play, até 80 caracteres):** Cargas, entregas, paletes e chapatex da Levíssima, com rastreio e comprovante.

**Descrição completa:**

> O LEVÍSSIMA é o app de cargas e entregas da Levíssima Água Mineral, usado pela equipe do escritório, pela expedição e pelos motoristas.
>
> • Lançamento das cargas com os produtos e o cálculo automático de paletes e chapatex — ou importando a nota fiscal (XML ou PDF).
> • Ok do faturamento e conferência da expedição com senha de 4 números, sem digitar nome.
> • Pager entregue sozinho, tempo de espera no pátio e estoque dos produtos.
> • Ordem de carregamento com as assinaturas do motorista e do conferente, enviada ao motorista pelo WhatsApp.
> • App do motorista: saída para entrega, chegada em cada cliente e localização ao vivo para o escritório acompanhar no mapa.
> • Comprovante de entrega com os produtos, a nota fiscal, os paletes e chapatex entregues e devolvidos e a assinatura do cliente.
> • Saldo de paletes e chapatex de cada cliente e lembrete do que recolher.
> • Pesquisas de satisfação opcionais, vistas só pela diretoria.
>
> Acesso só com senha cadastrada pela empresa.

**Palavras-chave (App Store, até 100 caracteres):** cargas,entregas,paletes,chapatex,logística,motorista,comprovante,rastreio,expedição,água mineral

**Categoria:** Empresa (Business). Secundária: Produtividade.

**Classificação:** Livre / 4+.

**Novidades desta versão:** Primeira versão do app LEVÍSSIMA.

---

## Segurança dos dados (Google Play) e Privacidade do app (App Store)

| Dado | Coletado | Para quê | Compartilhado | Observação |
|---|---|---|---|---|
| Localização precisa | Sim | Funcionalidade do app (acompanhar a viagem) | Não | Só do motorista, só com o app aberto, a partir de "Saí para entrega". Pode pausar. |
| Nome | Sim | Funcionalidade do app | Não | Motoristas, equipe e quem recebe a entrega. |
| Telefone | Sim | Funcionalidade do app | Não | Celular do motorista, para abrir o WhatsApp. |
| Fotos e arquivos | Sim, quando a pessoa escolhe | Importar a nota fiscal | Não | O arquivo é lido no aparelho. |
| Assinaturas | Sim | Comprovante de entrega e ordem de carregamento | Não | — |
| Respostas das pesquisas | Sim, opcional | Melhorar o atendimento | Não | Criptografadas; só a diretoria lê. |

- Dados criptografados em trânsito: **sim**.
- A pessoa pode pedir a exclusão dos dados: **sim**, pela empresa (o motorista removido perde o acesso na hora).
- Rastreamento para publicidade: **não**. Anúncios: **não**.
