#!/usr/bin/env bash
# Ciclo completo de la FASE 1 (20260930213647_crm_potencial_lead) en el BANCO Docker propio.
# Nunca contra producción. Deja el banco como lo encontró: fase 1 aplicada y registrada, y la
# fase 2 repuesta si estaba.
#
#   BANCO_CONTENEDOR=avancecorp-potencial-20260930 bash banco/ciclo-fase1.sh
#
# Qué corre:
#   1 · migración → repetida (se niega) → reversa → reversa repetida (se niega) → migración
#   2 · prueba-sintetica.sql
#   3 · mutantes de la MIGRACIÓN: reversa + migración alterada en una transacción (se deshace);
#       su pre/postflight debe rechazarlos
#   4 · mutantes de LÓGICA: la sintética con una función alterada dentro de su transacción; debe
#       reportar fallas. «gerencia-pasa» solo en el ayudante sobrevive A PROPÓSITO (la puerta
#       vuelve a exigir el rol); el mutante doble sí debe caer.
#   5 · prueba-concurrencia.sh y sus mutantes: puerta sin bloqueo, reversa sin candados y reversa
#       con el orden viejo de candados (los dos últimos BORRAN las tablas del banco: se reaplica)
#   6 · registrar ×2 y verificar
set -uo pipefail
C="${BANCO_CONTENEDOR:-avancecorp-potencial-20260930}"
D="$(cd "$(dirname "$0")/../../.." && pwd)"   # …/supabase
P="$D/scripts/potencial-lead"
M="$D/migrations/20260930213647_crm_potencial_lead.sql"
M2="$D/migrations/20260930235917_crm_potencial_lead_caducidad.sql"
R="$P/reversa.sql"; R2="$P/reversa-caducidad.sql"
PUERTA="crm.marcar_potencial_lead_fn(uuid,crm.nivel_potencial)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

