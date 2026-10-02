#!/usr/bin/env bash
# Ciclo completo de 20261002005004_crm_asignar_cuenta_pago en el BANCO Docker propio.
# Nunca contra producción: todo va por `docker exec` contra el contenedor del banco. No edita ningún
# archivo del repositorio: los mutantes y las copias alteradas viven en un directorio temporal.
#
#   BANCO_CONTENEDOR=avancecorp-cuentas-asignar-20261001 bash supabase/scripts/cuentas-pago-asignar/ciclo.sh
#
# ASIGNAR_SALIDA=<carpeta> conserva ahí las fotos (catálogo, trinquetes), las listas de mutantes y la
# salida de cada corrida. El banco se monta antes con supabase/scripts/potencial-lead/banco/montar-banco.sh
# (esquema de producción, sin datos). Cada paso se compara con lo que se espera (✓ / ✗); «△ MEDIDO»
# son comportamientos que no forman parte del contrato y se anotan sin contar. Al final hay una tabla
# por tramo y el ciclo sale con 1 si hubo algún ✗. La migración, la reversa, reabrir-puerta y el
# registrador van en UN mensaje y como postgres, igual que en producción (`supabase db query --file`);
# la prueba va sentencia a sentencia y como supabase_admin (ver su cabecera).
#
# Tramos:
#    0 · punto de partida: restos fuera, las dos migraciones fuera, derivados y registrador al día
#    1 · siembras (común y extra, dos veces cada una) → fotos SIN la migración: catálogo, datos y trinquetes
#    2 · lo que debe NEGARSE sin la migración: reversa, reabrir-puerta y registrar
#    3 · migración (veredicto ASIGNAR_CUENTA_PAGO_OK como FILA) → otra vez (se niega, sin fila) → prueba →
#        nada escrito → trinquetes CON la migración: idénticos
#    4 · registrar → reversa SIN asignaciones: RETIRADA, catálogo de antes y registro borrado → registrar se
#        niega → reaplicar; de dónde sale el veredicto (una aplicación que falla da NULL; repetida, OK)
#    5 · la reversa en REPEATABLE READ y SERIALIZABLE: se niega
#    6 · una asignación CONFIRMADA → reversa: PUERTA_CERRADA, nada borrado (ni el registro) → migración (ya
#        aplicada, veredicto NULL) → reabrir-puerta frente a mundos alterados (se niega) → reabrir (ACL
#        exacta) → otra asignación → limpieza → RETIRADA
#    7 · la reversa frente a mundos alterados (falta una pieza, permisos de más, candados apagados…); piezas
#        cambiadas DE VERDAD con cero asignaciones: cierra en vez de borrar y reabrir se niega hasta reponerlas
#    8 · concurrencia con dos sesiones reales (prueba-concurrencia.sh entera)
#    9 · con la otra migración (20261001233019): las dos carreras REALES entre una asignación y su carga;
#        asignar → otra → prueba con T10; la carga suelta (vincular-rezago.sql) frente a «Asignar»; y al
#        revés, otra → asignar → prueba; trinquetes idénticos; reversa de la otra → prueba
#   10 · mutantes de la MIGRACIÓN: su texto real alterado; debe pararlos el pre/postflight
#   11 · los mismos mutantes inyectados en la prueba: dice QUÉ TRAMO caza cada uno
#   12 · mutantes de CONCURRENCIA: el núcleo y la reversa alterados de verdad; los caza prueba-concurrencia.sh
#   13 · mutantes del PREFLIGHT: el mundo alterado; la migración debe negarse
#   14 · mutantes de los DERIVADOS: reabrir-puerta con una cláusula menos de «piezas enteras» (cada una
#        debe reabrir exactamente en sus mundos) y la reversa alterada frente a sus mundos
#   15 · estado final: banco limpio, migración aplicada y registrada (dos veces) → prueba
#
# CÓMO SE DEJA EL BANCO LIMPIO (limpiar_restos, más abajo). Una asignación confirmada deja una
# constancia que NO se borra ni se vacía (sus disparadores lo impiden, con razón) y un vínculo. En el
# banco, y SOLO en el banco, se quitan como supabase_admin con `session_replication_role = replica`
# (apaga los disparadores de usuario): constancias, vínculos, sellos y retiros de los contratos ASIGNAR-NN,
# las cuotas a «pendiente», las cuentas de prueba a «vigentes» y el contrato de prueba a «activo». La
# bitácora (public.audit_log) es de solo añadir y no se toca. Después, con cero constancias y las
# piezas enteras, reversa.sql devuelve RETIRADA, el catálogo es el de antes de la migración y la versión
# deja de estar registrada.
set -uo pipefail
C="${BANCO_CONTENEDOR:-avancecorp-cuentas-asignar-20261001}"
D="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # …/supabase
P="$D/scripts/cuentas-pago-asignar"
M="$D/migrations/20261002005004_crm_asignar_cuenta_pago.sql"
R="$P/reversa.sql"
RE="$P/reabrir-puerta.sql"
REGISTRAR="$P/registrar.sql"
GENERAR="$P/generar-derivados.py"
PRUEBA="$P/test-asignar-cuenta-pago.sql"
CONC="$P/prueba-concurrencia.sh"
EXTRA="$P/siembra-extra.sql"
SIEMBRA="$D/scripts/cuentas-pago-rezago/siembra.sql"
OTRA="$D/migrations/20261001233019_crm_cuentas_pago_motivo_y_rezago.sql"
OTRA_REVERSA="$D/scripts/cuentas-pago-rezago/reversa.sql"
TRINQUETES="$D/scripts/potencial-lead/banco/trinquetes.sql"
VERSION='20261002005004'
NOMBRE='crm_asignar_cuenta_pago'
PUERTA='crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'
NUCLEO='private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'
CANDADO='private.trg_contrato_cuenta_pago_asignaciones_inmutable()'
TABLA='crm.contrato_cuenta_pago_asignaciones'
ADMIN='c9e00000-0000-4000-8000-000000000001'
SUPER='a5190000-0000-4000-8000-000000000031'
MOTIVO='Operaciones confirmó con el cliente en cuál cobra'
RETIRADA='RETIRADA: no queda la puerta, el núcleo ni la tabla de constancias'
CERRADA='PUERTA_CERRADA: nadie puede asignar; no se borró nada (las constancias y los vínculos siguen)'
NO_ENTERAS='ERROR:  REABRIR ASIGNAR: las piezas no están enteras como las dejó la migración 20261002005004'
ACL_RECIEN='candado:postgres nucleo:authenticated,postgres puerta:authenticated,postgres'
ACL_CERRADA='candado:postgres nucleo:postgres puerta:postgres'
k() { printf 'a519d000-0000-4000-8000-0000000000%02d' "$1"; }      # contrato ASIGNAR-NN
x() { printf 'a519c000-0000-4000-8000-0000000000%02d' "$1"; }      # cuenta de la siembra extra
s() { printf 'a519a000-0000-4000-8000-0000000080%02d' "$1"; }      # solicitud del ciclo
FALLOS=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SALIDA="${ASIGNAR_SALIDA:-$T}"; mkdir -p "$SALIDA"

# ── Contabilidad por tramo ───────────────────────────────────────────────────────────────────
TRAMOS=(); T_OK=(); T_KO=(); T_ASERT=(); IT=-1; MEDIDOS=0
tramo() { IT=$((IT + 1)); TRAMOS[$IT]="$1"; T_OK[$IT]=0; T_KO[$IT]=0; T_ASERT[$IT]=0; echo "── $1"; }
anota() { if [ "$1" = ok ]; then T_OK[$IT]=$((${T_OK[$IT]} + 1)); else T_KO[$IT]=$((${T_KO[$IT]} + 1)); FALLOS=$((FALLOS + 1)); fi; }
# paso <etiqueta> <lo que se espera (grep -E)> <resultado>
paso() {
  local marca='✓'
  if grep -Eq -- "$2" <<<"$3"; then anota ok; else marca='✗'; anota ko; fi
  printf '%s %-66s %s\n' "$marca" "$1" "$(cut -c1-300 <<<"$3" | head -3)"
}
# igual <etiqueta> <esperado> <obtenido>
igual() {
  if [ "$2" = "$3" ]; then anota ok; printf '✓ %-66s %s\n' "$1" "igual"
  else anota ko; printf '✗ %-66s\n    esperaba: %s\n    vino:     %s\n' "$1" "$(cut -c1-400 <<<"$2")" "$(cut -c1-400 <<<"$3")"; fi
}
# Algo que se mide y se cuenta en el informe, pero no es parte del contrato: no suma ni resta.
medido() { MEDIDOS=$((MEDIDOS + 1)); printf '△ MEDIDO %-57s %s\n' "$1" "$2"; }

# ── Ayudantes ────────────────────────────────────────────────────────────────────────────────
# Una consulta de un solo valor (los dos canales juntos: no hay avisos que se crucen).
q() { docker exec -i -e PGPASSWORD=postgres "$C" psql -U "${2:-postgres}" -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "$1" 2>&1 </dev/null; }
# Un mensaje con sus dos canales POR SEPARADO: las filas en <base>.out, los avisos y errores en <base>.err.
# `docker exec` no conserva el orden entre los dos canales, así que «la última línea» de la mezcla no es de fiar.
lanzar() { # $1 base · $2 usuario · $3 sql · $4 aislamiento por defecto de la conexión (opcional)
  if [ -n "${4:-}" ]; then
    docker exec -i -e PGPASSWORD=postgres -e "PGOPTIONS=-c default_transaction_isolation=${4// /\\ }" "$C" \
      psql -U "$2" -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "$3" > "$1.out" 2> "$1.err" </dev/null
  else
    docker exec -i -e PGPASSWORD=postgres "$C" psql -U "$2" -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "$3" > "$1.out" 2> "$1.err" </dev/null
  fi
}
# Lo que dejó un mensaje: su primer ERROR; si no, su última fila no vacía; y si no dio filas, su último aviso.
canales() {
  if grep -q 'ERROR:' "$1.err" 2>/dev/null; then grep -m1 -o 'ERROR:.*' "$1.err" | cut -c1-300
  elif grep -q . "$1.out" 2>/dev/null; then grep . "$1.out" | tail -1
  else grep . "$1.err" 2>/dev/null | tail -1; fi
}
resultado() { local f r; f=$(mktemp "$T/r.XXXXXX"); lanzar "$f" "$1" "$2" "${3:-}"; r=$(canales "$f"); rm -f "$f" "$f.out" "$f.err"; printf '%s\n' "$r"; }
ultima() { resultado "${2:-postgres}" "$1"; }
# Un archivo en UN mensaje y como postgres (los veredictos viajan como fila). Con $2 = un nivel de
# aislamiento, la conexión nace con ese nivel por defecto (un SET delante, en el mismo mensaje, no sirve:
# el «begin» del archivo hereda la transacción del mensaje).
archivo() { resultado postgres "$(cat "$1")" "${2:-}"; }
# El primer ERROR de un archivo o, si no lo hay, su aviso que empieza por $2 (da igual qué más diga).
aviso() {
  local f r; f=$(mktemp "$T/r.XXXXXX"); lanzar "$f" postgres "$(cat "$1")"
  if grep -q 'ERROR:' "$f.err"; then r=$(grep -m1 -o 'ERROR:.*' "$f.err" | cut -c1-300); else r=$(grep -m1 -o "NOTICE:  $2.*" "$f.err"); fi
  rm -f "$f" "$f.out" "$f.err"; printf '%s\n' "$r"
}
# Solo las FILAS que devuelve un archivo (sin avisos ni errores): para ver que el veredicto es una fila.
filas() { docker exec -i -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "$(cat "$1")" 2>/dev/null </dev/null | tr '\n' ' ' | sed 's/ $//'; }
# Un archivo SENTENCIA A SENTENCIA y sin parar en los errores (como lo lanzaría alguien con psql -f): deja
# las filas en $T/s.out y los avisos y errores en $T/s.err. $2 = aislamiento por defecto de la conexión.
sentencias() {
  if [ -n "${2:-}" ]; then
    docker exec -i -e PGPASSWORD=postgres -e "PGOPTIONS=-c default_transaction_isolation=${2// /\\ }" "$C" \
      psql -U postgres -h 127.0.0.1 -d postgres -qAt < "$1" > "$T/s.out" 2> "$T/s.err"
  else
    docker exec -i -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -qAt < "$1" > "$T/s.out" 2> "$T/s.err"
  fi
}
# «<n> fila(s): …» de lo que dejó `sentencias` en la salida estándar (NULL = fila vacía).
renglones() { awk '{ l = l (NR > 1 ? "/" : "") ($0 == "" ? "NULL" : $0) } END { print NR " fila" (NR == 1 ? "" : "s") ": " l }' "$1"; }
aplicada() {
  q "select case (to_regclass('$TABLA') is not null)::int + (to_regprocedure('$PUERTA') is not null)::int
                 + (to_regprocedure('$NUCLEO') is not null)::int + (to_regprocedure('$CANDADO') is not null)::int
            when 4 then 'sí' when 0 then 'no' else 'a medias' end;"
}
otra_aplicada() { q "select case when to_regprocedure('private.cuenta_pago_diagnostico(uuid[])') is not null then 'sí' else 'no' end;"; }
# Por catálogo, nunca llamando: sin EXECUTE bajo SET ROLE este Postgres se cae.
abierta() { q "select case when has_function_privilege('authenticated', '$PUERTA', 'EXECUTE') and has_function_privilege('authenticated', '$NUCLEO', 'EXECUTE') then 'abierta' else 'cerrada' end;"; }
permisos() {
  q "select string_agg(f.n || ':' || coalesce((select string_agg(case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end, ','
                                                               order by case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end)
                                                from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                                                where p.oid = to_regprocedure(f.firma) and a.privilege_type = 'EXECUTE'), '(nadie)'), ' ' order by f.n)
     from (values ('puerta', '$PUERTA'), ('nucleo', '$NUCLEO'), ('candado', '$CANDADO')) f(n, firma);"
}
constancias() { q "select count(*) from $TABLA;"; }
constancia_md5() { q "set timezone = 'UTC'; select md5(string_agg(to_jsonb(a)::text, ',' order by a.id)) from $TABLA a;" | grep -v '^SET$'; }
registro() { q "select count(*) from supabase_migrations.schema_migrations where version = '$VERSION';"; }
huellas_vivas() { q "select md5(p.prosrc) from unnest(array['$CANDADO', '$NUCLEO', '$PUERTA']) with ordinality f(firma, n) join pg_proc p on p.oid = to_regprocedure(f.firma) order by f.n;" | tr '\n' ' ' | sed 's/ $//'; }
# Las tres huellas que exige el postflight de la migración, leídas de su texto (candado, núcleo, puerta).
huellas_del_postflight() { grep -E "^ +\('(private|crm)\.[a-z_]+\((uuid,uuid,uuid,text)?\)', (null|'authenticated'), (true|false), '[0-9a-f]{32}'\)" "$M" | grep -o "[0-9a-f]\{32\}" | tr '\n' ' ' | sed 's/ $//'; }

