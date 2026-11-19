# Fontes dos módulos da fábrica

- `originais/`: os programas como foram feitos (Manutenção, Uniformes e EPI e o Estoque de garrafões antigo, que não é mais usado).
- `empilhadeiras.html`: o módulo Checklist de empilhadeiras.
- `garrafoes.html`: o módulo Estoque de garrafões (refeito em 17/11/2026; segunda versão em 19/11/2026: novos por marca e fabricação, sucata só por litragem, assinatura do cliente na tela na venda e na troca, foto da nota pela câmera na entrada; regras no banco pelas migrações 0056 e 0057).
- `manutencao-fichas.js`: fichas de manutenção preventiva e de lubrificação em planilha ou no checklist do Word (.docx) (importar, ver a ficha com O/X/NA ou em lista, baixar), inserido no programa da Manutenção pelo `montar.py`.
- `manutencao-extra.js`: pedidos de 21/10/2026 na Manutenção (apagar chamado só a senha mestre, materiais no atendimento, documentação em PDF e QR da máquina, estoque por máquina, fotos das peças, selecionar vários e excluir), inserido depois das fichas.
- `ponte.js`: liga os módulos ao login e ao banco do LEVÍSSIMA (sem a configuração do Supabase).
- `montar.py`: gera `www/modulos/` a partir daqui: `python3 montar.py ../../www <url do Supabase> <chave pública>`.

Para mudar um módulo, altere o arquivo daqui e rode o `montar.py` de novo.