q() { docker exec -i -e PGPASSWORD=postgres "$C" psql -U "${2:-postgres}" -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "$1" 2>&1; }
# Un archivo en UN mensaje (como `db query --file`): primer ERROR o último NOTICE.
msg() { local o; o=$(q "$(cat "$1")"); if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-130; else grep -o 'NOTICE:.*' <<<"$o" | tail -1 | cut -c1-130; fi; }
# Para mutantes: lo esperado es un ERROR.
rechazo() { local o; o=$(q "$(cat "$1")"); if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-110; else echo "SIN ERROR (¡el mutante pasó!)"; fi; }
sint() { docker cp "$1" "$C:/tmp/s.sql" >/dev/null; docker exec -e PGPASSWORD=postgres "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -f /tmp/s.sql 2>&1 | grep -o 'SINTETICA.*\|ERROR:  mutante.*\|ERROR:.*' | head -1 | cut -c1-300; }
conc() { BANCO_CONTENEDOR="$C" REVERSA_SQL="${1:-$R}" bash "$P/prueba-concurrencia.sh" 2>&1; }
# Restos del mundo de prueba-concurrencia.sh (un mutante que borra las tablas corta su limpieza).
IDS_U="'00000000-0000-4000-8000-00000000c0a1','00000000-0000-4000-8000-00000000c0a2','00000000-0000-4000-8000-00000000c0b1','00000000-0000-4000-8000-00000000c0b2'"
IDS_L="'00000000-0000-4000-8000-00000000c0c1','00000000-0000-4000-8000-00000000c0c9'"
limpiar_conc() { q "set session_replication_role = replica; do \$l\$ begin if to_regclass('crm.lead_potencial') is not null then delete from crm.lead_potencial_eventos where lead_id in ($IDS_L); delete from crm.lead_potencial where lead_id in ($IDS_L); end if; end \$l\$; delete from crm.leads where id in ($IDS_L); delete from crm.equipo where perfil_id in ($IDS_U); delete from public.perfiles where id in ($IDS_U); delete from auth.users where id in ($IDS_U); update crm.multiempresa_flags set activo = false where nombre = 'potencial_lead';" supabase_admin >/dev/null; }

f2=$(q "select (to_regprocedure('private.dias_lunes_a_sabado(date,date)') is not null)::int")
f1=$(q "select (to_regclass('crm.lead_potencial') is not null)::int")
limpiar_conc
[ "$f2" = "1" ] && echo "0 la fase 2 está aplicada; se retira para el ciclo y se repone al final: $(msg "$R2")"
[ "$f1" = "1" ] && echo "0 reversa del estado previo:  $(msg "$R")"

echo "── 1 · ciclo"
echo "1 migración:        $(msg "$M")"
echo "2 repetida:         $(msg "$M")"
echo "3 reversa:          $(msg "$R")"
echo "4 reversa repetida: $(msg "$R")"
echo "5 migración:        $(msg "$M")"
echo "── 2 · sintética"
echo "6 sintética:        $(sint "$P/prueba-sintetica.sql")"

echo "── 3 · mutantes de la migración (deben ser rechazados)"
python3 - "$T" "$M" "$R" <<'PY'
import sys
T,M,R=sys.argv[1:]
mig=open(M).read(); rev=open(R).read()
rev=rev.replace('begin;\n','',1); rev=rev[:rev.rindex('commit;')]
m=mig.replace("begin;\nset local lock_timeout = '5s';\n",'',1); m=m[:m.rindex('commit;')]
def mut(n,a,b):
    assert a in m, n
    open(f'{T}/mut-{n}.sql','w').write('begin;\n'+rev+'\n'+m.replace(a,b,1)+'\ncommit;\n')
SEQ='revoke all on sequence crm.lead_potencial_eventos_orden_seq from public, anon, authenticated, service_role;'
mut('privada-sin-revoke','revoke all on function private.potencial_rechazo(uuid, uuid) from public, anon, authenticated, service_role;\n','')
mut('grant-select',SEQ,SEQ+'\ngrant select on crm.lead_potencial to authenticated;')
mut('secuencia-abierta',SEQ,'grant usage on sequence crm.lead_potencial_eventos_orden_seq to authenticated;')
mut('policy-true','using (exists (select 1 from crm.leads l where l.id = lead_potencial.lead_id));','using (true);')
mut('inmutable-solo-update','create trigger lead_potencial_evento_inmutable before update or delete on crm.lead_potencial_eventos','create trigger lead_potencial_evento_inmutable before update on crm.lead_potencial_eventos')
mut('sin-truncate','''create trigger lead_potencial_evento_no_truncate before truncate on crm.lead_potencial_eventos
  for each statement execute function private.potencial_evento_inmutable();''','')
mut('puerta-invoker',"volatile\nsecurity definer\nset search_path = ''\nset lock_timeout = '5s'","volatile\nsecurity invoker\nset search_path = ''\nset lock_timeout = '5s'")
mut('bandera-encendida',"values ('potencial_lead', false,","values ('potencial_lead', true,")
open(f'{T}/mut-rol-alterado.sql','w').write('begin;\n'+rev+'''
do $x$ declare d text := pg_get_functiondef('private.rol_crm(uuid)'::regprocedure);
begin execute replace(d, 'select e.rol_crm', 'select /* mutante */ e.rol_crm'); end $x$;
'''+m+'\ncommit;\n')
PY
for f in "$T"/mut-*.sql; do printf "  %-24s → %s\n" "$(basename "$f" .sql)" "$(rechazo "$f")"; done
echo "  estado tras los mutantes (tablas/bandera/dueño): $(q "select (to_regclass('crm.lead_potencial') is not null)::text || '/' || (select activo::text from crm.multiempresa_flags where nombre='potencial_lead') || '/' || (select relowner::regrole::text from pg_class where oid='crm.lead_potencial'::regclass)")"

echo "── 4 · mutantes de lógica (la sintética debe reportar fallas)"
python3 - "$T" "$P/prueba-sintetica.sql" <<'PY'
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
    open(f'{T}/sint-{n}.sql','w').write(t.replace("begin;\n","begin;\n"+''.join(cuerpo(n,*p) for p in pares),1))
RECHAZO='private.potencial_rechazo(uuid,uuid)'; NUCLEO='private.potencial_marcar_nucleo(uuid,uuid,crm.nivel_potencial)'
PUERTA='crm.marcar_potencial_lead_fn(uuid,crm.nivel_potencial)'
ROL=(RECHAZO,"if (v_rol = 'vendedor' or v_rol = 'supervisor') is not true then","if (v_rol in ('vendedor','supervisor','gerencia')) is not true then")
mut('gerencia-pasa-solo-ayudante',ROL)
mut('gerencia-pasa-doble',ROL,(PUERTA,"in ('vendedor', 'supervisor')) is not true then","in ('vendedor', 'supervisor', 'gerencia')) is not true then"))
mut('cerrado-pasa',(RECHAZO,"if v_etapa is null or v_etapa in ('convertido', 'descartado') then","if false then"))
mut('parqueo-sin-rol',(RECHAZO,"else v_rol = 'supervisor' and v_supervisor in","else v_supervisor in"))
mut('token-null',(RECHAZO,"return 'ok';","return null;"))
mut('sin-antirrebote',(NUCLEO,"and v_actual.marcado_por = p_actor and v_actual.marcado_en > v_ahora - interval '60 seconds' then","and false then"))
mut('no-reinicia-reloj',(NUCLEO,"        marcado_en = excluded.marcado_en","        marcado_en = p.marcado_en"))
PY
for f in "$T"/sint-*.sql; do printf "  %-28s → %s\n" "$(basename "$f" .sql)" "$(sint "$f")"; done
echo "  (gerencia-pasa-solo-ayudante debe dar «de N OK»: la puerta exige el rol antes; es el doble candado)"

echo "── 5 · concurrencia"
conc | grep "✓\|✗\|CONCURRENCIA\|·"
echo "  mutante · puerta sin potencial_bloquear_lead (deben fallar A y B):"
q "select pg_get_functiondef('$PUERTA'::regprocedure)" > "$T/puerta-original.sql"
q "do \$x\$ declare d text := pg_get_functiondef('$PUERTA'::regprocedure); a text := 'if private.potencial_bloquear_lead(p_lead_id) is not true then'; begin if position(a in d) = 0 then raise exception 'no encontré el bloqueo'; end if; execute replace(d, a, 'if false then'); end \$x\$;" >/dev/null
conc | grep "✗\|CONCURRENCIA"
docker exec -i -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -q < "$T/puerta-original.sql" >/dev/null
echo "    puerta restaurada: $(q "select position('potencial_bloquear_lead' in pg_get_functiondef('$PUERTA'::regprocedure)) > 0")"
echo "  mutante · reversa sin candados (C debe fallar: borra la marca confirmada):"
sed -e '/^select 1 from crm.multiempresa_flags where nombre = .potencial_lead. for update;$/d' -e '/^lock table /d' "$R" > "$T/reversa-sin-candados.sql"
conc "$T/reversa-sin-candados.sql" | grep "✗\|CONCURRENCIA"
[ "$(q "select (to_regclass('crm.lead_potencial') is not null)::int")" = "1" ] || echo "    reaplicar tras el mutante: $(msg "$M")"
limpiar_conc
echo "  mutante · reversa con el orden viejo de candados (D debe fallar: deadlock):"
sed -e '/^lock table crm.leads, public.perfiles in access exclusive mode;$/d' "$R" > "$T/reversa-orden-viejo.sql"
conc "$T/reversa-orden-viejo.sql" | grep "✗\|CONCURRENCIA"
[ "$(q "select (to_regclass('crm.lead_potencial') is not null)::int")" = "1" ] || echo "    reaplicar tras el mutante: $(msg "$M")"
limpiar_conc

echo "── 6 · registro y verificación"
for i in 1 2; do echo "registrar #$i: $(docker exec -i -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt < "$P/registrar.sql" 2>&1 | grep -o 'NOTICE:.*\|ERROR:.*' | head -1)"; done
echo "verificar:    $(docker exec -i -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -qAt < "$P/verificar.sql" 2>&1 | grep -o 'VERIFICAR.*' | head -1)"
[ "$f2" = "1" ] && echo "fase 2 repuesta: $(msg "$M2")"
echo "FIN ciclo fase 1"
