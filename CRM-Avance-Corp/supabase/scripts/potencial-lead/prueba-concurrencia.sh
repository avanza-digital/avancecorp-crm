#!/usr/bin/env bash
# Prueba de CONCURRENCIA de 20260930213647_crm_potencial_lead (Codex r1 F1 y F2).
# SOLO en el banco Docker propio: crea un mundo sintético CONFIRMADO (ids fijos), corre dos
# sesiones de verdad que se cruzan y lo limpia al final. Nunca contra producción.
#
#   BANCO_CONTENEDOR=avancecorp-potencial-20260930 bash prueba-concurrencia.sh
#
# Casos:
#   A · reasignación en vuelo: T1 reasigna L1 de V1 a V2 y tarda; V1 intenta marcar en medio.
#       Esperado: V1 espera a T1 y recibe P0002 (antes del arreglo escribía con permiso caducado).
#   B · cierre en vuelo: T1 descarta L1 y tarda; V1 marca en medio → 22023.
#   C · reversa contra una marca sin confirmar: V1 marca y tarda en confirmar; otra sesión apaga la
#       bandera; la reversa corre en medio. Esperado: la reversa espera y se NIEGA (hay marcas).
#   D · (Codex r2 R2-3) reversa contra una marca A MEDIO CAMINO: una sesión con el perfil de
#       candados de la marca tras potencial_bloquear_lead (FOR SHARE del lead) que después escribe
#       en el historial. Esperado: sin interbloqueo; la reversa espera, ve el evento y se niega.
#   E · (Codex r2 R2-1) lead todavía sin confirmar: T1 inserta L9 y tarda; V1 intenta marcarlo.
#       Esperado: P0002 (no hay fila que bloquear) y nada escrito.
# A y B miden además que V1 ESPERÓ (≥ 1,5 s): prueba de que las dos sesiones se cruzaron.
set -euo pipefail
C="${BANCO_CONTENEDOR:-avancecorp-potencial-20260930}"
DIR="$(cd "$(dirname "$0")" && pwd)"
psql_as() { # $1 = usuario, resto = argumentos de psql
  local u="$1"; shift
  docker exec -i -e PGPASSWORD=postgres "$C" psql -U "$u" -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt "$@"
}
V1=00000000-0000-4000-8000-00000000c0a1; V2=00000000-0000-4000-8000-00000000c0a2
S1=00000000-0000-4000-8000-00000000c0b1; S2=00000000-0000-4000-8000-00000000c0b2
L1=00000000-0000-4000-8000-00000000c0c1
L9=00000000-0000-4000-8000-00000000c0c9
ok=0; mal=0
esperar() { # $1 caso, $2 esperado (regex), $3 obtenido
  if [[ "$3" =~ $2 ]]; then echo "  ✓ $1"; ok=$((ok+1)); else echo "  ✗ $1 — esperado /$2/, obtenido: $3"; mal=$((mal+1)); fi
}

mundo() {
  psql_as supabase_admin <<SQL
set session_replication_role = replica;
insert into auth.users (id, email) values ('$V1','cv1@potencial.banco'),('$V2','cv2@potencial.banco'),('$S1','cs1@potencial.banco'),('$S2','cs2@potencial.banco') on conflict do nothing;
insert into public.perfiles (id, nombre_completo, rol, activo) values ('$V1','CONC V1','analista',true),('$V2','CONC V2','analista',true),('$S1','CONC S1','analista',true),('$S2','CONC S2','analista',true) on conflict (id) do nothing;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values ('$S1','supervisor',null,true),('$S2','supervisor',null,true),('$V1','vendedor','$S1',true),('$V2','vendedor','$S2',true) on conflict (perfil_id) do nothing;
delete from crm.lead_potencial where lead_id = '$L1';
delete from crm.lead_potencial_eventos where lead_id = '$L1';
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, activo)
  values ('$L1','CONC L1','+51987659001','landing',50000,'PEN','contactado','$V1',true)
  on conflict (id) do update set vendedor_id = '$V1', asignado_supervisor_id = null, etapa = 'contactado', motivo_descarte = null, activo = true;