# La foto del CATÁLOGO de crm, private y public, un renglón por aspecto (para saber cuál cambió).
foto_catalogo() {
  q "set search_path = '';
     select 'funciones ' || count(*) || ' ' || md5(coalesce(string_agg(md5(pg_get_functiondef(p.oid)) || coalesce(p.proacl::text, '-') || p.proowner::regrole::text || coalesce(obj_description(p.oid, 'pg_proc'), '-'), ',' order by p.oid::regprocedure::text), ''))
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('crm', 'private', 'public') and p.prokind in ('f', 'p');
     select 'relaciones ' || count(*) || ' ' || md5(coalesce(string_agg(c.oid::regclass::text || c.relkind::text || c.relpersistence::text || c.relrowsecurity::text || c.relforcerowsecurity::text || coalesce(c.relacl::text, '-') || c.relowner::regrole::text || coalesce(obj_description(c.oid, 'pg_class'), '-') || coalesce(c.reloptions::text, '-'), ',' order by c.oid::regclass::text), ''))
       from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname in ('crm', 'private', 'public');
     select 'columnas ' || count(*) || ' ' || md5(coalesce(string_agg(a.attrelid::regclass::text || '.' || a.attname || ':' || format_type(a.atttypid, a.atttypmod) || a.attnotnull::text || coalesce(pg_get_expr(d.adbin, d.adrelid), '-') || coalesce(a.attacl::text, '-') || coalesce(col_description(a.attrelid, a.attnum), '-'), ',' order by a.attrelid::regclass::text, a.attnum), ''))
       from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
       where n.nspname in ('crm', 'private', 'public') and a.attnum > 0 and not a.attisdropped;
     select 'disparadores ' || count(*) || ' ' || md5(coalesce(string_agg(pg_get_triggerdef(t.oid) || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname), ''))
       from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname in ('crm', 'private', 'public') and not t.tgisinternal;
     select 'restricciones ' || count(*) || ' ' || md5(coalesce(string_agg(coalesce(k.conrelid::regclass::text, '-') || k.conname || pg_get_constraintdef(k.oid), ',' order by coalesce(k.conrelid::regclass::text, '-'), k.conname), ''))
       from pg_constraint k join pg_namespace n on n.oid = k.connamespace where n.nspname in ('crm', 'private', 'public');
     select 'politicas ' || count(*) || ' ' || md5(coalesce(string_agg(p.polrelid::regclass::text || p.polname || p.polcmd::text || p.polpermissive::text || p.polroles::text || coalesce(pg_get_expr(p.polqual, p.polrelid), '-') || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '-'), ',' order by p.polrelid::regclass::text, p.polname), ''))
       from pg_policy p;
     select 'indices ' || count(*) || ' ' || md5(coalesce(string_agg(pg_get_indexdef(i.indexrelid) || i.indisvalid::text, ',' order by i.indexrelid::regclass::text), ''))
       from pg_index i join pg_class c on c.oid = i.indrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname in ('crm', 'private', 'public');
     select 'tipos ' || count(*) || ' ' || md5(coalesce(string_agg(n.nspname || '.' || t.typname, ',' order by n.nspname, t.typname), ''))
       from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname in ('crm', 'private', 'public');
     select 'comentarios ' || count(*) from pg_description;
     select 'dependencias ' || count(*) from pg_depend;
     select 'permisos_por_defecto ' || count(*) || ' ' || md5(coalesce(string_agg(d.defaclrole::regrole::text || d.defaclnamespace::text || d.defaclobjtype::text || d.defaclacl::text, ',' order by d.oid), '')) from pg_default_acl d;
     select 'esquemas ' || md5(string_agg(n.nspname || coalesce(n.nspacl::text, '-') || n.nspowner::regrole::text, ',' order by n.nspname)) from pg_namespace n where n.nspname in ('crm', 'private', 'public');" | grep -v '^SET$'
}
# La foto de las PIEZAS de la migración en un md5: definición entera, ACL, dueño y comentario de las tres
# funciones; RLS, ACL, dueño, comentario, columnas, disparadores, restricciones e índices de la tabla.
foto_piezas() {
  local v
  v=$(q "set search_path = '';
     select md5(
       (select string_agg(md5(pg_get_functiondef(p.oid)) || coalesce(p.proacl::text, '-') || p.proowner::regrole::text || coalesce(obj_description(p.oid, 'pg_proc'), '-'), ',' order by p.oid::regprocedure::text)
          from pg_proc p where p.oid in (to_regprocedure('$PUERTA'), to_regprocedure('$NUCLEO'), to_regprocedure('$CANDADO')))
       || (select c.relrowsecurity::text || c.relforcerowsecurity::text || coalesce(c.relacl::text, '-') || c.relowner::regrole::text || coalesce(obj_description(c.oid, 'pg_class'), '-') from pg_class c where c.oid = to_regclass('$TABLA'))
       || (select string_agg(a.attname || format_type(a.atttypid, a.atttypmod) || a.attnotnull::text || coalesce(a.attacl::text, '-') || coalesce(col_description(a.attrelid, a.attnum), '-'), ',' order by a.attnum)
             from pg_attribute a where a.attrelid = to_regclass('$TABLA') and a.attnum > 0 and not a.attisdropped)
       || (select string_agg(pg_get_triggerdef(t.oid) || t.tgenabled::text, ',' order by t.tgname) from pg_trigger t where t.tgrelid = to_regclass('$TABLA') and not t.tgisinternal)
       || (select string_agg(k.conname || pg_get_constraintdef(k.oid), ',' order by k.conname) from pg_constraint k where k.conrelid = to_regclass('$TABLA'))
       || (select string_agg(pg_get_indexdef(i.indexrelid), ',' order by i.indexrelid::regclass::text) from pg_index i where i.indrelid = to_regclass('$TABLA')));" | grep -v '^SET$')
  echo "${v:-(sin piezas)}"
}
# La foto de los DATOS que la asignación lee o podría tocar (todas las columnas de todas las filas). La
# bitácora es de solo añadir: va aparte (cuántas filas tiene).
foto_datos() {
  q "set timezone = 'UTC';
     select 'vinculos=' || (select count(*) || ':' || md5(coalesce(string_agg(md5(to_jsonb(v)::text), ',' order by v.id), '')) from crm.contrato_cuentas_pago v)
         || ' cuentas=' || (select count(*) || ':' || md5(coalesce(string_agg(md5(to_jsonb(v)::text), ',' order by v.id), '')) from crm.cuentas_bancarias v)
         || ' contratos=' || (select count(*) || ':' || md5(coalesce(string_agg(md5(to_jsonb(v)::text), ',' order by v.id), '')) from public.contratos v)
         || ' cuotas=' || (select count(*) || ':' || md5(coalesce(string_agg(md5(to_jsonb(v)::text), ',' order by v.id), '')) from public.cronograma_pagos v)
         || ' perfiles=' || (select count(*) || ':' || md5(coalesce(string_agg(md5(to_jsonb(v)::text), ',' order by v.id), '')) from public.perfiles v)
         || ' equipo=' || (select count(*) || ':' || md5(coalesce(string_agg(v.perfil_id::text || v.rol_crm || v.activo::text, ',' order by v.perfil_id), '')) from crm.equipo v)
         || ' sellos=' || (select count(*) from crm.cuotas_cuenta_pagada)
         || ' cambios=' || (select count(*) from crm.contrato_cuenta_pago_cambios)
         || ' retiros=' || (select count(*) from crm.cuentas_bancarias_retiros)
         || ' rastro_vigente=' || (select count(*) from private.backfill_cuentas_p0xx b where b.revertida_en is null);" | grep -v '^SET$'
}
bitacora() { q "select count(*) from public.audit_log;"; }
# La foto de los trinquetes (private.assert_*() y contadores crudos), como en potencial-lead/banco/ciclo-fase3a.sh.
# $1 = «enteros»: la misma foto con el mensaje ENTERO de cada trinquete (trinquetes.sql lo corta a 160 caracteres).
# $2 = sentencias que se inyectan al empezar su transacción (para fotografiar bajo un mutante; se deshacen).
# Los avisos (un renglón por trinquete) y las filas (el censo) salen por canales distintos: primero unos y
# después las otras, siempre en ese orden.
trinquetes() {
  local f="$TRINQUETES" g
  if [ -n "${1:-}${2:-}" ]; then
    f="$T/trinquetes-variante.sql"
    python3 - "$TRINQUETES" "$f" "${1:-}" "${2:-}" <<'PY'
import io, sys
origen, destino, enteros, inyeccion = sys.argv[1:]
t = io.open(origen, encoding='utf-8').read()
if enteros:
    a = "left(replace(sqlerrm, E'\\n', ' '), 160)"
    assert t.count(a) == 1, 'trinquetes.sql ya no corta el mensaje como se esperaba'
    t = t.replace(a, "replace(sqlerrm, E'\\n', ' ')")
if inyeccion:
    assert t.count('begin;\n') >= 1
    t = t.replace('begin;\n', 'begin;\n' + inyeccion + '\n', 1)
io.open(destino, 'w', encoding='utf-8').write(t)
PY
  fi
  g=$(mktemp "$T/t.XXXXXX")
  docker exec -i -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -qAt < "$f" > "$g.out" 2> "$g.err"
  sed 's/^.*NOTICE:  //' "$g.err"; cat "$g.out"
  rm -f "$g" "$g.out" "$g.err"
}
sembrar() { local o; o=$(q "$(cat "$1")"); if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-260; else grep -m1 -o 'SIEMBRA .*' <<<"$o"; fi; }

# SOLO BANCO (ver la cabecera). Quita los vínculos que creó cualquier asignación (los señala su
# constancia) y deja el mundo de la siembra extra como se sembró. Quita también lo que pudo dejar una
# prueba de concurrencia cortada a medias: su doble de storage.objects, retiros, rastro de carga y la
# membresía de la administradora que revoca.
limpiar_restos() {
  ultima "set session_replication_role = replica;
     do \$l\$ begin
       if to_regclass('$TABLA') is not null then
         delete from crm.contrato_cuentas_pago l using $TABLA a where l.id = a.vinculo_id;
         delete from $TABLA;
       end if;
       if to_regclass('storage.objects') is not null
          and coalesce(obj_description(to_regclass('storage.objects'), 'pg_class'), '') like 'DOBLE de prueba-concurrencia.sh%' then
         drop table storage.objects;
       end if;
     end \$l\$;
     delete from crm.cuotas_cuenta_pagada where contrato_id::text like 'a519d000-%';
     delete from crm.contrato_cuentas_pago where contrato_id::text like 'a519d000-%';
     delete from private.backfill_cuentas_p0xx where contrato_id::text like 'a519d000-%';
     delete from crm.cuentas_bancarias_retiros where cliente_id::text like 'a5190000-%';
     update public.cronograma_pagos set estado = 'pendiente', fecha_pago_real = null, monto_pagado = null, registrado_por = null
      where id::text like 'a519e000-%' and (estado <> 'pendiente' or fecha_pago_real is not null or monto_pagado is not null or registrado_por is not null);
     update crm.cuentas_bancarias set activa = true, desactivada_por = null, desactivada_en = null
      where id::text like 'a519c000-%' and id <> '$(x 4)' and not activa;
     update public.contratos set estado = 'activo' where id = '$(k 5)' and estado <> 'activo';
     update crm.equipo set activo = true where perfil_id = 'a5190000-0000-4000-8000-000000000034' and not activo;
     set session_replication_role = origin;
     select 'restos limpios';" supabase_admin
}
# SOLO BANCO. Quita las piezas de la migración sin preguntar (para arrancar de cero y tras un mutante
# que las dejó alteradas). Se niega si la constancia tiene filas: antes va limpiar_restos.
retirar_a_la_fuerza() {
  ultima "do \$r\$ begin
       if to_regclass('$TABLA') is not null then
         if exists (select 1 from $TABLA) then raise exception 'la constancia tiene filas: limpia antes'; end if;
       end if;
     end \$r\$;
     drop function if exists $PUERTA;
     drop function if exists $NUCLEO;
     drop table if exists $TABLA;
     drop function if exists $CANDADO;
     select 'piezas fuera';"
}
quitar_registro() { ultima "delete from supabase_migrations.schema_migrations where version = '$VERSION'; select 'registro fuera';"; }

# La prueba (test-asignar-cuenta-pago.sql), entera o con una alteración inyectada ($1 = archivo) en la
# línea «MUTANTE». Deja: VEREDICTO (su última línea, o el primer ERROR), CAIDOS (tramos en FAIL), N
# (comprobaciones) y SALIDA_PRUEBA (todo).
correr_prueba() {
  local f="$PRUEBA"
  if [ -n "${1:-}" ]; then
    f="$T/prueba-alterada.sql"
    python3 - "$PRUEBA" "$1" "$f" <<'PY'
import io, sys
prueba, alteracion, destino = sys.argv[1:]
t = io.open(prueba, encoding='utf-8').read()
marca = [l for l in t.split('\n') if l.startswith('-- «MUTANTE»')]
assert len(marca) == 1, 'la prueba no tiene (una sola vez) la línea «MUTANTE»'
io.open(destino, 'w', encoding='utf-8').write(t.replace(marca[0], io.open(alteracion, encoding='utf-8').read(), 1))
PY
  fi
  SALIDA_PRUEBA=$(docker exec -i -e PGPASSWORD=postgres "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt < "$f" 2>&1)
  VEREDICTO=$(grep -E -o '^ASIGNAR (OK|FALLO) .*' <<<"$SALIDA_PRUEBA" | head -1 | cut -c1-200)
  [ -n "$VEREDICTO" ] || VEREDICTO=$(grep -m1 -o 'ERROR:.*' <<<"$SALIDA_PRUEBA" | cut -c1-300)
  CAIDOS=$(grep -E -o '^T[0-9C]+ FAIL' <<<"$SALIDA_PRUEBA" | awk '{print $1}' | tr '\n' ' ' | sed 's/ $//')
  N=$(sed -n 's/^ASIGNAR OK · [0-9]* tramos · \([0-9]*\) comprobaciones.*/\1/p' <<<"$SALIDA_PRUEBA" | head -1)
}
# Corre la prueba, exige el veredicto OK y suma sus comprobaciones al tramo. $2 = lo que debe decir T10.
prueba_paso() {
  correr_prueba
  NP=$((${NP:-0} + 1)); [ "$SALIDA" = "$T" ] || printf '%s\n' "$SALIDA_PRUEBA" > "$SALIDA/prueba-corrida-$NP.txt"
  paso "$1" '^ASIGNAR OK · 10 tramos' "$VEREDICTO"
  T_ASERT[$IT]=$((${T_ASERT[$IT]} + ${N:-0}))
  [ -n "${2:-}" ] && paso "    T10 en esta corrida" "$2" "$(grep -E '^T10 ' <<<"$SALIDA_PRUEBA" | cut -c1-200)"
  grep -E '^T[0-9C]+ FAIL' <<<"$SALIDA_PRUEBA" | cut -c1-300 | sed 's/^/    /'
}
# Una asignación CONFIRMADA, como llamada de la API (authenticator, claims en las dos formas, SET ROLE).
asignar_confirmada() { # $1 uid · $2 solicitud · $3 contrato · $4 cuenta · $5 = «ms» para añadir « ESPERA_MS <n>»
  if [ "$(abierta)" != "abierta" ]; then echo "NO SE LLAMA: authenticated no tiene EXECUTE (llamar tumbaría este Postgres)"; return; fi
  docker exec -i -e PGPASSWORD=postgres "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt 2>&1 <<SQL | grep -o 'RESULTADO .*' | sed 's/^RESULTADO //' | tail -1
do \$m\$
declare v jsonb; r text; t0 constant timestamptz := clock_timestamp();
begin
  perform set_config('lock_timeout', '8s', true), set_config('statement_timeout', '8s', true),
          set_config('request.jwt.claim.sub', '$1', true), set_config('request.jwt.claim.role', 'authenticated', true),
          set_config('request.jwt.claims', json_build_object('sub', '$1', 'role', 'authenticated')::text, true);
  execute 'set local session authorization authenticator';
  execute 'set local role authenticated';
  begin
    v := crm.asignar_cuenta_pago_contrato('$2', '$3', '$4', '$MOTIVO');
    r := 'OK:' || v::text;
  exception when others then
    r := 'ERR:' || sqlstate || ':' || sqlerrm;
  end;
  raise notice 'RESULTADO %', r || case when '${5:-}' = 'ms' then ' ESPERA_MS ' || (extract(epoch from clock_timestamp() - t0) * 1000)::integer else '' end;
end \$m\$;
SQL
}
vinculo() { q "select coalesce((select cuenta_bancaria_id || '|' || coalesce(creado_por::text, '(null)') from crm.contrato_cuentas_pago where contrato_id = '$1'), 'sin vínculo')"; }
# Guarda la definición viva de una función y la repone después (CREATE OR REPLACE conserva ACL, dueño y comentario).
guardar() { q "select pg_get_functiondef('$1'::regprocedure)" > "$T/$2.sql"; }
reponer() { docker exec -i -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -q < "$T/$1.sql" >/dev/null 2>&1; }
# El resultado de un mensaje-mutante: su primer ERROR, o MUTANTE_SIN_ERROR si llegó al final.
mutado() { local o; o=$(q "$(cat "$1")"); if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-200; else grep -m1 -o 'MUTANTE_SIN_ERROR' <<<"$o" || echo '(sin veredicto)'; fi; }
# El resultado de un mensaje-mundo (todo dentro de una transacción que se deshace): su primer ERROR, o sus
# filas unidas con « · » (el veredicto que daría el guion y el estado en que lo dejaría).
mundo() {
  local f r; f=$(mktemp "$T/r.XXXXXX"); lanzar "$f" postgres "$(cat "$1")"
  if grep -q 'ERROR:' "$f.err"; then r=$(grep -m1 -o 'ERROR:.*' "$f.err" | cut -c1-200)
  else r=$(grep . "$f.out" | awk 'NR > 1 { printf " · " } { printf "%s", $0 } END { print "" }'); fi
  rm -f "$f" "$f.out" "$f.err"; printf '%s\n' "$r"
}
# conc_mutante <etiqueta> <casos> <archivo que altera el núcleo vivo | ''> <reversa alterada | ''>
# Altera de verdad el núcleo (o usa una reversa alterada), corre esos casos de prueba-concurrencia.sh y exige
# que FALLEN; después repone todo. Imprime los ✗: es lo que el mutante deja pasar.
conc_mutante() {
  local o
  guardar "$NUCLEO" nucleo-original
  [ -z "$3" ] || q "$(cat "$3")" >/dev/null
  o=$(BANCO_CONTENEDOR="$C" SOLO="$2" REVERSA_SQL="${4:-$R}" bash "$CONC" 2>&1)
  if [ "$(aplicada)" = "sí" ]; then reponer nucleo-original; else limpiar_restos >/dev/null; retirar_a_la_fuerza >/dev/null; archivo "$M" >/dev/null; fi
  [ "$(abierta)" = "abierta" ] || { limpiar_restos >/dev/null; archivo "$RE" >/dev/null; }
  limpiar_restos >/dev/null
  paso "  $1 (casos $2)" '^CONCURRENCIA asignar_cuenta_pago: [0-9]+ OK, [1-9][0-9]* FALLAS$' "$(tail -1 <<<"$o")"
  grep '✗' <<<"$o" | cut -c1-420 | sed 's/^/      /'
}

# ══ 0 · Punto de partida ════════════════════════════════════════════════════════════════════
tramo "0 · punto de partida"
if ! docker ps --format '{{.Names}}' | grep -qx "$C"; then echo "No hay un contenedor $C corriendo: móntalo con potencial-lead/banco/montar-banco.sh" >&2; exit 2; fi
paso "restos de corridas anteriores fuera" '^restos limpios$' "$(limpiar_restos)"
[ "$(aplicada)" = "no" ] || paso "se retiran las piezas de asignar que hubiera (banco)" '^piezas fuera$' "$(retirar_a_la_fuerza)"
[ "$(otra_aplicada)" = "no" ] || paso "se revierte la otra migración con su reversa documentada" '^NOTICE:  REVERSA: [0-9]+ vínculos de la carga borrados' "$(aviso "$OTRA_REVERSA" 'REVERSA:')"
paso "registro de la versión fuera" '^registro fuera$' "$(quitar_registro)"
igual "el banco está en ANTES: ni asignar ni la otra migración" 'no/no' "$(aplicada)/$(otra_aplicada)"
igual "paridad: compuerta, candados ajenos y bloqueo de pagos de producción" \
  '810dce30e37d1da9d913ef48ab6a4aa1 7e946a5af78a827c18ee5b218896f24c e95919db53c44ff1fe6632c346f27a06 5efb8619e4342763ae77df2ee0bb1f61' \
  "$(q "select md5(p.prosrc) from unnest(array['private.admin_banca_vigente(uuid)', 'private.trg_contrato_cuenta_pago_coherente()', 'private.trg_registro_cuenta_pago_no_borrar()', 'private.exigir_cuenta_pago_cronograma()']) with ordinality f(firma, n) join pg_proc p on p.oid = to_regprocedure(f.firma) order by f.n;" | tr '\n' ' ' | sed 's/ $//')"
MD5_MIG="$(python3 -c "import hashlib,io,sys; print(hashlib.md5(io.open(sys.argv[1], encoding='utf-8').read().encode('utf-8')).hexdigest())" "$M")"
paso "reversa.sql y reabrir-puerta.sql están al día con la migración (generar-derivados.py --verificar, solo lee)" "^derivados al día \(migración md5 $MD5_MIG\)" "$(python3 "$GENERAR" --verificar 2>&1 | tail -1)"
paso "registrar.sql está al día (lleva el md5 de la migración de hoy)" "md5 $MD5_MIG" "$(grep -m1 -o 'md5 [0-9a-f]\{32\}' "$REGISTRAR" 2>/dev/null || echo 'no hay registrar.sql: se genera con potencial-lead/banco/generar-registrador.py')"
igual "las huellas que espera la prueba son las del postflight de la migración (candado núcleo puerta)" "$(huellas_del_postflight)" \
  "$(for n in md5_candado md5_nucleo md5_puerta; do sed -n "s/^  ('$n', *'\([0-9a-f]\{32\}\)'),$/\1/p" "$PRUEBA"; done | tr '\n' ' ' | sed 's/ $//')"
igual "migración, reversa y reabrir-puerta sin caracteres invisibles, tabuladores ni retornos de carro" 'ninguno' "$(python3 - "$M" "$R" "$RE" <<'PY'
import io, sys, unicodedata
malos = []
for p in sys.argv[1:]:
    t = io.open(p, encoding='utf-8').read()
    for i, l in enumerate(t.split('\n'), 1):
        for c in l:
            if (ord(c) > 127 and unicodedata.category(c) in ('Zs', 'Zl', 'Zp', 'Cf', 'Cc', 'Co', 'Cn', 'Mn')) or c in '\t\r':
                malos.append('%s:%d U+%04X' % (p.split('/')[-1], i, ord(c)))
print(' '.join(sorted(set(malos))) or 'ninguno')
PY
)"

# ══ 1 · Siembras y fotos SIN la migración ═══════════════════════════════════════════════════
tramo "1 · siembras y fotos sin la migración"
paso "siembra común" '^SIEMBRA cuentas-pago-rezago OK' "$(sembrar "$SIEMBRA")"
paso "siembra común otra vez (idempotente)" '^SIEMBRA cuentas-pago-rezago OK' "$(sembrar "$SIEMBRA")"
paso "siembra extra" '^SIEMBRA EXTRA cuentas-pago-asignar OK: 6 personal, 2 clientes, 7 cuentas \(1 inactivas\), 13 contratos \(11 abiertos, 2 cerrados\), 0 vínculos, 33 cuotas pendientes' "$(sembrar "$EXTRA")"
paso "siembra extra otra vez (idempotente)" '^SIEMBRA EXTRA cuentas-pago-asignar OK' "$(sembrar "$EXTRA")"
DATOS_SEMBRADO="$(foto_datos)"
foto_catalogo > "$SALIDA/catalogo-antes.txt"
paso "foto del catálogo sin la migración (12 renglones)" '^12$' "$(wc -l < "$SALIDA/catalogo-antes.txt" | tr -d ' ')"
trinquetes > "$SALIDA/trinquetes-sin.txt"
trinquetes enteros > "$SALIDA/trinquetes-enteros-sin.txt"
paso "foto de trinquetes sin la migración" '^3[0-9]+ renglones' "$(wc -l < "$SALIDA/trinquetes-sin.txt" | tr -d ' ') renglones"
SIN_RASTRO_ANTES="$(q "select count(*) from private.tablas_sin_rastro();")"

# ── Fábrica de mutantes (sobre el texto REAL de la migración, de la reversa y de reabrir-puerta) ──
mkdir -p "$T/mut" "$T/pre" "$T/vivo" "$T/rea" "$T/rev"
python3 - "$T" "$M" "$R" "$RE" <<'PY' || { echo "✗ la fábrica de mutantes no pudo escribir sus archivos (¿cambió el texto de la migración o de sus derivados?)"; FALLOS=$((FALLOS + 1)); }
import io, os, re, sys
T, M, R, RE = sys.argv[1:]
mig = io.open(M, encoding='utf-8').read()
rev = io.open(R, encoding='utf-8').read()
rea = io.open(RE, encoding='utf-8').read()
NUCLEO = 'private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'
PUERTA = 'crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'
CANDADO = 'private.trg_contrato_cuenta_pago_asignaciones_inmutable()'
TABLA = 'crm.contrato_cuenta_pago_asignaciones'
VERSION = '20261002005004'
POST = 'ERROR:  ASIGNAR POSTFLIGHT'

def escribe(ruta, texto):
    d = os.path.dirname(ruta)
    if not os.path.isdir(d):
        os.makedirs(d)
    io.open(ruta, 'w', encoding='utf-8').write(texto)
def una(texto, fragmento, donde='la migración', veces=1):
    assert texto.count(fragmento) == veces, 'el fragmento no está %d vez/veces en %s: %r' % (veces, donde, fragmento[:80])
    return fragmento
def cuerpo(t):
    """El archivo sin su «begin;» ni nada desde su último «commit;»: para meterlo en otra transacción."""
    return t[t.index('begin;\n') + len('begin;\n'):t.rindex('commit;')]
MC, RC, REC = cuerpo(mig), cuerpo(rev), cuerpo(rea)
def mensaje(antes, m):
    """Reversa + (mundo alterado) + migración, en UNA transacción que nunca se confirma."""
    return 'begin;\n' + RC + '\n' + antes + '\n' + m + "\nselect 'MUTANTE_SIN_ERROR';\nrollback;\n"
def vivo(firma, pares):
    """Altera la función VIVA a partir de su definición: falla si el fragmento no está."""
    s = ''
    for a, b in pares:
        s += ("do $m$ declare d text := pg_catalog.pg_get_functiondef('%s'::regprocedure);\nbegin\n"
              "  if position($a$%s$a$ in d) = 0 then raise exception 'MUTANTE MAL ESCRITO: no encontré el fragmento en %s'; end if;\n"
              "  execute replace(d, $a$%s$a$, $b$%s$b$);\nend $m$;\n") % (firma, a, firma, a, b)
    return s
lista = []
def mutante(n, desc, pares, iny=None, espera_a=POST, espera_b='-', firma=NUCLEO, nota='-'):
    """pares = (fragmento, reemplazo) sobre el texto de la migración. iny = lo que se inyecta en la prueba
    (por defecto, los mismos pares sobre la función viva; '' = no se inyecta). nota = por qué, si espera_b es
    '^TC$', a la prueba secuencial solo se lo delata la huella."""
    m = MC
    for a, b in pares:
        una(mig, a, 'la migración (mutante %s)' % n)
        m = m.replace(a, b, 1)
    escribe('%s/mut/%s.mig.sql' % (T, n), mensaje('', m))
    if iny is None:
        iny = vivo(firma, pares)
    if iny:
        escribe('%s/mut/%s.iny.sql' % (T, n), iny)
    lista.append('|'.join([n, desc, espera_a, espera_b, nota]))

# ── Fragmentos del núcleo, tal como están en la migración
GUARDA = ("  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then\n"
          "    raise exception using errcode = '0A000',\n"
          "      message = 'La asignación no admite este modo de transacción';\n"
          "  end if;\n")
COMPUERTA = "  if not coalesce(private.admin_banca_vigente(v_actor), false) then"
COMPUERTA_ENTERA = (COMPUERTA + "\n    raise exception using errcode = '42501',\n"
                    "      message = 'Solo administración puede asignar la cuenta de pago';\n  end if;\n")
CLIENTE = "  if v_cuenta.cliente_id is distinct from v_ct.cliente_id then"
MONEDA = "  if v_cuenta.moneda is distinct from v_ct.moneda then"
ACTIVA = "  if v_cuenta.activa is not true then"
CON_CUENTA = "  if exists (select 1 from crm.contrato_cuentas_pago l where l.contrato_id = p_contrato_id) then"
CERRADO = "  if v_ct.estado is null or v_ct.estado not in ('activo', 'vencido') then"
MOTIVO = re.search(r"  if pg_catalog\.length\(pg_catalog\.regexp_replace\(v_motivo, .*\n     or pg_catalog\.length\(v_motivo\) > 500 then", mig).group(0)
V_MOTIVO = re.search(r"  v_motivo text := pg_catalog\.regexp_replace\(coalesce\(p_motivo, ''\), .*", mig).group(0)
VINCULO = "    values (p_contrato_id, p_cuenta_id, v_actor)\n    returning id into v_vinculo;"
CONSTANCIA = ("  insert into crm.contrato_cuenta_pago_asignaciones\n"
              "    (solicitud_id, contrato_id, cliente_id, cuenta_bancaria_id, vinculo_id, motivo, asignado_por)\n"
              "  values (p_solicitud_id, p_contrato_id, v_ct.cliente_id, p_cuenta_id, v_vinculo, v_motivo, v_actor);\n")
MISMOS = ("    if v_previa.contrato_id = p_contrato_id and v_previa.cuenta_bancaria_id = p_cuenta_id\n"
          "       and v_previa.motivo = v_motivo then")
FILTRO = ("    if v_esquema is distinct from 'crm' or v_tabla is distinct from 'contrato_cuentas_pago'\n"
          "       or v_restriccion is distinct from 'contrato_cuentas_pago_contrato_id_key' then")
CAPTURA = ("  exception when unique_violation then\n"
           "    get stacked diagnostics v_esquema = schema_name, v_tabla = table_name,\n"
           "                            v_restriccion = constraint_name;\n"
           + FILTRO + "\n      raise;\n    end if;\n"
           "    raise exception using errcode = '22023',\n"
           "      message = pg_catalog.format('El contrato %s ya tiene cuenta de pago; para cambiarla usa «Cambiar cuenta de pago»', v_ct.numero_contrato);\n"
           "  end;")
ULTIMOS = re.search(r"    'ultimos', case when pg_catalog\.length\(v_cuenta\.numero_cuenta\) >= 8\n\s+then pg_catalog\.right\(v_cuenta\.numero_cuenta, 4\) end\);", mig).group(0)
REP_ULTIMOS = re.search(r"\(select case when pg_catalog\.length\(cb\.numero_cuenta\) >= 8\n\s+then pg_catalog\.right\(cb\.numero_cuenta, 4\) end", mig).group(0)
REPETIDA = mig[mig.index("      return pg_catalog.jsonb_build_object(\n        'solicitud_id', p_solicitud_id, 'ya_aplicada', true,"):
               mig.index("where cb.id = v_previa.cuenta_bancaria_id));") + len("where cb.id = v_previa.cuenta_bancaria_id));")]
FOR_SHARE_CUENTA = "  select * into v_cuenta from crm.cuentas_bancarias where id = p_cuenta_id for share;"
FOR_SHARE_CONTRATO = "  where ct.id = p_contrato_id\n  for share;"
CANDADO_SOLICITUD = "  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('asignar-cuenta-pago:' || p_solicitud_id::text, 0));\n"

# ── 1 a 12: lógica del núcleo
mutante('01-sin-compuerta', 'sin la compuerta de administración', [(COMPUERTA, "  if false then")], espera_b='T1')
mutante('02-compuerta-operaciones', 'la compuerta acepta operaciones',
        [(COMPUERTA, "  if not (coalesce(private.admin_banca_vigente(v_actor), false) or exists (select 1 from public.perfiles p where p.id = v_actor and p.rol = 'operaciones' and p.activo is true)) then")], espera_b='T1')
mutante('03-sin-cliente', 'no exige que la cuenta sea del cliente', [(CLIENTE, "  if false then")], espera_b='T4')
mutante('04-sin-moneda', 'no exige la moneda', [(MONEDA, "  if false then")], espera_b='T4')
mutante('05-acepta-inactiva', 'acepta una cuenta inactiva', [(ACTIVA, "  if false then")], espera_b='T4')
mutante('06-con-cuenta-sin-mirar', 'no rechaza el contrato que ya tiene cuenta (queda la unicidad)', [(CON_CUENTA, "  if false then")], espera_b='^TC$',
        nota='equivalente en lo que se observa: la unicidad del vínculo, capturada, da el mismo mensaje')
mutante('06b-con-cuenta-doble', 'ni lo rechaza ni captura la unicidad (doble)', [(CON_CUENTA, "  if false then"), (CAPTURA, "  end;")], espera_b='T4')
mutante('07-acepta-cerrado', 'acepta un contrato cerrado', [(CERRADO, "  if false then")], espera_b='T4')
mutante('07b-solo-activo', 'rechaza el contrato vencido', [("v_ct.estado not in ('activo', 'vencido')", "v_ct.estado not in ('activo')")], espera_b='T3')
mutante('08-sin-motivo', 'no valida el motivo (queda el CHECK de la tabla)', [(MOTIVO, "  if false then")], espera_b='T4')
mutante('08b-motivo-sin-recortar', 'no recorta el motivo', [(V_MOTIVO, "  v_motivo text := coalesce(p_motivo, '');")], espera_b='T2')
mutante('08c-motivo-minimo-4', 'acepta 4 visibles', [("'', 'g')) < 5", "'', 'g')) < 4")], espera_b='T4')
mutante('08d-motivo-maximo-501', 'acepta 501 caracteres', [("or pg_catalog.length(v_motivo) > 500 then", "or pg_catalog.length(v_motivo) > 501 then")], espera_b='T4')
mutante('09-creado-por-nulo', 'el vínculo queda sin autor', [(VINCULO, VINCULO.replace('v_actor', 'null'))], espera_b='T1')
mutante('10-sin-constancia', 'no escribe la constancia', [(CONSTANCIA, "")], espera_b='T2')
mutante('11-idempotencia-sin-comparar', 'la solicitud repetida no compara los datos', [(MISMOS, "    if true then")], espera_b='T5')
mutante('11b-sin-idempotencia', 'no mira si la solicitud ya se usó', [("  if found then\n    if v_previa.contrato_id", "  if false then\n    if v_previa.contrato_id")], espera_b='T5')
mutante('12-sin-capturar-unicidad', 'no captura la violación de unicidad', [(CAPTURA, "  end;")], espera_b='T4')
mutante('12b-traduce-todo-23505', 'traduce CUALQUIER 23505 a «ya tiene cuenta»', [(FILTRO + "\n      raise;\n    end if;\n", "")], espera_b='T4')
mutante('12c-filtra-solo-tabla', 'filtra el 23505 solo por nombre de tabla', [(FILTRO, "    if v_tabla is distinct from 'contrato_cuentas_pago' then")], espera_b='T4')
mutante('12d-filtra-solo-esquema', 'filtra el 23505 solo por esquema', [(FILTRO, "    if v_esquema is distinct from 'crm' then")], espera_b='T4')
mutante('12e-filtra-por-tabla-sin-restriccion', 'vuelve a traducir por esquema y tabla, sin mirar la restricción (la clave primaria del vínculo pasaría por «ya tiene cuenta»)',
        [(FILTRO, "    if v_esquema is distinct from 'crm' or v_tabla is distinct from 'contrato_cuentas_pago' then")], espera_b='T4')
mutante('12f-filtra-solo-restriccion', 'filtra el 23505 solo por el nombre de la restricción',
        [(FILTRO, "    if v_restriccion is distinct from 'contrato_cuentas_pago_contrato_id_key' then")], espera_b='T4')
# ── El retorno
mutante('r1-ultimos-entero', '«ultimos» devuelve el número de cuenta entero', [(ULTIMOS, "    'ultimos', v_cuenta.numero_cuenta);")], espera_b='T1')
mutante('r1b-ultimos-sin-umbral', '«ultimos» sin el umbral de 8 caracteres', [(ULTIMOS, "    'ultimos', pg_catalog.right(v_cuenta.numero_cuenta, 4));")], espera_b='T2')
mutante('r1c-repeticion-sin-umbral', 'la repetición devuelve «ultimos» sin el umbral', [(REP_ULTIMOS, "(select pg_catalog.right(cb.numero_cuenta, 4)")], espera_b='T2')
mutante('r1d-umbral-7', '«ultimos» con el umbral en 7 caracteres', [(ULTIMOS, ULTIMOS.replace('>= 8', '>= 7'))], espera_b='T2')
mutante('r2-repetida-dos-claves', 'la repetición devuelve otras claves', [(REPETIDA, "      return pg_catalog.jsonb_build_object('solicitud_id', p_solicitud_id, 'ya_aplicada', true);")], espera_b='T5')
mutante('r3-retorno-con-cci', 'el retorno lleva el CCI', [(ULTIMOS, ULTIMOS[:-2] + ", 'cci', v_cuenta.cci);")], espera_b='T1')
# ── Candados y la guarda de aislamiento (solo los ve la concurrencia: en la prueba secuencial, que corre en
# UNA transacción READ COMMITTED, únicamente los delata la huella)
SIN_GUARDA = [(GUARDA, "")]
GUARDA_RR = [("<> 'read committed' then\n    raise exception using errcode = '0A000'", "not in ('read committed', 'repeatable read') then\n    raise exception using errcode = '0A000'")]
GUARDA_DESPUES = [(GUARDA + COMPUERTA_ENTERA, COMPUERTA_ENTERA + GUARDA)]
mutante('g1-sin-guarda-de-aislamiento', 'sin la guarda de aislamiento', SIN_GUARDA, espera_b='^TC$', nota='lo caza la concurrencia con dos sesiones (tramo 12)')
mutante('g2-guarda-admite-repeatable-read', 'la guarda deja pasar REPEATABLE READ', GUARDA_RR, espera_b='^TC$', nota='lo caza la concurrencia con dos sesiones (tramo 12)')
mutante('g3-guarda-despues-de-la-compuerta', 'la guarda va DESPUÉS de la compuerta (ya miró datos)', GUARDA_DESPUES, espera_b='^TC$', nota='lo caza la concurrencia con dos sesiones (tramo 12)')
mutante('c1-sin-for-share-cuenta', 'sin FOR SHARE de la cuenta', [(FOR_SHARE_CUENTA, FOR_SHARE_CUENTA.replace(' for share;', ';'))], espera_b='^TC$',
        nota='lo caza la concurrencia con dos sesiones (tramo 12, y frente a la carga en el tramo 9)')
mutante('c2-sin-for-share-contrato', 'sin FOR SHARE del contrato', [(FOR_SHARE_CONTRATO, "  where ct.id = p_contrato_id;")], espera_b='^TC$', nota='lo caza la concurrencia con dos sesiones (tramo 12)')
mutante('c3-sin-candado-solicitud', 'sin el candado consultivo de la solicitud', [(CANDADO_SOLICITUD, "")], espera_b='^TC$', nota='lo caza la concurrencia con dos sesiones (tramo 12)')
for n, pares in (('c0-sin-capturar-unicidad', [(CAPTURA, "  end;")]), ('c1-sin-for-share-cuenta', [(FOR_SHARE_CUENTA, FOR_SHARE_CUENTA.replace(' for share;', ';'))]),
                 ('c2-sin-for-share-contrato', [(FOR_SHARE_CONTRATO, "  where ct.id = p_contrato_id;")]), ('c3-sin-candado-solicitud', [(CANDADO_SOLICITUD, "")]),
                 ('g1-sin-guarda-de-aislamiento', SIN_GUARDA), ('g2-guarda-admite-repeatable-read', GUARDA_RR), ('g3-guarda-despues-de-la-compuerta', GUARDA_DESPUES)):
    escribe('%s/vivo/%s.sql' % (T, n), vivo(NUCLEO, pares))
# ── 13 a 24: permisos, forma y tabla
G_PUERTA = "grant execute on function %s\n  to authenticated;" % PUERTA
G_NUCLEO = "grant execute on function %s\n  to authenticated;" % NUCLEO
R_PUERTA = "revoke all on function %s\n  from public, anon, authenticated, service_role;\n" % PUERTA
R_CANDADO = "revoke all on function %s from public, anon, authenticated, service_role;" % CANDADO
R_TABLA = "revoke all on %s from public, anon, authenticated, service_role;" % TABLA
RLS = "alter table %s enable row level security;\n" % TABLA
def disparador(nombre):
    return re.search(r"create trigger %s\n.*\n.*;\n" % nombre, mig).group(0)
AUDIT = disparador('trg_audit_contrato_cuenta_pago_asignaciones')
T_INM = 'trg_contrato_cuenta_pago_asignaciones_00_inmutable'
T_NB = 'trg_contrato_cuenta_pago_asignaciones_00_no_borrar'
T_SV = 'trg_contrato_cuenta_pago_asignaciones_00_sin_vaciar'
mutante('13-puerta-anon', 'la puerta con EXECUTE para anon', [(G_PUERTA, G_PUERTA.replace('to authenticated;', 'to authenticated, anon;'))],
        iny="grant execute on function %s to anon;\n" % PUERTA, espera_b='T1')
mutante('13b-puerta-public', 'la puerta sin su revoke (PUBLIC ejecuta)', [(R_PUERTA, "")], iny="grant execute on function %s to public;\n" % PUERTA, espera_b='T1')
mutante('14-nucleo-anon', 'el núcleo con EXECUTE para anon', [(G_NUCLEO, G_NUCLEO.replace('to authenticated;', 'to authenticated, anon;'))],
        iny="grant execute on function %s to anon;\n" % NUCLEO, espera_b='T1')
mutante('14b-nucleo-service-role', 'el núcleo con EXECUTE para service_role', [(G_NUCLEO, G_NUCLEO.replace('to authenticated;', 'to authenticated, service_role;'))],
        iny="grant execute on function %s to service_role;\n" % NUCLEO, espera_b='T1')
mutante('14c-candado-authenticated', 'el candado con EXECUTE para authenticated', [(R_CANDADO, R_CANDADO + "\ngrant execute on function %s to authenticated;" % CANDADO)],
        iny="grant execute on function %s to authenticated;\n" % CANDADO, espera_b='TC')
mutante('15-puerta-definer', 'la puerta SECURITY DEFINER', [("volatile security invoker", "volatile security definer")],
        iny="alter function %s security definer;\n" % PUERTA, espera_b='TC')
mutante('15b-nucleo-invoker', 'el núcleo SECURITY INVOKER', [("returns jsonb\nlanguage plpgsql\nsecurity definer", "returns jsonb\nlanguage plpgsql\nsecurity invoker")],
        iny="alter function %s security invoker;\n" % NUCLEO, espera_b='T1')
mutante('15c-nucleo-sin-search-path', 'el núcleo sin search_path fijo', [("returns jsonb\nlanguage plpgsql\nsecurity definer\nset search_path to ''\n", "returns jsonb\nlanguage plpgsql\nsecurity definer\n")],
        iny="alter function %s reset search_path;\n" % NUCLEO, espera_b='TC')
mutante('15d-nucleo-search-path-cambiado', 'el núcleo con el search_path cambiado (pg_catalog, public)',
        [("returns jsonb\nlanguage plpgsql\nsecurity definer\nset search_path to ''\n", "returns jsonb\nlanguage plpgsql\nsecurity definer\nset search_path to pg_catalog, public\n")],
        iny="alter function %s set search_path to pg_catalog, public;\n" % NUCLEO, espera_b='TC')
mutante('15e-puerta-stable', 'la puerta declarada STABLE', [("volatile security invoker", "stable security invoker")],
        iny="alter function %s stable;\n" % PUERTA, espera_b='TC')
mutante('16-tabla-select-authenticated', 'la tabla con lectura para authenticated', [(R_TABLA, R_TABLA + "\ngrant select on %s to authenticated;" % TABLA)],
        iny="grant select on %s to authenticated;\n" % TABLA, espera_b='T7')
mutante('16b-tabla-todo-service-role', 'la tabla con todo para service_role', [(R_TABLA, R_TABLA + "\ngrant all on %s to service_role;" % TABLA)],
        iny="grant all on %s to service_role;\n" % TABLA, espera_b='T7')
mutante('17-tabla-sin-rls', 'la tabla sin RLS', [(RLS, "")], iny="alter table %s disable row level security;\n" % TABLA,
        espera_b='T7')
mutante('18-tabla-sin-bitacora', 'la tabla sin bitácora', [(AUDIT, "")], iny="drop trigger trg_audit_contrato_cuenta_pago_asignaciones on %s;\n" % TABLA, espera_b='T2')
mutante('18b-bitacora-solo-altas', 'la bitácora solo de altas', [("  after insert or delete or update on %s" % TABLA, "  after insert on %s" % TABLA)],
        iny=("drop trigger trg_audit_contrato_cuenta_pago_asignaciones on %s;\ncreate trigger trg_audit_contrato_cuenta_pago_asignaciones after insert on %s "
             "for each row execute function private.log_audit_crm();\n") % (TABLA, TABLA), espera_b='T7')
for n, nombre, desc in (('19-sin-candado-no-se-modifica', T_INM, 'sin el candado «no se modifica»'),
                        ('19b-sin-candado-no-se-borra', T_NB, 'sin el candado «no se borra»'),
                        ('19c-sin-candado-no-se-vacia', T_SV, 'sin el candado «no se vacía»')):
    mutante(n, desc, [(disparador(nombre), "")], iny="drop trigger %s on %s;\n" % (nombre, TABLA), espera_b='T7')
BLOQUEA = "  raise exception using errcode = '22023',\n    message = 'El registro de asignaciones de cuenta de pago no se modifica ni se vacía';"
mutante('19d-candado-deja-pasar', 'el candado «no se modifica» deja pasar', [(BLOQUEA, "  return new;")], espera_b='T7', firma=CANDADO)
mutante('20-cuerpo-sin-huella', 'el cuerpo cambia (un comentario) y la huella no', [(COMPUERTA, "  -- cambio sin actualizar la huella\n" + COMPUERTA)], espera_b='^TC$',
        nota='equivalente por construcción: solo cambia un comentario')
mutante('21-constancia-con-fk', 'la constancia con una clave foránea', [("  contrato_id         uuid not null,", "  contrato_id         uuid not null references public.contratos (id),")],
        iny="alter table %s add constraint zz_prueba_fk foreign key (contrato_id) references public.contratos (id);\n" % TABLA, espera_b='T7')
COMENTARIO = "comment on column %s.motivo is 'Motivo escrito por administración (5 a 500 caracteres).';\n" % TABLA
mutante('22-columna-sin-comentario', 'una columna sin comentario', [(COMENTARIO, "")], iny="comment on column %s.motivo is null;\n" % TABLA, espera_b='T7')
C_PUERTA = re.search(r"comment on function crm\.asignar_cuenta_pago_contrato\(uuid,uuid,uuid,text\) is '.*';\n", mig).group(0)
mutante('22b-puerta-sin-comentario', 'la puerta sin comentario', [(C_PUERTA, "")], iny="comment on function %s is null;\n" % PUERTA, espera_b='TC')
# ── Las reglas de la tabla y la forma de los candados: el postflight las exige.
CHECK = re.search(r"check \(motivo = regexp_replace\(.*\n.*\n\s*and length\(motivo\) <= 500\)", mig).group(0)
SOLICITUD_UQ = "constraint contrato_cuenta_pago_asignaciones_solicitud_uq unique,"
mutante('23-motivo-sin-check', 'el CHECK del motivo vaciado (mismo nombre, ya no valida)', [(CHECK, "check (motivo is not null)")],
        iny="alter table %s drop constraint contrato_cuenta_pago_asignaciones_motivo_valido;\n" % TABLA, espera_b='T7')
mutante('23b-solicitud-sin-unica', 'la tabla sin la unicidad de la solicitud', [(" " + SOLICITUD_UQ, ",")],
        iny="alter table %s drop constraint contrato_cuenta_pago_asignaciones_solicitud_uq;\n" % TABLA, espera_b='T7')
CON_CANDADO = ("  before update on %s\n  for each row execute function %s;" % (TABLA, CANDADO))
mutante('23c-candado-con-condicion', 'el candado «no se modifica» con una condición que nunca se cumple (mismo nombre, habilitado)',
        [(CON_CANDADO, CON_CANDADO.replace("for each row execute", "for each row when (old.motivo is null) execute"))],
        iny=("drop trigger %s on %s;\ncreate trigger %s before update on %s "
             "for each row when (old.motivo is null) execute function %s;\n") % (T_INM, TABLA, T_INM, TABLA, CANDADO), espera_b='T7')
mutante('23e-solicitud-unica-diferible', 'la unicidad de la solicitud DIFERIBLE', [(SOLICITUD_UQ, SOLICITUD_UQ[:-1] + " deferrable initially deferred,")],
        iny=("alter table %s drop constraint contrato_cuenta_pago_asignaciones_solicitud_uq;\n"
             "alter table %s add constraint contrato_cuenta_pago_asignaciones_solicitud_uq unique (solicitud_id) deferrable initially deferred;\n") % (TABLA, TABLA), espera_b='T7')
mutante('23f-no-borrar-otra-funcion', 'el candado «no se borra» ejecutando otra función',
        [("  for each row execute function private.trg_registro_cuenta_pago_no_borrar();", "  for each row execute function %s;" % CANDADO)],
        iny=("drop trigger %s on %s;\ncreate trigger %s before delete on %s for each row execute function %s;\n") % (T_NB, TABLA, T_NB, TABLA, CANDADO), espera_b='T7')
mutante('23g-candado-solo-una-columna', 'el candado «no se modifica» solo para una columna',
        [(CON_CANDADO, CON_CANDADO.replace("before update on", "before update of motivo on"))],
        iny=("drop trigger %s on %s;\ncreate trigger %s before update of motivo on %s for each row execute function %s;\n") % (T_INM, TABLA, T_INM, TABLA, CANDADO), espera_b='T7')
# ── Lo que el postflight NO ve (se anota a sabiendas, espera_a = MUTANTE_SIN_ERROR): un permiso POR COLUMNA
# (has_table_privilege solo mira la tabla), el CHECK aflojado con su mismo nombre (solo busca «regexp_replace»
# en su definición) y un revoke que en este banco es redundante.
mutante('16c-columna-select-authenticated', 'una columna de la tabla con lectura para authenticated (permiso POR COLUMNA)',
        [(R_TABLA, R_TABLA + "\ngrant select (motivo) on %s to authenticated;" % TABLA)],
        iny="grant select (motivo) on %s to authenticated;\n" % TABLA, espera_a='MUTANTE_SIN_ERROR', espera_b='T7')
mutante('23d-check-minimo-1', 'el CHECK del motivo aflojado (1 visible en vez de 5), con su mismo nombre', [("'', 'g')) >= 5", "'', 'g')) >= 1")],
        iny=("alter table %s drop constraint contrato_cuenta_pago_asignaciones_motivo_valido;\n"
             "alter table %s add constraint contrato_cuenta_pago_asignaciones_motivo_valido %s;\n") % (TABLA, TABLA, CHECK.replace(">= 5", ">= 1")),
        espera_a='MUTANTE_SIN_ERROR', espera_b='T7')
mutante('24-tabla-sin-revoke', 'la tabla sin su revoke (en este banco crm no da permisos por defecto)', [(R_TABLA + "\n", "")], iny='', espera_a='MUTANTE_SIN_ERROR')
# ── Solo en la prueba: la compuerta ajena (private.admin_banca_vigente) alterada. La migración la para en el PREFLIGHT (tramo 13).
ROLES = "p.rol in ('admin', 'superadmin')"
COMPUERTA_AJENA = vivo('private.admin_banca_vigente(uuid)', [(ROLES, "p.rol in ('admin', 'superadmin', 'operaciones')")])
escribe('%s/mut/02b-compuerta-ajena.iny.sql' % T, COMPUERTA_AJENA)
lista.append('02b-compuerta-ajena|la compuerta de F3 (private.admin_banca_vigente) acepta operaciones|-|T1|-')
escribe('%s/mut/lista.txt' % T, '\n'.join(lista) + '\n')
# La migración ENTERA sin RLS: para ver qué veredicto da una aplicación que falla, sentencia a sentencia.
escribe('%s/mut/17-tabla-sin-rls.entero.sql' % T, mig.replace(RLS, '', 1))

# ── Mutantes del PREFLIGHT: el mundo alterado antes de aplicar la migración (todo en una transacción que se deshace)
pre = []
def mundo(n, desc, alteracion, espera):
    escribe('%s/pre/%s.sql' % (T, n), mensaje(alteracion, MC))
    pre.append('|'.join([n, desc, espera]))
PIEZAS = 'ERROR:  ASIGNAR PREFLIGHT: la compuerta de administración o los candados del vínculo no son los esperados'
TRIGGERS = 'ERROR:  ASIGNAR PREFLIGHT: faltan los triggers de coherencia, bitácora o candado del vínculo'
UNICO = 'ERROR:  ASIGNAR PREFLIGHT: el vínculo ya no es único por contrato \\(o su restricción cambió de nombre\\)'
SENUELO = ("create function private.zz_senuelo() returns trigger language plpgsql set search_path to '' as $s$ begin return new; end $s$;\n")
COHERENTE_AJENA = vivo('private.trg_contrato_cuenta_pago_coherente()', [("and cb.moneda = ct.moneda", "and true")])
NO_BORRAR_AJENA = vivo('private.trg_registro_cuenta_pago_no_borrar()', [("Los registros de cuentas de pago no se borran", "No se borran")])
BITACORA_SENUELO = (SENUELO + "drop trigger trg_audit_contrato_cuentas_pago on crm.contrato_cuentas_pago;\n"
                    "create trigger trg_audit_contrato_cuentas_pago after insert or delete or update on crm.contrato_cuentas_pago for each row execute function private.zz_senuelo();")
mundo('p1-compuerta-alterada', 'private.admin_banca_vigente acepta operaciones', COMPUERTA_AJENA, PIEZAS)
mundo('p2-coherencia-alterada', 'el candado de coherencia del vínculo cambiado', COHERENTE_AJENA, PIEZAS)
mundo('p3-no-borrar-alterado', 'el candado «no se borra» cambiado', NO_BORRAR_AJENA, PIEZAS)
mundo('p4-coherencia-apagada', 'el disparador de coherencia apagado', "alter table crm.contrato_cuentas_pago disable trigger trg_contrato_cuenta_pago_coherente;", TRIGGERS)
mundo('p5-coherencia-senuelo', 'el disparador de coherencia, mismo nombre y otra función',
      SENUELO + "drop trigger trg_contrato_cuenta_pago_coherente on crm.contrato_cuentas_pago;\n"
      "create trigger trg_contrato_cuenta_pago_coherente before insert or update on crm.contrato_cuentas_pago for each row execute function private.zz_senuelo();", TRIGGERS)
mundo('p6-bitacora-senuelo', 'la bitácora del vínculo, mismo nombre y otra función', BITACORA_SENUELO, TRIGGERS)
mundo('p7-inmutable-ausente', 'sin el candado inmutable del vínculo', "drop trigger trg_contrato_cuenta_pago_00_inmutable on crm.contrato_cuentas_pago;", TRIGGERS)
mundo('p8-unico-diferible', 'la unicidad del vínculo vuelta DIFERIBLE',
      "alter table crm.contrato_cuentas_pago drop constraint contrato_cuentas_pago_contrato_id_key;\n"
      "alter table crm.contrato_cuentas_pago add constraint contrato_cuentas_pago_contrato_id_key unique (contrato_id) deferrable initially deferred;", UNICO)
mundo('p9-unico-ausente', 'sin la unicidad del vínculo por contrato', "alter table crm.contrato_cuentas_pago drop constraint contrato_cuentas_pago_contrato_id_key;", UNICO)
mundo('p10-unico-parcial', 'la unicidad del vínculo vuelta PARCIAL',
      "alter table crm.contrato_cuentas_pago drop constraint contrato_cuentas_pago_contrato_id_key;\n"
      "create unique index contrato_cuentas_pago_contrato_id_key on crm.contrato_cuentas_pago (contrato_id) where creado_por is not null;", UNICO)
mundo('p11-sin-usage-private', 'authenticated sin USAGE sobre private', "revoke usage on schema private from authenticated;",
      'ERROR:  ASIGNAR PREFLIGHT: authenticated necesita USAGE sobre crm y private')
mundo('p12-columna-renombrada', 'crm.contrato_cuentas_pago sin la columna creado_por', "alter table crm.contrato_cuentas_pago rename column creado_por to autor;",
      'ERROR:  ASIGNAR PREFLIGHT: alguna tabla no tiene las columnas esperadas')
mundo('p13-sin-log-audit', 'sin private.log_audit_crm (renombrada)', "alter function private.log_audit_crm() rename to zz_log_audit_crm;",
      'ERROR:  ASIGNAR PREFLIGHT: faltan dependencias')
mundo('p14-unico-renombrado', 'la restricción de unicidad del vínculo con otro nombre (el núcleo la reconoce por su nombre)',
      "alter table crm.contrato_cuentas_pago rename constraint contrato_cuentas_pago_contrato_id_key to zz_un_vinculo_por_contrato;", UNICO)
escribe('%s/pre/lista.txt' % T, '\n'.join(pre) + '\n')

# ── Reversas alteradas para la concurrencia
SIN_CANDADO = una(rev, "    execute 'lock table crm.contrato_cuenta_pago_asignaciones in access exclusive mode';\n", 'la reversa')
escribe('%s/vivo/reversa-sin-candado.sql' % T, rev.replace(SIN_CANDADO, ''))
AISLAMIENTO = re.search(r"  if pg_catalog\.current_setting\('transaction_isolation'\) <> 'read committed' then\n.*\n.*\n  end if;\n", rev)
assert AISLAMIENTO, 'la reversa ya no exige READ COMMITTED como se esperaba'
escribe('%s/vivo/reversa-sin-aislamiento.sql' % T, rev.replace(AISLAMIENTO.group(0), ''))

# ── reabrir-puerta frente a un mundo alterado: cerrar la puerta + la alteración + reabrir-puerta, en UNA
# transacción que se deshace. MUTANTE_SIN_ERROR = reabrió.
CERRAR = ("revoke execute on function %s from authenticated;\nrevoke execute on function %s from authenticated;\n" % (PUERTA, NUCLEO))
ROL = "create role zz_asignar_prueba;\n"
mundos_rea = []
def reabrir(n, desc, alteracion, espera='NEGAR'):
    mundos_rea.append((n, desc, alteracion, espera))
reabrir('r00-control', 'nada alterado (testigo: así sí reabre)', "", 'REABRIR')
reabrir('r01-nucleo-alterado', 'el NÚCLEO con el cuerpo alterado', vivo(NUCLEO, [(COMPUERTA, "  -- alterado\n" + COMPUERTA)]))
reabrir('r02-puerta-alterada', 'la PUERTA con el cuerpo alterado', vivo(PUERTA, [("  select private.", "  select /* alterada */ private.")]))
reabrir('r03-candado-neutralizado', 'el CANDADO neutralizado (su cuerpo deja pasar)', vivo(CANDADO, [(BLOQUEA, "  return new;")]))
reabrir('r04-puerta-definer', 'la PUERTA vuelta SECURITY DEFINER (mismo cuerpo)', "alter function %s security definer;" % PUERTA)
reabrir('r05-nucleo-sin-search-path', 'el NÚCLEO sin search_path fijo (mismo cuerpo)', "alter function %s reset search_path;" % NUCLEO)
reabrir('r05b-nucleo-search-path-cambiado', 'el NÚCLEO con el search_path CAMBIADO (pg_catalog, public)', "alter function %s set search_path to pg_catalog, public;" % NUCLEO)
reabrir('r06-nucleo-invoker', 'el NÚCLEO vuelto SECURITY INVOKER (mismo cuerpo)', "alter function %s security invoker;" % NUCLEO)
reabrir('r07-nucleo-ajuste-de-mas', 'el NÚCLEO con un ajuste de más además del search_path', "alter function %s set lock_timeout to '5s';" % NUCLEO)
reabrir('r08-puerta-anon', 'anon colado en la puerta', "grant execute on function %s to anon;" % PUERTA)
reabrir('r09-nucleo-service-role', 'service_role colado en el núcleo', "grant execute on function %s to service_role;" % NUCLEO)
reabrir('r10-candado-authenticated', 'authenticated con EXECUTE en el candado', "grant execute on function %s to authenticated;" % CANDADO)
reabrir('r10b-puerta-rol-cualquiera', 'un rol cualquiera (creado para la prueba) con EXECUTE en la puerta', ROL + "grant execute on function %s to zz_asignar_prueba;" % PUERTA)
reabrir('r10c-nucleo-public', 'PUBLIC con EXECUTE en el núcleo', "grant execute on function %s to public;" % NUCLEO)
reabrir('r11-candado-apagado', 'el candado «no se modifica» DESHABILITADO en la tabla', "alter table %s disable trigger %s;" % (TABLA, T_INM))
reabrir('r12-candado-con-condicion', 'el candado «no se modifica» con una condición que nunca se cumple',
        "drop trigger %s on %s;\ncreate trigger %s before update on %s for each row when (old.motivo is null) execute function %s;" % (T_INM, TABLA, T_INM, TABLA, CANDADO))
reabrir('r13-no-borrar-otra-funcion', 'el candado «no se borra» ejecutando otra función',
        "drop trigger %s on %s;\ncreate trigger %s before delete on %s for each row execute function %s;" % (T_NB, TABLA, T_NB, TABLA, CANDADO))
reabrir('r14-sin-candado-vaciar', 'la tabla sin el candado «no se vacía»', "drop trigger %s on %s;" % (T_SV, TABLA))
reabrir('r15-sin-bitacora', 'la tabla SIN bitácora', "drop trigger trg_audit_contrato_cuenta_pago_asignaciones on %s;" % TABLA)
reabrir('r15b-bitacora-solo-altas', 'la bitácora solo de altas',
        ("drop trigger trg_audit_contrato_cuenta_pago_asignaciones on %s;\ncreate trigger trg_audit_contrato_cuenta_pago_asignaciones after insert on %s "
         "for each row execute function private.log_audit_crm();") % (TABLA, TABLA))
reabrir('r16-sin-rls', 'la tabla SIN RLS', "alter table %s disable row level security;" % TABLA)
reabrir('r17-tabla-select-authenticated', 'un permiso de tabla de más: lectura para authenticated', "grant select on %s to authenticated;" % TABLA)
reabrir('r17b-tabla-todo-service-role', 'un permiso de tabla de más: todo para service_role', "grant all on %s to service_role;" % TABLA)
reabrir('r17c-tabla-select-public', 'un permiso de tabla de más: lectura para PUBLIC', "grant select on %s to public;" % TABLA)
reabrir('r18-sin-unica', 'la tabla sin la unicidad de la solicitud', "alter table %s drop constraint contrato_cuenta_pago_asignaciones_solicitud_uq;" % TABLA)
reabrir('r19-unica-diferible', 'la unicidad de la solicitud vuelta DIFERIBLE',
        ("alter table %s drop constraint contrato_cuenta_pago_asignaciones_solicitud_uq;\n"
         "alter table %s add constraint contrato_cuenta_pago_asignaciones_solicitud_uq unique (solicitud_id) deferrable initially deferred;") % (TABLA, TABLA))
reabrir('r20-sin-check', 'la tabla sin el CHECK del motivo', "alter table %s drop constraint contrato_cuenta_pago_asignaciones_motivo_valido;" % TABLA)
reabrir('r24-compuerta-ajena', 'la compuerta de F3 (private.admin_banca_vigente) alterada: acepta operaciones', COMPUERTA_AJENA)
reabrir('r25-coherencia-ajena', 'el candado de coherencia del vínculo (F3) alterado', COHERENTE_AJENA)
reabrir('r26-no-borrar-ajeno', 'el candado «no se borra» (F3) alterado', NO_BORRAR_AJENA)
reabrir('r27-coherencia-apagada', 'el disparador de coherencia del vínculo deshabilitado', "alter table crm.contrato_cuentas_pago disable trigger trg_contrato_cuenta_pago_coherente;")
reabrir('r28-bitacora-vinculo-senuelo', 'la bitácora del vínculo, mismo nombre y otra función', BITACORA_SENUELO)
# Lo único que «piezas enteras» no mira (límite declarado; el núcleo valida el motivo por su cuenta): se mide.
reabrir('r21-check-redefinido', 'el CHECK del motivo redefinido con su mismo nombre (ya no valida nada)',
        ("alter table %s drop constraint contrato_cuenta_pago_asignaciones_motivo_valido;\n"
         "alter table %s add constraint contrato_cuenta_pago_asignaciones_motivo_valido check (motivo is not null);") % (TABLA, TABLA), 'MEDIR')
# Lo que antes solo se medía y ahora «piezas enteras» SÍ mira (se niega):
reabrir('r22-con-fk', 'una clave foránea añadida a la constancia',
        "alter table %s add constraint zz_prueba_fk foreign key (contrato_id) references public.contratos (id);" % TABLA)
reabrir('r23-columna-select', 'un permiso de lectura POR COLUMNA para authenticated', "grant select (motivo) on %s to authenticated;" % TABLA)
reabrir('r29-puerta-stable', 'la PUERTA declarada STABLE (mismo cuerpo)', "alter function %s stable;" % PUERTA)
reabrir('r30-disparador-de-mas', 'un disparador de más en la constancia que se traga las altas (BEFORE INSERT que devuelve NULL)',
        ("create function private.zz_traga() returns trigger language plpgsql set search_path to '' as $s$ begin return null; end $s$;\n"
         "create trigger zz_traga before insert on %s for each row execute function private.zz_traga();") % TABLA)
reabrir('r31-vinculo-sin-unicidad', 'el vínculo SIN su unicidad por contrato (el preflight de la migración sí la exige)',
        "alter table crm.contrato_cuentas_pago drop constraint contrato_cuentas_pago_contrato_id_key;")
reabrir('r32-vinculo-unicidad-renombrada', 'la unicidad del vínculo con otro nombre (el núcleo la reconoce por su nombre)',
        "alter table crm.contrato_cuentas_pago rename constraint contrato_cuentas_pago_contrato_id_key to zz_un_vinculo_por_contrato;")
def mundo_rea(alteracion, cuerpo_reabrir):
    return 'begin;\n' + CERRAR + alteracion + '\n' + cuerpo_reabrir + "\nselect 'MUTANTE_SIN_ERROR';\nrollback;\n"
for n, desc, alteracion, espera in mundos_rea:
    escribe('%s/rea/%s.sql' % (T, n), mundo_rea(alteracion, REC))
escribe('%s/rea/lista.txt' % T, '\n'.join('|'.join([n, desc, espera]) for n, desc, alteracion, espera in mundos_rea) + '\n')

# ── Mutantes de reabrir-puerta: «piezas enteras» con una cláusula menos (en sus dos copias: antes y después de
# abrir). Con cada mutante, reabrir debe REABRIR exactamente en los mundos que esa cláusula vigilaba.
def clausula(inicio):
    """La cláusula de primer nivel («    and …») que empieza con ese texto, hasta la siguiente."""
    i = rea.index(inicio)
    m = re.compile(r"\n    (?:and |-- )|\n  \), false\)").search(rea, i + 1)
    return rea[i:m.start() + 1]
def sin(fragmento, reemplazo=''):
    una(REC, fragmento, 'el cuerpo de reabrir-puerta', 2)
    return REC.replace(fragmento, reemplazo)
CONSTANCIA_RC = "pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones')"
mutantes_rea = [
    ('m01-sin-huellas', 'sin comparar la huella de los cuerpos', sin("     where pg_catalog.md5(p.prosrc) = f.huella\n", "     where true\n"),
     'r01-nucleo-alterado r02-puerta-alterada r03-candado-neutralizado'),
    ('m02-sin-definer', 'sin mirar DEFINER/INVOKER', sin("       and p.prosecdef = f.definer\n"), 'r04-puerta-definer r06-nucleo-invoker'),
    ('m03-sin-search-path', 'sin exigir el search_path exacto', sin("       and p.proconfig = array['search_path=\"\"']\n"),
     'r05-nucleo-sin-search-path r05b-nucleo-search-path-cambiado r07-nucleo-ajuste-de-mas'),
    ('m04-sin-nadie-de-mas', 'sin mirar quién más ejecuta', sin(clausula("    and not exists (\n      select 1 from pg_catalog.pg_proc p\n")),
     'r08-puerta-anon r09-nucleo-service-role r10-candado-authenticated r10b-puerta-rol-cualquiera r10c-nucleo-public'),
    ('m05-sin-compuerta-f3', 'sin la huella de la compuerta de F3',
     sin(clausula("    and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p\n         where p.oid = pg_catalog.to_regprocedure('private.admin_banca_vigente(uuid)'))")), 'r24-compuerta-ajena'),
    ('m06-sin-coherencia-f3', 'sin la huella del candado de coherencia de F3',
     sin(clausula("    and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p\n         where p.oid = pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_coherente()'))")), 'r25-coherencia-ajena'),
    ('m07-sin-no-borrar-f3', 'sin la huella del candado «no se borra» de F3',
     sin(clausula("    and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p\n         where p.oid = pg_catalog.to_regprocedure('private.trg_registro_cuenta_pago_no_borrar()'))")), 'r26-no-borrar-ajeno'),
    ('m08-sin-disparadores-del-vinculo', 'sin mirar los disparadores del vínculo',
     sin(clausula("    and (select pg_catalog.count(*) from pg_catalog.pg_trigger t\n         where t.tgrelid = pg_catalog.to_regclass('crm.contrato_cuentas_pago')")),
     'r27-coherencia-apagada r28-bitacora-vinculo-senuelo'),
    ('m09-sin-rls', 'sin mirar la RLS de la constancia', sin(clausula("    and coalesce((select t.relrowsecurity")), 'r16-sin-rls'),
    ('m10-sin-permisos-de-tabla', 'sin mirar los permisos de tabla de la API', sin(clausula("    and not exists (\n      select 1 from (values ('anon')")),
     'r17-tabla-select-authenticated r17b-tabla-todo-service-role r17c-tabla-select-public'),
    ('m11-sin-candados', 'sin mirar los tres candados de la constancia',
     sin(clausula("    and (select pg_catalog.count(*) from pg_catalog.pg_trigger t\n         where t.tgrelid = %s\n" % CONSTANCIA_RC)),
     'r11-candado-apagado r12-candado-con-condicion r13-no-borrar-otra-funcion r14-sin-candado-vaciar'),
    ('m12-sin-bitacora', 'sin mirar la bitácora de la constancia', sin(clausula("    and exists (\n      select 1 from pg_catalog.pg_trigger t")),
     'r15-sin-bitacora r15b-bitacora-solo-altas'),
    ('m13-sin-unica', 'sin mirar la unicidad de la solicitud',
     sin(clausula("    and exists (\n      select 1 from pg_catalog.pg_constraint c\n      where c.conrelid = %s and c.contype = 'u'" % CONSTANCIA_RC)),
     'r18-sin-unica r19-unica-diferible'),
    ('m14-sin-check', 'sin mirar el CHECK del motivo',
     sin(clausula("    and exists (\n      select 1 from pg_catalog.pg_constraint c\n      where c.conrelid = %s and c.contype = 'c'" % CONSTANCIA_RC)), 'r20-sin-check'),
    ('m15-sin-unicidad-del-vinculo', 'sin mirar la unicidad del vínculo por contrato',
     sin(clausula("    and exists (\n      select 1\n      from pg_catalog.pg_constraint c\n      join pg_catalog.pg_index i")),
     'r31-vinculo-sin-unicidad r32-vinculo-unicidad-renombrada'),
    ('m16-sin-volatilidad', 'sin mirar que la puerta y el núcleo sean VOLATILE',
     sin(clausula("    and (select pg_catalog.count(*) from pg_catalog.pg_proc p\n         where p.oid in (")), 'r29-puerta-stable'),
    ('m17-sin-claves-foraneas', 'sin mirar que la constancia siga sin claves foráneas',
     sin(clausula("    and not exists (\n      select 1 from pg_catalog.pg_constraint c\n      where c.conrelid = %s and c.contype = 'f')" % CONSTANCIA_RC)), 'r22-con-fk'),
    ('m18-sin-permisos-por-columna', 'sin mirar los permisos por columna de la constancia',
     sin(clausula("    and not exists (\n      select 1 from pg_catalog.pg_attribute a")), 'r23-columna-select'),
    ('m19-sin-disparadores-de-mas', 'sin mirar si la constancia tiene disparadores de más',
     sin(clausula("    and not exists (\n      select 1 from pg_catalog.pg_trigger t")), 'r30-disparador-de-mas'),
]
for mid, mdesc, cuerpo_mutado, esperados in mutantes_rea:
    assert cuerpo_mutado != REC
    for n, desc, alteracion, espera in mundos_rea:
        if espera == 'NEGAR':
            escribe('%s/rea/%s/%s.sql' % (T, mid, n), mundo_rea(alteracion, cuerpo_mutado))
escribe('%s/rea/mutantes.txt' % T, '\n'.join('|'.join([mid, mdesc, esperados]) for mid, mdesc, cuerpo_mutado, esperados in mutantes_rea) + '\n')

# ── La reversa frente a un mundo alterado: la alteración + la reversa + el veredicto que daría + el estado en
# que lo dejaría, en UNA transacción que se deshace. Punto de partida: aplicada, abierta, registrada y sin asignaciones.
VEREDICTO_REV = rev[rev.rindex('commit;') + len('commit;'):]
ESTADO = ("select 'ESTADO piezas=' || ((pg_catalog.to_regclass('%(t)s') is not null)::int + (pg_catalog.to_regprocedure('%(p)s') is not null)::int\n"
          "         + (pg_catalog.to_regprocedure('%(n)s') is not null)::int + (pg_catalog.to_regprocedure('%(c)s') is not null)::int)\n"
          "    || ' ejecutan=' || (select pg_catalog.string_agg(f.n || ':' || coalesce((\n"
          "           select pg_catalog.string_agg(case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end, ','\n"
          "                    order by case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end)\n"
          "           from pg_catalog.pg_proc p, pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a\n"
          "           where p.oid = pg_catalog.to_regprocedure(f.firma) and a.privilege_type = 'EXECUTE'), '-'), ' ' order by f.n)\n"
          "         from (values ('puerta', '%(p)s'), ('nucleo', '%(n)s')) f(n, firma))\n"
          "    || ' registro=' || (select pg_catalog.count(*) from supabase_migrations.schema_migrations where version = '%(v)s');\n") % dict(t=TABLA, p=PUERTA, n=NUCLEO, c=CANDADO, v=VERSION)
V_RETIRADA = 'RETIRADA: no queda la puerta, el núcleo ni la tabla de constancias'
V_CERRADA = 'PUERTA_CERRADA: nadie puede asignar; no se borró nada (las constancias y los vínculos siguen)'
V_RESTOS = 'RESTOS: no quedan la puerta ni el núcleo, pero sí otras piezas de la migración; hay que retirarlas a mano antes de volver a aplicarla'
RETIRA = V_RETIRADA + ' · ESTADO piezas=0 ejecutan=nucleo:- puerta:- registro=0'
def cierra(piezas=4):
    return V_CERRADA + ' · ESTADO piezas=%d ejecutan=nucleo:postgres puerta:postgres registro=1' % piezas
mundos_rev = []
def revertir(n, desc, alteracion, espera):
    mundos_rev.append((n, desc, alteracion, espera))
revertir('v00-control', 'nada alterado y 0 asignaciones (testigo)', "", RETIRA)
revertir('v01-puerta-ya-cerrada', '0 asignaciones, todo entero y la puerta ya cerrada', CERRAR, RETIRA)
revertir('v02-falta-disparador-inmutable', 'una pieza AUSENTE: el disparador «no se modifica» (puerta y núcleo vivos)', "drop trigger %s on %s;" % (T_INM, TABLA), cierra())
revertir('v03-falta-funcion-candado', 'una pieza AUSENTE: la función del candado inmutable, y con ella sus dos disparadores (puerta y núcleo vivos)', "drop function %s cascade;" % CANDADO, cierra(3))
revertir('v04-falta-la-tabla', 'una pieza AUSENTE: la tabla de constancias (puerta y núcleo vivos)', "drop table %s;" % TABLA, cierra(3))
revertir('v05-rol-cualquiera-en-la-puerta', 'un GRANT EXECUTE de más a un rol cualquiera (creado para la prueba) en la puerta',
         ROL + "grant execute on function %s to zz_asignar_prueba;\nselect 'ANTES rol=' || pg_catalog.has_function_privilege('zz_asignar_prueba', '%s', 'EXECUTE');" % (PUERTA, PUERTA),
         'ANTES rol=true · ' + cierra())
revertir('v06-public-en-el-nucleo', 'un GRANT EXECUTE de más a PUBLIC en el núcleo',
         "grant execute on function %s to public;\nselect 'ANTES anon=' || pg_catalog.has_function_privilege('anon', '%s', 'EXECUTE');" % (NUCLEO, NUCLEO),
         'ANTES anon=true · ' + cierra())
revertir('v07-candado-apagado', '0 asignaciones y un disparador de la constancia DESHABILITADO', "alter table %s disable trigger %s;" % (TABLA, T_NB), cierra())
revertir('v08-compuerta-ajena', '0 asignaciones y la compuerta de F3 alterada', COMPUERTA_AJENA, cierra())
revertir('v09-coherencia-apagada', '0 asignaciones y el disparador de coherencia del vínculo deshabilitado', "alter table crm.contrato_cuentas_pago disable trigger trg_contrato_cuenta_pago_coherente;", cierra())
revertir('v10-sin-rls', '0 asignaciones y la tabla sin RLS', "alter table %s disable row level security;" % TABLA, cierra())
revertir('v11-nucleo-alterado', '0 asignaciones y el cuerpo del núcleo alterado', vivo(NUCLEO, [(COMPUERTA, "  -- alterado\n" + COMPUERTA)]), cierra())
revertir('v12-sin-bitacora', '0 asignaciones y la constancia sin bitácora', "drop trigger trg_audit_contrato_cuenta_pago_asignaciones on %s;" % TABLA, cierra())
revertir('v13-tabla-select-anon', '0 asignaciones y un permiso de tabla de más (anon lee)', "grant select on %s to anon;" % TABLA, cierra())
revertir('v14-sin-check', '0 asignaciones y la tabla sin el CHECK del motivo', "alter table %s drop constraint contrato_cuenta_pago_asignaciones_motivo_valido;" % TABLA, cierra())
revertir('v15-una-asignacion', 'todo entero y UNA constancia (escrita a mano como dueño)',
         ("insert into %s (solicitud_id, contrato_id, cliente_id, cuenta_bancaria_id, vinculo_id, motivo, asignado_por)\n"
          "values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'Constancia de prueba', gen_random_uuid());") % TABLA, cierra())
revertir('v20-solo-queda-el-candado', 'solo la función del candado (alguien quitó a mano la puerta, el núcleo y la tabla)',
         "drop function %s;\ndrop function %s;\ndrop table %s;" % (PUERTA, NUCLEO, TABLA),
         V_RESTOS + ' · ESTADO piezas=1 ejecutan=nucleo:- puerta:- registro=1')
revertir('v21-permiso-reconcedido', 'un EXECUTE dado CON GRANT OPTION a un rol, que ese rol volvió a conceder a otro',
         ("create role zz_asignar_a;\ncreate role zz_asignar_b;\ngrant zz_asignar_a to postgres with set true;\n"
          "grant usage on schema crm to zz_asignar_a;\ngrant execute on function %(p)s to zz_asignar_a with grant option;\n"
          "set local role zz_asignar_a;\ngrant execute on function %(p)s to zz_asignar_b;\nreset role;\n"
          "select 'ANTES b=' || pg_catalog.has_function_privilege('zz_asignar_b', '%(p)s', 'EXECUTE');") % dict(p=PUERTA),
         'ANTES b=true · ' + cierra())
def mundo_rev(alteracion, cuerpo_reversa):
    return 'begin;\n' + alteracion + '\n' + cuerpo_reversa + '\n' + VEREDICTO_REV + '\n' + ESTADO + 'rollback;\n'
for n, desc, alteracion, espera in mundos_rev:
    escribe('%s/rev/%s.sql' % (T, n), mundo_rev(alteracion, RC))
escribe('%s/rev/lista.txt' % T, '\n'.join('|'.join([n, desc, espera]) for n, desc, alteracion, espera in mundos_rev) + '\n')
# Mutantes de la reversa frente a esos mismos mundos.
SOLO_SI_ENTERAS = una(RC, "  if v_asignaciones = 0 and v_intactas then", 'la reversa')
A_TODOS = una(RC, "        and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner\n    loop", 'la reversa')
SOLO_AUTH = "        and a.privilege_type = 'EXECUTE' and a.grantee = 'authenticated'::regrole::oid\n    loop"
COMPRUEBA = RC[RC.index("    if exists (\n      select 1 from pg_catalog.pg_proc p\n      where p.oid in ("):RC.index("      raise exception 'REVERSA ASIGNAR: la puerta no quedó cerrada';\n    end if;\n") + len("      raise exception 'REVERSA ASIGNAR: la puerta no quedó cerrada';\n    end if;\n")]
una(RC, COMPRUEBA, 'la reversa')
mutantes_rev = [
    ('w1-retira-sin-mirar-las-piezas', 'retira con 0 asignaciones aunque las piezas no estén enteras', RC.replace(SOLO_SI_ENTERAS, "  if v_asignaciones = 0 then")),
    ('w2-solo-revoca-a-authenticated', 'al cerrar, solo le quita el permiso a authenticated', RC.replace(A_TODOS, SOLO_AUTH)),
    ('w3-solo-authenticated-y-sin-comprobar', 'solo se lo quita a authenticated y no comprueba que nadie más ejecute', RC.replace(A_TODOS, SOLO_AUTH).replace(COMPRUEBA, '')),
]
for mid, mdesc, cuerpo_mutado in mutantes_rev:
    for n, desc, alteracion, espera in mundos_rev:
        if espera != 'MEDIR':
            escribe('%s/rev/%s/%s.sql' % (T, mid, n), mundo_rev(alteracion, cuerpo_mutado))
escribe('%s/rev/mutantes.txt' % T, '\n'.join('|'.join([mid, mdesc]) for mid, mdesc, cuerpo_mutado in mutantes_rev) + '\n')
print('%d mutantes de la migración, %d del preflight, %d mundos para reabrir-puerta (%d mutantes), %d mundos para la reversa (%d mutantes)'
      % (len(lista), len(pre), len(mundos_rea), len(mutantes_rea), len(mundos_rev), len(mutantes_rev)))
PY
if [ "$SALIDA" != "$T" ]; then
  mkdir -p "$SALIDA/mut" "$SALIDA/pre" "$SALIDA/vivo" "$SALIDA/rea" "$SALIDA/rev"
  cp "$T"/mut/* "$SALIDA/mut/" 2>/dev/null; cp "$T"/pre/* "$SALIDA/pre/" 2>/dev/null; cp "$T"/vivo/* "$SALIDA/vivo/" 2>/dev/null
  cp "$T"/rea/*.sql "$T"/rea/*.txt "$SALIDA/rea/" 2>/dev/null; cp "$T"/rev/*.sql "$T"/rev/*.txt "$SALIDA/rev/" 2>/dev/null
fi

# ══ 2 · Lo que debe negarse sin la migración ════════════════════════════════════════════════
tramo "2 · sin la migración: reversa, reabrir y registrar se niegan"
paso "reversa" '^ERROR:  REVERSA ASIGNAR: la migración 20261002005004 no está aplicada; no hay nada que revertir' "$(archivo "$R")"
paso "reabrir-puerta" "^$NO_ENTERAS" "$(archivo "$RE")"
paso "registrar" '^ERROR:  REGISTRO: la migración 20261002005004 no está aplicada; aplícala primero' "$(archivo "$REGISTRAR")"
igual "ninguno de los tres devuelve una fila en un mensaje (el error corta antes del veredicto)" '//' "$(filas "$R")/$(filas "$RE")/$(filas "$REGISTRAR")"
igual "nada cambió en el catálogo" "$(cat "$SALIDA/catalogo-antes.txt")" "$(foto_catalogo)"
# Sentencia a sentencia, tras el error, la fila final sigue saliendo y dice el ESTADO, no lo que hizo la corrida.
sentencias "$R"; medido "veredicto de la reversa sin nada aplicado, sentencia a sentencia" "$(renglones "$T/s.out") (se negó: «$(grep -m1 -o 'REVERSA ASIGNAR:.*' "$T/s.err" | cut -c1-70)»)"
sentencias "$RE"; medido "veredicto de reabrir-puerta sin nada aplicado, sentencia a sentencia" "$(renglones "$T/s.out") (se negó; dice PUERTA_CERRADA aunque no hay puerta)"

# ══ 3 · Migración, prueba y trinquetes ══════════════════════════════════════════════════════
tramo "3 · migración → repetida → prueba → trinquetes"
igual "la migración devuelve su veredicto como FILA (única fila)" 'ASIGNAR_CUENTA_PAGO_OK' "$(filas "$M")"
igual "quedó aplicada, con las huellas de su postflight (candado núcleo puerta)" "sí $(huellas_del_postflight)" "$(aplicada) $(huellas_vivas)"
PIEZAS="$(foto_piezas)"
igual "permisos de ejecutar: puerta y núcleo solo authenticated; candado nadie" "$ACL_RECIEN" "$(permisos)"
foto_catalogo > "$SALIDA/catalogo-con.txt"
paso "lo que la migración añade al catálogo (renglones que cambian)" '^columnas comentarios dependencias disparadores funciones indices relaciones restricciones tipos$' \
  "$(diff "$SALIDA/catalogo-antes.txt" "$SALIDA/catalogo-con.txt" | sed -n 's/^> \([a-z_]*\) .*/\1/p' | sort | tr '\n' ' ' | sed 's/ $//')"
paso "repetida: se NIEGA" '^ERROR:  ASIGNAR PREFLIGHT: ya aplicada \(los objetos existen\); no se sobrescriben' "$(archivo "$M")"
igual "repetida: no devuelve ninguna fila (ni el OK)" '' "$(filas "$M")"
igual "repetida: no tocó las piezas" "$PIEZAS" "$(foto_piezas)"
B0="$(bitacora)"
prueba_paso "prueba (solo asignar)" '^T10 PASS · 0 comprobaciones · NO APLICA'
igual "la prueba no dejó nada escrito (datos, constancias y bitácora)" "$DATOS_SEMBRADO constancias=0 bitacora=$B0" "$(foto_datos) constancias=$(constancias) bitacora=$(bitacora)"
igual "la prueba no tocó las piezas ni dejó su doble de storage.objects" "$PIEZAS sin storage.objects" "$(foto_piezas) $(q "select case when to_regclass('storage.objects') is null then 'sin storage.objects' else 'CON storage.objects' end;")"
trinquetes > "$SALIDA/trinquetes-con.txt"
trinquetes enteros > "$SALIDA/trinquetes-enteros-con.txt"
igual "trinquetes CON la migración: idénticos a los de antes (foto de trinquetes.sql)" "$(cat "$SALIDA/trinquetes-sin.txt")" "$(cat "$SALIDA/trinquetes-con.txt")"
igual "trinquetes CON la migración: idénticos también con los mensajes enteros" "$(cat "$SALIDA/trinquetes-enteros-sin.txt")" "$(cat "$SALIDA/trinquetes-enteros-con.txt")"
# La cabecera de la migración: con ella aplicada, la reversa de F3 ya no puede quitar su candado «no se borra»
# (lo usa la constancia nueva). Se ensaya lo que hace esa reversa, en una transacción que se deshace.
DEP="$(q "begin; drop table crm.cambio_cuenta_avisos; drop table crm.contrato_cuenta_pago_cambios; drop table crm.cuotas_cuenta_pagada;
          drop function private.trg_registro_cuenta_pago_no_borrar(); rollback;")"
paso "el candado «no se borra» de F3 ya no se puede quitar: lo usa la constancia nueva" \
  'cannot drop function private.trg_registro_cuenta_pago_no_borrar\(\) because other objects depend on it.*trg_contrato_cuenta_pago_asignaciones_00_no_borrar on table crm.contrato_cuenta_pago_asignaciones depends' \
  "$(tr '\n' ' ' <<<"$DEP" | cut -c1-330)"
igual "    y el ensayo no borró nada" "sí 3" "$(aplicada) $(q "select count(*) from pg_class where oid in (to_regclass('crm.cambio_cuenta_avisos'), to_regclass('crm.contrato_cuenta_pago_cambios'), to_regclass('crm.cuotas_cuenta_pagada'));")"
igual "el vigía de bitácora no señala la tabla nueva (tablas sin rastro: las mismas que antes)" "$SIN_RASTRO_ANTES/0" "$(q "select count(*) || '/' || count(*) filter (where t.tabla = '$TABLA') from private.tablas_sin_rastro() t;")"

# ══ 4 · Reversa sin asignaciones ════════════════════════════════════════════════════════════
tramo "4 · registrar → reversa sin asignaciones → RETIRADA → reaplicar; de dónde sale el veredicto"
paso "registrar (para ver que la reversa, al retirar, también quita el registro)" '^NOTICE:  REGISTRO: 20261002005004 / crm_asignar_cuenta_pago \(1 sentencia: el archivo entero\)' "$(archivo "$REGISTRAR")"
igual "la versión quedó registrada" '1' "$(registro)"
igual "reversa: veredicto como FILA" "$RETIRADA" "$(filas "$R")"
igual "el catálogo vuelve a ser EXACTAMENTE el de antes de la migración (12 aspectos)" "$(cat "$SALIDA/catalogo-antes.txt")" "$(foto_catalogo)"
igual "los datos no cambiaron" "$DATOS_SEMBRADO" "$(foto_datos)"
igual "tras RETIRADA la versión ya NO está registrada" '0' "$(registro)"
paso "tras RETIRADA registrar se niega («no está aplicada»)" '^ERROR:  REGISTRO: la migración 20261002005004 no está aplicada; aplícala primero' "$(archivo "$REGISTRAR")"
igual "    y la versión sigue sin registrar" '0' "$(registro)"
paso "reversa repetida: se niega" '^ERROR:  REVERSA ASIGNAR: la migración 20261002005004 no está aplicada' "$(archivo "$R")"
# El veredicto de la migración sale del ESTADO REAL (núcleo de esta migración puesto y puerta abierta para
# authenticated), no de un ajuste de sesión. Se mira sentencia a sentencia, que es donde importa: en un solo
# mensaje, si algo falla, no llega a salir ninguna fila.
# (1) Una aplicación que FALLA (el texto real sin su «enable row level security»: el postflight la rechaza).
paso "una aplicación que falla su postflight, en un mensaje: el error y ninguna fila" '^ERROR:  ASIGNAR POSTFLIGHT: la constancia quedó accesible desde la API o sin RLS · $' "$(archivo "$T/mut/17-tabla-sin-rls.entero.sql") · $(filas "$T/mut/17-tabla-sin-rls.entero.sql")"
sentencias "$T/mut/17-tabla-sin-rls.entero.sql"
paso "la misma, sentencia a sentencia: el error" '^ERROR:  ASIGNAR POSTFLIGHT: la constancia quedó accesible desde la API o sin RLS' "$(grep -m1 -o 'ERROR:  ASIGNAR POSTFLIGHT.*' "$T/s.err")"
igual "    su fila de veredicto sale NULL (ningún OK) y nada quedó aplicado" '1 fila: NULL · no' "$(renglones "$T/s.out") · $(aplicada)"
# (2) Una aplicación buena y, en la MISMA sesión, otra vez: la segunda se niega.
cat "$M" "$M" > "$T/dos.sql"; sentencias "$T/dos.sql"
igual "reaplicada (sentencia a sentencia): quedó como la primera vez" "sí $PIEZAS" "$(aplicada) $(foto_piezas)"
paso "la segunda pasada, en la misma sesión, se niega" '^ERROR:  ASIGNAR PREFLIGHT: ya aplicada' "$(grep -m1 -o 'ERROR:  ASIGNAR PREFLIGHT.*' "$T/s.err")"
igual "    veredictos de las dos pasadas: OK y OK (el segundo dice el estado —sigue aplicada y abierta—, no que esa pasada aplicara)" '2 filas: ASIGNAR_CUENTA_PAGO_OK/ASIGNAR_CUENTA_PAGO_OK' "$(renglones "$T/s.out")"
paso "tras reaplicar, registrar" '^NOTICE:  REGISTRO: 20261002005004 / crm_asignar_cuenta_pago' "$(archivo "$REGISTRAR")"
igual "    una sola fila de registro, con el archivo de hoy (versión|nombre|sentencias|md5)" "$VERSION|$NOMBRE|1|$MD5_MIG" \
  "$(q "select version || '|' || name || '|' || cardinality(statements) || '|' || md5(statements[1]) from supabase_migrations.schema_migrations where version = '$VERSION';")"
prueba_paso "prueba tras reaplicar"

# ══ 5 · La reversa exige READ COMMITTED ═════════════════════════════════════════════════════
tramo "5 · la reversa en REPEATABLE READ y SERIALIZABLE"
paso "reversa en REPEATABLE READ: se niega" '^ERROR:  REVERSA ASIGNAR: la transacción debe ir en READ COMMITTED \(va en repeatable read\)' "$(archivo "$R" 'repeatable read')"
paso "reversa en SERIALIZABLE: se niega" '^ERROR:  REVERSA ASIGNAR: la transacción debe ir en READ COMMITTED \(va en serializable\)' "$(archivo "$R" 'serializable')"
sentencias "$R" 'repeatable read'
igual "en REPEATABLE READ, sentencia a sentencia: se niega y la fila final dice lo que hay" 'negada · 1 fila: SIN_CAMBIOS: la puerta sigue abierta' \
  "$(grep -q 'debe ir en READ COMMITTED (va en repeatable read)' "$T/s.err" && echo negada || echo 'sin el error esperado') · $(renglones "$T/s.out")"
igual "no cambió nada: aplicada, abierta, con sus piezas y registrada" "sí abierta $PIEZAS 1" "$(aplicada) $(abierta) $(foto_piezas) $(registro)"

# ══ 6 · Reversa CON una asignación confirmada, y reabrir ════════════════════════════════════
tramo "6 · una asignación confirmada → PUERTA_CERRADA → reabrir frente a mundos alterados → reabrir"
paso "una asignación CONFIRMADA (admin, ASIGNAR-12)" '^OK:\{"banco": "BCP", "moneda": "PEN", "ultimos": "0001", "ya_aplicada": false, "solicitud_id": "[0-9a-f-]+", "numero_contrato": "ASIGNAR-12"\}$' "$(asignar_confirmada "$ADMIN" "$(s 1)" "$(k 12)" "$(x 1)")"
CONSTANCIA="$(constancia_md5)"
VINCULO="$(q "set timezone = 'UTC'; select to_jsonb(l)::text from crm.contrato_cuentas_pago l where l.contrato_id = '$(k 12)';" | grep -v '^SET$')"
DATOS_CON_UNA="$(foto_datos)"
igual "reversa con una asignación: veredicto como FILA" "$CERRADA" "$(filas "$R")"
igual "nada borrado: la tabla, las tres funciones y sus cuerpos siguen" "sí $(huellas_del_postflight)" "$(aplicada) $(huellas_vivas)"
igual "la constancia está intacta" "1 $CONSTANCIA" "$(constancias) $(constancia_md5)"
igual "el vínculo está intacto" "$VINCULO" "$(q "set timezone = 'UTC'; select to_jsonb(l)::text from crm.contrato_cuentas_pago l where l.contrato_id = '$(k 12)';" | grep -v '^SET$')"
igual "los datos no cambiaron con la reversa" "$DATOS_CON_UNA" "$(foto_datos)"
igual "la puerta quedó cerrada: nadie más que el dueño ejecuta (por catálogo)" "cerrada $ACL_CERRADA" "$(abierta) $(permisos)"
igual "PUERTA_CERRADA no toca el registro: la versión sigue anotada" '1' "$(registro)"
paso "con la puerta cerrada no se asigna (el ciclo no llama: lo dice el catálogo)" '^NO SE LLAMA' "$(asignar_confirmada "$ADMIN" "$(s 2)" "$(k 13)" "$(x 2)")"
igual "reversa otra vez: mismo veredicto, nada cambia" "$CERRADA · 1 $CONSTANCIA" "$(filas "$R") · $(constancias) $(constancia_md5)"
paso "migración con la puerta cerrada, en un mensaje: se niega (ya aplicada) y no da ninguna fila" '^ERROR:  ASIGNAR PREFLIGHT: ya aplicada \(los objetos existen\); no se sobrescriben · $' "$(archivo "$M") · $(filas "$M")"
sentencias "$M"
igual "migración con la puerta cerrada, sentencia a sentencia: se niega y su fila de veredicto sale NULL" 'ya aplicada · 1 fila: NULL' \
  "$(grep -q 'ASIGNAR PREFLIGHT: ya aplicada' "$T/s.err" && echo 'ya aplicada' || echo 'sin el error esperado') · $(renglones "$T/s.out")"
# reabrir-puerta frente a un mundo alterado, con la puerta cerrada. Cada alteración y reabrir-puerta van en UNA
# transacción que se deshace: debe negarse siempre que las piezas no estén ENTERAS como las dejó la migración.
while IFS='|' read -r id desc espera <&3; do
  r=$(mutado "$T/rea/$id.sql")
  case "$espera" in
    REABRIR) paso "  reabrir con $desc" '^MUTANTE_SIN_ERROR$' "$r" ;;
    MEDIR)   medido "reabrir con $desc" "$([ "$r" = "MUTANTE_SIN_ERROR" ] && echo 'REABRE (las «piezas enteras» no lo miran)' || echo "$r")" ;;
    *)       paso "  reabrir con $desc" "^$NO_ENTERAS" "$r" ;;
  esac
