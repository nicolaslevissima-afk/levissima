# Fontes dos módulos da fábrica

- `originais/`: os programas como foram feitos (Manutenção, Uniformes e EPI, Estoque de garrafões).
- `empilhadeiras.html`: o módulo Checklist de empilhadeiras.
- `manutencao-fichas.js`: fichas de manutenção preventiva em planilha (importar, ver a ficha com O/X/NA, baixar), inserido no programa da Manutenção pelo `montar.py`.
- `manutencao-extra.js`: pedidos de 21/10/2026 na Manutenção (apagar chamado só a senha mestre, materiais no atendimento, documentação em PDF e QR da máquina, estoque por máquina, fotos das peças, selecionar vários e excluir), inserido depois das fichas.
- `ponte.js`: liga os módulos ao login e ao banco do LEVÍSSIMA (sem a configuração do Supabase).
- `montar.py`: gera `www/modulos/` a partir daqui: `python3 montar.py ../../www <url do Supabase> <chave pública>`.

Para mudar um módulo, altere o arquivo daqui e rode o `montar.py` de novo.
