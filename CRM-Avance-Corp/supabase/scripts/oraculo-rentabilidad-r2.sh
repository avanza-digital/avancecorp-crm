#!/usr/bin/env bash
# ORÁCULO RENTABILIDAD R2 (migración 20260906180000) — SOLO en el BANCO. Presupone R1 (20260906170000).
# Prueba el OBSERVADOR diferido de public.contratos (alta nuevo, renovación, upgrade inferido/ambiguo, corrección de tasa,
# UPDATE sin cambio de tasa) y la TARJETA crm.observacion_rentabilidad_fn (autoridad, periodo, cifras, sonda coherente).
# Sin R2 = MUTANTE: B..G ROJAS. Uso: S=/ruta/scratchpad ./oraculo-rentabilidad-r2.sh (lee $S/banco-pooler.txt).
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
RUN="${RUN:-$(date +%d%H%M)}"
AQUI="$(cd "$(dirname "$0")" && pwd)"
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'; SUP='f3000000-0000-0000-0000-000000000003'
V2='f3000000-0000-0000-0000-000000000004'
PA="f3a00000-0000-0000-0000-${RUN}000001"   # cliente de V (siembra f3)
PB="f3b00000-0000-0000-0000-${RUN}000002"   # cliente de V2 (esta corrida), tendrá UN solo contrato activo
SUP2="f3c00000-0000-0000-0000-${RUN}000003"
ROJO=0; VERDE=0
ok()   { echo "  ✅ $*"; VERDE=$((VERDE+1)); }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; set local role authenticated; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
run_anon() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set local role authenticated; select set_config('request.jwt.claims', '{\"role\":\"authenticated\"}', true); $1; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
sys()  { psql "$PG" -q -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; select set_config('crm.op_privilegiada','on',true); $1; commit;" 2>&1 | grep -E "ERROR|WARNING"; }
j()    { python3 -c "
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]) if lines else {}
for k in sys.argv[2].split('.'):
    d=d.get(k) if isinstance(d,dict) else None