done 3< "$T/rea/lista.txt"
igual "los ensayos se deshicieron: puerta cerrada, piezas de la migración, constancia y registro intactos" \
  "cerrada $(huellas_del_postflight) $ACL_CERRADA 1 $CONSTANCIA 1" "$(abierta) $(huellas_vivas) $(permisos) $(constancias) $(constancia_md5) $(registro)"
# El camino bueno: con las piezas intactas, reabre.
igual "reabrir-puerta con las piezas intactas: veredicto como FILA" 'PUERTA_REABIERTA' "$(filas "$RE")"
igual "reabierta: la ACL queda EXACTAMENTE como recién aplicada" "abierta $ACL_RECIEN" "$(abierta) $(permisos)"
igual "reabierta: las piezas enteras son las de recién aplicada (definición, ACL literal, disparadores, reglas…)" "$PIEZAS" "$(foto_piezas)"
paso "tras reabrir se vuelve a asignar (superadmin, ASIGNAR-13): cerrar → reabrir → asignar funciona" '^OK:\{.*"ya_aplicada": false.*"numero_contrato": "ASIGNAR-13"\}$' "$(asignar_confirmada "$SUPER" "$(s 2)" "$(k 13)" "$(x 2)")"
igual "reabrir otra vez con la puerta ya abierta: no cambia nada" "PUERTA_REABIERTA $PIEZAS" "$(filas "$RE") $(foto_piezas)"
igual "dos constancias y sus dos vínculos" "2 $(x 1)|$ADMIN $(x 2)|$SUPER" "$(constancias) $(vinculo "$(k 12)") $(vinculo "$(k 13)")"
# Dejar el banco limpio (ver la cabecera).
paso "limpieza del banco (réplica): constancias, vínculos y restos fuera" '^restos limpios$' "$(limpiar_restos)"
igual "banco limpio: los datos son los de la siembra y no quedan constancias" "$DATOS_SEMBRADO 0" "$(foto_datos) $(constancias)"
igual "ya sin asignaciones, la reversa RETIRA: catálogo de antes y la versión deja de estar registrada" "$RETIRADA · igual · 0" \
  "$(filas "$R") · $([ "$(foto_catalogo)" = "$(cat "$SALIDA/catalogo-antes.txt")" ] && echo igual || echo distinto) · $(registro)"
