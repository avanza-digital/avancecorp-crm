#!/usr/bin/env node
// Genera el REGISTRADOR de 20260905131000 (altas_nuevas_por_analista_v2) leyendo
// la migracion DEL ARCHIVO, byte a byte — mismo principio que
// generar-registrador-f7.mjs (la leccion de ATR-4: un registrador tecleado a mano
// acaba guardando un cuerpo que no es el que se aplico).
//
// Uso:
//   node supabase/scripts/generar-registrador-altas.mjs             # escribe
//   node supabase/scripts/generar-registrador-altas.mjs --verificar # falla si esta viejo
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const MIGRACIONES = join(AQUI, '..', 'migrations');
const VERSION = '20260905131000';
const NOMBRE = 'crm_altas_nuevas_por_analista_v2';
const ARCHIVO = `${VERSION}_${NOMBRE}.sql`;
const SALIDA = join(AQUI, `registrar-${VERSION}.sql`);
const FIRMA = 'crm.altas_nuevas_por_analista_fn(integer)';

/** Un tag dolar que NO aparezca en ninguno de los textos (evita colisiones con
 *  $fn$ / $post$ del cuerpo). */
function delimitadorLibre(base, ...textos) {
  for (let i = 0; i < 50; i++) {
    const tag = i === 0 ? `$${base}$` : `$${base}_${i}$`;
    if (textos.every((t) => !t.includes(tag))) return tag;
  }
  throw new Error('sin delimitador libre');
}

const cuerpo = readFileSync(join(MIGRACIONES, ARCHIVO), 'utf8');
const tag = delimitadorLibre('mig_altas', cuerpo);
const tagReg = delimitadorLibre('reg_altas', cuerpo, tag);

const registrador = `-- Registra ${VERSION} (${NOMBRE}) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/generar-registrador-altas.mjs leyendo la migracion
-- del archivo: no editar a mano; regenerar. Orden de la casa: PRIMERO aplicar la
-- migracion con \`db query --linked --file\`, DESPUES este registrador (el pin 1
-- se niega a registrar lo que no paso).
do ${tagReg}
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := ${tag}${cuerpo}${tag};

  -- 1) PIN: lo que la migracion hizo ES verdad — la funcion existe. Si no,
  --    no se registra lo que no paso.
  if to_regprocedure('${FIRMA}') is null then
    raise exception 'registrar altas: ${FIRMA} NO existe — aplicar la migracion antes de registrar';
  end if;

  -- 2) La version no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${VERSION}' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar altas: la version ${VERSION} existe con OTRO cuerpo — investigar antes de tocar';
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
    raise exception 'registrar altas: la relectura no encontro la fila exacta';
  end if;
end ${tagReg};
`;

if (process.argv.includes('--verificar')) {
  if (!existsSync(SALIDA)) { console.error(`❌ falta ${SALIDA}`); process.exit(1); }
  if (readFileSync(SALIDA, 'utf8') !== registrador) {
    console.error(`❌ ${SALIDA} esta VIEJO respecto a ${ARCHIVO}: regenerar`);
    process.exit(1);
  }
  console.log('✅ registrador al dia');
} else {
  writeFileSync(SALIDA, registrador);
  console.log(`escrito ${SALIDA} (${registrador.length} bytes, tag ${tag})`);
}