print('' if d is None else (json.dumps(d) if isinstance(d,(dict,list)) else (('%f' % d).rstrip('0').rstrip('.') if isinstance(d,(int,float)) and not isinstance(d,bool) else d)))" "$1" "$2" 2>/dev/null; }
code() { echo "$1" | grep -oE "ERROR:  [0-9A-Z]{5}" | head -1 | awk '{print $2}'; }
espera() { local c; c="$(code "$1")"; if [[ "$c" == "$2" ]] && echo "$1" | grep -qiE "$3"; then ok "$4 → $2"; else rojo "$4: esperaba $2 /$3/, salió: $(echo "$1" | tr '\n' ' ' | cut -c1-220)"; fi; }
N_ALTA=0
# alta <actor> <cliente> <numero> <tasa> [capital] [categoria=nuevo] [extra_json] [fi] [fv] [cuota] [retorno]
alta() {
  N_ALTA=$((N_ALTA+1)); local cap="${5:-20000}"; local cat="${6:-nuevo}"; local extra="${7:-}"; local fi="${8:-2026-03-11}"; local fv="${9:-2027-03-11}"; local fc="${10:-2026-04-11}"
  local cci; cci="$(printf '002%s%011d' "$RUN" "$N_ALTA")"
  run_as "$1" "select crm.crear_contrato_con_cuenta_pdf_v2(
    jsonb_build_object('cliente_id','$2','numero_contrato','$3','capital',$cap,'moneda','PEN','tasa_anual',$4,
      'modalidad','mensual','tipo_interes','simple','categoria','$cat','fecha_inicio','$fi','fecha_vencimiento','$fv',
      'notas_internas','oraculo rentabilidad r2 r$RUN' $extra),
    jsonb_build_array(
      jsonb_build_object('numero_cuota',1,'fecha_programada','$fc','monto_programado',250,'tipo','cuota'),
      jsonb_build_object('numero_cuota',2,'fecha_programada','$fv','monto_programado',$cap,'tipo','retorno')),
    jsonb_build_object('tipo','nueva','banco','BCP','tipo_cuenta','ahorros','numero_cuenta','R2$RUN$N_ALTA','cci','$cci',
      'titular_distinto',false,'beneficiario_nombre',null,'beneficiario_dni',null))"
}
obs() { q "select coalesce(regla,'-')||'|'||coalesce(round(tasa_base,2)::text,'-')||'|'||coalesce(round(tasa_final,2)::text,'-')||'|'||coalesce(round(tasa_recibida,2)::text,'-')||'|'||divergente||'|'||coalesce(contrato_origen_id::text,'-')||'|'||coalesce(detalle->>'motivo','-')||'|'||coalesce(detalle->>'operacion','-')||'|'||coalesce(detalle->>'base_conservada','-') from crm.ledger_rentabilidad where contrato_id='$1' and origen='observacion' order by registrado_en desc limit 1"; }
n_obs() { q "select count(*) from crm.ledger_rentabilidad where contrato_id='$1' and origen='observacion'"; }
tarjeta() { run_as "$1" "select crm.observacion_rentabilidad_fn(${2:-null},${3:-null})"; }
GATES_OK="0fd6fa8d1d8f8106cb52662cb64193e0 85614480d6c8939e818342ef3fe63c65 7f2b4976640553a50ab27cf25b30fb36 061c40e345312ca5e515ddd5ee282e5c db2e6d36d46c72250fd6f42022af80be"
GATES_D19="0fd6fa8d1d8f8106cb52662cb64193e0 85614480d6c8939e818342ef3fe63c65 0de7a130ae366cde54035e2c50f213e2 4bf2f691888bee4d3198cccba8acd396 db2e6d36d46c72250fd6f42022af80be"
GATES_R4="a363ad7e514c8eef3257acd7a1a54d44 85614480d6c8939e818342ef3fe63c65 0de7a130ae366cde54035e2c50f213e2 4bf2f691888bee4d3198cccba8acd396 db2e6d36d46c72250fd6f42022af80be"   # con RENTABILIDAD R4 (la puerta del alta declara el origen del upgrade)   # con F2.b D-19 aplicada (banco)
gates() { q "select string_agg(h, ' ' order by o) from (select case p.proname when 'crear_contrato_con_cuenta_pdf_v2' then 1 when 'actualizar_contrato_con_cuenta_pdf_v3' then 2 when 'crear_contrato_con_cuenta' then 3 when 'crear_contrato' then 4 else 5 end o, md5(p.prosrc) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='crm' and p.proname in ('crear_contrato_con_cuenta_pdf_v2','actualizar_contrato_con_cuenta_pdf_v3','crear_contrato_con_cuenta')) or (n.nspname='public' and p.proname in ('crear_contrato','actualizar_contrato'))) x"; }

echo "== Preflight (RUN=$RUN) =="
FLAG_RP="$(q "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'")"; FLAG_IE="$(q "select activo from crm.multiempresa_flags where nombre='inversiones_escritura'")"
restaurar() { psql "$PG" -q -c "update crm.multiempresa_flags set activo='${FLAG_RP:-f}' where nombre='resolver_en_puertas'; update crm.multiempresa_flags set activo='${FLAG_IE:-f}' where nombre='inversiones_escritura';" >/dev/null; }
trap restaurar EXIT
psql "$PG" -q -c "update crm.multiempresa_flags set activo=false where nombre in ('resolver_en_puertas','inversiones_escritura');" >/dev/null
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
INST="$(q "select (to_regprocedure('crm.observacion_rentabilidad_fn(date,date)') is not null)")"
if [[ "$INST" == "t" ]]; then echo "  R2 instalada (todo debe salir VERDE)"; else echo "  ⚠️ R2 NO instalada: corrida MUTANTE (B..G deben salir ROJAS)"; fi
[[ "$(q "select (to_regclass('crm.ledger_rentabilidad') is not null)")" == "t" ]] && ok "premisa: R1 instalada" || rojo "falta R1"
# Huecos que el banco YA traía: altas sin su observación de INSERT anteriores a esta corrida. La tarjeta las cuenta y
# no se pueden borrar (un contrato con operaciones de cartera no se marca como prueba, y el ledger es append-only), así
# que la aserción de abajo es «esta corrida no añade huecos nuevos», que es lo que de verdad se está probando.
HUECOS_INI="$(q "select count(*) from public.contratos c
  where not c.es_demo
    and c.creado_en >= (select (valor->>'en')::timestamptz from crm.rentabilidad_hitos where clave='observacion_activa_desde')
    and not exists (select 1 from crm.ledger_rentabilidad l where l.contrato_id = c.id and l.origen in ('observacion','enforcement') and l.detalle ->> 'evento' = 'INSERT')")"
