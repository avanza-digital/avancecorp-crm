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
#   D   retiran la cuenta en vuelo (las sentencias del retiro de F4) → la asignación espera y recibe «ya no está vigente»
#   F   cierran el contrato en vuelo → la asignación espera y recibe «está cerrado»
#   E1  la reversa con una asignación sin confirmar → espera, la ve y solo CIERRA la puerta (nada borrado);
#       después reabrir-puerta.sql la reabre
#   E2  la reversa con una asignación que tarda más que su lock_timeout → cae sin cambiar nada
#   E3  la reversa en REPEATABLE READ con una asignación sin confirmar → se niega y no borra nada
#   E4  la reversa retira todo mientras una llamada ya había entrado (esperando el candado de su solicitud)
#       → esa llamada falla limpia y no escribe nada
#   E5  el límite que avisa reversa.sql: con asignaciones registradas, la llamada que ya había entrado
#       se completa DESPUÉS de cerrada la puerta
set -uo pipefail
C="${BANCO_CONTENEDOR:-avancecorp-cuentas-asignar-20261001}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRACION="${MIGRACION_SQL:-$DIR/../../migrations/20261002005004_crm_asignar_cuenta_pago.sql}"
REVERSA="${REVERSA_SQL:-$DIR/reversa.sql}"
REABRIR="${REABRIR_SQL:-$DIR/reabrir-puerta.sql}"
SOLO="${SOLO:-A A2 A3 A4 B1 B2 C1 C2 D F E1 E2 E3 E4 E5}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

PUERTA='crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'
NUCLEO='private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'
ADMIN='c9e00000-0000-4000-8000-000000000001'
SUPER='a5190000-0000-4000-8000-000000000031'
OPER='c9e00000-0000-4000-8000-000000000002'
MOTIVO='Operaciones confirmó con el cliente en cuál cobra'
k() { printf 'a519d000-0000-4000-8000-0000000000%02d' "$1"; }      # contrato ASIGNAR-NN
x() { printf 'a519c000-0000-4000-8000-0000000000%02d' "$1"; }      # cuenta de la siembra extra
s() { printf 'a519a000-0000-4000-8000-0000000090%02d' "$1"; }      # solicitud
cuota() { printf 'a519e000-0000-4000-8000-00000000%02d%02d' "$1" "$2"; }
YA_TIENE='ya tiene cuenta de pago; para cambiarla usa «Cambiar cuenta de pago»'

psql_as() { local u="$1"; shift; docker exec -i -e PGPASSWORD=postgres "$C" psql -U "$u" -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt "$@"; }
q() { psql_as postgres -c "$1" 2>&1; }
# Un archivo en UN mensaje, como postgres: su primer ERROR, o su última línea (el veredicto viaja como fila).
# Con $2 = un nivel de aislamiento, la conexión nace con ese nivel por defecto (un SET delante en el
# mismo mensaje no sirve: el «begin» del archivo no abre una transacción nueva, hereda la del mensaje).
archivo() {
  local o
  if [ -n "${2:-}" ]; then
    o=$(docker exec -i -e PGPASSWORD=postgres -e "PGOPTIONS=-c default_transaction_isolation=${2// /\\ }" "$C" \
          psql -U postgres -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "$(cat "$1")" 2>&1)
  else
    o=$(psql_as postgres -c "$(cat "$1")" 2>&1)
  fi
  if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-220; else tail -1 <<<"$o"; fi
}

