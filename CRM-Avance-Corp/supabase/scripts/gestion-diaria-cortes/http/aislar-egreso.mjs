// No modifica firewall, rutas del host ni otras redes/instancias.
// Retira la ruta por defecto DENTRO de cada namespace de red del banco.
// El acceso loopback publicado y el tráfico entre sus servicios se conservan.
import assert from 'node:assert/strict';
import { writeFileSync, existsSync } from 'node:fs';
import { carpeta, proyecto, docker, verificarBanco, credencialesLocales } from './banco.mjs';

assert.deepEqual(process.argv.slice(2), ['--solo-banco-autorizado']);
// Debe poder aislar un servicio recién arrancado, antes de su healthcheck.
verificarBanco({enPreparacion:true});
const servicios = ['db','auth','rest','kong','storage','inbucket'];
const inspecciones = JSON.parse(docker(['inspect', ...servicios.map(s => `supabase_${s}_${proyecto}`)]));
const imagen = inspecciones.find(c => c.Name === `/supabase_kong_${proyecto}`).Image;
const resguardo = `${carpeta}/rutas-originales.json`;
if (!existsSync(resguardo)) writeFileSync(resguardo, JSON.stringify(inspecciones.map(c => ({
  nombre: c.Name, id: c.Id, gateway: c.NetworkSettings.Networks[proyecto].Gateway,
})), null, 2)+'\n', { mode: 0o600, flag: 'wx' });

for (const instancia of inspecciones) {
  // Un reinicio automático reconstruiría la ruta de Docker. El banco se
  // detiene ante fallos y sólo se retoma pasando otra vez por este aislamiento.
  docker(['update','--restart','no',instancia.Id]);
  const base = ['run','--rm','--pull=never','--label',`avancecorp.task=${proyecto}`,
    '--network',`container:${instancia.Id}`,'--cap-drop','ALL','--read-only',
    '--security-opt','no-new-privileges=true','--user','0','--entrypoint','/bin/busybox'];
  const rutas = docker([...base,imagen,'ip','route']);
  const porDefecto = rutas.split('\n').find(r => r.startsWith('default '));
  if (porDefecto) {
    assert.equal(porDefecto.trim(), `default via ${instancia.NetworkSettings.Networks[proyecto].Gateway} dev eth0`);
    docker([...base,'--cap-add','NET_ADMIN',imagen,'ip','route','del','default']);
  }
  assert.ok(!docker([...base,imagen,'ip','route']).split('\n').some(r => r.startsWith('default ')));
  assert.ok(!docker([...base,imagen,'ip','-6','route']).split('\n').some(r => r.startsWith('default ')));
  console.log(`PASS: ${instancia.Name.slice(1)} sin ruta por defecto IPv4/IPv6`);
}
const limite = Date.now()+20_000;
for(;;) {
  try { verificarBanco(); break; }
  catch(error) {
    if(!/healthy/.test(error.message) || Date.now()>=limite) throw error;
    await new Promise(resolve=>setTimeout(resolve,250));
  }
}
const c = credencialesLocales();
const salud = await fetch(`${c.API_URL}/auth/v1/health`, { redirect:'error',
  headers:{apikey:c.ANON_KEY}, signal:AbortSignal.timeout(10_000) });
assert.equal(salud.status,200,'El aislamiento no debe cortar el Auth local');
verificarBanco();
console.log('PASS: servicios propios siguen sanos y Auth HTTP200; no se modificaron rutas del host');
