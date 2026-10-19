// Auth y PostgREST reales sobre una copia desechable del banco propio.
// No admite destinos remotos ni cambia datos/modos del banco de origen.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { setTimeout as esperar } from 'node:timers/promises';
import { contenedor, sql as origen } from './banco.mjs';

export async function bancoHttp(ejecutar) {
  const sufijo = randomUUID().replaceAll('-', '').slice(0, 12);
  const db = `recorrido_http_${sufijo}`, creados = [];
  const red = 'supabase_network_avancecorp-recorrido-lead-20261018';
  let creada = false;
  const comando = (args, input) => {
    const r = spawnSync('docker', args, { input, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
    assert.equal(r.status, 0, r.stderr || 'Fallo de Docker en el banco local');
    return r.stdout.trim();
  };
  const sql = texto => comando(['exec', '-i', contenedor, 'psql', '-X', '-qAt', '-U', 'supabase_admin',
    '-d', db, '-v', 'ON_ERROR_STOP=1', '-f', '-'], texto);
  const inspect = nombre => JSON.parse(comando(['inspect', nombre]))[0];
  const cfg = JSON.parse(spawnSync('supabase', ['status', '--workdir',
    '/private/tmp/recorrido-lead-hechos-20261018/stack', '-o', 'json'], { encoding: 'utf8' }).stdout);
  assert.equal(cfg.API_URL, 'http://127.0.0.1:58521');
  const foto = origen('select to_jsonb(c) from crm.recorrido_control c');
  try {
    assert(Object.hasOwn(inspect(contenedor).NetworkSettings.Networks, red));
    origen(`create database ${db} template template0 owner postgres;`); creada = true;
    const dump = (...secciones) => comando(['exec', contenedor, 'pg_dump', '-U', 'supabase_admin',
      '-d', 'postgres', '--no-comments', ...secciones.map(s => '--section=' + s)]);
    sql(dump('pre-data', 'data'));
    // Completa autores ficticios de configuración antes de restaurar las FK.
    // La copia de origen contiene configuración pública sin personas productivas.
    const referencias = origen(`select string_agg(format('select %I as id from %s where %I is not null',a.attname,c.conrelid::regclass,a.attname),' union ')
      from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1]
      where c.contype='f' and c.confrelid='public.perfiles'::regclass and cardinality(c.conkey)=1
        and c.conrelid::regclass::text like 'crm.%'`);
    sql(`create temporary table autores_ficticios as select distinct r.id from (${referencias}) r
      where not exists(select 1 from public.perfiles p where p.id=r.id);
      insert into auth.users(id) select id from autores_ficticios a where not exists(select 1 from auth.users u where u.id=a.id);
      insert into public.perfiles(id,nombre_completo,rol,activo,tipo_documento)
        select id,'AUTOR FICTICIO DE CONFIGURACION','comercial',false,'DNI' from autores_ficticios;`);
    sql(dump('post-data'));
    const urls = {};
    for (const [tipo, puerto, variable] of [['auth', 9999, 'GOTRUE_DB_DATABASE_URL'], ['rest', 3000, 'PGRST_DB_URI']]) {
      const fuente = inspect(`supabase_${tipo}_avancecorp-recorrido-lead-20261018`);
      assert(Object.hasOwn(fuente.NetworkSettings.Networks, red));
      const env = Object.fromEntries(fuente.Config.Env.map(e => [e.slice(0, e.indexOf('=')), e.slice(e.indexOf('=') + 1)]));
      const uri = new URL(env[variable]); assert.equal(uri.hostname, contenedor); uri.pathname = '/' + db;
      env[variable] = uri.href;
      const nombre = `${db}_${tipo}`;
      // Los secretos pasan por stdin, nunca por argv, logs ni archivos versionados.
      const entrada = Object.entries(env).map(([k, v]) => { assert(!/[\r\n]/.test(v)); return `${k}=${v}`; }).join('\n');
      comando(['run', '-d', '--name', nombre, '--label', 'avancecorp.task=recorrido-lead-http',
        '--network', red, '-p', `127.0.0.1::${puerto}`, '--env-file', '/dev/stdin', fuente.Config.Image], entrada);
      creados.push(nombre);
      const info = inspect(nombre);
      const asignado = info.NetworkSettings.Ports[`${puerto}/tcp`][0];
      assert.equal(asignado.HostIp, '127.0.0.1');
      urls[tipo] = `http://127.0.0.1:${asignado.HostPort}`;
    }
    const http = async (ruta, { token = cfg.ANON_KEY, body, method = 'POST', schema } = {}) => {
      const auth = ruta.startsWith('/auth/v1/');
      assert(auth || ruta.startsWith('/rest/v1/'));
      const respuesta = await fetch(urls[auth ? 'auth' : 'rest'] + ruta.replace(auth ? '/auth/v1' : '/rest/v1', ''), {
        method, signal: AbortSignal.timeout(20000), headers: { apikey: cfg.ANON_KEY,
          Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', Prefer: 'return=representation',
          ...(schema ? { 'Content-Profile': schema, 'Accept-Profile': schema } : {}) },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
      const texto = await respuesta.text(); let data; try { data = JSON.parse(texto); } catch { data = texto; }
      return { status: respuesta.status, data };
    };
    for (const [tipo, ruta] of [['auth', '/health'], ['rest', '/']]) {
      let listo = false;
      for (let i = 0; i < 80 && !listo; i++) {
        try { listo = (await fetch(urls[tipo] + ruta, { signal: AbortSignal.timeout(1000) })).ok; } catch { /* arrancando */ }
        if (!listo) await esperar(250);
      }
      assert(listo, `${tipo} no arrancó en la copia desechable`);
    }
    // Adaptador de direcciones para el handler oficial ejecutado en proceso.
    // Todas las respuestas siguen siendo de Auth/PostgREST reales de esta copia.
    const apiUrl = 'http://recorrido.local';
    const fetchApi = (entrada, opciones) => {
      const url = new URL(entrada); assert.equal(url.origin, apiUrl);
      const auth = url.pathname.startsWith('/auth/v1/');
      assert(auth || url.pathname.startsWith('/rest/v1/'));
      return fetch(urls[auth ? 'auth' : 'rest'] + url.pathname.replace(auth ? '/auth/v1' : '/rest/v1', '') + url.search, opciones);
    };
    await ejecutar({ sql, http, apiUrl, fetchApi, anon: cfg.ANON_KEY, servicio: cfg.SERVICE_ROLE_KEY });
  } finally {
    for (const nombre of creados.reverse()) comando(['rm', '-f', nombre]);
    if (creada) { assert.match(db, /^recorrido_http_[a-f0-9]{12}$/); origen(`drop database ${db} with (force)`); }
    assert.equal(origen('select to_jsonb(c) from crm.recorrido_control c'), foto, 'El banco de origen debe quedar intacto');
    console.log('PASS: copia HTTP eliminada; control del banco original intacto.');
  }
}
