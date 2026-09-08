// Conserva la candidata técnica inmutable y produce su revisión publicable.
// No conecta a bases. Solo admite las dos derivas capturadas y revisadas.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { funcionesDelSql } from './leer-funciones-sql.mjs';

const leer = p => readFileSync(new URL(p, import.meta.url), 'utf8');
const original = leer('../../migrations/20260907191832_crm_f4_inversiones_base_y_escritores.sql');
assert.equal(createHash('sha256').update(original).digest('hex'),
  '84f8b3b407812363ebe9705aaaab46b8620d48a79dc7d6d38cc285a18a293afe');
const actual = leer('./publicacion-2026-09-08/pdf-antes.sql');
assert.equal(createHash('md5').update(actual).digest('hex'), 'f1a9655a75261d6ba2bb16744c77a8d9');
const inventario = JSON.parse(leer('./publicacion-2026-09-08/inventario-antes.json'));
const inventarioAnterior = JSON.parse(leer('./base-inventario-consumidores.json')).funciones;
assert.equal(inventario.length, inventarioAnterior.length);
const documento = 'crm.corregir_documento_inversionista_fn(uuid, text, text, text, uuid)';
assert.deepEqual(inventario.filter(x => x.firma !== documento), inventarioAnterior.filter(x => x.firma !== documento));
assert.equal(inventario.find(x => x.firma === documento).md5, '45077ddc61bd59ab5f435116de292b05');
assert.equal(createHash('md5').update(leer('./publicacion-2026-09-08/documento-antes.sql')).digest('hex'),
  '45077ddc61bd59ab5f435116de292b05');

function reemplazar(s, antes, despues) {
  assert.equal(s.split(antes).length - 1, 1, `Ancla no única: ${antes.slice(0, 100)}`);
  return s.replace(antes, despues);
}
let pdf = reemplazar(actual, '\nbegin\n',
  '\nbegin\n  perform private.inversiones_escritura_bajo_candado(); -- F4: bandera antes de persona/cuenta/PDF\n');
pdf = reemplazar(pdf, '  v_pdf := private.crear_job_contrato_pdf_base(v_contrato_id, v_actor_id);',
  `  v_pdf := private.crear_job_contrato_pdf_base(v_contrato_id, v_actor_id);
  if private.inversiones_escritura_bajo_candado() then
    perform private.inversion_cotitulares_vincular(
      (select id from crm.inversiones where contrato_id=v_contrato_id),'alta');
  end if;`);
const funciones = funcionesDelSql(original);
const anterior = funciones.find(f => f.nombre === 'crm.crear_contrato_con_cuenta_pdf_v2').definicion;
let salida = reemplazar(original, anterior, pdf.trimEnd() + (pdf.trimEnd().endsWith(';') ? '' : ';'));
assert.equal(salida.split('9833ed526e733dc8af6ca78e5c85c7ca').length - 1, 2);
salida = salida.replaceAll('9833ed526e733dc8af6ca78e5c85c7ca', 'f1a9655a75261d6ba2bb16744c77a8d9');
salida = reemplazar(salida, '49d73e13f8969161060e2ce2b669a85a', '45077ddc61bd59ab5f435116de292b05');
salida = reemplazar(salida,
  '-- F4 multiempresa: SQL candidato. Construcción y pruebas aisladas; G4 aún no aprobado.',
  '-- F4 publicable: reemplaza la candidata no aplicada 20260907191832. G4 técnico cerrado.\n' +
  '-- Conserva Rentabilidad R4 y la corrección documental exclusiva de Administración.\n' +
  '-- Instalar solo esta revisión; no ejecutar también la candidata anterior.');
const despues = funcionesDelSql(salida);
assert.equal(despues.length, 48);
assert.deepEqual(despues.filter(f => f.nombre !== 'crm.crear_contrato_con_cuenta_pdf_v2'),
  funciones.filter(f => f.nombre !== 'crm.crear_contrato_con_cuenta_pdf_v2'));
const destino = resolve(process.argv[2] ?? '');
const carpeta = fileURLToPath(new URL('../../migrations/', import.meta.url));
assert(destino.startsWith(carpeta) && /^\d{14}_crm_f4_publicacion_compatible_rentabilidad\.sql$/.test(basename(destino)));
const existente = existsSync(destino) ? readFileSync(destino, 'utf8') : '';
assert(existente === '' || existente === salida, 'No sobrescribir otro artefacto');
writeFileSync(destino, salida);
console.log(JSON.stringify({ archivo: basename(destino), sha256: createHash('sha256').update(salida).digest('hex'),
  funciones: despues.length, cuerposSinCambio: 47, conservaRentabilidadR4: true, conservaAdministracion: true }));
