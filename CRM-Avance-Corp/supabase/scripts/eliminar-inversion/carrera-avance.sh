#!/usr/bin/env bash
# Carrera de DOS conexiones (Codex r1, P1): mientras un admin (sin gerencia) pide eliminar un contrato que AÚN no es
# conversión, otra sesión lo bloquea, le enlaza un lead convertido y confirma. La puerta debe clasificarlo DESPUÉS de esperar
# el contrato → es conversión → 42501 «solo gerencia». Con el contexto de r1 (sin bloquear el contrato) como MUTANTE, la
# carrera se reproduce: el admin eliminaría la conversión. Siembra con commit y limpia SIEMPRE al salir.
#   BANCO_CONTENEDOR=avancecorp-eliminar-inversion-20261005 bash supabase/scripts/eliminar-inversion/carrera-avance.sh
set -euo pipefail
C="${BANCO_CONTENEDOR:?BANCO_CONTENEDOR}"
psqla() { docker exec -i -e PGPASSWORD=postgres "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt "$@"; }
EMP=91000000-0000-4000-8000-000000000001
ADM=9a000000-0000-4000-8000-0000000000a1
VEN=9a000000-0000-4000-8000-0000000000a4
CLI=9a000000-0000-4000-8000-0000000000a5
INV=9b000000-0000-4000-8000-0000000000b1
CON=9d000000-0000-4000-8000-0000000000d1
IVR=9f000000-0000-4000-8000-0000000000f1
LEA=9c000000-0000-4000-8000-0000000000c1

limpiar() {
  psqla <<SQL >/dev/null 2>&1 || true
begin;
set local session_replication_role = replica;
delete from crm.inversiones_eliminadas where fuente_id = '$CON';
delete from crm.contratos_eliminados_auditoria where contrato_id = '$CON';
delete from private.contrato_eliminaciones where contrato_id = '$CON';
delete from crm.conversion_acreditaciones where lead_id = '$LEA';
delete from crm.cierres_avance_anulados where lead_id = '$LEA';
delete from crm.actividades where lead_id = '$LEA';
delete from crm.inversion_solicitudes where inversionista_id = '$INV';
delete from crm.inversion_eventos where inversion_id = '$IVR';
delete from crm.inversion_titulares where inversion_id = '$IVR';
delete from crm.inversiones where id = '$IVR';
delete from crm.lead_asignaciones where lead_id = '$LEA';
delete from crm.leads where id = '$LEA';
delete from public.contratos where id = '$CON';
delete from crm.inversionistas where id = '$INV';
delete from crm.equipo where perfil_id in ('$ADM', '$VEN');
delete from public.perfiles where id in ('$ADM', '$VEN', '$CLI');
delete from crm.empresas where id = '$EMP';
commit;
SQL
}
sembrar() {
  psqla <<SQL
begin;
set local session_replication_role = replica;
insert into crm.empresas (id, clave, nombre_legal, nombre_visible, fuente_capital, activa) values ('$EMP', 'avance', 'AVANCE CARRERA', 'Avance', 'contratos', true);
insert into public.perfiles (id, nombre_completo, rol, activo) values ('$ADM', 'ADMIN CARRERA', 'admin', true),
  ('$VEN', 'VENDEDOR CARRERA', 'analista', true), ('$CLI', 'CLIENTE CARRERA', 'cliente', true);
insert into crm.equipo (perfil_id, rol_crm, activo) values ('$VEN', 'vendedor', true);
insert into crm.inversionistas (id, estado) values ('$INV', 'activo');
insert into public.contratos (id, numero_contrato, cliente_id, capital, moneda, modalidad, fecha_inicio, fecha_vencimiento,
  producto_condicion_id, fecha_cierre_comercial, estado, categoria)
  values ('$CON', 'CARRERA-0001', '$CLI', 7000, 'PEN', 'mensual', '2026-09-10', '2027-09-10', gen_random_uuid(), '2026-09-10', 'activo', 'nuevo');
insert into crm.inversiones (id, inversionista_id, empresa_id, contrato_id, estado, fecha_comercial, es_primera_conversion)
  values ('$IVR', '$INV', '$EMP', '$CON', 'vigente', '2026-09-10', false);
insert into crm.inversion_titulares (inversion_id, inversionista_id) values ('$IVR', '$INV');
insert into crm.inversion_eventos (inversion_id, tipo) values ('$IVR', 'registro');
-- Lead convertido SIN contrato todavía: la otra sesión se lo enlazará en plena eliminación.
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, convertido_en, vendedor_id, perfil_id, contrato_id, activo, monto_estimado)
  values ('$LEA', 'LEAD CARRERA', '999000099', 'landing', 'convertido', '2026-09-10 15:00-05', '$VEN', '$CLI', null, true, 1000);
insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda, origen,
    sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en, resultado, resultado_en,
    finalizado_en, finalizado_por, motivo_cierre)
  values ('$LEA', 1, 1, '$VEN', 'asignado', '2026-09-05 15:00-05', 'PEN', 'landing', '2026-09-05 15:00-05', gen_random_uuid(),
    '2026-09-10 15:00-05', '2026-09-10 15:00-05', 'convertido', '2026-09-10 15:00-05', '2026-09-10 15:00-05', '$VEN', 'convertido');
