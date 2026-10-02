#!/usr/bin/env bash
# Ciclo completo de 20261001233019_crm_cuentas_pago_motivo_y_rezago en el BANCO Docker propio.
# Nunca contra producción: todo va por `docker exec` contra el contenedor del banco. No edita ningún
# archivo del repositorio: los mutantes y las copias alteradas de la migración viven en un directorio
# temporal.
#
#   BANCO_CONTENEDOR=avancecorp-cuentas-pago-20261001 bash supabase/scripts/cuentas-pago-rezago/ciclo.sh
#   BANCO_CONTENEDOR=…                                bash supabase/scripts/cuentas-pago-rezago/ciclo.sh preparar
#
# «preparar» se queda en el tramo 1: deja el banco sembrado y comprobado en el estado ANTES (no
# necesita la migración). VERBOSO=1 enseña la salida entera de cada corrida de la prueba.
# REZAGO_SALIDA=<carpeta> conserva ahí los JSON del ensayo, las fotos de trinquetes y los mutantes.
#
# El banco se monta antes con supabase/scripts/potencial-lead/banco/montar-banco.sh (esquema de
# producción, sin datos). Cada paso se compara con lo que se espera (✓ / ✗); al final hay una tabla
# por tramo y el ciclo sale con 1 si hubo algún ✗. La migración, las reversas, la carga suelta, el
# ensayo y el registrador van en UN mensaje y como postgres, igual que en producción
# (`supabase db query --file`); la prueba va sentencia a sentencia y como supabase_admin (ver su cabecera).
#
# Tramos:
#    0 · punto de partida: derivados, registrador y ensayo al día con el archivo de hoy; copias alteradas en un
#        directorio temporal; restos fuera, y el banco en ANTES
#    1 · siembra → prueba ANTES → foto; censo sin funciones; trinquetes SIN la migración
#    2 · lo que debe NEGARSE o no hacer nada en ANTES: vincular-rezago, registrar, las dos reversas; el ENSAYO en ANTES: PASA
#    3 · el ENSAYO en sus otros veredictos: INCOMPLETO (falta algo que probar) y FALLA (ensayos mutantes); el banco queda igual
#    4 · lo que debe CANCELAR la migración entera: conciliación del perfil, tope de candidatos, cuenta a medio
#        registrar, el bloqueo vivo con otro cuerpo (huella) y otro aislamiento que READ COMMITTED
#    5 · aislamiento a DOS sesiones: una segunda cuenta registrada a mitad de la carga (confirmada mientras la carga
#        espera el candado, o registrada y confirmada entre su fotografía y el candado); el archivo real no vincula,
#        el mutante sin la guarda (en REPEATABLE READ y en SERIALIZABLE) sí
#    6 · pagos en vuelo frente a la migración, a dos sesiones: de un contrato ok y de uno una_cuenta, en los dos órdenes
#    7 · pagos en vuelo frente al ENSAYO, a dos sesiones (en ANTES): espera y PASA; con un pago lento, FALLA por lock timeout
#    8 · migración (con filas de conciliación que NO deben cancelarla) → prueba DESPUÉS; censo; trinquetes CON:
#        idénticos; y una conexión REAL de la API (authenticator) con y sin claims
#    9 · migración otra vez (idempotencia)
#   10 · el ENSAYO con la migración aplicada: PASA, INCOMPLETO; un ensayo mutante no llega a correr
#   11 · reversa → ANTES; reversa repetida
#   12 · volver a aplicar
#   13 · huellas y guardas: con una de las cuatro funciones vivas alterada se niegan migración, reversas,
#        vincular-rezago y registrar; las demás guardas de sus preflight; y los cuatro archivos en otro aislamiento
#   14 · negativas de reversa.sql: pago sellado, cambio de cuenta, PDF (trabajo y archivo), disparadores de sello apagados
#   15 · pagos en vuelo frente a reversa.sql, a dos sesiones: espera y se niega (también con un cambio de cuenta o un
#        PDF en vuelo); al revés, el pago espera y es rechazado; el mutante sin la guarda borra el vínculo de un
#        contrato ya pagado; y el ENSAYO con un pago lento
#   16 · reversa solo del código: vínculos intactos y pagables; reaplicar; con un pago ya hecho; después la reversa completa
#   17 · vincular-rezago: a dos sesiones (el real y el mutante sin la guarda); vincula solo lo que pasó a una_cuenta, con
#        su marca del día; repetirlo no hace nada; la reversa no lo toca
#   18 · mutantes del bloqueo ANTERIOR (prueba ANTES) y de la MIGRACIÓN real (prueba DESPUÉS, pre/postflight, postcondiciones)
#   19 · tiempos de 200 pagos con cada bloqueo (alternados) y estado final: migración aplicada y registrada (×2)
#
# Los tramos a dos sesiones (5, 6, 7, 15 y parte del 17) lanzan una sesión en segundo plano que se queda EN VUELO
# (transacción abierta, dormida en pg_sleep) y miran en pg_stat_activity/pg_locks quién espera a quién. Los tiempos
# que comparan son anchos a propósito: «no esperó» = menos de 2 s; «esperó» = entre 2 y 5 s de un vuelo de 4 s;
# «se canceló» = a los 5 s (lock_timeout) de un vuelo de 8 s.
set -uo pipefail
C="${BANCO_CONTENEDOR:-avancecorp-cuentas-pago-20261001}"
D="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # …/supabase
P="$D/scripts/cuentas-pago-rezago"
M="$D/migrations/20261001233019_crm_cuentas_pago_motivo_y_rezago.sql"
R="$P/reversa.sql"
RC="$P/reversa-solo-codigo.sql"
VR="$P/vincular-rezago.sql"
ENSAYO="$P/ensayo-prod-sin-escribir.sql"
REGISTRAR="$P/registrar.sql"
DERIVADOS="$P/generar-derivados.py"
CENSO="$P/censo.sql"
CENSO_SIN="$P/censo-sin-funciones.sql"
TRINQUETES="$D/scripts/potencial-lead/banco/trinquetes.sql"
SIEMBRA="$P/siembra.sql"
PRUEBA="$P/test-cuentas-pago-rezago.sql"
VERSION='20261001233019'
MARCA='migracion:rezago-vinculos:20261001'
MD5_ANTERIOR='5efb8619e4342763ae77df2ee0bb1f61'
# Lo sembrado que el ciclo nombra (ver siembra.sql).
ADMIN='c9e00000-0000-4000-8000-000000000001'
OPER='c9e00000-0000-4000-8000-000000000002'
CLIENTE_C='c9e00000-0000-4000-8000-000000000013'   # REZAGO-03 (PEN)
CLIENTE_D='c9e00000-0000-4000-8000-000000000014'   # REZAGO-04 (USD)
CLIENTE_H='c9e00000-0000-4000-8000-000000000018'   # REZAGO-09 (USD), solo tiene cuenta PEN
CLIENTE_J='c9e00000-0000-4000-8000-000000000020'   # REZAGO-11 (USD), no tiene ninguna cuenta
REZAGO_03='c9ed0000-0000-4000-8000-000000000003'
REZAGO_07='c9ed0000-0000-4000-8000-000000000007'   # varias_cuentas: bloqueado antes y después
CUOTA_0301='c9ee0000-0000-4000-8000-000000000301'
CUOTA_0302='c9ee0000-0000-4000-8000-000000000302'
CUOTA_0901='c9ee0000-0000-4000-8000-000000000901'
CUOTA_1101='c9ee0000-0000-4000-8000-000000001101'
CUOTA_DE_ANTES='c9ee0000-0000-4000-8000-000000000400'   # la que REZAGO-04 ya tenía pagada, sin sello
CUENTA_04='c9ec0000-0000-4000-8000-000000000004'   # la única PEN activa de C: la que vincula la carga
CUENTA_05='c9ec0000-0000-4000-8000-000000000005'   # la PEN inactiva de C
REZAGO_06='c9ed0000-0000-4000-8000-000000000006'
CUENTA_09='c9ec0000-0000-4000-8000-000000000009'   # la única PEN de E (REZAGO-05 y REZAGO-06)
# Lo que el ciclo crea y retira.
CUENTA_H_USD='c9ec0000-0000-4000-8000-0000000000d1'
CUENTA_J_USD='c9ec0000-0000-4000-8000-0000000000d2'
CUENTA_A_MEDIAS='c9ec0000-0000-4000-8000-0000000000aa'
PDF_JOB='c9eb0000-0000-4000-8000-000000000001'
CUENTA_SEGUNDA='c9ec0000-0000-4000-8000-0000000000ab'     # la segunda cuenta PEN que OTRA sesión le registra a C a mitad de la carga
CUENTA_J_SEGUNDA='c9ec0000-0000-4000-8000-0000000000ac'   # lo mismo para J (USD), frente a vincular-rezago.sql
# Más de lo sembrado, para los tramos a dos sesiones y el ensayo.
ANALISTA='c9e00000-0000-4000-8000-000000000004'
CUENTA_01='c9ec0000-0000-4000-8000-000000000001'    # la cuenta vinculada de REZAGO-01 (ok)
CUOTA_0101='c9ee0000-0000-4000-8000-000000000101'   # REZAGO-01, cuota 1: la que el ENSAYO elige como «ya estaba bien»
CUOTA_0102='c9ee0000-0000-4000-8000-000000000102'
REZAGO_11='c9ed0000-0000-4000-8000-000000000011'
# Otro aislamiento por defecto para UNA sesión (lo que haría un ALTER ROLE … SET o un cliente configurado así).
RR='-c default_transaction_isolation=repeatable\ read'
SER='-c default_transaction_isolation=serializable'
RU='-c default_transaction_isolation=read\ uncommitted'
FALLOS=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SALIDA="${REZAGO_SALIDA:-$T}"; mkdir -p "$SALIDA"

# ── Contabilidad por tramo ───────────────────────────────────────────────────────────────────
TRAMOS=(); T_OK=(); T_KO=(); T_ASERT=(); IT=-1
tramo() { IT=$((IT + 1)); TRAMOS[$IT]="$1"; T_OK[$IT]=0; T_KO[$IT]=0; T_ASERT[$IT]=0; echo "── $1"; }
anota() { if [ "$1" = ok ]; then T_OK[$IT]=$((${T_OK[$IT]} + 1)); else T_KO[$IT]=$((${T_KO[$IT]} + 1)); FALLOS=$((FALLOS + 1)); fi; }
# paso <etiqueta> <lo que se espera (grep -E)> <resultado>
paso() {
  local marca='✓'
  if grep -Eq -- "$2" <<<"$3"; then anota ok; else marca='✗'; anota ko; fi
  printf '%s %-60s %s\n' "$marca" "$1" "$3"
}
# igual <etiqueta> <esperado> <obtenido>
igual() {
  if [ "$2" = "$3" ]; then anota ok; printf '✓ %-60s %s\n' "$1" "igual"
  else anota ko; printf '✗ %-60s\n    esperaba: %s\n    vino:     %s\n' "$1" "$2" "$3"; fi
}
SIN_ERROR='^(NOTICE:|\(sin avisos\))'

# ── Ayudantes ────────────────────────────────────────────────────────────────────────────────
# Q_OPCIONES = opciones de arranque de la sesión (p. ej. otro aislamiento por defecto) · Q_NOMBRE = su
# application_name (para ver en pg_stat_activity quién espera a quién).
q() { docker exec -i -e PGPASSWORD=postgres -e PGOPTIONS="${Q_OPCIONES:-}" -e PGAPPNAME="${Q_NOMBRE:-ciclo}" "$C" psql -U "${2:-postgres}" -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "$1" 2>&1; }
# La última línea de una consulta, o su primer ERROR (así un fallo nunca pasa por un resultado).
ultima() {
  local o; o=$(q "$1" "${2:-postgres}")
  if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-260; else tail -1 <<<"$o"; fi
}
# Un archivo en UN mensaje: su primer ERROR, o su último NOTICE propio (no los «does not exist,
# skipping» de un DROP IF EXISTS), o «(sin avisos)».
msg() {
  local o; o=$(q "$(cat "$1")")
  if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-420
  else o=$(grep -o 'NOTICE:.*' <<<"$o" | grep -v 'does not exist, skipping' | tail -1 | cut -c1-420); echo "${o:-(sin avisos)}"; fi
}
# La prueba en un modo (antes | despues | solo_codigo), o un archivo de prueba alterado ($2): su veredicto o su primer FALLO.
prueba() {
  local o; o=$(docker exec -i -e PGPASSWORD=postgres "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -v modo="$1" -qAt < "${2:-$PRUEBA}" 2>&1)
  [ "${VERBOSO:-0}" = 1 ] && sed 's/^/      /' <<<"$o" >&2
  if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-330; else grep -E -o '^REZAGO (antes|despues|solo_codigo) OK.*' <<<"$o" | tail -1; fi
}
# Corre la prueba, la da por buena si su veredicto es OK y suma sus comprobaciones al tramo.
prueba_paso() {
  local r n; r=$(prueba "$2")
  paso "$1" "^REZAGO $2 OK" "$r"
  n=$(sed -n 's/^REZAGO [a-z_]* OK · \([0-9]*\) comprobaciones.*/\1/p' <<<"$r")
  T_ASERT[$IT]=$((${T_ASERT[$IT]} + ${n:-0}))
}

# La foto del banco en una línea: cuerpo y comentario del bloqueo, las funciones nuevas (cuántas, sus
# cuerpos y permisos), la huella de TODAS las columnas de vínculos, cuentas, contratos y cuotas,
# sellos, cambios, conciliación, PDF, el estado de los disparadores y el registro de la versión.
estado() {
  ultima "set timezone = 'UTC';
     select 'bloqueo=' || (select md5(p.prosrc) || '/' || md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) from pg_proc p where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure)
         || ' nuevas=' || (select count(*) || ':' || md5(coalesce(string_agg(n.nspname || '.' || p.proname || md5(p.prosrc) || coalesce(p.proacl::text, ''), ',' order by n.nspname, p.proname), ''))
                           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                           where (n.nspname, p.proname) in (('private', 'cuenta_pago_diagnostico'), ('private', 'cuentas_pago_motivos_autorizado'), ('crm', 'cuentas_pago_motivos_fn')))
         || ' vinculos=' || (select count(*) || ':' || md5(coalesce(string_agg(md5(to_jsonb(x)::text), ',' order by x.id), '')) from crm.contrato_cuentas_pago x)
         || ' cuentas=' || (select count(*) || ':' || md5(coalesce(string_agg(md5(to_jsonb(x)::text), ',' order by x.id), '')) from crm.cuentas_bancarias x)
         || ' contratos=' || (select count(*) || ':' || md5(coalesce(string_agg(md5(to_jsonb(x)::text), ',' order by x.id), '')) from public.contratos x)
         || ' cuotas=' || (select count(*) || ':' || md5(coalesce(string_agg(md5(to_jsonb(x)::text), ',' order by x.id), '')) from public.cronograma_pagos x)
         || ' sellos=' || (select count(*) from crm.cuotas_cuenta_pagada)
         || ' cambios=' || (select count(*) from crm.contrato_cuenta_pago_cambios)
         || ' conciliacion=' || (select count(*) from private.conciliacion_cuentas_p0xx)
         || ' pdf=' || ((select count(*) from private.contrato_pdf_jobs) + (select count(*) from private.contrato_pdfs))
         || ' disparadores=' || (select md5(string_agg(t.tgrelid::regclass::text || t.tgname || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname))
                                 from pg_trigger t
                                 where not t.tgisinternal
                                   and t.tgrelid in ('public.cronograma_pagos'::regclass, 'crm.contrato_cuentas_pago'::regclass,
                                                     'crm.cuentas_bancarias'::regclass, 'public.contratos'::regclass, 'crm.cuotas_cuenta_pagada'::regclass))
         || ' registro=' || (select count(*) from supabase_migrations.schema_migrations where version = '$VERSION');"
}
# Conteos: vínculos, rastro, bitácora (total y altas de vínculo) y filas repetidas.
conteos() {
  q "select 'vinculos=' || (select count(*) from crm.contrato_cuentas_pago)
         || ' contratos_con_dos_vinculos=' || (select count(*) - count(distinct x.contrato_id) from crm.contrato_cuentas_pago x)
         || ' rastro=' || (select count(*) from private.backfill_cuentas_p0xx b)
         || ' rastro_vigente=' || (select count(*) from private.backfill_cuentas_p0xx b where b.revertida_en is null)
         || ' contratos_con_dos_rastros_vigentes=' || (select count(*) - count(distinct b.contrato_id) from private.backfill_cuentas_p0xx b where b.revertida_en is null)
         || ' bitacora=' || (select count(*) from public.audit_log)
         || ' altas_de_vinculo_en_bitacora=' || (select count(*) from public.audit_log a where a.tabla = 'crm.contrato_cuentas_pago' and a.operacion = 'INSERT');"
}
# «vigentes revertidos» del rastro de la carga de la migración.
rastro() { q "select count(*) filter (where b.revertida_en is null) || ' ' || count(b.revertida_en) from private.backfill_cuentas_p0xx b where b.marca_actor = '$MARCA';"; }
# Lo mismo para las cargas posteriores (vincular-rezago.sql: una marca por día).
rastro_cargas() { q "select count(*) filter (where b.revertida_en is null) || ' ' || count(b.revertida_en) from private.backfill_cuentas_p0xx b where b.marca_actor like 'carga:rezago-vinculos:%';"; }
aplicada() { q "select (to_regprocedure('private.cuenta_pago_diagnostico(uuid[])') is not null)::int;"; }
sembrar() { local o; o=$(q "$(cat "$SIEMBRA")"); if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-260; else grep -m1 -o 'SIEMBRA .*' <<<"$o"; fi; }
# El censo por caso, por una consulta suelta (sin funciones nuevas).
censo() {
  q "select string_agg(s.caso || '=' || s.n, ' ' order by s.caso) from (
       select case when l.id is not null and cb.cliente_id = ct.cliente_id and cb.moneda = ct.moneda then 'ok'
                   when l.id is not null then 'cuenta_no_corresponde'
                   when a.en_moneda = 1 then 'una_cuenta' when a.en_moneda >= 2 then 'varias_cuentas'
                   when a.otra_moneda >= 1 then 'otra_moneda' else 'sin_cuenta' end as caso, count(*) as n
       from public.contratos ct
       left join crm.contrato_cuentas_pago l on l.contrato_id = ct.id
       left join crm.cuentas_bancarias cb on cb.id = l.cuenta_bancaria_id
       cross join lateral (select count(*) filter (where x.moneda = ct.moneda) as en_moneda, count(*) filter (where x.moneda <> ct.moneda) as otra_moneda
                           from crm.cuentas_bancarias x where x.cliente_id = ct.cliente_id and x.activa) a
       group by 1) s;"
}
# La foto de los trinquetes (private.assert_*() y contadores crudos), como en potencial-lead/banco/ciclo-fase3a.sh.
trinquetes() { docker exec -i -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -qAt < "$TRINQUETES" 2>&1 | sed 's/^.*NOTICE:  //'; }
# El ensayo de producción: la línea ENTERA de su primer ERROR (ahí va el JSON). $1 = otro archivo (un ensayo mutante).
ensayo() { q "$(cat "${1:-$ENSAYO}")" | grep -m1 -o 'ERROR:.*'; }
# El ensayo después de un SQL previo ($1) en SU MISMA transacción: su error final lo deshace todo, también lo previo.
ensayo_tras() { q "begin; $1 $(sin_transaccion "${2:-$ENSAYO}")" | grep -m1 -o 'ERROR:.*'; }
# El JSON del ensayo (por la entrada estándar) en una línea: veredicto, lo vinculado, cuántos pagos e identidades
# salieron como se esperaba, la conexión, los fallos y lo que quedó sin probar.
resumen_ensayo() {
  python3 -c '
import json, sys
t = sys.stdin.read().strip()
if "ENSAYO_DESHECHO >> " not in t:
    print("SIN ENSAYO_DESHECHO: " + t[:300]); sys.exit()
j = json.loads(t.split("ENSAYO_DESHECHO >> ", 1)[1])
x = [p["como_se_esperaba"] for p in j["pagos"] + j["identidad"]]
print("veredicto=%s · todo_como_se_esperaba=%s · vinculados=%s · %d como se esperaba, %d no, %d sin probar · conexion=%s/%s · fallos=%s · sin_probar=%s" % (
    j["veredicto"], str(j["todo_como_se_esperaba"]).lower(), j["carga"]["vinculados"],
    x.count(True), x.count(False), x.count(None), j["conexion"]["session_user"], j["conexion"]["current_user"],
    json.dumps(j["fallos"], ensure_ascii=False), json.dumps(j["sin_probar"], ensure_ascii=False)))'
}

