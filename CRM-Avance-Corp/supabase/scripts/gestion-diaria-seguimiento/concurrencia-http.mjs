// Dos sesiones Auth reales y barrera PostgreSQL: verifica que ambas peticiones
// esperan SIMULTÁNEAMENTE el mismo lock antes de soltarlas. No basta Promise.all.
// Deja historia sintética auditable; no resetea la base ni cambia código runtime.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { carpeta, contenedor, apiUrl, sql, credencialesLocales } from '../gestion-diaria-cortes/http/banco.mjs';
import { USER_BY_KEY } from '../fixtures.mjs';

assert.deepEqual(process.argv.slice(2),['--solo-banco-autorizado']);
const archivo=`${carpeta}/gd-f4-concurrencia-http.json`;
assert.equal(existsSync(archivo),false,'Hay evidencia previa; no repetir ni borrar la historia');
const c=credencialesLocales();
const {password}=JSON.parse(readFileSync(`${carpeta}/credenciales-fixtures.json`,'utf8'));
const q=x=>`'${String(x).replaceAll("'","''")}'`;
const pausita=ms=>new Promise(r=>setTimeout(r,ms));
async function peticion(ruta,token,body) {
  const r=await fetch(`${apiUrl}${ruta}`,{method:'POST',redirect:'error',signal:AbortSignal.timeout(20_000),
    headers:{apikey:c.ANON_KEY,Authorization:`Bearer ${token??c.ANON_KEY}`,
      'Content-Type':'application/json','Accept-Profile':'crm','Content-Profile':'crm'},body:JSON.stringify(body)});
  return {status:r.status,data:await r.json()};
}
const rpc=(nombre,token,body={})=>peticion(`/rest/v1/rpc/${nombre}`,token,body);
async function login(key) {
  const r=await peticion('/auth/v1/token?grant_type=password',null,{email:USER_BY_KEY[key].email,password});
  assert.equal(r.status,200,`Auth ${key}`);
  return {token:r.data.access_token,id:r.data.user.id};
}
const gerente1=await login('gerencia'),gerente2=await login('gerencia');
const sup1=await login('sup2'),sup2=await login('sup2');
assert.equal(sup1.id,sup2.id); assert.ok(sup1.token!==sup2.token,'Deben ser dos sesiones distintas');
const evidencia=[];

// Representa una política publicada la víspera. Solo la preparación de datos
// del banco usa ese reloj; el trigger original se restituye en el MISMO COMMIT.
// Las llamadas HTTP siguientes usan exclusivamente el reloj real del servidor.
assert.equal(sql('select count(*)=1 and bool_and(version=1 and not cortes_activos) from crm.politica_gestion_diaria'),'t');
assert.equal(sql("select extract(isodow from now() at time zone 'America/Lima')<=6 and (now() at time zone 'America/Lima')::time >= time '11:30' and (now() at time zone 'America/Lima')::time < case when extract(isodow from now() at time zone 'America/Lima')=6 then time '12:50' else time '17:50' end"),'t','Ensayo real requiere ventana de cortes; no forzar el reloj del producto');
sql(`begin;
  select set_config('request.jwt.claim.sub',${q(gerente1.id)},true);
  do $fixture$ declare original text; reloj text; begin
    original:=pg_get_functiondef('private.trg_politica_gestion_diaria_insertar()'::regprocedure);
    reloj:=quote_literal(statement_timestamp()-interval '1 day')||'::timestamptz';
    if strpos(original,'statement_timestamp()')=0 then raise exception 'Falta ancla de reloj del fixture'; end if;
    execute replace(original,'statement_timestamp()',reloj);
    insert into crm.politica_gestion_diaria(version,version_anterior_id,vigente_desde,creado_en,creado_por,motivo,cortes_activos)
      select 2,id,((statement_timestamp() at time zone 'America/Lima')::date::timestamp at time zone 'America/Lima'),
        statement_timestamp()-interval '1 day',auth.uid(),'FIXTURE F4: política programada la víspera, solo banco sintético',true
      from crm.politica_gestion_diaria where version=1;
    execute original;
    perform private.assert_gestion_diaria();
  end $fixture$;
  commit;`);
evidencia.push('Fixture de política de la víspera; trigger original y gates restituidos dentro del mismo commit');

