#!/usr/bin/env bash
# Mutantes de crm.eliminar_inversion_fn: por cada defensa, una versión que la neutraliza dentro de una transacción que
# se revierte. La batería (test-eliminar-inversion.sql) TIENE que fallar con cada uno; si alguno sobrevive, esa defensa
# no está probada. Uso (banco Docker con la migración aplicada):
#   BANCO_CONTENEDOR=avancecorp-eliminar-inversion-20261005 bash supabase/scripts/eliminar-inversion/mutantes.sh
set -euo pipefail
C="${BANCO_CONTENEDOR:?BANCO_CONTENEDOR}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIG="$DIR/../../migrations/20261005200945_crm_eliminar_inversion.sql"
# Cuerpo de la batería sin su BEGIN inicial ni su ROLLBACK final: el mutante va delante, en la misma transacción.
CUERPO="$(sed '1,/^begin;$/d' "$DIR/test-eliminar-inversion.sql" | sed '$d')"
[ "$(tail -n 1 "$DIR/test-eliminar-inversion.sql")" = "rollback;" ] || { echo "la batería ya no termina en rollback" >&2; exit 2; }
PUERTA="$(python3 - "$MIG" <<'PY'
import sys
s = open(sys.argv[1]).read()
i = s.index('create function crm.eliminar_inversion_fn')
j = s.index('end $$;', i) + len('end $$;')
print(s[i:j].replace('create function', 'create or replace function', 1))
PY
)"
reemplazar() { python3 -c 'import sys; s=sys.stdin.read(); a,b=sys.argv[1],sys.argv[2]; assert s.count(a)==1, a; print(s.replace(a,b))' "$1" "$2"; }
# Extrae de la migración la definición que empieza en $1 y termina en la primera aparición de $2 (ambos incluidos); la
# convierte en CREATE OR REPLACE y aplica el reemplazo $3 → $4 (que debe aparecer exactamente una vez).
mutar() {
  python3 - "$MIG" "$1" "$2" "$3" "$4" <<'PY'
import sys
mig, ini, fin, a, b = sys.argv[1:6]
s = open(mig).read()
i = s.index(ini)
j = s.index(fin, i) + len(fin)
f = s[i:j]
if f.startswith('create function'):
    f = f.replace('create function', 'create or replace function', 1)
assert f.count(a) == 1, a
print(f.replace(a, b))
PY
}
LBU_PROD="$DIR/leads_before_update.produccion.sql"   # texto de producción de private.leads_before_update (lo deja la reversa)

