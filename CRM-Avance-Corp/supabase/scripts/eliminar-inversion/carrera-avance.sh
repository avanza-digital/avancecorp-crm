#!/usr/bin/env bash
# Carreras de DOS conexiones sobre la clasificación «¿es una conversión?» de crm.eliminar_inversion_fn. En ambas, un admin
# (sin gerencia) pide eliminar un contrato que AÚN no es conversión mientras otra sesión lo convierte en conversión y confirma:
#   1 (Codex r1, P1) la otra sesión bloquea el contrato y le ENLAZA un lead convertido;
#   2 (Codex r2)     la otra sesión, como el único escritor de acreditaciones (private.conversion_acreditar_fuente), toma el
#                    candado del MES de la fuente y la ACREDITA.
# La puerta debe esperar y clasificar DESPUÉS → 42501 «solo gerencia». Con el contexto sin el candado correspondiente (mutante)
# la carrera se reproduce: el admin eliminaría la conversión. La sesión A SIEMPRE se deshace (se juzga por su respuesta), y la
# siembra se limpia al salir.
#   BANCO_CONTENEDOR=avancecorp-eliminar-inversion-20261005 bash supabase/scripts/eliminar-inversion/carrera-avance.sh
set -euo pipefail
C="${BANCO_CONTENEDOR:?BANCO_CONTENEDOR}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIG="$DIR/../../migrations/20261005200945_crm_eliminar_inversion.sql"
psqla() { docker exec -i -e PGPASSWORD=postgres "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt "$@"; }
EMP=91000000-0000-4000-8000-000000000001
ADM=9a000000-0000-4000-8000-0000000000a1
VEN=9a000000-0000-4000-8000-0000000000a4
CLI=9a000000-0000-4000-8000-0000000000a5
INV=9b000000-0000-4000-8000-0000000000b1
CON=9d000000-0000-4000-8000-0000000000d1   # escenario 1: se le enlaza un lead
CON2=9d000000-0000-4000-8000-0000000000d2  # escenario 2: se acredita
IVR=9f000000-0000-4000-8000-0000000000f1
IVR2=9f000000-0000-4000-8000-0000000000f2
LEA=9c000000-0000-4000-8000-0000000000c1
LEA2=9c000000-0000-4000-8000-0000000000c2
SEPT="$(psqla -c "select (date '2026-09-01' - date '2000-01-01')")"   # misma clave de mes que crm.cerrar_periodo

limpiar() {
  psqla <<SQL >/dev/null 2>&1 || true
begin;
set local session_replication_role = replica;
delete from crm.inversiones_eliminadas where fuente_id in ('$CON', '$CON2');
delete from crm.contratos_eliminados_auditoria where contrato_id in ('$CON', '$CON2');
delete from private.contrato_eliminaciones where contrato_id in ('$CON', '$CON2');
delete from crm.conversion_acreditaciones where lead_id in ('$LEA', '$LEA2');
delete from crm.cierres_avance_anulados where lead_id in ('$LEA', '$LEA2');
delete from crm.actividades where lead_id in ('$LEA', '$LEA2');
delete from crm.inversion_solicitudes where inversionista_id = '$INV';
delete from crm.inversion_eventos where inversion_id in ('$IVR', '$IVR2');
delete from crm.inversion_titulares where inversion_id in ('$IVR', '$IVR2');
delete from crm.inversiones where id in ('$IVR', '$IVR2');
delete from crm.lead_asignaciones where lead_id in ('$LEA', '$LEA2');
delete from crm.leads where id in ('$LEA', '$LEA2');
delete from public.contratos where id in ('$CON', '$CON2');
delete from crm.inversionistas where id = '$INV';
delete from crm.equipo where perfil_id in ('$ADM', '$VEN');
delete from public.perfiles where id in ('$ADM', '$VEN', '$CLI');
delete from crm.empresas where id = '$EMP';
delete from crm.conversion_politica where manifiesto_huella = 'carrera';
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
insert into crm.conversion_politica (unica, vigente_desde, activada_en, manifiesto_huella, resultado)
  values (true, '2026-09-01', '2026-09-01 00:00-05', 'carrera', '{}'::jsonb) on conflict (unica) do nothing;
insert into public.contratos (id, numero_contrato, cliente_id, capital, moneda, modalidad, fecha_inicio, fecha_vencimiento,
  producto_condicion_id, fecha_cierre_comercial, estado, categoria) values
  ('$CON', 'CARRERA-0001', '$CLI', 7000, 'PEN', 'mensual', '2026-09-10', '2027-09-10', gen_random_uuid(), '2026-09-10', 'activo', 'nuevo'),
  ('$CON2', 'CARRERA-0002', '$CLI', 8000, 'PEN', 'mensual', '2026-09-15', '2027-09-15', gen_random_uuid(), '2026-09-15', 'activo', 'nuevo');
insert into crm.inversiones (id, inversionista_id, empresa_id, contrato_id, estado, fecha_comercial, es_primera_conversion) values
  ('$IVR', '$INV', '$EMP', '$CON', 'vigente', '2026-09-10', false), ('$IVR2', '$INV', '$EMP', '$CON2', 'vigente', '2026-09-15', false);
insert into crm.inversion_titulares (inversion_id, inversionista_id) values ('$IVR', '$INV'), ('$IVR2', '$INV');
insert into crm.inversion_eventos (inversion_id, tipo) values ('$IVR', 'registro'), ('$IVR2', 'registro');
-- Leads convertidos SIN contrato enlazado ni acreditación: la otra sesión los volverá conversión en plena eliminación.
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, convertido_en, vendedor_id, perfil_id, contrato_id, activo, monto_estimado) values
  ('$LEA', 'LEAD CARRERA', '999000099', 'landing', 'convertido', '2026-09-10 15:00-05', '$VEN', '$CLI', null, true, 1000),
  ('$LEA2', 'LEAD CARRERA ACREDITA', '999000098', 'landing', 'convertido', '2026-09-15 15:00-05', '$VEN', '$CLI', null, true, 1000);
insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda, origen,
    sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en, resultado, resultado_en,
    finalizado_en, finalizado_por, motivo_cierre)
  select l.id, 1, 1, '$VEN', 'asignado', l.convertido_en - interval '5 days', 'PEN', 'landing', l.convertido_en - interval '5 days',
    gen_random_uuid(), l.convertido_en, l.convertido_en, 'convertido', l.convertido_en, l.convertido_en, '$VEN', 'convertido'
  from crm.leads l where l.id in ('$LEA', '$LEA2');
