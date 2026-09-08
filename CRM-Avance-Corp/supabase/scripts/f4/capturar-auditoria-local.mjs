import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { sql } from './banco-local.mjs';

const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const raiz = 'CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/';
// Nombres del bundle fijados por el entrypoint del renderer, comprobados en disco.
const candidatos = ['template-v2.ts', 'renderer.ts', 'assets-v2.ts',
  'pdfmake-0.2.20-pdfprinter.js', 'vfs-fonts-0.2.20.js'];
const manifiestoPdf = [];
for (const nombre of candidatos) {
  const archivo = raiz + nombre;
  const actual = readFileSync(archivo);
  const antes = spawnSync('git', ['show', `HEAD:${archivo}`], { maxBuffer: 16 * 1024 * 1024 });
  assert.equal(antes.status, 0);
  assert.equal(sha(actual), sha(antes.stdout), `Cambió el contenido documental: ${archivo}`);
  manifiestoPdf.push({ archivo, sha256: sha(actual), igualAHead: true });
}
const indices = JSON.parse(sql(`select jsonb_agg(jsonb_build_object('nombre',indexname,'ddl',indexdef) order by indexname)
  from pg_indexes where schemaname='crm' and indexname in
  ('inversionistas_perfil_uidx','inversiones_contrato_uidx','inversiones_cierre_uidx')`));
assert.equal(indices.length, 3);
assert(indices.every(i => i.ddl.includes('UNIQUE INDEX')));
const consumidoresPrimeraConversion = JSON.parse(sql(`select coalesce(jsonb_agg(n.nspname||'.'||p.proname order by n.nspname,p.proname),'[]')
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('crm','private','public') and p.prokind='f' and p.prosrc ilike '%es_primera_conversion%'`));
const jobs = JSON.parse(sql(`select coalesce(jsonb_agg(to_jsonb(t)),'[]') from
  (select template_version,estado,count(*) as cantidad from private.contrato_pdf_jobs group by 1,2 order by 1,2) t`));
const banderas = JSON.parse(sql('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags'));
assert.equal(banderas.inversiones_escritura, false);
const capturadoEn = new Date().toISOString();
const head = spawnSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' });
assert.equal(head.status, 0);
writeFileSync(new URL(`../evidencia-f4/auditoria-comprobaciones-${capturadoEn.replaceAll(':','-')}.json`, import.meta.url),
  JSON.stringify({ entorno: 'avancecorp-f4-bank', capturadoEn, headComparado: head.stdout.trim(), manifiestoPdf, indices,
    consumidoresPrimeraConversion, jobs, banderas,
    limite: 'Captura local. No certifica inventario de clientes externos, tratamiento histórico ni todas las versiones futuras de plantilla.',
  }, null, 2) + '\n', { flag: 'wx' });
console.log(JSON.stringify({ indicesUnicos: indices.length, consumidoresPrimeraConversion,
  contenidoDocumentalSinCambios: true, banderas }));
