#!/usr/bin/env bash
# ÚLTIMO PASO — solo DESPUÉS de que la pantalla nueva esté publicada y verificada.
# Devuelve el permiso de uso a las dos funciones del domicilio legal.
# Hasta ahora existían pero eran inalcanzables: así no hubo ni un minuto con la
# escritura irreversible abierta sin interfaz que la ordenara.
set -euo pipefail
cd "$(dirname "$0")"
export SUPABASE_ACCESS_TOKEN="$(security find-generic-password -s 'Supabase CLI' -w)"
S=$(mktemp -d)
cat > "$S/abrir.sql" <<'SQL'
grant execute on function crm.datos_legales_contrato_fn(uuid) to authenticated;
grant execute on function crm.completar_domicilio_cliente(uuid, text) to authenticated;
SQL
npx --yes supabase@latest db query --linked --file "$S/abrir.sql"
cat > "$S/ver.sql" <<'SQL'
select has_function_privilege('authenticated','crm.datos_legales_contrato_fn(uuid)','execute')      as lectura_debe_ser_true,
       has_function_privilege('authenticated','crm.completar_domicilio_cliente(uuid, text)','execute') as escritura_debe_ser_true,
       has_function_privilege('anon','crm.completar_domicilio_cliente(uuid, text)','execute')          as anon_debe_ser_false,
       has_function_privilege('authenticated','crm.normalizar_domicilio_legal(text)','execute')        as normalizador_debe_ser_false,
       (select count(*) from public.perfiles where rol='cliente' and activo and domicilio is null)     as clientes_sin_domicilio_hoy;
SQL
npx --yes supabase@latest db query --linked --file "$S/ver.sql"
rm -rf "$S"
echo
echo "✅ esperado: lectura true · escritura true · anon false · normalizador false"
echo "   El último número (clientes sin domicilio) es el marcador: hoy 332."
echo "   Si baja en los próximos días, el arreglo está llegando a la gente."