commit;
SQL
}
# Sesión B, escenario 1: bloquea el contrato, espera, le enlaza el lead convertido y confirma.
sesion_b1() {
  psqla <<SQL
begin;
select 1 from public.contratos where id = '$CON' for update;
select pg_sleep(4);
set local crm.op_privilegiada = 'on';
update crm.leads set contrato_id = '$CON' where id = '$LEA';
commit;
SQL
}
# Sesión B, escenario 2: como private.conversion_acreditar_fuente, toma el candado del MES de la fuente y la acredita.
sesion_b2() {
  psqla <<SQL
begin;
select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'), $SEPT);
select pg_sleep(4);
insert into crm.conversion_acreditaciones (lead_id, episodio_id, inversionista_id, analista_id, origen, fuente_tipo, fuente_id, fecha_comercial,
    confirmado_en, vinculado_en, acreditado_en, periodo_comercial, plazo_hasta, estado, motivo)
  values ('$LEA2', (select la.id from crm.lead_asignaciones la where la.lead_id = '$LEA2' and la.resultado = 'convertido'), '$INV', '$VEN', 'landing', 'contrato', '$CON2', '2026-09-15', '2026-09-15 15:00-05', '2026-09-15 15:00-05',
    '2026-09-15 15:00-05', '2026-09-01', private.conversion_plazo_hasta('2026-09-01'), 'acreditada', 'Acreditación de la carrera');
commit;
SQL
}
# Sesión A: el admin (sin gerencia) pide eliminar. \$1 = contrato, \$2 = SQL opcional que va antes (el mutante).
sesion_a() {
  psqla <<SQL
begin;
$2
select set_config('request.jwt.claim.sub', '$ADM', true);
select set_config('request.jwt.claims', '{"sub":"$ADM","role":"authenticated"}', true);
set local role authenticated;
select 'RESULTADO ' || crm.eliminar_inversion_fn('$1', 'Prueba de carrera de dos conexiones')::text;
-- SIEMPRE se deshace: así el mutante (si lo hay) nunca queda instalado y se juzga por la respuesta de la puerta.
rollback;
SQL
}
# Mutantes: el contexto de la migración SIN el candado del contrato (r1) o SIN el candado del mes (r3).
contexto_sin() {
  python3 - "$MIG" "$1" <<'PY'
import sys
mig, quitar = sys.argv[1], sys.argv[2]
s = open(mig).read()
i = s.index('create function private.eliminar_inversion_contexto')
j = s.index('end $$;', i) + len('end $$;')
f = s[i:j].replace('create function', 'create or replace function', 1)
if quitar == 'contrato':
    for a, b in [
        ("    perform pg_advisory_xact_lock(hashtextextended('contrato_eliminar_auditado:' || p_fuente::text, 0));\n", ''),
        ("    select c.fecha_cierre_comercial into v_fecha from public.contratos c where c.id = p_fuente for update;\n",
         "    select c.fecha_cierre_comercial into v_fecha from public.contratos c where c.id = p_fuente;\n"),
        ("    perform 1 from crm.leads l where l.contrato_id = p_fuente order by l.id for update;\n", ''),
        # Sin el candado del contrato tampoco hay candado de mes previo: el r1 no lo tenía.
        ("  perform pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'),\n    (date_trunc('month', v_fecha::timestamp)::date - date '2000-01-01')::integer);\n", ''),
    ]:
        assert f.count(a) == 1, a
        f = f.replace(a, b)
else:
    a = "  perform pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'),\n    (date_trunc('month', v_fecha::timestamp)::date - date '2000-01-01')::integer);\n"
    assert f.count(a) == 1, a
    f = f.replace(a, '')
print(f)
PY
}
trap limpiar EXIT
correr() {  # $1 = etiqueta, $2 = sesión B, $3 = contrato, $4 = SQL previo de la sesión A
  limpiar; sembrar >/dev/null
  "$2" > /tmp/carrera-b.txt 2>&1 & local pb=$!
  sleep 1.5
  local salida; salida="$(sesion_a "$3" "$4" 2>&1 || true)"
  wait "$pb" || { echo "la sesión B falló: $(cat /tmp/carrera-b.txt)" >&2; exit 1; }
  echo "$1 | A: $(printf '%s' "$salida" | grep -o 'RESULTADO.*\|ERROR:.*' | head -1 | cut -c1-110)"
}
fallo=0
r1="$(correr "1 enlace     · corregido" sesion_b1 "$CON" "")"; echo "$r1"
m1="$(correr "1 enlace     · MUTANTE  " sesion_b1 "$CON" "$(contexto_sin contrato)")"; echo "$m1"
r2="$(correr "2 acreditar  · corregido" sesion_b2 "$CON2" "")"; echo "$r2"
m2="$(correr "2 acreditar  · MUTANTE  " sesion_b2 "$CON2" "$(contexto_sin mes)")"; echo "$m2"
for r in "$r1" "$r2"; do printf '%s' "$r" | grep -q 'solo gerencia' || { echo "FALLA: la corrección no cerró: $r" >&2; fallo=1; }; done
for m in "$m1" "$m2"; do printf '%s' "$m" | grep -q 'RESULTADO {"ok": true' || { echo "FALLA: el mutante no reprodujo la carrera (la prueba no distingue): $m" >&2; fallo=1; }; done
[ "$fallo" -eq 0 ] && echo "PASS carreras Avance: la corrección cierra las dos carreras y cada mutante la reproduce"
exit "$fallo"
