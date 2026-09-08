#!/bin/bash
# Oráculo del ensayo de la plantilla v8. Cada caso corre sobre una copia limpia
# del banco (create database ... template), así que un caso nunca contamina al
# siguiente.
set -uo pipefail
export PGPASSWORD=postgres
PG="psql -h 127.0.0.1 -p 55322 -U postgres -v ON_ERROR_STOP=1 -tA"
BASE=banco_pdf_v8
MIG="/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp/supabase/migrations/20260908173000_crm_contrato_pdf_plantilla_v8_letra_legible.sql"
REV="/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp/supabase/scripts/rollback-pdf-v8.sql"
OK=0; MAL=0

copia() { # $1 = nombre de la copia
  $PG -d postgres -c "drop database if exists $1;" >/dev/null
  $PG -d postgres -c "create database $1 template $BASE;" >/dev/null
}

afirma() { # $1 = etiqueta, $2 = esperado, $3 = obtenido
  if [ "$2" == "$3" ]; then OK=$((OK+1)); echo "  ✅ $1";
  else MAL=$((MAL+1)); echo "  ❌ $1 · esperado [$2] · obtenido [$3]"; fi
}

huella_funciones() { # $1 = base
  $PG -d "$1" -c "select string_agg(p.oid::text||'|'||pg_get_userbyid(p.proowner)||'|'||coalesce(p.proacl::text,'-')||'|'||p.prosecdef::text||'|'||coalesce(array_to_string(p.proconfig,','),'-')||'|'||p.provolatile::text, ' ~ ' order by p.proname)
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname in ('crear_job_contrato_pdf_base','crear_revision_contrato_pdf_base');"
}

echo "════ CASO 1 · camino feliz ════"
copia t1
ANTES_FN=$(huella_funciones t1)
ANTES_PDFS=$($PG -d t1 -c "select md5(string_agg(t::text, '|' order by t::text)) from private.contrato_pdfs t;")
SALIDA=$($PG -d t1 -f "$MIG" 2>&1)
echo "$SALIDA" | grep -q "CONTRATO_PDF_V8_MIGRATION_OK" && R=ok || R="fallo: $(echo "$SALIDA" | tail -2)"
afirma "la migración termina con CONTRATO_PDF_V8_MIGRATION_OK" "ok" "$R"
afirma "caso 1 · pendiente sin bytes pasa a v8" "contrato-aep-17-v8" "$($PG -d t1 -c "select template_version from private.contrato_pdf_jobs where id='11111111-1111-4111-8111-111111111111';")"
afirma "caso 2 · error_reintentable sin bytes pasa a v8" "contrato-aep-17-v8" "$($PG -d t1 -c "select template_version from private.contrato_pdf_jobs where id='22222222-2222-4222-8222-222222222222';")"
afirma "caso 3 · error_reintentable CON bytes se queda en v7" "contrato-aep-17-v7" "$($PG -d t1 -c "select template_version from private.contrato_pdf_jobs where id='33333333-3333-4333-8333-333333333333';")"
afirma "los jobs sellados no se tocan" "contrato-aep-17-v5|contrato-aep-17-v7" "$($PG -d t1 -c "select string_agg(template_version,'|' order by template_version) from private.contrato_pdf_jobs where estado='sellado';")"
afirma "el ledger de PDFs sellados queda idéntico" "$ANTES_PDFS" "$($PG -d t1 -c "select md5(string_agg(t::text, '|' order by t::text)) from private.contrato_pdfs t;")"
afirma "la huella de atributos no viene vacía (si no, no mide nada)" "si" "$([ -n "$ANTES_FN" ] && [[ "$ANTES_FN" == *"postgres=X/postgres"* ]] && echo si || echo no)"
afirma "propietario, ACL, secdef, search_path, volatilidad y OID intactos" "$ANTES_FN" "$(huella_funciones t1)"
afirma "y el search_path vacío sobrevive CON sus comillas" 'search_path=""' "$($PG -d t1 -c "select array_to_string(p.proconfig,',') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='crear_job_contrato_pdf_base';")"
afirma "las dos funciones estampan ya la v8" "2" "$($PG -d t1 -c "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and strpos(p.prosrc,'contrato-aep-17-v8')>0;")"
afirma "ninguna función estampa ya la v7" "0" "$($PG -d t1 -c "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname not in ('pg_catalog','information_schema') and p.prokind in ('f','p') and strpos(pg_get_functiondef(p.oid),'contrato-aep-17-v7')>0;")"
afirma "el trigger de inmutabilidad quedó habilitado en origen" "O" "$($PG -d t1 -c "select tgenabled from pg_trigger where tgrelid='private.contrato_pdf_jobs'::regclass and tgname='contrato_pdf_jobs_transiciones_validas';")"
afirma "el default de template_version es la v8" "'contrato-aep-17-v8'::text" "$($PG -d t1 -c "select column_default from information_schema.columns where table_schema='private' and table_name='contrato_pdf_jobs' and column_name='template_version';")"
afirma "el trigger sigue bloqueando el borrado de jobs" "ERROR" "$($PG -d t1 -c "delete from private.contrato_pdf_jobs where id='11111111-1111-4111-8111-111111111111';" 2>&1 | grep -o ERROR | head -1)"
afirma "los dos CHECK siguen presentes" "2" "$($PG -d t1 -c "select count(*) from pg_constraint where conname in ('contrato_pdf_jobs_template_valido','contrato_pdfs_version_ruta_valida');")"
afirma "el CHECK nuevo rechaza una versión inventada" "ERROR" "$($PG -d t1 -c "update private.contrato_pdf_jobs set template_version='contrato-aep-17-v9' where id='11111111-1111-4111-8111-111111111111';" 2>&1 | grep -o ERROR | head -1)"