# SOLO BANCO. Deshace lo que el ciclo (o una corrida que murió a medias) dejó CONFIRMADO sobre el
# mundo sembrado: un pago y su sello, una cuota insertada, un cambio de cuenta, un PDF, filas de
# conciliación, las cuentas y los vínculos del tramo de vincular-rezago, un disparador de sello
# apagado. Va como supabase_admin y en modo réplica porque sellos, historial y PDF no se borran (sus
# disparadores lo impiden, con razón). Solo toca filas del mundo sembrado (c9e…) y NO borra nada de
# la bitácora (public.audit_log es de solo añadir: lo que el ciclo confirma se queda ahí).
limpiar_restos() {
  ultima "alter table public.cronograma_pagos enable trigger trg_cronograma_pagos_20_sellar_cuenta_insert;
     alter table public.cronograma_pagos enable trigger trg_cronograma_pagos_20_sellar_cuenta_update;
     set session_replication_role = replica;
     delete from crm.cuotas_cuenta_pagada where contrato_id::text like 'c9ed0000-%';
     delete from crm.contrato_cuenta_pago_cambios where contrato_id::text like 'c9ed0000-%';
     delete from private.contrato_pdfs where contrato_id::text like 'c9ed0000-%';
     delete from private.contrato_pdf_jobs where contrato_id::text like 'c9ed0000-%';
     delete from private.conciliacion_cuentas_p0xx where cliente_id::text like 'c9e00000-%';
     delete from public.cronograma_pagos where contrato_id::text like 'c9ed0000-%' and id::text not like 'c9ee0000-%';
     update public.cronograma_pagos
        set estado = 'pendiente', fecha_pago_real = null, monto_pagado = null, registrado_por = null
      where id::text like 'c9ee0000-%' and id <> '$CUOTA_DE_ANTES'
        and (estado <> 'pendiente' or fecha_pago_real is not null or monto_pagado is not null or registrado_por is not null);
     update public.cronograma_pagos
        set estado = 'pagado', fecha_pago_real = date '2026-09-05', monto_pagado = 100, registrado_por = null
      where id = '$CUOTA_DE_ANTES'
        and (estado <> 'pagado' or fecha_pago_real is distinct from date '2026-09-05' or monto_pagado is distinct from 100 or registrado_por is not null);
     delete from crm.contrato_cuentas_pago l using private.backfill_cuentas_p0xx b
      where b.tipo = 'vinculo' and b.fila_id = l.id and b.marca_actor like 'carga:rezago-vinculos:%' and l.contrato_id::text like 'c9ed0000-%';
     delete from private.backfill_cuentas_p0xx where marca_actor like 'carga:rezago-vinculos:%' and contrato_id::text like 'c9ed0000-%';
     delete from crm.cuentas_bancarias where id in ('$CUENTA_H_USD', '$CUENTA_J_USD', '$CUENTA_A_MEDIAS', '$CUENTA_SEGUNDA', '$CUENTA_J_SEGUNDA');
     update crm.contrato_cuentas_pago set cuenta_bancaria_id = '$CUENTA_04'
      where contrato_id = '$REZAGO_03' and cuenta_bancaria_id <> '$CUENTA_04';
     select 'restos limpios';" supabase_admin
}
quitar_registro() { ultima "delete from supabase_migrations.schema_migrations where version = '$VERSION'; select 'registro fuera';"; }
# El rastro ya revertido de corridas anteriores del ciclo (solo estorba para leer los conteos).
quitar_rastro_revertido() { ultima "delete from private.backfill_cuentas_p0xx where marca_actor = '$MARCA' and revertida_en is not null; select 'rastro revertido fuera';"; }

# Una sesión de Operaciones por la API, en un mensaje: claims en las dos formas (el auth.uid() de la
# imagen lee request.jwt.claim.sub; el de producción, request.jwt.claims), SET ROLE y la RPC.
# pagar = CONFIRMADO · intento_pago = lo mismo pero deshecho (para saber si un contrato se puede pagar).
sesion_oper() {
  echo "do \$s\$ begin
       perform set_config('request.jwt.claim.sub', '$OPER', true);
       perform set_config('request.jwt.claim.role', 'authenticated', true);
       perform set_config('request.jwt.claims', json_build_object('sub', '$OPER', 'role', 'authenticated')::text, true);
     end \$s\$;
     set local role authenticated;"
}
pagar() {
  ultima "begin; $(sesion_oper)
     select coalesce(crm.registrar_pago_con_cuenta('$1', (now() at time zone 'America/Lima')::date, 100, null)::text, 'no se pagó');
     reset role; commit;"
}
intento_pago() {
  ultima "begin; $(sesion_oper)
     select coalesce(crm.registrar_pago_con_cuenta('$1', (now() at time zone 'America/Lima')::date, 100, null)::text, 'no se pagó');
     reset role; rollback;"
}
sello() { q "select coalesce((select cuenta_bancaria_id || '|' || origen from crm.cuotas_cuenta_pagada where cuota_id = '$1'), 'sin sello');"; }
# Un cambio de cuenta CONFIRMADO en REZAGO-03, escrito a mano: la puerta real
# (crm.cambiar_cuenta_pago_contratos) exige un respaldo en storage.objects, que esta imagen no
# tiene. Va la fila del historial y, en la MISMA transacción, el vínculo hacia la otra cuenta PEN
# del cliente (así lo exige private.trg_contrato_cuenta_pago_inmutable).
cambiar_cuenta() {
  ultima "begin;
     insert into crm.contrato_cuenta_pago_cambios
       (solicitud_id, contrato_id, cliente_id, cuenta_anterior_id, cuenta_nueva_id, motivo, respaldo_ruta, cambiado_por)
     values ('c9ea0000-0000-4000-8000-000000000001', '$REZAGO_03', '$CLIENTE_C', '$CUENTA_04', '$CUENTA_05',
             'Cambio ficticio para el ciclo del banco', '$CLIENTE_C/c9ea0000-0000-4000-8000-000000000002.pdf', '$ADMIN');
     update crm.contrato_cuentas_pago set cuenta_bancaria_id = '$CUENTA_05' where contrato_id = '$REZAGO_03';
     commit;
     select count(*) || ' cambio registrado' from crm.contrato_cuenta_pago_cambios where contrato_id = '$REZAGO_03';"
}
conciliar() { ultima "insert into private.conciliacion_cuentas_p0xx (clase, cliente_id, moneda, motivo) values ('$1', '$2', '$3', '$4'); select count(*) || ' filas de conciliación' from private.conciliacion_cuentas_p0xx;"; }
quitar_conciliacion() { ultima "delete from private.conciliacion_cuentas_p0xx where cliente_id::text like 'c9e00000-%'; select count(*) || ' filas de conciliación' from private.conciliacion_cuentas_p0xx;"; }
# Lanza un archivo de migración ($1) mientras OTRA sesión tiene una cuenta a medio registrar (su
# alta sin confirmar, que al final deshace). Devuelve «<segundos> s · <resultado>».
con_cuenta_a_medias() {
  ( q "begin;
       insert into crm.cuentas_bancarias (id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci, origen, creado_por)
       values ('$CUENTA_A_MEDIAS', '$CLIENTE_C', 'PEN', 'BCP', 'ahorros', '19199000000099', '00219900000000000099', 'contrato', '$ADMIN');
       select pg_sleep(8);
       rollback;" >/dev/null 2>&1 ) &
  local otra=$! t0 t1 r
  sleep 1.5
  t0=$(date +%s); r=$(msg "$1"); t1=$(date +%s)
  wait "$otra"
  echo "$((t1 - t0)) s · $r"
}
# ── Dos sesiones ─────────────────────────────────────────────────────────────────────────────
# Cada sesión lleva su application_name (Q_NOMBRE) y así se ve en pg_stat_activity quién espera a quién.
# cronometrado <comando…> → «<segundos, un decimal> s · <su salida>»
ahora() { python3 -c 'import time; print("%.2f" % time.time())'; }
md5_de() { python3 -c 'import hashlib, sys; print(hashlib.md5(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }
cronometrado() {
  local t0 r; t0=$(ahora); r=$("$@")
  echo "$(python3 -c 'import sys, time; print("%.1f" % (time.time() - float(sys.argv[1])))' "$t0") s · $r"
}
# Espera a que la sesión $1 esté EN VUELO: con lo suyo hecho y sin confirmar, dentro de su pg_sleep. Si no llega, ✗.
en_vuelo() {
  local i
  for i in $(seq 1 40); do
    [ "$(q "select count(*) from pg_stat_activity where application_name = '$1' and wait_event = 'PgSleep';" supabase_admin)" = 1 ] && return 0
    sleep 0.1
  done
  anota ko; printf '✗ %-60s %s\n' "la sesión «$1» no llegó a quedar en vuelo" "(sigue el tramo, pero lo que venga no vale)"
}
# Quién espera a quién AHORA: «A espera a B [tipo/evento · fila de <tabla> | tabla <tabla> en <modo>]».
quien_espera() {
  q "select coalesce(string_agg(a.application_name || ' espera a '
              || coalesce((select string_agg(distinct b.application_name, '+') from pg_stat_activity b where b.pid = any(pg_blocking_pids(a.pid))), '?')
              || ' [' || coalesce(a.wait_event_type, '') || '/' || coalesce(a.wait_event, '')
              || coalesce(' · fila de ' || (select string_agg(distinct t.relation::regclass::text, ',') from pg_locks t where t.pid = a.pid and t.locktype = 'tuple'), '')
              || coalesce(' · tabla ' || (select string_agg(distinct t.relation::regclass::text || ' en ' || t.mode, ',') from pg_locks t where t.pid = a.pid and t.locktype = 'relation' and not t.granted), '')
              || ']', ' · ' order by a.application_name), 'nadie espera')
     from pg_stat_activity a
     where a.datname = current_database() and a.pid <> pg_backend_pid() and cardinality(pg_blocking_pids(a.pid)) > 0;" supabase_admin
}
# Lo mismo, insistiendo unos segundos hasta que esperen al menos $1 sesiones (por defecto, una): la sesión recién
# lanzada tarda en llegar a su candado.
ver_espera() {
  local i r='nadie espera' n="${1:-1}"
  for i in $(seq 1 30); do
    r=$(quien_espera)
    [ "$r" != 'nadie espera' ] && [ "$(grep -o ' espera a ' <<<"$r" | wc -l | tr -d ' ')" -ge "$n" ] && break
    sleep 0.1
  done
  echo "$r"
}
# Los candados de TABLA concedidos a la sesión $1 sobre las tablas del pago y de la carga («tabla:modo»).
candados_de() {
  q "select coalesce(string_agg(distinct l.relation::regclass::text || ':' || l.mode, ' ' order by l.relation::regclass::text || ':' || l.mode), '(ninguno)')
     from pg_locks l join pg_stat_activity a on a.pid = l.pid
     where a.application_name = '$1' and l.locktype = 'relation' and l.granted
       and l.relation in ('crm.cuentas_bancarias'::regclass, 'crm.contrato_cuentas_pago'::regclass, 'public.contratos'::regclass,
                          'public.cronograma_pagos'::regclass, 'crm.cuotas_cuenta_pagada'::regclass);" supabase_admin
}
# Los modos de candado de TABLA que la sesión $1 tiene sobre la tabla $2.
candados_sobre() {
  q "select coalesce(string_agg(distinct l.mode, ',' order by l.mode), '(ninguno)')
     from pg_locks l join pg_stat_activity a on a.pid = l.pid
     where a.application_name = '$1' and l.locktype = 'relation' and l.granted and l.relation = '$2'::regclass;" supabase_admin
}
# Un pago por la RPC, como Operaciones, que se queda EN VUELO $2 segundos después del UPDATE y entonces confirma.
pago_en_vuelo() {
  Q_NOMBRE=pago-en-vuelo q "begin; $(sesion_oper)
     select coalesce(crm.registrar_pago_con_cuenta('$1', (now() at time zone 'America/Lima')::date, 100, null)::text, 'no se pagó');
     reset role; select pg_sleep($2); commit;"
}
# Un intento de pago que el bloqueo RECHAZA, dentro de una transacción que sigue abierta $2 segundos.
pago_rechazado_en_vuelo() {
  Q_NOMBRE=pago-rechazado q "begin; $(sesion_oper)
     do \$p\$ begin
       perform crm.registrar_pago_con_cuenta('$1', (now() at time zone 'America/Lima')::date, 100, null);
       raise notice 'PAGADO';
     exception when others then
       raise notice 'RECHAZADO: % %', sqlstate, sqlerrm;
     end \$p\$;
     reset role; select pg_sleep($2); commit;"
}
# Un cambio de cuota que NO es un pago (la marca de notificación), sin confirmar $2 segundos y al final deshecho:
# toma la fila del contrato FOR UPDATE igual que un pago (primer trigger de cuotas) y el bloqueo no lo rechaza.
cambio_en_vuelo() {
  Q_NOMBRE=cambio-en-vuelo q "begin; update public.cronograma_pagos set notif_pago_enviada_en = now() where id = '$1'; select pg_sleep($2); rollback;"
}
# Un cambio de cuenta de REZAGO-03 (cuenta 04 → 05) que tarda $1 segundos en confirmar. Va escrito a mano (la puerta
# real exige un respaldo en storage.objects, que esta imagen no tiene), pero toma los candados de la puerta real y en
# su orden (private.cambiar_cuenta_pago_contratos_autorizado): cuenta nueva FOR SHARE → contrato FOR SHARE → vínculo FOR UPDATE.
cambio_cuenta_en_vuelo() {
  Q_NOMBRE=cambio-de-cuenta q "begin;
     select 1 from crm.cuentas_bancarias where id = '$CUENTA_05' for share;
     select 1 from public.contratos where id = '$REZAGO_03' for share;
     select 1 from crm.contrato_cuentas_pago where contrato_id = '$REZAGO_03' for update;
     insert into crm.contrato_cuenta_pago_cambios
       (solicitud_id, contrato_id, cliente_id, cuenta_anterior_id, cuenta_nueva_id, motivo, respaldo_ruta, cambiado_por)
     values ('c9ea0000-0000-4000-8000-000000000001', '$REZAGO_03', '$CLIENTE_C', '$CUENTA_04', '$CUENTA_05',
             'Cambio ficticio para el ciclo del banco', '$CLIENTE_C/c9ea0000-0000-4000-8000-000000000002.pdf', '$ADMIN');
     update crm.contrato_cuentas_pago set cuenta_bancaria_id = '$CUENTA_05' where contrato_id = '$REZAGO_03';
     select pg_sleep($1); commit;"
}
# Un PDF en curso de REZAGO-03 (el trabajo en private.contrato_pdf_jobs) que tarda $1 segundos en confirmar.
pdf_en_vuelo() {
  Q_NOMBRE=pdf-en-vuelo q "begin;
     insert into private.contrato_pdf_jobs (id, contrato_id, storage_path, nombre_archivo, snapshot, solicitado_por)
     values ('$PDF_JOB', '$REZAGO_03', '$REZAGO_03/v2/$PDF_JOB/contrato.pdf', 'contrato-ficticio-del-ciclo.pdf', '{}'::jsonb, '$ADMIN');
     select pg_sleep($1); commit;"
}
# OTRA sesión registra una cuenta más ($1) al cliente $2 en la moneda $3: la inserta ya y la CONFIRMA a los $4
# segundos. $5 = dos dígitos para que su número y su CCI no repitan los de otra.
registra_cuenta() {
  Q_NOMBRE=registra-cuenta q "begin;
     insert into crm.cuentas_bancarias (id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci, origen, creado_por)
     values ('$1', '$2', '$3', 'Interbank', 'ahorros', '898990000000$5', '003899000000000000$5', 'portal', '$ADMIN');
     select pg_sleep($4); commit;" >/dev/null 2>&1
}
# Un archivo ($1) corrido como transacción EN VUELO: todo su cuerpo, $2 segundos abierta, y entonces confirma.
archivo_en_vuelo() { q "begin; $(sin_transaccion "$1") select pg_sleep($2); commit;"; }
# De vuelta al estado ANTES tras un escenario que confirmó un pago, una cuenta o la migración: retira lo confirmado,
# revierte la migración si quedó aplicada (y suma a «revertidos» los vínculos que la reversa diga que borró) y compara la foto.
volver_a_antes() {
  local r n
  paso "$1 · se retira lo confirmado" '^restos limpios$' "$(limpiar_restos)"
  if [ "$(aplicada)" = 1 ]; then
    r=$(msg "$R"); paso "$1 · reversa" '^NOTICE:  REVERSA: [0-9]+ vínculos de la carga borrados' "$r"
    n=$(sed -n 's/^NOTICE:  REVERSA: \([0-9]*\) vínculos.*/\1/p' <<<"$r"); revertidos=$((revertidos + ${n:-0}))
  fi
  paso "$1 · rastro: ninguno vigente y los revertidos que tocan" "^0 ${revertidos}\$" "$(rastro)"
  igual "$1 · el banco vuelve a ANTES" "$e_antes" "$(estado)"
}

