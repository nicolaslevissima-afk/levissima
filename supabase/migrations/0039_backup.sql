-- LEVÍSSIMA · 0039: backup diário criptografado na nuvem (pedido de 29/10/2026).
--
-- Quem faz o backup é o GitHub (repositório privado levissima-backups), todo dia de madrugada: ele chama a função
-- "backup" do Supabase com um token do próprio GitHub (OIDC, sem senha guardada em lugar nenhum), recebe as tabelas
-- e os links dos arquivos, cifra tudo com a frase BACKUP_SENHA (AES-256) e guarda como release do repositório.
-- Ficam fora só os segredos e o que é passageiro (tentativas, desafios, travas, código do autenticador): depois de uma
-- restauração, os PINs e o autenticador da senha mestre são cadastrados de novo; as senhas de acesso continuam valendo.
--
-- * backup_tabelas_0039 / backup_pagina_0039 / backup_arquivos_0039: só a chave de serviço (a função "backup") usa.
-- * backup_execucoes: cada backup feito (a senha mestre vê em Cadastros › Segurança).

create table if not exists public.backup_execucoes (
  id bigserial primary key,
  em timestamptz not null default now(),
  tipo text not null default 'diario',
  tag text not null default '',
  tamanho bigint not null default 0,
  tabelas int not null default 0,
  linhas bigint not null default 0,
  arquivos int not null default 0
);
alter table public.backup_execucoes enable row level security;
revoke all on public.backup_execucoes from public, anon;
grant select on public.backup_execucoes to authenticated;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'backup_execucoes' and policyname = 'backup_le_0039') then
    create policy "backup_le_0039" on public.backup_execucoes for select to authenticated
      using ((select public.papel_atual()) = 'mestre');
  end if;
end $$;

create or replace function public.backup_tabelas_0039()
returns text[]
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(array_agg(c.relname::text order by c.relname), '{}')
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p')
     and c.relname not in ('acesso_segredo', 'acesso_desafios', 'acesso_tentativas', 'acesso_totp', 'pin_segredo',
                           'pin_tentativas', 'modulo_travas', 'backup_execucoes');
$$;
revoke execute on function public.backup_tabelas_0039() from public, anon, authenticated;
grant execute on function public.backup_tabelas_0039() to service_role;

create or replace function public.backup_pagina_0039(p_tabela text, p_offset integer, p_limite integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare r jsonb;
begin
  if not (p_tabela = any (public.backup_tabelas_0039())) then raise exception 'tabela'; end if;
  execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from (select * from public.%I order by 1 offset %s limit %s) t',
                 p_tabela, greatest(coalesce(p_offset, 0), 0), least(greatest(coalesce(p_limite, 500), 1), 2000)) into r;
  return r;
end $$;
revoke execute on function public.backup_pagina_0039(text, integer, integer) from public, anon, authenticated;
grant execute on function public.backup_pagina_0039(text, integer, integer) to service_role;

create or replace function public.backup_arquivos_0039(p_desde timestamptz)
returns table (bucket text, nome text, tamanho bigint, atualizado timestamptz)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select o.bucket_id::text, o.name::text, coalesce((o.metadata ->> 'size')::bigint, 0), coalesce(o.updated_at, o.created_at)
    from storage.objects o
   where o.name is not null and (p_desde is null or coalesce(o.updated_at, o.created_at) >= p_desde)
   order by 1, 2;
$$;
revoke execute on function public.backup_arquivos_0039(timestamptz) from public, anon, authenticated;
grant execute on function public.backup_arquivos_0039(timestamptz) to service_role;