igual "se reaplica para seguir" "ASIGNAR_CUENTA_PAGO_OK $PIEZAS" "$(filas "$M") $(foto_piezas)"
paso "    y se registra" '^NOTICE:  REGISTRO: 20261002005004 / crm_asignar_cuenta_pago' "$(archivo "$REGISTRAR")"

# ══ 7 · La reversa frente a mundos alterados; piezas cambiadas de verdad ════════════════════
tramo "7 · la reversa frente a mundos alterados; piezas cambiadas de verdad con cero asignaciones"
igual "punto de partida: aplicada, abierta, registrada, sin constancias" "sí abierta 1 0" "$(aplicada) $(abierta) $(registro) $(constancias)"
# Cada mundo: la alteración + la reversa + su veredicto + el estado en que lo dejaría, en UNA transacción que se deshace.
while IFS='|' read -r id desc espera <&3; do
  r=$(mundo "$T/rev/$id.sql")
  if [ "$espera" = "MEDIR" ]; then medido "reversa con $desc" "$r"; else igual "  reversa con $desc" "$espera" "$r"; fi
done 3< "$T/rev/lista.txt"
igual "los mundos se deshicieron: aplicada, abierta, intacta, registrada y sin el rol de prueba" "sí abierta $PIEZAS 1 0" \
  "$(aplicada) $(abierta) $(foto_piezas) $(registro) $(q "select count(*) from pg_roles where rolname like 'zz\_asignar\_%'")"
