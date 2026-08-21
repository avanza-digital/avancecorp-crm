#!/usr/bin/env bash
# Ensayo del asiento «Operaciones» contra el esquema y los datos REALES de
# produccion, sin escribir nada: todo va dentro de una transaccion que termina
# en rollback. Con --mutantes ademas rompe el arreglo cuatro veces y exige que
# el oraculo se ponga ROJO en cada una.
#
#   ./run-test-portal-asiento-operaciones.sh            # solo la base
#   ./run-test-portal-asiento-operaciones.sh --mutantes # base + 4 mutantes
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(cd "$AQUI/../.." && pwd)"
MIG="$RAIZ/supabase/migrations/20260821222348_portal_asiento_operaciones.sql"
ORA="$AQUI/test-portal-asiento-operaciones.sql"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

correr() {  # $1 = etiqueta, $2 = fichero con la mutacion (opcional)
  { echo "begin;"
    echo "set local lock_timeout='3s'; set local statement_timeout='120s';"
    cat "$MIG"
    [ -n "${2:-}" ] && cat "$2"
    cat "$ORA"
    echo "rollback;"
  } > "$TMP/ensayo.sql"
  (cd "$RAIZ" && npx --no-install supabase db query --linked --file "$TMP/ensayo.sql" 2>&1)
}

echo "== BASE =="
if correr base | grep -q "3/3 actos en verde"; then
  echo "   VERDE"
else
  echo "   ROJO — el asiento no quedo como se describe"; exit 1
fi

[ "${1:-}" = "--mutantes" ] || exit 0

# --- Los cuatro mutantes -----------------------------------------------------
cat > "$TMP/m1.sql" <<'SQL'
alter policy documentos_admin_inserta on public.documentos with check (public.es_admin());
SQL
cat > "$TMP/m2.sql" <<'SQL'
create or replace function public.es_admin() returns boolean language sql stable security definer
set search_path to 'public','pg_temp' as $f$
  SELECT EXISTS (SELECT 1 FROM public.perfiles WHERE id = auth.uid()
                 AND rol IN ('admin','superadmin','operaciones') AND activo = true);
$f$;
SQL
cat > "$TMP/m3.sql" <<'SQL'
alter policy documentos_admin_elimina on public.documentos using (public.es_gestor_cartera());
SQL
cat > "$TMP/m4.sql" <<'SQL'
-- Deja actualizar_numero_contrato en es_admin(): corregir el N de contrato SI es suyo.
create or replace function public.actualizar_numero_contrato(p_id uuid, p_numero text, p_notas text default null, p_categoria text default null)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $f$
BEGIN
  IF NOT public.es_admin() THEN RAISE EXCEPTION 'No autorizado'; END IF;
  RAISE EXCEPTION 'El N de contrato no puede quedar vacio';
END; $f$;
SQL

cat > "$TMP/m5.sql" <<'SQL'
-- Abre cerrar_contrato al asiento nuevo: cerrar ciclo es de Gloria.
create or replace function public.cerrar_contrato(p_id uuid, p_resultado text, p_contrato_nuevo_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
BEGIN
  IF NOT public.es_gestor_cartera() THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
  RAISE EXCEPTION 'Resultado invalido';
END; $f$;
SQL
cat > "$TMP/m6.sql" <<'SQL'
-- Quita el corte del asesor del trigger: vuelve a poder reasignar cartera.
create or replace function public.proteger_campos_inmutables()
returns trigger language plpgsql set search_path to 'public','pg_temp' as $f$
BEGIN
  NEW.id := OLD.id; NEW.creado_en := OLD.creado_en; NEW.creado_por := OLD.creado_por;
  RETURN NEW;
END; $f$;
SQL

declare -a NOMBRES=(
  "m1 · cierra la subida de documentos"
  "m2 · contamina es_admin() con el rol nuevo"
  "m3 · abre el borrado de documentos"
  "m4 · deja actualizar_numero_contrato en es_admin()"
  "m5 · abre cerrar_contrato al asiento nuevo"
  "m6 · quita el corte del asesor en el trigger"
)
FALLOS=0
for i in 1 2 3 4 5 6; do
  echo "== MUTANTE ${NOMBRES[$((i-1))]} =="
  if correr "m$i" "$TMP/m$i.sql" | grep -q "3/3 actos en verde"; then
    echo "   VERDE — el oraculo NO lo caza: no prueba lo que dice probar"; FALLOS=$((FALLOS+1))
  else
    echo "   ROJO (correcto)"
  fi
done
[ "$FALLOS" -eq 0 ] || { echo "$FALLOS mutante(s) sin cazar"; exit 1; }
echo "6/6 mutantes cazados."
