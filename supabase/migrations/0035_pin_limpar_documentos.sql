-- LEVÍSSIMA · 0035: liga o gatilho da 0034 e tira o hash do PIN dos documentos da equipe (29/10/2026).
-- Rodar junto com a versão do app que confere o PIN no servidor (pin_conferir). Antes de limpar, acerta equipe_pins
-- com algum PIN que tenha sido trocado por um app antigo depois da 0034 (o "trocar" só continua se o PIN não mudou).

insert into public.equipe_pins (membro_id, hash, trocar, por)
select d.id, public.pin_hash_0034(lower(d.data ->> 'pinHash')), false, 'migração 0035'
  from public.docs d
 where d.colecao = 'equipe' and coalesce(d.data ->> 'pinHash', '') ~ '^[0-9a-fA-F]{64}$'
on conflict (membro_id) do update
   set hash = excluded.hash, ativo = true,
       trocar = case when public.equipe_pins.hash = excluded.hash then public.equipe_pins.trocar else false end,
       atualizado_em = case when public.equipe_pins.hash = excluded.hash then public.equipe_pins.atualizado_em else now() end;

create or replace trigger equipe_pin_guarda_0034 before insert or update on public.docs
  for each row when (new.colecao in ('equipe', 'cadastro-pedidos')) execute function public.equipe_pin_guarda_0034();

update public.docs set data = data where colecao in ('equipe', 'cadastro-pedidos');