echo "════ CASO 2 · reserva v7 EN VUELO (lease vivo) ════"
copia t2
$PG -d t2 -c "insert into private.contrato_pdf_jobs (id,contrato_id,revision,estado,storage_path,nombre_archivo,template_version,snapshot,solicitado_por,lease_token,lease_expira_en) values ('44444444-4444-4444-8444-444444444444','aaaaaaa4-4444-4444-8444-444444444444',1,'procesando','aaaaaaa4-4444-4444-8444-444444444444/v2/44444444-4444-4444-8444-444444444444/contrato.pdf','Contrato-caso-4.pdf','contrato-aep-17-v7','{\"caso\":4}'::jsonb,'99999999-9999-4999-8999-999999999999','88888888-8888-4888-8888-888888888888', now() + interval '5 minutes');" >/dev/null
SALIDA=$($PG -d t2 -f "$MIG" 2>&1)
echo "$SALIDA" | grep -q "reservas v7 en vuelo" && R=aborta || R="NO abortó: $(echo "$SALIDA" | tail -2)"
afirma "el preflight aborta con las reservas en vuelo" "aborta" "$R"
afirma "tras abortar, nada cambió de versión" "contrato-aep-17-v7" "$($PG -d t2 -c "select template_version from private.contrato_pdf_jobs where id='11111111-1111-4111-8111-111111111111';")"
afirma "tras abortar, el trigger sigue habilitado" "O" "$($PG -d t2 -c "select tgenabled from pg_trigger where tgrelid='private.contrato_pdf_jobs'::regclass and tgname='contrato_pdf_jobs_transiciones_validas';")"

echo "════ CASO 3 · MUTANTE del P0: el UPDATE falla a mitad ════"
copia t3
$PG -d t3 -c "alter table private.contrato_pdf_jobs add constraint mutante_prohibe_v8 check (not (template_version='contrato-aep-17-v8' and estado='pendiente'));" >/dev/null
SALIDA=$($PG -d t3 -f "$MIG" 2>&1)
echo "$SALIDA" | grep -q "mutante_prohibe_v8" && R=falla || R="no falló donde se esperaba"
afirma "el UPDATE falla por el mutante" "falla" "$R"
afirma "el rollback devolvió el trigger habilitado" "O" "$($PG -d t3 -c "select tgenabled from pg_trigger where tgrelid='private.contrato_pdf_jobs'::regclass and tgname='contrato_pdf_jobs_transiciones_validas';")"
afirma "el rollback devolvió los dos CHECK" "2" "$($PG -d t3 -c "select count(*) from pg_constraint where conname in ('contrato_pdf_jobs_template_valido','contrato_pdfs_version_ruta_valida');")"
afirma "el rollback dejó el CHECK viejo (sin v8)" "no" "$($PG -d t3 -c "select case when pg_get_constraintdef(oid) like '%v8%' then 'si' else 'no' end from pg_constraint where conname='contrato_pdf_jobs_template_valido';")"
afirma "el rollback dejó las funciones en v7" "2" "$($PG -d t3 -c "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and strpos(p.prosrc,'contrato-aep-17-v7')>0;")"
afirma "el rollback dejó el default en v7" "'contrato-aep-17-v7'::text" "$($PG -d t3 -c "select column_default from information_schema.columns where table_schema='private' and table_name='contrato_pdf_jobs' and column_name='template_version';")"

