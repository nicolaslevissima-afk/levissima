-- LEVÍSSIMA · 0014: acesso da diretoria (vê tudo e só inclui) e entrada com o rosto (passkeys), pedido de 18/10/2026.
--
-- 1. Senhas da diretoria: ref 'diretoria:<id>', papel 'diretoria' em acesso_senhas. No login, a função "acesso" põe
--    papel 'mestre' no token (vê tudo, como a senha mestre) e so_inclui = true. As regras abaixo impedem quem tem
--    so_inclui de ALTERAR ou APAGAR qualquer registro (docs, módulos e arquivos); incluir continua liberado.
--    Exceção: o contador de números dos chamados da Manutenção (modulo_docs config/contador), que é parte de abrir
--    um chamado novo. A função "acesso" também recusa as ações da senha mestre para quem tem so_inclui.
-- 2. Biometria (rosto): acesso_senhas.biometria = true exige o rosto. No 1º acesso com a senha, a pessoa cadastra
--    o rosto (passkey do aparelho: Face ID no iPhone, biometria do computador) antes de entrar; depois, a senha
--    sozinha não entra mais, só o rosto. acesso_biometria guarda só a chave pública de cada aparelho (nunca foto);
--    acesso_desafios guarda os desafios de uso único (5 a 10 minutos). As duas tabelas só a função "acesso" lê
--    (RLS ligado e sem regras: o app não enxerga).

alter table public.acesso_senhas drop constraint if exists acesso_senhas_papel_check;
alter table public.acesso_senhas add constraint acesso_senhas_papel_check
  check (papel = any (array['mestre', 'equipe', 'motorista', 'setor', 'representante', 'diretoria']));
alter table public.acesso_senhas add column if not exists biometria boolean not null default false;

create table if not exists public.acesso_biometria (
  cred_id text primary key,
  ref text not null references public.acesso_senhas (ref) on delete cascade,
  chave text not null,
  alg integer not null,
  contador bigint not null default 0,
  transportes text[] not null default '{}',
  aparelho text not null default '',
  criado_em timestamptz not null default now(),
  usado_em timestamptz
);
create index if not exists acesso_biometria_ref on public.acesso_biometria (ref);
alter table public.acesso_biometria enable row level security;

create table if not exists public.acesso_desafios (
  id bigint generated always as identity primary key,
  tipo text not null check (tipo in ('cadastro', 'entrar')),
  ref text references public.acesso_senhas (ref) on delete cascade,
  ticket text unique,
  desafio text unique,
  expira timestamptz not null
);
alter table public.acesso_desafios enable row level security;
revoke all on public.acesso_biometria, public.acesso_desafios from anon, authenticated;

create or replace function public.so_inclui()
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$ select coalesce((auth.jwt() -> 'app_metadata' ->> 'so_inclui')::boolean, false); $$;
revoke execute on function public.so_inclui() from public, anon;
grant execute on function public.so_inclui() to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'so_inclui_nao_altera_0014') then
    create policy "so_inclui_nao_altera_0014" on public.docs as restrictive for update to authenticated
      using (not (select public.so_inclui())) with check (not (select public.so_inclui()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'so_inclui_nao_apaga_0014') then
    create policy "so_inclui_nao_apaga_0014" on public.docs as restrictive for delete to authenticated
      using (not (select public.so_inclui()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'modulo_docs' and policyname = 'so_inclui_nao_altera_0014') then
    create policy "so_inclui_nao_altera_0014" on public.modulo_docs as restrictive for update to authenticated
      using (not (select public.so_inclui()) or (caminho = 'config' and id = 'contador'))
      with check (not (select public.so_inclui()) or (caminho = 'config' and id = 'contador'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'modulo_docs' and policyname = 'so_inclui_nao_apaga_0014') then
    create policy "so_inclui_nao_apaga_0014" on public.modulo_docs as restrictive for delete to authenticated
      using (not (select public.so_inclui()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'so-inclui: nao altera') then
    create policy "so-inclui: nao altera" on storage.objects as restrictive for update to authenticated
      using (not (select public.so_inclui())) with check (not (select public.so_inclui()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'so-inclui: nao apaga') then
    create policy "so-inclui: nao apaga" on storage.objects as restrictive for delete to authenticated
      using (not (select public.so_inclui()));
  end if;
end $$;
