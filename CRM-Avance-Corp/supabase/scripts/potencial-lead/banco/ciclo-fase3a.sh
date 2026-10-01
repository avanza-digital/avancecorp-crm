#!/usr/bin/env bash
# Ciclo completo de la FASE 3, entrega A (20261001151704_crm_potencial_lead_lectura) en el BANCO
# Docker propio. Nunca contra producción. Exige las fases 1 y 2 aplicadas. Deja la migración aplicada
# y registrada.
#
#   BANCO_CONTENEDOR=avancecorp-potencial-20260930 bash banco/ciclo-fase3a.sh
#
# Qué corre:
#   1 · ciclo: migración → repetida (se niega) → reversa → repetida (se niega) → migración, con la
#       foto de los trinquetes (banco/trinquetes.sql) sin y con la migración: debe ser idéntica
#   2 · prueba-lectura.sql, y las fases 1 y 2 sin regresión (prueba-sintetica y prueba-caducidad)
#   3 · mutantes de LÓGICA sobre prueba-lectura.sql. «sin-sesion» sobrevive A PROPÓSITO (el gate lo
#       cubre); su doble con el gate roto debe caer
#   4 · mutantes de la MIGRACIÓN (postflight) y del PREFLIGHT (un ayudante o una policy cambiados,
#       sin la fase 2, o el job con otro horario): deben ser rechazados
#   5 · la medición de la puerta (medir-lectura.sql)
#   6 · registrar ×2, verificar, y el verificador frente a un ayudante abierto a PUBLIC (debe verlo)
set -uo pipefail
C="${BANCO_CONTENEDOR:-avancecorp-potencial-20260930}"
D="$(cd "$(dirname "$0")/../../.." && pwd)"   # …/supabase
P="$D/scripts/potencial-lead"
V=20261001151704
M="$D/migrations/${V}_crm_potencial_lead_lectura.sql"
R="$P/reversa-lectura.sql"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

