#!/usr/bin/env node

// GATE DE LA ANALITICA DE LEADS Y CITAS (P-055 F6.a)
//
// Corre `supabase/scripts/trinquete-analitica-lc.sql` contra el proyecto
// enlazado y FALLA si nace un contador crudo sin declarar
// sin estar declarada, si una puerta exenta cambia de cuerpo (su razon caduca) o
// si el nucleo `private.assert_analitica_leads_citas()` deja de preguntar las dos mitades.
//
// 🔴 Las dos cosas que este proyecto ya pago:
//   1. `supabase db query` devuelve codigo 0 aunque la consulta reviente: el
//      error viaja dentro del JSON. Este envoltorio lo lee.
//   2. Ese canal NO transporta los `raise notice`. Por eso el verde no se da por
//      «no hubo error» sino por VER la fila de veredicto.
//
// Uso:
//   npm run gate:analitica             → el trinquete
//   npm run gate:analitica:mutante     → ademas rompe la regla de SIETE formas
//                                       (puerta nueva, comentario senuelo, puerta
//                                       mixta, vista, politica, rol a mano y
//                                       exencion caducada) dentro de una
//                                       transaccion que se deshace entera, y
//                                       exige que el gate REAL las cace.

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const CRM_ROOT = fileURLToPath(new URL('../..', import.meta.url));
const TRINQUETE = 'supabase/scripts/trinquete-analitica-lc.sql';
const MUTANTE = 'supabase/scripts/trinquete-analitica-lc-mutante.sql';

const args = new Set(process.argv.slice(2));
const permitidos = new Set(['--mutante', '--help', '-h']);
const desconocidos = [...args].filter((a) => !permitidos.has(a));
if (desconocidos.length > 0) fallar(`Opciones desconocidas: ${desconocidos.join(', ')}`);
if (args.has('--help') || args.has('-h')) {
  console.log('npm run gate:analitica [-- --mutante]');
  process.exit(0);
}

function correr(archivo) {
  const r = spawnSync(
    'npx',
    ['supabase', 'db', 'query', '--linked', '--file', archivo],
    { cwd: CRM_ROOT, encoding: 'utf8', env: process.env },
  );
  if (r.error) fallar(`No se pudo ejecutar supabase CLI: ${r.error.message}`);
  return `${r.stdout ?? ''}${r.stderr ?? ''}`;
}

function fallar(mensaje, detalle) {
  console.error(`\n❌ ${mensaje}`);
  if (detalle) console.error(detalle.trim());
  process.exit(1);
}

// --- 1. El trinquete: el verde exige VER la fila de veredicto ---------------
const salida = correr(TRINQUETE);
const veredicto = /"veredicto":\s*"(OK:[^"]*)"/.exec(salida)?.[1];
if (!veredicto) {
  fallar(
    salida.includes('SIN declarar')
      ? 'PUERTA NUEVA SIN DECLARAR: alguien pregunta por el pregunta cruda.'
      : salida.includes('cuerpo CAMBIO')
        ? 'EXENCION CADUCADA: una puerta exenta cambio de cuerpo y su razon ya no vale.'
        : salida.includes('es_analista_vigente')
          ? 'EL NUCLEO DE LA PREGUNTA UNICA FUE ALTERADO.'
          : 'El trinquete no devolvio su fila de veredicto (¿falta aplicar la F6.a?).',
    salida,
  );
}
console.log(`✅ Trinquete de vigencia: ${veredicto}`);

// --- 2. El mutante: probar que el gate SABE ponerse rojo --------------------
if (args.has('--mutante')) {
  const m = correr(MUTANTE);
  if (m.includes('MUTANTE_ANALITICA_SOBREVIVIO')) {
    const filos = /MUTANTE_ANALITICA_SOBREVIVIO en el\/los filo\(s\):[^"\\]*/.exec(m)?.[0] ?? '';
    fallar(`EL MUTANTE SOBREVIVIO: esa defensa no esta probada. ${filos}`, m);
  }
  if (!m.includes('MUTANTE_ANALITICA_CAZADO')) {
    fallar('El mutante no llego a su veredicto (no dijo ni CAZADO ni SOBREVIVIO).', m);
  }
  console.log('✅ Mutante cazado por los dieciséis filos: cada uno ejecuta el gate REAL y lo hace reventar.');
}

console.log('\nGate de analitica de leads y citas en verde.');
