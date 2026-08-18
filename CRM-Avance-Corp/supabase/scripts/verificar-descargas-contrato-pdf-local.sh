#!/usr/bin/env bash

set -euo pipefail

readonly QA_MAX_PDF_BYTES='10485760'

usage() {
  cat <<'USAGE'
Uso:
  verificar-descargas-contrato-pdf-local.sh \
    --origin http://127.0.0.1:55321 \
    --inmediata /ruta/descarga-inmediata.pdf \
    --mi-cartera /ruta/descarga-mi-cartera.pdf \
    --posterior /ruta/descarga-posterior.pdf \
    [--expected-sha256 HEX_64 --expected-bytes ENTERO]

Compara offline tres archivos regulares, distintos y no symlink. Comprueba
cabecera PDF, límite de 10 MiB, tamaño, SHA-256 y finalmente igualdad byte a
byte con cmp. --origin es evidencia declarada del entorno y solo admite el API
local en loopback:55321; cualquier mención de supabase.co se rechaza.

El script no descarga archivos ni realiza solicitudes de red.
USAGE
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_value() {
  [[ $# -ge 2 && -n "$2" ]] || fail "Falta el valor de $1"
}

sha256_file() {
  local qa_file=$1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$qa_file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$qa_file" | awk '{print $1}'
  else
    fail 'Falta sha256sum o shasum'
  fi
}

canonical_file() {
  local qa_file=$1
  local qa_dir
  local qa_base
  qa_dir="$(cd "$(dirname "$qa_file")" && pwd -P)"
  qa_base="$(basename "$qa_file")"
  printf '%s/%s\n' "$qa_dir" "$qa_base"
}

file_identity() {
  local qa_file=$1
  if stat -f '%d:%i' "$qa_file" >/dev/null 2>&1; then
    stat -f '%d:%i' "$qa_file"
  else
    stat -c '%d:%i' "$qa_file"
  fi
}

verify_pdf() {
  local qa_label=$1
  local qa_file=$2
  local qa_size
  local qa_magic

  [[ -f "$qa_file" && ! -L "$qa_file" && -r "$qa_file" ]] || \
    fail "$qa_label no es un archivo regular, legible y no symlink: $qa_file"
  qa_size="$(wc -c < "$qa_file" | tr -d '[:space:]')"
  [[ "$qa_size" =~ ^[0-9]+$ && "$qa_size" -gt 0 ]] || \
    fail "$qa_label está vacío o tiene tamaño inválido"
  [[ "$qa_size" -le "$QA_MAX_PDF_BYTES" ]] || \
    fail "$qa_label supera el límite contractual de 10 MiB"
  qa_magic="$(LC_ALL=C head -c 5 "$qa_file")"
  [[ "$qa_magic" == '%PDF-' ]] || fail "$qa_label no empieza con %PDF-"
}

main() {
  local qa_origin=''
  local qa_inmediata=''
  local qa_mi_cartera=''
  local qa_posterior=''
  local qa_expected_sha=''
  local qa_expected_bytes=''
  local qa_origin_lower
  local qa_path_inmediata
  local qa_path_mi_cartera
  local qa_path_posterior
  local qa_identity_inmediata
  local qa_identity_mi_cartera
  local qa_identity_posterior
  local qa_sha_inmediata
  local qa_sha_mi_cartera
  local qa_sha_posterior
  local qa_bytes_inmediata
  local qa_bytes_mi_cartera
  local qa_bytes_posterior

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --origin)
        require_value "$@"
        qa_origin=$2
        shift 2
        ;;
      --inmediata)
        require_value "$@"
        qa_inmediata=$2
        shift 2
        ;;
      --mi-cartera)
        require_value "$@"
        qa_mi_cartera=$2
        shift 2
        ;;
      --posterior)
        require_value "$@"
        qa_posterior=$2
        shift 2
        ;;
      --expected-sha256)
        require_value "$@"
        qa_expected_sha=$2
        shift 2
        ;;
      --expected-bytes)
        require_value "$@"
        qa_expected_bytes=$2
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        usage >&2
        fail "Argumento desconocido: $1"
        ;;
    esac
  done

  [[ -n "$qa_origin" && -n "$qa_inmediata" && -n "$qa_mi_cartera" && -n "$qa_posterior" ]] || {
    usage >&2
    fail 'Faltan argumentos obligatorios'
  }

  qa_origin_lower="$(printf '%s' "$qa_origin" | tr '[:upper:]' '[:lower:]')"
  case "$qa_origin_lower" in
    *supabase.co*) fail 'Se rehúsa validar una descarga declarada desde *.supabase.co' ;;
  esac
  case "$qa_origin_lower" in
    http://127.0.0.1:55321|http://127.0.0.1:55321/|http://localhost:55321|http://localhost:55321/|http://\[::1\]:55321|http://\[::1\]:55321/) ;;
    *) fail 'El origen debe ser exactamente el API local de loopback en el puerto 55321' ;;
  esac

  if [[ -n "$qa_expected_sha" || -n "$qa_expected_bytes" ]]; then
    [[ -n "$qa_expected_sha" && -n "$qa_expected_bytes" ]] || \
      fail 'expected-sha256 y expected-bytes deben proporcionarse juntos'
    qa_expected_sha="$(printf '%s' "$qa_expected_sha" | tr '[:upper:]' '[:lower:]')"
    [[ "$qa_expected_sha" =~ ^[0-9a-f]{64}$ ]] || \
      fail 'expected-sha256 debe contener exactamente 64 dígitos hexadecimales'
    [[ "$qa_expected_bytes" =~ ^[1-9][0-9]*$ ]] || \
      fail 'expected-bytes debe ser un entero positivo'
  fi

  verify_pdf 'descarga inmediata' "$qa_inmediata"
  verify_pdf 'descarga Mi cartera' "$qa_mi_cartera"
  verify_pdf 'descarga posterior' "$qa_posterior"

  qa_path_inmediata="$(canonical_file "$qa_inmediata")"
  qa_path_mi_cartera="$(canonical_file "$qa_mi_cartera")"
  qa_path_posterior="$(canonical_file "$qa_posterior")"
  [[ "$qa_path_inmediata" != "$qa_path_mi_cartera" && \
     "$qa_path_inmediata" != "$qa_path_posterior" && \
     "$qa_path_mi_cartera" != "$qa_path_posterior" ]] || \
    fail 'Las tres evidencias deben usar rutas de archivo distintas'

  qa_identity_inmediata="$(file_identity "$qa_inmediata")"
  qa_identity_mi_cartera="$(file_identity "$qa_mi_cartera")"
  qa_identity_posterior="$(file_identity "$qa_posterior")"
  [[ "$qa_identity_inmediata" != "$qa_identity_mi_cartera" && \
     "$qa_identity_inmediata" != "$qa_identity_posterior" && \
     "$qa_identity_mi_cartera" != "$qa_identity_posterior" ]] || \
    fail 'Las tres evidencias deben ser archivos físicos distintos, no hardlinks'

  qa_sha_inmediata="$(sha256_file "$qa_inmediata")"
  qa_sha_mi_cartera="$(sha256_file "$qa_mi_cartera")"
  qa_sha_posterior="$(sha256_file "$qa_posterior")"
  qa_bytes_inmediata="$(wc -c < "$qa_inmediata" | tr -d '[:space:]')"
  qa_bytes_mi_cartera="$(wc -c < "$qa_mi_cartera" | tr -d '[:space:]')"
  qa_bytes_posterior="$(wc -c < "$qa_posterior" | tr -d '[:space:]')"

  [[ "$qa_sha_inmediata" == "$qa_sha_mi_cartera" && \
     "$qa_sha_inmediata" == "$qa_sha_posterior" ]] || \
    fail 'Los SHA-256 de las tres descargas no coinciden'
  [[ "$qa_bytes_inmediata" == "$qa_bytes_mi_cartera" && \
     "$qa_bytes_inmediata" == "$qa_bytes_posterior" ]] || \
    fail 'Los tamaños de las tres descargas no coinciden'
  cmp -s "$qa_inmediata" "$qa_mi_cartera" || \
    fail 'La descarga inmediata y Mi cartera difieren byte a byte'
  cmp -s "$qa_inmediata" "$qa_posterior" || \
    fail 'La descarga inmediata y la posterior difieren byte a byte'

  if [[ -n "$qa_expected_sha" ]]; then
    [[ "$qa_sha_inmediata" == "$qa_expected_sha" ]] || \
      fail 'El SHA-256 común no coincide con el esperado'
    [[ "$qa_bytes_inmediata" == "$qa_expected_bytes" ]] || \
      fail 'El tamaño común no coincide con el esperado'
  fi

  printf 'CONTRATO_PDF_DESCARGAS_OK\n'
  printf 'origin=%s\n' "$qa_origin_lower"
  printf 'sha256=%s\n' "$qa_sha_inmediata"
  printf 'bytes=%s\n' "$qa_bytes_inmediata"
  printf 'copias=3\n'
  printf 'inmediata=%s\n' "$qa_path_inmediata"
  printf 'mi_cartera=%s\n' "$qa_path_mi_cartera"
  printf 'posterior=%s\n' "$qa_path_posterior"
}

main "$@"
