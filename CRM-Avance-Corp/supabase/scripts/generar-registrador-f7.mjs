#!/usr/bin/env node
// Genera los REGISTRADORES de las olas de demolicion de la F7 leyendo la
// migracion DEL ARCHIVO, byte a byte.
//
// 🔴 POR QUE EXISTE ESTE GENERADOR. En ATR-4 (01/09) el registrador se escribio
//    a mano incrustando el cuerpo de la migracion, la migracion se edito
//    despues, y el registrador quedo con una version VIEJA dentro: el registro
//    habria guardado un texto que no era el que se aplico. Aqui el cuerpo se
//    lee del archivo en el momento de generar, y **`npm run gate:f7` corre
//    `--verificar` ANTES de tocar el servidor**: si alguien edita una migracion
//    de demolicion y no regenera, el gate se pone rojo. (Lo cazo la segunda
//    auditoria de Codex: la version anterior de este comentario prometia esa
//    comprobacion en `gate:config`, donde NO estaba cableada.)
//
// Uso:
//   node scripts/generar-registrador-f7.mjs            # (re)escribe los dos
//   node scripts/generar-registrador-f7.mjs --verificar # falla si estan viejos
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const MIGRACIONES = join(AQUI, '..', 'migrations');

/** Las dos olas. `pines` es lo que debe ser VERDAD del mundo vivo para que la
 *  version pueda registrarse: si la migracion no se aplico, el registrador
 *  aborta y NO deja constancia de algo que no paso. */
const OLAS = [
  {
    clave: 'ola2',
    version: '20260913130000',
    nombre: 'crm_f7_ola2_demoler_las_siete_gemelas_v2',
    archivo: '20260913130000_crm_f7_ola2_demoler_las_siete_gemelas_v2.sql',
    salida: 'registrar-f7-ola2-version.sql',
    titulo: 'OLA 2 — las siete gemelas demolidas',
    resumen: 'las 7 gemelas del catalogo viejo, demolidas y con su acta',
    pines: `  -- 1) LAS SIETE SE FUERON DE VERDAD (esto es lo que la migracion hizo).
  select count(*) into v_n from unnest(v_firmas) as f(firma)
   where to_regprocedure(f.firma) is not null;
  if v_n > 0 then
    raise exception 'registrar OLA 2: % gemela(s) siguen vivas — no se registra lo que no paso', v_n;
  end if;

  -- 2) EL LIBRO tiene las siete actas, por firma exacta.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = any (v_firmas) and estado = 'demolida';
  if v_n <> 7 then
    raise exception 'registrar OLA 2: el libro marca % de las 7 firmas demolidas', v_n;
  end if;

  -- 3) LAS PUERTAS VIVAS siguen en pie y el trigger de snapshot, armado.
  if to_regprocedure('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)') is null
     or to_regprocedure('crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb)') is null then
    raise exception 'registrar OLA 2: falta una puerta VIVA de contratos — no se registra un mundo roto';
  end if;
  select count(*) into v_n from pg_trigger t
   where t.tgrelid = 'public.contratos'::regclass
     and t.tgname = 'trg_contratos_producto_snapshot' and not t.tgisinternal
     and t.tgenabled <> 'D';
  if v_n <> 1 then
    raise exception 'registrar OLA 2: el trigger de snapshot del catalogo no esta armado';
  end if;

  -- 4) LOS GUARDIANES, EN VERDE.
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then
    raise exception 'registrar OLA 2: vigilante F7 en rojo: %', v_verd;
  end if;
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'registrar OLA 2: % alerta(s) del vigia sin resolver', v_n;
  end if;`,
    declara: `  v_firmas constant text[] := array[
    'crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
    'crm.crear_contrato_producto(uuid,jsonb,jsonb)',
    'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'public.crear_contrato_producto(uuid,jsonb,jsonb)'];
  v_n int; v_verd text; v_cuerpo text;`,
  },
  {
    clave: 'ola2b',
    version: '20260914130000',
    nombre: 'crm_f7_ola2b_demoler_el_tablero_de_altas_v2',
    archivo: '20260914130000_crm_f7_ola2b_demoler_el_tablero_de_altas_v2.sql',
    salida: 'registrar-f7-ola2b-version.sql',
    titulo: 'OLA 2b — el tablero de altas por analista, demolido',
    resumen: 'el tablero de altas por analista, demolido y con su acta',
    pines: `  -- 1) EL TABLERO SE FUE (esto es lo que la migracion hizo).
  if to_regprocedure('crm.metricas_altas_analista_fn(integer)') is not null then
    raise exception 'registrar OLA 2b: la funcion sigue viva — no se registra lo que no paso';
  end if;

  -- 2) SU ACTA esta en el libro.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = 'crm.metricas_altas_analista_fn(integer)' and estado = 'demolida';
  if v_n <> 1 then
    raise exception 'registrar OLA 2b: el libro no tiene su acta (filas %)', v_n;
  end if;

  -- 3) LAS DOS DEL BRIDGE, INTACTAS Y CON SU DUEÑO (deuda declarada: no se tocan).
  select count(*) into v_n from pg_proc p
   where p.oid in (to_regprocedure('crm.metricas_distribucion_leads_fn(date,date)'),
                   to_regprocedure('crm.metricas_distribucion_leads_v2_fn(date,date)'))
     and pg_get_userbyid(p.proowner) = 'crm_metricas_bridge';
  if v_n <> 2 then
    raise exception 'registrar OLA 2b: las 2 del bridge no siguen vivas con su dueño (coincidencias %)', v_n;
  end if;

  -- 4) LOS GUARDIANES, EN VERDE.
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then
    raise exception 'registrar OLA 2b: vigilante F7 en rojo: %', v_verd;
  end if;
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'registrar OLA 2b: % alerta(s) del vigia sin resolver', v_n;
  end if;`,
    declara: `  v_n int; v_verd text; v_cuerpo text;`,
  },
];

