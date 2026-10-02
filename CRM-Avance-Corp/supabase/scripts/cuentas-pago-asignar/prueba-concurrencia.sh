#!/usr/bin/env bash
# Prueba de CONCURRENCIA de 20261002005004_crm_asignar_cuenta_pago (T9): dos sesiones de verdad que
# se cruzan. SOLO en el banco Docker propio, con la siembra común, la siembra extra y la migración
# aplicada. Nunca contra producción. A diferencia de test-asignar-cuenta-pago.sql, aquí las cosas se
# CONFIRMAN (dos sesiones no se ven si no): al empezar y al terminar se limpia el mundo de la siembra
# extra y al final se comprueba que quedó igual que antes.
#
#   BANCO_CONTENEDOR=avancecorp-cuentas-asignar-20261001 bash prueba-concurrencia.sh
#   SOLO="A D F" bash prueba-concurrencia.sh        # solo esos casos (lo usan los mutantes de ciclo.sh)
#   REVERSA_SQL=/ruta/reversa-alterada.sql …        # para probar una reversa alterada
#
# Cada sesión «en vuelo» hace su trabajo, espera con pg_sleep y confirma; la otra entra cuando el
# banco dice que la primera YA está esperando (pg_stat_activity), así que el cruce es seguro y no
# depende del reloj. Las sesiones de la API entran como authenticator (con sus 8 s de lock_timeout
# y statement_timeout, como PostgREST), fijan los claims en las dos formas y hacen SET ROLE.
# «✓ / ✗» son comprobaciones; «△ MEDIDO» es un hecho que se mide y se anota, sin contar.
#
# Casos:
#   A   dos asignaciones a la vez al MISMO contrato con cuentas distintas → gana una; la otra espera y
#       recibe «ya tiene cuenta de pago» (22023), nunca el 23505 crudo
#   A2  la primera se deshace (ROLLBACK) → la segunda espera y entonces SÍ asigna
#   A3  la MISMA solicitud dos veces a la vez (doble clic) → una sola asignación; la segunda, ya_aplicada
#   A4  la misma solicitud a la vez con OTRA cuenta → «Esta solicitud ya se usó con otros datos»
#   B1  alguien tiene bloqueado el contrato como lo bloquea un pago (FOR UPDATE) → la asignación espera y termina bien
#   B2  una asignación sin confirmar y llega un pago → el pago espera, encuentra el vínculo y queda sellado
#   C1  otra sesión tiene «lock table crm.cuentas_bancarias in exclusive mode» (la carga de 20261001233019)
#       → la asignación espera y termina bien
#   C2  lo mismo con lock_timeout corto → cae con 55P03 y no deja nada escrito
#   D   retiran la cuenta en vuelo (las sentencias del retiro de F4: FOR UPDATE y activa = false) → la
#       asignación espera y recibe «ya no está vigente»
#   F   cierran el contrato en vuelo → la asignación espera y recibe «está cerrado»
#   G1  la asignación en REPEATABLE READ → 0A000 y nada escrito (también para quien no es administración)
#   G2  la asignación en SERIALIZABLE → 0A000 y nada escrito
#   G3  doble clic con la segunda llamada en REPEATABLE READ → 0A000 (sin la guarda diría «ya tiene cuenta de pago»)
#   G4  una administradora revocada DESPUÉS de la fotografía de una transacción REPEATABLE READ → 0A000 y nada
#       escrito (sin la guarda asignaría, viéndola aún vigente); control: en READ COMMITTED recibe 42501
#   E1  la reversa con una asignación sin confirmar → espera, la ve y solo CIERRA la puerta (nada borrado);
#       después reabrir-puerta.sql la reabre
#   E2  la reversa con una asignación que tarda más que su lock_timeout → cae sin cambiar nada
#   E3  la reversa en REPEATABLE READ con una asignación sin confirmar → se niega y no borra nada
#   E4  la reversa retira todo mientras una llamada ya había entrado (esperando el candado de su solicitud)
#       → esa llamada falla limpia y no escribe nada
#   E5  el límite que avisa reversa.sql: con asignaciones registradas, la llamada que ya había entrado
#       se completa DESPUÉS de cerrada la puerta
#   H1  F4 (crm.retirar_cuenta_cliente, en READ COMMITTED) retira una cuenta, sin confirmar, y llega su
#       asignación → espera y recibe «ya no está vigente»            H1b  lo mismo con F4 en REPEATABLE READ
#   H2  una asignación sin confirmar y F4 (READ COMMITTED) quiere retirar esa cuenta → F4 espera y se niega
#   H3  una asignación sin confirmar y F4 en REPEATABLE READ → △ MEDIDO: qué hace F4 (riesgo previo de F4)
#   H4  F4 en REPEATABLE READ con la fotografía anterior a una asignación ya confirmada → △ MEDIDO
#   Los casos H necesitan que F4 compile, y F4 declara storage.objects (%rowtype), que la imagen no trae:
#   mientras duran se crea en el banco un DOBLE mínimo de esa tabla y al terminar se quita.
#   R1  la carga automática (cuentas-pago-rezago/vincular-rezago.sql) en vuelo, con su candado EXCLUSIVE de
#       cuentas tomado, y llega «Asignar» sobre su candidato → Asignar espera; la carga lo vincula (sin
#       autor, con su rastro) y Asignar recibe «ya tiene cuenta de pago»; ninguna constancia
#   R2  al revés: «Asignar» sin confirmar sobre el candidato y se lanza la carga → la carga espera en su
#       «lock table»; al confirmar, ya no ve candidato (0 vinculados); un vínculo (de la admin) y una constancia
#   R3  lo mismo, con la asignación tardando más que el lock_timeout de la carga (5 s) → la carga cae por
#       lock_timeout sin dejar nada, y la asignación queda
#   Los casos R solo corren con la otra migración (20261001233019) aplicada; sin ella dicen NO APLICA. Su
#   candidato es ASIGNAR-05 (dólares): se le retira al cliente la cuenta en dólares que le sobra (x05), y
#   el contrato queda con UNA sola cuenta activa en su moneda y sin vínculo, que es para lo que existe
#   vincular-rezago.sql. Al terminar, la cuenta vuelve a estar vigente y el vínculo y su rastro se quitan.
set -uo pipefail
C="${BANCO_CONTENEDOR:-avancecorp-cuentas-asignar-20261001}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRACION="${MIGRACION_SQL:-$DIR/../../migrations/20261002005004_crm_asignar_cuenta_pago.sql}"
REVERSA="${REVERSA_SQL:-$DIR/reversa.sql}"
REABRIR="${REABRIR_SQL:-$DIR/reabrir-puerta.sql}"
VINCULAR="${VINCULAR_SQL:-$DIR/../cuentas-pago-rezago/vincular-rezago.sql}"
SOLO="${SOLO:-A A2 A3 A4 B1 B2 C1 C2 D F G1 G2 G3 G4 E1 E2 E3 E4 E5 H1 H1b H2 H3 H4 R1 R2 R3}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

PUERTA='crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'
NUCLEO='private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'
ADMIN='c9e00000-0000-4000-8000-000000000001'
SUPER='a5190000-0000-4000-8000-000000000031'
ADMIN_EQUIPO='a5190000-0000-4000-8000-000000000034'   # admin con membresía CRM vigente: la que se revoca en G4
OPER='c9e00000-0000-4000-8000-000000000002'
CLIENTE_P='a5190000-0000-4000-8000-000000000041'
MOTIVO='Operaciones confirmó con el cliente en cuál cobra'
k() { printf 'a519d000-0000-4000-8000-0000000000%02d' "$1"; }      # contrato ASIGNAR-NN
x() { printf 'a519c000-0000-4000-8000-0000000000%02d' "$1"; }      # cuenta de la siembra extra
s() { printf 'a519a000-0000-4000-8000-0000000090%02d' "$1"; }      # solicitud
cuota() { printf 'a519e000-0000-4000-8000-00000000%02d%02d' "$1" "$2"; }
YA_TIENE='ya tiene cuenta de pago; para cambiarla usa «Cambiar cuenta de pago»'
NO_ADMITE='ERR:0A000:La asignación no admite este modo de transacción'
CERRADA='^PUERTA_CERRADA: nadie puede asignar; no se borró nada \(las constancias y los vínculos siguen\)$'
RETIRADA='^RETIRADA: no queda la puerta, el núcleo ni la tabla de constancias$'

