#!/bin/zsh
# uso: medir.sh <actor_uuid> '<expresión sql>' <etiqueta>
# Ejecuta la expresión como el actor dentro de un DO que SIEMPRE termina en raise (nada se escribe)
# y devuelve los recorridos (seq/idx) por tabla de ESA transacción (pg_stat_xact_user_tables).
S="$(dirname "$0")"
f="$S/medida-$3.sql"
cat > "$f" <<SQL
do \$m\$
declare v_t0 timestamptz; v_ms int; v_seq text; v_idx text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub','$1','role','authenticated')::text, true);
  v_t0 := clock_timestamp();
  perform $2;
  v_ms := round(extract(epoch from clock_timestamp()-v_t0)*1000);
  select string_agg(format('%s.%s seq=%s (%s filas)', schemaname, relname, seq_scan, seq_tup_read), ' · ' order by seq_tup_read desc)
    into v_seq from pg_stat_xact_user_tables where schemaname in ('crm','private','public') and seq_scan>0;
  select string_agg(format('%s idx=%s', relname, idx_scan), ' · ' order by idx_scan desc)
    into v_idx from (select relname, idx_scan from pg_stat_xact_user_tables where schemaname in ('crm','private','public') and idx_scan>0 order by idx_scan desc limit 6) x;
  raise exception 'MEDIDA|% ms|SEQ: %|IDX: %', v_ms, coalesce(v_seq,'-'), coalesce(v_idx,'-');
end \$m\$;
SQL
cd "/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp"
out=$(supabase db query --linked -f "$f" 2>/dev/null)
msg=$(printf '%s' "$out" | python3 -c '
import sys,json,re
raw=sys.stdin.read()
m=re.search(r"MEDIDA\|(.*?)(?:\\\\n|\\n|\")", raw.replace("\\\\","\\"))
if m: print(m.group(1))
else:
    e=re.search(r"ERROR:\s*(.{0,300})", raw); print("ERROR: "+(e.group(1) if e else raw[:300]))
')
echo "[$3] $msg"