[[ "${HUECOS_INI:-0}" == "0" ]] || echo "  ⚠️ el banco ya traía $HUECOS_INI alta(s) sin observar antes de empezar (contaminación previa; la tarjeta las contará)"
GATES_INI="$(gates)"; [[ "$GATES_INI" == "$GATES_OK" || "$GATES_INI" == "$GATES_D19" || "$GATES_INI" == "$GATES_R4" ]] && ok "premisa: las 5 puertas de escritura llevan un texto conocido (prod 06/09, D-19 o R4)" || rojo "puertas con otro texto: $GATES_INI"
sys "insert into auth.users (id) values ('$SUP2'), ('$PB') on conflict (id) do nothing;
     insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni) values ('$SUP2','R2 SUPERVISOR DOS r$RUN','comercial','DNI','8${RUN}3') on conflict (id) do update set activo = true;
     insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo, creado_por) values ('$SUP2','supervisor',null,true,'$G') on conflict (perfil_id) do update set activo=true, rol_crm='supervisor', supervisor_id=null;
     update public.perfiles set activo=true where id='$V2';
     update crm.equipo set activo=true, supervisor_id='$SUP2', rol_crm='vendedor' where perfil_id='$V2';
     insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, asesor_perfil_id) values ('$PB','R2 CLIENTE DE V2 r$RUN','cliente','DNI','7${RUN}5','$V2') on conflict (id) do nothing;"
[[ "$(q "select count(*) from public.perfiles where id='$PB' and rol='cliente' and activo and asesor_perfil_id='$V2'")" == "1" ]] && ok "fixture: PB cliente de V2 (sin contratos)" || rojo "fixture PB"
LEDGER_ANTES="$(q "select count(*) from crm.ledger_rentabilidad")"
BASE="$(q "select round(tasa_base_nueva,2) from (select * from crm.politica_rentabilidad order by vigente_desde desc, version desc limit 1) p")"; [[ -z "$BASE" ]] && BASE="(sin política)"
echo "  política vigente: base $BASE"

echo "== B) Alta NUEVA: el observador anota base vs recibida =="
O="$(alta "$V" "$PA" "R2-$RUN-N12" 12)"; N12="$(j "$O" id)"; [[ -n "$N12" ]] && ok "alta al 12% entra (nada bloquea)" || rojo "alta 12: ${O:0:200}"
[[ "$(n_obs "$N12")" == "1" ]] && ok "una observación para el alta" || rojo "observaciones: $(n_obs "$N12")"
[[ "$(obs "$N12")" == "primera_inversion|$BASE|12.00|12.00|true|-|-|INSERT|-" ]] && ok "primera_inversion · base $BASE · final 12 · DIVERGENTE · INSERT" || rojo "obs N12: $(obs "$N12")"
[[ "$(q "select detalle->>'capital'||'|'||(detalle->>'moneda')||'|'||(detalle->>'plazo_dias')||'|'||(detalle->>'es_demo')||'|'||coalesce(detalle->>'analista_cierre_id',detalle->>'creado_por') from crm.ledger_rentabilidad where contrato_id='$N12' and origen='observacion'")" == "20000.00|PEN|365|false|$V" ]] && ok "detalle: capital 20000 · PEN · plazo 365 · no demo · analista V" || rojo "detalle N12: $(q "select detalle from crm.ledger_rentabilidad where contrato_id='$N12' and origen='observacion'" | cut -c1-300)"
[[ "$(q "select actor_id from crm.ledger_rentabilidad where contrato_id='$N12' and origen='observacion'")" == "$V" ]] && ok "actor_id = quien digitó (V)" || rojo "actor_id distinto"
O="$(alta "$V" "$PA" "R2-$RUN-N15" 15)"; N15="$(j "$O" id)"
[[ -n "$N15" && "$(obs "$N15")" == "primera_inversion|$BASE|15.00|15.00|false|-|-|INSERT|-" ]] && ok "alta al 15% → observada, NO divergente" || rojo "obs N15: $(obs "$N15")"
[[ "$(q "select (detalle->'resolucion'->>'contratos_previos')::int from crm.ledger_rentabilidad where contrato_id='$N15' and origen='observacion'")" == "1" ]] && ok "contratos_previos excluye al propio contrato (PA tenía 1: N12)" || rojo "previos: $(q "select detalle->'resolucion'->>'contratos_previos' from crm.ledger_rentabilidad where contrato_id='$N15' and origen='observacion'")"