set session_replication_role = origin;
update crm.multiempresa_flags set activo = true where nombre = 'potencial_lead';
SQL
}
limpiar() {
  psql_as supabase_admin <<SQL
set session_replication_role = replica;
delete from crm.lead_potencial_eventos where lead_id = '$L1';
delete from crm.lead_potencial where lead_id = '$L1';
delete from crm.leads where id in ('$L1', '$L9');
delete from crm.equipo where perfil_id in ('$V1','$V2','$S1','$S2');
delete from public.perfiles where id in ('$V1','$V2','$S1','$S2');
delete from auth.users where id in ('$V1','$V2','$S1','$S2');
set session_replication_role = origin;
update crm.multiempresa_flags set activo = false where nombre = 'potencial_lead';
SQL
}
marcar_como() { # $1 actor, $2 nivel → imprime ok:<nivel> o el SQLSTATE
  psql_as supabase_admin <<SQL 2>&1 | tail -1
do \$m\$ declare v jsonb; begin
  perform set_config('request.jwt.claim.sub', '$1', true);
  perform set_config('request.jwt.claims', json_build_object('sub', '$1', 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    v := crm.marcar_potencial_lead_fn('$L1', '$2');
    raise notice 'RESULTADO ok:%', v ->> 'nivel';
  exception when others then
    raise notice 'RESULTADO %', sqlstate;
  end;
end \$m\$;
SQL
}

echo "A · reasignación en vuelo"
mundo
( psql_as supabase_admin -c "begin; set local session_replication_role = replica; update crm.leads set vendedor_id = '$V2' where id = '$L1'; select pg_sleep(3); commit;" >/dev/null ) &
sleep 1
t0=$(date +%s%N); r=$(marcar_como "$V1" estrella); t1=$(date +%s%N); wait
esperar "V1 marca mientras reasignan L1 a V2 → P0002" 'RESULTADO P0002' "$r"
esperar "V1 esperó a la reasignación (≥ 1,5 s)" '^1$' "$(( (t1 - t0) >= 1500000000 ? 1 : 0 ))"
esperar "no quedó marca escrita con el permiso caducado" '^0$' "$(psql_as supabase_admin -c "select count(*) from crm.lead_potencial where lead_id = '$L1'")"

echo "B · cierre en vuelo"
mundo
( psql_as supabase_admin -c "begin; set local session_replication_role = replica; update crm.leads set etapa = 'descartado', motivo_descarte = 'sin_interes' where id = '$L1'; select pg_sleep(3); commit;" >/dev/null ) &
sleep 1
t0=$(date +%s%N); r=$(marcar_como "$V1" estrella); t1=$(date +%s%N); wait
esperar "V1 marca mientras descartan L1 → 22023" 'RESULTADO 22023' "$r"
esperar "V1 esperó al descarte (≥ 1,5 s)" '^1$' "$(( (t1 - t0) >= 1500000000 ? 1 : 0 ))"

echo "C · reversa contra una marca sin confirmar"
mundo
( psql_as supabase_admin -c "begin; select set_config('request.jwt.claim.sub', '$V1', true), set_config('request.jwt.claims', json_build_object('sub', '$V1', 'role', 'authenticated')::text, true); set local role authenticated; select crm.marcar_potencial_lead_fn('$L1', 'estrella'); select pg_sleep(4); commit;" >/dev/null ) &
sleep 1
psql_as supabase_admin -c "update crm.multiempresa_flags set activo = false where nombre = 'potencial_lead';" >/dev/null
r=$(docker exec -i -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "$(cat "$DIR/reversa.sql")" 2>&1 | grep -m1 -o 'ERROR:.*\|NOTICE:.*REVERSA.*' || true); wait || true
esperar "la reversa espera a la marca y se niega" 'REVERSA potencial_lead: hay marcas' "$r"
esperar "la marca confirmada sigue en su tabla" '^1$' "$(psql_as supabase_admin -c "select count(*) from crm.lead_potencial where lead_id = '$L1'" 2>&1 | tail -1)"

echo "D · reversa contra una marca a medio camino (orden de candados)"
mundo
psql_as supabase_admin -c "update crm.multiempresa_flags set activo = false where nombre = 'potencial_lead';" >/dev/null
d_out=$(mktemp)
( psql_as postgres -c "begin; select 1 from crm.leads where id = '$L1' for share; select pg_sleep(3); insert into crm.lead_potencial_eventos (lead_id, nivel_nuevo, motivo, por) values ('$L1', 'estrella', 'manual', '$V1'); commit;" > "$d_out" 2>&1 || true ) &
sleep 1
r=$(docker exec -i -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "$(cat "$DIR/reversa.sql")" 2>&1 | grep -m1 -o 'ERROR:.*\|NOTICE:.*REVERSA.*' || true); wait || true
esperar "la reversa no interbloquea y se niega" 'REVERSA potencial_lead: hay marcas' "$r"
esperar "la marca a medio camino confirmó (sin deadlock)" '^$' "$(grep -o 'deadlock\|ERROR.*' "$d_out" || true)"
rm -f "$d_out"

echo "E · lead todavía sin confirmar"
mundo
( psql_as supabase_admin -c "begin; set local session_replication_role = replica; insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, activo) values ('$L9','CONC L9','+51987659009','landing',50000,'PEN','contactado','$V1',true); select pg_sleep(3); commit;" >/dev/null ) &
sleep 1
r=$(psql_as supabase_admin <<SQL 2>&1 | tail -1
do \$m\$ declare v jsonb; begin
  perform set_config('request.jwt.claim.sub', '$V1', true);
  perform set_config('request.jwt.claims', json_build_object('sub', '$V1', 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    v := crm.marcar_potencial_lead_fn('$L9', 'estrella');
    raise notice 'RESULTADO ok:%', v ->> 'nivel';
  exception when others then
    raise notice 'RESULTADO %', sqlstate;
  end;
end \$m\$;
SQL
); wait
esperar "V1 marca un lead aún sin confirmar → P0002" 'RESULTADO P0002' "$r"
esperar "no quedó marca sobre el lead nuevo" '^0$' "$(psql_as supabase_admin -c "select count(*) from crm.lead_potencial where lead_id = '$L9'")"

limpiar
echo "CONCURRENCIA potencial_lead: $ok OK, $mal FALLAS"
[ "$mal" -eq 0 ]