ok=0; mal=0
esperar() { # $1 caso · $2 esperado (regex) · $3 obtenido
  if [[ "$3" =~ $2 ]]; then echo "  ✓ $1"; ok=$((ok + 1)); else echo "  ✗ $1 — esperado /$2/, obtenido: $3"; mal=$((mal + 1)); fi
}
quiere() { case " $SOLO " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# ── Sesiones ─────────────────────────────────────────────────────────────────────────────────
# Así entra PostgREST: authenticator (con sus timeouts de 8 s), claims en las dos formas y SET ROLE.
api() { # $1 = uid
  echo "set local lock_timeout = '8s'; set local statement_timeout = '8s';
        select set_config('request.jwt.claim.sub', '$1', true), set_config('request.jwt.claim.role', 'authenticated', true),
               set_config('request.jwt.claims', json_build_object('sub', '$1', 'role', 'authenticated')::text, true);
        set local session authorization authenticator; set local role authenticated;"
}
# Una asignación «en vuelo»: se hace, espera $6 segundos y termina con $7 (commit | rollback). Va en segundo plano.
en_vuelo() { # $1 marca · $2 uid · $3 solicitud · $4 contrato · $5 cuenta · $6 segundos · $7 commit|rollback
  psql_as supabase_admin -c "begin; $(api "$2")
     select 'EN_VUELO $1 ' || crm.asignar_cuenta_pago_contrato('$3', '$4', '$5', '$MOTIVO')::text;
     select pg_sleep($6) /* $1 */; ${7:-commit};" > "$T/$1.out" 2>&1 &
}
# Otra sesión que mantiene algo tomado $2 segundos (como el usuario $3, por defecto postgres). En segundo plano.
ocupa() { # $1 marca · $2 segundos · $3 usuario · $4 sentencias
  psql_as "${3:-postgres}" -c "begin; $4 select pg_sleep($2) /* $1 */; commit;" > "$T/$1.out" 2>&1 &
}
# No sigue hasta que el banco dice que la sesión de la marca YA está esperando (dormida o en un candado).
cruzar() { # $1 marca · $2 evento de espera (PgSleep | advisory | relation | transactionid | tuple …)
  local i
  for i in $(seq 1 100); do
    [ "$(q "select count(*) from pg_stat_activity where query like '%$1%' and wait_event = '${2:-PgSleep}' and pid <> pg_backend_pid()")" = "1" ] && return 0
    sleep 0.1
  done
  echo "  ✗ la sesión $1 no llegó a esperar (${2:-PgSleep}): $(cat "$T/$1.out" 2>/dev/null | tr '\n' ' ' | cut -c1-200)"; mal=$((mal + 1)); return 1
}
# Una asignación observada, como llamada de la API: «RESULTADO OK:<json>|ERR:<sqlstate>:<mensaje> ESPERA_MS <n>».
asignar() { # $1 uid · $2 solicitud · $3 contrato · $4 cuenta · $5 lock_timeout (opcional)
  psql_as supabase_admin 2>&1 <<SQL | grep -o 'RESULTADO .*' | tail -1
do \$m\$
declare v jsonb; r text; t0 constant timestamptz := clock_timestamp();
begin
  perform set_config('lock_timeout', '${5:-8s}', true), set_config('statement_timeout', '8s', true),
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
  raise notice 'RESULTADO % ESPERA_MS %', r, (extract(epoch from clock_timestamp() - t0) * 1000)::integer;
end \$m\$;
SQL
}
# Un pago observado, como operaciones por la RPC.
pagar() { # $1 cuota
  psql_as supabase_admin 2>&1 <<SQL | grep -o 'RESULTADO .*' | tail -1
do \$m\$
declare v uuid; r text; t0 constant timestamptz := clock_timestamp();
begin
  perform set_config('lock_timeout', '8s', true), set_config('statement_timeout', '8s', true),
          set_config('request.jwt.claim.sub', '$OPER', true), set_config('request.jwt.claim.role', 'authenticated', true),
          set_config('request.jwt.claims', json_build_object('sub', '$OPER', 'role', 'authenticated')::text, true);
  execute 'set local session authorization authenticator';
  execute 'set local role authenticated';
  begin
    v := crm.registrar_pago_con_cuenta('$1', (now() at time zone 'America/Lima')::date, 100, null);
    r := 'OK:' || coalesce(v::text, 'no se pagó');
  exception when others then
    r := 'ERR:' || sqlstate || ':' || sqlerrm;
  end;
  raise notice 'RESULTADO % ESPERA_MS %', r, (extract(epoch from clock_timestamp() - t0) * 1000)::integer;
end \$m\$;
SQL
}
espera_ms() { sed -n 's/.* ESPERA_MS \([0-9]*\)$/\1/p' <<<"$1"; }
espero() { [ "$(espera_ms "$1")" -ge "${2:-1500}" ] 2>/dev/null && echo sí || echo "no ($(espera_ms "$1") ms)"; }
vinculo() { q "select coalesce((select cuenta_bancaria_id || '|' || coalesce(creado_por::text, '(null)') from crm.contrato_cuentas_pago where contrato_id = '$1'), 'sin vínculo')"; }
constancias() { q "select count(*) from crm.contrato_cuenta_pago_asignaciones where contrato_id = '$1'"; }
aplicada() { q "select (to_regclass('crm.contrato_cuenta_pago_asignaciones') is not null and to_regprocedure('$PUERTA') is not null and to_regprocedure('$NUCLEO') is not null)::int"; }
# Por catálogo, nunca llamando: sin EXECUTE bajo SET ROLE este Postgres se cae.
abierta() { q "select (has_function_privilege('authenticated', '$PUERTA', 'EXECUTE') and has_function_privilege('authenticated', '$NUCLEO', 'EXECUTE'))::int"; }

# SOLO BANCO. Deja el mundo de la siembra extra como se sembró: sin constancias, sin vínculos, sin
# sellos, con las cuotas pendientes, la cuenta 06 vigente y los contratos en su estado. Va como
# supabase_admin y en modo réplica porque la constancia y los sellos no se borran (sus disparadores
# lo impiden, con razón). La bitácora (public.audit_log) es de solo añadir: no se toca.
limpiar() {
  psql_as supabase_admin -c "
    set session_replication_role = replica;
    do \$l\$ begin if to_regclass('crm.contrato_cuenta_pago_asignaciones') is not null then delete from crm.contrato_cuenta_pago_asignaciones; end if; end \$l\$;
    delete from crm.cuotas_cuenta_pagada where contrato_id::text like 'a519d000-%';
    delete from crm.contrato_cuentas_pago where contrato_id::text like 'a519d000-%';
    update public.cronograma_pagos set estado = 'pendiente', fecha_pago_real = null, monto_pagado = null, registrado_por = null
     where id::text like 'a519e000-%' and (estado <> 'pendiente' or fecha_pago_real is not null or monto_pagado is not null or registrado_por is not null);
    update crm.cuentas_bancarias set activa = true, desactivada_por = null, desactivada_en = null
     where id::text like 'a519c000-%' and id <> '$(x 4)' and not activa;
    update public.contratos set estado = 'activo' where id = '$(k 5)' and estado <> 'activo';
    set session_replication_role = origin;" >/dev/null 2>&1
}
# La foto del mundo que la prueba puede tocar (todo menos la bitácora).
huella() {
  q "set timezone = 'UTC';
     select 'vinculos=' || (select count(*) || ':' || md5(coalesce(string_agg(md5(to_jsonb(v)::text), ',' order by v.id), '')) from crm.contrato_cuentas_pago v)
         || ' cuentas=' || (select count(*) || ':' || md5(coalesce(string_agg(md5(to_jsonb(v)::text), ',' order by v.id), '')) from crm.cuentas_bancarias v)
         || ' contratos=' || (select count(*) || ':' || md5(coalesce(string_agg(md5(to_jsonb(v)::text), ',' order by v.id), '')) from public.contratos v)
         || ' cuotas=' || (select count(*) || ':' || md5(coalesce(string_agg(md5(to_jsonb(v)::text), ',' order by v.id), '')) from public.cronograma_pagos v)
         || ' sellos=' || (select count(*) from crm.cuotas_cuenta_pagada)
         || ' constancias=' || (select count(*) from crm.contrato_cuenta_pago_asignaciones)
         || ' puerta=' || (select md5(p.prosrc) || coalesce(p.proacl::text, '') from pg_proc p where p.oid = '$PUERTA'::regprocedure)
         || ' nucleo=' || (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = '$NUCLEO'::regprocedure);" | grep -v '^SET$'
}

# ── Punto de partida ─────────────────────────────────────────────────────────────────────────
if [ "$(aplicada)" != "1" ]; then echo "La migración 20261002005004 no está aplicada en $C: aplícala antes (ciclo.sh lo hace)." >&2; exit 2; fi
if [ "$(abierta)" != "1" ]; then echo "La puerta está CERRADA en $C (reversa con asignaciones): limpia y reabre antes (ciclo.sh lo hace)." >&2; exit 2; fi
if [ "$(q "select count(*) from public.contratos where id::text like 'a519d000-%'")" != "13" ]; then echo "Falta la siembra extra en $C (siembra-extra.sql)." >&2; exit 2; fi
limpiar
H0="$(huella)"

if quiere A; then
  echo "A · dos asignaciones a la vez al mismo contrato, con cuentas distintas"
  en_vuelo vueloA "$ADMIN" "$(s 1)" "$(k 6)" "$(x 1)" 3 commit
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
  en_vuelo vueloA2 "$ADMIN" "$(s 3)" "$(k 7)" "$(x 1)" 3 rollback
  if cruzar vueloA2; then
    r=$(asignar "$SUPER" "$(s 4)" "$(k 7)" "$(x 2)"); wait
    esperar "la segunda asigna" '^RESULTADO OK:\{.*"ya_aplicada": false.* ESPERA_MS' "$r"
    esperar "la segunda ESPERÓ a que la primera terminara (≥ 1,5 s)" '^sí$' "$(espero "$r")"
    esperar "quedó el vínculo de la segunda (la primera no dejó nada)" "^$(x 2)\|$SUPER/1$" "$(vinculo "$(k 7)")/$(constancias "$(k 7)")"
  else wait; fi
fi

if quiere A3; then
  echo "A3 · la misma solicitud dos veces a la vez (doble clic)"
  en_vuelo vueloA3 "$ADMIN" "$(s 5)" "$(k 8)" "$(x 1)" 3 commit
  if cruzar vueloA3; then
    r=$(asignar "$ADMIN" "$(s 5)" "$(k 8)" "$(x 1)"); wait
    esperar "la segunda recibe ya_aplicada (no «ya tiene cuenta de pago»)" '^RESULTADO OK:\{.*"ya_aplicada": true.* ESPERA_MS' "$r"
    esperar "la segunda ESPERÓ a la primera (≥ 1,5 s)" '^sí$' "$(espero "$r")"
    esperar "una sola constancia y un solo vínculo" "^1/$(x 1)\|$ADMIN$" "$(constancias "$(k 8)")/$(vinculo "$(k 8)")"
  else wait; fi
fi

if quiere A4; then
  echo "A4 · la misma solicitud a la vez, con otra cuenta"
  en_vuelo vueloA4 "$ADMIN" "$(s 6)" "$(k 9)" "$(x 1)" 3 commit
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
  en_vuelo vueloB2 "$ADMIN" "$(s 8)" "$(k 11)" "$(x 2)" 3 commit
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

# ── La reversa, con asignaciones cruzándose ──────────────────────────────────────────────────
if quiere E1; then
  echo "E1 · la reversa con una asignación sin confirmar"
  limpiar
  en_vuelo vueloE1 "$ADMIN" "$(s 13)" "$(k 6)" "$(x 1)" 3 commit
  if cruzar vueloE1; then
    r=$(archivo "$REVERSA"); wait
    esperar "la reversa espera, ve la asignación y solo cierra la puerta" '^PUERTA_CERRADA: 1 asignaciones conservadas; no se borró nada$' "$r"
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
  en_vuelo vueloE2 "$ADMIN" "$(s 14)" "$(k 6)" "$(x 1)" 7 commit
  if cruzar vueloE2; then
    r=$(archivo "$REVERSA"); wait
    esperar "la reversa cae por lock_timeout" '^ERROR:  canceling statement due to lock timeout' "$r"
    esperar "no cambió nada: la puerta sigue abierta y la asignación se confirmó" "^1/1/1$" "$(aplicada)/$(abierta)/$(constancias "$(k 6)")"
  else wait; fi
fi

if quiere E3; then
  echo "E3 · la reversa en REPEATABLE READ con una asignación sin confirmar"
  limpiar
  en_vuelo vueloE3 "$ADMIN" "$(s 15)" "$(k 6)" "$(x 1)" 3 commit
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
      esperar "la reversa no espera a esa llamada y lo retira todo (no había asignaciones)" '^RETIRADA: sin asignaciones registradas' "$r"
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
      esperar "la reversa cierra la puerta contando UNA asignación" '^PUERTA_CERRADA: 1 asignaciones conservadas; no se borró nada$' "$r"
      esperar "LÍMITE CONOCIDO: la llamada que ya había entrado se completa después (pasa de 1 a 2 constancias con la puerta cerrada)" "^1 → 2 · RESULTADO OK:.*\"ya_aplicada\": false.* · cerrada$" "$n1 → $(q "select count(*) from crm.contrato_cuenta_pago_asignaciones") · $(cat "$T/llamadaE5.out" | sed 's/ ESPERA_MS.*//') · $([ "$(abierta)" = "0" ] && echo cerrada || echo abierta)"
    else wait; fi
  else wait; fi
  limpiar
  esperar "se reabre la puerta para dejar el banco como estaba" '^PUERTA_REABIERTA$' "$( [ "$(abierta)" = "1" ] && echo PUERTA_REABIERTA || archivo "$REABRIR")"
fi

# ── Cierre: el mundo como estaba ─────────────────────────────────────────────────────────────
limpiar
if [ "$(aplicada)" = "1" ]; then
  esperar "al terminar, el mundo, la puerta y sus permisos quedaron como al empezar" '^igual$' "$([ "$(huella)" = "$H0" ] && echo igual || printf 'distinto\n    antes:   %s\n    después: %s' "$H0" "$(huella)")"
else
  echo "  ✗ al terminar la migración NO está aplicada"; mal=$((mal + 1))
fi
echo "CONCURRENCIA asignar_cuenta_pago: $ok OK, $mal FALLAS"
[ "$mal" -eq 0 ]
