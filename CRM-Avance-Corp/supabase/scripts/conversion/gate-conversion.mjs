#!/usr/bin/env node
// Gate de coherencia de la conversión: VERDE o ROJO, con el motivo.
//
//   node supabase/scripts/conversion/gate-conversion.mjs <foto.json>
//   supabase db query --linked --file supabase/scripts/conversion/foto.sql | node .../gate-conversion.mjs -
//   node .../gate-conversion.mjs --diff <antes.json> <despues.json>
//
// No escribe en ninguna base. Sale con 1 en rojo para que valga como gate.
import { readFile } from 'node:fs/promises';
import { comprobarCoherencia, compararFotos } from './coherencia.mjs';

const args = process.argv.slice(2);
const leer = async (ruta) => {
  const texto = ruta === '-' ? await new Promise((r) => { let s = ''; process.stdin.on('data', (c) => { s += c; }); process.stdin.on('end', () => r(s)); }) : await readFile(ruta, 'utf8');
  // `db query` envuelve la fila en una tabla; la foto es el primer `{` … último `}`.
  const desde = texto.indexOf('{'); const hasta = texto.lastIndexOf('}');
  const crudo = JSON.parse(texto.slice(desde, hasta + 1));
  return crudo.foto ?? crudo;
};
const salida = (l) => process.stdout.write(`${l}\n`);

if (args[0] === '--diff') {
  const [antes, despues] = await Promise.all([leer(args[1]), leer(args[2])]);
  const r = compararFotos(antes, despues);
  if (r.sin_cambios) { salida('SIN CAMBIOS: las dos fotos dicen lo mismo en los cuatro caminos y en todas las filas.'); process.exit(0); }
  salida(`SE MOVIERON ${r.cambios.length} valores:`);
  for (const c of r.cambios) salida(`  · ${c.donde}: ${c.antes} → ${c.despues}`);
  process.exit(1);
}

const foto = await leer(args[0] ?? '-');
const r = comprobarCoherencia(foto);
if (r.ok) {
  salida(`VERDE · ${r.comprobadas} comprobaciones · mes ${foto.mes} hasta ${foto.hasta} · ${foto.caminos.nucleo_directo.pct} % por los cuatro caminos`);
  process.exit(0);
}
salida(`ROJO · ${r.fallos.length} fallo(s) de ${r.comprobadas} comprobaciones · mes ${foto.mes}`);
for (const f of r.fallos) salida(`  [${f.regla}] ${f.detalle}`);
process.exit(1);
