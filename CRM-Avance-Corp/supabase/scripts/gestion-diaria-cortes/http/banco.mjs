// Destino fijo aprobado por el usuario. No permite elegir URL, base o proyecto.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';

export const proyecto = 'gestion-diaria-f4-http';
export const carpeta = '/private/tmp/gestion-diaria-f4-http.WQNCJc';
export const apiUrl = 'http://127.0.0.1:59321';
export const contenedor = `supabase_db_${proyecto}`;
const socket = 'unix:///Users/usuario/.docker/run/docker.sock';
const servicios = ['db', 'auth', 'rest', 'kong', 'storage', 'inbucket'];
const puertos = { db: ['5432/tcp', '59322'], kong: ['8000/tcp', '59321'], inbucket: ['8025/tcp', '59324'] };

export function docker(args, opciones = {}) {
  assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT, 'No admite redirecciones Docker por entorno');
  const contexto = spawnSync('docker', ['context', 'inspect', '--format', '{{.Endpoints.docker.Host}}'], { encoding: 'utf8' });
  assert.equal(contexto.status, 0, 'No se pudo verificar Docker local');
  assert.equal(contexto.stdout.trim(), socket, 'El socket Docker no es el autorizado');
  const r = spawnSync('docker', ['--host', socket, ...args], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, ...opciones });
  // Nunca mostrar inspect.Config.Env, argumentos de conexión ni cuerpos SQL.
  if (r.status !== 0) throw new Error(`Docker local: ${args[0]} falló (exit ${r.status ?? 'sin estado'})`);
  return r.stdout.trim();
}

export function validarServicios(datos, red, { exigirSalud = true } = {}) {
  assert.equal(red.Name, proyecto);
  assert.equal(red.Labels?.['avancecorp.task'], proyecto);
  assert.equal(red.Options?.['com.docker.network.bridge.enable_ip_masquerade'], 'false');
  assert.equal(red.EnableIPv6,false,'La red del banco no debe habilitar IPv6 externo');
  assert.deepEqual(datos.map(d => d.Name).sort(), servicios.map(s => `/supabase_${s}_${proyecto}`).sort());
  for (const d of datos) {
    const servicio = servicios.find(s => d.Name === `/supabase_${s}_${proyecto}`);
    assert.equal(d.Config.Labels?.['com.supabase.cli.project'], proyecto);
    assert.equal(d.Config.Labels?.['com.supabase.cli.workdir'], carpeta);
    assert.deepEqual(Object.keys(d.NetworkSettings.Networks), [proyecto]);
    assert.equal(d.State.Running, true, `${servicio} no está corriendo`);
    if (d.State.Health && exigirSalud) assert.equal(d.State.Health.Status, 'healthy', `${servicio} no está healthy`);
    assert.equal(d.HostConfig.RestartPolicy?.Name,'no',`${servicio}: reinicio automático no autorizado`);
    const esperado = puertos[servicio];
    assert.deepEqual(d.HostConfig.PortBindings ?? {}, esperado
      ? { [esperado[0]]: [{ HostIp: '127.0.0.1', HostPort: esperado[1] }] } : {});
    if (servicio === 'db') {
      assert.deepEqual(d.Mounts.map(m => [m.Type, m.Name, m.Destination]),
        [['volume', `supabase_db_${proyecto}`, '/var/lib/postgresql/data']]);
    }
    const clave = { auth: 'GOTRUE_DB_DATABASE_URL', rest: 'PGRST_DB_URI', storage: 'DATABASE_URL' }[servicio];
    if (clave) {
      const valor = d.Config.Env.find(e => e.startsWith(`${clave}=`))?.slice(clave.length + 1);
      assert.ok(valor, `Falta conexión propia de ${servicio}`);
      const url = new URL(valor);
      // No usar assert.equal sobre la URL completa: podría imprimir contraseñas.
      assert.ok(['postgres', 'postgresql'].includes(url.protocol.slice(0, -1)), 'Protocolo SQL inválido');
      assert.equal(url.hostname, contenedor, `Base ajena en ${servicio}`);
      assert.ok(url.port === '' || url.port === '5432', 'Puerto SQL ajeno');
      assert.equal(url.pathname, '/postgres', `Base ajena en ${servicio}`);
    }
  }
  return true;
}

