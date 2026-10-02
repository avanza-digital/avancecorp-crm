#!/usr/bin/env bash
# Ciclo completo de 20261002005004_crm_asignar_cuenta_pago en el BANCO Docker propio.
# Nunca contra producción: todo va por `docker exec` contra el contenedor del banco. No edita ningún
# archivo del repositorio: los mutantes y las copias alteradas viven en un directorio temporal.
#
#   BANCO_CONTENEDOR=avancecorp-cuentas-asignar-20261001 bash supabase/scripts/cuentas-pago-asignar/ciclo.sh
#
# ASIGNAR_SALIDA=<carpeta> conserva ahí las fotos (catálogo, trinquetes), los mutantes y la salida de
# cada corrida. El banco se monta antes con supabase/scripts/potencial-lead/banco/montar-banco.sh
# (esquema de producción, sin datos). Cada paso se compara con lo que se espera (✓ / ✗); «△ MEDIDO»
# son comportamientos que no forman parte del contrato y se anotan sin contar. Al final hay una tabla
# por tramo y el ciclo sale con 1 si hubo algún ✗. La migración, la reversa, reabrir-puerta y el
# registrador van en UN mensaje y como postgres, igual que en producción (`supabase db query --file`);
# la prueba va sentencia a sentencia y como supabase_admin (ver su cabecera).
#
# Tramos:
#    0 · punto de partida: restos fuera, las dos migraciones fuera, registrador al día, archivos sin invisibles
#    1 · siembras (común y extra, dos veces cada una) → fotos SIN la migración: catálogo, datos y trinquetes
#    2 · lo que debe NEGARSE sin la migración: reversa, reabrir-puerta y registrar
#    3 · migración (veredicto ASIGNAR_CUENTA_PAGO_OK como FILA) → otra vez (se niega, sin fila) → prueba →
#        nada escrito → trinquetes CON la migración: idénticos
#    4 · reversa SIN asignaciones → RETIRADA y el catálogo vuelve a ser el de antes → repetida (se niega) →
#        reaplicar (y qué dice el veredicto en una sesión reutilizada)
#    5 · la reversa en REPEATABLE READ y SERIALIZABLE: se niega
#    6 · una asignación CONFIRMADA → reversa: PUERTA_CERRADA, nada borrado → repetida → migración (ya aplicada) →
#        reabrir-puerta frente a piezas alteradas → reabrir → otra asignación → limpieza → RETIRADA
#    7 · piezas cambiadas con CERO asignaciones: la reversa cierra en vez de borrar; reabrir se niega hasta reponerlas
#    8 · concurrencia con dos sesiones reales (prueba-concurrencia.sh entera)
#    9 · con la otra migración (20261001233019): las dos carreras REALES entre una asignación y su carga sobre
#        el mismo contrato; asignar → otra → prueba con T10; y al revés, otra → asignar → prueba; trinquetes
#        idénticos; reversa de la otra → prueba
#   10 · mutantes de la MIGRACIÓN: su texto real alterado; debe pararlos el pre/postflight
#   11 · los mismos mutantes inyectados en la prueba: dice QUÉ TRAMO caza cada uno
#   12 · mutantes de CONCURRENCIA: el núcleo y la reversa alterados de verdad; los caza prueba-concurrencia.sh
#   13 · mutantes del PREFLIGHT: el mundo alterado; la migración debe negarse
#   14 · estado final: banco limpio, migración aplicada y registrada (dos veces) → prueba
#
# CÓMO SE DEJA EL BANCO LIMPIO (limpiar_restos, más abajo). Una asignación confirmada deja una
# constancia que NO se borra ni se vacía (sus disparadores lo impiden, con razón) y un vínculo. En el
# banco, y SOLO en el banco, se quitan como supabase_admin con `session_replication_role = replica`
# (apaga los disparadores de usuario): constancias, vínculos y sellos de los contratos ASIGNAR-NN, las
# cuotas a «pendiente», la cuenta de prueba a «vigente» y el contrato de prueba a «activo». La
# bitácora (public.audit_log) es de solo añadir y no se toca. Después, con cero constancias y las
# piezas intactas, reversa.sql devuelve RETIRADA y el catálogo es el de antes de la migración.
set -uo pipefail
C="${BANCO_CONTENEDOR:-avancecorp-cuentas-asignar-20261001}"
D="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # …/supabase
P="$D/scripts/cuentas-pago-asignar"
M="$D/migrations/20261002005004_crm_asignar_cuenta_pago.sql"
R="$P/reversa.sql"
RE="$P/reabrir-puerta.sql"
REGISTRAR="$P/registrar.sql"
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
k() { printf 'a519d000-0000-4000-8000-0000000000%02d' "$1"; }      # contrato ASIGNAR-NN
x() { printf 'a519c000-0000-4000-8000-0000000000%02d' "$1"; }      # cuenta de la siembra extra
s() { printf 'a519a000-0000-4000-8000-0000000080%02d' "$1"; }      # solicitud del ciclo
FALLOS=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SALIDA="${ASIGNAR_SALIDA:-$T}"; mkdir -p "$SALIDA"

# ── Contabilidad por tramo ───────────────────────────────────────────────────────────────────
TRAMOS=(); T_OK=(); T_KO=(); T_ASERT=(); IT=-1
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
medido() { printf '△ MEDIDO %-57s %s\n' "$1" "$2"; }

# ── Ayudantes ────────────────────────────────────────────────────────────────────────────────
q() { docker exec -i -e PGPASSWORD=postgres "$C" psql -U "${2:-postgres}" -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "$1" 2>&1 </dev/null; }
# La última línea de una consulta, o su primer ERROR (así un fallo nunca pasa por un resultado).
ultima() { local o; o=$(q "$1" "${2:-postgres}"); if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-300; else tail -1 <<<"$o"; fi; }
# Un archivo en UN mensaje y como postgres: su primer ERROR, o su última línea (los veredictos viajan
# como fila). Con $2 = un nivel de aislamiento, la conexión nace con ese nivel por defecto (un SET
# delante, en el mismo mensaje, no sirve: el «begin» del archivo hereda la transacción del mensaje).
archivo() {
  local o
  if [ -n "${2:-}" ]; then
    o=$(docker exec -i -e PGPASSWORD=postgres -e "PGOPTIONS=-c default_transaction_isolation=${2// /\\ }" "$C" \
          psql -U postgres -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "$(cat "$1")" 2>&1 </dev/null)
  else
    o=$(q "$(cat "$1")")
  fi
  if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-300; else tail -1 <<<"$o"; fi
}
# Solo las FILAS que devuelve un archivo (sin avisos ni errores): para ver que el veredicto es una fila.
filas() { docker exec -i -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "$(cat "$1")" 2>/dev/null </dev/null | tr '\n' ' ' | sed 's/ $//'; }
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
         || ' sellos=' || (select count(*) from crm.cuotas_cuenta_pagada)
         || ' cambios=' || (select count(*) from crm.contrato_cuenta_pago_cambios)
         || ' retiros=' || (select count(*) from crm.cuentas_bancarias_retiros)
         || ' rastro_vigente=' || (select count(*) from private.backfill_cuentas_p0xx b where b.revertida_en is null);" | grep -v '^SET$'
}
bitacora() { q "select count(*) from public.audit_log;"; }
# La foto de los trinquetes (private.assert_*() y contadores crudos), como en potencial-lead/banco/ciclo-fase3a.sh.
# $1 = «enteros»: la misma foto con el mensaje ENTERO de cada trinquete (trinquetes.sql lo corta a 160 caracteres).
# $2 = sentencias que se inyectan al empezar su transacción (para fotografiar bajo un mutante; se deshacen).
trinquetes() {
  local f="$TRINQUETES"
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
  docker exec -i -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -qAt < "$f" 2>&1 | sed 's/^.*NOTICE:  //'
}
sembrar() { local o; o=$(q "$(cat "$1")"); if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-260; else grep -m1 -o 'SIEMBRA .*' <<<"$o"; fi; }

