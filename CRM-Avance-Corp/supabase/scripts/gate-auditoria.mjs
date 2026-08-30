#!/usr/bin/env node

// GATE DE AUDITORÍA (P-055 F1.4/F1.5)
//
// Corre el trinquete `supabase/scripts/trinquete-auditoria.sql` contra el
// proyecto enlazado y FALLA si alguna tabla de crm/public quedó sin rastro
// completo sin estar declarada en la lista blanca.
//
// 🔴 DOS COSAS QUE COSTARON UNA AUDITORÍA:
//   1. `supabase db query` devuelve código 0 aunque la consulta reviente: el
//      error viaja dentro del JSON. Este envoltorio lo lee.
//   2. Ese mismo canal NO transporta los `raise notice` (medido: un bloque que
//      solo hace `raise notice` devuelve `{"rows": []}`). Por eso el verde no se
//      da por «no hubo error» sino por VER la fila de veredicto que el SQL
//      devuelve al final. Un gate que buscara su OK en un aviso estaría siempre
//      verde por vacío.
//
// Uso:
//   npm run gate:auditoria               → el trinquete
//   npm run gate:auditoria:mutante       → además rompe la regla a propósito
//                                          (cinco filos) dentro de una
//                                          transacción que se deshace entera, y
//                                          exige que el gate REAL la cace: cada
//                                          filo ejecuta private.assert_auditoria().

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

if (!salida.includes('TRINQUETE_AUDITORIA_OK')) {
  const roto = salida.includes('TRINQUETE DE AUDITORÍA ROTO');
  const desalineada = salida.includes('LISTA BLANCA DESALINEADA');
  const sello = salida.includes('SELLO ROTO');
  const alertas = salida.includes('EL VIGÍA TIENE ALERTAS ABIERTAS');
  fallar(
    roto
      ? 'TRINQUETE ROTO: hay tablas sin rastro completo sin declarar.'
      : desalineada
        ? 'LISTA BLANCA DESALINEADA: la base y el repo no dicen lo mismo.'
        : sello
          ? 'SELLO ROTO: alguien tocó la lista blanca sin re-sellar.'
          : alertas
            ? 'EL VIGÍA TIENE ALERTAS ABIERTAS.'
            : 'El trinquete no devolvió su fila de veredicto (¿falta aplicar F1.4/F1.5?).',
    salida,
  );
}

const sinRastro = /"sin_rastro":\s*"?(\d+)"?/.exec(salida)?.[1] ?? '?';
const exenciones = /"exenciones":\s*"?(\d+)"?/.exec(salida)?.[1] ?? '?';
if (sinRastro !== '0') fallar(`El trinquete dice OK pero reporta ${sinRastro} tablas sin rastro.`, salida);
console.log(`✅ Trinquete: 0 tablas sin rastro completo · ${exenciones} exenciones declaradas y selladas.`);

// --- 2. El mutante: probar que el gate SABE ponerse rojo --------------------
if (args.has('--mutante')) {
  const m = correr(MUTANTE);
  if (m.includes('EL MUTANTE SOBREVIVIÓ')) {
    const filos = /EL MUTANTE SOBREVIVIÓ en el\/los filo\(s\):[^"\\]*/.exec(m)?.[0] ?? '';
    fallar(`EL MUTANTE SOBREVIVIÓ: esa defensa no está probada. ${filos}`, m);
  }
  // El éxito del mutante es su excepción: así deshace la transacción entera.
  if (!m.includes('MUTANTE_CAZADO')) {
    fallar('El mutante no llegó a su veredicto (no dijo ni CAZADO ni SOBREVIVIÓ).', m);
  }
  console.log('✅ Mutante cazado por los cinco filos: cada uno ejecuta el gate REAL y lo hace reventar.');
}

console.log('\nGate de auditoría en verde.');
