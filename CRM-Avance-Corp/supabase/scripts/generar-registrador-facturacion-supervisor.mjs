#!/usr/bin/env node
// Genera el REGISTRADOR de 20260916205617 (crm_facturacion_diaria_supervisor)
// leyendo la migracion DEL ARCHIVO, byte a byte — mismo principio que
// generar-registrador-altas.mjs (la leccion de ATR-4: un registrador tecleado a
// mano acaba guardando un cuerpo que no es el que se aplico).
//
// Uso:
//   node supabase/scripts/generar-registrador-facturacion-supervisor.mjs             # escribe
//   node supabase/scripts/generar-registrador-facturacion-supervisor.mjs --verificar # falla si esta viejo
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const MIGRACIONES = join(AQUI, '..', 'migrations');
const VERSION = '20260916205617';
const NOMBRE = 'crm_facturacion_diaria_supervisor';
const ARCHIVO = `${VERSION}_${NOMBRE}.sql`;
const SALIDA = join(AQUI, `registrar-${VERSION}.sql`);
const FIRMA = 'crm.facturacion_diaria_fn(date)';

/** Un tag dolar que NO aparezca en ninguno de los textos (evita colisiones con
 *  $function$ / $postflight$ del cuerpo). */
function delimitadorLibre(base, ...textos) {
  for (let i = 0; i < 50; i++) {
    const tag = i === 0 ? `$${base}$` : `$${base}_${i}$`;
    if (textos.every((t) => !t.includes(tag))) return tag;
  }
  throw new Error('sin delimitador libre');
}

const cuerpo = readFileSync(join(MIGRACIONES, ARCHIVO), 'utf8');
const tag = delimitadorLibre('mig_fsup', cuerpo);
const tagReg = delimitadorLibre('reg_fsup', cuerpo, tag);

const registrador = `-- Registra ${VERSION} (${NOMBRE}) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/generar-registrador-facturacion-supervisor.mjs
-- leyendo la migracion del archivo: no editar a mano; regenerar. Orden de la
-- casa: PRIMERO aplicar la migracion con \`db query --linked --file\`, DESPUES
-- este registrador (el pin 1 se niega a registrar lo que no paso).
do ${tagReg}
declare v_n int; v_cuerpo text; v_huella text;
begin
  v_cuerpo := ${tag}${cuerpo}${tag};

  -- 1) PIN: lo que la migracion hizo ES verdad — la funcion existe y su cuerpo
  --    YA NO es el de 20260910230000 (huella f64e92e2...). Si no, no se
  --    registra lo que no paso.
  if to_regprocedure('${FIRMA}') is null then
    raise exception 'registrar facturacion supervisor: ${FIRMA} NO existe — aplicar la migracion antes de registrar';
  end if;
  select md5(p.prosrc) into v_huella from pg_proc p where p.oid = '${FIRMA}'::regprocedure;
  if v_huella = 'f64e92e224fc64f3f0470f31e23aa56c' then
    raise exception 'registrar facturacion supervisor: la funcion viva sigue siendo la de 20260910230000 — aplicar la migracion antes de registrar';
  end if;

  -- 2) La version no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${VERSION}' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar facturacion supervisor: la version ${VERSION} existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  -- 3) Registro (idempotente).
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('${VERSION}', '${NOMBRE}', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 4) RELECTURA fail-closed: la fila EXACTA, o se cae la transaccion entera.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${VERSION}' and name = '${NOMBRE}'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar facturacion supervisor: la relectura no encontro la fila exacta';
  end if;
end ${tagReg};
`;

if (process.argv.includes('--verificar')) {
  if (!existsSync(SALIDA) || readFileSync(SALIDA, 'utf8') !== registrador) {
    console.error(`${SALIDA} esta VIEJO respecto a ${ARCHIVO}: regenerar`);
    process.exit(1);
  }
  console.log(`registrador al dia: ${SALIDA}`);
} else {
  writeFileSync(SALIDA, registrador);
  console.log(`escrito ${SALIDA} (${registrador.length} bytes)`);
}
