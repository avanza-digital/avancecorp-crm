#!/usr/bin/env node
// Genera supabase/scripts/registrar-20260917235656.sql leyendo la migración del
// archivo (mismo patrón que cartera-origen/generar-registrador.mjs): PRIMERO se
// aplica la migración con `db query --linked --file`, DESPUÉS el registrador,
// que se NIEGA a registrar lo que no pasó.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const VERSION = '20260917235656';
const NOMBRE = 'crm_prodelco_inversiones_en_dolares';
const SALIDA = join(AQUI, '..', `registrar-${VERSION}.sql`);

// Las cuatro definiciones que la migración publica, con la huella medida en la
// copia a paridad. Si en producción no quedan EXACTAMENTE así, no se registra.
const ESCRITORES = [
  ['crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text,integer,numeric)', 'f1759833df86b0a7e6f08d21ec2260c4'],
  ['crm.corregir_cierre_externo(uuid,numeric,text,text,text,text,date,text)', '93c3c6eb72b37fdf58b537781154ab88'],
  ['private.inversion_validar_datos(uuid,jsonb,jsonb)', '7c7f4bb5d77a7834571af850585f505f'],
  ['crm.confirmar_inversion_revisada_fn(uuid,integer)', 'eb671aa677a9ba63fa995510e4f48192'],
  ['crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)', 'fe210a25d8a08cfbce923d3ac12ab199'],
];
const CHECK_ESPERADO = "CHECK ((moneda = ANY (ARRAY['PEN'::text, 'USD'::text])))";

function delimitadorLibre(base, ...textos) {
  for (let i = 0; i < 50; i++) {
    const tag = i === 0 ? `$${base}$` : `$${base}_${i}$`;
    if (textos.every((t) => !t.includes(tag))) return tag;
  }
  throw new Error('sin delimitador libre');
}

const cuerpo = readFileSync(join(AQUI, '..', '..', 'migrations', `${VERSION}_${NOMBRE}.sql`), 'utf8');
const tag = delimitadorLibre('mig_prodelco_usd', cuerpo);
const tagReg = delimitadorLibre('reg_prodelco_usd', cuerpo, tag);

const pines = ESCRITORES.map(([firma, md5]) =>
  `  if to_regprocedure('${firma}') is null
     or md5(pg_get_functiondef('${firma}'::regprocedure)) is distinct from '${md5}' then
    raise exception 'registrar prodelco usd: % no quedó como la publica la migración ${VERSION} — aplicarla antes de registrar', '${firma}';
  end if;`).join('\n');

const registrador = `-- Registra ${VERSION} (${NOMBRE}) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/prodelco-usd/generar-registrador.mjs leyendo la
-- migración del archivo: no editar a mano; regenerar. Orden de la casa: PRIMERO
-- aplicar la migración con \`db query --linked --file\`, DESPUÉS este registrador.
do ${tagReg}
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := ${tag}${cuerpo}${tag};

  -- 1) PIN: lo que la migración hizo ES verdad. Los cuatro escritores con su
  --    definición publicada, el CHECK ensanchado y el catálogo abierto SOLO
  --    para Prodelco (Qorilazo se queda en soles: es la decisión de Miguel).
${pines}
  if (select pg_get_constraintdef(oid) from pg_constraint
      where conrelid='crm.cierres_externos'::regclass and conname='cierres_externos_moneda_check')
     is distinct from ${'$q$'}${CHECK_ESPERADO}${'$q$'} then
    raise exception 'registrar prodelco usd: el CHECK de moneda no es el que publica la migración';
  end if;
  if (select jsonb_object_agg(clave, monedas order by clave) from crm.empresas)
     is distinct from '{"avance":["PEN","USD"],"prodelco":["PEN","USD"],"qorilazo":["PEN"]}'::jsonb then
    raise exception 'registrar prodelco usd: el catálogo de empresas no quedó como publica la migración';
  end if;
  -- La moneda inmutable entre revisiones de una solicitud F4: es la defensa que
  -- impide que un bundle anterior reescriba en soles una solicitud en dólares.
  if (select p.prosrc from pg_proc p
      where p.oid='crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)'::regprocedure)
     not like '%p_datos->''moneda'' is distinct from v_s.datos->''moneda''%' then
    raise exception 'registrar prodelco usd: la correccion de solicitudes F4 no declara la moneda inmutable';
  end if;

  -- 2) La versión no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${VERSION}' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar prodelco usd: la versión ${VERSION} existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  -- 3) Registro (idempotente).
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('${VERSION}', '${NOMBRE}', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 4) RELECTURA fail-closed: la fila EXACTA, o se cae la transacción entera.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${VERSION}' and name = '${NOMBRE}'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar prodelco usd: la relectura no encontró la fila exacta';
  end if;
end ${tagReg};
`;

writeFileSync(SALIDA, registrador);
console.log(`escrito ${SALIDA} (${registrador.length} bytes)`);