psql_as() { local u="$1"; shift; docker exec -i -e PGPASSWORD=postgres "$C" psql -U "$u" -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt "$@"; }
q() { psql_as postgres -c "$1" 2>&1 </dev/null; }
# Lo que dejó un mensaje, con sus dos canales por separado ($1.out = filas, $1.err = avisos y errores): su
# primer ERROR; si no, su última fila no vacía; y si no dio filas, su último aviso. `docker exec` no conserva
# el orden entre los dos canales, así que «la última línea» de la mezcla no es de fiar.
resultado_de_canales() {
  if grep -q 'ERROR:' "$1.err" 2>/dev/null; then grep -m1 -o 'ERROR:.*' "$1.err" | cut -c1-240
  elif grep -q . "$1.out" 2>/dev/null; then grep . "$1.out" | tail -1
  else grep . "$1.err" 2>/dev/null | tail -1; fi
}
# Un archivo en UN mensaje, como postgres (el veredicto viaja como fila).
# Con $2 = un nivel de aislamiento, la conexión nace con ese nivel por defecto (un SET delante en el
# mismo mensaje no sirve: el «begin» del archivo no abre una transacción nueva, hereda la del mensaje).
archivo() {
  local f; f=$(mktemp "$T/archivo.XXXXXX")
  if [ -n "${2:-}" ]; then
    docker exec -i -e PGPASSWORD=postgres -e "PGOPTIONS=-c default_transaction_isolation=${2// /\\ }" "$C" \
      psql -U postgres -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "$(cat "$1")" > "$f.out" 2> "$f.err" </dev/null
  else
    psql_as postgres -c "$(cat "$1")" > "$f.out" 2> "$f.err" </dev/null
  fi
  resultado_de_canales "$f"
  rm -f "$f" "$f.out" "$f.err"
}

