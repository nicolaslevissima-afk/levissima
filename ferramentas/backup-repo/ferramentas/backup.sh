#!/usr/bin/env bash
# LEVÍSSIMA · backup diário (roda no GitHub Actions do repositório privado levissima-backups).
# 1. pede um token OIDC ao GitHub e baixa, pela função "backup" do Supabase, todas as tabelas e os arquivos;
# 2. junta tudo num .tar.gz e cifra com a frase BACKUP_SENHA (gpg, AES-256);
# 3. guarda como release: "diario-AAAA-MM-DD" (banco + arquivos novos dos últimos 3 dias) e, no dia 1º de cada mês
#    (ou se o mês ainda não tem), "mensal-AAAA-MM" (banco + todos os arquivos);
# 4. apaga os diários com mais de 30 dias e os mensais com mais de 12 meses;
# 5. avisa o app (Cadastros › Segurança mostra o último backup).
set -euo pipefail

FUNCAO="${FUNCAO_BACKUP:-https://lzsvtwwpthjncrhznfez.supabase.co/functions/v1/backup}"
if [ "${#BACKUP_SENHA}" -lt 16 ]; then
  echo "::error::Falta o segredo BACKUP_SENHA (frase de pelo menos 16 caracteres) em Settings › Secrets and variables › Actions."
  exit 1
fi

token() {
  curl -sSf -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=levissima-backup" | jq -r .value
}
chamar() { # chamar '<json>'  (token novo a cada chamada: ele vale poucos minutos)
  curl -sSf --retry 3 --retry-delay 5 -X POST "$FUNCAO" -H "Authorization: Bearer $(token)" -H 'Content-Type: application/json' -d "$1"
}

HOJE=$(TZ=America/Sao_Paulo date +%F)
MES=$(TZ=America/Sao_Paulo date +%Y-%m)
TIPO=diario
if [ "$(TZ=America/Sao_Paulo date +%d)" = "01" ] || ! gh release view "mensal-$MES" > /dev/null 2>&1; then TIPO=mensal; fi

PASTA=$(mktemp -d)
mkdir -p "$PASTA/banco" "$PASTA/arquivos"

# ---- tabelas ----
TABELAS=$(chamar '{"acao":"tabelas"}')
N_TAB=0; N_LIN=0
for T in $(echo "$TABELAS" | jq -r '.tabelas[]'); do
  OFF=0; : > "$PASTA/banco/$T.ndjson"
  while true; do
    PAG=$(chamar "$(jq -nc --arg t "$T" --argjson o "$OFF" '{acao:"pagina",tabela:$t,offset:$o}')")
    QTD=$(echo "$PAG" | jq '.linhas | length')
    echo "$PAG" | jq -c '.linhas[]' >> "$PASTA/banco/$T.ndjson"
    N_LIN=$((N_LIN + QTD)); OFF=$((OFF + QTD))
    if [ "$QTD" -lt 500 ]; then break; fi
  done
  N_TAB=$((N_TAB + 1))
  echo "tabela $T: $OFF linhas"
done

# ---- arquivos (fotos, PDFs, documentos) ----
if [ "$TIPO" = mensal ]; then CORPO='{"acao":"arquivos"}'
else CORPO=$(jq -nc --arg d "$(date -u -d '3 days ago' +%FT%TZ)" '{acao:"arquivos",desde:$d}'); fi
chamar "$CORPO" > "$PASTA/arquivos.json"
N_ARQ=0
while IFS=$'\t' read -r B NOME URL; do
  if [ -z "$URL" ] || [ "$URL" = null ]; then continue; fi
  DEST="$PASTA/arquivos/$B/$NOME"
  case "$DEST" in *..*) continue ;; esac
  mkdir -p "$(dirname "$DEST")"
  if curl -sSf --retry 3 -o "$DEST" "$URL"; then N_ARQ=$((N_ARQ + 1)); else echo "::warning::Não baixou $B/$NOME"; fi
done < <(jq -r '.arquivos[] | [.bucket, .nome, (.url // "null")] | @tsv' "$PASTA/arquivos.json")
# a lista guardada não leva os links (eles expiram e não servem depois)
jq '{arquivos: [.arquivos[] | del(.url)]}' "$PASTA/arquivos.json" > "$PASTA/arquivos-lista.json" && rm "$PASTA/arquivos.json"

jq -n --arg em "$(date -u +%FT%TZ)" --arg tipo "$TIPO" --argjson t "$N_TAB" --argjson l "$N_LIN" --argjson a "$N_ARQ" \
  '{feitoEm:$em, tipo:$tipo, tabelas:$t, linhas:$l, arquivos:$a, formato:"banco/<tabela>.ndjson (uma linha JSON por registro) e arquivos/<bucket>/<caminho>"}' > "$PASTA/LEIA.json"

# ---- cifrar e guardar ----
TAG="diario-$HOJE"; [ "$TIPO" = mensal ] && TAG="mensal-$MES"
SAIDA="levissima-$TAG.tar.gz.gpg"
tar -C "$PASTA" -czf - . | gpg --batch --yes --pinentry-mode loopback --symmetric --cipher-algo AES256 --s2k-digest-algo SHA512 --s2k-count 65011712 \
  --passphrase-fd 3 -o "$SAIDA" 3<<< "$BACKUP_SENHA"
rm -rf "$PASTA"
TAM=$(stat -c %s "$SAIDA")
gh release delete "$TAG" --yes --cleanup-tag > /dev/null 2>&1 || true
gh release create "$TAG" "$SAIDA" --title "Backup $TAG" --notes "Backup $TIPO de $HOJE: $N_TAB tabelas, $N_LIN registros, $N_ARQ arquivos. Cifrado (AES-256); para abrir, veja o README."
# no dia em que sai o mensal, sai também o diário (o mensal é o mesmo conteúdo, mais completo)
if [ "$TIPO" = mensal ]; then gh release delete "diario-$HOJE" --yes --cleanup-tag > /dev/null 2>&1 || true; fi

# ---- prazo: 30 dias para os diários, 12 meses para os mensais ----
LIMITE_D=$(date -u -d '30 days ago' +%s); LIMITE_M=$(date -u -d '370 days ago' +%s)
gh release list --limit 400 --json tagName,createdAt | jq -r '.[] | [.tagName, .createdAt] | @tsv' | while IFS=$'\t' read -r T EM; do
  S=$(date -u -d "$EM" +%s)
  case "$T" in
    diario-*) if [ "$S" -lt "$LIMITE_D" ]; then gh release delete "$T" --yes --cleanup-tag; fi ;;
    mensal-*) if [ "$S" -lt "$LIMITE_M" ]; then gh release delete "$T" --yes --cleanup-tag; fi ;;
  esac
done

chamar "$(jq -nc --arg tipo "$TIPO" --arg tag "$TAG" --argjson tam "$TAM" --argjson t "$N_TAB" --argjson l "$N_LIN" --argjson a "$N_ARQ" \
  '{acao:"concluido", tipo:$tipo, tag:$tag, tamanho:$tam, tabelas:$t, linhas:$l, arquivos:$a}')" > /dev/null
echo "Backup $TAG pronto: $TAM bytes, $N_TAB tabelas, $N_LIN registros, $N_ARQ arquivos."
