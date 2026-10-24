-- LEVÍSSIMA · 0032: arquivos, fotos e áudios nas Solicitações (pedido de 24/10/2026).
--
-- * A mensagem da solicitação pode levar até 6 anexos (chat_msgs.anexos = [{ caminho, nome, tipo, tam, seg }]).
-- * Os arquivos ficam no balde privado "comunicacao", na pasta da conversa: sol/<quem pede>/... — quem pede lê e envia
--   só na pasta dele; o Nicolas (senha mestre) lê e responde em todas. Ninguém altera nem apaga por aqui.
-- * Gravação só pela função sol_enviar3 (a mensagem sem texto vira "📎 nome do arquivo").

alter table public.chat_msgs add column if not exists anexos jsonb;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('comunicacao', 'comunicacao', false, 26214400, array[
  'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic', 'image/heif',
  'audio/webm', 'audio/ogg', 'audio/mpeg', 'audio/mp3', 'audio/mp4', 'audio/aac', 'audio/x-m4a', 'audio/m4a', 'audio/wav', 'audio/x-wav', 'audio/3gpp', 'audio/amr', 'audio/opus',
  'video/mp4', 'video/webm', 'video/quicktime', 'video/3gpp',
  'application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-powerpoint', 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'text/plain', 'text/csv', 'application/zip', 'application/x-zip-compressed', 'application/octet-stream'])
on conflict (id) do nothing;

-- pasta da conversa no balde (a referência vira só letras, números, _ e -)
create or replace function public.sol_pasta_0032(p_conversa text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$ select 'sol/' || regexp_replace(coalesce(p_conversa, ''), '[^A-Za-z0-9_-]', '_', 'g'); $$;
grant execute on function public.sol_pasta_0032(text) to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'comunicacao: le 0032') then
    create policy "comunicacao: le 0032" on storage.objects for select to authenticated
      using (bucket_id = 'comunicacao' and (select public.chat_pode_0019())
             and (((select public.ref_atual()) = 'mestre' and name like 'sol/%')
                  or name like public.sol_pasta_0032((select public.ref_atual())) || '/%'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'comunicacao: envia 0032') then
    create policy "comunicacao: envia 0032" on storage.objects for insert to authenticated
      with check (bucket_id = 'comunicacao' and (select public.chat_pode_0019())
                  and (((select public.ref_atual()) = 'mestre' and name like 'sol/%' and name not like 'sol/mestre/%')
                       or name like public.sol_pasta_0032((select public.ref_atual())) || '/%'));
  end if;
end $$;

create or replace function public.sol_enviar3(p_texto text, p_conversa text default null, p_responde bigint default null, p_anexos jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eu text := public.ref_atual();
  v_txt text := btrim(coalesce(p_texto, ''));
  v_conv text;
  v_num int;
  v_pasta text;
  v_anx jsonb := '[]'::jsonb;
  a jsonb;
  c public.chat_msgs;
  r public.chat_msgs;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  if v_eu = 'mestre' then
    if p_conversa is null or p_conversa = 'mestre' or not public.chat_destino_ok_0019(p_conversa) then raise exception 'destino' using errcode = '22023'; end if;
    v_conv := p_conversa;
  else
    v_conv := v_eu;
  end if;
  v_pasta := public.sol_pasta_0032(v_conv) || '/';
  if p_anexos is not null and jsonb_typeof(p_anexos) = 'array' then
    if jsonb_array_length(p_anexos) > 6 then raise exception 'anexos' using errcode = '22023'; end if;
    for a in select * from jsonb_array_elements(p_anexos) loop
      if left(coalesce(a ->> 'caminho', ''), length(v_pasta)) <> v_pasta
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
  if v_eu <> 'mestre' then
    perform pg_advisory_xact_lock(hashtext('sol|' || v_conv));
    select coalesce(max(numero), 0) + 1 into v_num from public.chat_msgs where tipo = 'sol' and conversa = v_conv and de <> 'mestre';
  end if;
  if p_responde is not null then c := public.chat_citar_0027(p_responde, 'sol', v_conv); end if;
  insert into public.chat_msgs (tipo, conversa, de, de_nome, para, texto, numero, responde, responde_texto, responde_de_nome, anexos)
  values ('sol', v_conv, v_eu, public.nome_atual(), case when v_eu = 'mestre' then v_conv else 'mestre' end, v_txt, v_num, c.id,
          case when c.id is null then null when c.apagada then '(mensagem apagada)' else left(c.texto, 160) end, c.de_nome,
          case when jsonb_array_length(v_anx) > 0 then v_anx else null end)
  returning * into r;
  return to_jsonb(r);
end $$;
revoke execute on function public.sol_enviar3(text, text, bigint, jsonb) from public, anon;
grant execute on function public.sol_enviar3(text, text, bigint, jsonb) to authenticated;
