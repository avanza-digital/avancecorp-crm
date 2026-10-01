import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { sql, db, contenedor } from './banco.mjs';

// sql verifica nombre y marca del banco antes de abrir las dos sesiones.
sql('select 1');
const id = 'd0000000-0000-4000-8000-000000000090';
const alta = `select crm.crear_lead_documento_fn(
  '{"id":"${id}","nombre_completo":"CARRERA SINTETICA","telefono":"988770090","origen":"referido","monto_estimado":5000,"moneda":"PEN"}',
  'CE','009900090');`;
const actor = `set local role authenticated;
  select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);`;
function sesion(cuerpo, alLeer = () => {}) {
  return new Promise((resolve, reject) => {
    const p = spawn('docker', ['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres',
      '-d',db,'-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose','-f','-']);
    let salida = '', error = '';
    p.stdout.on('data', d => { salida += d; alLeer(salida); });
    p.stderr.on('data', d => { error += d; });
    p.on('error', reject);
    p.on('close', codigo => resolve({codigo, salida, error}));
    p.stdin.end(cuerpo);
  });
}
let desbloquear;
const bloqueado = new Promise(r => { desbloquear = r; });
const primera = sesion(`begin; ${actor} ${alta}
  select 'DOCUMENTO_BLOQUEADO'; select pg_sleep(7); rollback;`, s => {
  if (s.includes('DOCUMENTO_BLOQUEADO')) desbloquear();
});
await Promise.race([bloqueado, primera.then(r => { throw new Error(`No tomó el candado: ${r.error}`); })]);
const segunda = await sesion(`begin; ${actor}
  ${alta.replaceAll(id, 'd0000000-0000-4000-8000-000000000091').replaceAll('988770090','988770091')}
  rollback;`);
assert.notEqual(segunda.codigo, 0, 'La segunda sesión no debe atravesar el candado');
assert.match(segunda.error, /55P03.*lock timeout/s, 'Falla por candado, no por un error de fixture');
assert.equal((await primera).codigo, 0);
assert.equal(sql(`select count(*) from crm.leads where id in ('${id}','d0000000-0000-4000-8000-000000000091')`), '0');
assert.equal(sql("select count(*) from crm.inversionista_identificadores where documento_normalizado='009900090'"), '0');
console.log('PASS: dos sesiones no crean a la vez el mismo CE; rollback sin filas huérfanas');