ok=0; mal=0
esperar() { # $1 caso · $2 esperado (regex) · $3 obtenido
  if [[ "$3" =~ $2 ]]; then echo "  ✓ $1"; ok=$((ok + 1)); else echo "  ✗ $1 — esperado /$2/, obtenido: $3"; mal=$((mal + 1)); fi
}
medido() { echo "  △ MEDIDO $1: $2"; }
quiere() { case " $SOLO " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# ── Sesiones ─────────────────────────────────────────────────────────────────────────────────
# Así entra PostgREST: authenticator (con sus timeouts de 8 s), claims en las dos formas y SET ROLE.
api() { # $1 = uid
  echo "set local lock_timeout = '8s'; set local statement_timeout = '8s';
        select set_config('request.jwt.claim.sub', '$1', true), set_config('request.jwt.claim.role', 'authenticated', true),
               set_config('request.jwt.claims', json_build_object('sub', '$1', 'role', 'authenticated')::text, true);
        set local session authorization authenticator; set local role authenticated;"
}
# Una llamada «en vuelo»: se hace, espera $4 segundos y termina con $5 (commit | rollback). Va en segundo plano.
en_vuelo() { # $1 marca · $2 uid · $3 expresión · $4 segundos · $5 commit|rollback · $6 aislamiento (por defecto READ COMMITTED)
  psql_as supabase_admin -c "begin transaction isolation level ${6:-read committed}; $(api "$2")
     select 'EN_VUELO $1 ' || ($3)::text;
     select pg_sleep($4) /* $1 */; ${5:-commit};" > "$T/$1.out" 2>&1 </dev/null &
}
# Otra sesión que mantiene algo tomado $2 segundos (como el usuario $3, por defecto postgres). En segundo plano.
ocupa() { # $1 marca · $2 segundos · $3 usuario · $4 sentencias
  psql_as "${3:-postgres}" -c "begin; $4 select pg_sleep($2) /* $1 */; commit;" > "$T/$1.out" 2>&1 </dev/null &
}
# No sigue hasta que el banco dice que la sesión de la marca YA está esperando (dormida o en un candado).
cruzar() { # $1 marca · $2 evento de espera (PgSleep | advisory | …)
  local i visto='' raro=''
  for i in $(seq 1 100); do
    visto=$(q "select count(*) from pg_stat_activity where query like '%$1%' and wait_event = '${2:-PgSleep}' and pid <> pg_backend_pid()")
    [ "$visto" = "1" ] && return 0
    [ "$visto" = "0" ] || [ -n "$raro" ] || raro="sondeo $i: $visto"
    sleep 0.1
  done
  echo "  ✗ la sesión $1 no llegó a esperar (${2:-PgSleep}); sondeos distintos de 0 y de 1: «$(tr '\n' ' ' <<<"${raro:-ninguno}" | cut -c1-200)»; su salida: $(cat "$T/$1.out" 2>/dev/null | tr '\n' ' ' | cut -c1-200)"; mal=$((mal + 1)); return 1
}
# El bloque que hace UNA llamada como usuario de la API y dice qué pasó, sin abortar la transacción.
llamada() { # $1 uid · $2 expresión · $3 lock_timeout
  cat <<SQL
do \$m\$
declare r text; t0 constant timestamptz := clock_timestamp();
begin
  perform set_config('lock_timeout', '${3:-8s}', true), set_config('statement_timeout', '8s', true),
          set_config('request.jwt.claim.sub', '$1', true), set_config('request.jwt.claim.role', 'authenticated', true),
          set_config('request.jwt.claims', json_build_object('sub', '$1', 'role', 'authenticated')::text, true);
  execute 'set local session authorization authenticator';
  execute 'set local role authenticated';
  begin
    execute \$e\$select ($2)::text\$e\$ into r;
    r := 'OK:' || coalesce(r, '(null)');
  exception when others then
    r := 'ERR:' || sqlstate || ':' || sqlerrm;
  end;
  raise notice 'RESULTADO % ESPERA_MS %', r, (extract(epoch from clock_timestamp() - t0) * 1000)::integer;
end \$m\$;
SQL
}
# Una llamada OBSERVADA: «RESULTADO OK:<valor>|ERR:<sqlstate>:<mensaje> ESPERA_MS <n>».
observada() { # $1 uid · $2 expresión · $3 aislamiento (por defecto READ COMMITTED) · $4 lock_timeout
  psql_as supabase_admin -c "begin transaction isolation level ${3:-read committed};
$(llamada "$1" "$2" "${4:-8s}")
commit;" 2>&1 </dev/null | grep -o 'RESULTADO .*' | tail -1
}
# Una transacción que fija su fotografía, espera $2 segundos y ENTONCES hace la llamada. En segundo plano.
con_foto() { # $1 marca · $2 segundos · $3 aislamiento · $4 uid · $5 expresión
  psql_as supabase_admin -c "begin transaction isolation level $3;
select count(*) from crm.equipo;
select pg_sleep($2) /* $1 */;
$(llamada "$4" "$5")
commit;" > "$T/$1.out" 2>&1 </dev/null &
}
resultado_de() { grep -o 'RESULTADO .*' "$T/$1.out" | tail -1; }
aplicada() { q "select (to_regclass('crm.contrato_cuenta_pago_asignaciones') is not null and to_regprocedure('$PUERTA') is not null and to_regprocedure('$NUCLEO') is not null)::int"; }
# Por catálogo, nunca llamando: sin EXECUTE bajo SET ROLE este Postgres se cae.
abierta() { q "select (has_function_privilege('authenticated', '$PUERTA', 'EXECUTE') and has_function_privilege('authenticated', '$NUCLEO', 'EXECUTE'))::int"; }
expresion_asignar() { echo "crm.asignar_cuenta_pago_contrato('$1', '$2', '$3', '$MOTIVO')"; }   # solicitud · contrato · cuenta
expresion_retirar() { echo "crm.retirar_cuenta_cliente('$1', '$CLIENTE_P', '$2', 'El cliente pidió retirar esta cuenta', null)"; }   # solicitud · cuenta
asignar() { # $1 uid · $2 solicitud · $3 contrato · $4 cuenta · $5 lock_timeout · $6 aislamiento
  if [ "$(abierta)" != "1" ]; then echo "RESULTADO NO SE LLAMA: authenticated no tiene EXECUTE (llamar tumbaría este Postgres)"; return; fi
  observada "$1" "$(expresion_asignar "$2" "$3" "$4")" "${6:-read committed}" "${5:-8s}"
}
pagar() { observada "$OPER" "crm.registrar_pago_con_cuenta('$1', (now() at time zone 'America/Lima')::date, 100, null)"; }   # $1 cuota
retirar() { observada "$ADMIN" "$(expresion_retirar "$1" "$2")" "${3:-read committed}"; }   # solicitud · cuenta · aislamiento
espera_ms() { sed -n 's/.* ESPERA_MS \([0-9]*\)$/\1/p' <<<"$1"; }
espero() { [ "$(espera_ms "$1")" -ge "${2:-1500}" ] 2>/dev/null && echo sí || echo "no ($(espera_ms "$1") ms)"; }
vinculo() { q "select coalesce((select cuenta_bancaria_id || '|' || coalesce(creado_por::text, '(null)') from crm.contrato_cuentas_pago where contrato_id = '$1'), 'sin vínculo')"; }
constancias() { q "select count(*) from crm.contrato_cuenta_pago_asignaciones where contrato_id = '$1'"; }
cuenta_activa() { q "select activa from crm.cuentas_bancarias where id = '$1'"; }
retiros() { q "select count(*) from crm.cuentas_bancarias_retiros where cuenta_id = '$1'"; }

# SOLO BANCO. Deja el mundo de la siembra extra como se sembró: sin constancias, sin los vínculos que
# crearon, sin sellos ni retiros, con las cuotas pendientes, las cuentas vigentes, el contrato de prueba
# activo, la administradora de G4 con su membresía vigente y sin el rastro de carga de sus contratos (casos
# R). Va como supabase_admin y en modo réplica porque constancias, sellos y retiros no se borran (sus
# disparadores lo impiden, con razón). La bitácora (public.audit_log) es de solo añadir: no se toca.
limpiar() {
  psql_as supabase_admin -c "
    set session_replication_role = replica;
    do \$l\$ begin
      if to_regclass('crm.contrato_cuenta_pago_asignaciones') is not null then
        delete from crm.contrato_cuentas_pago l using crm.contrato_cuenta_pago_asignaciones a where l.id = a.vinculo_id;
        delete from crm.contrato_cuenta_pago_asignaciones;
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
    update crm.equipo set activo = true where perfil_id = '$ADMIN_EQUIPO' and not activo;
    set session_replication_role = origin;" >/dev/null 2>&1 </dev/null
}
# La foto del mundo que la prueba puede tocar (todo menos la bitácora).
huella() {
  q "set timezone = 'UTC';
     select 'vinculos=' || (select count(*) || ':' || md5(coalesce(string_agg(md5(to_jsonb(v)::text), ',' order by v.id), '')) from crm.contrato_cuentas_pago v)
         || ' cuentas=' || (select count(*) || ':' || md5(coalesce(string_agg(md5(to_jsonb(v)::text), ',' order by v.id), '')) from crm.cuentas_bancarias v)
         || ' contratos=' || (select count(*) || ':' || md5(coalesce(string_agg(md5(to_jsonb(v)::text), ',' order by v.id), '')) from public.contratos v)
         || ' cuotas=' || (select count(*) || ':' || md5(coalesce(string_agg(md5(to_jsonb(v)::text), ',' order by v.id), '')) from public.cronograma_pagos v)
         || ' equipo=' || (select count(*) || ':' || md5(coalesce(string_agg(v.perfil_id::text || v.rol_crm || v.activo::text, ',' order by v.perfil_id), '')) from crm.equipo v)
         || ' sellos=' || (select count(*) from crm.cuotas_cuenta_pagada)
         || ' retiros=' || (select count(*) from crm.cuentas_bancarias_retiros)
         || ' constancias=' || (select count(*) from crm.contrato_cuenta_pago_asignaciones)
         || ' rastro=' || (select count(*) || ':' || count(*) filter (where b.revertida_en is null) from private.backfill_cuentas_p0xx b)
         || ' puerta=' || (select md5(p.prosrc) || coalesce(p.proacl::text, '') from pg_proc p where p.oid = '$PUERTA'::regprocedure)
         || ' nucleo=' || (select md5(p.prosrc) || coalesce(p.proacl::text, '') from pg_proc p where p.oid = '$NUCLEO'::regprocedure)
         || ' storage.objects=' || coalesce(to_regclass('storage.objects')::text, '(no existe)');" | grep -v '^SET$'
}
# El doble de storage.objects para que F4 compile en sesiones distintas (solo si la imagen no lo trae).
DOBLE=0
con_doble_de_storage() {
  [ "$(q "select to_regclass('storage.objects') is null")" = "t" ] || return 0
  psql_as supabase_admin -c "create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text,
       owner uuid, owner_id text, metadata jsonb, created_at timestamptz default now());
     comment on table storage.objects is 'DOBLE de prueba-concurrencia.sh (asignar cuenta de pago): se quita al terminar';
     grant select on storage.objects to postgres;" >/dev/null 2>&1 </dev/null && DOBLE=1
}
sin_doble_de_storage() {
  [ "$DOBLE" = "1" ] || return 0
  psql_as supabase_admin -c "drop table storage.objects;" >/dev/null 2>&1 </dev/null; DOBLE=0
}
# ── La carga automática de la otra migración (casos R) ──
otra_aplicada() { q "select (to_regprocedure('private.cuenta_pago_diagnostico(uuid[])') is not null)::int"; }
ahora_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }
# Los interbloqueos que ha contado el servidor en esta base (un 40P01 saldría además en la sesión que lo sufre).
interbloqueos() { q "select deadlocks from pg_stat_database where datname = current_database()"; }
# SOLO BANCO. Deja ASIGNAR-05 como candidato de la carga: retira la cuenta en dólares que le sobra a su
# cliente (x05). Devuelve «caso/cuentas activas en su moneda/candidatos de la carga en todo el banco».
candidato_de_la_carga() {
  psql_as supabase_admin -c "set session_replication_role = replica;
    update crm.cuentas_bancarias set activa = false, desactivada_por = '$ADMIN', desactivada_en = now() where id = '$(x 5)';" >/dev/null 2>&1 </dev/null
  q "select d.caso || '/' || d.cuentas_en_moneda || '/' || (select count(*) from private.cuenta_pago_diagnostico() t where t.caso = 'una_cuenta')
     from private.cuenta_pago_diagnostico(array['$(k 5)']::uuid[]) d"
}
# El rastro vigente de carga de un contrato: «<cuántos>:<marca>» (la marca de vincular-rezago.sql lleva el día).
rastro_de_carga() { q "select count(*) || ':' || coalesce(string_agg(b.marca_actor, ','), '') from private.backfill_cuentas_p0xx b join crm.contrato_cuentas_pago l on l.id = b.fila_id and l.contrato_id = b.contrato_id where b.contrato_id = '$1' and b.tipo = 'vinculo' and b.revertida_en is null"; }
sin_abrazos() { # $1 $2 = las dos sesiones (sus .out y .err) · $3 = interbloqueos antes
  echo "$(cat "$T/$1.out" "$T/$1.err" "$T/$2.out" "$T/$2.err" 2>/dev/null | grep -ci 'deadlock\|40P01' | tr -d ' ')/$(cat "$T/$1.out" "$T/$1.err" "$T/$2.out" "$T/$2.err" 2>/dev/null | grep -ci 'lock timeout\|55P03' | tr -d ' ')/$(( $(interbloqueos) - $3 ))"
}
f4_listo() { q "select (to_regclass('storage.objects') is not null and has_function_privilege('authenticated', 'crm.retirar_cuenta_cliente(uuid,uuid,uuid,text,text)', 'EXECUTE') and has_function_privilege('authenticated', 'private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)', 'EXECUTE'))::int"; }

