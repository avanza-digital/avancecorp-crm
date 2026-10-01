#!/usr/bin/env bash
# Ciclo completo de la FASE 2 (20260930235917_crm_potencial_lead_caducidad) en el BANCO Docker
# propio. Nunca contra producción. Exige la fase 1 aplicada. Deja la fase 2 aplicada y registrada.
#
#   BANCO_CONTENEDOR=avancecorp-potencial-20260930 bash banco/ciclo-fase2.sh
#
# Qué corre:
#   1 · SIN pg_cron: migración → reversa → migración → reversa (la reversa no debe nombrar cron.job)
#   2 · CON pg_cron: migración (job programado) → repetida (se niega) → reversa de la fase 1 con la
#       2 puesta (se niega) → reversa f2 (sin job) → repetida (se niega) → migración
#   3 · prueba-caducidad.sql, prueba-sintetica.sql (fase 1 sin regresión) y
#       prueba-concurrencia-caducidad.sh
#   4 · mutantes de LÓGICA sobre prueba-caducidad.sql. «cerrados» y «corte» rotos SOLO en el filtro
#       sobreviven A PROPÓSITO (la relectura bajo candado los cubre); los dobles deben caer.
#   5 · mutantes de CONCURRENCIA (la tarea espera el consultivo; sin SKIP LOCKED)
#   6 · mutantes de la MIGRACIÓN (su postflight debe rechazarlos)
#   7 · una corrida REAL de pg_cron con la misma orden, y la medición del lote (medir-lote.sql)
#   8 · registrar ×2 y verificar
set -uo pipefail
C="${BANCO_CONTENEDOR:-avancecorp-potencial-20260930}"
D="$(cd "$(dirname "$0")/../../.." && pwd)"   # …/supabase
P="$D/scripts/potencial-lead"
M="$D/migrations/20260930235917_crm_potencial_lead_caducidad.sql"
R2="$P/reversa-caducidad.sql"; R1="$P/reversa.sql"
CAD="private.potencial_caducar(date,timestamp with time zone,integer)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