echo "== C) RENOVACIÓN: hereda del origen aunque al commit ya esté «renovado» =="
O="$(alta "$V" "$PA" "R2-$RUN-ORI" 15 20000 nuevo "" 2025-03-11 2026-03-11 2025-04-11)"; ORI="$(j "$O" id)"; [[ -n "$ORI" ]] && ok "origen ORI (15%, vence 2026-03-11) creado" || rojo "ORI: ${O:0:200}"
O="$(alta "$V" "$PA" "R2-$RUN-REN" 18 20000 renovacion ",'contrato_origen_id','$ORI','capital_renovado',20000,'capital_adicional',0" 2026-03-11 2027-03-11 2026-04-11)"; REN="$(j "$O" id)"
[[ -n "$REN" ]] && ok "renovación REN al 18% entra" || rojo "REN: ${O:0:220}"
[[ "$(q "select estado||'|'||coalesce(renovado_a_id::text,'-') from public.contratos where id='$ORI'")" == "renovado|$REN" ]] && ok "la puerta cerró ORI como renovado → REN (al commit el origen ya está cerrado)" || rojo "ORI: $(q "select estado, renovado_a_id from public.contratos where id='$ORI'")"
[[ "$(obs "$REN")" == "heredada_renovacion|15.00|18.00|18.00|true|$ORI|-|INSERT|-" ]] && ok "REN observada: heredada_renovacion · base 15 (del origen) · final 18 · DIVERGENTE · origen ORI (la sobrecarga de 5 args acepta el origen ya renovado POR REN)" || rojo "obs REN: $(obs "$REN")"

echo "== D) UPGRADE: origen inferido si es único, sin_regla si es ambiguo =="
O="$(alta "$V2" "$PB" "R2-$RUN-PB1" 12)"; PB1="$(j "$O" id)"; [[ -n "$PB1" ]] && ok "PB tiene UN contrato activo (PB1 al 12%)" || rojo "PB1: ${O:0:200}"
O="$(alta "$V2" "$PB" "R2-$RUN-UPG" 12 30000 upgrade "" 2026-06-01 2027-06-01 2026-07-01)"; UPG="$(j "$O" id)"
[[ -n "$UPG" ]] && ok "upgrade UPG de PB entra" || rojo "UPG: ${O:0:220}"
[[ "$(obs "$UPG")" == "sin_regla|12.00|12.00|12.00|false|-|upgrade_origen_inferido|INSERT|-" ]] && ok "UPG observado: sin_regla · motivo upgrade_origen_inferido (D2: una inferencia no es una regla) · sin origen anotado" || rojo "obs UPG: $(obs "$UPG")"
[[ "$(q "select detalle->'candidato_origen'->>'id' from crm.ledger_rentabilidad where contrato_id='$UPG' and origen='observacion'")" == "$PB1" ]] && ok "…pero el detalle guarda el CANDIDATO único (PB1) para R3" || rojo "sin candidato en detalle"
O="$(alta "$V" "$PA" "R2-$RUN-UPA" 16 30000 upgrade "" 2026-06-01 2027-06-01 2026-07-01)"; UPA="$(j "$O" id)"
[[ -n "$UPA" ]] && ok "upgrade UPA de PA entra (PA tiene varios activos)" || rojo "UPA: ${O:0:220}"
[[ "$(obs "$UPA")" == "sin_regla|16.00|16.00|16.00|false|-|upgrade_origen_ambiguo|INSERT|-" ]] && ok "UPA observado: sin_regla · motivo upgrade_origen_ambiguo · base = recibida (no se inventa)" || rojo "obs UPA: $(obs "$UPA")"