# ── Punto de partida ─────────────────────────────────────────────────────────────────────────
if [ "$(aplicada)" != "1" ]; then echo "La migración 20261002005004 no está aplicada en $C: aplícala antes (ciclo.sh lo hace)." >&2; exit 2; fi
if [ "$(abierta)" != "1" ]; then echo "La puerta está CERRADA en $C (reversa con asignaciones): limpia y reabre antes (ciclo.sh lo hace)." >&2; exit 2; fi
if [ "$(q "select count(*) from public.contratos where id::text like 'a519d000-%'")" != "13" ]; then echo "Falta la siembra extra en $C (siembra-extra.sql)." >&2; exit 2; fi
if [ "$(q "select has_function_privilege('authenticated', 'crm.registrar_pago_con_cuenta(uuid,date,numeric,text)', 'EXECUTE')::int")" != "1" ]; then echo "authenticated no puede ejecutar crm.registrar_pago_con_cuenta en $C: no se llama." >&2; exit 2; fi
limpiar
H0="$(huella)"

if quiere A; then
  echo "A · dos asignaciones a la vez al mismo contrato, con cuentas distintas"
  en_vuelo vueloA "$ADMIN" "$(expresion_asignar "$(s 1)" "$(k 6)" "$(x 1)")" 3 commit
  if cruzar vueloA; then
    r=$(asignar "$SUPER" "$(s 2)" "$(k 6)" "$(x 2)"); wait
    esperar "la segunda recibe «ya tiene cuenta de pago» (22023), no el 23505 crudo" "^RESULTADO ERR:22023:El contrato ASIGNAR-06 $YA_TIENE ESPERA_MS" "$r"
    esperar "la segunda ESPERÓ a la primera (≥ 1,5 s)" '^sí$' "$(espero "$r")"
    esperar "la primera se aplicó" 'EN_VUELO vueloA \{.*"ya_aplicada": false' "$(cat "$T/vueloA.out")"
    esperar "quedó UN vínculo: la cuenta de la primera, a nombre de quien la asignó" "^$(x 1)\|$ADMIN$" "$(vinculo "$(k 6)")"
    esperar "quedó UNA constancia, la de la primera solicitud" "^1/$(s 1)$" "$(constancias "$(k 6)")/$(q "select string_agg(solicitud_id::text, ',') from crm.contrato_cuenta_pago_asignaciones where contrato_id = '$(k 6)'")"
  else wait; fi
fi

if quiere A2; then
  echo "A2 · la primera asignación se deshace: la segunda espera y entonces asigna"
  en_vuelo vueloA2 "$ADMIN" "$(expresion_asignar "$(s 3)" "$(k 7)" "$(x 1)")" 3 rollback
  if cruzar vueloA2; then
    r=$(asignar "$SUPER" "$(s 4)" "$(k 7)" "$(x 2)"); wait
    esperar "la segunda asigna" '^RESULTADO OK:\{.*"ya_aplicada": false.* ESPERA_MS' "$r"
    esperar "la segunda ESPERÓ a que la primera terminara (≥ 1,5 s)" '^sí$' "$(espero "$r")"
    esperar "quedó el vínculo de la segunda (la primera no dejó nada)" "^$(x 2)\|$SUPER/1$" "$(vinculo "$(k 7)")/$(constancias "$(k 7)")"
  else wait; fi
fi

if quiere A3; then
  echo "A3 · la misma solicitud dos veces a la vez (doble clic)"
  en_vuelo vueloA3 "$ADMIN" "$(expresion_asignar "$(s 5)" "$(k 8)" "$(x 1)")" 3 commit
  if cruzar vueloA3; then
    r=$(asignar "$ADMIN" "$(s 5)" "$(k 8)" "$(x 1)"); wait
    esperar "la segunda recibe ya_aplicada (no «ya tiene cuenta de pago»)" '^RESULTADO OK:\{.*"ya_aplicada": true.* ESPERA_MS' "$r"
    esperar "la segunda ESPERÓ a la primera (≥ 1,5 s)" '^sí$' "$(espero "$r")"
    esperar "una sola constancia y un solo vínculo" "^1/$(x 1)\|$ADMIN$" "$(constancias "$(k 8)")/$(vinculo "$(k 8)")"
  else wait; fi
fi

if quiere A4; then
  echo "A4 · la misma solicitud a la vez, con otra cuenta"
  en_vuelo vueloA4 "$ADMIN" "$(expresion_asignar "$(s 6)" "$(k 9)" "$(x 1)")" 3 commit
  if cruzar vueloA4; then
    r=$(asignar "$ADMIN" "$(s 6)" "$(k 9)" "$(x 2)"); wait
    esperar "la segunda recibe «ya se usó con otros datos»" '^RESULTADO ERR:22023:Esta solicitud ya se usó con otros datos ESPERA_MS' "$r"
    esperar "quedó la cuenta de la primera" "^1/$(x 1)\|$ADMIN$" "$(constancias "$(k 9)")/$(vinculo "$(k 9)")"
  else wait; fi
fi

if quiere B1; then
  echo "B1 · el contrato está bloqueado como lo bloquea un pago (FOR UPDATE de su fila)"
  ocupa pagoB1 3 postgres "select 1 from public.contratos where id = '$(k 10)' for update;"
  if cruzar pagoB1; then
    r=$(asignar "$ADMIN" "$(s 7)" "$(k 10)" "$(x 1)"); wait
    esperar "la asignación termina bien (sin abrazo mortal)" '^RESULTADO OK:\{.*"ya_aplicada": false.* ESPERA_MS' "$r"
    esperar "la asignación ESPERÓ al candado del contrato (≥ 1,5 s)" '^sí$' "$(espero "$r")"
    esperar "la otra sesión terminó sin error" '^$' "$(grep -o 'ERROR.*\|deadlock' "$T/pagoB1.out" || true)"
    esperar "estado final: el contrato cobra en la cuenta asignada" "^$(x 1)\|$ADMIN$" "$(vinculo "$(k 10)")"
  else wait; fi
fi

if quiere B2; then
  echo "B2 · una asignación sin confirmar y llega el pago de una cuota del contrato"
  en_vuelo vueloB2 "$ADMIN" "$(expresion_asignar "$(s 8)" "$(k 11)" "$(x 2)")" 3 commit
  if cruzar vueloB2; then
    r=$(pagar "$(cuota 11 1)"); wait
    esperar "el pago pasa: al seguir ya encuentra el vínculo" "^RESULTADO OK:$(cuota 11 1) ESPERA_MS" "$r"
    esperar "el pago ESPERÓ a la asignación (≥ 1,5 s)" '^sí$' "$(espero "$r")"
    esperar "la cuota quedó pagada y sellada en la cuenta asignada" "^pagado\|$(x 2)\|registro$" "$(q "select c.estado || '|' || coalesce((select s.cuenta_bancaria_id || '|' || s.origen from crm.cuotas_cuenta_pagada s where s.cuota_id = c.id), 'sin sello') from public.cronograma_pagos c where c.id = '$(cuota 11 1)'")"
    esperar "la asignación terminó sin error" '^$' "$(grep -o 'ERROR.*\|deadlock' "$T/vueloB2.out" || true)"
  else wait; fi