# Copias ALTERADAS de los archivos del PRIMARY, en el directorio temporal (nunca en el repositorio):
#   · migración, reversa.sql y vincular-rezago.sql SIN su guarda de READ COMMITTED (mutantes a dos sesiones);
#   · la migración real y la sin guarda, con 4 s de pausa justo antes de «lock table» (para que OTRA sesión
#     registre y confirme una cuenta después de fijada la fotografía y antes del candado);
#   · tres ensayos mutantes (el bloqueo de la migración que lleva dentro, alterado y con su huella actualizada);
#   · el ensayo con una pausa antes de su error final (para tenerlo EN VUELO).
generar_copias() {
  python3 - "$T" "$M" "$R" "$VR" "$ENSAYO" <<'PY'
import hashlib, io, sys
DEST, MIG, REV, VINC, ENS = sys.argv[1:]
lee = lambda p: io.open(p, encoding="utf-8").read()
def escribe(nombre, texto): io.open(f"{DEST}/{nombre}", "w", encoding="utf-8").write(texto)
def cambiar(texto, a, b):
    assert texto.count(a) == 1, ("fragmento no único o ausente", a[:70], texto.count(a))
    return texto.replace(a, b)
def md5(s): return hashlib.md5(s.encode("utf-8")).hexdigest()
def cuerpo(texto, nombre):
    ini = texto.index("create or replace function " + nombre + "(")
    a = texto.index("$function$", ini) + len("$function$")
    return texto[a:texto.index("$function$", a)]
def guarda(prefijo):
    return f"""  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception '{prefijo}: la transacción debe ir en READ COMMITTED (va en %)',
      pg_catalog.current_setting('transaction_isolation');
  end if;
"""
escribe("migracion-sin-guarda.sql", cambiar(lee(MIG), guarda("REZAGO PREFLIGHT"), ""))
CANDADO = "lock table crm.cuentas_bancarias in exclusive mode;\n"
escribe("migracion-con-pausa.sql", cambiar(lee(MIG), CANDADO, "select pg_sleep(4);\n" + CANDADO))
escribe("migracion-sin-guarda-con-pausa.sql", cambiar(cambiar(lee(MIG), guarda("REZAGO PREFLIGHT"), ""), CANDADO, "select pg_sleep(4);\n" + CANDADO))
escribe("reversa-sin-guarda.sql", cambiar(lee(REV), guarda("REVERSA"), ""))
escribe("vincular-sin-guarda.sql", cambiar(lee(VINC), guarda("VINCULAR"), ""))

ens = lee(ENS)
BLOQUEO = "private.exigir_cuenta_pago_cronograma"
def ensayo_mutante(nombre, a, b):
    t = cambiar(ens, a, b)
    vieja, nueva = md5(cuerpo(ens, BLOQUEO)), md5(cuerpo(t, BLOQUEO))
    assert vieja != nueva and t.count(vieja) == 2, (nombre, t.count(vieja))
    escribe(nombre, t.replace(vieja, nueva))   # como si quien cambió el cuerpo hubiera actualizado pre y postflight
RECHAZA = "  if not found then\n    -- Solo aquí, con el pago YA rechazado"
COND = """    if (v_rol is null and session_user is distinct from 'authenticator')
       or v_rol = 'service_role'
       or ((select public.es_gestor_cartera()) is true
           and (select private.membresia_crm_revocada()) is false) then"""
ensayo_mutante("ensayo-deja-pasar.sql", RECHAZA, RECHAZA.replace("if not found then", "if false then"))
ensayo_mutante("ensayo-bloquea-todo.sql", RECHAZA, RECHAZA.replace("if not found then", "if true then"))
ensayo_mutante("ensayo-detalle-a-todos.sql", COND, "    if true then")
FIN = "  raise exception 'ENSAYO_DESHECHO >> %', jsonb_build_object(\n"
escribe("ensayo-con-pausa.sql", cambiar(ens, FIN, "  perform pg_sleep(4);\n" + FIN))
print("9 copias")
PY
}

# El cuerpo de un archivo .sql sin su «begin;» ni su «commit;» de nivel superior (para correrlo dentro de OTRA transacción).
sin_transaccion() {
  python3 -c '
import io, sys
l = io.open(sys.argv[1], encoding="utf-8").read().split("\n")
i = next(k for k, x in enumerate(l) if x.strip() == "begin;")
j = max([k for k, x in enumerate(l) if x.strip() == "commit;"] or [len(l)])
sys.stdout.write("\n".join(l[i + 1:j]) + "\n")' "$1"
}
# Corre un archivo ($2) con una función viva ($1) ALTERADA (una línea de comentario más en su cuerpo:
# otra huella, mismo comportamiento), todo dentro de una transacción que se deshace. Devuelve el
# primer ERROR, o «(sin error)».
con_funcion_alterada() {
  local o
  o=$(q "begin;
     do \$a\$
     declare d text := pg_get_functiondef('$1'::regprocedure);
     begin
       if right(d, 11) <> E'\$function\$\n' then raise exception 'el ciclo no sabe alterar %', '$1'; end if;
       execute left(d, length(d) - 11) || E'-- alterada por el ciclo\n\$function\$';
     end \$a\$;
     $(sin_transaccion "$2")
     rollback;")
  if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-260; else echo "(sin error)"; fi
}
# Corre un archivo ($2) dentro de una transacción que se deshace, después de un SQL previo ($1), como
# postgres o como $3. Devuelve su primer ERROR, o su último NOTICE propio, o «(sin avisos)».
tras() {
  local o
  o=$(q "begin;
     $1
     $(sin_transaccion "$2")
     rollback;" "${3:-postgres}")
  if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-260
  else o=$(grep -o 'NOTICE:.*' <<<"$o" | grep -v 'does not exist, skipping' | tail -1 | cut -c1-260); echo "${o:-(sin avisos)}"; fi
}
# Una conexión REAL de la API: entra como authenticator (así session_user = authenticator, igual que
# PostgREST), hace SET ROLE a $1 y pone los claims $2 (rol) y $3 (sub) en las dos formas, o ninguno
# si $2 va vacío. Intenta INSERTAR una cuota ya pagada en el contrato $4 (un INSERT llega siempre al
# bloqueo) y devuelve el primer ERROR. Todo se deshace.
api_inserta_pagada() {
  local o
  o=$(docker exec -i -e PGPASSWORD=postgres "$C" psql -U authenticator -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "begin;
     select set_config('request.jwt.claim.sub', '$3', true), set_config('request.jwt.claim.role', '$2', true),
            set_config('request.jwt.claims', case when '$2' = '' then '' else json_build_object('sub', nullif('$3', ''), 'role', '$2')::text end, true);
     set local role $1;
     insert into public.cronograma_pagos (contrato_id, numero_cuota, fecha_programada, monto_programado, estado, monto_pagado, fecha_pago_real)
     values ('$4', 91, current_date, 100, 'pagado', 100, current_date);
     rollback;" 2>&1)
  if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-260; else echo "(sin error)"; fi
}
# 200 pagos de cuotas de contratos que están ok antes y después (REZAGO-01 y REZAGO-02), por conexión
# directa y todo deshecho. Se cronometra solo la sentencia que marca la cuota pagada. Cada serie
# empieza con un VACUUM (las filas muertas que deja el propio ciclo encarecen cada pasada) y una pasada
# de calentamiento que no se anota; después, cinco pasadas.
tiempos() {
  local i o=''
  q "vacuum (analyze) public.cronograma_pagos, crm.cuotas_cuenta_pagada, crm.contrato_cuentas_pago, crm.cuentas_bancarias, public.contratos, public.audit_log;" >/dev/null
  for i in 0 1 2 3 4 5; do
    [ "$i" = 0 ] && o=''
    o="$o $(q "begin;
      do \$t\$
      declare
        v_ids uuid[] := array['c9ee0000-0000-4000-8000-000000000101', 'c9ee0000-0000-4000-8000-000000000102', 'c9ee0000-0000-4000-8000-000000000103',
                              'c9ee0000-0000-4000-8000-000000000201', 'c9ee0000-0000-4000-8000-000000000202', 'c9ee0000-0000-4000-8000-000000000203']::uuid[];
        v_hoy date := (now() at time zone 'America/Lima')::date;
        t0 timestamptz; ms numeric := 0; i integer;
      begin
        for i in 1..200 loop
          t0 := clock_timestamp();
          update public.cronograma_pagos set estado = 'pagado', fecha_pago_real = v_hoy, monto_pagado = 100 where id = v_ids[1 + (i % 6)];
          ms := ms + extract(epoch from clock_timestamp() - t0) * 1000;
          update public.cronograma_pagos set estado = 'pendiente', fecha_pago_real = null, monto_pagado = null where id = v_ids[1 + (i % 6)];
        end loop;
        raise notice 'TIEMPO % ms', round(ms, 1);
      end \$t\$;
      rollback;" | grep -o 'TIEMPO.*' | sed 's/TIEMPO //')"
    [ "$i" = 0 ] && o=''
  done
  echo "200 pagos, cinco pasadas:$o"
}

# ── Mutantes ─────────────────────────────────────────────────────────────────────────────────
# Genera en $T/mutantes los archivos de la prueba con un mutante dentro de su transacción, y un
# índice (separado por tabuladores) «archivo, modo, lo que se espera (grep -E), descripción». Nunca
# escribe en el repositorio.
generar_mutantes() {
  mkdir -p "$T/mutantes"
  python3 - "$T/mutantes" "$M" "$PRUEBA" <<'PY'
import hashlib, io, sys
DEST, MIG, PRUEBA = sys.argv[1:]
mig = io.open(MIG, encoding="utf-8").read()
prueba = io.open(PRUEBA, encoding="utf-8").read()
assert prueba.count("begin;\n") >= 1
indice = []

def md5(s): return hashlib.md5(s.encode("utf-8")).hexdigest()
def cuerpo(texto, nombre):
    ini = texto.index("create or replace function " + nombre + "(")
    a = texto.index("$function$", ini) + len("$function$")
    return texto[a:texto.index("$function$", a)]
FUNCIONES = ["private.exigir_cuenta_pago_cronograma", "private.cuenta_pago_diagnostico",
             "private.cuentas_pago_motivos_autorizado", "crm.cuentas_pago_motivos_fn"]
def resellar(texto):
    """Como si quien cambió el cuerpo hubiera actualizado también las huellas de pre y postflight."""
    for fn in FUNCIONES:
        vieja, nueva = md5(cuerpo(mig, fn)), md5(cuerpo(texto, fn))
        if vieja != nueva:
            assert texto.count(vieja) == 2, fn
            texto = texto.replace(vieja, nueva)
    return texto
def sin_transaccion(texto):
    l = texto.split("\n")
    i = next(k for k, x in enumerate(l) if x.strip() == "begin;")
    j = max(k for k, x in enumerate(l) if x.strip() == "commit;")
    return "\n".join(l[i + 1:j])
def cambiar(texto, pares):
    for a, b in pares:
        assert texto.count(a) == 1, ("fragmento no único o ausente", a[:70], texto.count(a))
        texto = texto.replace(a, b)
    return texto
def escribir(nombre, modo, espera, descripcion, inyeccion, ancla="begin;\n"):
    assert prueba.count(ancla) == 1 or ancla == "begin;\n"
    io.open(f"{DEST}/{nombre}.sql", "w", encoding="utf-8").write(prueba.replace(ancla, ancla + inyeccion + "\n", 1))
    indice.append("\t".join([nombre, modo, espera, descripcion]))

# ── A · El bloqueo ANTERIOR, con la prueba ANTES. Se inyecta después de T0 (que fija su md5). ──
def viejo(n, descripcion, a, b, espera=r"FALLO \[T"):
    escribir(f"a{n}", "antes", espera, descripcion, f"""do $m$ declare d text := pg_get_functiondef('private.exigir_cuenta_pago_cronograma()'::regprocedure);
begin
  if position($a${a}$a$ in d) = 0 then raise exception 'mutante a{n}: no encontré el fragmento'; end if;
  execute replace(d, $a${a}$a$, $b${b}$b$);
end $m$;""", ancla="select pg_temp.t0_precondiciones();\n")
viejo(1, "bloqueo anterior sin for share", "for share of cp, ct", "", r"FALLO \[T4 .*candado")
viejo(2, "bloqueo anterior que nunca rechaza", "if not found then", "if false then")
viejo(3, "bloqueo anterior que exige cuenta activa", "and cb.moneda = ct.moneda", "and cb.moneda = ct.moneda and cb.activa", r"FALLO \[T4 REZAGO-02")
viejo(4, "bloqueo anterior que no mira el cliente", "and cb.cliente_id = ct.cliente_id", "", r"FALLO \[T. REZAGO-14")
viejo(5, "bloqueo anterior que no mira la moneda", "and cb.moneda = ct.moneda", "", r"FALLO \[T. REZAGO-15")
viejo(6, "bloqueo anterior con otro texto", "Sin cuenta de pago — requiere conciliación", "Sin cuenta de pago")
viejo(7, "bloqueo anterior con otro sqlstate", "errcode = '23514'", "errcode = 'P0001'")

# ── B · La MIGRACIÓN real, alterada, dentro de la transacción de la prueba DESPUÉS (desde ANTES). ──
POSTFLIGHT_CUERPO = r"REZAGO POSTFLIGHT: cuerpo"
def m(nombre, descripcion, espera, pares, sellar=None):
    """sellar=None: no toca cuerpos · False: cuerpo cambiado y huellas viejas · True: huellas actualizadas."""
    t = cambiar(mig, pares)
    if sellar:
        t = resellar(t)
    escribir(nombre, "despues", espera, descripcion, sin_transaccion(t))
def cuerpo_mutado(n, descripcion, espera_resellado, pares, espera_sin_sellar=POSTFLIGHT_CUERPO):
    m(f"m{n}a", descripcion + " (huella sin actualizar)", espera_sin_sellar, pares, sellar=False)
    m(f"m{n}b", descripcion + " (huella actualizada)", espera_resellado, pares, sellar=True)

escribir("m00", "despues", r"^REZAGO despues OK", "CONTROL: la migración sin tocar, dentro de la transacción de la prueba", sin_transaccion(mig))

COND = """    if (v_rol is null and session_user is distinct from 'authenticator')
       or v_rol = 'service_role'
       or ((select public.es_gestor_cartera()) is true
           and (select private.membresia_crm_revocada()) is false) then"""
cuerpo_mutado("01", "el bloqueo da el detalle a todos", r"FALLO \[T3", [(COND, "    if true then")])
cuerpo_mutado("02", "el bloqueo sin la condición de session_user", r"FALLO \[T3 .*sinclaims",
    [("(v_rol is null and session_user is distinct from 'authenticator')", "(v_rol is null)")])
cuerpo_mutado("02x", "el bloqueo mira current_user en vez de session_user", r"FALLO \[T3 .*sinclaims",
    [("session_user is distinct from 'authenticator'", "current_user is distinct from 'authenticator'")])
cuerpo_mutado("03", "el camino feliz llama al diagnóstico", r"FALLO \[T4b",
    [("  perform 1\n  from crm.contrato_cuentas_pago cp\n", "  perform 1 from private.cuenta_pago_diagnostico(array[new.contrato_id]);\n  perform 1\n  from crm.contrato_cuentas_pago cp\n")])
cuerpo_mutado("04", "el bloqueo deja pasar cuando no hay vínculo", r"FALLO \[T",
    [("  if not found then\n    -- Solo aquí, con el pago YA rechazado", "  if false then\n    -- Solo aquí, con el pago YA rechazado")])
cuerpo_mutado("05", "el bloqueo sin for share", r"FALLO \[T4 .*candado", [("  for share of cp, ct;", "  ;")])
# 06, 07 y 08 cambian el diagnóstico, que la carga usa ANTES del postflight: los para la carga misma,
# con la huella actualizada o sin actualizar.
cuerpo_mutado("06", "el diagnóstico cuenta cuentas inactivas", r"query returned no rows",
    [("    where a.cliente_id = ct.cliente_id\n      and a.activa is true\n", "    where a.cliente_id = ct.cliente_id\n")],
    espera_sin_sellar=r"query returned no rows")
OK_ = "      when cp.id is not null and cb.cliente_id = ct.cliente_id and cb.moneda = ct.moneda then 'ok'"
DISCREPA = r"REZAGO: en 1 contratos el diagnóstico y el bloqueo no dicen lo mismo"
cuerpo_mutado("07", "ok sin mirar la moneda", DISCREPA,
    [(OK_, "      when cp.id is not null and cb.cliente_id = ct.cliente_id then 'ok'")], espera_sin_sellar=DISCREPA)
cuerpo_mutado("08", "ok sin mirar el cliente", DISCREPA,
    [(OK_, "      when cp.id is not null and cb.moneda = ct.moneda then 'ok'")], espera_sin_sellar=DISCREPA)

CANDIDATOS = "    where d.caso = 'una_cuenta'\n    order by d.contrato_id\n  loop"
RECHEQUEO = "    where d.caso = 'una_cuenta';\n    if not found then"
ELIGE = """    select cb.id into strict v_cuenta
    from crm.cuentas_bancarias cb
    where cb.cliente_id = v_d.cliente_id
      and cb.moneda = v_d.moneda
      and cb.activa is true;"""
ELIGE_UNA = """    select cb.id into v_cuenta
    from crm.cuentas_bancarias cb
    where cb.cliente_id = v_d.cliente_id
      and cb.moneda = v_d.moneda
      and cb.activa is true
    order by cb.creado_en
    limit 1;"""
PREFIERE_INACTIVA = ELIGE.replace("into strict", "into").replace("\n      and cb.activa is true;", "\n    order by cb.activa\n    limit 1;")
m("m09", "la carga vincula también con varias cuentas (elige una)", r"REZAGO: había 4 contratos por vincular y se vincularon 6",
  [(CANDIDATOS, CANDIDATOS.replace("= 'una_cuenta'", "in ('una_cuenta', 'varias_cuentas')")),
   (RECHEQUEO, RECHEQUEO.replace("= 'una_cuenta'", "in ('una_cuenta', 'varias_cuentas')")), (ELIGE, ELIGE_UNA)])
m("m09x", "el diagnóstico llama una_cuenta a tener varias y la carga elige una (huella actualizada)", r"FALLO \[T1",
  [("      when q.en_moneda = 1 then 'una_cuenta'", "      when q.en_moneda >= 1 then 'una_cuenta'"), (ELIGE, ELIGE_UNA)], sellar=True)
m("m10", "la carga no exige cuenta activa", r"query returned more than one row",
  [(ELIGE, ELIGE.replace("\n      and cb.activa is true;", ";"))])
m("m10x", "la carga prefiere la cuenta inactiva", r"REZAGO: el rastro \(3\) no coincide con los vínculos creados \(4\)", [(ELIGE, PREFIERE_INACTIVA)])
RASTRO = """    insert into private.backfill_cuentas_p0xx (tipo, fila_id, cliente_id, contrato_id, marca_actor)
    values ('vinculo', v_vinculo, v_d.cliente_id, v_fila.contrato_id, c_marca);
"""
m("m11", "la carga no deja rastro", r"REZAGO: el rastro \(0\) no coincide con los vínculos creados \(4\)", [(RASTRO, "")])

COMPUERTA = """  if (select private.membresia_crm_revocada()) is not false
     or (select public.es_gestor_cartera()) is not true then
    raise exception using errcode = '42501', message = 'No autorizado para consultar cuentas de pago';
  end if;
"""
TOPE = """  if coalesce(pg_catalog.cardinality(p_contrato_ids), 0) > 5000 then
    raise exception using errcode = '22023', message = 'Demasiados contratos en una sola consulta';
  end if;
"""
cuerpo_mutado("12", "el autorizador sin compuerta", r"FALLO \[T7", [(COMPUERTA, "")])
cuerpo_mutado("13", "el autorizador devuelve también los ok", r"FALLO \[T7",
    [("  from private.cuenta_pago_diagnostico(p_contrato_ids) d\n  where d.caso <> 'ok';", "  from private.cuenta_pago_diagnostico(p_contrato_ids) d;")])
cuerpo_mutado("14", "el autorizador sin tope", r"FALLO \[T7", [(TOPE, "")])
GRANT_PUERTA = "grant execute on function crm.cuentas_pago_motivos_fn(uuid[]) to authenticated;\n"
REVOKE_DIAG = "revoke all on function private.cuenta_pago_diagnostico(uuid[]) from public, anon, authenticated, service_role;\n"
A_ANON = [(GRANT_PUERTA, GRANT_PUERTA + "grant execute on function crm.cuentas_pago_motivos_fn(uuid[]) to anon;\n")]
A_AUTHENTICATED = [(REVOKE_DIAG, REVOKE_DIAG + "grant execute on function private.cuenta_pago_diagnostico(uuid[]) to authenticated;\n")]
PUERTA_INVOKER = "language sql\nstable\nsecurity invoker\nset search_path to ''\nas $function$\n  select * from private.cuentas_pago_motivos_autorizado(p_contrato_ids);"
A_DEFINER = [(PUERTA_INVOKER, PUERTA_INVOKER.replace("security invoker", "security definer"))]
m("m15", "la puerta con EXECUTE para anon", r"REZAGO POSTFLIGHT: EXECUTE", A_ANON)
m("m16", "el diagnóstico con EXECUTE para authenticated", r"REZAGO POSTFLIGHT: EXECUTE", A_AUTHENTICATED)
m("m17", "la puerta DEFINER", r"REZAGO POSTFLIGHT: cuerpo, DEFINER", A_DEFINER)
cuerpo_mutado("18", "un mensaje con el número de cuenta", r"FALLO \[T",
    [("""        'Contrato %s sin cuenta de pago: el cliente ya tiene una cuenta en %s; falta vincularla a este contrato.',
        ct.numero_contrato, m.del_contrato)""",
      """        'Contrato %s sin cuenta de pago: el cliente ya tiene una cuenta en %s (%s); falta vincularla a este contrato.',
        ct.numero_contrato, m.del_contrato,
        (select x.numero_cuenta from crm.cuentas_bancarias x
         where x.cliente_id = ct.cliente_id and x.moneda = ct.moneda and x.activa is true limit 1))""")])
cuerpo_mutado("19", "el texto genérico cambiado", r"FALLO \[T3",
    [("message = coalesce(v_mensaje, 'Sin cuenta de pago — requiere conciliación');", "message = coalesce(v_mensaje, 'Sin cuenta de pago');")])
SIN_CANDADO = [("lock table crm.cuentas_bancarias in exclusive mode;\n", "")]
m("m20", "la migración sin el candado de la tabla de cuentas (sin concurrencia nadie lo ve)", r"^REZAGO despues OK", SIN_CANDADO)
io.open(f"{DEST}/m20-migracion-sin-candado.sql", "w", encoding="utf-8").write(cambiar(mig, SIN_CANDADO))
SIN_GUARDA_RC = [("  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then\n"
                  "    raise exception 'REZAGO PREFLIGHT: la transacción debe ir en READ COMMITTED (va en %)',\n"
                  "      pg_catalog.current_setting('transaction_isolation');\n"
                  "  end if;\n", "")]
m("m33", "la migración sin la guarda de READ COMMITTED (en una sola sesión nadie lo ve)", r"^REZAGO despues OK", SIN_GUARDA_RC)
io.open(f"{DEST}/m33-migracion-sin-guarda.sql", "w", encoding="utf-8").write(cambiar(mig, SIN_GUARDA_RC))

# Más mutantes del mismo corte (no pedidos, baratos).
cuerpo_mutado("21", "la gestora con la membresía revocada recibe el detalle", r"FALLO \[T3 .*revocada",
    [("       or ((select public.es_gestor_cartera()) is true\n           and (select private.membresia_crm_revocada()) is false) then",
      "       or ((select public.es_gestor_cartera()) is true) then")])
cuerpo_mutado("22", "el rol de servicio recibe el genérico", r"FALLO \[T3 .*servicio", [("       or v_rol = 'service_role'\n", "")])
cuerpo_mutado("23", "la conexión directa recibe el genérico", r"FALLO \[T3 .*directa",
    [("    if (v_rol is null and session_user is distinct from 'authenticator')\n       or v_rol = 'service_role'", "    if v_rol = 'service_role'")])
cuerpo_mutado("24", "el bloqueo rechaza con otro sqlstate", r"FALLO \[T",
    [("    raise exception using\n      errcode = '23514',\n      message = coalesce(v_mensaje", "    raise exception using\n      errcode = 'P0001',\n      message = coalesce(v_mensaje")])
cuerpo_mutado("25", "el autorizador no mira la revocación", r"FALLO \[T7 .*revocada",
    [("  if (select private.membresia_crm_revocada()) is not false\n     or (select public.es_gestor_cartera()) is not true then",
      "  if (select public.es_gestor_cartera()) is not true then")])
cuerpo_mutado("26", "el tope del autorizador deja pasar 5001", r"FALLO \[T7 .*5001", [("0) > 5000 then", "0) > 5001 then")])
cuerpo_mutado("27", "el tope del autorizador rechaza 5000", r"FALLO \[T7 .*5000", [("0) > 5000 then", "0) >= 5000 then")])
cuerpo_mutado("28", "el autorizador pone el tope antes que la compuerta", r"FALLO \[T7 .*antes que el tope", [(COMPUERTA + TOPE, TOPE + COMPUERTA)])
m("m29", "la carga vincula con autor", r"FALLO \[T5 .*creado_por",
  [("    values (v_fila.contrato_id, v_cuenta, null)\n", "    values (v_fila.contrato_id, v_cuenta, 'c9e00000-0000-4000-8000-000000000001')\n")])
cuerpo_mutado("30", "otra_moneda se clasifica como sin_cuenta", r"FALLO \[T1", [("      when q.otra_moneda > 0 then 'otra_moneda'\n", "")])
m("m32", "la carga sella con la cuenta nueva las cuotas que el contrato ya tenía pagadas", r"FALLO \[T0 .*ningún resto",
  [(RASTRO, RASTRO + """    insert into crm.cuotas_cuenta_pagada (cuota_id, contrato_id, cuenta_bancaria_id, origen)
    select q.id, q.contrato_id, v_cuenta, 'inferido' from public.cronograma_pagos q
    where q.contrato_id = v_fila.contrato_id and q.estado = 'pagado';
""")])
cuerpo_mutado("31", "las monedas del mensaje cruzadas", r"FALLO \[T1",
    [("select case ct.moneda when 'PEN' then 'soles' when 'USD' then 'dólares' else ct.moneda end as del_contrato,",
      "select case ct.moneda when 'PEN' then 'dólares' when 'USD' then 'soles' else ct.moneda end as del_contrato,")])

# Dobles: se quita además la defensa de la migración, para ver si la prueba es una segunda línea.
SIN_POSTFLIGHT_ACL = [("      raise exception 'REZAGO POSTFLIGHT: EXECUTE, search_path o comentario inesperados en %', v_f.firma;", "      null;")]
SIN_POSTFLIGHT_FORMA = [("      raise exception 'REZAGO POSTFLIGHT: cuerpo, DEFINER/INVOKER, volatilidad o dueño inesperados en %', v_f.firma;", "      null;")]
SIN_POST_RASTRO = [("    raise exception 'REZAGO: el rastro (%) no coincide con los vínculos creados (%)', v_rastro, v_hechos;", "    null;")]
SIN_POST_DISCREPANCIA = [("    raise exception 'REZAGO: en % contratos el diagnóstico y el bloqueo no dicen lo mismo', v_discrepancias;", "    null;")]
m("d15", "DOBLE: la puerta con EXECUTE para anon y el postflight sin su comprobación", r"FALLO \[T7 catálogo de crm", A_ANON + SIN_POSTFLIGHT_ACL)
m("d16", "DOBLE: el diagnóstico con EXECUTE para authenticated y el postflight sin su comprobación", r"FALLO \[T7 catálogo de private.cuenta_pago_diagnostico", A_AUTHENTICATED + SIN_POSTFLIGHT_ACL)
m("d17", "DOBLE: la puerta DEFINER y el postflight sin su comprobación", r"FALLO \[T7 catálogo de crm", A_DEFINER + SIN_POSTFLIGHT_FORMA)
m("d11", "DOBLE: la carga sin rastro y sin su postcondición", r"FALLO \[T5 .*rastro", [(RASTRO, "")] + SIN_POST_RASTRO)
m("d10", "DOBLE: la carga prefiere la cuenta inactiva y sin la postcondición del rastro", r"FALLO \[T", [(ELIGE, PREFIERE_INACTIVA)] + SIN_POST_RASTRO)
m("d07", "DOBLE: ok sin mirar la moneda y sin la postcondición (huella actualizada)", r"FALLO \[T",
  [(OK_, "      when cp.id is not null and cb.cliente_id = ct.cliente_id then 'ok'")] + SIN_POST_DISCREPANCIA, sellar=True)
m("d08", "DOBLE: ok sin mirar el cliente y sin la postcondición (huella actualizada)", r"FALLO \[T",
  [(OK_, "      when cp.id is not null and cb.moneda = ct.moneda then 'ok'")] + SIN_POST_DISCREPANCIA, sellar=True)

io.open(f"{DEST}/indice.txt", "w", encoding="utf-8").write("\n".join(indice) + "\n")
print(f"{len(indice)} mutantes")
PY
}
# Corre los mutantes cuyo nombre empieza por $1 y dice, para cada uno, quién lo cazó.
correr_mutantes() {
  local nombre modo espera descripcion r quien
  while IFS=$'\t' read -r nombre modo espera descripcion; do
    case "$nombre" in "$1"*) ;; *) continue ;; esac
    r=$(prueba "$modo" "$T/mutantes/$nombre.sql")
    case "$r" in
      *'REZAGO PREFLIGHT'*)  quien='PREFLIGHT de la migración' ;;
      *'REZAGO POSTFLIGHT'*) quien='POSTFLIGHT de la migración' ;;
      'ERROR:  REZAGO:'*)    quien='POSTCONDICIÓN de la carga' ;;
      *'query returned'*)    quien='el STRICT de la carga' ;;
      *'FALLO ['*)           quien="la PRUEBA ($(sed -n 's/.*FALLO \[\(T[0-9a-z]*\).*/\1/p' <<<"$r"))" ;;
      'REZAGO '*' OK'*)      quien='NADIE: pasa' ;;
      *)                     quien='otro error' ;;
    esac
    if grep -Eq -- "$espera" <<<"$r"; then anota ok; printf '✓ %-5s %-86s → %s\n' "$nombre" "$descripcion" "$quien"
    else anota ko; printf '✗ %-5s %-86s → %s (se esperaba /%s/)\n' "$nombre" "$descripcion" "$quien" "$espera"; fi
    printf '        %s\n' "$(cut -c1-210 <<<"$r")"
  done < "$T/mutantes/indice.txt"
}

