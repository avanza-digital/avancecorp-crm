#!/usr/bin/env bash
# Prueba de CONCURRENCIA de 20260930235917_crm_potencial_lead_caducidad (fase 2).
# SOLO en el banco Docker propio. La tarea NUNCA espera (Codex f2 r1 F1, auditor P3-1/P3-2):
#   A · una re-marca del analista en vuelo (tiene el candado consultivo del lead): la tarea salta ese
#       lead al instante, no lo baja, y el lead queda para la próxima corrida.
#   B · un descarte en vuelo (fila del lead bloqueada): la tarea salta el lead al instante (SKIP
#       LOCKED) y, confirmado el descarte, la marca queda intacta.
#   C · la próxima corrida, ya sin nada en vuelo, baja lo que correspondía.
#   BANCO_CONTENEDOR=avancecorp-potencial-20260930 bash prueba-concurrencia-caducidad.sh
set -euo pipefail
C="${BANCO_CONTENEDOR:-avancecorp-potencial-20260930}"
psql_as() { local u="$1"; shift; docker exec -i -e PGPASSWORD=postgres "$C" psql -U "$u" -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt "$@"; }
V1=00000000-0000-4000-8000-00000000d0a1; S1=00000000-0000-4000-8000-00000000d0b1
L1=00000000-0000-4000-8000-00000000d0c1
ok=0; mal=0
esperar() { if [[ "$3" =~ $2 ]]; then echo "  ✓ $1"; ok=$((ok+1)); else echo "  ✗ $1 — esperado /$2/, obtenido: $3"; mal=$((mal+1)); fi; }
limpiar() {
  psql_as supabase_admin <<SQL
set session_replication_role = replica;
delete from crm.lead_potencial_eventos where lead_id = '$L1';
delete from crm.lead_potencial where lead_id = '$L1';
delete from crm.leads where id = '$L1';
delete from crm.equipo where perfil_id in ('$V1','$S1');
delete from public.perfiles where id in ('$V1','$S1');
delete from auth.users where id in ('$V1','$S1');
SQL
}
limpiar
psql_as supabase_admin <<SQL
set session_replication_role = replica;
insert into auth.users (id, email) values ('$V1','dv1@caducidad.banco'),('$S1','ds1@caducidad.banco');
insert into public.perfiles (id, nombre_completo, rol, activo) values ('$V1','CONC CAD V1','analista',true),('$S1','CONC CAD S1','analista',true);
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values ('$S1','supervisor',null,true),('$V1','vendedor','$S1',true);
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, activo)
  values ('$L1','CONC CAD L1','+51987669001','landing',50000,'PEN','contactado','$V1',true);
insert into crm.lead_potencial (lead_id, nivel, origen, marcado_por, marcado_en)
  values ('$L1','estrella','manual','$V1', '2026-10-05 10:00'::timestamp at time zone 'America/Lima');
SQL

echo "A · la tarea se cruza con una re-marca en vuelo"
( psql_as postgres -c "begin; select pg_advisory_xact_lock(hashtext('crm.lead_potencial'), hashtext('$L1')); update crm.lead_potencial set marcado_en = '2026-10-12 09:00'::timestamp at time zone 'America/Lima', origen = 'manual' where lead_id = '$L1'; select pg_sleep(3); commit;" >/dev/null ) &
sleep 1
t0=$(date +%s%N); r=$(psql_as postgres -c "select private.potencial_caducar('2026-10-12')" 2>&1 | tail -1); t1=$(date +%s%N); wait
esperar "la tarea salta el lead ocupado (0 cambios)" '^0$' "$r"
esperar "la tarea NO esperó (< 1 s)" '^1$' "$(( (t1 - t0) < 1000000000 ? 1 : 0 ))"
esperar "el lead sigue estrella manual" '^estrella\|manual$' "$(psql_as postgres -c "select nivel || '|' || origen from crm.lead_potencial where lead_id = '$L1'")"
esperar "sin eventos de caducidad" '^0$' "$(psql_as postgres -c "select count(*) from crm.lead_potencial_eventos where lead_id = '$L1'")"

echo "B · la tarea se cruza con un descarte en vuelo"
psql_as postgres -c "update crm.lead_potencial set marcado_en = '2026-10-05 10:00'::timestamp at time zone 'America/Lima' where lead_id = '$L1'" >/dev/null
( psql_as supabase_admin -c "begin; set local session_replication_role = replica; update crm.leads set etapa = 'descartado', motivo_descarte = 'sin_interes' where id = '$L1'; select pg_sleep(3); commit;" >/dev/null ) &
sleep 1
t0=$(date +%s%N); r=$(psql_as postgres -c "select private.potencial_caducar('2026-10-12')" 2>&1 | tail -1); t1=$(date +%s%N); wait
esperar "la tarea salta el lead bloqueado (0 cambios)" '^0$' "$r"
esperar "la tarea NO esperó (< 1 s)" '^1$' "$(( (t1 - t0) < 1000000000 ? 1 : 0 ))"
esperar "confirmado el descarte, la marca quedó intacta" '^estrella\|manual$' "$(psql_as postgres -c "select nivel || '|' || origen from crm.lead_potencial where lead_id = '$L1'")"
esperar "y la tarea siguiente tampoco toca un lead descartado" '^0$' "$(psql_as postgres -c "select private.potencial_caducar('2026-10-12')")"

echo "C · sin nada en vuelo, la corrida siguiente baja lo que tocaba"
psql_as supabase_admin -c "set session_replication_role = replica; update crm.leads set etapa = 'contactado', motivo_descarte = null where id = '$L1';" >/dev/null
esperar "baja la estrella vencida" '^1$' "$(psql_as postgres -c "select private.potencial_caducar('2026-10-12')")"
esperar "queda tibio por caducidad" '^tibio\|caducidad$' "$(psql_as postgres -c "select nivel || '|' || origen from crm.lead_potencial where lead_id = '$L1'")"

limpiar
echo "CONCURRENCIA caducidad: $ok OK, $mal FALLAS"
[ "$mal" -eq 0 ]
