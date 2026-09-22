// Solo los casos sintéticos versionados; no acepta un archivo con datos reales.
import { leerClave, preguntar } from '../jev/cliente.mjs';
import { CASOS, VERSION_PREGUNTA } from './juicio.mjs';
import { ejecutarVivo } from './ejecucion.mjs';

const args = process.argv.slice(2);
if (args.some(arg => arg !== '--vivo') || args.length > 1) {
  console.error('Uso: node scripts/gestion-diaria-typesafe/piloto.mjs [--vivo]');
  process.exitCode = 2;
} else if (!args.includes('--vivo')) {
  // El modo normal no lee la clave ni abre conexiones.
  console.log(JSON.stringify({ modo: 'sin_red', casos: CASOS.length, version: VERSION_PREGUNTA, habilita_produccion: false }));
} else {
  const { codigoSalida, salida } = await ejecutarVivo({ leerClave, preguntar });
  console.log(JSON.stringify(salida, null, 2));
  process.exitCode = codigoSalida;
}