fi

if quiere C1; then
  echo "C1 · otra sesión tiene «lock table crm.cuentas_bancarias in exclusive mode»"
  ocupa cargaC1 3 postgres "lock table crm.cuentas_bancarias in exclusive mode;"
  if cruzar cargaC1; then
    r=$(asignar "$ADMIN" "$(s 9)" "$(k 12)" "$(x 1)"); wait
    esperar "la asignación espera y termina bien" '^RESULTADO OK:\{.*"ya_aplicada": false.* ESPERA_MS' "$r"
    esperar "la asignación ESPERÓ al candado de la tabla (≥ 1,5 s)" '^sí$' "$(espero "$r")"
    esperar "quedó el vínculo y su constancia" "^$(x 1)\|$ADMIN/1$" "$(vinculo "$(k 12)")/$(constancias "$(k 12)")"
  else wait; fi
fi

if quiere C2; then
  echo "C2 · lo mismo, con lock_timeout de 1 s en quien asigna"
  ocupa cargaC2 3 postgres "lock table crm.cuentas_bancarias in exclusive mode;"
  if cruzar cargaC2; then
    r=$(asignar "$ADMIN" "$(s 10)" "$(k 13)" "$(x 1)" 1s); wait
    esperar "la asignación cae por lock_timeout (55P03)" '^RESULTADO ERR:55P03:canceling statement due to lock timeout ESPERA_MS' "$r"
    esperar "cayó a su segundo, sin esperar a la otra sesión" '^sí/sí$' "$(espero "$r" 900)/$([ "$(espera_ms "$r")" -lt 2500 ] && echo sí || echo no)"
    esperar "no dejó nada: ni vínculo ni constancia" '^sin vínculo/0/0$' "$(vinculo "$(k 13)")/$(constancias "$(k 13)")/$(q "select count(*) from crm.contrato_cuenta_pago_asignaciones where solicitud_id = '$(s 10)'")"
  else wait; fi
fi

if quiere D; then
  echo "D · retiran la cuenta mientras se asigna (las sentencias del retiro de F4: FOR UPDATE y activa = false)"
  ocupa retiroD 3 postgres "select 1 from crm.cuentas_bancarias where id = '$(x 6)' for update;
    update crm.cuentas_bancarias set activa = false, desactivada_por = '$ADMIN', desactivada_en = now() where id = '$(x 6)';"
  if cruzar retiroD; then
    r=$(asignar "$ADMIN" "$(s 11)" "$(k 1)" "$(x 6)"); wait
    esperar "la asignación espera al retiro y recibe «ya no está vigente»" '^RESULTADO ERR:22023:La cuenta elegida ya no está vigente ESPERA_MS' "$r"
    esperar "la asignación ESPERÓ al retiro (≥ 1,5 s)" '^sí$' "$(espero "$r")"
    esperar "no quedó vínculo hacia la cuenta retirada" '^sin vínculo/0$' "$(vinculo "$(k 1)")/$(constancias "$(k 1)")"
  else wait; fi
fi

if quiere F; then
  echo "F · cierran el contrato mientras se asigna"
  ocupa cierreF 3 supabase_admin "set local session_replication_role = replica; update public.contratos set estado = 'renovado' where id = '$(k 5)';"
  if cruzar cierreF; then
    r=$(asignar "$ADMIN" "$(s 12)" "$(k 5)" "$(x 3)"); wait
    esperar "la asignación espera al cierre y recibe «está cerrado»" '^RESULTADO ERR:22023:El contrato ASIGNAR-05 está cerrado \(renovado\) ESPERA_MS' "$r"
    esperar "la asignación ESPERÓ al cierre (≥ 1,5 s)" '^sí$' "$(espero "$r")"
    esperar "no quedó vínculo en el contrato cerrado" '^sin vínculo/0$' "$(vinculo "$(k 5)")/$(constancias "$(k 5)")"
  else wait; fi
fi

# ── La guarda de aislamiento del núcleo: solo se asigna en READ COMMITTED ─────────────────────
if quiere G1; then
  echo "G1 · la asignación en REPEATABLE READ"
  limpiar
  r=$(asignar "$ADMIN" "$(s 21)" "$(k 6)" "$(x 1)" 8s 'repeatable read')
  esperar "una administradora, con datos válidos, recibe 0A000" "^RESULTADO $NO_ADMITE ESPERA_MS" "$r"
  r=$(asignar "$OPER" "$(s 22)" "$(k 6)" "$(x 1)" 8s 'repeatable read')
  esperar "quien no es administración también recibe 0A000 (la guarda va antes que la compuerta)" "^RESULTADO $NO_ADMITE ESPERA_MS" "$r"
  esperar "nada escrito" '^sin vínculo/0$' "$(vinculo "$(k 6)")/$(constancias "$(k 6)")"
fi

if quiere G2; then
  echo "G2 · la asignación en SERIALIZABLE"
  limpiar
  r=$(asignar "$ADMIN" "$(s 23)" "$(k 6)" "$(x 1)" 8s 'serializable')
  esperar "recibe 0A000" "^RESULTADO $NO_ADMITE ESPERA_MS" "$r"
  esperar "nada escrito" '^sin vínculo/0$' "$(vinculo "$(k 6)")/$(constancias "$(k 6)")"
  r=$(asignar "$ADMIN" "$(s 23)" "$(k 6)" "$(x 1)" 8s 'read committed')
  esperar "control: la MISMA llamada en READ COMMITTED asigna" '^RESULTADO OK:\{.*"ya_aplicada": false.* ESPERA_MS' "$r"
fi

if quiere G3; then
  echo "G3 · doble clic con la segunda llamada en REPEATABLE READ"
  limpiar
  en_vuelo vueloG3 "$ADMIN" "$(expresion_asignar "$(s 24)" "$(k 7)" "$(x 1)")" 3 commit
  if cruzar vueloG3; then
    r=$(asignar "$ADMIN" "$(s 24)" "$(k 7)" "$(x 1)" 8s 'repeatable read'); wait
    esperar "la segunda recibe 0A000 (sin la guarda esperaría y diría «ya tiene cuenta de pago» en vez de ya_aplicada)" "^RESULTADO $NO_ADMITE ESPERA_MS" "$r"
    esperar "quedó una sola asignación, la de la primera" "^1/$(x 1)\|$ADMIN$" "$(constancias "$(k 7)")/$(vinculo "$(k 7)")"
  else wait; fi
fi

if quiere G4; then
  echo "G4 · una administradora revocada después de la fotografía de su transacción"
  limpiar
  con_foto fotoG4 3 'repeatable read' "$ADMIN_EQUIPO" "$(expresion_asignar "$(s 25)" "$(k 8)" "$(x 1)")"
  if cruzar fotoG4; then
    psql_as supabase_admin -c "set session_replication_role = replica; update crm.equipo set activo = false where perfil_id = '$ADMIN_EQUIPO';" >/dev/null 2>&1 </dev/null; wait
    esperar "testigo: la revocación quedó confirmada mientras la otra transacción esperaba" '^f$' "$(q "select activo from crm.equipo where perfil_id = '$ADMIN_EQUIPO'")"
    esperar "en REPEATABLE READ (su fotografía aún la ve vigente) recibe 0A000" "^RESULTADO $NO_ADMITE ESPERA_MS" "$(resultado_de fotoG4)"
    esperar "la administradora revocada no dejó nada escrito" '^sin vínculo/0$' "$(vinculo "$(k 8)")/$(constancias "$(k 8)")"
  else wait; fi
  limpiar
  con_foto fotoG4rc 3 'read committed' "$ADMIN_EQUIPO" "$(expresion_asignar "$(s 26)" "$(k 8)" "$(x 1)")"
  if cruzar fotoG4rc; then
    psql_as supabase_admin -c "set session_replication_role = replica; update crm.equipo set activo = false where perfil_id = '$ADMIN_EQUIPO';" >/dev/null 2>&1 </dev/null; wait
    esperar "control en READ COMMITTED: la misma secuencia ve la revocación y recibe 42501" '^RESULTADO ERR:42501:Solo administración puede asignar la cuenta de pago ESPERA_MS' "$(resultado_de fotoG4rc)"
    esperar "    y tampoco deja nada escrito" '^sin vínculo/0$' "$(vinculo "$(k 8)")/$(constancias "$(k 8)")"
  else wait; fi
  limpiar
