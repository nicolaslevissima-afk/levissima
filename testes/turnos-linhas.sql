-- linhas como estavam no banco em 23/11/2026 (horários próprios, sem rhId)
update public.docs set data = jsonb_set(data, '{linhas}', '[
 {"id":"l1","nome":"Linha 1","metaId":"l1","un":"fardos","produtos":["1,5L natural"],"maquinas":[],"turnos":[{"fim":"13:15","dias":[1,2,3,4,5,6],"nome":"DESC 1","pausa":0,"inicio":"05:20"},{"fim":"21:00","dias":[1,2,3,4,5,6],"nome":"DESC 2","pausa":0,"inicio":"12:10"},{"fim":"05:20","dias":[1,2,3,4,5],"nome":"DESC 3","pausa":0,"inicio":"20:55"}]},
 {"id":"linha2","nome":"Linha 2","metaId":"l2","un":"fardos","produtos":["510ml natural"],"maquinas":[],"turnos":[{"fim":"13:15","dias":[1,2,3,4,5,6],"nome":"DESC 1","pausa":0,"inicio":"05:20"}]},
 {"id":"g10","nome":"Linha 10 L","metaId":"g10","un":"galões","produtos":["10L"],"maquinas":[],"turnos":[]},
 {"id":"copo","nome":"Copos","metaId":"copo","un":"caixas","produtos":[],"maquinas":[],"turnos":[]},
 {"id":"retornavel","nome":"Retornável","metaId":"ret","un":"garrafões","produtos":[],"maquinas":[],"op":false,"turnos":["Retornável 1 (dia)","Retornável 2 (noite)"]}
]'::jsonb) where colecao = 'mp-config' and id = 'linhas-producao';
insert into public.docs (colecao, id, data) values ('equipe', 'equipe-laura', '{"nome":"Laura","configuraPcp":true}') on conflict do nothing;
