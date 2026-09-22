import { open } from 'node:fs/promises';
import { BANCO } from './banco.mjs';
import { compararRevisiones, leerRevision, LIMITE_REVISION_BYTES } from './banco-core.mjs';

// Solo compara los dos archivos entregados explícitamente. No persiste ni envía nada.
async function leer(ruta) {
  const archivo = await open(ruta, 'r');
  try {
    const estado = await archivo.stat();
    if (!estado.isFile() || estado.size > LIMITE_REVISION_BYTES) throw new Error('archivo_invalido');
    const buffer = Buffer.alloc(LIMITE_REVISION_BYTES + 1);
    let total = 0;
    while (total < buffer.length) {
      const { bytesRead } = await archivo.read(buffer, total, buffer.length - total, total);
      if (!bytesRead) break;
      total += bytesRead;
    }
    return leerRevision(buffer.subarray(0, total).toString('utf8'), BANCO);
  } finally { await archivo.close(); }
}

try {
  const rutas = process.argv.slice(2);
  if (rutas.length !== 2) throw new Error('argumentos_invalidos');
  const [primera, segunda] = await Promise.all(rutas.map(leer));
  console.log(JSON.stringify(compararRevisiones(primera, segunda, BANCO), null, 2));
} catch (error) {
  const mensajes = {
    espacios_repetidos: 'Los dos archivos son del mismo equipo. Entrega uno de Equipo A y otro de Equipo B.',
    argumentos_invalidos: 'Uso: npm run gestion-diaria:comparar -- /ruta/equipo-a.json /ruta/equipo-b.json',
    ENOENT: 'No se encontró uno de los archivos. Comprueba las dos rutas y vuelve a intentarlo.',
    EACCES: 'No hay permiso para leer uno de los archivos. Elige las descargas de este ejercicio.',
    archivo_invalido: 'Se necesitan archivos JSON de hasta 16 KiB, no carpetas ni archivos grandes.',
  };
  const clave = Object.hasOwn(mensajes, error?.message) ? error.message : error?.code;
  console.error(Object.hasOwn(mensajes, clave) ? mensajes[clave]
    : 'Archivo no válido: comprueba versión, huella, IDs y categorías del banco vigente, sin campos extra. No se muestra su contenido.');
  process.exitCode = 1;
}