fi

# ── La reversa, con asignaciones cruzándose ──────────────────────────────────────────────────
if quiere E1; then
  echo "E1 · la reversa con una asignación sin confirmar"
  limpiar
  en_vuelo vueloE1 "$ADMIN" "$(expresion_asignar "$(s 13)" "$(k 6)" "$(x 1)")" 3 commit
  if cruzar vueloE1; then
    r=$(archivo "$REVERSA"); wait
    esperar "la reversa espera, ve la asignación y solo cierra la puerta" "$CERRADA" "$r"
    esperar "la constancia y el vínculo de la asignación siguen" "^1/$(x 1)\|$ADMIN$" "$(constancias "$(k 6)")/$(vinculo "$(k 6)")"
    esperar "la puerta quedó cerrada (authenticated sin EXECUTE, por catálogo)" '^0$' "$(abierta)"
    esperar "reabrir-puerta.sql la reabre" '^PUERTA_REABIERTA$' "$(archivo "$REABRIR")"
    esperar "la puerta quedó abierta otra vez" '^1$' "$(abierta)"
  else wait; fi
  [ "$(aplicada)" = "1" ] || echo "    (la reversa retiró la migración; se reaplica: $(archivo "$MIGRACION"))"
  [ "$(abierta)" = "1" ] || { limpiar; echo "    (reabrir: $(archivo "$REABRIR"))"; }
fi

if quiere E2; then
  echo "E2 · la reversa con una asignación que tarda más que su lock_timeout (5 s)"
  limpiar
  en_vuelo vueloE2 "$ADMIN" "$(expresion_asignar "$(s 14)" "$(k 6)" "$(x 1)")" 7 commit
  if cruzar vueloE2; then
    r=$(archivo "$REVERSA"); wait
    esperar "la reversa cae por lock_timeout" '^ERROR:  canceling statement due to lock timeout' "$r"
    esperar "no cambió nada: la puerta sigue abierta y la asignación se confirmó" "^1/1/1$" "$(aplicada)/$(abierta)/$(constancias "$(k 6)")"
  else wait; fi
fi

if quiere E3; then
  echo "E3 · la reversa en REPEATABLE READ con una asignación sin confirmar"
  limpiar
  en_vuelo vueloE3 "$ADMIN" "$(expresion_asignar "$(s 15)" "$(k 6)" "$(x 1)")" 3 commit
  if cruzar vueloE3; then
    r=$(archivo "$REVERSA" 'repeatable read'); wait
    esperar "la reversa se niega: exige READ COMMITTED" '^ERROR:  REVERSA ASIGNAR: la transacción debe ir en READ COMMITTED \(va en repeatable read\)' "$r"
    esperar "no borró nada: la tabla, la constancia y la puerta siguen" "^1/1/1$" "$(aplicada)/$(abierta)/$( [ "$(aplicada)" = "1" ] && constancias "$(k 6)" || echo 'sin tabla')"
  else wait; fi
  [ "$(aplicada)" = "1" ] || echo "    (la reversa retiró la migración; se reaplica: $(archivo "$MIGRACION"))"
  [ "$(abierta)" = "1" ] || { limpiar; echo "    (reabrir: $(archivo "$REABRIR"))"; }
fi

if quiere E4; then
  echo "E4 · la reversa retira todo mientras una llamada ya había entrado (espera el candado de su solicitud)"
  limpiar
  ocupa candadoE4 4 postgres "select pg_advisory_xact_lock(hashtextextended('asignar-cuenta-pago:' || '$(s 16)', 0));"
  if cruzar candadoE4; then
    ( asignar "$ADMIN" "$(s 16)" "$(k 6)" "$(x 1)" > "$T/llamadaE4.out" 2>&1 ) &
    if cruzar "$(s 16)" advisory; then
      r=$(archivo "$REVERSA"); wait
      esperar "la reversa no espera a esa llamada y lo retira todo (no había asignaciones)" "$RETIRADA" "$r"
      esperar "la llamada que ya había entrado falla limpia: la tabla ya no existe" '^RESULTADO ERR:42P01:relation "crm.contrato_cuenta_pago_asignaciones" does not exist ESPERA_MS' "$(cat "$T/llamadaE4.out")"
      esperar "esa llamada no dejó ningún vínculo" '^sin vínculo$' "$(vinculo "$(k 6)")"
    else wait; fi
  else wait; fi
  esperar "se reaplica la migración para seguir" '^ASIGNAR_CUENTA_PAGO_OK$' "$( [ "$(aplicada)" = "1" ] && echo ASIGNAR_CUENTA_PAGO_OK || archivo "$MIGRACION")"
fi

if quiere E5; then
  echo "E5 · el límite que avisa reversa.sql: la llamada que ya había entrado se completa tras cerrar la puerta"
  limpiar
  esperar "preparación: una asignación ya registrada" '^RESULTADO OK:' "$(asignar "$ADMIN" "$(s 17)" "$(k 6)" "$(x 1)")"
  ocupa candadoE5 4 postgres "select pg_advisory_xact_lock(hashtextextended('asignar-cuenta-pago:' || '$(s 18)', 0));"
  if cruzar candadoE5; then
    ( asignar "$ADMIN" "$(s 18)" "$(k 7)" "$(x 2)" > "$T/llamadaE5.out" 2>&1 ) &
    if cruzar "$(s 18)" advisory; then
      r=$(archivo "$REVERSA"); n1=$(q "select count(*) from crm.contrato_cuenta_pago_asignaciones"); wait
      esperar "la reversa cierra la puerta (había una asignación)" "$CERRADA" "$r"
      esperar "LÍMITE CONOCIDO: la llamada que ya había entrado se completa después (pasa de 1 a 2 constancias con la puerta cerrada)" "^1 → 2 · RESULTADO OK:.*\"ya_aplicada\": false.* · cerrada$" "$n1 → $(q "select count(*) from crm.contrato_cuenta_pago_asignaciones") · $(cat "$T/llamadaE5.out" | sed 's/ ESPERA_MS.*//') · $([ "$(abierta)" = "0" ] && echo cerrada || echo abierta)"
    else wait; fi
  else wait; fi
  limpiar
  esperar "se reabre la puerta para dejar el banco como estaba" '^PUERTA_REABIERTA$' "$( [ "$(abierta)" = "1" ] && echo PUERTA_REABIERTA || archivo "$REABRIR")"
fi

# ── F4 (retirar cuenta) frente a asignar, con dos sesiones ───────────────────────────────────
if quiere H1 || quiere H1b || quiere H2 || quiere H3 || quiere H4; then
  con_doble_de_storage
  if [ "$(f4_listo)" != "1" ]; then
    echo "H · F4 no se puede llamar en $C (falta storage.objects o el EXECUTE de authenticated): casos H NO CORRIDOS"; mal=$((mal + 1))
    SOLO="${SOLO//H1b/}"; SOLO="${SOLO//H1/}"; SOLO="${SOLO//H2/}"; SOLO="${SOLO//H3/}"; SOLO="${SOLO//H4/}"
  fi
