#!/usr/bin/env node

// GATE DE LOS VIGIAS QUE CIERRAN SUS PROPIAS ALERTAS
//
// Comprueba, contra el proyecto enlazado, que el gesto de cierre sigue puesto:
//   · los tres vigias que escriben en `private.vigia_alertas` ABREN y CIERRAN
//     exactamente la misma fase (leido de su cuerpo, no de una lista a mano);
//   · ninguna alerta abierta pertenece a una fase que nadie sabe cerrar
//     (`private.vigia_alertas_sin_cierre()` vacia).
//
// 🔴 Por que existe. Hasta el 22/09/2026 la tabla acumulo 45 alertas y CERO
//    cierres desde el 05/09: los vigias solo sabian abrir. El preflight de
//    demolicion de la Fase 7 exige cero alertas abiertas de cualquier fase, asi
//    que era un candado sin llave. Este gate es lo que impide que vuelva a
//    perderse -- en particular, que un literal de fase se desvie SOLO en el
//    `update` de un vigia y esa fase deje de cerrarse en silencio.
//
// 🔴 Las dos cosas que este proyecto ya pago, y que este envoltorio respeta:
//   1. `supabase db query` devuelve codigo 0 aunque la consulta reviente: el
//      error viaja dentro del JSON. Aqui se lee.
//   2. Ese canal NO transporta los `raise notice`. Por eso el verde no se da
//      por «no hubo error» sino por VER la fila de veredicto.
//
// Uso:
//   npm run gate:vigias             → el estado del gesto de cierre
//   npm run gate:vigias:mutante     → ademas rompe la regla de SIETE formas
//                                     (incluidos dos filos ESTATICOS, los
//                                     unicos que cubren a los vigias cuyo
//                                     assert esta en rojo) dentro de una
//                                     transaccion que se deshace entera.

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const CRM_ROOT = fileURLToPath(new URL('../..', import.meta.url));
const ESTADO = 'supabase/scripts/vigias-cierran-estado.sql';
const MUTANTE = 'supabase/scripts/vigias-cierran-mutante.sql';

const args = new Set(process.argv.slice(2));
const permitidos = new Set(['--mutante', '--help', '-h']);
const desconocidos = [...args].filter((a) => !permitidos.has(a));
if (desconocidos.length > 0) fallar(`Opciones desconocidas: ${desconocidos.join(', ')}`);
if (args.has('--help') || args.has('-h')) {
  console.log('npm run gate:vigias [-- --mutante]');
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

// --- 1. El estado: el verde exige VER la fila de veredicto -----------------
const salida = correr(ESTADO);
const veredicto = /"veredicto":\s*"(OK:[^"]*)"/.exec(salida)?.[1];
if (!veredicto) {
  fallar(
    salida.includes('abre y cierra fases distintas')
      ? 'UN VIGIA ABRE Y CIERRA FASES DISTINTAS: esa fase no se cerrara nunca.'
      : salida.includes('sin cierre')
        ? 'HAY ALERTAS ABIERTAS DE UNA FASE QUE NADIE SABE CERRAR: el stop-the-line se puede bloquear para siempre.'
        : salida.includes('vigia_fases_cerrables')
          ? 'Falta private.vigia_fases_cerrables() (¿sin aplicar 20260922182454?).'
          : 'El gate no devolvio su fila de veredicto.',
    salida,
  );
}
console.log(`✅ Vigías: ${veredicto}`);

// --- 2. El mutante: probar que el gate SABE ponerse rojo --------------------
if (args.has('--mutante')) {
  const m = correr(MUTANTE);
  if (m.includes('MUTANTE_VIGIAS_SOBREVIVIO')) {
    const filos = /MUTANTE_VIGIAS_SOBREVIVIO en el\/los filo\(s\):[^"\\]*/.exec(m)?.[0] ?? '';
    fallar(`EL MUTANTE SOBREVIVIO: esa defensa no esta probada. ${filos}`, m);
  }
  if (!m.includes('MUTANTE_VIGIAS_CAZADO')) {
    fallar('El mutante no llego a su veredicto (no dijo ni CAZADO ni SOBREVIVIO).', m);
  }
  console.log('✅ Mutante cazado por los siete filos, dos de ellos ESTÁTICOS: cubren a los vigías cuyo assert está en rojo.');
}

console.log('\nGate de los vigías en verde.');
