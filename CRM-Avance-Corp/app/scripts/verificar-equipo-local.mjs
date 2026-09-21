// Comprueba que la respuesta SQL instalada pasa el validador REAL del cliente,
// no solamente un fixture escrito a mano. No imprime nombres, ids ni métricas.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createServer } from 'vite';
const consulta = `begin;
select set_config('request.jwt.claim.sub', (select e.perfil_id::text from crm.equipo e
  where private.rol_crm(e.perfil_id)='supervisor' order by e.perfil_id limit 1), true);
set local role authenticated;
select crm.gestion_diaria_equipo_fn();
rollback;`;
const r = spawnSync('docker', ['exec', '-i', 'supabase_db_avancecorp-f5-bank', 'psql',
  '-X', '-qAt', '-U', 'postgres', '-d', 'gestion_diaria_f4_vista_chvrqh', '-v', 'ON_ERROR_STOP=1', '-f', '-'],
{ input: consulta, encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 });
assert.equal(r.status, 0, r.stderr);
const foto = JSON.parse(r.stdout.trim().split('\n').at(-1));
const servidor = await createServer({ server: { middlewareMode: true }, appType: 'custom' });
try {
  const { DiaEquipoSchema } = await servidor.ssrLoadModule('/src/lib/gestion-diaria-equipo.ts');
  const v = await import('valibot');
  const resultado = v.safeParse(DiaEquipoSchema, foto);
  assert.ok(resultado.success, 'El JSON de PostgreSQL debe cumplir el contrato Valibot');
  assert.ok(foto.equipo.length > 0, 'El banco debe incluir equipo activo');
  console.log('PASS: respuesta PostgreSQL bajo authenticated validada por el contrato real del frontend.');
} finally {
  await servidor.close();
}
