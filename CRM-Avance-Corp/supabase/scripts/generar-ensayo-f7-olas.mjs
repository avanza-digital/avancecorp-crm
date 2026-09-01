#!/usr/bin/env node
// Arma el ENSAYO de las olas 2 y 2b de la F7 concatenando los ARCHIVOS REALES
// (migraciones, registradores y marchas atras), no copias incrustadas a mano.
//
// 🔴 POR QUE. La auditoria de Codex del 01/09 tumbo el ensayo anterior por dos
//    razones, y las dos se corrigen aqui:
//     ① el ACTO del mutante NO ejecutaba el preflight real: repetia su consulta
//       y comprobaba que devolvia siete. Si el `if` de la migracion se borrara,
//       se invirtiera, o el archivo divergiera de la copia incrustada, el
//       ensayo seguia VERDE. Ahora se ejecuta el preflight DEL ARCHIVO y se
//       exige que aborte, comprobando ademas el TEXTO del error (un fallo de
//       sintaxis tambien «aborta», y eso seria un falso verde).
//
//     ② el viaje en el tiempo ELIMINABA el CHECK `f7_obs_ventana` y confiaba en
//       el rollback exterior para reponerlo: la migracion nunca se probaba con
//       su guarda temporal instalada. Ahora el CHECK no se toca — se mueven
//       `cerrada_en` y `drop_no_antes_de` A LA VEZ, de forma coherente, bajando
//       el trigger NOMBRADO (doctrina limpieza-leads) y volviendolo a subir.
//
// El ensayo corre CONTRA PRODUCCION dentro de una transaccion que TERMINA
// SIEMPRE en `raise`: no persiste nada. Uso:
//   node scripts/generar-ensayo-f7-olas.mjs
//   npx supabase db query --linked --file supabase/scripts/ensayo-f7-olas-2-y-2b.sql
import { readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const MIGRACIONES = join(AQUI, '..', 'migrations');

// 🔴 Los registradores PRIMERO. Este ensayo los EMBEBE: si estuvieran viejos,
//    ensayaria un paquete que no es el que se va a publicar — y saldria verde.
//    (Lo pidio la segunda auditoria de Codex.)
{
  const r = spawnSync('node', [join(AQUI, 'generar-registrador-f7.mjs'), '--verificar'],
    { encoding: 'utf8' });
  if (r.status !== 0) {
    process.stderr.write(`${r.stdout ?? ''}${r.stderr ?? ''}`);
    console.error('\n✗ No se arma el ensayo con registradores DESFASADOS:'
      + ' regeneralos primero (node scripts/generar-registrador-f7.mjs).');
    process.exit(1);
  }
}

const MIG_OLA2 = '20260913130000_crm_f7_ola2_demoler_las_siete_gemelas_v2.sql';
const MIG_OLA2B = '20260914130000_crm_f7_ola2b_demoler_el_tablero_de_altas_v2.sql';

/** Quita la PRIMERA linea `begin;` y la ULTIMA linea `commit;` de nivel
 *  superior, para poder pegar el archivo dentro de la transaccion del ensayo.
 *  Se hace por posicion —no por patron global— porque los registradores llevan
 *  la migracion entera DENTRO de un literal, con sus propios begin/commit. */
function sinTransaccion(texto, etiqueta) {
  const lineas = texto.split('\n');
  const iBegin = lineas.findIndex((l) => l.trim() === 'begin;');
  if (iBegin === -1) throw new Error(`${etiqueta}: no encuentro el 'begin;' de nivel superior`);
  let iCommit = -1;
  for (let i = lineas.length - 1; i >= 0; i--) {
    if (lineas[i].trim() === 'commit;') { iCommit = i; break; }
  }
  if (iCommit === -1 || iCommit < iBegin) throw new Error(`${etiqueta}: no encuentro el 'commit;' final`);
  lineas[iBegin] = `-- [ensayo] begin; retirado (${etiqueta})`;
  lineas[iCommit] = `-- [ensayo] commit; retirado (${etiqueta})`;
  return lineas.join('\n');
}

/** Extrae un bloque `do $tag$ ... $tag$;` completo del texto. */
function bloqueDo(texto, tag, etiqueta) {
  const abre = texto.indexOf(`do $${tag}$`);
  if (abre === -1) throw new Error(`${etiqueta}: no encuentro el bloque do $${tag}$`);
  const cierra = texto.indexOf(`$${tag}$;`, abre + `do $${tag}$`.length);
  if (cierra === -1) throw new Error(`${etiqueta}: el bloque do $${tag}$ no cierra`);
  return texto.slice(abre, cierra + `$${tag}$;`.length);
}

const migOla2 = readFileSync(join(MIGRACIONES, MIG_OLA2), 'utf8');
const migOla2b = readFileSync(join(MIGRACIONES, MIG_OLA2B), 'utf8');
const regOla2 = readFileSync(join(AQUI, 'registrar-f7-ola2-version.sql'), 'utf8');
const regOla2b = readFileSync(join(AQUI, 'registrar-f7-ola2b-version.sql'), 'utf8');
const rbOla2 = readFileSync(join(AQUI, 'rollback-f7-ola2-gemelas.sql'), 'utf8');
const rbOla2b = readFileSync(join(AQUI, 'rollback-f7-ola2b-tableros.sql'), 'utf8');

const preOla2 = bloqueDo(migOla2, 'ola2_pre', MIG_OLA2);
const preOla2b = bloqueDo(migOla2b, 'ola2b_pre', MIG_OLA2B);
for (const [txt, et] of [[preOla2, 'ola2'], [preOla2b, 'ola2b']]) {
  if (txt.includes('$mutante_sql$')) throw new Error(`${et}: colision con el delimitador del mutante`);
}

const ensayo = `-- ENSAYO de las OLAS 2 y 2b de la F7 — CONTRA PRODUCCION, SIN ESCRIBIR NADA.
--
-- 🤖 GENERADO por \`scripts/generar-ensayo-f7-olas.mjs\` — NO editar a mano.
--    Concatena los ARCHIVOS REALES (migraciones, registradores y marchas atras).
--    Si tocas cualquiera de ellos, vuelve a generar.
--
-- Termina SIEMPRE en \`raise\`: la transaccion entera se deshace. Lo unico que
-- deja es el veredicto en el mensaje de error. Doctrina «probar en produccion
-- sin escribir nada».
--
-- Los siete actos:
--   0 · foto previa del mundo
--   1 · VIAJE EN EL TIEMPO coherente — con el CHECK \`f7_obs_ventana\` PUESTO:
--       se mueven \`cerrada_en\` y \`drop_no_antes_de\` a la vez, bajando el
--       trigger NOMBRADO. La ventana queda SIN cumplir a proposito.
--   2 · MUTANTE DE LA VENTANA — se ejecuta el preflight REAL de cada ola y se
--       exige que ABORTE, con su mensaje. Si sobrevive, la guarda no existe.
--   3 · se cumple la ventana y corren las MIGRACIONES REALES
--   4 · corren los REGISTRADORES REALES (sus pines exigen el mundo post-DROP)
--   5 · corren las MARCHAS ATRAS REALES
--   6 · se comprueba que el mundo volvio ENTERO (definicion, comentario, ACL)
--   7 · veredicto y rollback

begin;
set local lock_timeout = '10s';
set local statement_timeout = '600s';

-- =====================================================================
-- ACTO 0 · FOTO PREVIA
-- =====================================================================
do $acto0$
declare v_n int;
begin
  select count(*) into v_n from private.f7_piezas_en_observacion;
  raise notice 'ACTO 0 · el libro tiene % piezas', v_n;
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'ENSAYO ABORTADO: % alerta(s) del vigia abiertas — stop-the-line', v_n;
  end if;
end $acto0$;

-- =====================================================================
-- ACTO 1 · VIAJE EN EL TIEMPO, CON EL CHECK PUESTO.
-- El CHECK exige drop_no_antes_de >= cerrada_en + 14, y el trigger congela
-- \`cerrada_en\` y prohibe encoger la ventana. Se baja el trigger NOMBRADO, se
-- mueven las DOS fechas de forma coherente, y se vuelve a subir. El CHECK no
-- se toca en ningun momento: la migracion se probara con su guarda instalada.
-- La ventana queda a MAÑANA — sin cumplir — para el mutante del ACTO 2.
-- =====================================================================
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;
update private.f7_piezas_en_observacion
   set cerrada_en = (now() at time zone 'America/Lima')::date - 14,
       drop_no_antes_de = (now() at time zone 'America/Lima')::date + 1
 where ola = 'F5.d' and estado = 'observacion';
update private.f7_piezas_en_observacion
   set cerrada_en = (now() at time zone 'America/Lima')::date - 14,
       drop_no_antes_de = (now() at time zone 'America/Lima')::date + 1
 where firma = 'crm.metricas_altas_analista_fn(integer)' and estado = 'observacion';
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;

-- =====================================================================
-- ACTO 2 · EL MUTANTE DE LA VENTANA. Se ejecuta el preflight REAL —el del
-- archivo, no una copia— y se exige que ABORTE por la ventana. Se comprueba el
-- TEXTO del error: un fallo de sintaxis tambien aborta, y contarlo como exito
-- seria justo el falso verde que esta auditoria vino a matar.
-- =====================================================================
do $acto2$
declare v_cazado boolean; v_msg text;
begin
  -- (2a) OLA 2
  v_cazado := false;
  begin
    execute $mutante_sql$${preOla2}$mutante_sql$;
  exception when others then
    v_cazado := true; v_msg := sqlerrm;
  end;
  if not v_cazado then
    raise exception 'MUTANTE-VENTANA OLA 2 SOBREVIVIO: el preflight no aborto con la ventana sin cumplir';
  end if;
  -- 🔎 La guarda de la Ola 2 es COMPUESTA (firma, ola, estado, OK y fecha), asi
  --    que «no estan listas» sola NO identifica la causa temporal: podria venir
  --    de un libro alterado. Se exige ademas que el detalle nombre la fecha de
  --    MAÑANA, que es exactamente lo que el viaje en el tiempo puso — y que solo
  --    puede salir de la rama de la ventana. (Lo pidio Codex en la 2.ª vuelta.)
  if v_msg not like '%no estan listas%' then
    raise exception 'MUTANTE-VENTANA OLA 2: aborto, pero por OTRA razon (%). La guarda temporal no esta probada.', v_msg;
  end if;
  if v_msg not like ('%demolible ' || ((now() at time zone 'America/Lima')::date + 1)::text || '%') then
    raise exception 'MUTANTE-VENTANA OLA 2: aborto por «no estan listas» pero SIN nombrar la fecha futura (%) — la causa no era la ventana: %',
      ((now() at time zone 'America/Lima')::date + 1), v_msg;
  end if;
  raise notice 'ACTO 2a · mutante de ventana CAZADO por el preflight real: %', v_msg;

  -- (2b) OLA 2b
  v_cazado := false;
  begin
    execute $mutante_sql$${preOla2b}$mutante_sql$;
  exception when others then
    v_cazado := true; v_msg := sqlerrm;
  end;
  if not v_cazado then
    raise exception 'MUTANTE-VENTANA OLA 2b SOBREVIVIO: el preflight no aborto con la ventana sin cumplir';
  end if;
  if v_msg not like '%sigue en su ventana%' then
    raise exception 'MUTANTE-VENTANA OLA 2b: aborto, pero por OTRA razon (%)', v_msg;
  end if;
  raise notice 'ACTO 2b · mutante de ventana CAZADO por el preflight real: %', v_msg;
end $acto2$;

-- =====================================================================
-- ACTO 3 · SE CUMPLE LA VENTANA (hoy) y corren las MIGRACIONES REALES.
-- =====================================================================
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;
update private.f7_piezas_en_observacion
   set drop_no_antes_de = (now() at time zone 'America/Lima')::date
 where estado = 'observacion'
   and (ola = 'F5.d' or firma = 'crm.metricas_altas_analista_fn(integer)');
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;

-- ---------- MIGRACION REAL: ${MIG_OLA2} ----------
${sinTransaccion(migOla2, MIG_OLA2)}

-- ---------- REGISTRADOR REAL: registrar-f7-ola2-version.sql ----------
${sinTransaccion(regOla2, 'registrar-f7-ola2-version.sql')}

-- ---------- MIGRACION REAL: ${MIG_OLA2B} ----------
${sinTransaccion(migOla2b, MIG_OLA2B)}

-- ---------- REGISTRADOR REAL: registrar-f7-ola2b-version.sql ----------
${sinTransaccion(regOla2b, 'registrar-f7-ola2b-version.sql')}

-- =====================================================================
-- ACTO 5 · LAS MARCHAS ATRAS REALES.
-- =====================================================================
-- ---------- MARCHA ATRAS REAL: rollback-f7-ola2b-tableros.sql ----------
${sinTransaccion(rbOla2b, 'rollback-f7-ola2b-tableros.sql')}

-- ---------- MARCHA ATRAS REAL: rollback-f7-ola2-gemelas.sql ----------
${sinTransaccion(rbOla2, 'rollback-f7-ola2-gemelas.sql')}

-- =====================================================================
-- ACTO 6 · ¿VOLVIO EL MUNDO? Las ocho, vivas y cerradas, con su definicion
-- COMPLETA y su comentario. Y las dos del bridge, intactas con su dueño.
-- =====================================================================
do $acto6$
declare
  v_esperado constant text[][] := array[
    array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)','956fb5f32191291d4b7ebafce5abbdb1'],
    array['crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)','1d884ef9f60a55dd4d0613a256e3ea71'],
    array['crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)','a93f2db825cc26c19b1756cde0cdc435'],
    array['crm.crear_contrato_producto(uuid,jsonb,jsonb)','230bcc46e72191600cbd5fc789e1d503'],
    array['public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)','c786d25a9aca26f6a818dd57abe6ef72'],
    array['public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)','7128b0ebb65497e67c56d5383988b512'],
    array['public.crear_contrato_producto(uuid,jsonb,jsonb)','58f41209f1cedf46198e7c76903f7bbb'],
    array['crm.metricas_altas_analista_fn(integer)','f439e788e16a49fa23d8b52c0047f929']
  ];
  v_fila text[]; v_hd text; v_n int; v_verd text;
begin
  foreach v_fila slice 1 in array v_esperado loop
    if to_regprocedure(v_fila[1]) is null then
      raise exception 'ACTO 6: % NO volvio', v_fila[1];
    end if;
    select md5(pg_get_functiondef(p.oid)) into v_hd from pg_proc p where p.oid = to_regprocedure(v_fila[1]);
    if v_hd is distinct from v_fila[2] then
      raise exception 'ACTO 6: % volvio con OTRA definicion (huella %)', v_fila[1], v_hd;
    end if;
  end loop;

  select count(*) into v_n from pg_proc p
   where p.oid in (to_regprocedure('crm.metricas_distribucion_leads_fn(date,date)'),
                   to_regprocedure('crm.metricas_distribucion_leads_v2_fn(date,date)'))
     and pg_get_userbyid(p.proowner) = 'crm_metricas_bridge';
  if v_n <> 2 then
    raise exception 'ACTO 6: las 2 del bridge no siguen con su dueño (coincidencias %)', v_n;
  end if;

  select count(*) into v_n from private.f7_piezas_en_observacion where estado = 'demolida';
  if v_n <> 0 then
    raise exception 'ACTO 6: quedan % pieza(s) marcadas demolidas tras la marcha atras', v_n;
  end if;

  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'ACTO 6: vigilante F7 en rojo: %', v_verd; end if;
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'ACTO 6: analitica en rojo: %', v_verd; end if;
  select private.assert_analista_vigencia() into v_verd;
  if v_verd not like 'OK%' then raise exception 'ACTO 6: vigencia en rojo: %', v_verd; end if;
end $acto6$;

-- =====================================================================
-- ACTO 7 · VEREDICTO. Termina SIEMPRE en error: nada se queda.
-- =====================================================================
do $acto7$
declare v_v int; v_d int;
begin
  select count(*) into v_v from supabase_migrations.schema_migrations;
  select count(*) into v_d from private.f7_piezas_en_observacion;
  raise exception 'F7-OLAS-2y2b-ENSAYO-VERDE: mutante de ventana cazado en las dos olas por el preflight REAL (con el CHECK puesto), migraciones y registradores aplicados (registro habria quedado en % versiones), marchas atras recrearon las 8 con definicion y comentario al byte, libro con % piezas y guardianes en verde. TODO DESHECHO.', v_v, v_d;
end $acto7$;

rollback;
`;

const destino = join(AQUI, 'ensayo-f7-olas-2-y-2b.sql');
let actual = null;
try { actual = readFileSync(destino, 'utf8'); } catch { /* aun no existe */ }

if (process.argv.includes('--verificar')) {
  // Un ensayo VIEJO acredita un paquete que ya no es el que se va a publicar:
  // exactamente el mismo fallo que el registrador desfasado. `gate:f7` lo corre.
  if (actual === ensayo) {
    console.log('✓ ensayo-f7-olas-2-y-2b.sql al dia');
  } else {
    console.error('✗ ensayo-f7-olas-2-y-2b.sql esta DESFASADO respecto de las migraciones,'
      + ' registradores o marchas atras. Corre: node scripts/generar-ensayo-f7-olas.mjs'
      + ' y VUELVE A ENSAYARLO contra produccion — un ensayo viejo no acredita nada.');
    process.exit(1);
  }
} else if (actual === ensayo) {
  console.log('✓ ensayo-f7-olas-2-y-2b.sql ya estaba al dia');
} else {
  writeFileSync(destino, ensayo, 'utf8');
  console.log(`↻ ensayo-f7-olas-2-y-2b.sql generado (${ensayo.split('\n').length} lineas)`);
}