async function simultaneas(clase,objeto,trabajos) {
  const conexion=spawn('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{stdio:['pipe','pipe','pipe']});
  let salida='',fallo='';
  conexion.stdout.on('data',b=>{salida+=b.toString()});
  conexion.stderr.on('data',b=>{fallo+=b.toString()});
  const terminada=new Promise(resolve=>conexion.on('close',resolve));
  conexion.stdin.write(`set statement_timeout='15s'; set idle_in_transaction_session_timeout='15s'; begin; select pg_advisory_xact_lock(${clase},${objeto}); select 'BARRERA_LISTA';\n`);
  const limite=Date.now()+10_000;
  while(!salida.includes('BARRERA_LISTA') && Date.now()<limite && !fallo) await pausita(20);
  assert.ok(salida.includes('BARRERA_LISTA'),'No se pudo preparar barrera local');
  let promesa;
  try {
    promesa=Promise.allSettled(trabajos.map(t=>t()));
    let esperando=0;
    for(let i=0;i<30 && esperando<2;i++) {
      esperando=Number(sql(`select count(*) from pg_locks where locktype='advisory' and not granted
        and classid=${clase} and objid::bigint=((${objeto})::bigint+4294967296)%4294967296`));
      if(esperando<2) await pausita(50);
    }
    assert.equal(esperando,2,'Las dos solicitudes deben estar esperando el lock a la vez');
    evidencia.push(`Dos peticiones concurrentes observadas esperando el lock ${clase}`);
  } finally {
    conexion.stdin.end('commit;\n');
    assert.equal(await terminada,0,'Barrera terminada');
  }
  const resultados=await promesa;
  assert.ok(resultados.every(r=>r.status==='fulfilled'),'Solicitud HTTP interrumpida');
  return resultados.map(r=>r.value);
}

const config=await rpc('configuracion_gestion_diaria_fn',gerente1.token);
assert.equal(config.status,200);
const dia=sql("select to_char((now() at time zone 'America/Lima')::date+1,'YYYY-MM-DD')");
const publicar=token=>rpc('publicar_politica_gestion_diaria',token,{p_expected_version:2,
  p_vigente_desde:`${dia}T00:00:00-05:00`,p_config:{...config.data.vigente.configuracion,cortes_activos:false},
  p_motivo:'Fixture concurrente: cortes apagados desde mañana'});
const publicaciones=await simultaneas(194203,'43',[()=>publicar(gerente1.token),()=>publicar(gerente2.token)]);
assert.equal(publicaciones.filter(r=>r.status===200).length,1);
assert.equal(publicaciones.filter(r=>r.data.code==='40001').length,1);
assert.equal(sql('select count(*) from crm.politica_gestion_diaria'), '3');
evidencia.push('Dos publicaciones con la misma versión: una confirma y otra falla 40001; no se pisan');

const avisos=await rpc('gestion_diaria_avisos_fn',sup1.token);
assert.equal(avisos.status,200);
const aviso=avisos.data.alertas.find(a=>a.puede_presentar);
assert.ok(aviso,'Debe haber un corte real pendiente para el equipo sintético');
const id1=randomUUID(),id2=randomUUID();
const objeto=`hashtext(${q(sup1.id)})`;
const presentar=(token,id)=>rpc('gestion_diaria_presentar_corte',token,{p_alerta_id:aviso.id,p_solicitud_id:id});
const entregas=await simultaneas(194204,objeto,[()=>presentar(sup1.token,id1),()=>presentar(sup2.token,id2)]);
assert.ok(entregas.every(r=>r.status===200));
assert.equal(entregas.filter(r=>r.data.aviso!==null).length,1);
const ganador=entregas[0].data.aviso?{token:sup1.token,id:id1}:{token:sup2.token,id:id2};
assert.equal((await presentar(ganador.token,ganador.id)).data.aviso.id,aviso.id);
evidencia.push('Solo una sesión recibe la presentación; su reintento recupera la misma entrega');

const actuar=(token,id,accion)=>rpc('gestion_diaria_reconocer_corte',token,{p_alerta_id:aviso.id,p_solicitud_id:id,p_accion:accion});
const aplazamientos=await simultaneas(194204,objeto,[()=>actuar(sup1.token,randomUUID(),'posponer'),()=>actuar(sup2.token,randomUUID(),'posponer')]);
assert.equal(aplazamientos.filter(r=>r.status===200).length,1);
assert.equal(aplazamientos.filter(r=>r.data.code==='22023').length,1);
assert.equal(sql(`select count(*)=1 and bool_and(hasta-creado_en=interval '1 hour') from crm.alertas_reconocimientos
  where alerta_id=${q(aviso.id)} and accion='posponer'`),'t');
assert.equal((await rpc('gestion_diaria_avisos_fn',sup2.token)).data.alertas.find(a=>a.id===aviso.id).estado,'pospuesto');
assert.equal((await presentar(ganador.token,ganador.id)).data.aviso,null);
evidencia.push('Dos aplazamientos concurrentes: una sola fila de una hora, visible desde ambas sesiones; reintento no lo salta');
assert.equal((await actuar(sup2.token,randomUUID(),'reconocer')).status,200);
assert.equal((await rpc('gestion_diaria_avisos_fn',sup1.token)).data.alertas.find(a=>a.id===aviso.id).estado,'reconocido');
sql('select private.assert_gestion_diaria(); select private.assert_sla_nucleo(); select private.assert_sla_operacion(); select private.assert_sla_comandos(); select private.assert_sla_avisos();');
writeFileSync(archivo,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),evidencia,
  limites:'Banco sintético. Política fixture vigente hoy y OFF desde mañana; sin sustituir relojes de RPC ni eliminar historia.'},null,2)+'\n',{mode:0o600,flag:'wx'});
console.log('PASS: tres carreras HTTP reales con dos peticiones observadas esperando cada lock; publicación, presentación y aplazamiento únicos; reconocimiento entre sesiones');