# Y de verdad (confirmado): piezas cambiadas con cero asignaciones.
guardar "$NUCLEO" nucleo-original; guardar "$CANDADO" candado-original
q "do \$m\$ declare d text := pg_get_functiondef('$NUCLEO'::regprocedure); begin execute replace(d, 'declare' || chr(10) || '  v_actor uuid', 'declare' || chr(10) || '  -- alterado' || chr(10) || '  v_actor uuid'); end \$m\$;" >/dev/null
paso "testigo: el núcleo vivo ya no tiene la huella de la migración" '^distinta$' "$([ "$(huellas_vivas)" = "$(huellas_del_postflight)" ] && echo igual || echo distinta)"
paso "registrar con el núcleo cambiado: se niega" '^ERROR:  REGISTRO: la migración 20261002005004 no está aplicada' "$(archivo "$REGISTRAR")"
igual "reversa con el NÚCLEO cambiado y 0 asignaciones: cierra, no borra" "$CERRADA" "$(filas "$R")"
igual "    nada borrado, la puerta cerrada y la versión sigue registrada" "sí cerrada $ACL_CERRADA 1" "$(aplicada) $(abierta) $(permisos) $(registro)"
paso "reabrir con el núcleo cambiado: se niega" "^$NO_ENTERAS" "$(archivo "$RE")"
sentencias "$RE"
igual "    sentencia a sentencia: se niega y la fila final dice lo que hay" 'negada · 1 fila: PUERTA_CERRADA: no se reabrió' \
  "$(grep -q 'las piezas no están enteras' "$T/s.err" && echo negada || echo 'sin el error esperado') · $(renglones "$T/s.out")"
