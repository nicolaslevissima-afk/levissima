-- LEVÍSSIMA · códigos de barras por produto (PDF CODIGOS DE BARRA ATUALIZADO, 15/10/2026) e a marca Bom Coração.
-- EAN da garrafa e DUN do pacote. Dois números do PDF tinham dígito verificador errado e entraram corrigidos (o número do PDF também fica, para quem digitar):
-- Levíssima 510ml com gás 7897345102124 -> 7897345105124; Bulnez 1,5L natural 7898976797082 -> 7898976797085 (confirmar lendo a embalagem).
insert into public.docs (colecao, id, data) values
('produtos','marca-bom-coracao-510ml-natural','{"nome": "Bom Coração 510ml natural", "ordem": 26, "unidade": "fardos", "tipoChapatex": "fileira", "unidadesPorPalete": 150, "unidadesPorFileira": 25, "codigosBarras": ["7897345145113", "17897345145110"]}'::jsonb),
('produtos','marca-bom-coracao-510ml-gas','{"nome": "Bom Coração 510ml com gás", "ordem": 27, "unidade": "fardos", "tipoChapatex": "fileira", "unidadesPorPalete": 150, "unidadesPorFileira": 25, "codigosBarras": ["7897345145120", "17897345145127"]}'::jsonb),
('produtos','marca-bom-coracao-1500ml-natural','{"nome": "Bom Coração 1,5L natural", "ordem": 28, "unidade": "fardos", "tipoChapatex": "fileira", "unidadesPorPalete": 112, "unidadesPorFileira": 28, "codigosBarras": ["7897345145175", "17897345145172"]}'::jsonb),
('produtos','marca-bom-coracao-1500ml-gas','{"nome": "Bom Coração 1,5L com gás", "ordem": 29, "unidade": "fardos", "tipoChapatex": "fileira", "unidadesPorPalete": 112, "unidadesPorFileira": 28, "codigosBarras": ["7897345145182", "17897345145189"]}'::jsonb),
('produtos','marca-bom-coracao-6l','{"nome": "Bom Coração 6L", "ordem": 30, "unidade": "galões", "tipoChapatex": "fileira", "unidadesPorPalete": 168, "unidadesPorFileira": 42, "codigosBarras": ["7897345145311", "17897345145318"]}'::jsonb)
on conflict (colecao, id) do nothing;
update public.docs d set data = d.data || jsonb_build_object('codigosBarras', v.cods), atualizado_em = now()
from (values
('padrao-01-copo-200ml', '["7897345105018", "17897345105015", "27897345105012"]'::jsonb),
('padrao-02-copo-300ml', '["7897345105025", "17897345105022"]'::jsonb),
('padrao-03-350ml-natural', '["7897345105070", "17897345105077"]'::jsonb),
('padrao-04-350ml-gas', '["7897345105087", "17897345105084"]'::jsonb),
('padrao-05-510ml-natural', '["7897345105117", "17897345105114"]'::jsonb),
('padrao-06-510ml-gas', '["7897345105124", "17897345105121", "7897345102124"]'::jsonb),
('padrao-07-1500ml-natural', '["7897345105179", "17897345105176"]'::jsonb),
('padrao-07b-1500ml-gas', '["7897345105186", "17897345105183"]'::jsonb),
('padrao-08-6l', '["7897345105315", "17897345105312"]'::jsonb),
('padrao-09-10l', '["7897345105353"]'::jsonb),
('marca-colina-azul-510ml-natural', '["7897345104110", "17897345104117"]'::jsonb),
('marca-colina-azul-510ml-gas', '["7897345104127", "17897345104124"]'::jsonb),
('marca-colina-azul-1500ml-natural', '["7897345104172", "17897345104179"]'::jsonb),
('marca-colina-azul-1500ml-gas', '["7897345104189", "17897345104186"]'::jsonb),
('marca-colina-azul-6l', '["7897345104318", "17897345104315"]'::jsonb),
('marca-casa-de-mae-510ml-natural', '["7898701308210", "17898701308217"]'::jsonb),
('marca-casa-de-mae-510ml-gas', '["7898701308227", "17898701308224"]'::jsonb),
('marca-casa-de-mae-1500ml-natural', '["7898701308234", "17898701308231"]'::jsonb),
('marca-casa-de-mae-1500ml-gas', '["7898701308241", "17898701308248"]'::jsonb),
('marca-casa-de-mae-6l', '["7898701308203", "17898701308200"]'::jsonb),
('marca-new-mania-510ml-natural', '["7897345135114"]'::jsonb),
('marca-betel-510ml-natural', '["7897345115116"]'::jsonb),
('marca-bulnez-510ml-natural', '["7898976798075"]'::jsonb),
('marca-bulnez-1500ml-natural', '["7898976797085", "7898976797082"]'::jsonb)
) as v(id, cods)
where d.colecao = 'produtos' and d.id = v.id and coalesce(jsonb_array_length(d.data->'codigosBarras'), 0) = 0
returning d.id;
-- Matéria-prima da Bom Coração (rótulos e fichas técnicas, iguais às das outras marcas): carregada em 16/10/2026 pelo mesmo
-- formato de dados/materia_prima_2026-10-15.sql (ins-rt-bom-coracao-* e mp-fichas/marca-bom-coracao-*).