q() { docker exec -i -e PGPASSWORD=postgres "$C" psql -U "${2:-postgres}" -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "$1" 2>&1; }
msg() { local o; o=$(q "$(cat "$1")"); if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-130; else grep -o 'NOTICE:.*' <<<"$o" | tail -1 | cut -c1-130; fi; }
rechazo() { local o; o=$(q "$(cat "$1")"); if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-120; else echo "SIN ERROR (¡el mutante pasó!)"; fi; }
sint() { docker cp "$1" "$C:/tmp/s.sql" >/dev/null; docker exec -e PGPASSWORD=postgres "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -f /tmp/s.sql 2>&1 | grep -o 'LECTURA.*\|CADUCIDAD.*\|SINTETICA.*\|MEDIR.*\|ERROR:  mutante.*\|ERROR:.*' | head -1 | cut -c1-320; }
trinquetes() { docker cp "$P/banco/trinquetes.sql" "$C:/tmp/t.sql" >/dev/null; docker exec -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -qAt -f /tmp/t.sql 2>&1 | sed 's/^psql:[^ ]* NOTICE:  //'; }
aplicada() { q "select (to_regprocedure('crm.potencial_leads_fn(uuid[])') is not null)::int"; }
job() { q "select coalesce((select schedule from cron.job where jobname='crm-potencial-lead-caducidad'), '(sin job)')"; }

if [ "$(q "select (to_regclass('crm.lead_potencial') is not null and to_regprocedure('private.potencial_nivel_tras(crm.nivel_potencial,integer)') is not null)::int")" != "1" ]; then
  echo "Faltan las fases 1 y 2 en el banco: corre antes banco/ciclo-fase1.sh y banco/ciclo-fase2.sh." >&2; exit 2
fi
[ "$(aplicada)" = "1" ] && echo "0 reversa del estado previo: $(msg "$R")"

echo "── 1 · ciclo"
trinquetes > "$T/sin.txt"
echo "1 migración:        $(msg "$M")"
echo "2 repetida:         $(rechazo "$M")"
trinquetes > "$T/con.txt"
echo "3 reversa:          $(msg "$R")"
echo "4 reversa repetida: $(rechazo "$R")"
echo "5 migración:        $(msg "$M")"
if diff -q "$T/sin.txt" "$T/con.txt" >/dev/null; then
  echo "6 trinquetes:       idénticos sin y con la migración ($(grep -c 'pasa$' "$T/con.txt") pasan, $(grep -c 'cae:' "$T/con.txt") caen igual, censo igual)"
else
  echo "6 trinquetes:       ¡CAMBIARON!"; diff "$T/sin.txt" "$T/con.txt" | cut -c1-220 | head -12
fi

echo "── 2 · pruebas"
echo "7 lectura:          $(sint "$P/prueba-lectura.sql")"
echo "8 fase 1 intacta:   $(sint "$P/prueba-sintetica.sql")"
echo "9 fase 2 intacta:   $(sint "$P/prueba-caducidad.sql")"

echo "── 3 · mutantes de lógica (la prueba de lectura debe reportar fallas)"
python3 - "$T" "$P/prueba-lectura.sql" <<'PY'
import sys
T,S=sys.argv[1:]
t=open(S).read()
def cuerpo(n,fn,a,b):
    return f"""do $m$ declare d text := pg_get_functiondef('{fn}'::regprocedure);
begin
  if position($a${a}$a$ in d) = 0 then raise exception 'mutante {n}: no encontré el fragmento'; end if;
  execute replace(d, $a${a}$a$, $b${b}$b$);
end $m$;
"""
def mut(n,*pares):
    open(f'{T}/m-{n}.sql','w').write(t.replace("begin;\n","begin;\n"+''.join(cuerpo(n,*p) for p in pares),1))
NUC='private.potencial_lectura(uuid,uuid[],date,timestamp with time zone,date)'; PUE='crm.potencial_leads_fn(uuid[])'
BAJA='private.potencial_proxima_baja(crm.nivel_potencial,date,date)'; CORR='private.potencial_proxima_corrida(timestamp with time zone)'
RELOJ="private.potencial_reloj(p.lead_id, p.marcado_en, p_corte)"
mut('ve-inactivos',(NUC,"and l.activo = true","and true"))
mut('sin-ambito',(NUC,"        l.vendedor_id = any (v_visibles)\n","        true\n"))
mut('sin-propios',(NUC,"        l.vendedor_id = any (v_visibles)\n","        false\n"))
mut('sin-parqueo',(NUC,"        or (l.vendedor_id is null and l.asignado_supervisor_id = any (v_visibles))\n",""))
mut('sin-gerencia',(NUC,"        or v_rol = 'gerencia'\n",""))
mut('sin-lector',(NUC,"        or v_lector\n",""))
mut('actor-ajeno',(NUC,"if p_actor is distinct from (select auth.uid()) then","if false then"))
mut('puede-siempre',(NUC,"coalesce(private.potencial_rechazo(p_actor, l.id) = 'ok', false)","true"))
mut('puede-nunca',(NUC,"coalesce(private.potencial_rechazo(p_actor, l.id) = 'ok', false)","false"))
mut('marcado-cualquier-evento',(NUC,"where e.lead_id = p.lead_id and e.motivo = 'manual'","where e.lead_id = p.lead_id"))
mut('marcado-el-primero',(NUC,"order by e.orden desc","order by e.orden asc"))
mut('sin-zona-lima',(NUC,RELOJ+" at time zone 'America/Lima')::date as reloj_dia",RELOJ+")::date as reloj_dia"))
mut('reloj-sin-contactos',(NUC,RELOJ,"p.marcado_en"))
mut('corte-infinito',(NUC,RELOJ,"private.potencial_reloj(p.lead_id, p.marcado_en, 'infinity'::timestamptz)"))
mut('dias-hasta-manana',(NUC,"private.dias_lunes_a_sabado(x.reloj_dia, p_hoy) as dias","private.dias_lunes_a_sabado(x.reloj_dia, p_hoy + 1) as dias"))
mut('cerrados-bajan',(NUC,"      where l.etapa is not null and l.etapa not in ('convertido', 'descartado')\n","      where true\n"))
mut('proxima-es-hoy',(NUC,"private.potencial_proxima_baja(p.nivel, r.reloj_dia, p_proxima)","private.potencial_proxima_baja(p.nivel, r.reloj_dia, p_hoy)"))
mut('baja-un-dia-tarde',(BAJA,"v_dia := p_desde + i;","v_dia := p_desde + i + 1;"))
mut('baja-nivel-fijo',(BAJA,"baja_a := v_nuevo;","baja_a := 'tibio'::crm.nivel_potencial;"))
mut('baja-no-para',(BAJA,"      return next;\n      return;\n","      return next;\n"))
mut('corrida-a-las-0510',(CORR,"< time '05:45'","< time '05:10'"))
mut('corrida-sin-margen',(CORR,"< time '05:45'","< time '05:40'"))
mut('corrida-siempre-hoy',(CORR,"else (p_instante at time zone 'America/Lima')::date + 1","else (p_instante at time zone 'America/Lima')::date"))
mut('corrida-sin-zona',(CORR,"when (p_instante at time zone 'America/Lima')::time < time '05:45'","when (p_instante at time zone 'UTC')::time < time '05:45'"))
GATE=(PUE,"if private.puede_acceder_crm() is not true then","if false then")
SESION=(PUE,"if v_actor is null then","if false then")
mut('sin-gate',GATE)
mut('sin-bandera',(PUE,"if crm.bandera_activa('potencial_lead') is not true then","if false then"))
mut('sin-tope',(PUE,"pg_catalog.cardinality(p_lead_ids) > 200","pg_catalog.cardinality(p_lead_ids) > 100000"))
mut('tope-una-dimension',(PUE,"pg_catalog.cardinality(p_lead_ids) > 200","pg_catalog.array_length(p_lead_ids, 1) > 200"))
mut('sin-sesion',SESION)
mut('sin-sesion-ni-gate',SESION,GATE)
PY
for f in "$T"/m-*.sql; do printf "  %-26s → %s\n" "$(basename "$f" .sql)" "$(sint "$f")"; done
echo "  (sin-sesion debe dar «de N OK»: sin sesión el gate ya rechaza; su doble sin-sesion-ni-gate debe caer)"

echo "── 4 · mutantes de la migración y del preflight (deben ser rechazados)"
python3 - "$T" "$M" "$R" <<'PY'
import sys
T,M,R=sys.argv[1:]
mig=open(M).read(); rev=open(R).read()
rev=rev.replace("begin;\nset local lock_timeout = '5s';\n",'',1); rev=rev[:rev.rindex('commit;')]
m=mig.replace("begin;\nset local lock_timeout = '5s';\n",'',1); m=m[:m.rindex('commit;')]
CAB="begin;\nset local lock_timeout = '5s';\n"
def mut(n,a,b):
    assert a in m, n
    open(f'{T}/mf-{n}.sql','w').write(CAB+rev+'\n'+m.replace(a,b,1)+'\ncommit;\n')
def pre(n,antes):
    open(f'{T}/mf-{n}.sql','w').write(CAB+rev+'\n'+antes+'\n'+m+'\ncommit;\n')
PUERTA="language plpgsql\nstable\nsecurity definer\nset search_path = ''\nas $function$\ndeclare\n  v_actor uuid"
NUCLEO="language plpgsql\nstable\nsecurity invoker\nset search_path = ''\nas $function$\ndeclare\n  v_rol text;"
GRANT='grant execute on function crm.potencial_leads_fn(uuid[]) to authenticated;'
mut('puerta-invoker',PUERTA,PUERTA.replace('security definer','security invoker'))
mut('puerta-volatil',PUERTA,PUERTA.replace('stable','volatile'))
mut('puerta-sin-search-path',PUERTA,PUERTA.replace("set search_path = ''\n",''))
mut('puerta-set-de-mas',PUERTA,PUERTA.replace("set search_path = ''\n","set search_path = ''\nset statement_timeout = '30s'\n"))
mut('puerta-anon',GRANT,GRANT.replace('to authenticated;','to authenticated, anon;'))
mut('puerta-service-role',GRANT,GRANT.replace('to authenticated;','to authenticated, service_role;'))
mut('puerta-con-opcion',GRANT,GRANT.replace('to authenticated;','to authenticated with grant option;'))
mut('puerta-sin-grant',GRANT,'')
mut('nucleo-abierto','revoke all on function private.potencial_lectura(uuid, uuid[], date, timestamptz, date) from public, anon, authenticated, service_role;\n','')
mut('ayudante-abierto','revoke all on function private.potencial_proxima_baja(crm.nivel_potencial, date, date) from public, anon, authenticated, service_role;\n','')
mut('ayudante-a-authenticated',GRANT,GRANT+'\ngrant execute on function private.potencial_proxima_corrida(timestamptz) to authenticated;')
mut('nucleo-definer',NUCLEO,NUCLEO.replace('security invoker','security definer'))
mut('nucleo-acepta-otro-actor',"  if p_actor is distinct from (select auth.uid()) then\n","  if false then\n")
mut('con-conteo',"  v_rol := private.rol_crm(p_actor);\n","  perform (select pg_catalog.count(*) from crm.leads x where false);\n  v_rol := private.rol_crm(p_actor);\n")
mut('corrida-otra-hora',"< time '05:45'","< time '06:00'")
mut('corrida-sin-margen',"< time '05:45'","< time '05:40'")
mut('baja-un-dia-tarde',"    v_dia := p_desde + i;\n","    v_dia := p_desde + i + 1;\n")
pre('pre-ayudante-cambiado',"alter function private.es_lector_global() set statement_timeout = '30s';")
pre('pre-policy-nueva',"create policy lectura_mutante on crm.leads as restrictive for select to authenticated using (true);")
pre('pre-permisiva-nueva',"create policy lectura_mutante on crm.leads for select to authenticated using (false);")
pre('pre-policy-cambiada',"alter policy leads_select on crm.leads using (activo = true);")
pre('pre-gate-cambiado',"alter policy crm_actor_activo_gate on crm.leads using (true);")
pre('pre-roles-cambiados',"alter policy leads_select on crm.leads to authenticated, anon;")
pre('pre-sin-fase-2',"drop function private.potencial_nivel_tras(crm.nivel_potencial, integer);")
pre('pre-job-otro-horario',"update cron.job set schedule = '10 10 * * *' where jobname = 'crm-potencial-lead-caducidad';")
pre('pre-job-otro-comando',"update cron.job set command = 'select 1' where jobname = 'crm-potencial-lead-caducidad';")
pre('pre-job-inactivo',"update cron.job set active = false where jobname = 'crm-potencial-lead-caducidad';")
pre('pre-job-ausente',"delete from cron.job where jobname = 'crm-potencial-lead-caducidad';")
PY
for f in "$T"/mf-*.sql; do printf "  %-26s → %s\n" "$(basename "$f" .sql)" "$(rechazo "$f")"; done
echo "  tras los mutantes: puerta aplicada=$(aplicada), policies de crm.leads=$(q "select count(*) from pg_policy where polrelid='crm.leads'::regclass"), job=$(job)"
# Sin pg_cron (un banco sin la extensión) la migración se instala pero DICE que no comprobó la tarea.
python3 - "$T" "$M" "$R" <<'PY'
import sys
T,M,R=sys.argv[1:]
mig=open(M).read(); rev=open(R).read()
rev=rev.replace("begin;\nset local lock_timeout = '5s';\n",'',1); rev=rev[:rev.rindex('commit;')]
m=mig.replace("begin;\nset local lock_timeout = '5s';\n",'',1); m=m[:m.rindex('commit;')]
open(f'{T}/sin-cron.sql','w').write("begin;\ndrop extension pg_cron;\n"+rev+"\n"+m+"\nrollback;\n")
PY
echo "  sin pg_cron (se deshace): $(q "$(cat "$T/sin-cron.sql")" supabase_admin | grep -o 'ERROR:.*\|NOTICE:  potencial_lectura.*' | tail -1 | cut -c1-200)"
echo "  tras el ensayo sin pg_cron: puerta aplicada=$(aplicada), job=$(job)"

echo "── 5 · medición"
echo "10 $(sint "$P/banco/medir-lectura.sql")"

echo "── 6 · registro y verificación"
if grep -q "md5 $(md5 -q "$M" 2>/dev/null || md5sum "$M" | cut -d' ' -f1)" "$P/registrar-lectura.sql"; then echo "11 el registrador lleva el md5 de la migración"; else echo "11 ¡el registrador NO coincide con la migración! Regenerar con banco/generar-registrador.py"; fi
echo "12 registrar:        $(msg "$P/registrar-lectura.sql")"
echo "13 registrar otra vez: $(msg "$P/registrar-lectura.sql")"
echo "14 verificar:        $(q "$(cat "$P/verificar-lectura.sql")" | grep -o 'VERIFICAR.*' | cut -c1-420)"
# El verificador frente a un estado malo: un ayudante abierto a PUBLIC (se deshace). Debe decir 3, no 0.
echo "15 verificar con un ayudante abierto a PUBLIC: $(q "begin; grant execute on function private.potencial_proxima_baja(crm.nivel_potencial, date, date) to public; $(cat "$P/verificar-lectura.sql")" | grep -o 'EXECUTE de la API en los 3 ayudantes [0-9]*' )  (debe ser 3)"
