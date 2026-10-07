// El banco ejercita los valores que ofrece el formulario real, no una segunda lista.
import { readFileSync } from 'node:fs'
import { stripTypeScriptTypes } from 'node:module'
async function modulo(ruta) {
  const fuente=stripTypeScriptTypes(readFileSync(new URL('../../../app/src/lib/'+ruta,import.meta.url),'utf8'))
  return import('data:text/javascript;base64,'+Buffer.from(fuente).toString('base64'))
}
export async function catalogosUiSql() {
  const llamadas=await modulo('resultado-llamada.ts')
  const tipos=await modulo('tipos.ts')
  const valores={llamadas:llamadas.RESULTADOS.map(r=>({resultado:r.clave,tipo:r.tipo})),
    entrevistas:tipos.RESULTADOS_REUNION.map(r=>r.k),tipos_actividad:Object.keys(tipos.TIPOS_ACTIVIDAD)}
  return `create temp table catalogo_ui(valor jsonb);
    insert into catalogo_ui values ('${JSON.stringify(valores).replaceAll("'","''")}'::jsonb);
    grant select on catalogo_ui to authenticated;`
}
