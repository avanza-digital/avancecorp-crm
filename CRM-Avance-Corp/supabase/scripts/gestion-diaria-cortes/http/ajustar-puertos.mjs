// Sólo infraestructura del banco desechable autorizado el 21/09/2026.
// La CLI publica explícitamente en 0.0.0.0 e ignora host_binding_ipv4.
// Conserva los contenedores originales detenidos; no elimina datos ni volúmenes.
import assert from 'node:assert/strict';
import { request } from 'node:http';
import { spawnSync } from 'node:child_process';

const proyecto = 'gestion-diaria-f4-http';
const carpeta = '/private/tmp/gestion-diaria-f4-http.WQNCJc';
const socketPath = '/Users/usuario/.docker/run/docker.sock';
const destinos = { db: ['5432/tcp', '59322'], kong: ['8000/tcp', '59321'], inbucket: ['8025/tcp', '59324'] };
assert.deepEqual(process.argv.slice(2), ['--solo-banco-autorizado']);
assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT, 'No admite overrides Docker');
const contexto = spawnSync('docker', ['context', 'inspect', '--format', '{{.Endpoints.docker.Host}}'], { encoding: 'utf8' });
assert.equal(contexto.status, 0);
assert.equal(contexto.stdout.trim(), `unix://${socketPath}`, 'Socket no autorizado');

function api(method, path, body) {
  return new Promise((resolve, reject) => {
    const payload = body === undefined ? null : JSON.stringify(body);
    const req = request({ socketPath, path: `/v1.56${path}`, method,
      headers: payload ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) } : {},
    }, res => {
      let text = '';
      res.setEncoding('utf8');
      res.on('data', chunk => { text += chunk; });
      res.on('end', () => {
        // No imprimir cuerpos de Docker: pueden contener variables secretas.
        if (res.statusCode < 200 || res.statusCode >= 300) {
          reject(new Error(`Docker ${method} ${path.split('?')[0]}: HTTP ${res.statusCode}`));
        } else resolve(text ? JSON.parse(text) : null);
      });
    });
    req.setTimeout(45_000, () => req.destroy(new Error('Timeout Docker local')));
    req.on('error', reject);
    req.end(payload);
  });
}

function copiarConfiguracionKong(origen, destino) {
  // La CLI copia estos archivos DESPUÉS de crear el contenedor. No están en la
  // imagen ni en un volumen. Pasan en memoria de un contenedor propio al otro;
  // jamás se imprimen ni se guardan en el repo (contienen claves sólo locales).
  for (const archivo of ['kong.yml', 'custom_nginx.template', 'localhost.crt', 'localhost.key']) {
    const lectura = spawnSync('docker', ['--host', `unix://${socketPath}`, 'cp', `${origen}:/home/kong/${archivo}`, '-'],
      { maxBuffer: 8 * 1024 * 1024 });
    assert.equal(lectura.status, 0, `No se pudo leer configuración local de Kong: ${archivo}`);
    const escritura = spawnSync('docker', ['--host', `unix://${socketPath}`, 'cp', '-', `${destino}:/home/kong/`],
      { input: lectura.stdout, maxBuffer: 8 * 1024 * 1024 });
    assert.equal(escritura.status, 0, `No se pudo trasladar configuración local de Kong: ${archivo}`);
  }
}

async function exigirSalud(id, servicio) {
  for (let intento = 0; intento < 30; intento++) {
    const c = await api('GET', `/containers/${id}/json`);
    assert.equal(c.State.Running, true, `${servicio} no está corriendo`);
    if (c.State.Health?.Status === 'healthy') return;
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  throw new Error(`${servicio} no llegó a healthy; no se considera listo`);
}

const red = await api('GET', `/networks/${proyecto}`);
assert.equal(red.Labels['avancecorp.task'], proyecto);
assert.equal(red.Options['com.docker.network.bridge.enable_ip_masquerade'], 'false');

for (const [servicio, [interno, externo]] of Object.entries(destinos)) {
  const nombre = `supabase_${servicio}_${proyecto}`;
  const actual = await api('GET', `/containers/${nombre}/json`);
  assert.equal(actual.Name, `/${nombre}`);
  assert.equal(actual.Config.Labels['com.supabase.cli.project'], proyecto);
  assert.equal(actual.Config.Labels['com.supabase.cli.workdir'], carpeta);
  assert.deepEqual(Object.keys(actual.NetworkSettings.Networks), [proyecto]);
  assert.deepEqual(Object.keys(actual.HostConfig.PortBindings), [interno]);
  assert.equal(actual.HostConfig.PortBindings[interno][0].HostPort, externo);
  assert.equal(actual.HostConfig.PortBindings[interno].length, 1);
  if (actual.HostConfig.PortBindings[interno][0].HostIp === '127.0.0.1') {
    if (servicio === 'kong' && !actual.State.Running) {
      const original = await api('GET', `/containers/${nombre}_resguardo_puerto/json`);
      assert.equal(original.Config.Labels['com.supabase.cli.project'], proyecto);
      assert.equal(original.Config.Labels['com.supabase.cli.workdir'], carpeta);
      assert.equal(original.State.Running, false);
      assert.equal(original.Image, actual.Image);
      copiarConfiguracionKong(original.Id, actual.Id);
      await api('POST', `/containers/${actual.Id}/start`);
    }
    await exigirSalud(actual.Id, servicio);
    console.log(`PASS: ${servicio} ya está limitado a loopback:${externo}`);
    continue;
  }
  assert.equal(actual.HostConfig.PortBindings[interno][0].HostIp, '');
  assert.equal(actual.State.Running, true);
  assert.equal(actual.HostConfig.AutoRemove, false);
  const host = structuredClone(actual.HostConfig);
  host.PortBindings = { [interno]: [{ HostIp: '127.0.0.1', HostPort: externo }] };
  host.RestartPolicy = { Name: 'no', MaximumRetryCount: 0 };
  // Evitar que el resguardo vuelva a arrancar con el mismo volumen de PostgreSQL.
  await api('POST', `/containers/${actual.Id}/update`, { RestartPolicy: { Name: 'no' } });
  await api('POST', `/containers/${actual.Id}/stop?t=30`);
  await api('POST', `/containers/${actual.Id}/rename?name=${nombre}_resguardo_puerto`);
  const creado = await api('POST', `/containers/create?name=${nombre}`, {
    ...actual.Config,
    Image: actual.Image,
    HostConfig: host,
    NetworkingConfig: { EndpointsConfig: { [proyecto]: { Aliases: [nombre] } } },
  });
  if (servicio === 'kong') copiarConfiguracionKong(actual.Id, creado.Id);
  await api('POST', `/containers/${creado.Id}/start`);
  const verificado = await api('GET', `/containers/${creado.Id}/json`);
  assert.deepEqual(verificado.HostConfig.PortBindings, host.PortBindings);
  assert.equal(verificado.Image, actual.Image);
  assert.deepEqual(verificado.Mounts.map(m => [m.Type, m.Name, m.Destination]),
    actual.Mounts.map(m => [m.Type, m.Name, m.Destination]));
  await exigirSalud(creado.Id, servicio);
  console.log(`PASS: ${servicio} limitado a 127.0.0.1:${externo}; original detenido y conservado`);
}
