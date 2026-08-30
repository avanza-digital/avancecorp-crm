#!/usr/bin/env node

// GATE DE AUDITORÍA (P-055 F1.4)
//
// Corre el trinquete `supabase/scripts/trinquete-auditoria.sql` contra el
// proyecto enlazado y FALLA si alguna tabla de crm/public quedó sin rastro sin
// estar declarada en la lista blanca de ese archivo.
//
// Existe porque `supabase db query` devuelve código 0 aunque la consulta haya
// reventado: el error viaja dentro del JSON. Este envoltorio lo lee.
//
// Uso:
//   npm run gate:auditoria            → el trinquete
//   npm run gate:auditoria -- --mutante  → además rompe la regla a propósito
//                                          (tabla sin rastro dentro de una
//                                          transacción que se deshace) y exige
//                                          que el trinquete se ponga rojo.

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const CRM_ROOT = fileURLToPath(new URL('../..', import.meta.url));
const TRINQUETE = 'supabase/scripts/trinquete-auditoria.sql';
const MUTANTE = 'supabase/scripts/trinquete-auditoria-mutante.sql';

const args = new Set(process.argv.slice(2));
const permitidos = new Set(['--mutante', '--help', '-h']);
const desconocidos = [...args].filter((a) => !permitidos.has(a));
if (desconocidos.length > 0) fallar(`Opciones desconocidas: ${desconocidos.join(', ')}`);
if (args.has('--help') || args.has('-h')) {
  console.log('npm run gate:auditoria [-- --mutante]');
  process.exit(0);
}

function correr(archivo) {
  const r = spawnSync(
    'npx',
    ['supabase', 'db', 'query', '--linked', '--file', archivo],
    { cwd: CRM_ROOT, encoding: 'utf8', env: process.env },
  );
  const salida = `${r.stdout ?? ''}${r.stderr ?? ''}`;
  if (r.error) fallar(`No se pudo ejecutar supabase CLI: ${r.error.message}`);
  return { salida, codigo: r.status };
}

function fallar(mensaje, detalle) {
  console.error(`\n❌ ${mensaje}`);
  if (detalle) console.error(detalle.trim());
  process.exit(1);
}

// --- 1. El trinquete ---------------------------------------------------------
const { salida, codigo } = correr(TRINQUETE);
const reventó = salida.includes('"_tag":"Error"') || salida.includes('ERROR:');

if (reventó || codigo !== 0) {
  const roto = salida.includes('TRINQUETE DE AUDITORÍA ROTO');
  fallar(
    roto
      ? 'TRINQUETE DE AUDITORÍA ROTO: hay tablas sin rastro sin declarar.'
      : 'El trinquete de auditoría no pudo correr.',
    salida,
  );
}
console.log('✅ Trinquete de auditoría: 0 tablas sin rastro fuera de las declaradas.');

// --- 2. El mutante (opcional): probar que el gate SABE ponerse rojo ----------
if (args.has('--mutante')) {
  const m = correr(MUTANTE);
  if (m.salida.includes('"_tag":"Error"') || m.salida.includes('ERROR:')) {
    fallar('El mutante no pudo correr.', m.salida);
  }
  if (!m.salida.includes('MUTANTE CAZADO')) {
    fallar(
      'EL MUTANTE SOBREVIVIÓ: se creó una tabla sin rastro y el trinquete no se inmutó. ' +
        'Esa regla no está probada.',
      m.salida,
    );
  }
  console.log('✅ Mutante cazado: con una tabla sin rastro, el trinquete se pone rojo.');
}

console.log('\nGate de auditoría en verde.');
