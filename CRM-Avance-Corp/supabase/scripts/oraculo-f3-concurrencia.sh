#!/usr/bin/env bash
# ORÁCULO DEL LOTE Contrato-F2 (la «F3» del plan) — SOLO en el BANCO.
# Prueba LOS 5 INVARIANTES DE LA META «bajo concurrencia real» ejercitando LAS
# PUERTAS (convertir_lead / convertir_lead_externo / marcar-levantar no_contactar),
# NO el trigger superseded. Cada sesión corre en UNA transacción (begin…commit en
# un solo -c) para que los claims sobrevivan — el fallo del arnés anterior era
# `psql -c` autocommit entre sentencias (Codex #9).
# Uso: S=/ruta/scratchpad ./oraculo-f3-concurrencia.sh   (lee $S/banco-pooler.txt)
# Presupone: banco con F1 + backfill + lote (190000..260000) y siembra-banco-f3.sql.
set -uo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
# Cada corrida vive en su espacio (RUN de 4 dígitos): sin borrar nada, sin desmontar candados.
RUN="${RUN:-$(date +%d%H%M)}"   # 6 dígitos: día+hora+minuto
V='f3000000-0000-0000-0000-000000000001'; G='f3000000-0000-0000-0000-000000000002'
PA="f3a00000-0000-0000-0000-${RUN}000001"
L1="f31ead00-0000-0000-0000-${RUN}000001"; L2="f31ead00-0000-0000-0000-${RUN}000002"
L3="f31ead00-0000-0000-0000-${RUN}000003"; L4="f31ead00-0000-0000-0000-${RUN}000004"
L5="f31ead00-0000-0000-0000-${RUN}000005"; L6="f31ead00-0000-0000-0000-${RUN}000006"
DOC="7${RUN}1"; DOC5="7${RUN}3"; DOC4="7${RUN}4"; T="9${RUN}"; ROJO=0
AQUI="$(cd "$(dirname "$0")" && pwd)"
ok()   { echo "  ✅ $*"; }
rojo() { echo "  ❌ $*" >&2; ROJO=$((ROJO+1)); }
run_as() { psql "$PG" -qtA -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set timezone='America/Lima'; select set_config('request.jwt.claims', '{\"sub\":\"$1\",\"role\":\"authenticated\"}', true); $2; commit;" 2>&1; }
q()    { psql "$PG" -qtA -c "set timezone='America/Lima';" -c "$1" 2>/dev/null; }
flag() { psql "$PG" -q -c "update crm.multiempresa_flags set activo=$1, actualizado_en=now() where nombre='resolver_en_puertas';" >/dev/null; }
coop() { echo "select crm.convertir_lead_externo('$1','qorilazo',1000,'PEN','DNI','$DOC','F3 PERSONA UNO','TRX-F3-${RUN}-$2')"; }

echo "== Preflight (RUN=$RUN) =="
psql "$PG" -q -v ON_ERROR_STOP=1 -v run="$RUN" -c "set timezone='America/Lima';" -f "$AQUI/siembra-banco-f3.sql" 2>&1 | grep -E "SIEMBRA-F3-OK|ERROR" | head -2
[[ "$(q "select count(*) from crm.leads where id::text like 'f31ead00-0000-0000-0000-${RUN}%'")" == "5" ]] || { echo "La siembra del RUN $RUN no dejó 5 leads" >&2; exit 2; }
flag true
[[ "$(q "select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'")" == "t" ]] && ok "bandera ENCENDIDA para el ensayo" || rojo "no se pudo encender la bandera"

echo "== #1 Dos conversiones SIMULTÁNEAS del MISMO documento (leads distintos, coop) =="
run_as "$V" "$(coop "$L1" A)" > "$S/f3_race_a.out" & pa=$!
run_as "$V" "$(coop "$L2" B)" > "$S/f3_race_b.out" & pb=$!
wait "$pa"; ra=$?; wait "$pb"; rb=$?
A="$(cat "$S/f3_race_a.out")"; B="$(cat "$S/f3_race_b.out")"
echo "   A(L1) exit=$ra :: $(echo "$A"|tail -1|cut -c1-110)"; echo "   B(L2) exit=$rb :: $(echo "$B"|tail -1|cut -c1-110)"
echo "$A$B" | grep -qi deadlock && rojo "DEADLOCK entre las dos conversiones"
exitos=$(( (ra==0) + (rb==0) )); p0409=$(echo "$A$B" | grep -c "ya tiene un lead" || true)
[[ "$exitos" == "1" ]] && ok "exactamente UNA conversión ganó" || rojo "esperaba 1 éxito, hubo $exitos"
codigo=$(echo "$A$B" | grep -c "P0409" || true)
[[ "$p0409" == "1" && "$codigo" -ge 1 ]] && ok "la otra: SQLSTATE P0409 «ya tiene un lead» (un solo lead total)" || rojo "esperaba 1 P0409 (mensaje+SQLSTATE), hubo msg=$p0409 code=$codigo"
IDS="$(q "select count(distinct inversionista_id) from crm.inversionista_identificadores where documento_normalizado='$DOC' and estado='vigente'")"
INV="$(q "select count(*) from crm.inversiones inv join crm.inversionista_identificadores i on i.inversionista_id=inv.inversionista_id where i.documento_normalizado='$DOC'")"
LEADS="$(q "select count(*) from crm.leads l join crm.inversionista_identificadores i on i.inversionista_id=l.inversionista_id where i.documento_normalizado='$DOC'")"
TIT="$(q "select count(*) from crm.inversion_titulares t join crm.inversiones inv on inv.id=t.inversion_id join crm.inversionista_identificadores i on i.inversionista_id=inv.inversionista_id where i.documento_normalizado='$DOC' and t.rol='principal'")"
[[ "$IDS" == "1" ]]   && ok "UNA sola identidad para $DOC" || rojo "identidades: $IDS"
[[ "$LEADS" == "1" ]] && ok "UN solo lead con inversionista_id" || rojo "leads con identidad: $LEADS"
[[ "$INV" == "1" ]]   && ok "UNA inversión preservada (hecho económico del ganador)" || rojo "inversiones: $INV"
[[ "$TIT" == "1" ]]   && ok "titular principal presente (candado #6)" || rojo "titulares: $TIT"
WIN="$(q "select l.id from crm.leads l join crm.inversionista_identificadores i on i.inversionista_id=l.inversionista_id where i.documento_normalizado='$DOC' limit 1")"
WTRX=$([[ "$WIN" == "$L1" ]] && echo A || echo B)
[[ "$(q "select count(*) from crm.cierres_externos where lead_id='$WIN' and inversionista_id is not null")" == "1" ]] && ok "el cierre nació con inversionista_id (invariante #4 del contrato)" || rojo "cierre sin inversionista_id"
[[ "$(q "select count(*) from crm.inversionista_responsables r join crm.inversionista_identificadores i on i.inversionista_id=r.inversionista_id where i.documento_normalizado='$DOC' and r.hasta is null")" == "1" ]] && ok "responsable de relación abierto (el vendedor)" || rojo "tramos de responsable ≠ 1"

echo "== #4 Reintento IDÉNTICO tras éxito → mismo resultado, sin duplicar =="
R="$(run_as "$V" "$(coop "$WIN" "$WTRX")")"; rc=$?
{ [[ $rc == 0 ]] && echo "$R" | grep -q '"reintento": *true'; } && ok "reintento → MISMO resultado, reintento=true" || rojo "reintento no idempotente: exit=$rc :: $(echo "$R"|tail -1|cut -c1-110)"
[[ "$(q "select count(*) from crm.inversiones inv join crm.inversionista_identificadores i on i.inversionista_id=inv.inversionista_id where i.documento_normalizado='$DOC'")" == "1" ]] && ok "sigue UNA inversión (no duplicó)" || rojo "duplicó inversión"
[[ "$(q "select count(*) from crm.multiempresa_idempotencia where clave='conversion_coop:$WIN'")" == "1" ]] && ok "clave de idempotencia guardada" || rojo "sin fila de idempotencia"
R2="$(run_as "$V" "select crm.convertir_lead_externo('$WIN','qorilazo',2000,'PEN','DNI','$DOC','F3 PERSONA UNO','TRX-F3-${RUN}-$WTRX')")"
echo "$R2" | grep -q "datos distintos" && ok "misma clave con payload DISTINTO → P0409" || rojo "payload distinto no rechazado: $(echo "$R2"|tail -1|cut -c1-100)"

echo "== #2 La persona VUELVE por Avance (lead nuevo + perfil con el mismo documento) =="
R="$(run_as "$V" "select crm.convertir_lead('$L3','$PA')")"
echo "$R" | grep -q "ya tiene un lead" && ok "P0409: reutiliza su único lead, no convierte otro" || rojo "Avance no rechazó el 2.º lead: $(echo "$R"|tail -1|cut -c1-100)"
[[ "$(q "select inversionista_id is null and etapa='nuevo' from crm.leads where id='$L3'")" == "t" ]] && ok "L3 intacto (sin puntero, sigue 'nuevo': la tx se revirtió entera)" || rojo "L3 quedó tocado"

echo "== #3 Ninguna puerta paralela crea un lead por fuera: disponibilidad por documento =="
# $DOC tiene perfil (PA): el camino del PERFIL gana (prioritario, sin 'via').
D="$(q "select r->>'estado' || '/' || coalesce(r->>'via','') from private.verificar_disponibilidad_lead_impl('${T}99','$DOC',null) r")"
[[ "$D" == "ya_es_cliente/" ]] && ok "disponibilidad($DOC, persona CON perfil) → ya_es_cliente por el perfil (camino prioritario)" || rojo "disponibilidad dijo '$D' (esperaba ya_es_cliente/ por perfil)"
# Persona SIN perfil (coop): se convierte L5 aquí y se prueba el camino de IDENTIDAD + p_excluir.
run_as "$V" "select crm.convertir_lead_externo('$L5','qorilazo',1000,'PEN','DNI','$DOC5','F3 PERSONA CINCO','TRX-F3-${RUN}-5')" >/dev/null && ok "L5 convertido en coop (persona $DOC5, sin perfil)" || rojo "no se pudo convertir L5"
D5="$(q "select r->>'estado' || '/' || coalesce(r->>'via','') from private.verificar_disponibilidad_lead_impl('${T}97','$DOC5',null) r")"
[[ "$D5" == "ya_es_cliente/identidad" ]] && ok "disponibilidad($DOC5, SIN perfil) → ya_es_cliente vía IDENTIDAD (un solo lead total)" || rojo "disponibilidad dijo '$D5' (esperaba ya_es_cliente/identidad)"
DX="$(q "select private.verificar_disponibilidad_lead_impl('${T}97','$DOC5','$L5')->>'estado'")"
[[ "$DX" != "ya_es_cliente" ]] && ok "editando el PROPIO lead (p_excluir=L5) no se bloquea a sí mismo ('$DX')" || rojo "p_excluir no excluyó al propio lead"
R="$(run_as "$V" "insert into crm.leads (id,nombre_completo,telefono,monto_estimado,origen,etapa,creado_por,vendedor_id,dni) values (gen_random_uuid(),'F3 ALTA DENEGADA','${T}99',1000,'landing','nuevo','$V','$V','$DOC')")"
echo "$R" | grep -q "P0481\|no disponible\|ya es cliente" && ok "alta CON SESIÓN de un 2.º lead con el documento → denegada (trigger de disponibilidad: $(echo "$R"|grep -o 'P0[0-9]*'|head -1))" || rojo "un alta con sesión abrió un 2.º lead para $DOC: $(echo "$R"|tail -1|cut -c1-90)"

echo "== #5 no_contactar por PERSONA + oportunidad viva =="
R="$(run_as "$V" "select crm.marcar_no_contactar('$L5','prueba')")" && ok "vendedor marcó no_contactar" || rojo "marcar falló: $(echo "$R"|tail -1|cut -c1-100)"
[[ "$(q "select i.no_contactar from crm.inversionistas i join crm.inversionista_identificadores d on d.inversionista_id=i.id where d.documento_normalizado='$DOC5'")" == "t" ]] && ok "el veto quedó en la IDENTIDAD" || rojo "identidad sin veto"
[[ "$(q "select private.verificar_disponibilidad_lead_impl('${T}98','$DOC5',null)->>'estado'")" == "no_contactar" ]] && ok "disponibilidad por documento → no_contactar (aunque cambie el teléfono)" || rojo "disponibilidad no ve el veto de la persona"
R="$(run_as "$V" "update crm.leads set no_contactar=false where id='$L5'")"; echo "$R" | grep -q "por su puerta\|42501" && ok "UPDATE directo para BAJAR el veto → rechazado" || rojo "UPDATE directo bajó el veto"
R="$(run_as "$V" "select crm.levantar_no_contactar('$L5','intento')")"; echo "$R" | grep -q "Solo Gerencia\|42501" && ok "vendedor NO puede levantar" || rojo "vendedor levantó"
R="$(run_as "$G" "select crm.levantar_no_contactar('$L5','')")"; echo "$R" | grep -q "exige un motivo" && ok "gerencia sin motivo → rechazado" || rojo "levantó sin motivo"
run_as "$G" "select crm.levantar_no_contactar('$L5','cliente pidió reactivar por escrito')" >/dev/null && ok "gerencia CON motivo levantó el veto" || rojo "gerencia no pudo levantar"
[[ "$(q "select i.no_contactar from crm.inversionistas i join crm.inversionista_identificadores d on d.inversionista_id=i.id where d.documento_normalizado='$DOC5'")" == "f" ]] && ok "veto levantado en la identidad" || rojo "veto sigue"
run_as "$V" "select crm.marcar_no_contactar('$L5','prueba herencia')" >/dev/null
psql "$PG" -q -c "begin; select set_config('crm.op_privilegiada','on',true); insert into crm.leads (id,nombre_completo,telefono,monto_estimado,origen,etapa,creado_por,vendedor_id,dni) values ('$L6','F3 LEAD SEIS (hereda) r$RUN','${T}06',1000,'landing','nuevo','$V','$V','$DOC5'); commit;" >/dev/null 2>&1
[[ "$(q "select no_contactar from crm.leads where id='$L6'")" == "t" ]] && ok "un lead NUEVO de la persona vetada NACE vetado (cierra el bypass de importación)" || rojo "el lead nuevo no heredó el veto"
run_as "$G" "select crm.levantar_no_contactar('$L5','limpieza ensayo')" >/dev/null

echo "== Paridad con bandera APAGADA (aterrizaje aditivo) =="
flag false
run_as "$V" "select crm.convertir_lead_externo('$L4','qorilazo',1000,'PEN','DNI','$DOC4','F3 PERSONA CUATRO r$RUN','TRX-F3-${RUN}-4')" >/dev/null && ok "conversión coop con bandera OFF funciona como hoy" || rojo "conversión OFF falló"
[[ "$(q "select inversionista_id is null from crm.leads where id='$L4'")" == "t" ]] && ok "OFF: el lead NO tomó inversionista_id" || rojo "OFF: tocó inversionista_id"
[[ "$(q "select count(*) from crm.inversionista_identificadores where documento_normalizado='$DOC4'")" == "0" ]] && ok "OFF: NO se creó identidad" || rojo "OFF: creó identidad"
flag true

# Teardown: los actores f3 salen del roster (fuera de banda, como baja-historica de la suite)
# para no perturbar las mediciones de la suite RLS en el mismo banco. Los datos quedan.
psql "$PG" -q -c "begin; alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo=false where perfil_id::text like 'f3000000-%'; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;" >/dev/null 2>&1
flag false
echo; if [[ "$ROJO" == "0" ]]; then echo "ORÁCULO F3 (lote Contrato-F2): VERDE — los 5 invariantes se cumplen bajo concurrencia real, por las PUERTAS."; exit 0
else echo "ORÁCULO F3 (lote Contrato-F2): ROJO — $ROJO aserciones fallaron." >&2; exit 1; fi