reponer nucleo-original
igual "con el núcleo repuesto, reabrir reabre y todo es como recién aplicada" "PUERTA_REABIERTA abierta $PIEZAS" "$(filas "$RE") $(abierta) $(foto_piezas)"
q "do \$m\$ declare d text := pg_get_functiondef('$CANDADO'::regprocedure); begin execute replace(d, 'no se modifica ni se vacía', 'no se modifica ni se vacía.'); end \$m\$;" >/dev/null
igual "reversa con el CANDADO cambiado y 0 asignaciones: cierra, no borra" "$CERRADA · sí" "$(filas "$R") · $(aplicada)"
paso "reabrir con el candado cambiado: se niega" "^$NO_ENTERAS" "$(archivo "$RE")"
reponer candado-original
igual "con el candado repuesto, reabrir reabre y todo es como recién aplicada" "PUERTA_REABIERTA abierta $PIEZAS" "$(filas "$RE") $(abierta) $(foto_piezas)"
q "alter table $TABLA disable trigger trg_contrato_cuenta_pago_asignaciones_00_inmutable;" >/dev/null
igual "reversa con un candado DESHABILITADO y 0 asignaciones: cierra, no borra" "$CERRADA · sí" "$(filas "$R") · $(aplicada)"
paso "reabrir con el candado deshabilitado: se niega" "^$NO_ENTERAS" "$(archivo "$RE")"
q "alter table $TABLA enable trigger trg_contrato_cuenta_pago_asignaciones_00_inmutable;" >/dev/null
igual "con el candado habilitado otra vez, reabrir reabre y todo es como recién aplicada" "PUERTA_REABIERTA abierta $PIEZAS" "$(filas "$RE") $(abierta) $(foto_piezas)"
prueba_paso "prueba tras cerrar, reponer y reabrir"

