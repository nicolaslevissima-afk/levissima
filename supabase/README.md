# Supabase do LEVÍSSIMA

- Projeto: `levissima` (região São Paulo, `sa-east-1`), URL `https://lzsvtwwpthjncrhznfez.supabase.co`.
- `migrations/0001_levissima.sql`: tabela `docs` (todos os dados do app), tempo real e funções de gravação.
- `migrations/0002_acesso.sql`: senhas (só hash), regras de acesso por papel e pesquisas protegidas.
- `migrations/0003_modulos.sql`: módulos da fábrica — tabela `modulo_docs` (dados de cada módulo, separados), permissão por módulo no login (`pode_modulo`), senhas de setor, trava curta para numeração e estoque, e o chamado que o checklist de empilhadeira abre na Manutenção.
- `functions/acesso`: confere a senha e devolve o login com o papel e os módulos (publicada **sem** verificação de JWT, porque ela mesma faz a conferência). Ações: `entrar`, `conferir`, `definir`, `ajustar` (módulos e nome sem trocar a senha), `remover`, `lista`.

Já aplicado no projeto. Para rodar de novo em outro projeto: aplique as migrações em ordem, publique a função e crie a senha mestre pelo SQL (`select public.acesso_definir('mestre', 'mestre', 'Nome', 'senha');`).
