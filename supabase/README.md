# Supabase do LEVÍSSIMA

- Projeto: `levissima` (região São Paulo, `sa-east-1`), URL `https://lzsvtwwpthjncrhznfez.supabase.co`.
- `migrations/0001_levissima.sql`: tabela `docs` (todos os dados do app), tempo real e funções de gravação.
- `migrations/0002_acesso.sql`: senhas (só hash), regras de acesso por papel e pesquisas protegidas.
- `migrations/0003_modulos.sql`: módulos da fábrica — tabela `modulo_docs` (dados de cada módulo, separados), permissão por módulo no login (`pode_modulo`), senhas de setor, trava curta para numeração e estoque, e o chamado que o checklist de empilhadeira abre na Manutenção.
- `migrations/0004_fretes_documentos.sql` (aplicada em 14/10/2026): uma regra **restritiva** a mais na tabela `docs` — as coleções `fretes-tabela`, `fretes` e `motorista-docs` só abrem com a senha mestre — e o bucket **privado** `motoristas-docs` no Storage (documentos do motorista e do caminhão, até 15 MB, fotos e PDF), também só para a senha mestre.
- `migrations/0005_forca_de_vendas.sql` (aplicada em 14/10/2026): papel **representante** (Força de vendas, ref `representante:<id>`). O representante lê só os produtos, os nomes dos destinos e as cargas dele, e grava só cargas dele (origem `representante`, status `aberta`) enquanto não têm o ok do financeiro nem o da logística. `representantes` e `representante-docs` são só da senha mestre; os arquivos ficam no bucket `motoristas-docs`, pasta `representantes/`.
- `migrations/0006_producao_materia_prima.sql` (aplicada em 15/10/2026): coleções `producao-ordens`, `mp-insumos`, `mp-fichas`, `mp-movs`, `garrafoes-fechamentos` e `mp-config`, só do escritório (senha mestre e equipe); insumos, fichas técnicas e configuração só a senha mestre grava. Duas regras **restritivas**; nenhuma regra antiga muda.
- `dados/materia_prima_2026-10-15.sql`: 54 insumos (com estoque mínimo sugerido) e 31 fichas técnicas (25 produtos e 6 garrafões 10L/20L). Já carregado; depois disso o app mantém.
- `dados/codigos_barras_2026-10-16.sql`: códigos de barras (EAN da garrafa e DUN do pacote) de todos os produtos e a marca **Bom Coração** (5 produtos). Já carregado.
- Coleção `marcas` (id = marca): logo de cada marca (imagem pequena), enviado em Cadastros › Marcas.
- `dados/representantes_2026-10-14.sql`: os 9 representantes (Luís, Émerson, Luccas, Marcone, Ana Clara, Matheus, Mauricio, Marcelo e Renato), sem senha.
- `dados/motoristas_terceiros_2026-10-14.sql`: Renan França, Silvestre Pereira, Sérgio Félix e Guilherme Lourençon, terceiros contratados a serviço da Levíssima (`vinculo: terceiro`), sem senha.
- `dados/fretes_2026-09-29.sql`: a tabela de fretes de 29/09/2026 (84 linhas, valores para 16 e 18 paletes) e a lista de destinos (`config/fretes-destinos`, sem valores, que a equipe usa ao lançar a carga). Já carregada; depois disso a tabela é mantida pelo app.
- Empilhadeiras (`modulo_docs`, módulo `empilhadeiras`): 6 máquinas cadastradas em 14/10/2026 (EMP-01 a EMP-06) e `config/geral.horarioChecklist = 12:30`.
- `functions/acesso`: confere a senha e devolve o login com o papel e os módulos (v3, com o papel `representante`; publicada **sem** verificação de JWT, porque ela mesma faz a conferência). Ações: `entrar`, `conferir`, `definir`, `ajustar` (módulos e nome sem trocar a senha), `remover`, `lista`.

Já aplicado no projeto. Para rodar de novo em outro projeto: aplique as migrações em ordem, publique a função e crie a senha mestre pelo SQL (`select public.acesso_definir('mestre', 'mestre', 'Nome', 'senha');`).
- `functions/rastreio` (publicada sem verificação de JWT, de propósito): recebe a posição mandada pelo GPS nativo do app Android durante a viagem (`?c=<carga>&t=<chave da viagem>`), confere o hash da chave em `rastreio/<carga>.chaveHash` e grava o ponto enquanto a viagem está ativa.