q() { docker exec -i -e PGPASSWORD=postgres "$C" psql -U "${2:-postgres}" -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "$1" 2>&1; }
msg() { local o; o=$(q "$(cat "$1")"); if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-130; else grep -o 'NOTICE:.*' <<<"$o" | tail -1 | cut -c1-130; fi; }
rechazo() { local o; o=$(q "$(cat "$1")"); if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-110; else echo "SIN ERROR (¡el mutante pasó!)"; fi; }
job() { q "select coalesce((select schedule || ' | ' || command || ' | ' || username || '@' || database || ' | ' || active from cron.job where jobname='crm-potencial-lead-caducidad'), '(sin job)')"; }
sint() { docker cp "$1" "$C:/tmp/s.sql" >/dev/null; docker exec -e PGPASSWORD=postgres "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -f /tmp/s.sql 2>&1 | grep -o 'CADUCIDAD.*\|SINTETICA.*\|ERROR:  mutante.*\|ERROR:.*' | head -1 | cut -c1-300; }
conc() { BANCO_CONTENEDOR="$C" bash "$P/prueba-concurrencia-caducidad.sh" 2>&1; }
con_cron() { q "create extension if not exists pg_cron; grant usage on schema cron to postgres with grant option; grant all on all tables in schema cron to postgres with grant option; grant all on all functions in schema cron to postgres with grant option; grant all on all sequences in schema cron to postgres with grant option;" supabase_admin >/dev/null; }

if [ "$(q "select (to_regclass('crm.lead_potencial') is not null)::int")" != "1" ]; then
  echo "Falta la fase 1 en el banco: aplica antes 20260930213647_crm_potencial_lead.sql (o corre banco/ciclo-fase1.sh)." >&2; exit 2
fi
con_cron
[ "$(q "select (to_regprocedure('private.dias_lunes_a_sabado(date,date)') is not null)::int")" = "1" ] && echo "0 reversa del estado previo: $(msg "$R2")"

echo "── 1 · SIN pg_cron"
q "drop extension pg_cron;" supabase_admin >/dev/null
echo "1 migración:        $(msg "$M")"
echo "2 reversa:          $(msg "$R2")"
echo "3 migración:        $(msg "$M")"
echo "4 reversa:          $(msg "$R2")"
con_cron
echo "── 2 · CON pg_cron"
echo "5 migración:        $(msg "$M")"
echo "  job:              $(job)"
echo "6 repetida:         $(msg "$M")"
echo "7 reversa f1 con la f2 puesta: $(msg "$R1")"
echo "8 reversa f2:       $(msg "$R2")"
echo "  job:              $(job)"
echo "9 reversa repetida: $(msg "$R2")"
echo "10 migración:       $(msg "$M")"
echo "  job:              $(job)"
echo "── 3 · pruebas"
echo "11 caducidad:       $(sint "$P/prueba-caducidad.sql")"
echo "12 fase 1 intacta:  $(sint "$P/prueba-sintetica.sql")"
echo "13 concurrencia:"; conc | grep "✓\|✗\|CONCURRENCIA"

echo "── 4 · mutantes de lógica (la prueba de caducidad debe reportar fallas)"
python3 - "$T" "$P/prueba-caducidad.sql" <<'PY'
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
DIAS='private.dias_lunes_a_sabado(date,date)'; CAD='private.potencial_caducar(date,timestamp with time zone,integer)'
RELOJ='private.potencial_reloj(uuid,timestamp with time zone,timestamp with time zone)'; REGLA='private.potencial_nivel_tras(crm.nivel_potencial,integer)'
INICIO="p_hoy::timestamp at time zone 'America/Lima'"
mut('domingo-cuenta',(DIAS,"where pg_catalog.date_part('isodow', d) <> 7","where true"))
mut('hoy-incluido',(DIAS,"(p_hasta - 1)::timestamp","p_hasta::timestamp"))
mut('nota-es-gestion',(RELOJ,"'whatsapp_recibido', 'reunion_realizada')\n      and a.creado_en <= p_corte","'whatsapp_recibido', 'reunion_realizada', 'nota')\n      and a.creado_en <= p_corte"))
mut('reloj-sin-contacto',(RELOJ,"select max(a.creado_en) from crm.actividades a","select null::timestamptz from crm.actividades a"))
mut('futuro-cuenta',(RELOJ,"\n      and a.creado_en <= p_corte",""))
mut('sin-limite',(CAD,"    limit p_limite",""))
mut('sin-zona-lima',(CAD," at time zone 'America/Lima')::date, p_hoy)",")::date, p_hoy)"))
mut('umbral-4',(REGLA,"when p_dias >= 5 and p_nivel = 'estrella'","when p_dias >= 4 and p_nivel = 'estrella'"))
mut('tibio-a-5',(REGLA,"when p_dias >= 10 then","when p_dias >= 5 and p_nivel = 'tibio' then 'frio'::crm.nivel_potencial when p_dias >= 10 then"))
F_CERR=(CAD,"and l.etapa not in ('convertido', 'descartado')\n      and private","and true\n      and private")
B_CERR=(CAD,"and v_etapa not in ('convertido', 'descartado')","and true")
F_CORTE=(CAD,"private.potencial_reloj(p.lead_id, p.marcado_en, p_corte)",f"private.potencial_reloj(p.lead_id, p.marcado_en, {INICIO})")
B_CORTE=(CAD,"private.potencial_reloj(v_lead, v_actual.marcado_en, p_corte)",f"private.potencial_reloj(v_lead, v_actual.marcado_en, {INICIO})")
mut('cerrados-solo-filtro',F_CERR)
mut('cerrados-doble',F_CERR,B_CERR)
mut('corte-solo-filtro',F_CORTE)
mut('corte-doble',F_CORTE,B_CORTE)
PY
for f in "$T"/m-*.sql; do printf "  %-22s → %s\n" "$(basename "$f" .sql)" "$(sint "$f")"; done
echo "  (cerrados-solo-filtro y corte-solo-filtro deben dar «de N OK»: los cubre la relectura bajo candado)"

echo "── 5 · mutantes de concurrencia (debe fallar «NO esperó»)"
q "select pg_get_functiondef('$CAD'::regprocedure)" > "$T/caducar-original.sql"
restaurar() { docker exec -i -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -q < "$T/caducar-original.sql" >/dev/null; }
q "do \$x\$ declare d text := pg_get_functiondef('$CAD'::regprocedure); begin execute replace(d, 'continue when pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext(''crm.lead_potencial''), pg_catalog.hashtext(v_lead::text)) is not true;', 'perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(''crm.lead_potencial''), pg_catalog.hashtext(v_lead::text));'); end \$x\$;" >/dev/null
echo "  la tarea espera el consultivo:"; conc | grep "✗\|CONCURRENCIA"
restaurar
q "do \$x\$ declare d text := pg_get_functiondef('$CAD'::regprocedure); begin execute replace(d, 'for share skip locked;', 'for share;'); end \$x\$;" >/dev/null
echo "  sin SKIP LOCKED:"; conc | grep "✗\|CONCURRENCIA"
restaurar
echo "  restaurada: $(q "select position('skip locked' in pg_get_functiondef('$CAD'::regprocedure)) > 0 and position('pg_try_advisory_xact_lock' in pg_get_functiondef('$CAD'::regprocedure)) > 0")"

echo "── 6 · mutantes de la migración (deben ser rechazados)"
python3 - "$T" "$M" "$R2" <<'PY'
import sys
T,M,R=sys.argv[1:]
mig=open(M).read(); rev=open(R).read()
rev=rev.replace('begin;\n','',1); rev=rev[:rev.rindex('commit;')]
m=mig.replace("begin;\nset local lock_timeout = '5s';\n",'',1); m=m[:m.rindex('commit;')]
def mut(n,a,b):
    assert a in m, n
    open(f'{T}/mf-{n}.sql','w').write('begin;\n'+rev+'\n'+m.replace(a,b,1)+'\ncommit;\n')
mut('caducar-abierta','revoke all on function private.potencial_caducar(date, timestamptz, integer) from public, anon, authenticated, service_role;','')
mut('horario-una-pasada',"'10,40 10 * * *',","'10 10 * * *',")
mut('sin-lock-timeout',"set search_path = ''\nset lock_timeout = '10s'","set search_path = ''")
mut('regla-distinta',"when p_dias >= 5 and p_nivel = 'estrella'","when p_dias >= 6 and p_nivel = 'estrella'")
PY
for f in "$T"/mf-*.sql; do printf "  %-22s → %s\n" "$(basename "$f" .sql)" "$(rechazo "$f")"; done
echo "  job tras los mutantes: $(job)"

echo "── 7 · corrida real de pg_cron y medición del lote"
q "select cron.schedule('potencial-prueba-cron', '* * * * *', 'select private.potencial_caducar()');" >/dev/null
r=""
for _ in $(seq 1 30); do
  r=$(q "select d.status || ' | ' || coalesce(d.return_message,'') || ' | ' || d.username from cron.job_run_details d join cron.job j on j.jobid=d.jobid where j.jobname='potencial-prueba-cron' and d.status in ('succeeded','failed') order by d.start_time desc limit 1")
  [ -n "$r" ] && break
  sleep 5
done
q "select cron.unschedule('potencial-prueba-cron');" >/dev/null
echo "  pg_cron ejecutó la orden: ${r:-(no corrió en 150 s)}"
docker cp "$(dirname "$0")/medir-lote.sql" "$C:/tmp/medir.sql" >/dev/null
docker exec -e PGPASSWORD=postgres "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -f /tmp/medir.sql 2>&1 | grep -o "MEDICION.*\|ERROR.*" | sed 's/^/  /'

echo "── 8 · registro y verificación"
for i in 1 2; do echo "registrar #$i: $(docker exec -i -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt < "$P/registrar-caducidad.sql" 2>&1 | grep -o 'NOTICE:.*\|ERROR:.*' | head -1)"; done
echo "verificar:    $(docker exec -i -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -qAt < "$P/verificar-caducidad.sql" 2>&1 | grep -o 'VERIFICAR.*' | head -1)"
echo "FIN ciclo fase 2"
