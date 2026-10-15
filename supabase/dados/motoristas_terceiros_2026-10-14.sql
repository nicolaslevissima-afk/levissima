-- Motoristas terceiros contratados a serviço da Levíssima (cadastrados em 14/10/2026, a pedido do Nicolas).
-- Sem senha: o Nicolas cria a senha de cada um em Cadastros › Motoristas › Abrir › Trocar senha.
insert into public.docs (colecao, id, data) values
  ('motoristas', 'mot-renan-franca',        '{"nome": "Renan França",        "telefone": "", "vinculo": "terceiro", "criadoEm": "2026-10-14T23:10:00.000Z"}'),
  ('motoristas', 'mot-silvestre-pereira',   '{"nome": "Silvestre Pereira",   "telefone": "", "vinculo": "terceiro", "criadoEm": "2026-10-14T23:10:00.000Z"}'),
  ('motoristas', 'mot-sergio-felix',        '{"nome": "Sérgio Félix",        "telefone": "", "vinculo": "terceiro", "criadoEm": "2026-10-14T23:10:00.000Z"}'),
  ('motoristas', 'mot-guilherme-lourencon', '{"nome": "Guilherme Lourençon", "telefone": "", "vinculo": "terceiro", "criadoEm": "2026-10-14T23:10:00.000Z"}')
on conflict do nothing;
