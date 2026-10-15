-- LEVÍSSIMA · representantes da Força de vendas (só os nomes; cada senha é criada pela senha mestre no app).
insert into public.docs (colecao, id, data)
select 'representantes', r.id, jsonb_build_object('nome', r.nome, 'telefone', '', 'criadoEm', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
from (values ('rep-luis', 'Luís'), ('rep-emerson', 'Émerson'), ('rep-luccas', 'Luccas'), ('rep-marcone', 'Marcone'), ('rep-ana-clara', 'Ana Clara'),
             ('rep-matheus', 'Matheus'), ('rep-mauricio', 'Mauricio'), ('rep-marcelo', 'Marcelo'), ('rep-renato', 'Renato')) as r(id, nome)
on conflict do nothing;
