import test from 'node:test';
import assert from 'node:assert/strict';
import { validarServicios, validarRutas, proyecto, carpeta, contenedor } from './banco.mjs';
import { destinoPermitido } from './fetch-local.mjs';

function fixture() {
  const roles = ['db','auth','rest','kong','storage','inbucket'];
  const puertos = { db:['5432/tcp','59322'],kong:['8000/tcp','59321'],inbucket:['8025/tcp','59324'] };
  const datos = roles.map(s => ({
    Name:`/supabase_${s}_${proyecto}`, Config:{Labels:{'com.supabase.cli.project':proyecto,'com.supabase.cli.workdir':carpeta},
      Env: {auth:[`GOTRUE_DB_DATABASE_URL=postgresql://auth:ficticio@${contenedor}:5432/postgres`],
        rest:[`PGRST_DB_URI=postgresql://rest:ficticio@${contenedor}:5432/postgres`],
        storage:[`DATABASE_URL=postgresql://storage:ficticio@${contenedor}:5432/postgres`]}[s] ?? []},
    State:{Running:true,Health:{Status:'healthy'}},
    NetworkSettings:{Networks:{[proyecto]:{}}},
    HostConfig:{RestartPolicy:{Name:'no'},PortBindings:puertos[s]?{[puertos[s][0]]:[{HostIp:'127.0.0.1',HostPort:puertos[s][1]}]}:{}},
    Mounts:s==='db'?[{Type:'volume',Name:`supabase_db_${proyecto}`,Destination:'/var/lib/postgresql/data'}]:[],
  }));
  return {datos,red:{Name:proyecto,EnableIPv6:false,Labels:{'avancecorp.task':proyecto},Options:{'com.docker.network.bridge.enable_ip_masquerade':'false'}}};
}
test('acepta sólo los seis servicios propios con puertos loopback y DB común',() => {
  const {datos,red}=fixture(); assert.equal(validarServicios(datos,red),true);
});
for (const [nombre,mutar] of [
  ['otro proyecto',f=>{f.datos[0].Config.Labels['com.supabase.cli.project']='otro';}],
  ['otro directorio',f=>{f.datos[1].Config.Labels['com.supabase.cli.workdir']='/tmp/otro';}],
  ['otra red',f=>{f.datos[2].NetworkSettings.Networks={otra:{}};}],
  ['dos redes',f=>{f.datos[2].NetworkSettings.Networks.otra={};}],
  ['puerto público',f=>{f.datos[0].HostConfig.PortBindings['5432/tcp'][0].HostIp='0.0.0.0';}],
  ['puerto compartido',f=>{f.datos[0].HostConfig.PortBindings['5432/tcp'][0].HostPort='58322';}],
  ['volumen ajeno',f=>{f.datos[0].Mounts[0].Name='supabase_db_avancecorp-f5-bank';}],
  ['Auth apunta a otra base',f=>{f.datos[1].Config.Env=['GOTRUE_DB_DATABASE_URL=postgresql://x:y@prod.example/postgres'];}],
  ['REST apunta a otro database',f=>{f.datos[2].Config.Env=[`PGRST_DB_URI=postgresql://x:y@${contenedor}/otra`];}],
  ['servicio detenido',f=>{f.datos[3].State.Running=false;}],
  ['servicio enfermo',f=>{f.datos[4].State.Health.Status='unhealthy';}],
  ['reinicio automático',f=>{f.datos[4].HostConfig.RestartPolicy.Name='always';}],
  ['salida IPv6',f=>{f.red.EnableIPv6=true;}],
  ['falta un servicio',f=>{f.datos.pop();}],
]) test(`rechaza ${nombre}`,() => {const f=fixture();mutar(f);assert.throws(()=>validarServicios(f.datos,f.red));});

test('permite fetch únicamente al origen numérico del banco',() => {
  assert.equal(destinoPermitido('http://127.0.0.1:59321/rest/v1/rpc/gestion_diaria_equipo_fn'),true);
  for(const u of ['https://dctqcbznekcyxhjujuci.supabase.co/rest/v1/',
    'http://127.0.0.1:58321/','http://localhost:59321/','http://127.0.0.1:59322/',
    'http://user:pass@127.0.0.1:59321/','https://127.0.0.1:59321/']) {
    assert.equal(destinoPermitido(u),false);
  }
});

test('rutas: sólo red local y loopback; rechaza una salida por defecto',()=>{
  const local = 'eth0 000018AC 00000000 0001 0 0 0 0000FFFF 0 0 0';
  assert.equal(validarRutas(local),true);
  assert.throws(()=>validarRutas(`${local}\neth0 00000000 010018AC 0003 0 0 0 00000000 0 0 0`),/IPv4/);
  const v6 = `${'0'.repeat(32)} 00 ${'0'.repeat(32)} 00 ${'0'.repeat(32)} 00000000 00000000 00000000 00000001 eth0`;
  assert.throws(()=>validarRutas(v6),/IPv6/);
  assert.throws(()=>validarRutas('formato desconocido'),/Formato/);
});
