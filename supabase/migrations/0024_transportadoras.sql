-- LEVÍSSIMA · 0024: transportadoras (pedido de 20/10/2026).
-- Os motoristas terceiros podem trabalhar para uma transportadora que presta serviço para a Levíssima. A coleção
-- "transportadoras" (nome, dono/responsável, CNPJ, contato) é dado financeiro: só a senha mestre lê e grava, como os
-- fretes. Cada motorista guarda a transportadora (transportadoraId), o veículo (veiculoTipo) e a capacidade em paletes.
create or replace function public.colecao_so_mestre(p_colecao text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$ select p_colecao in ('fretes', 'fretes-tabela', 'motorista-docs', 'representantes', 'representante-docs', 'transportadoras'); $$;
