# Fontes dos módulos da fábrica

- `originais/`: os programas como foram feitos (Manutenção, Uniformes e EPI, Estoque de garrafões).
- `empilhadeiras.html`: o módulo Checklist de empilhadeiras.
- `ponte.js`: liga os módulos ao login e ao banco do LEVÍSSIMA (sem a configuração do Supabase).
- `montar.py`: gera `www/modulos/` a partir daqui: `python3 montar.py ../../www <url do Supabase> <chave pública>`.

Para mudar um módulo, altere o arquivo daqui e rode o `montar.py` de novo.
