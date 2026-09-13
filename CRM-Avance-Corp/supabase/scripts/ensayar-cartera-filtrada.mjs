// Ensayo atómico previo a instalar. Sólo banco: migra, compara y ROLLBACK.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { PRODUCTION_PROJECT_REF } from './fixtures.mjs';

const url = process.env.CRM_BANCO_PSQL_URL;
if (!url || url.includes(PRODUCTION_PROJECT_REF) || !url.includes('.supabase.com')) {
  console.error('Se requiere CRM_BANCO_PSQL_URL de una rama, nunca producción.');
  process.exit(1);
}
const psql = process.env.PSQL_BIN || 'psql';
function ejecutar(sql) {
  return execFileSync(psql, [url, '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-c', sql],
    { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 }).trim();
}
try {
  const anterior = ejecutar("select pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)")
    .replace('crm.resumen_cartera_fn()', 'pg_temp.resumen_cartera_anterior()') + ';';
  const migracion = readFileSync(fileURLToPath(new URL('../migrations/20260913213842_crm_cartera_filtro_recepcion.sql', import.meta.url)), 'utf8')
    .replace(/^begin;\n/m, '').replace(/^commit;\s*$/m, '');
  const oraculo = readFileSync(fileURLToPath(new URL('./test-cartera-filtrada.sql', import.meta.url)), 'utf8');
  const comparar = `
    do $equivalencia$
    declare r record; a jsonb; b jsonb; n integer:=0;
    begin
      for r in select perfil_id from crm.equipo where activo and private.rol_crm(perfil_id) is not null
        union select id from public.perfiles where rol='directorio' and activo loop
        perform set_config('request.jwt.claim.sub',r.perfil_id::text,true);
        a:=pg_temp.resumen_cartera_anterior(); b:=crm.resumen_cartera_fn();
        if a is distinct from b then
          raise exception 'Resumen incompatible para %: anterior %, nuevo %',r.perfil_id,a,b;
        end if;
        n:=n+1;
      end loop;
      if n<5 then raise exception 'Faltan roles para comparar el resumen'; end if;
      raise notice 'Resumen anterior/nuevo idéntico para % actores',n;
    end;
    $equivalencia$;
  `;
  console.log(ejecutar(oraculo.replace('set local role authenticated;', () =>
    `${anterior}\n${migracion}\n${comparar}\nset local role authenticated;`)));
  console.log('ENSAYO_CARTERA_FILTRADA_OK: permisos, paginación, fechas y compatibilidad; todo en rollback.');
} catch (error) {
  // El mensaje estándar de execFileSync contiene la URL/contraseña. No imprimirlo.
  console.error(String(error.stderr || 'No se completó el ensayo de cartera.'));
  process.exit(1);
}
