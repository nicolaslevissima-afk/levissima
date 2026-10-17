-- LEVÍSSIMA · 0010: agendamento on-line dos clientes (Agenda dos retornáveis).
--
-- Coleção nova na tabela "docs":
--   agenda-online   doc "config" (aberto, clientes por horário, antecedência, dias e horário) e os clientes com link
--                   (cli-*: nome, WhatsApp e a chave do link pessoal)
-- Regra (soma com as que já existem): só o escritório (senha mestre e equipe) lê e grava.
-- O cliente não tem login: a página agendar.html fala com a função "agendamento" (sem verificação de JWT), que confere
-- a chave do link e só mostra horários livres (sem nomes) e os agendamentos do próprio cliente; ela grava em
-- agenda-itens (origem "online") com a chave de serviço.

create or replace function public.colecao_escritorio_0010(p_colecao text)
returns boolean language sql immutable set search_path = public, pg_temp
as $$ select p_colecao in ('agenda-online'); $$;
revoke execute on function public.colecao_escritorio_0010(text) from public, anon;
grant execute on function public.colecao_escritorio_0010(text) to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'escritorio_0010') then
    create policy "escritorio_0010" on public.docs as restrictive for all to authenticated
      using (not public.colecao_escritorio_0010(colecao) or (select public.papel_atual()) in ('mestre', 'equipe'))
      with check (not public.colecao_escritorio_0010(colecao) or (select public.papel_atual()) in ('mestre', 'equipe'));
  end if;
end $$;
