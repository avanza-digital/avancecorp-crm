import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {probarAuditoria} from './auditoria-casos.mjs';

// Solo bancos Docker sintéticos conocidos; no admite una URL ni proyecto remoto.
const contenedor='supabase_db_avancecorp-f5-bank';
const db=process.env.CONTRATOS_AUDITORIA_BANCO || 'contratos_eliminar_20260915';
assert.ok(['contratos_eliminar_20260915','contratos_vinculados_20260916','contratos_registro_20260921'].includes(db), 'Banco local no autorizado');
function sql(consulta) {
  const r=spawnSync('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d',db,
    '-v','ON_ERROR_STOP=1','-f','-'],{input:consulta,encoding:'utf8'});
  assert.equal(r.status,0,r.stderr || r.error?.message);
  return r.stdout.trim();
}
probarAuditoria(sql);