echo "== E) CORRECCIÓN de tasa: UPDATE OF tasa_anual observado; UPDATE sin cambio de tasa, no =="
E="$(sys "update public.contratos set tasa_anual = 13 where id='$N12'")"
if [[ -z "$E" ]]; then
  [[ "$(n_obs "$N12")" == "2" && "$(obs "$N12")" == "primera_inversion|$BASE|13.00|13.00|true|-|-|UPDATE|true" ]] && ok "corrección 12 → 13 observada como UPDATE (segunda fila; la del alta no cambia)" || rojo "obs corrección: n=$(n_obs "$N12") $(obs "$N12")"
  [[ "$(q "select detalle->>'tasa_anterior' from crm.ledger_rentabilidad where contrato_id='$N12' and detalle->>'operacion'='UPDATE'")" == "12.00" ]] && ok "detalle.tasa_anterior = 12" || rojo "sin tasa_anterior"
else
  echo "  ⚠️ (el banco no dejó corregir la tasa directamente: ${E:0:140}; se prueba por la puerta del portal)"
  O="$(run_as "$V" "select public.actualizar_contrato('$N12', (select to_jsonb(c) - 'id' || jsonb_build_object('tasa_anual',13) from public.contratos c where c.id='$N12'), (select jsonb_agg(to_jsonb(p)) from public.cronograma_pagos p where p.contrato_id='$N12'))")"
  [[ "$(n_obs "$N12")" == "2" && "$(obs "$N12")" == "primera_inversion|$BASE|13.00|13.00|true|-|-|UPDATE|true" ]] && ok "corrección 12 → 13 por public.actualizar_contrato observada como UPDATE" || rojo "corrección por puerta: $(echo "$O" | tr '\n' ' ' | cut -c1-200) · n=$(n_obs "$N12") $(obs "$N12")"
fi
E="$(sys "update public.contratos set notas_internas = 'r2 sin tocar tasa' where id='$N15'")"
[[ -z "$E" && "$(n_obs "$N15")" == "1" ]] && ok "UPDATE que no toca la tasa → ninguna observación nueva" || rojo "UPDATE sin tasa: n=$(n_obs "$N15") $E"
E="$(sys "update public.contratos set tasa_anual = tasa_anual where id='$N15'")"
[[ -z "$E" && "$(n_obs "$N15")" == "1" ]] && ok "UPDATE OF tasa_anual con el MISMO valor → ninguna observación nueva" || rojo "UPDATE mismo valor: n=$(n_obs "$N15") $E"
E="$(sys "update public.contratos set tasa_anual = 13.5 where id='$N15'; update public.contratos set tasa_anual = 14 where id='$N15'")"
[[ -z "$E" && "$(n_obs "$N15")" == "2" && "$(obs "$N15")" == "primera_inversion|$BASE|14.00|14.00|true|-|-|UPDATE|true" ]] && ok "DOS correcciones en la MISMA transacción → UNA sola observación con el estado FINAL (14), base conservada" || rojo "multi-tx: n=$(n_obs "$N15") $(obs "$N15") $E"
[[ "$(q "select detalle->>'tasa_anterior' from crm.ledger_rentabilidad where contrato_id='$N15' and detalle->>'operacion'='UPDATE'")" == "15.00" ]] && ok "tasa_anterior = 15 (la imagen previa al primer evento)" || rojo "tasa_anterior: $(q "select detalle->>'tasa_anterior' from crm.ledger_rentabilidad where contrato_id='$N15' and detalle->>'operacion'='UPDATE'")"
E="$(sys "update public.contratos set tasa_anual = 18 where id='$N15'; update public.contratos set tasa_anual = 14 where id='$N15'")"
[[ -z "$E" && "$(n_obs "$N15")" == "2" ]] && ok "14 → 18 → 14 en la MISMA transacción (cambio neto vacío) → NO es una corrección: ninguna observación nueva (Codex #25)" || rojo "cambio neto vacío: n=$(n_obs "$N15") $E"
E="$(sys "update public.contratos set categoria = 'upgrade' where id='$N12'")"
if [[ -z "$E" ]]; then
  [[ "$(n_obs "$N12")" == "3" && "$(obs "$N12")" == "sin_regla|13.00|13.00|13.00|false|-|upgrade_sin_contrato_activo_previo|UPDATE|-" ]] && ok "cambio de CATEGORÍA con la misma tasa → observado y resuelto de nuevo (N12 fue el primer contrato de PA: upgrade sin activo previo) y detalle.cambios lo anota" || rojo "cambio categoría: n=$(n_obs "$N12") $(obs "$N12")"
  [[ "$(q "select detalle->'cambios'->'categoria'->>1 from crm.ledger_rentabilidad where contrato_id='$N12' and origen='observacion' order by registrado_en desc limit 1")" == "upgrade" ]] && ok "detalle.cambios.categoria = [nuevo, upgrade]" || rojo "sin cambios en detalle"
  E="$(sys "update public.contratos set capital = 21000 where id='$N12'")"
  [[ -z "$E" && "$(n_obs "$N12")" == "4" && "$(obs "$N12")" == "sin_regla|13.00|13.00|13.00|false|-|upgrade_sin_contrato_activo_previo|UPDATE|true" ]] && ok "cambio de capital tras pasar a upgrade → NO resucita primera_inversion del alta: conserva la INCERTIDUMBRE (sin_regla, mismo motivo) de la categoría vigente (Codex #20/#8)" || rojo "resucitó la regla: n=$(n_obs "$N12") $(obs "$N12")"