# ══ 8 · Concurrencia con dos sesiones reales ════════════════════════════════════════════════
tramo "8 · concurrencia (prueba-concurrencia.sh entera; los casos R dicen NO APLICA sin la otra migración)"
BANCO_CONTENEDOR="$C" bash "$CONC" > "$SALIDA/concurrencia.txt" 2>&1
grep -E '^[A-Z][0-9]?[a-z]? ·|✗|△' "$SALIDA/concurrencia.txt" | cut -c1-330 | sed 's/^/    /'
paso "concurrencia: todos los casos" '^CONCURRENCIA asignar_cuenta_pago: [0-9]+ OK, 0 FALLAS$' "$(tail -1 "$SALIDA/concurrencia.txt")"
T_ASERT[$IT]=$((${T_ASERT[$IT]} + $(sed -n 's/^CONCURRENCIA asignar_cuenta_pago: \([0-9]*\) OK.*/\1/p' "$SALIDA/concurrencia.txt" | tail -1)))
MEDIDOS=$((MEDIDOS + $(grep -c '△ MEDIDO' "$SALIDA/concurrencia.txt")))
igual "tras la concurrencia: aplicada, abierta, piezas intactas y el mundo como se sembró" "sí abierta $PIEZAS $DATOS_SEMBRADO 0" "$(aplicada) $(abierta) $(foto_piezas) $(foto_datos) $(constancias)"
igual "    el caso E4 retiró la migración DE VERDAD: su versión dejó de estar registrada (la prueba la reaplica sin registrar)" '0' "$(registro)"
paso "    se vuelve a registrar" '^NOTICE:  REGISTRO: 20261002005004 / crm_asignar_cuenta_pago' "$(archivo "$REGISTRAR")"

# ══ 9 · Con la otra migración ═══════════════════════════════════════════════════════════════
tramo "9 · con la otra migración (20261001233019), en los dos órdenes; la carga frente a «Asignar»"
# Las dos carreras REALES entre una asignación y la carga de la otra migración (que toma «lock table
# crm.cuentas_bancarias in exclusive mode»), sobre el MISMO contrato: REZAGO-03, que es «una_cuenta» y
# por eso lo quieren las dos (la carga lo vincularía sola; la administradora le asigna su única cuenta).
REZAGO_03='c9ed0000-0000-4000-8000-000000000003'; CUENTA_04='c9ec0000-0000-4000-8000-000000000004'
# Carrera 1 · la asignación va primero (sin confirmar) y entonces se aplica la otra migración.
docker exec -i -e PGPASSWORD=postgres "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "begin;
  set local lock_timeout = '8s'; set local statement_timeout = '8s';
  select set_config('request.jwt.claim.sub', '$ADMIN', true), set_config('request.jwt.claim.role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', '$ADMIN', 'role', 'authenticated')::text, true);
  set local session authorization authenticator; set local role authenticated;
  select 'EN_VUELO ' || crm.asignar_cuenta_pago_contrato('$(s 3)', '$REZAGO_03', '$CUENTA_04', '$MOTIVO')::text;
  select pg_sleep(3) /* vuelo-tramo9 */; commit;" > "$T/vuelo9.out" 2>&1 </dev/null &
for _ in $(seq 1 100); do [ "$(q "select count(*) from pg_stat_activity where query like '%vuelo-tramo9%' and wait_event = 'PgSleep' and pid <> pg_backend_pid()")" = "1" ] && break; sleep 0.1; done
t0=$(date +%s)
paso "carrera 1 · asignación en vuelo sobre REZAGO-03 y se aplica la otra: su carga vincula solo los otros tres" '"contratos": \["REZAGO-04", "REZAGO-05", "REZAGO-06"\], "vinculados": 3\}$' "$(archivo "$OTRA")"
t1=$(date +%s); wait
paso "    la otra ESPERÓ a la asignación (≥ 2 s); REZAGO-03 quedó con la cuenta ASIGNADA, a nombre de la admin, y su constancia" \
  '^sí · EN_VUELO \{.*"ya_aplicada": false.*"numero_contrato": "REZAGO-03"\} · '"$CUENTA_04"'\|'"$ADMIN"' · 1$' \
  "$([ $((t1 - t0)) -ge 2 ] && echo sí || echo "no ($((t1 - t0)) s)") · $(grep -o 'EN_VUELO .*' "$T/vuelo9.out") · $(vinculo "$REZAGO_03") · $(constancias)"
paso "    vuelta atrás: la reversa de la otra borra sus 3 vínculos y se limpia la asignación (banco)" '^NOTICE:  REVERSA: 3 vínculos de la carga borrados · restos limpios$' "$(aviso "$OTRA_REVERSA" 'REVERSA:') · $(limpiar_restos)"
igual "    el mundo vuelve a ser el sembrado, sin la otra y sin constancias" "$DATOS_SEMBRADO 0 no" "$(foto_datos) $(constancias) $(otra_aplicada)"
# Carrera 2 · la otra migración va primero (su carga tiene el candado EXCLUSIVE y tarda 3 s) y llega la asignación.
python3 - "$OTRA" "$T/otra-lenta.sql" <<'PY'
import io, sys
t = io.open(sys.argv[1], encoding='utf-8').read()
a = "\nlock table crm.cuentas_bancarias in exclusive mode;\n"
assert t.count(a) == 1, 'la otra migración ya no toma su candado como se esperaba'
io.open(sys.argv[2], 'w', encoding='utf-8').write(t.replace(a, a + "select pg_sleep(3);\n"))
PY
lanzar "$T/otra-lenta" postgres "$(cat "$T/otra-lenta.sql")" &
for _ in $(seq 1 100); do [ "$(q "select count(*) from pg_locks l where l.relation = 'crm.cuentas_bancarias'::regclass and l.mode = 'ExclusiveLock' and l.granted")" = "1" ] && break; sleep 0.1; done
r="$(asignar_confirmada "$ADMIN" "$(s 4)" "$REZAGO_03" "$CUENTA_04" ms)"; wait
paso "carrera 2 · la carga en vuelo y llega la asignación a REZAGO-03: espera y recibe «ya tiene cuenta de pago»" \
  '^ERR:22023:El contrato REZAGO-03 ya tiene cuenta de pago; para cambiarla usa «Cambiar cuenta de pago» ESPERA_MS [0-9]+$' "$r"