fin() {
  local i total_ok=0 total_asert=0
  echo "── Resumen por tramo"
  for i in $(seq 0 "$IT"); do
    if [ "${T_KO[$i]}" -eq 0 ]; then printf 'PASS  %-74s %3s pasos' "${TRAMOS[$i]}" "${T_OK[$i]}"
    else printf 'FAIL  %-74s %3s pasos bien, %s MAL' "${TRAMOS[$i]}" "${T_OK[$i]}" "${T_KO[$i]}"; fi
    [ "${T_ASERT[$i]}" -gt 0 ] && printf ' · %s comprobaciones de la prueba' "${T_ASERT[$i]}"
    printf '\n'
    total_ok=$((total_ok + ${T_OK[$i]})); total_asert=$((total_asert + ${T_ASERT[$i]}))
  done
  if [ "$FALLOS" -eq 0 ]; then echo "FIN ciclo cuentas-pago-rezago: todo como se esperaba ($total_ok pasos, $total_asert comprobaciones de la prueba)"
  else echo "FIN ciclo cuentas-pago-rezago: $FALLOS pasos FUERA de lo esperado (✗) de $((total_ok + FALLOS))"; fi
  [ "$FALLOS" -eq 0 ]
}

principal() {
  docker ps --format '{{.Names}}' | grep -qx "$C" || { echo "El contenedor $C no está corriendo: móntalo con supabase/scripts/potencial-lead/banco/montar-banco.sh" >&2; return 2; }
  [ -f "$SIEMBRA" ] && [ -f "$PRUEBA" ] || { echo "Faltan siembra.sql o test-cuentas-pago-rezago.sql en $P" >&2; return 2; }
  if [ "${1:-}" != preparar ]; then
    local f
    for f in "$M" "$R" "$RC" "$VR" "$ENSAYO" "$REGISTRAR" "$DERIVADOS" "$CENSO" "$CENSO_SIN" "$TRINQUETES"; do
      [ -f "$f" ] || { echo "Falta $f" >&2; return 2; }
    done
  fi
  local md5_migracion=''
  [ -f "$M" ] && md5_migracion=$(md5_de "$M")

  tramo "0 · punto de partida"
  if [ "${1:-}" != preparar ]; then
    echo "  archivo de la migración: md5 $md5_migracion"
    paso "derivados al día (generar-derivados.py --verificar)" '^derivados al día' "$(python3 "$DERIVADOS" --verificar 2>&1 | tail -1)"
    paso "registrar.sql lleva el md5 de la migración de hoy" "md5 ${md5_migracion}" "$(sed -n '4p' "$REGISTRAR")"
    paso "el ensayo se generó con ese mismo archivo" "md5 ${md5_migracion}" "$(sed -n '2p' "$ENSAYO")"
    paso "copias alteradas en el directorio temporal (sin guarda de aislamiento, ensayos mutantes)" '^9 copias$' "$(generar_copias 2>&1 | tail -1)"
    paso "ninguna otra sesión abierta en el banco (los tramos a dos sesiones miran quién espera a quién)" '^0 sesiones$' "$(q "select count(*) || ' sesiones' from pg_stat_activity where pid <> pg_backend_pid() and backend_type = 'client backend';" supabase_admin)"
  fi
  paso "restos de corridas anteriores" '^restos limpios$' "$(limpiar_restos)"
  paso "registro de la versión fuera (el ciclo lo repone al final)" '^registro fuera$' "$(quitar_registro)"
  if [ "$(aplicada)" = 1 ] || [ "$(rastro | cut -d' ' -f1)" != 0 ]; then
    if [ -f "$R" ]; then paso "la migración estaba aplicada: reversa" "$SIN_ERROR" "$(msg "$R")"
    else paso "la migración estaba aplicada y falta reversa.sql" '^nunca$' "no se puede partir del estado ANTES"; fi
  fi
  paso "rastro ya revertido de corridas anteriores, fuera" '^rastro revertido fuera$' "$(quitar_rastro_revertido)"

  tramo "1 · siembra y estado ANTES"
  paso "siembra" '^SIEMBRA cuentas-pago-rezago OK' "$(sembrar)"
  prueba_paso "prueba ANTES" antes
  local e_antes r_antes revertidos
  e_antes=$(estado); r_antes=$(rastro); revertidos=${r_antes#* }
  echo "  foto ANTES:  $e_antes"
  echo "  rastro de la carga de la migración (vigentes revertidos): $r_antes"
  paso "censo por la consulta suelta" '^cuenta_no_corresponde=2 ok=2 otra_moneda=2 sin_cuenta=3 una_cuenta=4 varias_cuentas=2$' "$(censo)"
  if [ "${1:-}" = preparar ]; then fin; return; fi
  paso "censo-sin-funciones.sql corre y cuenta lo mismo" '"una_cuenta": 4' "$(q "$(cat "$CENSO_SIN")" | tr -d '\n' | grep -o '"por_caso": {[^}]*}')"
  trinquetes > "$SALIDA/trinquetes-sin.txt"
  paso "foto de trinquetes SIN la migración" '^[1-9][0-9]* líneas' "$(wc -l < "$SALIDA/trinquetes-sin.txt" | tr -d ' ') líneas ($(grep -c 'pasa$' "$SALIDA/trinquetes-sin.txt") pasan, $(grep -c 'cae:' "$SALIDA/trinquetes-sin.txt") caen)"

  tramo "2 · lo que debe negarse o no hacer nada en el estado ANTES; el ENSAYO en ANTES"
  paso "vincular-rezago.sql se niega" '^ERROR:  VINCULAR: el bloqueo o el diagnóstico vivos no son los de la migración' "$(msg "$VR")"
  paso "registrar.sql se niega" '^ERROR:  REGISTRO: la migración 20261001233019 no está aplicada' "$(msg "$REGISTRAR")"
  paso "reversa-solo-codigo.sql no hace nada" "$SIN_ERROR" "$(msg "$RC")"
  paso "reversa.sql no hace nada" '^NOTICE:  REVERSA: 0 vínculos de la carga borrados' "$(msg "$R")"
  igual "tras los cuatro, la misma foto ANTES" "$e_antes" "$(estado)"
  # El ensayo dice su veredicto en el JSON de su error: PASA solo si todo se probó y todo salió como dicta la regla.
  # En ANTES: 4 casos bloqueados + 4 vinculados por la carga + 1 que ya estaba bien + 2 identidades = 11.
  local c0 j
  local E_PASA_ANTES='veredicto=PASA · todo_como_se_esperaba=true · vinculados=4 · 11 como se esperaba, 0 no, 0 sin probar · conexion=postgres/postgres · fallos=\[\] · sin_probar=\[\]$'
  c0=$(conteos)
  j=$(ensayo); echo "$j" > "$SALIDA/ensayo-antes.txt"
  paso "ENSAYO en ANTES: termina en ENSAYO_DESHECHO" '^ERROR:  ENSAYO_DESHECHO >> \{' "$(cut -c1-60 <<<"$j")…"
  paso "ENSAYO en ANTES: PASA · vinculó 4 · 11 pagos e identidades como se esperaba" "^${E_PASA_ANTES}" "$(resumen_ensayo <<<"$j")"
  igual "el ENSAYO no dejó nada: misma foto" "$e_antes" "$(estado)"
  igual "el ENSAYO no dejó nada: mismos conteos (bitácora incluida)" "$c0" "$(conteos)"
  echo "  JSON del ensayo en ANTES: $j"

  tramo "3 · el ENSAYO en sus otros veredictos: INCOMPLETO y FALLA (en ANTES; el banco queda igual)"
  # INCOMPLETO = nada falló, pero algo no se pudo probar. El mundo se altera en la MISMA transacción del ensayo
  # (ensayo_tras): su error final lo deshace todo, también la alteración.
  local SIN_ANALISTA="update public.perfiles set activo = false where id = '$ANALISTA';"
  local SIN_GESTOR="update public.perfiles set activo = false where rol in ('admin', 'superadmin', 'operaciones');"
  local A_TRASLADADO="update public.cronograma_pagos set estado = 'trasladado' where estado = 'pendiente' and contrato_id"
  local INC_IDENTIDAD='^veredicto=INCOMPLETO · todo_como_se_esperaba=false · vinculados=4 · 10 como se esperaba, 0 no, 0 sin probar · conexion=postgres/postgres · fallos=\[\] · sin_probar=\["identidad: falta un gestor de cartera vigente o un analista activo con quien probar"\]$'
  j=$(ensayo_tras "$SIN_ANALISTA"); echo "$j" > "$SALIDA/ensayo-incompleto-sin-analista.txt"
  paso "sin analista activo: INCOMPLETO" "$INC_IDENTIDAD" "$(resumen_ensayo <<<"$j")"
  paso "sin gestor de cartera vigente: INCOMPLETO" "$INC_IDENTIDAD" "$(ensayo_tras "$SIN_GESTOR" | resumen_ensayo)"
  j=$(ensayo_tras "$A_TRASLADADO in ('$REZAGO_07', 'c9ed0000-0000-4000-8000-000000000008');"); echo "$j" > "$SALIDA/ensayo-incompleto-caso-sin-cuotas.txt"
  paso "un caso (varias_cuentas) sin ninguna cuota pendiente: INCOMPLETO" '^veredicto=INCOMPLETO · todo_como_se_esperaba=false · vinculados=4 · 10 como se esperaba, 0 no, 0 sin probar · conexion=postgres/postgres · fallos=\[\] · sin_probar=\["caso varias_cuentas: hay 2 contratos y ninguno con una cuota pendiente que probar"\]$' "$(resumen_ensayo <<<"$j")"
  paso "ningún contrato que ya estaba bien con cuota pendiente: INCOMPLETO" '^veredicto=INCOMPLETO · todo_como_se_esperaba=false · vinculados=4 · 10 como se esperaba, 0 no, 0 sin probar · conexion=postgres/postgres · fallos=\[\] · sin_probar=\["ningún contrato que ya estaba bien tiene una cuota pendiente que probar"\]$' "$(ensayo_tras "$A_TRASLADADO in ('c9ed0000-0000-4000-8000-000000000001', 'c9ed0000-0000-4000-8000-000000000002');" | resumen_ensayo)"
  paso "un contrato que vinculó la carga, sin cuotas pendientes: INCOMPLETO" '^veredicto=INCOMPLETO · todo_como_se_esperaba=false · vinculados=4 · 10 como se esperaba, 0 no, 1 sin probar · conexion=postgres/postgres · fallos=\[\] · sin_probar=\["contrato REZAGO-05 \(vinculado por la carga\): no tiene ninguna cuota pendiente que probar"\]$' "$(ensayo_tras "$A_TRASLADADO = 'c9ed0000-0000-4000-8000-000000000005';" | resumen_ensayo)"
  paso "ningún contrato bloqueado con cuota pendiente: INCOMPLETO (los 4 casos y la identidad)" '^veredicto=INCOMPLETO · todo_como_se_esperaba=false · vinculados=4 · 5 como se esperaba, 0 no, 0 sin probar · conexion=postgres/postgres · fallos=\[\] · sin_probar=\[("caso [a-z_]+: hay [0-9] contratos y ninguno con una cuota pendiente que probar", ){4}"identidad: no hay ningún contrato bloqueado con una cuota pendiente"\]$' "$(ensayo_tras "$A_TRASLADADO::text >= '$REZAGO_07';" | resumen_ensayo)"
  paso "con TODAS las cuotas pendientes en «vencido»: PASA igual (también las prueba)" "^${E_PASA_ANTES}" "$(ensayo_tras "update public.cronograma_pagos set estado = 'vencido' where estado = 'pendiente';" | resumen_ensayo)"
  # FALLA = algún pago salió distinto de lo que dicta la regla. Tres ensayos MUTANTES: el bloqueo de la migración que
  # llevan dentro está alterado, con su huella actualizada en pre y postflight (si no, lo pararía el postflight).
  j=$(ensayo "$T/ensayo-deja-pasar.sql"); echo "$j" > "$SALIDA/ensayo-falla-deja-pasar.txt"
  paso "MUTANTE el bloqueo deja pasar: FALLA (los 4 bloqueados se pagan, y las 2 identidades)" '^veredicto=FALLA · todo_como_se_esperaba=false · vinculados=4 · 5 como se esperaba, 6 no, 0 sin probar · conexion=postgres/postgres · fallos=\["contrato REZAGO-14 \(bloqueado, caso cuenta_no_corresponde\): pagada ", "contrato REZAGO-09 \(bloqueado, caso otra_moneda\): pagada ", "contrato REZAGO-11 \(bloqueado, caso sin_cuenta\): pagada ", "contrato REZAGO-07 \(bloqueado, caso varias_cuentas\): pagada ", "identidad gestor de cartera: pagada ", "identidad analista \(no gestor\): pagada "\] · sin_probar=\[\]$' "$(resumen_ensayo <<<"$j")"
  j=$(ensayo "$T/ensayo-bloquea-todo.sql"); echo "$j" > "$SALIDA/ensayo-falla-bloquea-todo.txt"
  paso "MUTANTE el bloqueo lo rechaza todo: FALLA (los 4 vinculados y el que ya estaba bien)" '^veredicto=FALLA · todo_como_se_esperaba=false · vinculados=4 · 6 como se esperaba, 5 no, 0 sin probar · conexion=postgres/postgres · fallos=\[("contrato REZAGO-0[3-6] \(vinculado por la carga, caso ok\): bloqueada Sin cuenta de pago — requiere conciliación", ){4}"contrato REZAGO-01 \(ya estaba bien, caso ok\): bloqueada Sin cuenta de pago — requiere conciliación"\] · sin_probar=\[\]$' "$(resumen_ensayo <<<"$j")"
  j=$(ensayo "$T/ensayo-detalle-a-todos.sql"); echo "$j" > "$SALIDA/ensayo-falla-detalle-a-todos.txt"
  paso "MUTANTE el bloqueo da el detalle a todos: FALLA (solo la identidad del analista)" '^veredicto=FALLA · todo_como_se_esperaba=false · vinculados=4 · 10 como se esperaba, 1 no, 0 sin probar · conexion=postgres/postgres · fallos=\["identidad analista \(no gestor\): bloqueada Contrato REZAGO-07 sin cuenta de pago: el cliente tiene 2 cuentas en soles; confirma con él en cuál cobra este contrato\."\] · sin_probar=\[\]$' "$(resumen_ensayo <<<"$j")"
  paso "FALLA gana a INCOMPLETO (deja pasar + sin analista)" '^veredicto=FALLA · todo_como_se_esperaba=false · vinculados=4 · 5 como se esperaba, 5 no, 0 sin probar · .* · sin_probar=\["identidad: falta un gestor de cartera vigente o un analista activo con quien probar"\]$' "$(ensayo_tras "$SIN_ANALISTA" "$T/ensayo-deja-pasar.sql" | resumen_ensayo)"
  igual "ninguno de esos ensayos dejó nada: misma foto" "$e_antes" "$(estado)"
  igual "ninguno de esos ensayos dejó nada: mismos conteos (bitácora incluida)" "$c0" "$(conteos)"

  tramo "4 · lo que debe cancelar la migración entera (el banco sigue en ANTES)"
  # La guarda de S1: una fila de conciliación de PERFIL, del cliente y la moneda de un candidato.
  paso "conciliación: perfil_invalido para D en USD (REZAGO-04)" '^1 filas' "$(conciliar perfil "$CLIENTE_D" USD perfil_invalido)"
  local e_con; e_con=$(estado)
  paso "la migración se cancela" '^ERROR:  REZAGO: el contrato REZAGO-04 tiene una sola cuenta, pero su perfil legado quedó en conciliación' "$(msg "$M")"
  igual "no cambió nada" "$e_con" "$(estado)"
  paso "se quita la fila" '^0 filas' "$(quitar_conciliacion)"
  paso "conciliación: mismo_cci_datos_distintos para C en PEN (REZAGO-03)" '^1 filas' "$(conciliar perfil "$CLIENTE_C" PEN mismo_cci_datos_distintos)"
  paso "la migración se cancela" '^ERROR:  REZAGO: el contrato REZAGO-03 tiene una sola cuenta, pero su perfil legado quedó en conciliación' "$(msg "$M")"
  paso "el ENSAYO también se cancela ahí (y tampoco escribe)" '^ERROR:  REZAGO: el contrato REZAGO-03 tiene una sola cuenta, pero su perfil legado quedó en conciliación' "$(ensayo | cut -c1-260)"
  paso "se quita la fila" '^0 filas' "$(quitar_conciliacion)"
  igual "el banco sigue en ANTES" "$e_antes" "$(estado)"
  # El tope: una copia temporal de la migración con el rezago conocido en 3 (hay 4 candidatos).
  sed 's/c_tope constant integer := 23;/c_tope constant integer := 3;/' "$M" > "$T/migracion-tope-3.sql"
  paso "copia temporal de la migración con el tope en 3" '^1$' "$(grep -c 'c_tope constant integer := 3;' "$T/migracion-tope-3.sql")"
  paso "la migración con tope 3 se cancela" '^ERROR:  REZAGO: 4 contratos por vincular y el rezago conocido es de 3; no se toca nada' "$(msg "$T/migracion-tope-3.sql")"
  igual "el banco sigue en ANTES" "$e_antes" "$(estado)"
  # El candado de la tabla de cuentas: con una cuenta a medio registrar en OTRA sesión, la migración espera y se cancela.
  paso "con una cuenta a medio registrar, espera y se cancela" '^[4-9] s · ERROR:  canceling statement due to lock timeout' "$(con_cuenta_a_medias "$M")"
  paso "el ENSAYO, igual: espera y se cancela con el error de la migración (ahí no da veredicto)" '^[4-9] s · ERROR:  canceling statement due to lock timeout' "$(con_cuenta_a_medias "$ENSAYO")"
  igual "el banco sigue en ANTES" "$e_antes" "$(estado)"
  # La huella del bloqueo vivo: si no es la de P-0XX S3 ni la de esta migración, nadie lo pisa.
  local BLOQUEO='private.exigir_cuenta_pago_cronograma()'
  local HUELLA_MIG='^ERROR:  REZAGO PREFLIGHT: el bloqueo de pagos vivo \([0-9a-f]{32}\) no es el esperado; no se toca'
  local HUELLA_REV='^ERROR:  REVERSA: el bloqueo vivo \([0-9a-f]{32}\) no es el de la migración 20261001233019 ni el anterior; no se toca'
  paso "bloqueo vivo con otro cuerpo: la migración se niega" "$HUELLA_MIG" "$(con_funcion_alterada "$BLOQUEO" "$M")"
  paso "bloqueo vivo con otro cuerpo: reversa.sql se niega" "$HUELLA_REV" "$(con_funcion_alterada "$BLOQUEO" "$R")"
  paso "bloqueo vivo con otro cuerpo: reversa-solo-codigo.sql se niega" "$HUELLA_REV" "$(con_funcion_alterada "$BLOQUEO" "$RC")"
  igual "el banco sigue en ANTES" "$e_antes" "$(estado)"
  # (a) El aislamiento. La carga decide con lo que lee DESPUÉS de esperar sus candados; con otra cosa que READ COMMITTED
  # leería la fotografía de ANTES de esperar. La migración se niega (y el ensayo, que la lleva dentro).
  local NO_RC_MIG='^ERROR:  REZAGO PREFLIGHT: la transacción debe ir en READ COMMITTED \(va en '
  paso "en REPEATABLE READ (opción de la sesión): la migración se niega" "${NO_RC_MIG}repeatable read\\)\$" "$(Q_OPCIONES="$RR" msg "$M")"
  paso "en SERIALIZABLE (opción de la sesión): la migración se niega" "${NO_RC_MIG}serializable\\)\$" "$(Q_OPCIONES="$SER" msg "$M")"
  paso "en READ UNCOMMITTED (para Postgres es READ COMMITTED): también se niega" "${NO_RC_MIG}read uncommitted\\)\$" "$(Q_OPCIONES="$RU" msg "$M")"
  { echo "begin isolation level repeatable read;"; cat "$M"; } > "$T/migracion-tras-begin-rr.sql"
  { echo "set transaction isolation level serializable;"; cat "$M"; } > "$T/migracion-tras-set-ser.sql"
  paso "con «begin isolation level repeatable read;» delante, en el mismo mensaje: se niega" "${NO_RC_MIG}repeatable read\\)\$" "$(msg "$T/migracion-tras-begin-rr.sql")"
  paso "con «set transaction isolation level serializable;» delante, en el mismo mensaje: se niega" "${NO_RC_MIG}serializable\\)\$" "$(msg "$T/migracion-tras-set-ser.sql")"
  paso "el ENSAYO en REPEATABLE READ se niega igual (el error es el de la migración)" "${NO_RC_MIG}repeatable read\\)\$" "$(Q_OPCIONES="$RR" ensayo | cut -c1-260)"
  # Los tres derivados, también desde ANTES: el aislamiento es lo PRIMERO que miran (antes que las huellas).
  local nivel opciones
  for nivel in 'repeatable read' serializable; do
    opciones="$RR"; [ "$nivel" = serializable ] && opciones="$SER"
    paso "en $nivel, desde ANTES: vincular-rezago.sql se niega por el aislamiento" "^ERROR:  VINCULAR: la transacción debe ir en READ COMMITTED \\(va en $nivel\\)\$" "$(Q_OPCIONES="$opciones" msg "$VR")"
    paso "en $nivel, desde ANTES: reversa.sql se niega" "^ERROR:  REVERSA: la transacción debe ir en READ COMMITTED \\(va en $nivel\\)\$" "$(Q_OPCIONES="$opciones" msg "$R")"
    paso "en $nivel, desde ANTES: reversa-solo-codigo.sql se niega" "^ERROR:  REVERSA: la transacción debe ir en READ COMMITTED \\(va en $nivel\\)\$" "$(Q_OPCIONES="$opciones" msg "$RC")"
  done
  # Lo que NO cambia el aislamiento: fijar el valor por defecto dentro del mismo mensaje (su transacción ya empezó).
  paso "«set default_transaction_isolation» en el MISMO mensaje no cambia la transacción que ya empezó" '^read committed$' "$(q "set default_transaction_isolation = 'repeatable read'; begin; select current_setting('transaction_isolation'); commit;")"
  igual "el banco sigue en ANTES" "$e_antes" "$(estado)"
  prueba_paso "prueba ANTES" antes

  tramo "5 · aislamiento a dos sesiones: una segunda cuenta registrada a mitad de la carga"
  # El contraejemplo. OTRA sesión le registra a C (REZAGO-03, una_cuenta) una SEGUNDA cuenta en soles: la inserta, la
  # carga arranca y se queda esperando el candado de la tabla de cuentas, y la otra sesión CONFIRMA. Al seguir, C tiene
  # dos cuentas: ya no hay «una sola posible». En READ COMMITTED la carga lo ve; con la fotografía de antes, no.
  local DOS_DE_C="select (select count(*) from crm.contrato_cuentas_pago where contrato_id = '$REZAGO_03') || ' vínculo · ' || (select count(*) from crm.cuentas_bancarias where cliente_id = '$CLIENTE_C' and moneda = 'PEN' and activa) || ' cuentas PEN activas';"
  local ESPERA_CUENTA='^carga espera a registra-cuenta \[Lock/relation · tabla crm\.cuentas_bancarias en ExclusiveLock\]$'
  local ESPERO='^[2-4]\.[0-9] s · '
  local NO_ESPERO='^[01]\.[0-9] s · '
  local SE_CANCELO='^5\.[0-9] s · ERROR:  canceling statement due to lock timeout'
  # Control: el archivo real, en READ COMMITTED.
  ( registra_cuenta "$CUENTA_SEGUNDA" "$CLIENTE_C" PEN 4 98 ) &
  en_vuelo registra-cuenta
  ( Q_NOMBRE=carga cronometrado msg "$M" > "$T/carga.txt" ) &
  paso "la migración REAL espera a quien registra la cuenta (candado de la tabla)" "$ESPERA_CUENTA" "$(ver_espera)"
  wait
  paso "al seguir ve las DOS cuentas y NO vincula REZAGO-03" "${ESPERO}NOTICE:  REZAGO: antes .* vinculados 3 \\{REZAGO-04,REZAGO-05,REZAGO-06\\}" "$(cat "$T/carga.txt")"
  paso "REZAGO-03 queda sin vínculo, para Operaciones" '^0 vínculo · 2 cuentas PEN activas$' "$(q "$DOS_DE_C")"
  paso "censo: REZAGO-03 es ahora varias_cuentas" '^cuenta_no_corresponde=2 ok=5 otra_moneda=2 sin_cuenta=3 varias_cuentas=3$' "$(censo)"
  volver_a_antes "control"
  # Mutante: la misma migración SIN la guarda, lanzada en REPEATABLE READ y en SERIALIZABLE.
  for nivel in 'repeatable read' serializable; do
    opciones="$RR"; [ "$nivel" = serializable ] && opciones="$SER"
    ( registra_cuenta "$CUENTA_SEGUNDA" "$CLIENTE_C" PEN 4 98 ) &
    en_vuelo registra-cuenta
    ( Q_OPCIONES="$opciones" Q_NOMBRE=carga cronometrado msg "$T/migracion-sin-guarda.sql" > "$T/carga.txt" ) &
    paso "MUTANTE sin la guarda, en $nivel: espera igual" "$ESPERA_CUENTA" "$(ver_espera)"
    wait
    paso "MUTANTE: al seguir decide con la fotografía vieja y VINCULA REZAGO-03" "${ESPERO}NOTICE:  REZAGO: antes .* vinculados 4 \\{REZAGO-03,REZAGO-04,REZAGO-05,REZAGO-06\\}" "$(cat "$T/carga.txt")"
    paso "MUTANTE: REZAGO-03 vinculado teniendo DOS cuentas (lo que la guarda evita)" '^1 vínculo · 2 cuentas PEN activas$' "$(q "$DOS_DE_C")"
    paso "MUTANTE: y ya se paga, a una cuenta que nadie confirmó (deshecho)" "^${CUOTA_0301}\$" "$(intento_pago "$CUOTA_0301")"
    volver_a_antes "mutante en $nivel"
  done
  # El archivo real, lanzado en REPEATABLE READ en ese mismo trance: se niega antes de esperar a nadie.
  ( registra_cuenta "$CUENTA_SEGUNDA" "$CLIENTE_C" PEN 4 98 ) &
  en_vuelo registra-cuenta
  paso "la migración REAL en REPEATABLE READ, en ese trance: se niega sin esperar" "${NO_ESPERO}ERROR:  REZAGO PREFLIGHT: la transacción debe ir en READ COMMITTED \\(va en repeatable read\\)" "$(Q_OPCIONES="$RR" Q_NOMBRE=carga cronometrado msg "$M")"
  wait
  volver_a_antes "real en repeatable read"
  # El orden EXACTO del contraejemplo: la cuenta se registra Y se confirma DESPUÉS de fijada la fotografía de la carga y
  # ANTES de que pida el candado. Para abrir ese hueco, copias con 4 s de pausa justo antes de «lock table».
  local ALTA_SEGUNDA="insert into crm.cuentas_bancarias (id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci, origen, creado_por) values ('$CUENTA_SEGUNDA', '$CLIENTE_C', 'PEN', 'Interbank', 'ahorros', '89899000000098', '00389900000000000098', 'portal', '$ADMIN'); select count(*) || ' cuentas' from crm.cuentas_bancarias;"
  ( Q_OPCIONES="$RR" Q_NOMBRE=carga cronometrado msg "$T/migracion-sin-guarda-con-pausa.sql" > "$T/carga.txt" ) &
  en_vuelo carga
  paso "MUTANTE con pausa (repeatable read): dormido tras su fotografía, aún sin el candado de cuentas" '^(AccessShareLock|\(ninguno\))$' "$(candados_sobre carga crm.cuentas_bancarias)"
  paso "la otra sesión registra y CONFIRMA la segunda cuenta de C, sin esperar a nadie" "${NO_ESPERO}22 cuentas\$" "$(Q_NOMBRE=registra-cuenta cronometrado ultima "$ALTA_SEGUNDA")"
  wait
  paso "MUTANTE: al despertar toma el candado, decide con su fotografía y VINCULA REZAGO-03" "^[45]\\.[0-9] s · NOTICE:  REZAGO: antes .* vinculados 4 \\{REZAGO-03,REZAGO-04,REZAGO-05,REZAGO-06\\}" "$(cat "$T/carga.txt")"
  paso "MUTANTE: REZAGO-03 vinculado teniendo DOS cuentas" '^1 vínculo · 2 cuentas PEN activas$' "$(q "$DOS_DE_C")"
  volver_a_antes "mutante con pausa"
  ( Q_NOMBRE=carga cronometrado msg "$T/migracion-con-pausa.sql" > "$T/carga.txt" ) &
  en_vuelo carga
  paso "la otra sesión registra y CONFIRMA la segunda cuenta de C, sin esperar a nadie" "${NO_ESPERO}22 cuentas\$" "$(Q_NOMBRE=registra-cuenta cronometrado ultima "$ALTA_SEGUNDA")"
  wait
  paso "el archivo REAL con la misma pausa (READ COMMITTED): ve las dos cuentas y NO vincula REZAGO-03" "^[45]\\.[0-9] s · NOTICE:  REZAGO: antes .* vinculados 3 \\{REZAGO-04,REZAGO-05,REZAGO-06\\}" "$(cat "$T/carga.txt")"
  paso "REZAGO-03 queda sin vínculo" '^0 vínculo · 2 cuentas PEN activas$' "$(q "$DOS_DE_C")"
  volver_a_antes "real con pausa"
  prueba_paso "prueba ANTES" antes

  tramo "6 · pagos en vuelo frente a la migración, a dos sesiones"
  local ESPERA_FILA_CONTRATO='\[Lock/transactionid · fila de contratos\]$'
  # (c) Un pago de un contrato ok (REZAGO-01) confirmándose, y la migración en la otra sesión.
  ( pago_en_vuelo "$CUOTA_0101" 4 > "$T/pago.txt" 2>&1 ) &
  en_vuelo pago-en-vuelo
  echo "  candados de tabla del pago en vuelo: $(candados_de pago-en-vuelo)"
  paso "(c) el pago en vuelo solo LEE la tabla de cuentas (no choca con el candado de la carga)" '^AccessShareLock$' "$(candados_sobre pago-en-vuelo crm.cuentas_bancarias)"
  paso "(c) crm.cuotas_cuenta_pagada no tiene claves foráneas" '^0$' "$(q "select count(*) from pg_constraint where conrelid = 'crm.cuotas_cuenta_pagada'::regclass and contype = 'f';")"
  paso "(c) la migración NO espera al pago: aplica y vincula los 4" "${NO_ESPERO}NOTICE:  REZAGO: antes .* vinculados 4 " "$(Q_NOMBRE=carga cronometrado msg "$M")"
  paso "(c) nadie espera a nadie" '^nadie espera$' "$(quien_espera)"
  wait
  paso "(c) el pago confirma después, sellado en su cuenta" "^${CUOTA_0101} · ${CUENTA_01}\\|registro\$" "$(head -1 "$T/pago.txt") · $(sello "$CUOTA_0101")"
  volver_a_antes "(c)"
  # (c) Al revés: la CARGA en vuelo (la migración entera, sin confirmar) y llega el pago del contrato ok.
  ( Q_NOMBRE=carga archivo_en_vuelo "$M" 4 > "$T/carga.txt" 2>&1 ) &
  en_vuelo carga
  echo "  candados de tabla de la carga en vuelo: $(candados_de carga)"
  paso "(c) con la CARGA en vuelo, el pago de REZAGO-01 tampoco espera" "${NO_ESPERO}${CUOTA_0101}\$" "$(Q_NOMBRE=pago cronometrado pagar "$CUOTA_0101")"
  wait
  paso "(c) la carga confirma con sus 4 vínculos y el pago queda sellado" "^vinculados 4 \\{REZAGO-03,REZAGO-04,REZAGO-05,REZAGO-06\\} · ${CUENTA_01}\\|registro\$" "$(grep -o 'vinculados [0-9]* {[^}]*}' "$T/carga.txt" | tail -1) · $(sello "$CUOTA_0101")"
  volver_a_antes "(c) al revés"
  # (d) Un contrato una_cuenta (REZAGO-03). En ANTES el bloqueo rechaza su pago en el acto, así que «en vuelo» solo
  # puede estar: el intento ya rechazado con su transacción abierta; un pago que LLEGA con la carga en vuelo; o un
  # cambio de cuota que no es un pago (toma la fila del contrato FOR UPDATE igual que un pago, y nadie lo rechaza).
  ( pago_rechazado_en_vuelo "$CUOTA_0301" 4 > "$T/pago.txt" 2>&1 ) &
  en_vuelo pago-rechazado
  paso "(d) el intento rechazado, con su transacción aún abierta, no conserva candados" '^\(ninguno\)$' "$(candados_de pago-rechazado)"
  paso "(d) la migración no lo espera y vincula los 4" "${NO_ESPERO}NOTICE:  REZAGO: antes .* vinculados 4 " "$(Q_NOMBRE=carga cronometrado msg "$M")"
  wait
  paso "(d) el intento se rechazó con el texto de siempre; la cuota sigue pendiente" '^NOTICE:  RECHAZADO: 23514 Sin cuenta de pago — requiere conciliación · pendiente$' "$(grep -m1 -o 'NOTICE:.*' "$T/pago.txt") · $(q "select estado from public.cronograma_pagos where id = '$CUOTA_0301';")"
  volver_a_antes "(d) intento rechazado"
  ( Q_NOMBRE=carga archivo_en_vuelo "$M" 4 > "$T/carga.txt" 2>&1 ) &
  en_vuelo carga
  ( Q_NOMBRE=pago cronometrado pagar "$CUOTA_0301" > "$T/pago.txt" ) &
  paso "(d) con la CARGA en vuelo, el pago de REZAGO-03 espera a la carga en la fila del contrato" "^pago espera a carga ${ESPERA_FILA_CONTRATO}" "$(ver_espera)"
  wait
  paso "(d) al confirmar la carga, el pago sigue y SALE PAGADO" "${ESPERO}${CUOTA_0301}\$" "$(cat "$T/pago.txt")"
  paso "(d) sellado en la cuenta que la carga acaba de vincular" "^${CUENTA_04}\\|registro\$" "$(sello "$CUOTA_0301")"
  volver_a_antes "(d) pago que llega"
  ( cambio_en_vuelo "$CUOTA_0301" 4 >/dev/null 2>&1 ) &
  en_vuelo cambio-en-vuelo
  ( Q_NOMBRE=carga cronometrado msg "$M" > "$T/carga.txt" ) &
  paso "(d) con un cambio de cuota de REZAGO-03 en vuelo, la CARGA espera en la fila del contrato" "^carga espera a cambio-en-vuelo ${ESPERA_FILA_CONTRATO}" "$(ver_espera)"
  wait
  paso "(d) cuando el cambio termina, la carga sigue y vincula los 4" "${ESPERO}NOTICE:  REZAGO: antes .* vinculados 4 " "$(cat "$T/carga.txt")"
  volver_a_antes "(d) cambio en vuelo"
  ( cambio_en_vuelo "$CUOTA_0301" 8 >/dev/null 2>&1 ) &
  en_vuelo cambio-en-vuelo
  paso "(d) si el cambio tarda más de 5 s, la migración se cancela entera" "$SE_CANCELO" "$(Q_NOMBRE=carga cronometrado msg "$M")"
  wait
  igual "(d) no cambió nada: el banco sigue en ANTES" "$e_antes" "$(estado)"
  prueba_paso "prueba ANTES" antes

  tramo "7 · pagos en vuelo frente al ENSAYO, a dos sesiones (en ANTES, como se lanzará en producción)"
  # (f) El ensayo elige REZAGO-01 (el contrato que «ya estaba bien») y su primera cuota pendiente (la 1).
  ( pago_en_vuelo "$CUOTA_0101" 4 > "$T/pago.txt" 2>&1 ) &
  en_vuelo pago-en-vuelo
  ( Q_NOMBRE=ensayo cronometrado ensayo > "$T/ensayo.txt" ) &
  paso "(f) pago real en vuelo de la MISMA cuota: el ensayo espera en la fila de la cuota" '^ensayo espera a pago-en-vuelo \[Lock/transactionid · fila de cronograma_pagos\]$' "$(ver_espera)"
  wait
  paso "(f) al confirmar el pago, el ensayo sigue: PASA" "${ESPERO}${E_PASA_ANTES}" "$(cut -d' ' -f1-3 "$T/ensayo.txt") $(resumen_ensayo < "$T/ensayo.txt")"
  paso "(f) el pago real quedó confirmado y sellado; del ensayo no quedó nada" "^${CUOTA_0101} · ${CUENTA_01}\\|registro · 0 · 0 ${revertidos}\$" "$(head -1 "$T/pago.txt") · $(sello "$CUOTA_0101") · $(aplicada) · $(rastro)"
  volver_a_antes "(f) misma cuota"
  ( pago_en_vuelo "$CUOTA_0102" 4 > "$T/pago.txt" 2>&1 ) &
  en_vuelo pago-en-vuelo
  ( Q_NOMBRE=ensayo cronometrado ensayo > "$T/ensayo.txt" ) &
  paso "(f) pago real en vuelo de OTRA cuota del mismo contrato: el ensayo espera en la fila del contrato" "^ensayo espera a pago-en-vuelo ${ESPERA_FILA_CONTRATO}" "$(ver_espera)"
  wait
  paso "(f) al confirmar el pago, el ensayo sigue: PASA" "${ESPERO}${E_PASA_ANTES}" "$(cut -d' ' -f1-3 "$T/ensayo.txt") $(resumen_ensayo < "$T/ensayo.txt")"
  volver_a_antes "(f) otra cuota"
  ( pago_en_vuelo "$CUOTA_0101" 8 > "$T/pago.txt" 2>&1 ) &
  en_vuelo pago-en-vuelo
  j=$(Q_NOMBRE=ensayo cronometrado ensayo); echo "$j" > "$SALIDA/ensayo-falla-pago-lento.txt"
  paso "(f) si el pago tarda más de 5 s: FALLA, y el fallo es un «lock timeout», no la regla" '^5\.[0-9] s · veredicto=FALLA · todo_como_se_esperaba=false · vinculados=4 · 10 como se esperaba, 1 no, 0 sin probar · conexion=postgres/postgres · fallos=\["contrato REZAGO-01 \(ya estaba bien, caso ok\): bloqueada canceling statement due to lock timeout"\] · sin_probar=\[\]$' "$(cut -d' ' -f1-3 <<<"$j") $(resumen_ensayo <<<"$j")"
  wait
  paso "(f) el pago real quedó confirmado y sellado; del ensayo no quedó nada" "^${CUOTA_0101} · ${CUENTA_01}\\|registro · 0 · 0 ${revertidos}\$" "$(head -1 "$T/pago.txt") · $(sello "$CUOTA_0101") · $(aplicada) · $(rastro)"
  volver_a_antes "(f) pago lento"
  # Al revés: el ENSAYO en vuelo (una copia con 4 s de pausa antes de su error final) y llegan DOS pagos reales: el de
  # esa misma cuota de REZAGO-01, y uno de REZAGO-03, que el ensayo acaba de vincular (y de pagar) DENTRO de su transacción.
  ( Q_NOMBRE=ensayo ensayo "$T/ensayo-con-pausa.sql" > "$T/ensayo.txt" ) &
  en_vuelo ensayo
  echo "  candados de tabla del ensayo en vuelo: $(candados_de ensayo)"
  ( Q_NOMBRE=pago-ok cronometrado pagar "$CUOTA_0101" > "$T/pago.txt" ) &
  ( Q_NOMBRE=pago-rezago cronometrado pagar "$CUOTA_0301" > "$T/pago-rezago.txt" ) &
  paso "(f) con el ENSAYO en vuelo, los dos pagos reales esperan al ensayo, cada uno en su cuota" '^pago-ok espera a ensayo \[Lock/transactionid · fila de cronograma_pagos\] · pago-rezago espera a ensayo \[Lock/transactionid · fila de cronograma_pagos\]$' "$(ver_espera 2)"
  wait
  paso "(f) el ensayo termina (PASA) y se deshace" "^${E_PASA_ANTES}" "$(resumen_ensayo < "$T/ensayo.txt")"
  paso "(f) el pago del contrato ok sigue: confirmado y sellado" "${ESPERO}${CUOTA_0101} · ${CUENTA_01}\\|registro\$" "$(cat "$T/pago.txt") · $(sello "$CUOTA_0101")"
  paso "(f) el pago de REZAGO-03 NO se cuela por el vínculo que el ensayo deshizo: rechazado como siempre" "${ESPERO}ERROR:  Sin cuenta de pago — requiere conciliación · pendiente · sin sello\$" "$(cat "$T/pago-rezago.txt") · $(q "select estado from public.cronograma_pagos where id = '$CUOTA_0301';") · $(sello "$CUOTA_0301")"
  volver_a_antes "(f) ensayo en vuelo"
  prueba_paso "prueba ANTES" antes

  tramo "8 · migración"
  # Tres filas de conciliación que NO deben cancelarla: otra clase, otra moneda y otro motivo.
  conciliar contrato "$CLIENTE_D" USD perfil_invalido >/dev/null
  conciliar perfil "$CLIENTE_D" PEN perfil_invalido >/dev/null
  paso "conciliación que no aplica (otra clase · otra moneda · otro motivo)" '^3 filas' "$(conciliar perfil "$CLIENTE_C" PEN perfil_conflictivo)"
  paso "migración" '^NOTICE:  REZAGO: antes .*"una_cuenta": 4.* vinculados 4 \{REZAGO-03,REZAGO-04,REZAGO-05,REZAGO-06\}' "$(msg "$M")"
  paso "se quitan las tres filas" '^0 filas' "$(quitar_conciliacion)"
  prueba_paso "prueba DESPUÉS" despues
  local e_despues c_despues
  e_despues=$(estado); c_despues=$(conteos)
  echo "  foto DESPUÉS: $e_despues"
  echo "  conteos:      $c_despues"
  paso "rastro: 4 vigentes" "^4 ${revertidos}\$" "$(rastro)"
  paso "censo.sql corre y cuenta lo mismo que la prueba" '"ok": 6' "$(q "$(cat "$CENSO")" | tr -d '\n' | grep -o '"por_caso": {[^}]*}')"
  # A quién se le dice el detalle, con una conexión REAL como authenticator (como entra PostgREST).
  local GENERICO='^ERROR:  Sin cuenta de pago — requiere conciliación$'
  local DETALLE_07='^ERROR:  Contrato REZAGO-07 sin cuenta de pago: el cliente tiene 2 cuentas en soles; confirma con él en cuál cobra este contrato\.$'
  paso "API sin claims, rol anon: genérico" "$GENERICO" "$(api_inserta_pagada anon '' '' "$REZAGO_07")"
  paso "API sin claims, rol authenticated: genérico" "$GENERICO" "$(api_inserta_pagada authenticated '' '' "$REZAGO_07")"
  paso "API sin claims, rol service_role: genérico" "$GENERICO" "$(api_inserta_pagada service_role '' '' "$REZAGO_07")"
  paso "API con claims de anon: genérico" "$GENERICO" "$(api_inserta_pagada anon anon '' "$REZAGO_07")"
  paso "API con claims del analista: genérico" "$GENERICO" "$(api_inserta_pagada authenticated authenticated "$ANALISTA" "$REZAGO_07")"
  paso "API con claims de la gestora (admin): el motivo" "$DETALLE_07" "$(api_inserta_pagada authenticated authenticated "$ADMIN" "$REZAGO_07")"
  paso "API con claims de service_role: el motivo" "$DETALLE_07" "$(api_inserta_pagada service_role service_role '' "$REZAGO_07")"
  paso "conexión directa (postgres, sin claims): el motivo" "$DETALLE_07" "$(ultima "begin; insert into public.cronograma_pagos (contrato_id, numero_cuota, fecha_programada, monto_programado, estado, monto_pagado, fecha_pago_real) values ('$REZAGO_07', 91, current_date, 100, 'pagado', 100, current_date); rollback;")"
  igual "esas ocho pruebas no dejaron nada" "$e_despues" "$(estado)"
  trinquetes > "$SALIDA/trinquetes-con.txt"
  if diff -q "$SALIDA/trinquetes-sin.txt" "$SALIDA/trinquetes-con.txt" >/dev/null; then
    paso "trinquetes: idénticos sin y con la migración" '^idénticos' "idénticos ($(grep -c 'pasa$' "$SALIDA/trinquetes-con.txt") pasan, $(grep -c 'cae:' "$SALIDA/trinquetes-con.txt") caen igual, censo igual)"
  else
    paso "trinquetes: idénticos sin y con la migración" '^idénticos' "¡CAMBIARON! $(diff "$SALIDA/trinquetes-sin.txt" "$SALIDA/trinquetes-con.txt" | head -4 | tr '\n' ' ' | cut -c1-240)"
  fi

  tramo "9 · migración otra vez (idempotencia)"
  paso "migración repetida: no vincula nada" '^NOTICE:  REZAGO: antes .* vinculados 0 \{\}' "$(msg "$M")"
  igual "misma foto tras repetir" "$e_despues" "$(estado)"
  igual "mismos conteos (ni vínculos ni rastro ni bitácora de más)" "$c_despues" "$(conteos)"
  paso "sin filas repetidas" 'contratos_con_dos_vinculos=0 .*contratos_con_dos_rastros_vigentes=0 ' "$(conteos)"
  prueba_paso "prueba DESPUÉS" despues

  tramo "10 · el ENSAYO con la migración aplicada"
  # Aplicada: 4 casos bloqueados + 0 vinculados (ya estaba hecho) + 1 que ya estaba bien + 2 identidades = 7.
  j=$(ensayo); echo "$j" > "$SALIDA/ensayo-aplicada.txt"
  paso "termina en ENSAYO_DESHECHO" '^ERROR:  ENSAYO_DESHECHO >> \{' "$(cut -c1-60 <<<"$j")…"
  paso "PASA · no vinculó nada (ya estaba hecho) · 7 pagos e identidades como se esperaba" '^veredicto=PASA · todo_como_se_esperaba=true · vinculados=0 · 7 como se esperaba, 0 no, 0 sin probar · conexion=postgres/postgres · fallos=\[\] · sin_probar=\[\]$' "$(resumen_ensayo <<<"$j")"
  echo "  JSON del ensayo con la migración aplicada: $j"
  j=$(ensayo_tras "$SIN_ANALISTA"); echo "$j" > "$SALIDA/ensayo-aplicada-incompleto.txt"
  paso "sin analista activo: INCOMPLETO" '^veredicto=INCOMPLETO · todo_como_se_esperaba=false · vinculados=0 · 6 como se esperaba, 0 no, 0 sin probar · conexion=postgres/postgres · fallos=\[\] · sin_probar=\["identidad: falta un gestor de cartera vigente o un analista activo con quien probar"\]$' "$(resumen_ensayo <<<"$j")"
  # Un ensayo mutante aquí no llega a ensayar nada: su preflight espera el bloqueo anterior o el suyo, y el vivo es el real.
  paso "un ensayo mutante no corre con la migración real aplicada (lo para su propio preflight)" "$HUELLA_MIG" "$(ensayo "$T/ensayo-deja-pasar.sql" | cut -c1-260)"
  igual "no dejaron nada: misma foto" "$e_despues" "$(estado)"
  igual "no dejaron nada: mismos conteos (bitácora incluida)" "$c_despues" "$(conteos)"

  tramo "11 · reversa: todo vuelve al estado ANTES"
  paso "reversa" '^NOTICE:  REVERSA: 4 vínculos de la carga borrados' "$(msg "$R")"
  prueba_paso "prueba ANTES" antes
  igual "misma foto que antes de aplicar" "$e_antes" "$(estado)"
  paso "rastro: ninguno vigente y 4 más con revertida_en" "^0 $((revertidos + 4))\$" "$(rastro)"
  paso "reversa repetida: no hace nada" '^NOTICE:  REVERSA: 0 vínculos de la carga borrados' "$(msg "$R")"
  igual "tras repetirla, la misma foto" "$e_antes" "$(estado)"
  revertidos=$((revertidos + 4))

  tramo "12 · volver a aplicar"
  paso "migración" '^NOTICE:  REZAGO: antes .* vinculados 4 ' "$(msg "$M")"
  prueba_paso "prueba DESPUÉS" despues
  paso "rastro: 4 vigentes y los revertidos de antes" "^4 ${revertidos}\$" "$(rastro)"
  local e_limpio; e_limpio=$(estado)

  tramo "13 · huellas y guardas: lo que hace negarse a cada archivo (y nada cambia)"
  local fn
  local NO_SON='^ERROR:  VINCULAR: el bloqueo o el diagnóstico vivos no son los de la migración 20261001233019; no se toca nada'
  local NO_APLICADA='^ERROR:  REGISTRO: la migración 20261001233019 no está aplicada; aplícala primero'
  paso "bloqueo alterado: la migración" "$HUELLA_MIG" "$(con_funcion_alterada "$BLOQUEO" "$M")"
  paso "bloqueo alterado: reversa.sql" "$HUELLA_REV" "$(con_funcion_alterada "$BLOQUEO" "$R")"
  paso "bloqueo alterado: reversa-solo-codigo.sql" "$HUELLA_REV" "$(con_funcion_alterada "$BLOQUEO" "$RC")"
  paso "bloqueo alterado: vincular-rezago.sql" "$NO_SON" "$(con_funcion_alterada "$BLOQUEO" "$VR")"
  paso "bloqueo alterado: registrar.sql" "$NO_APLICADA" "$(con_funcion_alterada "$BLOQUEO" "$REGISTRAR")"
  for fn in 'private.cuenta_pago_diagnostico(uuid[])' 'private.cuentas_pago_motivos_autorizado(uuid[])' 'crm.cuentas_pago_motivos_fn(uuid[])'; do
    paso "$fn alterada: la migración" '^ERROR:  REZAGO PREFLIGHT: alguna función de esta migración ya existe con otro cuerpo; no se pisa' "$(con_funcion_alterada "$fn" "$M")"
    paso "$fn alterada: reversa.sql" '^ERROR:  REVERSA: alguna función de la migración cambió después; no se toca' "$(con_funcion_alterada "$fn" "$R")"
    paso "$fn alterada: reversa-solo-codigo.sql" '^ERROR:  REVERSA: alguna función de la migración cambió después; no se toca' "$(con_funcion_alterada "$fn" "$RC")"
    paso "$fn alterada: vincular-rezago.sql" "$NO_SON" "$(con_funcion_alterada "$fn" "$VR")"
    paso "$fn alterada: registrar.sql" "$NO_APLICADA" "$(con_funcion_alterada "$fn" "$REGISTRAR")"
  done
  # Las demás guardas, cada una provocada dentro de una transacción que se deshace.
  paso "authenticated sin USAGE sobre private: la migración se niega" '^ERROR:  REZAGO PREFLIGHT: authenticated necesita USAGE sobre crm y private' "$(tras "revoke usage on schema private from authenticated;" "$M")"
  paso "un disparador del bloqueo apagado: la migración se niega" '^ERROR:  REZAGO PREFLIGHT: los triggers del bloqueo de pagos no están como se espera' "$(tras "alter table public.cronograma_pagos disable trigger trg_cronograma_pagos_10_exigir_cuenta_pago_update;" "$M")"
  paso "el disparador de coherencia apagado: la migración se niega" '^ERROR:  REZAGO PREFLIGHT: faltan los triggers de coherencia o de bitácora del vínculo' "$(tras "alter table crm.contrato_cuentas_pago disable trigger trg_contrato_cuenta_pago_coherente;" "$M")"
  paso "la bitácora del vínculo apagada: vincular-rezago.sql se niega" '^ERROR:  VINCULAR: faltan los triggers de coherencia o de bitácora del vínculo' "$(tras "alter table crm.contrato_cuentas_pago disable trigger trg_audit_contrato_cuentas_pago;" "$VR")"
  paso "aplicada por quien no es el dueño (supabase_admin): se niega" '^ERROR:  REZAGO PREFLIGHT: quien aplica \(supabase_admin\) no es el dueño del bloqueo de pagos' "$(ultima "$(cat "$M")" supabase_admin)"
  paso "un vínculo de la carga sustituido por otro: reversa.sql se niega" '^ERROR:  REVERSA: se esperaban 4 vínculos de la carga y se encontraron 3; no se borra nada' "$(tras "delete from crm.contrato_cuentas_pago where contrato_id = '$REZAGO_06'; insert into crm.contrato_cuentas_pago (contrato_id, cuenta_bancaria_id) values ('$REZAGO_06', '$CUENTA_09');" "$R")"
  igual "nada cambió" "$e_limpio" "$(estado)"
  # (a) El aislamiento: los cuatro archivos se niegan en REPEATABLE READ y en SERIALIZABLE (aquí reversa.sql borraría
  # 4 vínculos y reversa-solo-codigo.sql repondría el bloqueo anterior: la foto dice que no lo hicieron).
  for nivel in 'repeatable read' serializable; do
    opciones="$RR"; [ "$nivel" = serializable ] && opciones="$SER"
    paso "en $nivel: la migración se niega" "^ERROR:  REZAGO PREFLIGHT: la transacción debe ir en READ COMMITTED \\(va en $nivel\\)\$" "$(Q_OPCIONES="$opciones" msg "$M")"
    paso "en $nivel: vincular-rezago.sql se niega" "^ERROR:  VINCULAR: la transacción debe ir en READ COMMITTED \\(va en $nivel\\)\$" "$(Q_OPCIONES="$opciones" msg "$VR")"
    paso "en $nivel: reversa.sql se niega" "^ERROR:  REVERSA: la transacción debe ir en READ COMMITTED \\(va en $nivel\\)\$" "$(Q_OPCIONES="$opciones" msg "$R")"
    paso "en $nivel: reversa-solo-codigo.sql se niega" "^ERROR:  REVERSA: la transacción debe ir en READ COMMITTED \\(va en $nivel\\)\$" "$(Q_OPCIONES="$opciones" msg "$RC")"
  done
  igual "en otro aislamiento nada cambió" "$e_limpio" "$(estado)"

  tramo "14 · negativas de reversa.sql (en todas: no cambia nada)"
  local e_x c_x r_x
  local NEGATIVA='^ERROR:  REVERSA: el contrato REZAGO-03 ya registró un pago, un cambio de cuenta o un PDF con su vínculo; no se borra nada'
  # 14a · un pago sellado
  paso "pago confirmado de REZAGO-03 (cuota 1) por la RPC" "^${CUOTA_0301}\$" "$(pagar "$CUOTA_0301")"
  paso "sellado en la cuenta que vinculó la carga" "^${CUENTA_04}\\|registro\$" "$(sello "$CUOTA_0301")"
  e_x=$(estado); c_x=$(conteos); r_x=$(rastro)
  paso "con un pago sellado: la reversa se niega" "$NEGATIVA" "$(msg "$R")"
  igual "no cambió nada (foto)" "$e_x" "$(estado)"; igual "no cambió nada (conteos)" "$c_x" "$(conteos)"; igual "no cambió nada (rastro)" "$r_x" "$(rastro)"
  paso "se retira el pago" '^restos limpios$' "$(limpiar_restos)"
  igual "el banco vuelve a la foto de antes" "$e_limpio" "$(estado)"
  # 14b · un cambio de cuenta
  paso "cambio de cuenta confirmado en REZAGO-03" '^1 cambio registrado$' "$(cambiar_cuenta)"
  e_x=$(estado); c_x=$(conteos); r_x=$(rastro)
  paso "con un cambio de cuenta: la reversa se niega" "$NEGATIVA" "$(msg "$R")"
  igual "no cambió nada (foto)" "$e_x" "$(estado)"; igual "no cambió nada (conteos)" "$c_x" "$(conteos)"; igual "no cambió nada (rastro)" "$r_x" "$(rastro)"
  paso "se retira el cambio" '^restos limpios$' "$(limpiar_restos)"
  igual "el banco vuelve a la foto de antes" "$e_limpio" "$(estado)"
  # 14c · un PDF en curso (private.contrato_pdf_jobs)
  paso "un PDF en curso para REZAGO-03 (contrato_pdf_jobs)" '^1 trabajo$' "$(ultima "insert into private.contrato_pdf_jobs (id, contrato_id, storage_path, nombre_archivo, snapshot, solicitado_por)
     values ('$PDF_JOB', '$REZAGO_03', '$REZAGO_03/v2/$PDF_JOB/contrato.pdf', 'contrato-ficticio-del-ciclo.pdf', '{}'::jsonb, '$ADMIN');
     select count(*) || ' trabajo' from private.contrato_pdf_jobs;")"
  e_x=$(estado); c_x=$(conteos); r_x=$(rastro)
  paso "con un PDF en curso: la reversa se niega" "$NEGATIVA" "$(msg "$R")"
  igual "no cambió nada (foto)" "$e_x" "$(estado)"; igual "no cambió nada (conteos)" "$c_x" "$(conteos)"; igual "no cambió nada (rastro)" "$r_x" "$(rastro)"
  paso "se retira el PDF" '^restos limpios$' "$(limpiar_restos)"
  # 14d · un PDF ya generado (private.contrato_pdfs, plantilla v1: sin trabajo)
  paso "un PDF generado para REZAGO-03 (contrato_pdfs)" '^1 archivo$' "$(ultima "insert into private.contrato_pdfs (contrato_id, storage_path, nombre_archivo, sha256, bytes, template_version, snapshot, generado_por)
     values ('$REZAGO_03', '$REZAGO_03/contrato.pdf', 'contrato-ficticio-del-ciclo.pdf', repeat('a', 64), 1024, 'contrato-aep-17-v1', '{}'::jsonb, '$ADMIN');
     select count(*) || ' archivo' from private.contrato_pdfs;")"
  e_x=$(estado); c_x=$(conteos); r_x=$(rastro)
  paso "con un PDF generado: la reversa se niega" "$NEGATIVA" "$(msg "$R")"
  igual "no cambió nada (foto)" "$e_x" "$(estado)"; igual "no cambió nada (conteos)" "$c_x" "$(conteos)"; igual "no cambió nada (rastro)" "$r_x" "$(rastro)"
  paso "se retira el PDF" '^restos limpios$' "$(limpiar_restos)"
  igual "el banco vuelve a la foto de antes" "$e_limpio" "$(estado)"
  # 14e · un disparador de sello apagado (sin sellos no se puede saber si un vínculo se usó): cada uno de los dos
  local sello_trg
  for sello_trg in trg_cronograma_pagos_20_sellar_cuenta_update trg_cronograma_pagos_20_sellar_cuenta_insert; do
    paso "se apaga $sello_trg" '^apagado$' "$(ultima "alter table public.cronograma_pagos disable trigger $sello_trg; select 'apagado';")"
    e_x=$(estado); c_x=$(conteos); r_x=$(rastro)
    paso "con ese sello apagado: la reversa se niega" '^ERROR:  REVERSA: los triggers que sellan la cuenta de cada pago no están habilitados' "$(msg "$R")"
    igual "no cambió nada (foto)" "$e_x" "$(estado)"; igual "no cambió nada (conteos)" "$c_x" "$(conteos)"; igual "no cambió nada (rastro)" "$r_x" "$(rastro)"
    paso "se vuelve a encender" '^restos limpios$' "$(limpiar_restos)"
    igual "el banco vuelve a la foto de antes" "$e_limpio" "$(estado)"
  done
  prueba_paso "prueba DESPUÉS" despues

  tramo "15 · pagos en vuelo frente a reversa.sql (y al ENSAYO) con la migración aplicada, a dos sesiones"
  # (e) Un pago de un contrato que vinculó la carga (REZAGO-03) confirmándose, y reversa.sql en la otra sesión.
  ( pago_en_vuelo "$CUOTA_0301" 4 > "$T/pago.txt" 2>&1 ) &
  en_vuelo pago-en-vuelo
  ( Q_NOMBRE=reversa cronometrado msg "$R" > "$T/reversa.txt" ) &
  paso "(e) reversa.sql espera al pago en vuelo, en la fila del contrato" "^reversa espera a pago-en-vuelo ${ESPERA_FILA_CONTRATO}" "$(ver_espera)"
  wait
  paso "(e) al confirmar el pago, la reversa sigue, ve el sello y SE NIEGA" "${ESPERO}ERROR:  REVERSA: el contrato REZAGO-03 ya registró un pago, un cambio de cuenta o un PDF con su vínculo; no se borra nada" "$(cat "$T/reversa.txt")"
  paso "(e) el pago quedó confirmado y sellado; la migración sigue aplicada con sus 4 vínculos" "^${CUOTA_0301} · ${CUENTA_04}\\|registro · 1 · 4 ${revertidos}\$" "$(head -1 "$T/pago.txt") · $(sello "$CUOTA_0301") · $(aplicada) · $(rastro)"
  paso "se retira el pago" '^restos limpios$' "$(limpiar_restos)"
  igual "el banco vuelve a la foto de antes" "$e_limpio" "$(estado)"
  ( pago_en_vuelo "$CUOTA_0301" 8 > "$T/pago.txt" 2>&1 ) &
  en_vuelo pago-en-vuelo
  paso "(e) si el pago tarda más de 5 s, la reversa se cancela sin borrar nada" "$SE_CANCELO" "$(Q_NOMBRE=reversa cronometrado msg "$R")"
  wait
  paso "(e) la migración sigue aplicada con sus 4 vínculos; el pago, confirmado" "^${CUOTA_0301} · 1 · 4 ${revertidos}\$" "$(head -1 "$T/pago.txt") · $(aplicada) · $(rastro)"
  paso "se retira el pago" '^restos limpios$' "$(limpiar_restos)"
  igual "el banco vuelve a la foto de antes" "$e_limpio" "$(estado)"
  # Los otros dos «usos» de un vínculo, también en vuelo: un cambio de cuenta (con los candados de la puerta real) y un
  # PDF en curso (su clave foránea toma la fila del contrato). La reversa espera en el contrato y, al seguir, se niega.
  ( cambio_cuenta_en_vuelo 4 >/dev/null 2>&1 ) &
  en_vuelo cambio-de-cuenta
  ( Q_NOMBRE=reversa cronometrado msg "$R" > "$T/reversa.txt" ) &
  paso "(e) reversa.sql espera a un cambio de cuenta en vuelo, en la fila del contrato" "^reversa espera a cambio-de-cuenta ${ESPERA_FILA_CONTRATO}" "$(ver_espera)"
  wait
  paso "(e) al confirmar el cambio, la reversa sigue y SE NIEGA" "${ESPERO}ERROR:  REVERSA: el contrato REZAGO-03 ya registró un pago, un cambio de cuenta o un PDF con su vínculo; no se borra nada" "$(cat "$T/reversa.txt")"
  paso "(e) el cambio quedó confirmado; la migración sigue aplicada con sus 4 vínculos" "^1 cambio · ${CUENTA_05} · 1 · 4 ${revertidos}\$" "$(q "select count(*) || ' cambio' from crm.contrato_cuenta_pago_cambios;") · $(q "select cuenta_bancaria_id from crm.contrato_cuentas_pago where contrato_id = '$REZAGO_03';") · $(aplicada) · $(rastro)"
  paso "se retira el cambio" '^restos limpios$' "$(limpiar_restos)"
  igual "el banco vuelve a la foto de antes" "$e_limpio" "$(estado)"
  ( pdf_en_vuelo 4 >/dev/null 2>&1 ) &
  en_vuelo pdf-en-vuelo
  ( Q_NOMBRE=reversa cronometrado msg "$R" > "$T/reversa.txt" ) &
  paso "(e) reversa.sql espera a un PDF en curso en vuelo, en la fila del contrato" "^reversa espera a pdf-en-vuelo ${ESPERA_FILA_CONTRATO}" "$(ver_espera)"
  wait
  paso "(e) al confirmar el PDF, la reversa sigue y SE NIEGA" "${ESPERO}ERROR:  REVERSA: el contrato REZAGO-03 ya registró un pago, un cambio de cuenta o un PDF con su vínculo; no se borra nada" "$(cat "$T/reversa.txt")"
  paso "(e) el PDF quedó confirmado; la migración sigue aplicada con sus 4 vínculos" "^1 trabajo · 1 · 4 ${revertidos}\$" "$(q "select count(*) || ' trabajo' from private.contrato_pdf_jobs;") · $(aplicada) · $(rastro)"
  paso "se retira el PDF" '^restos limpios$' "$(limpiar_restos)"
  igual "el banco vuelve a la foto de antes" "$e_limpio" "$(estado)"
  # (f) con la migración aplicada: el ENSAYO frente a un pago real lento del contrato que elige (REZAGO-01).
  ( pago_en_vuelo "$CUOTA_0101" 8 > "$T/pago.txt" 2>&1 ) &
  en_vuelo pago-en-vuelo
  j=$(Q_NOMBRE=ensayo cronometrado ensayo); echo "$j" > "$SALIDA/ensayo-aplicada-falla-pago-lento.txt"
  paso "(f) con la migración aplicada y un pago real lento: el ENSAYO da FALLA por «lock timeout»" '^5\.[0-9] s · veredicto=FALLA · todo_como_se_esperaba=false · vinculados=0 · 6 como se esperaba, 1 no, 0 sin probar · conexion=postgres/postgres · fallos=\["contrato REZAGO-01 \(ya estaba bien, caso ok\): bloqueada canceling statement due to lock timeout"\] · sin_probar=\[\]$' "$(cut -d' ' -f1-3 <<<"$j") $(resumen_ensayo <<<"$j")"
  wait
  paso "se retira el pago" '^restos limpios$' "$(limpiar_restos)"
  igual "el banco vuelve a la foto de antes" "$e_limpio" "$(estado)"
  # (e) Al revés: la REVERSA en vuelo (entera, sin confirmar) y llega un pago de REZAGO-03.
  ( Q_NOMBRE=reversa archivo_en_vuelo "$R" 4 > "$T/reversa.txt" 2>&1 ) &
  en_vuelo reversa
  echo "  candados de tabla de la reversa en vuelo: $(candados_de reversa)"
  ( Q_NOMBRE=pago cronometrado pagar "$CUOTA_0301" > "$T/pago.txt" ) &
  paso "(e) con la REVERSA en vuelo, un pago de REZAGO-03 espera a la reversa en la fila del contrato" "^pago espera a reversa ${ESPERA_FILA_CONTRATO}" "$(ver_espera)"
  wait
  paso "(e) al confirmar la reversa, el pago es RECHAZADO con el texto de antes" "${ESPERO}ERROR:  Sin cuenta de pago — requiere conciliación\$" "$(cat "$T/pago.txt")"
  paso "(e) la reversa borró sus 4 vínculos" '^NOTICE:  REVERSA: 4 vínculos de la carga borrados' "$(grep -o 'NOTICE:  REVERSA.*' "$T/reversa.txt" | tail -1)"
  revertidos=$((revertidos + 4))
  volver_a_antes "(e) reversa en vuelo"
  paso "migración (se vuelve a aplicar para seguir)" '^NOTICE:  REZAGO: antes .* vinculados 4 ' "$(msg "$M")"
  # (e) MUTANTE: reversa.sql SIN la guarda, en REPEATABLE READ, con el pago en vuelo.
  ( pago_en_vuelo "$CUOTA_0301" 4 > "$T/pago.txt" 2>&1 ) &
  en_vuelo pago-en-vuelo
  ( Q_OPCIONES="$RR" Q_NOMBRE=reversa cronometrado msg "$T/reversa-sin-guarda.sql" > "$T/reversa.txt" ) &
  paso "MUTANTE reversa sin la guarda, en repeatable read: espera igual" "^reversa espera a pago-en-vuelo ${ESPERA_FILA_CONTRATO}" "$(ver_espera)"
  wait
  paso "MUTANTE: al seguir NO ve el sello (fotografía vieja) y BORRA los 4 vínculos" "${ESPERO}NOTICE:  REVERSA: 4 vínculos de la carga borrados" "$(cat "$T/reversa.txt")"
  paso "MUTANTE: el daño — cuota pagada y sellada en una cuenta que ya no es la del contrato" "^pagado · ${CUENTA_04}\\|registro · 0 vínculos\$" "$(q "select estado from public.cronograma_pagos where id = '$CUOTA_0301';") · $(sello "$CUOTA_0301") · $(q "select count(*) || ' vínculos' from crm.contrato_cuentas_pago where contrato_id = '$REZAGO_03';")"
  revertidos=$((revertidos + 4))
  volver_a_antes "mutante"
  paso "migración (se vuelve a aplicar para seguir)" '^NOTICE:  REZAGO: antes .* vinculados 4 ' "$(msg "$M")"
  paso "rastro: 4 vigentes y los revertidos de antes" "^4 ${revertidos}\$" "$(rastro)"
  e_limpio=$(estado)   # los vínculos de la carga tienen ids nuevos
  prueba_paso "prueba DESPUÉS" despues

  tramo "16 · reversa solo del código"
  paso "reversa-solo-codigo.sql" "$SIN_ERROR" "$(msg "$RC")"
  prueba_paso "prueba SOLO CÓDIGO: bloqueo anterior, 3 funciones fuera, vínculos intactos y pagables" solo_codigo
  paso "rastro: los 4 siguen vigentes" "^4 ${revertidos}\$" "$(rastro)"
  paso "vincular-rezago.sql se niega (el diagnóstico ya no está)" '^ERROR:  VINCULAR: el bloqueo o el diagnóstico vivos no son los de la migración' "$(msg "$VR")"
  paso "volver a aplicar la migración funciona y no vincula de nuevo" '^NOTICE:  REZAGO: antes .* vinculados 0 \{\}' "$(msg "$M")"
  igual "misma foto que antes de revertir el código" "$e_limpio" "$(estado)"
  prueba_paso "prueba DESPUÉS" despues
  # El caso para el que existe: ya hay un pago, la reversa completa se niega y la del código sí pasa.
  paso "pago confirmado de REZAGO-03 (cuota 1)" "^${CUOTA_0301}\$" "$(pagar "$CUOTA_0301")"
  paso "la reversa completa se niega" "$NEGATIVA" "$(msg "$R")"
  paso "la reversa solo del código pasa" "$SIN_ERROR" "$(msg "$RC")"
  paso "el pago y su sello siguen" "^pagado/${CUENTA_04}\\|registro\$" "$(q "select estado from public.cronograma_pagos where id = '$CUOTA_0301';")/$(sello "$CUOTA_0301")"
  paso "bloqueo anterior, funciones fuera, 8 vínculos" "^${MD5_ANTERIOR} 0 8\$" "$(q "select md5(p.prosrc) || ' ' || $(aplicada) || ' ' || (select count(*) from crm.contrato_cuentas_pago) from pg_proc p where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure;")"
  paso "con el bloqueo anterior el contrato se sigue pagando (cuota 2, deshecho)" "^${CUOTA_0302}\$" "$(intento_pago "$CUOTA_0302")"
  paso "se retira el pago" '^restos limpios$' "$(limpiar_restos)"
  prueba_paso "prueba SOLO CÓDIGO" solo_codigo
  paso "reversa completa desde solo-código: borra los 4 vínculos sin usar" '^NOTICE:  REVERSA: 4 vínculos de la carga borrados' "$(msg "$R")"
  revertidos=$((revertidos + 4))
  prueba_paso "prueba ANTES" antes
  igual "misma foto que antes de aplicar" "$e_antes" "$(estado)"

  tramo "17 · vincular-rezago.sql: la carga, sola"
  paso "migración" '^NOTICE:  REZAGO: antes .* vinculados 4 ' "$(msg "$M")"
  local marca_dia c_y
  marca_dia=$(q "select 'carga:rezago-vinculos:' || to_char(now() at time zone 'America/Lima', 'YYYYMMDD');")
  local e_11; e_11=$(estado)
  paso "sin nada que vincular: no hace nada" '^NOTICE:  REZAGO: antes .* vinculados 0 \{\}' "$(msg "$VR")"
  igual "misma foto" "$e_11" "$(estado)"
  # A dos sesiones. Operaciones le registra a J (REZAGO-11, sin_cuenta) su cuenta en dólares, y OTRA sesión le registra
  # una SEGUNDA mientras la carga suelta espera el candado. El archivo real no vincula; sin la guarda y en REPEATABLE READ, sí.
  local ALTA_J="insert into crm.cuentas_bancarias (id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci, origen, creado_por) values ('$CUENTA_J_USD', '$CLIENTE_J', 'USD', 'Interbank', 'ahorros', '89899000000092', '00389900000000000092', 'portal', '$ADMIN'); select count(*) || ' cuentas' from crm.cuentas_bancarias;"
  local DOS_DE_J="select (select count(*) from crm.contrato_cuentas_pago where contrato_id = '$REZAGO_11') || ' vínculo · ' || (select count(*) from crm.cuentas_bancarias where cliente_id = '$CLIENTE_J' and moneda = 'USD' and activa) || ' cuentas USD activas';"
  local ESPERA_CUENTA_V='^vincular espera a registra-cuenta \[Lock/relation · tabla crm\.cuentas_bancarias en ExclusiveLock\]$'
  paso "J recibe su cuenta en dólares (REZAGO-11 pasa a una_cuenta)" '^22 cuentas$' "$(ultima "$ALTA_J")"
  ( registra_cuenta "$CUENTA_J_SEGUNDA" "$CLIENTE_J" USD 4 97 ) &
  en_vuelo registra-cuenta
  ( Q_NOMBRE=vincular cronometrado msg "$VR" > "$T/vincular.txt" ) &
  paso "vincular-rezago.sql REAL espera a quien registra la segunda cuenta" "$ESPERA_CUENTA_V" "$(ver_espera)"
  wait
  paso "al seguir ve las DOS cuentas y NO vincula REZAGO-11" "${ESPERO}NOTICE:  REZAGO: antes .* vinculados 0 \\{\\}" "$(cat "$T/vincular.txt")"
  paso "REZAGO-11 sin vínculo y con dos cuentas" '^0 vínculo · 2 cuentas USD activas$' "$(q "$DOS_DE_J")"
  paso "se retiran las dos cuentas" '^restos limpios$' "$(limpiar_restos)"
  igual "misma foto" "$e_11" "$(estado)"
  paso "J recibe otra vez su cuenta en dólares" '^22 cuentas$' "$(ultima "$ALTA_J")"
  ( registra_cuenta "$CUENTA_J_SEGUNDA" "$CLIENTE_J" USD 4 97 ) &
  en_vuelo registra-cuenta
  ( Q_OPCIONES="$RR" Q_NOMBRE=vincular cronometrado msg "$T/vincular-sin-guarda.sql" > "$T/vincular.txt" ) &
  paso "MUTANTE vincular sin la guarda, en repeatable read: espera igual" "$ESPERA_CUENTA_V" "$(ver_espera)"
  wait
  paso "MUTANTE: al seguir VINCULA REZAGO-11 con la fotografía vieja" "${ESPERO}NOTICE:  REZAGO: antes .* vinculados 1 \\{REZAGO-11\\}" "$(cat "$T/vincular.txt")"
  paso "MUTANTE: REZAGO-11 vinculado teniendo DOS cuentas" '^1 vínculo · 2 cuentas USD activas$' "$(q "$DOS_DE_J")"
  paso "se retira lo del mutante (cuentas, vínculo y rastro de la carga suelta)" '^restos limpios$' "$(limpiar_restos)"
  igual "misma foto" "$e_11" "$(estado)"
  # Operaciones registra la cuenta en dólares que les faltaba a H (otra_moneda) y a J (sin_cuenta).
  paso "se registran dos cuentas USD: a H y a J" '^23 cuentas$' "$(ultima "insert into crm.cuentas_bancarias (id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci, origen, creado_por) values
       ('$CUENTA_H_USD', '$CLIENTE_H', 'USD', 'BCP', 'ahorros', '19199000000091', '00219900000000000091', 'portal', '$ADMIN'),
       ('$CUENTA_J_USD', '$CLIENTE_J', 'USD', 'Interbank', 'ahorros', '89899000000092', '00389900000000000092', 'portal', '$ADMIN');
     select count(*) || ' cuentas' from crm.cuentas_bancarias;")"
  paso "REZAGO-09 y REZAGO-11 pasan a una_cuenta" '^cuenta_no_corresponde=2 ok=6 otra_moneda=1 sin_cuenta=2 una_cuenta=2 varias_cuentas=2$' "$(censo)"
  paso "todavía no se pagan: el motivo dice que falta vincular" '^ERROR:  Contrato REZAGO-09 sin cuenta de pago: el cliente ya tiene una cuenta en dólares; falta vincularla a este contrato\.$' "$(intento_pago "$CUOTA_0901")"
  paso "vincular-rezago.sql vincula exactamente esos dos" '^NOTICE:  REZAGO: antes .*"una_cuenta": 2.* vinculados 2 \{REZAGO-09,REZAGO-11\}' "$(msg "$VR")"
  paso "con la marca del día, creado_por null, a la cuenta registrada" "^REZAGO-09→${CUENTA_H_USD}\\|null\\|${marca_dia} · REZAGO-11→${CUENTA_J_USD}\\|null\\|${marca_dia}\$" "$(q "select string_agg(ct.numero_contrato || '→' || l.cuenta_bancaria_id || '|' || coalesce(l.creado_por::text, 'null') || '|' || b.marca_actor, ' · ' order by ct.numero_contrato)
       from private.backfill_cuentas_p0xx b join crm.contrato_cuentas_pago l on l.id = b.fila_id and l.contrato_id = b.contrato_id
       join public.contratos ct on ct.id = b.contrato_id
       where b.tipo = 'vinculo' and b.marca_actor like 'carga:rezago-vinculos:%' and b.revertida_en is null and b.cliente_id = ct.cliente_id;")"
  paso "bitácora: un alta por cada vínculo nuevo" '^2$' "$(q "select count(*) from public.audit_log a join private.backfill_cuentas_p0xx b on b.fila_id::text = a.fila_id
       where a.tabla = 'crm.contrato_cuentas_pago' and a.operacion = 'INSERT' and b.marca_actor like 'carga:rezago-vinculos:%';")"
  paso "los 4 de la migración intactos · 2 de la carga · 10 vínculos · censo" "^4 ${revertidos} · 2 0 · 10 · cuenta_no_corresponde=2 ok=8 otra_moneda=1 sin_cuenta=2 varias_cuentas=2\$" "$(rastro) · $(rastro_cargas) · $(q "select count(*) from crm.contrato_cuentas_pago;") · $(censo)"
  paso "REZAGO-09 ya se paga (deshecho)" "^${CUOTA_0901}\$" "$(intento_pago "$CUOTA_0901")"
  paso "REZAGO-11 ya se paga (deshecho)" "^${CUOTA_1101}\$" "$(intento_pago "$CUOTA_1101")"
  e_x=$(estado); c_y=$(conteos)
  paso "vincular-rezago.sql otra vez: no hace nada" '^NOTICE:  REZAGO: antes .* vinculados 0 \{\}' "$(msg "$VR")"
  igual "misma foto" "$e_x" "$(estado)"; igual "mismos conteos" "$c_y" "$(conteos)"
  paso "reversa.sql borra SOLO los 4 de la migración" '^NOTICE:  REVERSA: 4 vínculos de la carga borrados' "$(msg "$R")"
  revertidos=$((revertidos + 4))
  paso "quedan los 2 de vincular-rezago (6 vínculos), con su rastro vigente" "^0 ${revertidos} · 2 0 · 6\$" "$(rastro) · $(rastro_cargas) · $(q "select count(*) from crm.contrato_cuentas_pago;")"
  paso "bloqueo anterior y funciones fuera" "^${MD5_ANTERIOR} 0\$" "$(q "select md5(p.prosrc) || ' ' || $(aplicada) from pg_proc p where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure;")"
  paso "REZAGO-09 se sigue pagando con el bloqueo anterior (deshecho)" "^${CUOTA_0901}\$" "$(intento_pago "$CUOTA_0901")"
  paso "REZAGO-03 vuelve a estar bloqueado (texto genérico)" '^ERROR:  Sin cuenta de pago — requiere conciliación$' "$(intento_pago "$CUOTA_0301")"
  paso "se retira lo del tramo (cuentas, vínculos y rastro de la carga suelta)" '^restos limpios$' "$(limpiar_restos)"
  igual "el banco vuelve a ANTES" "$e_antes" "$(estado)"
  prueba_paso "prueba ANTES" antes

  tramo "18 · mutantes"
  paso "mutantes generados en un directorio temporal" '^[1-9][0-9]* mutantes$' "$(generar_mutantes 2>&1 | tail -1)"
  [ "$SALIDA" != "$T" ] && { rm -rf "$SALIDA/mutantes"; cp -R "$T/mutantes" "$SALIDA/mutantes"; }
  echo "  · del bloqueo ANTERIOR, con la prueba ANTES (inyectados después de T0, que fija su md5):"
  correr_mutantes a
  echo "  · de la MIGRACIÓN real, dentro de la transacción de la prueba DESPUÉS (m00 es el control sin tocar):"
  correr_mutantes m
  echo "  · dobles (además se quita la defensa de la propia migración):"
  correr_mutantes d
  igual "los mutantes no dejaron nada: el banco sigue en ANTES" "$e_antes" "$(estado)"
  # m20: sin concurrencia nadie ve que falta el candado; con una cuenta a medio registrar, la migración NO espera.
  paso "m20 con una cuenta a medio registrar: NO espera (lo contrario de lo que exige el tramo 4)" '^[0-2] s · NOTICE:  REZAGO: antes ' "$(con_cuenta_a_medias "$T/mutantes/m20-migracion-sin-candado.sql")"
  paso "se revierte el mutante aplicado" '^NOTICE:  REVERSA: 4 vínculos de la carga borrados' "$(msg "$R")"
  revertidos=$((revertidos + 4))
  igual "el banco vuelve a ANTES" "$e_antes" "$(estado)"
  # m33: en una sola sesión y en READ COMMITTED nadie nota que falta la guarda; a dos sesiones la cazó el tramo 5.
  igual "m33 es la misma copia que el tramo 5 lanzó a dos sesiones (y vinculó un contrato con dos cuentas)" "$(md5_de "$T/migracion-sin-guarda.sql")" "$(md5_de "$T/mutantes/m33-migracion-sin-guarda.sql")"

  tramo "19 · tiempos y estado final: migración aplicada y registrada"
  # Los dos bloqueos, alternados dos veces: así una deriva del banco no se confunde con una diferencia.
  echo "  bloqueo ANTERIOR · $(tiempos)"
  paso "migración" '^NOTICE:  REZAGO: antes .* vinculados 4 ' "$(msg "$M")"
  echo "  bloqueo NUEVO    · $(tiempos)"
  paso "reversa (segunda ronda de tiempos)" '^NOTICE:  REVERSA: 4 vínculos de la carga borrados' "$(msg "$R")"
  revertidos=$((revertidos + 4))
  echo "  bloqueo ANTERIOR · $(tiempos)"
  paso "migración" '^NOTICE:  REZAGO: antes .* vinculados 4 ' "$(msg "$M")"
  echo "  bloqueo NUEVO    · $(tiempos)"
  paso "registrar.sql" '^NOTICE:  REGISTRO: 20261001233019 / crm_cuentas_pago_motivo_y_rezago \(1 sentencia' "$(msg "$REGISTRAR")"
  paso "registrar.sql otra vez (idempotente)" '^NOTICE:  REGISTRO: 20261001233019 / crm_cuentas_pago_motivo_y_rezago \(1 sentencia' "$(msg "$REGISTRAR")"
  paso "una fila, 1 sentencia, con el md5 del archivo" "^1 fila · 1 sentencia · ${md5_migracion}\$" "$(q "select count(*) || ' fila · ' || max(cardinality(statements)) || ' sentencia · ' || max(md5(statements[1])) from supabase_migrations.schema_migrations where version = '$VERSION';")"
  prueba_paso "prueba DESPUÉS" despues
  paso "rastro: 4 vigentes" "^4 ${revertidos}\$" "$(rastro)"
  paso "ninguna sesión quedó abierta ni esperando" '^0 sesiones$' "$(q "select count(*) || ' sesiones' from pg_stat_activity where pid <> pg_backend_pid() and backend_type = 'client backend';" supabase_admin)"
  echo "  foto final: $(estado)"
  fin
}

# Si se carga con `source`, solo define las funciones (para lanzar un tramo a mano).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  principal "$@"
fi
