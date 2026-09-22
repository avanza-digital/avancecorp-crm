import { codigoDeError, enParalelo } from '../jev/cliente.mjs';
import { CASOS, crearSolicitud, resumir } from './juicio.mjs';

// Dependencias inyectables: los tests cubren la ruta viva sin clave ni red.
export async function ejecutarVivo({ leerClave, preguntar }) {
  try {
    const clave = await leerClave();
    const inicio = performance.now();
    const lote = await enParalelo(CASOS, 4, async caso => {
      const comienzo = performance.now();
      const respuesta = await preguntar(crearSolicitud(caso), { clave, intentos: 1, tope: 15000 });
      return { ...respuesta, latencia_ms: performance.now() - comienzo };
    });
    const resumen = resumir(Object.fromEntries(CASOS.map((caso, i) => [caso.id, lote[i]])), performance.now() - inicio);
    return { codigoSalida: resumen.coincidencias === resumen.total ? 0 : 1, salida: resumen };
  } catch (error) {
    return { codigoSalida: 1, salida: { estado: 'FAIL', error: codigoDeError(error), revision_humana: false, habilita_produccion: false } };
  }
}