fi

for caso in H1 H1b; do
  if quiere "$caso"; then
    [ "$caso" = "H1" ] && modo='read committed' || modo='repeatable read'
    echo "$caso · F4 ($modo) retira la cuenta, sin confirmar, y llega la asignación de esa cuenta"
    limpiar
    en_vuelo "vuelo$caso" "$ADMIN" "$(expresion_retirar "$(s 31)" "$(x 6)")" 3 commit "$modo"
    if cruzar "vuelo$caso"; then
      r=$(asignar "$ADMIN" "$(s 32)" "$(k 1)" "$(x 6)"); wait
      esperar "el retiro se aplicó" "EN_VUELO vuelo$caso \{.*\"ya_aplicada\": false" "$(cat "$T/vuelo$caso.out")"
      esperar "la asignación espera al retiro y recibe «ya no está vigente»" '^RESULTADO ERR:22023:La cuenta elegida ya no está vigente ESPERA_MS' "$r"
      esperar "la asignación ESPERÓ al retiro (≥ 1,5 s)" '^sí$' "$(espero "$r")"
      esperar "estado final coherente: cuenta retirada, contrato sin vínculo" '^f/sin vínculo/1$' "$(cuenta_activa "$(x 6)")/$(vinculo "$(k 1)")/$(retiros "$(x 6)")"
    else wait; fi
  fi
done

if quiere H2; then
  echo "H2 · una asignación sin confirmar y F4 (read committed) quiere retirar esa cuenta"
  limpiar
  en_vuelo vueloH2 "$ADMIN" "$(expresion_asignar "$(s 33)" "$(k 1)" "$(x 6)")" 3 commit
  if cruzar vueloH2; then
    r=$(retirar "$(s 34)" "$(x 6)" 'read committed'); wait
    esperar "F4 espera y se NIEGA: la cuenta ya cobra un contrato abierto" '^RESULTADO ERR:22023:La cuenta todavía cobra el contrato ASIGNAR-01\. Primero cambia su cuenta de pago ESPERA_MS' "$r"
    esperar "F4 ESPERÓ a la asignación (≥ 1,5 s)" '^sí$' "$(espero "$r")"
    esperar "estado final coherente: cuenta vigente, vinculada, sin retiro" "^t/$(x 6)\|$ADMIN/0$" "$(cuenta_activa "$(x 6)")/$(vinculo "$(k 1)")/$(retiros "$(x 6)")"
  else wait; fi
fi

if quiere H3; then
  echo "H3 · una asignación sin confirmar y F4 en REPEATABLE READ quiere retirar esa cuenta (se MIDE: riesgo previo de F4)"
  limpiar
  en_vuelo vueloH3 "$ADMIN" "$(expresion_asignar "$(s 35)" "$(k 1)" "$(x 6)")" 3 commit
  if cruzar vueloH3; then
    r=$(retirar "$(s 36)" "$(x 6)" 'repeatable read'); wait
    esperar "la asignación se confirmó" 'EN_VUELO vueloH3 \{.*"ya_aplicada": false' "$(cat "$T/vueloH3.out")"
    medido "F4 en REPEATABLE READ, tras esperar a la asignación de esa cuenta" "$(sed 's/"solicitud_id": "[0-9a-f-]*"/…/' <<<"$r")"
    medido "estado final (cuenta vigente / vínculo de ASIGNAR-01 / retiros de la cuenta)" "$(cuenta_activa "$(x 6)") / $(vinculo "$(k 1)") / $(retiros "$(x 6)") → $([ "$(cuenta_activa "$(x 6)")" = "f" ] && [ "$(vinculo "$(k 1)")" != "sin vínculo" ] && echo 'F4 RETIRÓ la cuenta que un contrato abierto acaba de recibir' || echo 'F4 no la retiró')"
  else wait; fi
fi

if quiere H4; then
  echo "H4 · F4 en REPEATABLE READ con la fotografía ANTERIOR a una asignación ya confirmada (se MIDE)"
  limpiar
  con_foto fotoH4 3 'repeatable read' "$ADMIN" "$(expresion_retirar "$(s 37)" "$(x 6)")"
  if cruzar fotoH4; then
    r=$(asignar "$ADMIN" "$(s 38)" "$(k 1)" "$(x 6)"); wait
    esperar "la asignación, entera y confirmada, entró mientras F4 esperaba con su fotografía" '^RESULTADO OK:\{.*"ya_aplicada": false.* ESPERA_MS' "$r"
    medido "F4 en REPEATABLE READ con la fotografía de antes de la asignación" "$(resultado_de fotoH4 | sed 's/"solicitud_id": "[0-9a-f-]*"/…/')"
    medido "estado final (cuenta vigente / vínculo de ASIGNAR-01 / retiros de la cuenta)" "$(cuenta_activa "$(x 6)") / $(vinculo "$(k 1)") / $(retiros "$(x 6)") → $([ "$(cuenta_activa "$(x 6)")" = "f" ] && [ "$(vinculo "$(k 1)")" != "sin vínculo" ] && echo 'F4 RETIRÓ la cuenta que un contrato abierto ya tenía asignada' || echo 'F4 no la retiró')"
  else wait; fi
  # Control: la misma secuencia con F4 en READ COMMITTED ve la asignación y se niega.
  limpiar
  con_foto fotoH4rc 3 'read committed' "$ADMIN" "$(expresion_retirar "$(s 39)" "$(x 6)")"
  if cruzar fotoH4rc; then
    r=$(asignar "$ADMIN" "$(s 40)" "$(k 1)" "$(x 6)"); wait
    esperar "control en READ COMMITTED: F4 ve la asignación y se niega" '^RESULTADO ERR:22023:La cuenta todavía cobra el contrato ASIGNAR-01\. Primero cambia su cuenta de pago ESPERA_MS' "$(resultado_de fotoH4rc)"
  else wait; fi
fi

# ── La carga automática (vincular-rezago.sql) frente a «Asignar», con dos sesiones ───────────
if quiere R1 || quiere R2 || quiere R3; then
  if [ "$(otra_aplicada)" != "1" ]; then
    echo "R · NO APLICA: la otra migración (20261001233019) no está aplicada en $C; los casos R1–R3 no se corren"
    SOLO="${SOLO//R1/}"; SOLO="${SOLO//R2/}"; SOLO="${SOLO//R3/}"
  fi
fi

if quiere R1; then
  echo "R1 · la carga (vincular-rezago.sql) en vuelo, con su candado EXCLUSIVE de cuentas tomado, y llega «Asignar» sobre su candidato"
  limpiar
  esperar "preparación: ASIGNAR-05 es el ÚNICO candidato de la carga (una cuenta activa en su moneda, sin vínculo)" '^una_cuenta/1/1/sin vínculo$' "$(candidato_de_la_carga)/$(vinculo "$(k 5)")"
  I0=$(interbloqueos)
  # La carga REAL, con una espera de 3 s justo después de tomar su candado (copia temporal: el archivo no se toca).
  python3 - "$VINCULAR" "$T/cargaR1.sql" <<'PY'