declare -a NOMBRES DDL
NOMBRES+=("cierre_anulado olvida la conversión eliminada")
DDL+=("create or replace function private.cierre_anulado(p_lead_id uuid) returns boolean language sql stable set search_path = '' as \$m\$
  select exists (select 1 from crm.cierres_externos ce where ce.lead_id = p_lead_id and ce.es_cierre_inicial and ce.anulado_en is not null)
      or exists (select 1 from crm.cierres_avance_anulados ca where ca.lead_id = p_lead_id) \$m\$;")
NOMBRES+=("la válvula abre siempre")
DDL+=("create or replace function private.inversion_eliminacion_autoriza(p_parte text, p_clave uuid, p_fila jsonb) returns boolean
  language sql stable set search_path = '' as \$m\$ select true \$m\$;")
NOMBRES+=("la válvula no compara la fila con la copia")
DDL+=("create or replace function private.inversion_eliminacion_autoriza(p_parte text, p_clave uuid, p_fila jsonb) returns boolean
  language sql stable set search_path = '' as \$m\$ select coalesce(current_setting('crm.inversion_eliminacion', true), '') <> ''
    and exists (select 1 from crm.inversiones_eliminadas a where a.valvula::text = current_setting('crm.inversion_eliminacion', true)) \$m\$;")
NOMBRES+=("la historia propia no se comprueba")
DDL+=("create or replace function private.inversion_motivo_no_eliminable(p_tipo text, p_fuente uuid, p_inversion uuid) returns text
  language sql stable set search_path = '' as \$m\$ select null::text \$m\$;")
NOMBRES+=("cualquiera es gerencia")
DDL+=("create or replace function private.eliminar_inversion_roles(p_actor uuid) returns jsonb language plpgsql set search_path = '' as \$m\$
  begin return jsonb_build_object('portal', 'admin', 'gerencia', true); end \$m\$;")
NOMBRES+=("admin elimina conversiones sin gerencia")
DDL+=("$(printf '%s' "$PUERTA" | reemplazar 'if not v_gerencia then' 'if false then')")
NOMBRES+=("Avance sin exigir admin del portal")
DDL+=("$(printf '%s' "$PUERTA" | reemplazar "if v_ctx ->> 'tipo' = 'contrato' and v_portal is null then" "if false then")")
NOMBRES+=("sin motivo mínimo")
DDL+=("$(printf '%s' "$PUERTA" | reemplazar 'if v_motivo is null or length(v_motivo) < 5 then' 'if v_motivo is null then')")
NOMBRES+=("la solicitud de alta de una cooperativa se busca en fuente.id (forma que producción no escribe)")
DDL+=("$(mutar 'create function private.inversion_motivo_no_eliminable' '$$;' "array['fuente', 'cierre_id']" "array['fuente', 'id']")")
NOMBRES+=("P4 sin el ancla copiada (leads_before_update de producción)")
DDL+=("$(cat "$LBU_PROD")")
NOMBRES+=("la válvula no exige la misma transacción")
DDL+=("$(mutar 'create function private.inversion_eliminacion_autoriza' '$$;' '        and a.transaccion = pg_current_xact_id_if_assigned()
' '')")
NOMBRES+=("la válvula no exige el mismo actor")
DDL+=("$(mutar 'create function private.inversion_eliminacion_autoriza' '$$;' '        and a.eliminado_por = (select auth.uid())
' '')")
NOMBRES+=("el censo de dependencias siempre da conocidas")
DDL+=("create or replace function private.inversion_eliminacion_dependencias_conocidas() returns boolean language sql stable
  set search_path = '' as \$m\$ select true \$m\$;")
NOMBRES+=("la conversión no mira la acreditación")
DDL+=("$(mutar 'create function private.eliminar_inversion_contexto' 'end $$;' "  select ca.lead_id into v_lead_acreditado from crm.conversion_acreditaciones ca
    where ca.fuente_tipo = v_tipo and ca.fuente_id = p_fuente and ca.estado in ('acreditada', 'mes_sellado', 'fecha_futura')
    for update;" "  v_lead_acreditado := null;")")

vivos=0
for i in "${!NOMBRES[@]}"; do
  # La marca separa «el mutante no se pudo instalar» (no se juzga: cuenta como vivo) de «la batería falló» (muerto).
  salida="$(printf 'begin;\n%s\n\\echo MUTANTE_INSTALADO\n%s\nrollback;\n' "${DDL[$i]}" "$CUERPO" | docker exec -i -e PGPASSWORD=postgres "$C" \
    psql -U supabase_admin -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -f - 2>&1 || true)"
  if ! printf '%s' "$salida" | grep -q 'MUTANTE_INSTALADO'; then
    echo "NO SE PUDO INSTALAR  ${NOMBRES[$i]}: $(printf '%s' "$salida" | grep -m1 ERROR | cut -c1-160)"; vivos=$((vivos + 1))
  elif printf '%s' "$salida" | grep -q 'PASS eliminar_inversion (22 bloques)'; then
    echo "SOBREVIVE  ${NOMBRES[$i]}"; vivos=$((vivos + 1))
  else
    echo "MUERTO     ${NOMBRES[$i]}: $(printf '%s' "$salida" | grep -m1 -o 'FALLA.*\|ERROR:.*' | cut -c1-140)"
  fi
done
echo "mutantes: ${#NOMBRES[@]} · sobreviven o no se pudieron juzgar: $vivos"
[ "$vivos" -eq 0 ]