paso "    la asignación ESPERÓ a la carga (≥ 1,5 s) y la otra terminó con sus 4 vínculos" '^sí · .*"contratos": \["REZAGO-03", "REZAGO-04", "REZAGO-05", "REZAGO-06"\], "vinculados": 4\}$' \
  "$([ "$(sed -n 's/.* ESPERA_MS \([0-9]*\)$/\1/p' <<<"$r")" -ge 1500 ] 2>/dev/null && echo sí || echo no) · $(canales "$T/otra-lenta")"
igual "    REZAGO-03 quedó con el vínculo de la CARGA (sin autor) y no hay ninguna constancia" "$CUENTA_04|(null) 0" "$(vinculo "$REZAGO_03") $(constancias)"
igual "las piezas de asignar no cambiaron al aplicar la otra" "sí abierta $PIEZAS" "$(aplicada) $(abierta) $(foto_piezas)"
prueba_paso "prueba con las DOS migraciones (orden asignar → otra)" '^T10 PASS · [1-9][0-9]* comprobaciones · con las dos migraciones \(la carga de la otra tiene 4 vínculos vivos\)'
medido "con las dos migraciones" "$(grep -E '^T10 ' <<<"$SALIDA_PRUEBA" | grep -o 'contrato cerrado.*' | cut -c1-330)"
paso "la otra, repetida, no hace nada (idempotente)" '"contratos": \[\], "vinculados": 0\}$' "$(archivo "$OTRA")"
DATOS_CON_LA_OTRA="$(foto_datos)"
# Dos sesiones con la otra puesta: A, B2 y C1 (el pago usa el bloqueo nuevo) y la carga suelta
# (vincular-rezago.sql) frente a «Asignar» en los dos órdenes (R1, R2) y con el lock_timeout de la carga (R3).
BANCO_CONTENEDOR="$C" SOLO="A B2 C1 R1 R2 R3" bash "$CONC" > "$SALIDA/concurrencia-con-la-otra.txt" 2>&1
grep -E '^R[0-9] ·|✗|△' "$SALIDA/concurrencia-con-la-otra.txt" | cut -c1-330 | sed 's/^/    /'
paso "concurrencia con la otra puesta (A, B2, C1 y la carga frente a «Asignar»: R1, R2, R3)" '^CONCURRENCIA asignar_cuenta_pago: [0-9]+ OK, 0 FALLAS$' "$(tail -1 "$SALIDA/concurrencia-con-la-otra.txt")"
paso "    los tres casos de la carga corrieron (no «NO APLICA»)" '^3 0$' "$(grep -c '^R[123] ·' "$SALIDA/concurrencia-con-la-otra.txt" | tr -d ' ') $(grep -c 'NO APLICA' "$SALIDA/concurrencia-con-la-otra.txt" | tr -d ' ')"
T_ASERT[$IT]=$((${T_ASERT[$IT]} + $(sed -n 's/^CONCURRENCIA asignar_cuenta_pago: \([0-9]*\) OK.*/\1/p' "$SALIDA/concurrencia-con-la-otra.txt" | tail -1)))
# Mutante: sin el FOR SHARE de la cuenta, la asignación escribe el vínculo ANTES de esperar a la carga, y la
# carga espera a ese vínculo: interbloqueo de verdad (40P01). Lo caza R1.
conc_mutante "núcleo sin FOR SHARE de la cuenta, frente a la carga: interbloqueo" "R1" "$T/vivo/c1-sin-for-share-cuenta.sql" ""
igual "tras la concurrencia con la otra: asignar intacta y el mundo como antes de esos casos" "sí abierta $PIEZAS $DATOS_CON_LA_OTRA 0" "$(aplicada) $(abierta) $(foto_piezas) $(foto_datos) $(constancias)"
# Orden otra → asignar: se retira asignar con la otra puesta y se vuelve a aplicar.
igual "con la otra puesta, la reversa de asignar retira" "$RETIRADA" "$(filas "$R")"
trinquetes > "$SALIDA/trinquetes-solo-la-otra.txt"; trinquetes enteros > "$SALIDA/trinquetes-enteros-solo-la-otra.txt"
igual "otra → asignar: la migración se aplica sobre la otra" "ASIGNAR_CUENTA_PAGO_OK $PIEZAS" "$(filas "$M") $(foto_piezas)"
trinquetes > "$SALIDA/trinquetes-las-dos.txt"; trinquetes enteros > "$SALIDA/trinquetes-enteros-las-dos.txt"
igual "trinquetes con la otra y SIN asignar = con las dos (foto de trinquetes.sql)" "$(cat "$SALIDA/trinquetes-solo-la-otra.txt")" "$(cat "$SALIDA/trinquetes-las-dos.txt")"
igual "    y con los mensajes enteros" "$(cat "$SALIDA/trinquetes-enteros-solo-la-otra.txt")" "$(cat "$SALIDA/trinquetes-enteros-las-dos.txt")"
prueba_paso "prueba con las DOS migraciones (orden otra → asignar)" '^T10 PASS · [1-9][0-9]* comprobaciones · con las dos migraciones'
# Vuelta: se revierte la otra con su reversa documentada y asignar sigue funcionando sola.
paso "reversa de la otra (la documentada en su migración)" '^NOTICE:  REVERSA: 4 vínculos de la carga borrados' "$(aviso "$OTRA_REVERSA" 'REVERSA:')"
igual "sin la otra, asignar sigue igual y el mundo es el sembrado" "sí abierta $PIEZAS no $DATOS_SEMBRADO" "$(aplicada) $(abierta) $(foto_piezas) $(otra_aplicada) $(foto_datos)"
prueba_paso "prueba otra vez sola" '^T10 PASS · 0 comprobaciones · NO APLICA'

# ══ 10 · Mutantes de la migración ═══════════════════════════════════════════════════════════
tramo "10 · mutantes de la MIGRACIÓN (texto real alterado; debe pararlos el pre/postflight)"
igual "punto de partida de los mutantes: aplicada, abierta, intacta y sin constancias" "sí abierta $PIEZAS 0" "$(aplicada) $(abierta) $(foto_piezas) $(constancias)"
while IFS='|' read -r id desc ea eb nota <&3; do
  [ -f "$T/mut/$id.mig.sql" ] || continue
  r=$(mutado "$T/mut/$id.mig.sql")
  if [ "$ea" = "MUTANTE_SIN_ERROR" ]; then
    paso "  $id" '^MUTANTE_SIN_ERROR$' "$r"
    medido "  $id" "PASA el postflight: $desc"
  else
    paso "  $id" "^$ea" "$r"
  fi
done 3< "$T/mut/lista.txt"
igual "los mutantes no dejaron nada: mismas piezas, mismos datos" "sí abierta $PIEZAS $DATOS_SEMBRADO" "$(aplicada) $(abierta) $(foto_piezas) $(foto_datos)"

# ══ 11 · Los mutantes en la prueba ══════════════════════════════════════════════════════════
tramo "11 · los mismos mutantes inyectados en la prueba: qué tramo caza cada uno"
while IFS='|' read -r id desc ea eb nota <&3; do
  [ -f "$T/mut/$id.iny.sql" ] || continue
  correr_prueba "$T/mut/$id.iny.sql"
  [ "$SALIDA" = "$T" ] || printf '%s\n' "$SALIDA_PRUEBA" > "$SALIDA/prueba-$id.txt"
  if [ "$eb" = '^TC$' ]; then
    paso "  $id" '^TC$' "${CAIDOS:-ninguno · $VEREDICTO}"
    echo "      (sobrevive a la prueba secuencial A SABIENDAS: ahí solo lo delata la huella en TC; $nota)"
  else
    paso "  $id" "(^| )$eb( |$)" "${CAIDOS:-ninguno · $VEREDICTO}"
    grep -E "^$eb FAIL" <<<"$SALIDA_PRUEBA" | sed 's/^\(T[0-9C]*\) FAIL · [0-9]* comprobaciones · /\1: /' | cut -c1-330 | sed 's/^/      /'
  fi
done 3< "$T/mut/lista.txt"
# El vigía de bitácora también ve la tabla sin su auditor: la foto de trinquetes CAMBIA.
trinquetes '' "drop trigger trg_audit_contrato_cuenta_pago_asignaciones on $TABLA;" > "$SALIDA/trinquetes-sin-bitacora.txt"
paso "18-tabla-sin-bitacora: además cambia la foto de trinquetes (assert_auditoria pasa de $SIN_RASTRO_ANTES a $((SIN_RASTRO_ANTES + 1)) tablas)" "AUDITORÍA ROTA: $((SIN_RASTRO_ANTES + 1)) tabla" \
  "$(diff "$SALIDA/trinquetes-con.txt" "$SALIDA/trinquetes-sin-bitacora.txt" | grep '^>' | cut -c1-150)"
igual "los mutantes inyectados se deshicieron: mismas piezas, mismos datos" "sí abierta $PIEZAS $DATOS_SEMBRADO" "$(aplicada) $(abierta) $(foto_piezas) $(foto_datos)"

# ══ 12 · Mutantes de concurrencia ═══════════════════════════════════════════════════════════
tramo "12 · mutantes de CONCURRENCIA (el núcleo y la reversa alterados de verdad)"
conc_mutante "núcleo sin capturar la violación de unicidad" "A" "$T/vivo/c0-sin-capturar-unicidad.sql" ""
conc_mutante "núcleo sin el candado consultivo de la solicitud" "A3 A4" "$T/vivo/c3-sin-candado-solicitud.sql" ""
conc_mutante "núcleo sin FOR SHARE de la cuenta" "D" "$T/vivo/c1-sin-for-share-cuenta.sql" ""
conc_mutante "núcleo sin FOR SHARE del contrato" "F" "$T/vivo/c2-sin-for-share-contrato.sql" ""
# Sin la guarda, con DOS sesiones se reproduce lo que evita: la solicitud repetida que en REPEATABLE READ dice
# «ya tiene cuenta de pago» en vez de ya_aplicada (G3) y la administradora revocada que aun así asigna (G4).
conc_mutante "núcleo SIN la guarda de aislamiento" "G1 G2 G3 G4" "$T/vivo/g1-sin-guarda-de-aislamiento.sql" ""
conc_mutante "núcleo con la guarda que deja pasar REPEATABLE READ" "G1 G3 G4" "$T/vivo/g2-guarda-admite-repeatable-read.sql" ""
conc_mutante "núcleo con la guarda DESPUÉS de la compuerta" "G1" "$T/vivo/g3-guarda-despues-de-la-compuerta.sql" ""
conc_mutante "reversa sin el candado de la tabla" "E1" "" "$T/vivo/reversa-sin-candado.sql"
conc_mutante "reversa sin exigir READ COMMITTED" "E3" "" "$T/vivo/reversa-sin-aislamiento.sql"
igual "tras los mutantes de concurrencia: aplicada, abierta, intacta y el mundo como se sembró" "sí abierta $PIEZAS $DATOS_SEMBRADO 0" "$(aplicada) $(abierta) $(foto_piezas) $(foto_datos) $(constancias)"

# ══ 13 · Mutantes del preflight ═════════════════════════════════════════════════════════════
tramo "13 · mutantes del PREFLIGHT (el mundo alterado; la migración debe negarse)"
while IFS='|' read -r id desc espera <&3; do
  paso "  $id · $desc" "^$espera" "$(mutado "$T/pre/$id.sql")"
done 3< "$T/pre/lista.txt"
igual "los mundos alterados se deshicieron: mismo catálogo que recién aplicada" "$(cat "$SALIDA/catalogo-con.txt")" "$(foto_catalogo)"

# ══ 14 · Mutantes de los derivados ══════════════════════════════════════════════════════════
tramo "14 · mutantes de los DERIVADOS (reabrir-puerta con una cláusula menos; la reversa alterada)"
# conc_mutante pudo dejar la versión sin registrar (si tuvo que reaplicar): los mundos de la reversa parten de registrada.
[ "$(registro)" = "1" ] || archivo "$REGISTRAR" >/dev/null
igual "punto de partida: aplicada, abierta, intacta, registrada y sin constancias" "sí abierta $PIEZAS 1 0" "$(aplicada) $(abierta) $(foto_piezas) $(registro) $(constancias)"
# reabrir-puerta: cada mutante le quita UNA cláusula a «piezas enteras». Frente a todos los mundos alterados,
# debe reabrir exactamente en los que esa cláusula vigilaba (y seguir negándose en los demás).
while IFS='|' read -r mid mdesc mesperados <&4; do
  volcados=''
  while IFS='|' read -r id desc espera <&3; do
    [ "$espera" = "NEGAR" ] || continue
    [ "$(mutado "$T/rea/$mid/$id.sql")" = "MUTANTE_SIN_ERROR" ] && volcados="$volcados $id"
  done 3< "$T/rea/lista.txt"
  igual "  reabrir $mid · $mdesc: reabre SOLO en sus mundos" "$mesperados" "${volcados# }"
done 4< "$T/rea/mutantes.txt"
# La reversa alterada frente a sus mundos: cuántos lo delatan (resultado distinto del que da la reversa de verdad).
while IFS='|' read -r mid mdesc <&4; do
  delatan=''; n=0
  while IFS='|' read -r id desc espera <&3; do
    [ "$espera" = "MEDIR" ] && continue
    r=$(mundo "$T/rev/$mid/$id.sql")
    if [ "$r" != "$espera" ]; then n=$((n + 1)); delatan="$delatan
      $id → $(cut -c1-170 <<<"$r")"; fi
  done 3< "$T/rev/lista.txt"
  paso "  reversa $mid · $mdesc" '^[1-9][0-9]* mundos lo delatan$' "$n mundos lo delatan"
  [ -z "$delatan" ] || printf '%s\n' "${delatan#?}"
done 4< "$T/rev/mutantes.txt"
igual "los mutantes de los derivados se deshicieron: aplicada, abierta, intacta, registrada y el mundo sembrado" "sí abierta $PIEZAS 1 $DATOS_SEMBRADO 0" \
  "$(aplicada) $(abierta) $(foto_piezas) $(registro) $(foto_datos) $(q "select count(*) from pg_roles where rolname like 'zz\_asignar\_%'")"

# ══ 15 · Estado final ═══════════════════════════════════════════════════════════════════════
tramo "15 · estado final: limpio, aplicada y registrada"
paso "restos fuera" '^restos limpios$' "$(limpiar_restos)"
igual "la migración está aplicada, abierta e intacta; la otra no" "sí abierta $PIEZAS no" "$(aplicada) $(abierta) $(foto_piezas) $(otra_aplicada)"
paso "registrar #1" '^NOTICE:  REGISTRO: 20261002005004 / crm_asignar_cuenta_pago \(1 sentencia: el archivo entero\)' "$(archivo "$REGISTRAR")"
paso "registrar #2 (idempotente)" '^NOTICE:  REGISTRO: 20261002005004 / crm_asignar_cuenta_pago \(1 sentencia: el archivo entero\)' "$(archivo "$REGISTRAR")"
igual "una sola fila de registro, con el archivo entero de hoy (versión|nombre|sentencias|md5)" "$VERSION|$NOMBRE|1|$MD5_MIG" \
  "$(q "select version || '|' || name || '|' || cardinality(statements) || '|' || md5(statements[1]) from supabase_migrations.schema_migrations where version = '$VERSION';")"
igual "el registro no cambia el catálogo de crm, private y public" "$(cat "$SALIDA/catalogo-con.txt")" "$(foto_catalogo)"
# La reversa, al retirar, borra también el registro de la versión; después todo se puede rehacer.
igual "reversa con la versión registrada: retira y borra su registro" "$RETIRADA · 0" "$(filas "$R") · $(registro)"
paso "    registrar sin las piezas: se niega («no está aplicada»)" '^ERROR:  REGISTRO: la migración 20261002005004 no está aplicada' "$(archivo "$REGISTRAR")"
igual "    y la versión sigue sin registrar" '0' "$(registro)"
igual "    se reaplica y queda como la primera vez" "ASIGNAR_CUENTA_PAGO_OK $PIEZAS" "$(filas "$M") $(foto_piezas)"
paso "    registrar tras reaplicar" '^NOTICE:  REGISTRO: 20261002005004 / crm_asignar_cuenta_pago' "$(archivo "$REGISTRAR")"
igual "    una sola fila de registro, con el archivo de hoy" "$VERSION|$NOMBRE|1|$MD5_MIG" \
  "$(q "select version || '|' || name || '|' || cardinality(statements) || '|' || md5(statements[1]) from supabase_migrations.schema_migrations where version = '$VERSION';")"
prueba_paso "prueba final" '^T10 PASS · 0 comprobaciones · NO APLICA'
igual "el mundo es el sembrado, sin constancias, sin sellos y sin storage.objects" "$DATOS_SEMBRADO 0 sin storage.objects" \
  "$(foto_datos) $(constancias) $(q "select case when to_regclass('storage.objects') is null then 'sin storage.objects' else 'CON storage.objects' end;")"
igual "trinquetes al final: los de antes de la migración" "$(cat "$SALIDA/trinquetes-sin.txt")" "$(trinquetes)"
echo "    estado final del banco: asignar=$(aplicada) puerta=$(abierta) la otra=$(otra_aplicada) constancias=$(constancias) registro=$(registro) bitácora=$(bitacora) filas"

# ── Resumen ──────────────────────────────────────────────────────────────────────────────────
echo "── resumen por tramo"
printf '%-104s %5s %5s %14s\n' "tramo" "✓" "✗" "comprobaciones"
i=0; SUMA_OK=0; SUMA_ASERT=0
while [ $i -le $IT ]; do
  printf '%-104s %5s %5s %14s  %s\n' "${TRAMOS[$i]}" "${T_OK[$i]}" "${T_KO[$i]}" "${T_ASERT[$i]}" "$([ "${T_KO[$i]}" -eq 0 ] && echo PASS || echo FAIL)"
  SUMA_OK=$((SUMA_OK + ${T_OK[$i]})); SUMA_ASERT=$((SUMA_ASERT + ${T_ASERT[$i]}))
  i=$((i + 1))
done
echo "total: $SUMA_OK ✓ · $FALLOS ✗ · $MEDIDOS △ medidos · $SUMA_ASERT comprobaciones dentro de las pruebas"
if [ "$FALLOS" -eq 0 ]; then echo "FIN ciclo asignar cuenta de pago: TODO ✓"; else echo "FIN ciclo asignar cuenta de pago: $FALLOS ✗"; fi
[ "$FALLOS" -eq 0 ]