import io, sys
t = io.open(sys.argv[1], encoding='utf-8').read()
a = "\nlock table crm.cuentas_bancarias in exclusive mode;\n"
assert t.count(a) == 1, 'vincular-rezago.sql ya no toma su candado como se esperaba'
io.open(sys.argv[2], 'w', encoding='utf-8').write("/* cargaR1 */ " + t.replace(a, a + "select pg_sleep(3);\n"))
PY
  psql_as postgres -c "$(cat "$T/cargaR1.sql")" > "$T/cargaR1.out" 2> "$T/cargaR1.err" </dev/null &
  if cruzar cargaR1; then
    esperar "testigo: la carga duerme con el candado EXCLUSIVE de crm.cuentas_bancarias ya concedido" '^1$' "$(q "select count(*) from pg_locks l where l.relation = 'crm.cuentas_bancarias'::regclass and l.mode = 'ExclusiveLock' and l.granted")"
    ( asignar "$ADMIN" "$(s 41)" "$(k 5)" "$(x 3)" > "$T/asignarR1.out" 2>&1 ) &
    en_espera=no
    for i in $(seq 1 60); do
      [ "$(q "select count(*) from pg_locks l join pg_stat_activity a on a.pid = l.pid where l.relation = 'crm.cuentas_bancarias'::regclass and l.mode = 'RowShareLock' and not l.granted and a.query like '%$(s 41)%' and a.pid <> pg_backend_pid()")" = "1" ] && { en_espera=sí; break; }
      sleep 0.1
    done
    wait
    r=$(cat "$T/asignarR1.out")
    esperar "«Asignar» quedó ESPERANDO el candado de la tabla de cuentas (RowShareLock sin conceder) mientras la carga seguía" '^sí$' "$en_espera"
    esperar "al soltar, la carga vinculó su candidato" '"contratos": \["ASIGNAR-05"\], "vinculados": 1\}$' "$(resultado_de_canales "$T/cargaR1")"
    esperar "«Asignar» responde 22023 «ya tiene cuenta de pago; para cambiarla usa «Cambiar cuenta de pago»»" "^RESULTADO ERR:22023:El contrato ASIGNAR-05 $YA_TIENE ESPERA_MS" "$r"
    esperar "«Asignar» ESPERÓ a la carga (≥ 1,5 s)" '^sí$' "$(espero "$r")"
    esperar "queda UN vínculo: el de la carga (creado_por NULL), con su rastro de carga" "^1/$(x 3)\|\(null\)/1:carga:rezago-vinculos:[0-9]{8}$" "$(q "select count(*) from crm.contrato_cuentas_pago where contrato_id = '$(k 5)'")/$(vinculo "$(k 5)")/$(rastro_de_carga "$(k 5)")"
    esperar "CERO constancias de asignación (ni del contrato ni de esa solicitud)" '^0/0$' "$(constancias "$(k 5)")/$(q "select count(*) from crm.contrato_cuenta_pago_asignaciones where solicitud_id = '$(s 41)'")"
    esperar "sin interbloqueo ni lock timeout (menciones en las dos sesiones / interbloqueos nuevos del servidor)" '^0/0/0$' "$(sin_abrazos cargaR1 asignarR1 "$I0")"
  else wait; fi
fi

if quiere R2; then
  echo "R2 · «Asignar» en vuelo (sin confirmar) sobre el candidato y se lanza la carga (vincular-rezago.sql, tal cual)"
  limpiar
  esperar "preparación: ASIGNAR-05 es el ÚNICO candidato de la carga (una cuenta activa en su moneda, sin vínculo)" '^una_cuenta/1/1/sin vínculo$' "$(candidato_de_la_carga)/$(vinculo "$(k 5)")"
  I0=$(interbloqueos)
  en_vuelo vueloR2 "$ADMIN" "$(expresion_asignar "$(s 42)" "$(k 5)" "$(x 3)")" 3 commit
  if cruzar vueloR2; then
    t0=$(ahora_ms)
    ( psql_as postgres -c "$(cat "$VINCULAR")" > "$T/cargaR2.out" 2> "$T/cargaR2.err" </dev/null; ahora_ms > "$T/cargaR2.fin" ) &
    en_espera=no
    for i in $(seq 1 60); do
      [ "$(q "select count(*) from pg_locks l join pg_stat_activity a on a.pid = l.pid where l.relation = 'crm.cuentas_bancarias'::regclass and l.mode = 'ExclusiveLock' and not l.granted and a.query like '%VINCULAR EL REZAGO%' and a.pid <> pg_backend_pid()")" = "1" ] && { en_espera=sí; break; }
      sleep 0.1
    done
    sigue_abierta=$(q "select count(*) from pg_stat_activity where query like '%vueloR2%' and wait_event = 'PgSleep' and pid <> pg_backend_pid()")
    wait
    esperar "la carga quedó ESPERANDO en su «lock table» (ExclusiveLock sin conceder) con la asignación aún sin confirmar" '^sí/1$' "$en_espera/$sigue_abierta"
    esperar "la asignación se confirmó" 'EN_VUELO vueloR2 \{.*"ya_aplicada": false.*"numero_contrato": "ASIGNAR-05"' "$(cat "$T/vueloR2.out")"
    esperar "al confirmar, la carga sigue y ya NO ve candidato: 0 vinculados" '"contratos": \[\], "vinculados": 0\}$' "$(resultado_de_canales "$T/cargaR2")"
    esperar "la carga ESPERÓ a la asignación (≥ 1,5 s)" '^sí$' "$([ $(( $(cat "$T/cargaR2.fin") - t0 )) -ge 1500 ] && echo sí || echo "no ($(( $(cat "$T/cargaR2.fin") - t0 )) ms)")"
    esperar "queda UN vínculo (creado_por = la administradora), UNA constancia y ningún rastro de carga" "^1/$(x 3)\|$ADMIN/1/0:$" "$(q "select count(*) from crm.contrato_cuentas_pago where contrato_id = '$(k 5)'")/$(vinculo "$(k 5)")/$(constancias "$(k 5)")/$(rastro_de_carga "$(k 5)")"
    esperar "sin interbloqueo ni lock timeout (menciones en las dos sesiones / interbloqueos nuevos del servidor)" '^0/0/0$' "$(sin_abrazos cargaR2 vueloR2 "$I0")"
  else wait; fi
fi

if quiere R3; then
  echo "R3 · lo mismo, con la asignación tardando más (7 s) que el lock_timeout de la carga (5 s)"
  limpiar
  esperar "preparación: ASIGNAR-05 es el ÚNICO candidato de la carga (una cuenta activa en su moneda, sin vínculo)" '^una_cuenta/1/1/sin vínculo$' "$(candidato_de_la_carga)/$(vinculo "$(k 5)")"
  I0=$(interbloqueos)
  en_vuelo vueloR3 "$ADMIN" "$(expresion_asignar "$(s 43)" "$(k 5)" "$(x 3)")" 7 commit
  if cruzar vueloR3; then
    r=$(archivo "$VINCULAR"); wait
    esperar "la carga cae por SU lock_timeout (el esperado), sin vincular nada" '^ERROR:  canceling statement due to lock timeout' "$r"
    esperar "la asignación se confirmó: UN vínculo (de la administradora), UNA constancia, ningún rastro de carga" "^1/$(x 3)\|$ADMIN/1/0:$" "$(q "select count(*) from crm.contrato_cuentas_pago where contrato_id = '$(k 5)'")/$(vinculo "$(k 5)")/$(constancias "$(k 5)")/$(rastro_de_carga "$(k 5)")"
    esperar "la carga, relanzada después, no tiene nada que vincular" '"contratos": \[\], "vinculados": 0\}$' "$(archivo "$VINCULAR")"
    esperar "sin interbloqueos en el servidor" '^0$' "$(( $(interbloqueos) - I0 ))"
  else wait; fi
fi

# ── Cierre: el mundo como estaba ─────────────────────────────────────────────────────────────
limpiar
sin_doble_de_storage
if [ "$(aplicada)" = "1" ]; then
  esperar "al terminar, el mundo, la puerta y sus permisos quedaron como al empezar" '^igual$' "$([ "$(huella)" = "$H0" ] && echo igual || printf 'distinto\n    antes:   %s\n    después: %s' "$H0" "$(huella)")"
else
  echo "  ✗ al terminar la migración NO está aplicada"; mal=$((mal + 1))
fi
echo "CONCURRENCIA asignar_cuenta_pago: $ok OK, $mal FALLAS"
[ "$mal" -eq 0 ]
