# LEVÍSSIMA · backups

Repositório **privado** com o backup diário do app LEVÍSSIMA (banco do Supabase e arquivos: fotos, PDFs, documentos).

## Como funciona

- Todo dia às **03:17** (horário de Brasília) o GitHub roda `.github/workflows/backup.yml`.
- Ele se identifica para a função `backup` do Supabase com o token do próprio GitHub (sem senha guardada), baixa todas
  as tabelas e os arquivos, junta num `.tar.gz` e **cifra com a frase `BACKUP_SENHA`** (AES-256).
- Cada backup vira uma **release** deste repositório (aba *Releases*):
  - `diario-AAAA-MM-DD`: o banco inteiro e os arquivos novos dos últimos 3 dias — **guardados por 30 dias**;
  - `mensal-AAAA-MM`: o banco inteiro e **todos** os arquivos — **guardados por 12 meses**.
- O app mostra o último backup em **Cadastros › Segurança**. Se o backup falhar, o GitHub manda e-mail.
- Ficam de fora só os segredos e o que é passageiro: depois de restaurar, cadastre de novo os **PINs** da equipe e o
  **código do autenticador** da senha mestre. As senhas de acesso continuam valendo.

## A frase BACKUP_SENHA

Fica em *Settings › Secrets and variables › Actions*. **Guarde uma cópia num lugar seguro fora do computador**
(sem ela, ninguém abre os backups — nem a LEVÍSSIMA). Ninguém além de você deve conhecer essa frase.

## Abrir um backup

1. Baixe o arquivo `levissima-....tar.gz.gpg` da release.
2. Num computador com `gpg` (Linux/Mac; no Windows, Gpg4win):

   ```
   gpg --decrypt levissima-diario-2026-11-02.tar.gz.gpg > backup.tar.gz
   tar -xzf backup.tar.gz
   ```

   O `gpg` pede a frase `BACKUP_SENHA`.
3. Dentro: `banco/<tabela>.ndjson` (uma linha JSON por registro), `arquivos/<bucket>/<caminho>` e `LEIA.json`.

## Restaurar

A restauração deve ser feita com cuidado, de preferência num projeto do Supabase novo ou com o app parado:
cada linha de `banco/<tabela>.ndjson` volta para a tabela de mesmo nome (`insert ... on conflict do nothing`), e os
arquivos voltam para o bucket de mesmo nome no Storage. Peça ajuda ao Claude com o arquivo já aberto.