# SOLO BANCO (ver la cabecera). Quita los vínculos que creó cualquier asignación (los señala su
# constancia) y deja el mundo de la siembra extra como se sembró.
limpiar_restos() {
  ultima "set session_replication_role = replica;
     do \$l\$ begin
       if to_regclass('$TABLA') is not null then
         delete from crm.contrato_cuentas_pago l using $TABLA a where l.id = a.vinculo_id;
         delete from $TABLA;
       end if;
     end \$l\$;
     delete from crm.cuotas_cuenta_pagada where contrato_id::text like 'a519d000-%';
     delete from crm.contrato_cuentas_pago where contrato_id::text like 'a519d000-%';
     update public.cronograma_pagos set estado = 'pendiente', fecha_pago_real = null, monto_pagado = null, registrado_por = null
      where id::text like 'a519e000-%' and (estado <> 'pendiente' or fecha_pago_real is not null or monto_pagado is not null or registrado_por is not null);
     update crm.cuentas_bancarias set activa = true, desactivada_por = null, desactivada_en = null
      where id::text like 'a519c000-%' and id <> '$(x 4)' and not activa;
     update public.contratos set estado = 'activo' where id = '$(k 5)' and estado <> 'activo';
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
     select 'piezas fuera';" | grep -v 'does not exist, skipping'
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

# ══ 0 · Punto de partida ════════════════════════════════════════════════════════════════════
tramo "0 · punto de partida"
if ! docker ps --format '{{.Names}}' | grep -qx "$C"; then echo "No hay un contenedor $C corriendo: móntalo con potencial-lead/banco/montar-banco.sh" >&2; exit 2; fi
paso "restos de corridas anteriores fuera" '^restos limpios$' "$(limpiar_restos)"
[ "$(aplicada)" = "no" ] || paso "se retiran las piezas de asignar que hubiera (banco)" '^piezas fuera$' "$(retirar_a_la_fuerza)"
[ "$(otra_aplicada)" = "no" ] || paso "se revierte la otra migración con su reversa documentada" '^NOTICE:  REVERSA: [0-9]+ vínculos de la carga borrados' "$(archivo "$OTRA_REVERSA")"
paso "registro de la versión fuera" '^registro fuera$' "$(quitar_registro)"
igual "el banco está en ANTES: ni asignar ni la otra migración" 'no/no' "$(aplicada)/$(otra_aplicada)"
igual "paridad: compuerta, candados ajenos y bloqueo de pagos de producción" \
  '810dce30e37d1da9d913ef48ab6a4aa1 7e946a5af78a827c18ee5b218896f24c e95919db53c44ff1fe6632c346f27a06 5efb8619e4342763ae77df2ee0bb1f61' \
  "$(q "select md5(p.prosrc) from unnest(array['private.admin_banca_vigente(uuid)', 'private.trg_contrato_cuenta_pago_coherente()', 'private.trg_registro_cuenta_pago_no_borrar()', 'private.exigir_cuenta_pago_cronograma()']) with ordinality f(firma, n) join pg_proc p on p.oid = to_regprocedure(f.firma) order by f.n;" | tr '\n' ' ' | sed 's/ $//')"
MD5_MIG="$(python3 -c "import hashlib,io,sys; print(hashlib.md5(io.open(sys.argv[1], encoding='utf-8').read().encode('utf-8')).hexdigest())" "$M")"
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

# ══ 2 · Lo que debe negarse sin la migración ════════════════════════════════════════════════
tramo "2 · sin la migración: reversa, reabrir y registrar se niegan"
paso "reversa" '^ERROR:  REVERSA ASIGNAR: la migración 20261002005004 no está aplicada; no hay nada que revertir' "$(archivo "$R")"
paso "reabrir-puerta" '^ERROR:  REABRIR ASIGNAR: las piezas vivas no son las de la migración 20261002005004; no se reabre' "$(archivo "$RE")"
paso "registrar" '^ERROR:  REGISTRO: la migración 20261002005004 no está aplicada; aplícala primero' "$(archivo "$REGISTRAR")"
igual "nada cambió en el catálogo" "$(cat "$SALIDA/catalogo-antes.txt")" "$(foto_catalogo)"

# ══ 3 · Migración, prueba y trinquetes ══════════════════════════════════════════════════════
tramo "3 · migración → repetida → prueba → trinquetes"
igual "la migración devuelve su veredicto como FILA (única fila)" 'ASIGNAR_CUENTA_PAGO_OK' "$(filas "$M")"
igual "quedó aplicada, con las huellas de su postflight (candado núcleo puerta)" "sí $(huellas_del_postflight)" "$(aplicada) $(huellas_vivas)"
PIEZAS="$(foto_piezas)"
igual "permisos de ejecutar: puerta y núcleo solo authenticated; candado nadie" 'candado:postgres nucleo:authenticated,postgres puerta:authenticated,postgres' "$(permisos)"
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
tramo "4 · reversa sin asignaciones → RETIRADA → catálogo de antes → reaplicar"
igual "reversa: veredicto como FILA" 'RETIRADA: sin asignaciones registradas; se quitaron la puerta, el núcleo, el candado y la tabla' "$(filas "$R")"
igual "el catálogo vuelve a ser EXACTAMENTE el de antes de la migración (12 aspectos)" "$(cat "$SALIDA/catalogo-antes.txt")" "$(foto_catalogo)"
igual "los datos no cambiaron" "$DATOS_SEMBRADO" "$(foto_datos)"
paso "reversa repetida: se niega" '^ERROR:  REVERSA ASIGNAR: la migración 20261002005004 no está aplicada' "$(archivo "$R")"
# Se reaplica sentencia a sentencia y DOS veces en la MISMA sesión: la primera aplica; la segunda se niega.
DOS="$(cat "$M" "$M" | docker exec -i -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -qAt 2>&1)"
igual "reaplicada (sentencia a sentencia): quedó como la primera vez" "sí $PIEZAS" "$(aplicada) $(foto_piezas)"
paso "la segunda pasada, en la misma sesión, se niega" 'ERROR:  ASIGNAR PREFLIGHT: ya aplicada' "$(grep -m1 -o 'ERROR:  ASIGNAR PREFLIGHT.*' <<<"$DOS")"
medido "veredicto tras la pasada FALLIDA en esa misma sesión" "$(grep -c '^ASIGNAR_CUENTA_PAGO_OK$' <<<"$DOS") filas ASIGNAR_CUENTA_PAGO_OK para 1 aplicación (2 = la sesión repite el OK anterior; en un mensaje o en conexión nueva no sale)"
prueba_paso "prueba tras reaplicar"

# ══ 5 · La reversa exige READ COMMITTED ═════════════════════════════════════════════════════
tramo "5 · la reversa en REPEATABLE READ y SERIALIZABLE"
paso "reversa en REPEATABLE READ: se niega" '^ERROR:  REVERSA ASIGNAR: la transacción debe ir en READ COMMITTED \(va en repeatable read\)' "$(archivo "$R" 'repeatable read')"
paso "reversa en SERIALIZABLE: se niega" '^ERROR:  REVERSA ASIGNAR: la transacción debe ir en READ COMMITTED \(va en serializable\)' "$(archivo "$R" 'serializable')"
igual "no cambió nada: aplicada, abierta y con sus piezas" "sí abierta $PIEZAS" "$(aplicada) $(abierta) $(foto_piezas)"

# ══ 6 · Reversa CON una asignación confirmada, y reabrir ════════════════════════════════════
tramo "6 · una asignación confirmada → PUERTA_CERRADA → reabrir"
paso "una asignación CONFIRMADA (admin, ASIGNAR-12)" '^OK:\{"banco": "BCP", "moneda": "PEN", "ultimos": "0001", "ya_aplicada": false, "solicitud_id": "[0-9a-f-]+", "numero_contrato": "ASIGNAR-12"\}$' "$(asignar_confirmada "$ADMIN" "$(s 1)" "$(k 12)" "$(x 1)")"
CONSTANCIA="$(q "set timezone = 'UTC'; select md5(string_agg(to_jsonb(a)::text, ',' order by a.id)) from $TABLA a;" | grep -v '^SET$')"
VINCULO="$(q "set timezone = 'UTC'; select to_jsonb(l)::text from crm.contrato_cuentas_pago l where l.contrato_id = '$(k 12)';" | grep -v '^SET$')"
DATOS_CON_UNA="$(foto_datos)"
igual "reversa con una asignación: veredicto como FILA" 'PUERTA_CERRADA: 1 asignaciones conservadas; no se borró nada' "$(filas "$R")"
igual "nada borrado: la tabla, las tres funciones y sus cuerpos siguen" "sí $(huellas_del_postflight)" "$(aplicada) $(huellas_vivas)"
igual "la constancia está intacta" "1 $CONSTANCIA" "$(constancias) $(q "set timezone = 'UTC'; select md5(string_agg(to_jsonb(a)::text, ',' order by a.id)) from $TABLA a;" | grep -v '^SET$')"
igual "el vínculo está intacto" "$VINCULO" "$(q "set timezone = 'UTC'; select to_jsonb(l)::text from crm.contrato_cuentas_pago l where l.contrato_id = '$(k 12)';" | grep -v '^SET$')"
igual "los datos no cambiaron con la reversa" "$DATOS_CON_UNA" "$(foto_datos)"
igual "la puerta quedó cerrada: nadie más que el dueño ejecuta (por catálogo)" 'cerrada candado:postgres nucleo:postgres puerta:postgres' "$(abierta) $(permisos)"
paso "con la puerta cerrada no se asigna (el ciclo no llama: lo dice el catálogo)" '^NO SE LLAMA' "$(asignar_confirmada "$ADMIN" "$(s 2)" "$(k 13)" "$(x 2)")"
igual "reversa otra vez: mismo veredicto, nada cambia" 'PUERTA_CERRADA: 1 asignaciones conservadas; no se borró nada' "$(filas "$R")"
paso "migración con la puerta cerrada: se niega (ya aplicada)" '^ERROR:  ASIGNAR PREFLIGHT: ya aplicada' "$(archivo "$M")"
# reabrir-puerta frente a piezas alteradas, con la puerta cerrada. Lo que su cabecera promete: «se niega
# si las piezas no son las de la migración». Cada alteración se repone y la puerta se vuelve a cerrar.
guardar "$NUCLEO" nucleo-original; guardar "$PUERTA" puerta-original; guardar "$CANDADO" candado-original
q "do \$m\$ declare d text := pg_get_functiondef('$NUCLEO'::regprocedure); begin execute replace(d, 'declare' || chr(10) || '  v_actor uuid', 'declare' || chr(10) || '  -- alterado' || chr(10) || '  v_actor uuid'); end \$m\$;" >/dev/null
paso "reabrir con el NÚCLEO alterado: se niega" '^ERROR:  REABRIR ASIGNAR: las piezas vivas no son las de la migración' "$(archivo "$RE")"
reponer nucleo-original
q "do \$m\$ declare d text := pg_get_functiondef('$PUERTA'::regprocedure); begin execute replace(d, '  select private.', '  select /* alterada */ private.'); end \$m\$;" >/dev/null
paso "reabrir con la PUERTA alterada: se niega" '^ERROR:  REABRIR ASIGNAR: las piezas vivas no son las de la migración' "$(archivo "$RE")"
reponer puerta-original
q "grant execute on function $PUERTA to anon;" >/dev/null
paso "reabrir con anon colado en la puerta: se niega" '^ERROR:  REABRIR ASIGNAR: quedó un permiso de ejecutar de más' "$(archivo "$RE")"
igual "    y no dejó la puerta a medio abrir" 'cerrada' "$(abierta)"
q "revoke execute on function $PUERTA from anon;" >/dev/null
igual "tras reponer, las piezas son las de la migración con la puerta cerrada (solo cambian los permisos)" "$(huellas_del_postflight) candado:postgres nucleo:postgres puerta:postgres" "$(huellas_vivas) $(permisos)"
# Medidas: alteraciones que reabrir-puerta NO mira (solo compara md5 del cuerpo del núcleo y de la puerta).
medir_reabrir() { # $1 etiqueta · $2 sentencia que altera · $3 sentencia que repone
  local r
  q "$2" >/dev/null
  r=$(archivo "$RE")
  medido "reabrir con $1" "$r"
  [ -z "$3" ] || q "$3" >/dev/null
  [ "$(abierta)" = "cerrada" ] || archivo "$R" >/dev/null
}
medir_reabrir "el CANDADO neutralizado (su cuerpo deja pasar)" \
  "do \$m\$ declare d text := pg_get_functiondef('$CANDADO'::regprocedure); begin execute regexp_replace(d, 'raise exception using errcode = ''22023'',\s+message = ''[^'']+'';', 'return new;'); end \$m\$;" ""
reponer candado-original
medir_reabrir "la PUERTA vuelta SECURITY DEFINER (mismo cuerpo)" "alter function $PUERTA security definer;" "alter function $PUERTA security invoker;"
medir_reabrir "el NÚCLEO sin search_path fijo (mismo cuerpo)" "alter function $NUCLEO reset search_path;" "alter function $NUCLEO set search_path to '';"
medir_reabrir "el NÚCLEO vuelto SECURITY INVOKER (mismo cuerpo)" "alter function $NUCLEO security invoker;" "alter function $NUCLEO security definer;"
medir_reabrir "el candado «no se modifica» APAGADO en la tabla" "alter table $TABLA disable trigger trg_contrato_cuenta_pago_asignaciones_00_inmutable;" "alter table $TABLA enable trigger trg_contrato_cuenta_pago_asignaciones_00_inmutable;"
medir_reabrir "la tabla SIN RLS" "alter table $TABLA disable row level security;" "alter table $TABLA enable row level security;"
igual "tras las medidas, todo repuesto y la puerta cerrada" "cerrada $(huellas_del_postflight)" "$(abierta) $(huellas_vivas)"
# El camino bueno.
igual "reabrir-puerta: veredicto como FILA" 'PUERTA_REABIERTA' "$(filas "$RE")"
igual "reabierta: las piezas son EXACTAMENTE las de recién aplicada (definición, ACL, disparadores…)" "abierta $PIEZAS" "$(abierta) $(foto_piezas)"
paso "tras reabrir se vuelve a asignar (superadmin, ASIGNAR-13)" '^OK:\{.*"ya_aplicada": false.*"numero_contrato": "ASIGNAR-13"\}$' "$(asignar_confirmada "$SUPER" "$(s 2)" "$(k 13)" "$(x 2)")"
igual "reabrir otra vez con la puerta ya abierta: no cambia nada" "PUERTA_REABIERTA $PIEZAS" "$(filas "$RE") $(foto_piezas)"
igual "dos constancias y sus dos vínculos" "2 $(x 1)|$ADMIN $(x 2)|$SUPER" "$(constancias) $(vinculo "$(k 12)") $(vinculo "$(k 13)")"
# Dejar el banco limpio (ver la cabecera).
paso "limpieza del banco (réplica): constancias, vínculos y restos fuera" '^restos limpios$' "$(limpiar_restos)"
igual "banco limpio: los datos son los de la siembra y no quedan constancias" "$DATOS_SEMBRADO 0" "$(foto_datos) $(constancias)"
igual "ya sin asignaciones, la reversa RETIRA y el catálogo es el de antes" "RETIRADA: sin asignaciones registradas; se quitaron la puerta, el núcleo, el candado y la tabla · igual" \
  "$(filas "$R") · $([ "$(foto_catalogo)" = "$(cat "$SALIDA/catalogo-antes.txt")" ] && echo igual || echo distinto)"
igual "se reaplica para seguir" "ASIGNAR_CUENTA_PAGO_OK $PIEZAS" "$(filas "$M") $(foto_piezas)"

# ══ 7 · Piezas cambiadas y cero asignaciones ════════════════════════════════════════════════
tramo "7 · piezas cambiadas con cero asignaciones: cierra en vez de borrar"
guardar "$NUCLEO" nucleo-original; guardar "$CANDADO" candado-original
q "do \$m\$ declare d text := pg_get_functiondef('$NUCLEO'::regprocedure); begin execute replace(d, 'declare' || chr(10) || '  v_actor uuid', 'declare' || chr(10) || '  -- alterado' || chr(10) || '  v_actor uuid'); end \$m\$;" >/dev/null
paso "testigo: el núcleo vivo ya no tiene la huella de la migración" '^distinta$' "$([ "$(huellas_vivas)" = "$(huellas_del_postflight)" ] && echo igual || echo distinta)"
igual "reversa con el NÚCLEO cambiado y 0 asignaciones: cierra, no borra" 'PUERTA_CERRADA: 0 asignaciones conservadas; no se borró nada (las piezas cambiaron después de la migración)' "$(filas "$R")"
igual "    nada borrado y la puerta cerrada" 'sí cerrada' "$(aplicada) $(abierta)"
paso "reabrir con el núcleo cambiado: se niega" '^ERROR:  REABRIR ASIGNAR: las piezas vivas no son las de la migración' "$(archivo "$RE")"
reponer nucleo-original
igual "con el núcleo repuesto, reabrir reabre y todo es como recién aplicada" "PUERTA_REABIERTA abierta $PIEZAS" "$(filas "$RE") $(abierta) $(foto_piezas)"
q "do \$m\$ declare d text := pg_get_functiondef('$CANDADO'::regprocedure); begin execute replace(d, 'no se modifica ni se vacía', 'no se modifica ni se vacía.'); end \$m\$;" >/dev/null
igual "reversa con el CANDADO cambiado y 0 asignaciones: cierra, no borra" 'PUERTA_CERRADA: 0 asignaciones conservadas; no se borró nada (las piezas cambiaron después de la migración)' "$(filas "$R")"
reponer candado-original
igual "con el candado repuesto, reabrir reabre y todo es como recién aplicada" "PUERTA_REABIERTA abierta $PIEZAS" "$(filas "$RE") $(abierta) $(foto_piezas)"
prueba_paso "prueba tras cerrar, reponer y reabrir"

# ══ 8 · Concurrencia con dos sesiones reales ════════════════════════════════════════════════
tramo "8 · concurrencia (prueba-concurrencia.sh, 15 casos)"
BANCO_CONTENEDOR="$C" bash "$CONC" > "$SALIDA/concurrencia.txt" 2>&1
grep -E '^[A-Z][0-9]? ·|✗' "$SALIDA/concurrencia.txt" | cut -c1-260 | sed 's/^/    /'
paso "concurrencia: todos los casos" '^CONCURRENCIA asignar_cuenta_pago: [0-9]+ OK, 0 FALLAS$' "$(tail -1 "$SALIDA/concurrencia.txt")"
T_ASERT[$IT]=$((${T_ASERT[$IT]} + $(sed -n 's/^CONCURRENCIA asignar_cuenta_pago: \([0-9]*\) OK.*/\1/p' "$SALIDA/concurrencia.txt" | tail -1)))
igual "tras la concurrencia: aplicada, abierta, piezas intactas y el mundo como se sembró" "sí abierta $PIEZAS $DATOS_SEMBRADO 0" "$(aplicada) $(abierta) $(foto_piezas) $(foto_datos) $(constancias)"

# ══ 9 · Con la otra migración ═══════════════════════════════════════════════════════════════
tramo "9 · con la otra migración (20261001233019), en los dos órdenes"
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
paso "    vuelta atrás: la reversa de la otra borra sus 3 vínculos y se limpia la asignación (banco)" '^NOTICE:  REVERSA: 3 vínculos de la carga borrados · restos limpios$' "$(archivo "$OTRA_REVERSA") · $(limpiar_restos)"
igual "    el mundo vuelve a ser el sembrado, sin la otra y sin constancias" "$DATOS_SEMBRADO 0 no" "$(foto_datos) $(constancias) $(otra_aplicada)"
# Carrera 2 · la otra migración va primero (su carga tiene el candado EXCLUSIVE y tarda 3 s) y llega la asignación.
python3 - "$OTRA" "$T/otra-lenta.sql" <<'PY'
import io, sys
t = io.open(sys.argv[1], encoding='utf-8').read()
a = "\nlock table crm.cuentas_bancarias in exclusive mode;\n"
assert t.count(a) == 1, 'la otra migración ya no toma su candado como se esperaba'
io.open(sys.argv[2], 'w', encoding='utf-8').write(t.replace(a, a + "select pg_sleep(3);\n"))
PY
q "$(cat "$T/otra-lenta.sql")" > "$T/otra-lenta.out" 2>&1 &
for _ in $(seq 1 100); do [ "$(q "select count(*) from pg_locks l where l.relation = 'crm.cuentas_bancarias'::regclass and l.mode = 'ExclusiveLock' and l.granted")" = "1" ] && break; sleep 0.1; done
r="$(asignar_confirmada "$ADMIN" "$(s 4)" "$REZAGO_03" "$CUENTA_04" ms)"; wait
paso "carrera 2 · la carga en vuelo y llega la asignación a REZAGO-03: espera y recibe «ya tiene cuenta de pago»" \
  '^ERR:22023:El contrato REZAGO-03 ya tiene cuenta de pago; para cambiarla usa «Cambiar cuenta de pago» ESPERA_MS [0-9]+$' "$r"
paso "    la asignación ESPERÓ a la carga (≥ 1,5 s) y la otra terminó con sus 4 vínculos" '^sí · .*"contratos": \["REZAGO-03", "REZAGO-04", "REZAGO-05", "REZAGO-06"\], "vinculados": 4\}$' \
  "$([ "$(sed -n 's/.* ESPERA_MS \([0-9]*\)$/\1/p' <<<"$r")" -ge 1500 ] 2>/dev/null && echo sí || echo no) · $(if grep -q 'ERROR:' "$T/otra-lenta.out"; then grep -m1 -o 'ERROR:.*' "$T/otra-lenta.out"; else tail -1 "$T/otra-lenta.out"; fi)"
igual "    REZAGO-03 quedó con el vínculo de la CARGA (sin autor) y no hay ninguna constancia" "$CUENTA_04|(null) 0" "$(vinculo "$REZAGO_03") $(constancias)"
igual "las piezas de asignar no cambiaron al aplicar la otra" "sí abierta $PIEZAS" "$(aplicada) $(abierta) $(foto_piezas)"
prueba_paso "prueba con las DOS migraciones (orden asignar → otra)" '^T10 PASS · [1-9][0-9]* comprobaciones · con las dos migraciones \(la carga de la otra tiene 4 vínculos vivos\)'
paso "la otra, repetida, no hace nada (idempotente)" '"contratos": \[\], "vinculados": 0\}$' "$(archivo "$OTRA")"
BANCO_CONTENEDOR="$C" SOLO="A B2 C1" bash "$CONC" > "$SALIDA/concurrencia-con-la-otra.txt" 2>&1
paso "concurrencia con la otra puesta (casos A, B2 y C1: el pago usa el bloqueo nuevo)" '^CONCURRENCIA asignar_cuenta_pago: [0-9]+ OK, 0 FALLAS$' "$(tail -1 "$SALIDA/concurrencia-con-la-otra.txt")"
grep '✗' "$SALIDA/concurrencia-con-la-otra.txt" | cut -c1-260 | sed 's/^/    /'
# Orden otra → asignar: se retira asignar con la otra puesta y se vuelve a aplicar.
igual "con la otra puesta, la reversa de asignar retira" 'RETIRADA: sin asignaciones registradas; se quitaron la puerta, el núcleo, el candado y la tabla' "$(filas "$R")"
trinquetes > "$SALIDA/trinquetes-solo-la-otra.txt"; trinquetes enteros > "$SALIDA/trinquetes-enteros-solo-la-otra.txt"
igual "otra → asignar: la migración se aplica sobre la otra" "ASIGNAR_CUENTA_PAGO_OK $PIEZAS" "$(filas "$M") $(foto_piezas)"
trinquetes > "$SALIDA/trinquetes-las-dos.txt"; trinquetes enteros > "$SALIDA/trinquetes-enteros-las-dos.txt"
igual "trinquetes con la otra y SIN asignar = con las dos (foto de trinquetes.sql)" "$(cat "$SALIDA/trinquetes-solo-la-otra.txt")" "$(cat "$SALIDA/trinquetes-las-dos.txt")"
igual "    y con los mensajes enteros" "$(cat "$SALIDA/trinquetes-enteros-solo-la-otra.txt")" "$(cat "$SALIDA/trinquetes-enteros-las-dos.txt")"
prueba_paso "prueba con las DOS migraciones (orden otra → asignar)" '^T10 PASS · [1-9][0-9]* comprobaciones · con las dos migraciones'
# Vuelta: se revierte la otra con su reversa documentada y asignar sigue funcionando sola.
paso "reversa de la otra (la documentada en su migración)" '^NOTICE:  REVERSA: 4 vínculos de la carga borrados' "$(archivo "$OTRA_REVERSA")"
igual "sin la otra, asignar sigue igual y el mundo es el sembrado" "sí abierta $PIEZAS no $DATOS_SEMBRADO" "$(aplicada) $(abierta) $(foto_piezas) $(otra_aplicada) $(foto_datos)"
prueba_paso "prueba otra vez sola" '^T10 PASS · 0 comprobaciones · NO APLICA'

# ── Fábrica de mutantes (sobre el texto REAL de la migración y de la reversa) ─────────────────
mkdir -p "$T/mut" "$T/pre" "$T/vivo"
python3 - "$T" "$M" "$R" <<'PY' || { echo "✗ la fábrica de mutantes no pudo escribir sus archivos (¿cambió el texto de la migración?)"; FALLOS=$((FALLOS + 1)); }
import io, re, sys
T, M, R = sys.argv[1:]
mig = io.open(M, encoding='utf-8').read()
rev = io.open(R, encoding='utf-8').read()
NUCLEO = 'private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'
PUERTA = 'crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'
CANDADO = 'private.trg_contrato_cuenta_pago_asignaciones_inmutable()'
TABLA = 'crm.contrato_cuenta_pago_asignaciones'
POST = 'ERROR:  ASIGNAR POSTFLIGHT'

def cuerpo(t):
    """El archivo sin su «begin;» ni nada desde su último «commit;»: para meterlo en otra transacción."""
    return t[t.index('begin;\n') + len('begin;\n'):t.rindex('commit;')]
MC, RC = cuerpo(mig), cuerpo(rev)
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
def mutante(n, desc, pares, iny=None, espera_a=POST, espera_b='-', firma=NUCLEO):
    """pares = (fragmento, reemplazo) sobre el texto de la migración. iny = lo que se inyecta en la prueba
    (por defecto, los mismos pares sobre la función viva; '' = no se inyecta)."""
    m = MC
    for a, b in pares:
        assert mig.count(a) == 1, 'mutante %s: el fragmento no está exactamente una vez en la migración: %r' % (n, a[:70])
        m = m.replace(a, b, 1)
    io.open('%s/mut/%s.mig.sql' % (T, n), 'w', encoding='utf-8').write(mensaje('', m))
    if iny is None:
        iny = vivo(firma, pares)
    if iny:
        io.open('%s/mut/%s.iny.sql' % (T, n), 'w', encoding='utf-8').write(iny)
    lista.append('|'.join([n, desc, espera_a, espera_b]))

# ── Fragmentos del núcleo, tal como están en la migración
COMPUERTA = "  if not coalesce(private.admin_banca_vigente(v_actor), false) then"
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
FILTRO = "    if v_esquema is distinct from 'crm' or v_tabla is distinct from 'contrato_cuentas_pago' then"
CAPTURA = ("  exception when unique_violation then\n"
           "    get stacked diagnostics v_esquema = schema_name, v_tabla = table_name;\n"
           + FILTRO + "\n      raise;\n    end if;\n"
           "    raise exception using errcode = '22023',\n"
           "      message = pg_catalog.format('El contrato %s ya tiene cuenta de pago; para cambiarla usa «Cambiar cuenta de pago»', v_ct.numero_contrato);\n"
           "  end;")
ULTIMOS = "    'ultimos', pg_catalog.right(v_cuenta.numero_cuenta, 4));"
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
mutante('06-con-cuenta-sin-mirar', 'no rechaza el contrato que ya tiene cuenta (queda la unicidad)', [(CON_CUENTA, "  if false then")], espera_b='^TC$')
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
# ── El retorno
mutante('r1-ultimos-entero', '«ultimos» devuelve el número de cuenta entero', [(ULTIMOS, "    'ultimos', v_cuenta.numero_cuenta);")], espera_b='T1')
mutante('r2-repetida-dos-claves', 'la repetición devuelve otras claves', [(REPETIDA, "      return pg_catalog.jsonb_build_object('solicitud_id', p_solicitud_id, 'ya_aplicada', true);")], espera_b='T5')
mutante('r3-retorno-con-cci', 'el retorno lleva el CCI', [(ULTIMOS, "    'ultimos', pg_catalog.right(v_cuenta.numero_cuenta, 4), 'cci', v_cuenta.cci);")], espera_b='T1')
# ── Candados (solo los ve la concurrencia: en la prueba secuencial únicamente los delata la huella)
mutante('c1-sin-for-share-cuenta', 'sin FOR SHARE de la cuenta', [(FOR_SHARE_CUENTA, FOR_SHARE_CUENTA.replace(' for share;', ';'))], espera_b='^TC$')
mutante('c2-sin-for-share-contrato', 'sin FOR SHARE del contrato', [(FOR_SHARE_CONTRATO, "  where ct.id = p_contrato_id;")], espera_b='^TC$')
mutante('c3-sin-candado-solicitud', 'sin el candado consultivo de la solicitud', [(CANDADO_SOLICITUD, "")], espera_b='^TC$')
for n, pares in (('c0-sin-capturar-unicidad', [(CAPTURA, "  end;")]), ('c1-sin-for-share-cuenta', [(FOR_SHARE_CUENTA, FOR_SHARE_CUENTA.replace(' for share;', ';'))]),
                 ('c2-sin-for-share-contrato', [(FOR_SHARE_CONTRATO, "  where ct.id = p_contrato_id;")]), ('c3-sin-candado-solicitud', [(CANDADO_SOLICITUD, "")])):
    io.open('%s/vivo/%s.sql' % (T, n), 'w', encoding='utf-8').write(vivo(NUCLEO, pares))
# ── 13 a 20 y más: permisos, forma y tabla
G_PUERTA = "grant execute on function %s\n  to authenticated;" % PUERTA
G_NUCLEO = "grant execute on function %s\n  to authenticated;" % NUCLEO
R_PUERTA = "revoke all on function %s\n  from public, anon, authenticated, service_role;\n" % PUERTA
R_CANDADO = "revoke all on function %s from public, anon, authenticated, service_role;" % CANDADO
R_TABLA = "revoke all on %s from public, anon, authenticated, service_role;" % TABLA
RLS = "alter table %s enable row level security;\n" % TABLA
def disparador(nombre):
    return re.search(r"create trigger %s\n.*\n.*;\n" % nombre, mig).group(0)
AUDIT = disparador('trg_audit_contrato_cuenta_pago_asignaciones')
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
for n, nombre, desc in (('19-sin-candado-no-se-modifica', 'trg_contrato_cuenta_pago_asignaciones_00_inmutable', 'sin el candado «no se modifica»'),
                        ('19b-sin-candado-no-se-borra', 'trg_contrato_cuenta_pago_asignaciones_00_no_borrar', 'sin el candado «no se borra»'),
                        ('19c-sin-candado-no-se-vacia', 'trg_contrato_cuenta_pago_asignaciones_00_sin_vaciar', 'sin el candado «no se vacía»')):
    mutante(n, desc, [(disparador(nombre), "")], iny="drop trigger %s on %s;\n" % (nombre, TABLA), espera_b='T7')
BLOQUEA = "  raise exception using errcode = '22023',\n    message = 'El registro de asignaciones de cuenta de pago no se modifica ni se vacía';"
mutante('19d-candado-deja-pasar', 'el candado «no se modifica» deja pasar', [(BLOQUEA, "  return new;")], espera_b='T7', firma=CANDADO)
mutante('20-cuerpo-sin-huella', 'el cuerpo cambia (un comentario) y la huella no', [(COMPUERTA, "  -- cambio sin actualizar la huella\n" + COMPUERTA)], espera_b='^TC$')
mutante('21-constancia-con-fk', 'la constancia con una clave foránea', [("  contrato_id         uuid not null,", "  contrato_id         uuid not null references public.contratos (id),")],
        iny="alter table %s add constraint zz_prueba_fk foreign key (contrato_id) references public.contratos (id);\n" % TABLA, espera_b='T7')
COMENTARIO = "comment on column %s.motivo is 'Motivo escrito por administración (5 a 500 caracteres).';\n" % TABLA
mutante('22-columna-sin-comentario', 'una columna sin comentario', [(COMENTARIO, "")], iny="comment on column %s.motivo is null;\n" % TABLA, espera_b='T7')
C_PUERTA = re.search(r"comment on function crm\.asignar_cuenta_pago_contrato\(uuid,uuid,uuid,text\) is '.*';\n", mig).group(0)
mutante('22b-puerta-sin-comentario', 'la puerta sin comentario', [(C_PUERTA, "")], iny="comment on function %s is null;\n" % PUERTA, espera_b='TC')
# ── Lo que el postflight NO mira (se anota a sabiendas): las restricciones de la tabla, la forma de los candados
# (solo nombre y habilitado) y un revoke redundante
CHECK = re.search(r"check \(motivo = regexp_replace\(.*\n.*\n\s*and length\(motivo\) <= 500\)", mig).group(0)
mutante('23-motivo-sin-check', 'la tabla sin el CHECK del motivo', [(CHECK, "check (motivo is not null)")],
        iny="alter table %s drop constraint contrato_cuenta_pago_asignaciones_motivo_valido;\n" % TABLA, espera_a='MUTANTE_SIN_ERROR', espera_b='T7')
mutante('23b-solicitud-sin-unica', 'la tabla sin la unicidad de la solicitud',
        [("  solicitud_id        uuid not null constraint contrato_cuenta_pago_asignaciones_solicitud_uq unique,", "  solicitud_id        uuid not null,")],
        iny="alter table %s drop constraint contrato_cuenta_pago_asignaciones_solicitud_uq;\n" % TABLA, espera_a='MUTANTE_SIN_ERROR', espera_b='T7')
CON_CANDADO = ("  before update on %s\n  for each row execute function %s;" % (TABLA, CANDADO))
mutante('23c-candado-con-condicion', 'el candado «no se modifica» con una condición que nunca se cumple (mismo nombre, habilitado)',
        [(CON_CANDADO, CON_CANDADO.replace("for each row execute", "for each row when (old.motivo is null) execute"))],
        iny=("drop trigger trg_contrato_cuenta_pago_asignaciones_00_inmutable on %s;\n"
             "create trigger trg_contrato_cuenta_pago_asignaciones_00_inmutable before update on %s "
             "for each row when (old.motivo is null) execute function %s;\n") % (TABLA, TABLA, CANDADO),
        espera_a='MUTANTE_SIN_ERROR', espera_b='T7')
mutante('24-tabla-sin-revoke', 'la tabla sin su revoke (en este banco crm no da permisos por defecto)', [(R_TABLA + "\n", "")], iny='', espera_a='MUTANTE_SIN_ERROR')
# ── Solo en la prueba: la compuerta ajena (private.admin_banca_vigente) alterada. La migración la para en el PREFLIGHT (tramo 13).
ROLES = "p.rol in ('admin', 'superadmin')"
io.open('%s/mut/02b-compuerta-ajena.iny.sql' % T, 'w', encoding='utf-8').write(vivo('private.admin_banca_vigente(uuid)', [(ROLES, "p.rol in ('admin', 'superadmin', 'operaciones')")]))
lista.append('02b-compuerta-ajena|la compuerta de F3 (private.admin_banca_vigente) acepta operaciones|-|T1')
io.open('%s/mut/lista.txt' % T, 'w', encoding='utf-8').write('\n'.join(lista) + '\n')

# ── Mutantes del PREFLIGHT: el mundo alterado antes de aplicar la migración (todo en una transacción que se deshace)
pre = []
def mundo(n, desc, alteracion, espera):
    io.open('%s/pre/%s.sql' % (T, n), 'w', encoding='utf-8').write(mensaje(alteracion, MC))
    pre.append('|'.join([n, desc, espera]))
PIEZAS = 'ERROR:  ASIGNAR PREFLIGHT: la compuerta de administración o los candados del vínculo no son los esperados'
TRIGGERS = 'ERROR:  ASIGNAR PREFLIGHT: faltan los triggers de coherencia, bitácora o candado del vínculo'
UNICO = 'ERROR:  ASIGNAR PREFLIGHT: el vínculo ya no es único por contrato'
SENUELO = ("create function private.zz_senuelo() returns trigger language plpgsql set search_path to '' as $s$ begin return new; end $s$;\n")
mundo('p1-compuerta-alterada', 'private.admin_banca_vigente acepta operaciones', vivo('private.admin_banca_vigente(uuid)', [(ROLES, "p.rol in ('admin', 'superadmin', 'operaciones')")]), PIEZAS)
mundo('p2-coherencia-alterada', 'el candado de coherencia del vínculo cambiado', vivo('private.trg_contrato_cuenta_pago_coherente()', [("and cb.moneda = ct.moneda", "and true")]), PIEZAS)
mundo('p3-no-borrar-alterado', 'el candado «no se borra» cambiado', vivo('private.trg_registro_cuenta_pago_no_borrar()', [("Los registros de cuentas de pago no se borran", "No se borran")]), PIEZAS)
mundo('p4-coherencia-apagada', 'el disparador de coherencia apagado', "alter table crm.contrato_cuentas_pago disable trigger trg_contrato_cuenta_pago_coherente;", TRIGGERS)
mundo('p5-coherencia-senuelo', 'el disparador de coherencia, mismo nombre y otra función',
      SENUELO + "drop trigger trg_contrato_cuenta_pago_coherente on crm.contrato_cuentas_pago;\n"
      "create trigger trg_contrato_cuenta_pago_coherente before insert or update on crm.contrato_cuentas_pago for each row execute function private.zz_senuelo();", TRIGGERS)
mundo('p6-bitacora-senuelo', 'la bitácora del vínculo, mismo nombre y otra función',
      SENUELO + "drop trigger trg_audit_contrato_cuentas_pago on crm.contrato_cuentas_pago;\n"
      "create trigger trg_audit_contrato_cuentas_pago after insert or delete or update on crm.contrato_cuentas_pago for each row execute function private.zz_senuelo();", TRIGGERS)
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
io.open('%s/pre/lista.txt' % T, 'w', encoding='utf-8').write('\n'.join(pre) + '\n')

# ── Reversas alteradas (las caza la concurrencia)
SIN_CANDADO = "  lock table crm.contrato_cuenta_pago_asignaciones in access exclusive mode;\n"
assert rev.count(SIN_CANDADO) == 1, 'la reversa ya no toma el candado de la tabla como se esperaba'
io.open('%s/vivo/reversa-sin-candado.sql' % T, 'w', encoding='utf-8').write(rev.replace(SIN_CANDADO, ''))
AISLAMIENTO = re.search(r"  if pg_catalog\.current_setting\('transaction_isolation'\) <> 'read committed' then\n.*\n.*\n  end if;\n", rev)
assert AISLAMIENTO, 'la reversa ya no exige READ COMMITTED como se esperaba'
io.open('%s/vivo/reversa-sin-aislamiento.sql' % T, 'w', encoding='utf-8').write(rev.replace(AISLAMIENTO.group(0), ''))
print('%d mutantes de la migración, %d del preflight' % (len(lista), len(pre)))
PY
[ "$SALIDA" = "$T" ] || cp -R "$T/mut" "$T/pre" "$T/vivo" "$SALIDA/" 2>/dev/null
# El resultado de un mensaje-mutante: su primer ERROR, o MUTANTE_SIN_ERROR si llegó al final.
mutado() { local o; o=$(q "$(cat "$1")"); if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-150; else grep -m1 -o 'MUTANTE_SIN_ERROR' <<<"$o" || echo '(sin veredicto)'; fi; }

# ══ 10 · Mutantes de la migración ═══════════════════════════════════════════════════════════
tramo "10 · mutantes de la MIGRACIÓN (texto real alterado; debe pararlos el pre/postflight)"
igual "punto de partida de los mutantes: aplicada, abierta, intacta y sin constancias" "sí abierta $PIEZAS 0" "$(aplicada) $(abierta) $(foto_piezas) $(constancias)"
while IFS='|' read -r id desc ea eb <&3; do
  [ -f "$T/mut/$id.mig.sql" ] || continue
  r=$(mutado "$T/mut/$id.mig.sql")
  if [ "$ea" = "MUTANTE_SIN_ERROR" ]; then
    paso "  $id" '^MUTANTE_SIN_ERROR$' "$r"
    medido "  $id" "pasa el postflight: $desc"
  else
    paso "  $id" "^$ea" "$r"
  fi
done 3< "$T/mut/lista.txt"
igual "los mutantes no dejaron nada: mismas piezas, mismos datos" "sí abierta $PIEZAS $DATOS_SEMBRADO" "$(aplicada) $(abierta) $(foto_piezas) $(foto_datos)"

# ══ 11 · Los mutantes en la prueba ══════════════════════════════════════════════════════════
tramo "11 · los mismos mutantes inyectados en la prueba: qué tramo caza cada uno"
while IFS='|' read -r id desc ea eb <&3; do
  [ -f "$T/mut/$id.iny.sql" ] || continue
  correr_prueba "$T/mut/$id.iny.sql"
  [ "$SALIDA" = "$T" ] || printf '%s\n' "$SALIDA_PRUEBA" > "$SALIDA/prueba-$id.txt"
  if [ "$eb" = '^TC$' ]; then
    paso "  $id" '^TC$' "${CAIDOS:-ninguno · $VEREDICTO}"
    echo "      (sobrevive a la prueba secuencial A SABIENDAS: $desc; solo lo delata la huella en TC)"
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
# conc_mutante <etiqueta> <casos> <archivo que altera el núcleo vivo | ''> <reversa alterada | ''>
conc_mutante() {
  local o
  guardar "$NUCLEO" nucleo-original
  [ -z "$3" ] || q "$(cat "$3")" >/dev/null
  o=$(BANCO_CONTENEDOR="$C" SOLO="$2" REVERSA_SQL="${4:-$R}" bash "$CONC" 2>&1)
  if [ "$(aplicada)" = "sí" ]; then reponer nucleo-original; else limpiar_restos >/dev/null; retirar_a_la_fuerza >/dev/null; archivo "$M" >/dev/null; fi
  [ "$(abierta)" = "abierta" ] || { limpiar_restos >/dev/null; archivo "$RE" >/dev/null; }
  limpiar_restos >/dev/null
  paso "  $1 (casos $2)" '^CONCURRENCIA asignar_cuenta_pago: [0-9]+ OK, [1-9][0-9]* FALLAS$' "$(tail -1 <<<"$o")"
  grep '✗' <<<"$o" | cut -c1-360 | sed 's/^/      /'
}
conc_mutante "núcleo sin capturar la violación de unicidad" "A" "$T/vivo/c0-sin-capturar-unicidad.sql" ""
conc_mutante "núcleo sin el candado consultivo de la solicitud" "A3 A4" "$T/vivo/c3-sin-candado-solicitud.sql" ""
conc_mutante "núcleo sin FOR SHARE de la cuenta" "D" "$T/vivo/c1-sin-for-share-cuenta.sql" ""
conc_mutante "núcleo sin FOR SHARE del contrato" "F" "$T/vivo/c2-sin-for-share-contrato.sql" ""
conc_mutante "reversa sin el candado de la tabla" "E1" "" "$T/vivo/reversa-sin-candado.sql"
conc_mutante "reversa sin exigir READ COMMITTED" "E3" "" "$T/vivo/reversa-sin-aislamiento.sql"
igual "tras los mutantes de concurrencia: aplicada, abierta, intacta y el mundo como se sembró" "sí abierta $PIEZAS $DATOS_SEMBRADO 0" "$(aplicada) $(abierta) $(foto_piezas) $(foto_datos) $(constancias)"

# ══ 13 · Mutantes del preflight ═════════════════════════════════════════════════════════════
tramo "13 · mutantes del PREFLIGHT (el mundo alterado; la migración debe negarse)"
while IFS='|' read -r id desc espera <&3; do
  paso "  $id · $desc" "^$espera" "$(mutado "$T/pre/$id.sql")"
done 3< "$T/pre/lista.txt"
igual "los mundos alterados se deshicieron: mismo catálogo que recién aplicada" "$(cat "$SALIDA/catalogo-con.txt")" "$(foto_catalogo)"

# ══ 14 · Estado final ═══════════════════════════════════════════════════════════════════════
tramo "14 · estado final: limpio, aplicada y registrada"
paso "restos fuera" '^restos limpios$' "$(limpiar_restos)"
igual "la migración está aplicada, abierta e intacta; la otra no" "sí abierta $PIEZAS no" "$(aplicada) $(abierta) $(foto_piezas) $(otra_aplicada)"
paso "registrar #1" '^NOTICE:  REGISTRO: 20261002005004 / crm_asignar_cuenta_pago \(1 sentencia: el archivo entero\)' "$(archivo "$REGISTRAR")"
paso "registrar #2 (idempotente)" '^NOTICE:  REGISTRO: 20261002005004 / crm_asignar_cuenta_pago \(1 sentencia: el archivo entero\)' "$(archivo "$REGISTRAR")"
igual "una sola fila de registro, con el archivo entero de hoy (versión|nombre|sentencias|md5)" "$VERSION|$NOMBRE|1|$MD5_MIG" \
  "$(q "select version || '|' || name || '|' || cardinality(statements) || '|' || md5(statements[1]) from supabase_migrations.schema_migrations where version = '$VERSION';")"
igual "el registro no cambia el catálogo de crm, private y public" "$(cat "$SALIDA/catalogo-con.txt")" "$(foto_catalogo)"
# La reversa no toca supabase_migrations.schema_migrations: se mide qué queda y que todo se puede rehacer.
igual "reversa con la versión ya registrada: retira" 'RETIRADA: sin asignaciones registradas; se quitaron la puerta, el núcleo, el candado y la tabla' "$(filas "$R")"
medido "tras RETIRADA, filas de la versión en schema_migrations" "$(q "select count(*) from supabase_migrations.schema_migrations where version = '$VERSION';") (la reversa no toca el registro: la versión sigue anotada como aplicada)"
paso "    registrar sin las piezas: se niega" '^ERROR:  REGISTRO: la migración 20261002005004 no está aplicada' "$(archivo "$REGISTRAR")"
igual "    se reaplica y queda como la primera vez" "ASIGNAR_CUENTA_PAGO_OK $PIEZAS" "$(filas "$M") $(foto_piezas)"
paso "    registrar #3 sobre la fila que ya estaba (mismo contenido): no falla" '^NOTICE:  REGISTRO: 20261002005004 / crm_asignar_cuenta_pago' "$(archivo "$REGISTRAR")"
igual "    sigue habiendo una sola fila de registro" '1' "$(q "select count(*) from supabase_migrations.schema_migrations where version = '$VERSION';")"
prueba_paso "prueba final" '^T10 PASS · 0 comprobaciones · NO APLICA'
igual "el mundo es el sembrado, sin constancias, sin sellos y sin storage.objects" "$DATOS_SEMBRADO 0 sin storage.objects" \
  "$(foto_datos) $(constancias) $(q "select case when to_regclass('storage.objects') is null then 'sin storage.objects' else 'CON storage.objects' end;")"
igual "trinquetes al final: los de antes de la migración" "$(cat "$SALIDA/trinquetes-sin.txt")" "$(trinquetes)"
echo "    estado final del banco: asignar=$(aplicada) puerta=$(abierta) la otra=$(otra_aplicada) constancias=$(constancias) registro=$(q "select count(*) from supabase_migrations.schema_migrations where version = '$VERSION';") bitácora=$(bitacora) filas"

# ── Resumen ──────────────────────────────────────────────────────────────────────────────────
echo "── resumen por tramo"
printf '%-92s %5s %5s %14s\n' "tramo" "✓" "✗" "comprobaciones"
i=0
while [ $i -le $IT ]; do
  printf '%-92s %5s %5s %14s  %s\n' "${TRAMOS[$i]}" "${T_OK[$i]}" "${T_KO[$i]}" "${T_ASERT[$i]}" "$([ "${T_KO[$i]}" -eq 0 ] && echo PASS || echo FAIL)"
  i=$((i + 1))
done
if [ "$FALLOS" -eq 0 ]; then echo "FIN ciclo asignar cuenta de pago: TODO ✓"; else echo "FIN ciclo asignar cuenta de pago: $FALLOS ✗"; fi
[ "$FALLOS" -eq 0 ]