echo "════ CASO 4 · MUTANTE del conjunto: una TERCERA función de private estampa la v7 ════"
copia t4
$PG -d t4 -c "create function private.tercera_intrusa() returns text language sql as \$\$ select 'contrato-aep-17-v7'::text \$\$;" >/dev/null
SALIDA=$($PG -d t4 -f "$MIG" 2>&1)
echo "$SALIDA" | grep -q "las funciones que estampan la v7 son" && R=aborta || R="NO abortó: $(echo "$SALIDA" | tail -2)"
afirma "aborta al encontrar una función no declarada" "aborta" "$R"

echo "════ CASO 5 · MUTANTE de la guarda: el literal aparece FUERA de private ════"
copia t5
$PG -d t5 -c "create function public.intrusa_del_portal() returns text language sql as \$\$ select 'contrato-aep-17-v7'::text \$\$;" >/dev/null
SALIDA=$($PG -d t5 -f "$MIG" 2>&1)
echo "$SALIDA" | grep -q "el literal v7 vive fuera de private" && R=aborta || R="NO abortó: $(echo "$SALIDA" | tail -2)"
afirma "aborta y nombra la intrusa de public" "aborta" "$R"
echo "$SALIDA" | grep -q "public.intrusa_del_portal" && R=nombra || R="no la nombra"
afirma "el mensaje dice cuál es" "nombra" "$R"

echo "════ CASO 6 · MUTANTE del contador: dos ocurrencias en una función esperada ════"
copia t6
$PG -d t6 -c "create or replace function private.crear_job_contrato_pdf_base(p_contrato_id uuid, p_actor_id uuid) returns jsonb language plpgsql security definer set search_path='' as \$function\$ begin return jsonb_build_object('a','contrato-aep-17-v7','b','contrato-aep-17-v7'); end; \$function\$;" >/dev/null
SALIDA=$($PG -d t6 -f "$MIG" 2>&1)
echo "$SALIDA" | grep -q "ocurrencias del literal v7" && R=aborta || R="NO abortó: $(echo "$SALIDA" | tail -2)"
afirma "aborta si el literal aparece dos veces" "aborta" "$R"

echo "════ CASO 7 · re-aplicar la migración ya aplicada ════"
copia t7
$PG -d t7 -f "$MIG" >/dev/null 2>&1
SALIDA=$($PG -d t7 -f "$MIG" 2>&1)
echo "$SALIDA" | grep -q "las funciones que estampan la v7 son" && R=aborta || R="otra cosa: $(echo "$SALIDA" | tail -2)"
afirma "la segunda pasada aborta en seco (no es idempotente, y lo dice)" "aborta" "$R"
afirma "y no deja el trigger apagado" "O" "$($PG -d t7 -c "select tgenabled from pg_trigger where tgrelid='private.contrato_pdf_jobs'::regclass and tgname='contrato_pdf_jobs_transiciones_validas';")"

echo "════ CASO 8 · lease VENCIDO (el mensaje no puede prometer una espera que no arregla) ════"
copia t8
$PG -d t8 -c "insert into private.contrato_pdf_jobs (id,contrato_id,revision,estado,storage_path,nombre_archivo,template_version,snapshot,solicitado_por,lease_token,lease_expira_en) values ('66666666-6666-4666-8666-666666666666','aaaaaaa6-6666-4666-8666-666666666666',1,'procesando','aaaaaaa6-6666-4666-8666-666666666666/v2/66666666-6666-4666-8666-666666666666/contrato.pdf','Contrato-caso-8.pdf','contrato-aep-17-v7','{\"caso\":8}'::jsonb,'99999999-9999-4999-8999-999999999999','77777777-7777-4777-8777-777777777777', now() - interval '10 minutes');" >/dev/null
SALIDA=$($PG -d t8 -f "$MIG" 2>&1)
echo "$SALIDA" | grep -q "1 con lease ya vencido" && R=distingue || R="NO distingue: $(echo "$SALIDA" | grep PREFLIGHT | head -1)"
afirma "el preflight cuenta aparte las de lease vencido" "distingue" "$R"
echo "$SALIDA" | grep -q "NO se mueven solas" && R=avisa || R="no avisa"
afirma "y dice que esperar no las arregla" "avisa" "$R"

