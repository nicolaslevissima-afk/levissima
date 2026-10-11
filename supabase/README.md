# Supabase do LEVÍSSIMA

- Projeto: `levissima` (região São Paulo, `sa-east-1`), URL `https://lzsvtwwpthjncrhznfez.supabase.co`.
- `migrations/0001_levissima.sql`: tabela `docs` (todos os dados do app), tempo real e funções de gravação.
- `migrations/0002_acesso.sql`: senhas (só hash), regras de acesso por papel e pesquisas protegidas.
- `functions/acesso`: confere a senha e devolve o login (publicada **sem** verificação de JWT, porque ela mesma faz a conferência).

Já aplicado no projeto. Para rodar de novo em outro projeto: aplique as migrações em ordem, publique a função e crie a senha mestre pelo SQL (`select public.acesso_definir('mestre', 'mestre', 'Nome', 'senha');`).