else
  echo "  ⚠️ (el banco no dejó cambiar la categoría directamente: ${E:0:120})"
fi
E="$(sys "update public.contratos set capital = 25000 where id='$REN'")"
if [[ -z "$E" ]]; then
  [[ "$(n_obs "$REN")" == "2" && "$(obs "$REN")" == "heredada_renovacion|15.00|18.00|18.00|true|$ORI|-|UPDATE|true" ]] && ok "cambio de CAPITAL (mismo cliente/categoría) → observado conservando base 15, regla y origen del alta" || rojo "cambio capital REN: n=$(n_obs "$REN") $(obs "$REN")"
  [[ "$(q "select (l2.politica_id = l1.politica_id) and l2.detalle ? 'observacion_base_id' from crm.ledger_rentabilidad l1 join crm.ledger_rentabilidad l2 on l2.contrato_id=l1.contrato_id and l2.detalle->>'operacion'='UPDATE' where l1.contrato_id='$REN' and l1.detalle->>'operacion'='INSERT'")" == "t" ]] && ok "la corrección arrastra la política de la resolución original y enlaza la observación base (Codex #21)" || rojo "política/enlace de la corrección"
else
  echo "  ⚠️ (el banco no dejó cambiar el capital directamente: ${E:0:120})"
fi

