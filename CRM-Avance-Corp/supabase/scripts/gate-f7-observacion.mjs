#!/usr/bin/env node

// GATE DE LA OBSERVACION F7 (Ola 0)
//
// Corre `supabase/scripts/trinquete-f7-observacion.sql` contra el proyecto
// enlazado y FALLA si hay alertas abiertas en private.vigia_alertas (de
// CUALQUIER fase - este gate es el lector que esa tabla no tenia), si el vigia
// 06:59 esta apagado o alterado, o si el assert de piezas cerradas revienta
// (pieza reabierta, cuerpo cambiado, llamador nuevo, demolida renacida...).
//
// Herencias pagadas por gates anteriores:
//   1. `supabase db query` devuelve 0 aunque la consulta reviente: el error
//      viaja en el JSON y aqui se lee.
//   2. El canal no transporta raise notice: el verde exige VER la fila.
//
// Uso:
//   npm run gate:f7               -> el trinquete
//   npm run gate:f7 -- --mutante  -> ademas inserta una alerta falsa en una
//                                    transaccion deshecha y exige que el
//                                    veredicto la cace (y que no quede escrita)

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const CRM_ROOT = fileURLToPath(new URL('../..', import.meta.url));
const TRINQUETE = 'supabase/scripts/trinquete-f7-observacion.sql';
// Tres archivos: db query solo devuelve el ULTIMO resultado de cada archivo
// (trampa medida) — cada filo entrega su veredicto en su propio SELECT final.
const MUTANTE_A = 'supabase/scripts/trinquete-f7-observacion-mutante-a.sql';
const MUTANTE_B = 'supabase/scripts/trinquete-f7-observacion-mutante-b.sql';
const MUTANTE_LIMPIEZA = 'supabase/scripts/trinquete-f7-observacion-mutante-limpieza.sql';

const args = new Set(process.argv.slice(2));
const permitidos = new Set(['--mutante', '--help', '-h']);
const desconocidos = [...args].filter((a) => !permitidos.has(a));
if (desconocidos.length > 0) fallar(`Opciones desconocidas: ${desconocidos.join(', ')}`);
if (args.has('--help') || args.has('-h')) {
  console.log('npm run gate:f7 [-- --mutante]');
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

const salida = correr(TRINQUETE);
const veredicto = /"veredicto":\s*"((?:[^"\\]|\\.)*)"/.exec(salida)?.[1];
if (!veredicto) {
  fallar('El trinquete no devolvio la fila de veredicto (¿error del servidor?)', salida);
}
if (!veredicto.startsWith('OK:')) {
  fallar(`Observacion F7 en rojo: ${veredicto}`);
}
console.log(`\n✅ ${veredicto}`);
console.log('Gate de la observacion F7 en verde.');

if (args.has('--mutante')) {
  const sA = correr(MUTANTE_A);
  const sB = correr(MUTANTE_B);
  const sL = correr(MUTANTE_LIMPIEZA);
  const filoA = /"veredicto_mutante_a":\s*"(MUTANTE-A-[^"]*)"/.exec(sA)?.[1];
  const filoB = /"veredicto_mutante_b":\s*"(MUTANTE-B-[^"]*)"/.exec(sB)?.[1];
  const limpio = /"veredicto_limpieza":\s*"([^"]*)"/.exec(sL)?.[1];
  const s2 = sA + sB + sL;
  if (!filoA || !filoA.startsWith('MUTANTE-A-CAZADO')) {
    fallar(`El filo A (alertas) SOBREVIVIO o no respondio: ${filoA ?? 'sin fila'}`, s2);
  }
  if (!filoB || !filoB.startsWith('MUTANTE-B-CAZADO')) {
    fallar(`El filo B (vigia apagado) SOBREVIVIO o no respondio: ${filoB ?? 'sin fila'}`, s2);
  }
  if (!limpio || !limpio.startsWith('LIMPIO')) {
    fallar(`El mutante dejo rastro: ${limpio ?? 'sin fila'}`, s2);
  }
  console.log(`✅ ${filoA}`);
  console.log(`✅ ${filoB}`);
  console.log(`✅ ${limpio}`);
}