echo "════ CASO 9 · CONCURRENCIA: otra sesión reclama un job v7 durante la migración ════"
copia t9
# Sesión rival: abre transacción, mete un job v7 'procesando' y NO cierra.
( $PG -d t9 -c "begin; insert into private.contrato_pdf_jobs (id,contrato_id,revision,estado,storage_path,nombre_archivo,template_version,snapshot,solicitado_por,lease_token,lease_expira_en) values ('aaaa0000-0000-4000-8000-000000000009','bbbb0000-0000-4000-8000-000000000009',1,'procesando','bbbb0000-0000-4000-8000-000000000009/v2/aaaa0000-0000-4000-8000-000000000009/contrato.pdf','Contrato-caso-9.pdf','contrato-aep-17-v7','{}'::jsonb,'99999999-9999-4999-8999-999999999999','cccc0000-0000-4000-8000-000000000009', now() + interval '5 minutes'); select pg_sleep(25); commit;" >/dev/null 2>&1 ) &
RIVAL=$!
sleep 3
SALIDA=$($PG -d t9 -f "$MIG" 2>&1)
wait $RIVAL 2>/dev/null
echo "$SALIDA" | grep -qE "lock timeout|tiempo de espera|canceling statement|reservas v7 en vuelo" && R=protegida || R="pasó igual: $(echo "$SALIDA" | tail -2)"
afirma "la migración no se cuela entre el conteo y el candado" "protegida" "$R"
afirma "y el trigger sigue habilitado tras el corte" "O" "$($PG -d t9 -c "select tgenabled from pg_trigger where tgrelid='private.contrato_pdf_jobs'::regclass and tgname='contrato_pdf_jobs_transiciones_validas';")"
afirma "el job de la sesión rival sigue en v7 y en vuelo" "contrato-aep-17-v7|procesando" "$($PG -d t9 -c "select template_version||'|'||estado from private.contrato_pdf_jobs where id='aaaa0000-0000-4000-8000-000000000009';")"

echo "════ CASO 10 · REVERSA v8 → v7 ════"
copia t10
$PG -d t10 -f "$MIG" >/dev/null 2>&1
ANTES_SELLADOS=$($PG -d t10 -c "select md5(string_agg(t::text,'|' order by t::text)) from private.contrato_pdfs t;")
SALIDA=$($PG -d t10 -f "$REV" 2>&1)
echo "$SALIDA" | grep -q "CONTRATO_PDF_V8_ROLLBACK_OK" && R=ok || R="fallo: $(echo "$SALIDA" | tail -2)"
afirma "la reversa termina en CONTRATO_PDF_V8_ROLLBACK_OK" "ok" "$R"
afirma "el default vuelve a la v7" "'contrato-aep-17-v7'::text" "$($PG -d t10 -c "select column_default from information_schema.columns where table_schema='private' and table_name='contrato_pdf_jobs' and column_name='template_version';")"
afirma "las funciones vuelven a estampar la v7" "2" "$($PG -d t10 -c "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and strpos(p.prosrc,'contrato-aep-17-v7')>0;")"
afirma "ninguna función estampa ya la v8" "0" "$($PG -d t10 -c "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and strpos(p.prosrc,'contrato-aep-17-v8')>0;")"
afirma "las reservas sin bytes vuelven a v7" "contrato-aep-17-v7" "$($PG -d t10 -c "select template_version from private.contrato_pdf_jobs where id='11111111-1111-4111-8111-111111111111';")"
afirma "el ledger de sellados sigue idéntico tras la reversa" "$ANTES_SELLADOS" "$($PG -d t10 -c "select md5(string_agg(t::text,'|' order by t::text)) from private.contrato_pdfs t;")"
afirma "los CHECK siguen admitiendo la v8 (aditivo, no se estrecha)" "si" "$($PG -d t10 -c "select case when pg_get_constraintdef(oid) like '%v8%' then 'si' else 'no' end from pg_constraint where conname='contrato_pdf_jobs_template_valido';")"
afirma "un PDF sellado v8 seguiría siendo insertable/legible tras la reversa" "si" "$($PG -d t10 -c "select case when pg_get_constraintdef(oid) like '%v8%' then 'si' else 'no' end from pg_constraint where conname='contrato_pdfs_version_ruta_valida';")"
afirma "el trigger quedó habilitado tras la reversa" "O" "$($PG -d t10 -c "select tgenabled from pg_trigger where tgrelid='private.contrato_pdf_jobs'::regclass and tgname='contrato_pdf_jobs_transiciones_validas';")"

echo
echo "════════ RESULTADO: $OK verdes · $MAL rojos ════════"
[ "$MAL" -eq 0 ]