echo "== F) La TARJETA de Gerencia =="
espera "$(tarjeta "$V")" 42501 "No autorizado" "el analista no lee la tarjeta"
espera "$(tarjeta "$SUP")" 42501 "No autorizado" "el supervisor tampoco"
espera "$(run_anon "select crm.observacion_rentabilidad_fn(null,null)")" 42501 "No autorizado" "sin sesión"
espera "$(tarjeta "$G" "'2026-09-10'" "'2026-09-01'")" 22023 "Periodo" "desde > hasta → 22023"
espera "$(tarjeta "$G" "'2025-01-01'" "'2026-09-01'")" 22023 "Periodo" "rango > 366 días → 22023"
T="$(tarjeta "$G")"
COH_ESP="$([[ "${HUECOS_INI:-0}" == "0" ]] && echo True || echo False)"
[[ "$(j "$T" version)" == "1" && "$(j "$T" coherente)" == "$COH_ESP" && "$(j "$T" sondas.consistencia_interna)" == "True" && "$(j "$T" sondas.cobertura_altas)" == "$COH_ESP" && "$(j "$T" sondas.cobertura_correcciones)" == "desconocida" ]] && ok "Gerencia lee la tarjeta (v1): coherente, consistencia_interna, cobertura_altas (0 huecos desde el hito), cobertura_correcciones=desconocida" || rojo "tarjeta: $(echo "$T" | cut -c1-400)"
[[ "$(j "$T" altas_sin_observar)" == "${HUECOS_INI:-0}" && -n "$(j "$T" cobertura.observacion_activa_desde)" ]] && ok "las altas anteriores a la activación (R1, hoy mismo) NO cuentan como huecos, y esta corrida no añade ninguno (${HUECOS_INI:-0} previos)" || rojo "huecos: $(j "$T" altas_sin_observar) (esperaba ${HUECOS_INI:-0}) act=$(j "$T" cobertura.observacion_activa_desde)"
[[ "$(j "$T" metodo)" == "simple_sobre_plazo_revision_efectiva" ]] && ok "método declarado" || rojo "método: $(j "$T" metodo)"
[[ "$(j "$T" politica.modo)" == "observacion" ]] && ok "trae la política vigente (observación)" || rojo "sin política"
OBS="$(j "$T" totales.contratos)"; EV="$(j "$T" totales.eventos)"; DIV="$(j "$T" totales.divergentes)"; SR="$(j "$T" totales.sin_regla)"; CORR="$(j "$T" totales.correcciones)"
[[ "$OBS" -ge 7 && "$EV" -gt "$OBS" && "$DIV" -ge 3 && "$SR" -ge 2 && "$CORR" -ge 3 ]] && ok "totales: contratos=$OBS eventos=$EV (> contratos: las correcciones no duplican contratos) divergentes=$DIV sin_regla=$SR correcciones=$CORR" || rojo "totales: contratos=$OBS eventos=$EV div=$DIV sr=$SR corr=$CORR"
# margen cedido de REN: 20000 × 3/100 × 365/365 = 600 PEN; entra en el total PEN del periodo
CED="$(j "$T" totales.cedido.PEN)"; python3 -c "import sys; sys.exit(0 if float('$CED' or 0) >= 750 else 1)" && ok "cedido PEN del periodo ≥ 750 (REN con su revisión efectiva)" || rojo "cedido PEN=$CED"
echo "$T" | grep -q '"motivo": "upgrade_origen_ambiguo"' && echo "$T" | grep -q '"motivo": "upgrade_origen_inferido"' && ok "casos sin regla: aparecen upgrade_origen_ambiguo y upgrade_origen_inferido" || rojo "faltan motivos de upgrade"
echo "$T" | grep -q "R2-$RUN-REN" && ok "últimos divergentes: aparece REN con su número" || rojo "REN no aparece en últimos divergentes"
python3 - "$T" "R2-$RUN-N15" <<'PY' && ok "revisión efectiva: N15 (corregido 15→13.5→14) aparece UNA vez en últimos divergentes, con tasa final 14 y cedido = 20000×(14−15)… no: retiene (puntos −1) → no está en cedidos; su fila única lleva puntos −1" || rojo "N15 duplicado o con puntos incorrectos en últimos divergentes"
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]); u=[x for x in d['ultimos_divergentes'] if x['numero_contrato']==sys.argv[2]]
assert len(u)==1, u
assert float(u[0]['tasa_final'])==14 and float(u[0]['puntos'])==-1 and u[0]['cedido'] is None, u[0]
PY
python3 - "$T" "R2-$RUN-REN" <<'PY' && ok "REN corregido de capital (20000→25000) cuenta UNA vez con su revisión efectiva: cedido = 25000×3%×365/365 = 750" || rojo "REN: cedido no es 750 o está duplicado"
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]); u=[x for x in d['ultimos_divergentes'] if x['numero_contrato']==sys.argv[2]]
assert len(u)==1 and abs(float(u[0]['cedido'])-750)<0.01, u
PY
python3 - "$T" "$V" <<'PY' && ok "por_analista: V figura con divergentes, cedido_pen y retenido_pen > 0; contratos e importes cuadran con el total por regla y por analista" || rojo "por_analista no cuadra"
import sys,json
lines=[l for l in sys.argv[1].splitlines() if l.strip().startswith('{')]
d=json.loads(lines[-1]); tot=d['totales']; pa=d['por_analista']; pr=d['por_regla']
v=[a for a in pa if a['analista_id']==sys.argv[2]]
assert v and v[0]['divergentes']>=2 and float(v[0]['cedido_pen'])>0 and float(v[0]['retenido_pen'])>0, v
assert sum(a['contratos'] for a in pa)==tot['contratos']==sum(r['contratos'] for r in pr)
assert abs(sum(float(a['cedido_pen']) for a in pa)-float(tot['cedido']['PEN']))<0.01 and abs(sum(float(r['cedido_pen']) for r in pr)-float(tot['cedido']['PEN']))<0.01
assert tot['divergentes']==tot['ceden']+tot['retienen']
PY
# Demo posterior: marcar N12 como demo DESPUÉS del alta debe sacarlo de la tarjeta (marca autoritativa = la del contrato hoy)
ANTES_CONTRATOS="$OBS"
O="$(run_as "$G" "select public.marcar_contrato_demo('$N12', true, 'oraculo r2: demo posterior al alta')")"
if ! echo "$O" | grep -q "ERROR"; then
  T3="$(tarjeta "$G")"
  [[ "$(j "$T3" totales.contratos)" == "$((OBS-1))" ]] && ok "N12 marcado demo tras el alta (por su puerta, Gerencia) → la tarjeta lo excluye (contratos $OBS → $((OBS-1)))" || rojo "demo posterior: contratos=$(j "$T3" totales.contratos) (esperaba $((OBS-1)))"
  run_as "$G" "select public.marcar_contrato_demo('$N12', false, 'oraculo r2: deshacer')" >/dev/null
