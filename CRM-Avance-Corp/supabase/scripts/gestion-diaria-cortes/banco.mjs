// Objetivo FIJO. No acepta URLs, variables de entorno, proyectos ni nombres de base.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
export const baseLocal = 'gestion_diaria_f4_vista_chvrqh';
export const contenedorLocal = 'supabase_db_avancecorp-f5-bank';
let socketLocal;
export function sqlLocal(texto) {
  if (!socketLocal) {
    assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT, 'No admite redirecciones Docker por entorno');
    const contexto = spawnSync('docker', ['context', 'inspect', '--format', '{{.Endpoints.docker.Host}}'], { encoding: 'utf8' });
    assert.equal(contexto.status, 0, 'No se pudo verificar el Docker local');
    socketLocal = contexto.stdout.trim();
    assert.match(socketLocal, /^unix:\/\//, 'El contexto Docker no es local');
  }
  const r = spawnSync('docker', ['--host', socketLocal, 'exec', '-i', contenedorLocal, 'psql', '-X', '-qAt',
    '-U', 'postgres', '-d', baseLocal, '-v', 'ON_ERROR_STOP=1', '-f', '-'], {
    encoding: 'utf8', input: `do $destino$ begin if current_database() <> '${baseLocal}' then
      raise exception 'Base no autorizada'; end if; end $destino$;\n${texto}`,
    maxBuffer: 8 * 1024 * 1024,
  });
  // Nunca volcar argumentos de conexión ni todo el SQL al fallar.
  const error = r.stderr?.replace(/^DETAIL:.*$/gm, 'DETAIL: omitido para no volcar valores de filas');
  assert.equal(r.status, 0, error || r.error?.message || 'Falló PostgreSQL local');
  return r.stdout.trim();
}