export function validarRutas(texto) {
  for(const linea of texto.trim().split('\n')) {
    const c = linea.trim().split(/\s+/);
    if(c[0]==='Iface') continue;
    if(/^[a-f0-9]{32}$/i.test(c[0])) {
      assert.equal(c.length,10,'Formato IPv6 inesperado');
      assert.ok(!(c[0]==='0'.repeat(32) && c[1]==='00' && (parseInt(c[8],16)&1)), 'Ruta IPv6 por defecto activa');
    } else {
      assert.ok(c.length>=8 && /^[a-f0-9]{8}$/i.test(c[1]),'Formato IPv4 inesperado');
      assert.ok(!(c[1]==='00000000' && c[7]==='00000000' && (parseInt(c[3],16)&1)), 'Ruta IPv4 por defecto activa');
    }
  }
  return true;
}
let namespacesVerificados = '';
export function verificarBanco({ enPreparacion = false } = {}) {
  const datos = JSON.parse(docker(['inspect', ...servicios.map(s => `supabase_${s}_${proyecto}`)]));
  const red = JSON.parse(docker(['network', 'inspect', proyecto]))[0];
  validarServicios(datos, red, {exigirSalud:!enPreparacion});
  const firma = datos.map(d=>`${d.Id}:${d.State.StartedAt}`).join('|');
  if(!enPreparacion && firma!==namespacesVerificados) {
    const imagen = datos.find(d=>d.Name===`/supabase_kong_${proyecto}`).Image;
    for(const d of datos) validarRutas(docker(['run','--rm','--pull=never',
      '--label',`avancecorp.task=${proyecto}`,'--network',`container:${d.Id}`,
      '--cap-drop','ALL','--read-only','--security-opt','no-new-privileges=true',
      '--entrypoint','/bin/busybox',imagen,'cat','/proc/net/route','/proc/net/ipv6_route']));
    namespacesVerificados = firma;
  }
  return { proyecto, apiUrl, servicios: datos.map(d => ({ nombre: d.Name.slice(1), imagen: d.Image,
    estado: d.State.Health?.Status ?? d.State.Status })) };
}

export function sql(texto, { bootstrap = false, propietarioAlmacen = false } = {}) {
  verificarBanco();
  const guarda = bootstrap
    ? `if to_regnamespace('crm') is not null or exists(select 1 from auth.users)
         or exists(select 1 from pg_tables where schemaname='public') then
         raise exception 'Bootstrap sólo sobre banco nuevo vacío'; end if;`
    : `if shobj_description((select oid from pg_database where datname=current_database()), 'pg_database')
         is distinct from 'BANCO SINTETICO gestion-diaria-f4-http / sin produccion' then
         raise exception 'Falta identidad del banco autorizado'; end if;`;
  const r = spawnSync('docker', ['--host', socket, 'exec', '-i', contenedor, 'psql', '-X', '-qAt',
    // Restaurar dueños exactos exige el administrador LOCAL. Los ensayos de
    // producto corren como postgres / identidades reales; no se les eleva aquí.
    '-U', bootstrap || propietarioAlmacen ? 'supabase_admin' : 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-f', '-'], {
    encoding: 'utf8', maxBuffer: 32 * 1024 * 1024,
    input: `do $destino$ begin if current_database()<>'postgres' then raise exception 'Base ajena'; end if;
      ${guarda} end $destino$;\n${texto}`,
  });
  if (r.status !== 0) {
    // Mensajes técnicos sin filas ni cuerpos de funciones potencialmente privados.
    const resumen = (r.stderr ?? '').split('\n').filter(l => /ERROR:|FATAL:/.test(l)).join('\n');
    throw new Error(resumen || `SQL local falló (exit ${r.status ?? 'sin estado'})`);
  }
  return r.stdout.trim();
}

export function credencialesLocales() {
  verificarBanco();
  const r = spawnSync('supabase', ['status', '--workdir', carpeta, '--network-id', proyecto, '-o', 'json'],
    { encoding: 'utf8', maxBuffer: 1024 * 1024 });
  assert.equal(r.status, 0, 'No se pudieron obtener credenciales del banco local');
  const c = JSON.parse(r.stdout);
  assert.equal(c.API_URL, apiUrl);
  const url = new URL(c.DB_URL);
  assert.equal(url.hostname, '127.0.0.1');
  assert.equal(url.port, '59322');
  assert.equal(url.pathname, '/postgres');
  for (const [campo, rol] of [['ANON_KEY', 'anon'], ['SERVICE_ROLE_KEY', 'service_role']]) {
    assert.ok(typeof c[campo] === 'string' && c[campo].length > 40, `Falta ${campo} local`);
    const payload = JSON.parse(Buffer.from(c[campo].split('.')[1], 'base64url'));
    assert.equal(payload.iss, 'supabase-demo', 'No es una credencial sintética local');
    assert.equal(payload.role, rol, 'Rol de la credencial local incorrecto');
  }
  return c;
}

export async function http(ruta, { token, body, method = 'POST', esquema = 'crm', headers = {} } = {}) {
  assert.ok(ruta.startsWith('/') && !ruta.startsWith('//'), 'Ruta API inválida');
  const c = credencialesLocales();
  const destino = new URL(ruta, apiUrl);
  assert.equal(destino.origin, apiUrl, 'Destino HTTP ajeno');
  const r = await fetch(destino, { method, redirect: 'error', signal: AbortSignal.timeout(30_000),
    headers: { apikey: c.ANON_KEY, Authorization: `Bearer ${token ?? c.ANON_KEY}`,
      'Content-Type': 'application/json', 'Accept-Profile': esquema, 'Content-Profile': esquema, ...headers },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const texto = await r.text();
  let data;
  try { data = JSON.parse(texto); } catch { data = texto; }
  return { status: r.status, ok: r.ok, data };
}
