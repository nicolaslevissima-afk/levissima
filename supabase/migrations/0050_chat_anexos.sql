-- LEVÍSSIMA · 0050: arquivos, fotos e áudios no Chat, no mesmo padrão das Solicitações (pedido de 11/11/2026).
--
-- * A mensagem do Chat pode levar até 6 anexos (chat_msgs.anexos, a mesma coluna da 0032).
-- * Os arquivos ficam no balde privado "comunicacao" (o mesmo das Solicitações), na pasta
--   chat/<quem enviou>/<para quem>/..., cada pessoa identificada pelo sha256 da referência de acesso (a pasta não
--   mostra quem é). Só as duas pessoas da conversa leem; cada um envia só na pasta chat/<eu>/<pessoa com acesso>/.
--   A senha mestre não lê o chat dos outros (igual às mensagens). Ninguém altera nem apaga por aqui.
-- * Gravação só pela função chat_enviar3 (a mensagem sem texto vira "📎 nome do arquivo"); chat_enviar2 continua
--   para as mensagens sem anexo.

-- identificador da pessoa na pasta: sha256 (hexadecimal) da referência de acesso
create or replace function public.chat_id_0050(p_ref text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$ select encode(sha256(convert_to(coalesce(p_ref, ''), 'UTF8')), 'hex'); $$;
revoke execute on function public.chat_id_0050(text) from public, anon;
grant execute on function public.chat_id_0050(text) to authenticated;

-- o identificador é de alguém (com acesso ativo, que não sou eu) que pode receber mensagem minha?
create or replace function public.chat_destino_id_ok_0050(p_id text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.acesso_senhas s
                  where s.papel in ('mestre', 'diretoria', 'equipe') and s.nome !~* 'desativad'
                    and s.ref <> public.ref_atual() and public.chat_id_0050(s.ref) = p_id);
$$;
revoke execute on function public.chat_destino_id_ok_0050(text) from public, anon;
grant execute on function public.chat_destino_id_ok_0050(text) to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'comunicacao: le chat 0050') then
    create policy "comunicacao: le chat 0050" on storage.objects for select to authenticated
      using (bucket_id = 'comunicacao' and name like 'chat/%' and (select public.chat_pode_0019())
             and (split_part(name, '/', 2) = (select public.chat_id_0050(public.ref_atual()))
                  or split_part(name, '/', 3) = (select public.chat_id_0050(public.ref_atual()))));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'comunicacao: envia chat 0050') then
    create policy "comunicacao: envia chat 0050" on storage.objects for insert to authenticated
      with check (bucket_id = 'comunicacao' and (select public.chat_pode_0019())
                  and name ~ '^chat/[0-9a-f]{64}/[0-9a-f]{64}/[A-Za-z0-9._-]{1,120}$'
                  and split_part(name, '/', 2) = (select public.chat_id_0050(public.ref_atual()))
                  and public.chat_destino_id_ok_0050(split_part(name, '/', 3)));
  end if;
end $$;

create or replace function public.chat_enviar3(p_para text, p_texto text, p_responde bigint default null, p_anexos jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eu text := public.ref_atual();
  v_txt text := btrim(coalesce(p_texto, ''));
  v_conv text;
  v_pasta text;
  v_anx jsonb := '[]'::jsonb;
  a jsonb;
  c public.chat_msgs;
  r public.chat_msgs;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  if p_para is null or p_para = v_eu or not public.chat_destino_ok_0019(p_para) then raise exception 'destino' using errcode = '22023'; end if;
  v_pasta := 'chat/' || public.chat_id_0050(v_eu) || '/' || public.chat_id_0050(p_para) || '/';
  if p_anexos is not null and jsonb_typeof(p_anexos) = 'array' then
    if jsonb_array_length(p_anexos) > 6 then raise exception 'anexos' using errcode = '22023'; end if;
    for a in select * from jsonb_array_elements(p_anexos) loop
      if jsonb_typeof(a) <> 'object'
         or left(coalesce(a ->> 'caminho', ''), length(v_pasta)) <> v_pasta
         or not exists (select 1 from storage.objects o where o.bucket_id = 'comunicacao' and o.name = a ->> 'caminho') then
        raise exception 'anexo' using errcode = '22023';
      end if;
      v_anx := v_anx || jsonb_build_array(jsonb_build_object('caminho', a ->> 'caminho', 'nome', left(coalesce(a ->> 'nome', 'arquivo'), 120),
        'tipo', left(coalesce(a ->> 'tipo', ''), 120), 'tam', coalesce((a ->> 'tam')::bigint, 0), 'seg', coalesce((a ->> 'seg')::int, 0)));
    end loop;
  end if;
  if v_txt = '' and jsonb_array_length(v_anx) > 0 then
    v_txt := left('📎 ' || (select string_agg(x ->> 'nome', ', ') from jsonb_array_elements(v_anx) x), 2000);
  end if;
  if v_txt = '' or length(v_txt) > 2000 then raise exception 'texto' using errcode = '22023'; end if;
  perform public.chat_limite_0019();
  v_conv := least(v_eu, p_para) || '|' || greatest(v_eu, p_para);
  if p_responde is not null then c := public.chat_citar_0027(p_responde, 'chat', v_conv); end if;
  insert into public.chat_msgs (tipo, conversa, de, de_nome, para, texto, responde, responde_texto, responde_de_nome, anexos)
  values ('chat', v_conv, v_eu, public.nome_atual(), p_para, v_txt, c.id,
          case when c.id is null then null when c.apagada then '(mensagem apagada)' else left(c.texto, 160) end, c.de_nome,
          case when jsonb_array_length(v_anx) > 0 then v_anx else null end)
  returning * into r;
  return to_jsonb(r);
end $$;
revoke execute on function public.chat_enviar3(text, text, bigint, jsonb) from public, anon;
grant execute on function public.chat_enviar3(text, text, bigint, jsonb) to authenticated;