else
  rojo "marcar demo por la puerta falló: $(echo "$O" | tr '\n' ' ' | cut -c1-200)"
fi
T2="$(tarjeta "$G" "'2026-01-01'" "'2026-01-31'")"
[[ "$(j "$T2" totales.contratos)" == "0" && "$(j "$T2" coherente)" == "True" && "$(j "$T2" cobertura.periodo_sin_cobertura)" == "True" ]] && ok "un periodo anterior a la activación devuelve 0 coherente y declara periodo_sin_cobertura" || rojo "periodo vacío: $(echo "$T2" | cut -c1-260)"
espera "$(tarjeta "$G" "'2026-09-01'" "'2099-01-01'")" 22023 "Periodo" "hasta en el futuro → 22023"
# La condición de renovación con NULL (Codex #3): un origen RETIRADO con renovado_a_id NULL no pasa aunque se informe p_contrato_nuevo_id
sys "update public.contratos set estado = 'retirado' where id='$PB1'"
if [[ "$(q "select estado from public.contratos where id='$PB1'")" == "retirado" ]]; then
  espera "$(psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "select private.resolver_tasa('$PB','renovacion','$PB1',now(),'$UPG')" 2>&1)" P0409 "cerrado o renovado" "núcleo 5 args: origen RETIRADO (renovado_a_id NULL) → P0409, no hereda"
else
  echo "  ⚠️ (el banco no dejó retirar PB1 a mano; se omite la prueba del NULL)"
fi

echo "== G) Nada cambió en las puertas; el ledger legacy no se tocó =="
[[ "$(gates)" == "$GATES_INI" ]] && ok "las 5 puertas de escritura siguen byte a byte (como al empezar)" || rojo "puertas cambiadas: $(gates)"
[[ "$(q "select count(*) from crm.ledger_rentabilidad where origen='backfill_legacy' and registrado_en > now() - interval '1 hour'")" == "0" ]] && ok "ninguna fila legacy nueva" || rojo "legacy tocado"
CREC=$(( $(q "select count(*) from crm.ledger_rentabilidad") - LEDGER_ANTES ))
# Con R4 el trigger vigila además modalidad, tipo de interés, producto y la marca de prueba: marcar un contrato como
# de ensayo, o cambiarle la modalidad, deja su propia fila. El rango cubre las dos formas (con y sin R4).
[[ "$CREC" -ge 9 && "$CREC" -le 16 ]] && ok "el ledger creció en $CREC observaciones (7 altas + correcciones observadas: tasa, multi-tx=1, categoría, capital, y con R4 también marca de prueba y modalidad)" || rojo "ledger creció en $CREC (esperaba 9..11)"

echo; echo "== RESULTADO RUN=$RUN: $VERDE verdes, $ROJO rojos =="
exit $(( ROJO > 0 ))