commit;
SQL
}
# Sesión B: bloquea el contrato, espera, le enlaza el lead convertido y confirma.
sesion_b() {
  psqla <<SQL
begin;
select 1 from public.contratos where id = '$CON' for update;
select pg_sleep(4);
set local crm.op_privilegiada = 'on';
update crm.leads set contrato_id = '$CON' where id = '$LEA';
commit;
SQL
}
# Sesión A: el admin (sin gerencia) pide eliminar el contrato. \$1 = SQL opcional que va antes (el mutante).
sesion_a() {
  psqla <<SQL
begin;
$1
select set_config('request.jwt.claim.sub', '$ADM', true);
select set_config('request.jwt.claims', '{"sub":"$ADM","role":"authenticated"}', true);
set local role authenticated;
select 'RESULTADO ' || crm.eliminar_inversion_fn('$CON', 'Prueba de carrera de dos conexiones')::text;
-- SIEMPRE se deshace: así el mutante (si lo hay) nunca queda instalado y se juzga por la respuesta de la puerta.
rollback;
SQL
}
CONTEXTO_R1="$(cat <<'SQL'
create or replace function private.eliminar_inversion_contexto(p_fuente uuid)
returns jsonb language plpgsql set search_path = '' as $m$
declare v_ce crm.cierres_externos%rowtype; v_inv crm.inversiones%rowtype; v_lead uuid; v_tipo text; v_empresa text;
  v_es_conversion boolean := false; v_anulada boolean := false;
begin
  if p_fuente is null then return null; end if;
  select * into v_ce from crm.cierres_externos where id = p_fuente for update;
  if found then return null; end if;
  if not exists (select 1 from public.contratos c where c.id = p_fuente) then return null; end if;
  v_tipo := 'contrato'; v_empresa := 'avance';
  select * into v_inv from crm.inversiones where contrato_id = p_fuente for update;
  select l.id into v_lead from crm.leads l where l.contrato_id = p_fuente and l.etapa = 'convertido' order by l.id limit 1 for update;
  v_es_conversion := v_lead is not null or coalesce(v_inv.es_primera_conversion, false);
  v_anulada := v_lead is not null and private.cierre_anulado(v_lead);
  return jsonb_build_object('tipo', v_tipo, 'fuente_id', p_fuente, 'empresa', v_empresa, 'inversion_id', v_inv.id,
    'inversionista_id', v_inv.inversionista_id, 'es_conversion', v_es_conversion, 'lead_id', v_lead,
    'conversion_anulada', v_es_conversion and v_anulada);
end $m$;
SQL
)"
trap limpiar EXIT
correr() {  # $1 = etiqueta, $2 = SQL previo de la sesión A
  limpiar; sembrar
  sesion_b > /tmp/carrera-b.txt 2>&1 & local pb=$!
  sleep 1.5
  local salida; salida="$(sesion_a "$2" 2>&1 || true)"
  wait "$pb" || { echo "la sesión B falló: $(cat /tmp/carrera-b.txt)" >&2; exit 1; }
  local enlazado; enlazado="$(psqla -c "select count(*) from crm.leads where id = '$LEA' and contrato_id = '$CON'")"
  local contrato; contrato="$(psqla -c "select count(*) from public.contratos where id = '$CON'")"
  echo "$1 | A: $(printf '%s' "$salida" | grep -o 'RESULTADO.*\|ERROR:.*' | head -1 | cut -c1-120) | contrato vivo=$contrato | lead enlazado=$enlazado"
}
con="$(correr "CON la corrección (r2)" "")"; echo "$con"
mut="$(correr "MUTANTE contexto r1  " "$CONTEXTO_R1")"; echo "$mut"
printf '%s' "$con" | grep -q 'solo gerencia.*contrato vivo=1 | lead enlazado=1' \
  || { echo "FALLA: con la corrección, el admin no recibió 42501 «solo gerencia»" >&2; exit 1; }
printf '%s' "$mut" | grep -q 'RESULTADO {"ok": true.*lead enlazado=1' \
  || { echo "FALLA: el mutante (contexto r1) no reprodujo la carrera: la prueba no distingue" >&2; exit 1; }
echo "PASS carrera Avance: la corrección cierra la carrera y el mutante la reproduce"