/** Devuelve un delimitador dollar-quote que NO aparece en ninguno de los textos.
 *  Es determinista (prueba sufijos en orden), asi que `--verificar` no se pone
 *  rojo solo por regenerar.
 *
 *  🔴 POR QUE. La primera version solo protegia el delimitador INTERIOR
 *     (`$mig_*$`) y daba por bueno el EXTERIOR (`$reg_*$`), que envuelve todo el
 *     bloque `do` — cuerpo embebido incluido. Una migracion que contuviera
 *     `$reg_ola2$` habria CERRADO el literal exterior antes de tiempo y
 *     producido SQL corrupto. Lo cazo la segunda auditoria de Codex. */
function delimitadorLibre(base, ...textos) {
  for (let i = 0; i < 100; i += 1) {
    const tag = i === 0 ? `$${base}$` : `$${base}_${i}$`;
    if (textos.every((t) => !t.includes(tag))) return tag;
  }
  throw new Error(`No hay delimitador libre para ${base} en 100 intentos`);
}

function generar(ola) {
  const cuerpo = readFileSync(join(MIGRACIONES, ola.archivo), 'utf8');
  const tag = delimitadorLibre(`mig_${ola.clave}`, cuerpo);
  // El exterior tiene que estar libre en TODO lo que va a envolver.
  const tagReg = delimitadorLibre(`reg_${ola.clave}`, cuerpo, ola.pines, ola.declara, tag);
  return `-- REGISTRADOR de la ${ola.titulo}.
--
-- 🤖 GENERADO por \`scripts/generar-registrador-f7.mjs\` — NO editar a mano.
--    El cuerpo de la migracion se lee DEL ARCHIVO al generar, para que no pueda
--    repetirse el fallo de ATR-4 (registrador con una version vieja dentro).
--    Si tocas la migracion, vuelve a generar: \`node scripts/generar-registrador-f7.mjs\`.
--
-- Inserta la version ${ola.version} en el registro SOLO si el mundo vivo ES el
-- posterior a la migracion. Patron de los registradores de ATR: pines del mundo
-- + relectura fail-closed despues del insert. \`!\` de Miguel, TRAS la migracion.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do ${tagReg}
declare
${ola.declara}
begin
${ola.pines}

  v_cuerpo := ${tag}${cuerpo}${tag};

  -- 5) Si la version ya existe: muda => abortar; cuerpo distinto => abortar.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${ola.version}' and statements is null;
  if v_n > 0 then
    raise exception 'registrar ${ola.clave}: la version existe MUDA — repararla, no pisarla';
  end if;
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${ola.version}' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar ${ola.clave}: la version existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('${ola.version}', '${ola.nombre}', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 6) RELECTURA fail-closed: la fila EXACTA, o se cae la transaccion entera.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${ola.version}'
     and name = '${ola.nombre}'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar ${ola.clave}: la relectura no encontro la fila exacta';
  end if;
end ${tagReg};

select '${ola.version} registrada: ${ola.resumen}' as resultado,
       (select count(*) from supabase_migrations.schema_migrations) as versiones,
       (select count(*) from private.f7_piezas_en_observacion where estado = 'demolida') as piezas_demolidas;
commit;
`;
}

const verificar = process.argv.includes('--verificar');
let desfasados = 0;
for (const ola of OLAS) {
  const destino = join(AQUI, ola.salida);
  const nuevo = generar(ola);
  let actual = null;
  try { actual = readFileSync(destino, 'utf8'); } catch { /* aun no existe */ }
  if (actual === nuevo) {
    console.log(`✓ ${ola.salida} al dia`);
    continue;
  }
  if (verificar) {
    console.error(`✗ ${ola.salida} esta DESFASADO respecto de ${ola.archivo}`);
    desfasados++;
    continue;
  }
  writeFileSync(destino, nuevo, 'utf8');
  console.log(`↻ ${ola.salida} regenerado desde ${ola.archivo}`);
}
if (desfasados > 0) {
  console.error(`\n${desfasados} registrador(es) desfasado(s). Corre: node scripts/generar-registrador-f7.mjs`);
  process.exit(1);
}
