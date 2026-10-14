// Exclusivamente banco propio. Credenciales públicas sintéticas, nunca reutilizar fuera del banco.
import assert from 'node:assert/strict'
import {createHash,createHmac} from 'node:crypto'
import {spawn,spawnSync} from 'node:child_process'
const endpoint='http://127.0.0.1:55484'
const id=nombre=>{const x=createHash('md5').update(nombre).digest('hex');return `${x.slice(0,8)}-${x.slice(8,12)}-${x.slice(12,16)}-${x.slice(16,20)}-${x.slice(20)}`}
const g=id('AV GERENCIA'),admin=id('AV ADMIN PORTAL'),a=id('AV FIORELLA'),b=id('AV JORGE'),cli=id('AV CLIENTE'),venta=id('AV 001595')
const jwt=sub=>{const base=x=>Buffer.from(JSON.stringify(x)).toString('base64url');const raw=base({alg:'HS256',typ:'JWT'})+'.'+base({sub,role:'authenticated',exp:Math.floor(Date.now()/1000)+600});return raw+'.'+createHmac('sha256','solo-banco-atencion-secreto-sintetico-20261013').update(raw).digest('base64url')}
async function rpc(nombre,cuerpo,actor=g){const r=await fetch(`${endpoint}/rpc/${nombre}`,{method:'POST',signal:AbortSignal.timeout(8000),headers:{'Content-Type':'application/json','Content-Profile':'crm',...(actor?{Authorization:`Bearer ${jwt(actor)}`}:{})},body:JSON.stringify(cuerpo)});return {status:r.status,data:await r.json()}}
const psql='/opt/homebrew/opt/postgresql@17/bin/psql'
const base=['-h','127.0.0.1','-p','55483','-U','postgres','-d','atencion_http','-v','ON_ERROR_STOP=1','-qAt']
const opts={env:{...process.env,PGPASSWORD:'postgres'},encoding:'utf8'}
const preparar=spawnSync(psql,[...base,'-c',`select set_config('request.jwt.claim.sub','${g}',false);do $$ begin if (select analista_cierre_id from public.contratos where id='${venta}') is distinct from '${a}'::uuid then perform public.reasignar_analista_contrato('${venta}','${a}','Restablecer fixture sintético HTTP');end if;end $$;`],opts);assert.equal(preparar.status,0,preparar.stderr)
const baseline=Number(spawnSync(psql,[...base,'-c','select count(*) from crm.reasignaciones_analista'],opts).stdout.trim())
const args={p_accion:'venta',p_id:venta,p_destino:b}
let pre=await rpc('previsualizar_cambio_responsabilidad_fn',args);assert.equal(pre.status,200,JSON.stringify(pre));assert.equal(pre.data.efectos[0].monto,150000)
assert.equal((await rpc('previsualizar_cambio_responsabilidad_fn',args,a)).status,403)
assert.equal((await rpc('previsualizar_cambio_responsabilidad_fn',args,null)).status,401)
const direct=await fetch(`${endpoint}/perfiles?id=eq.${cli}`,{method:'PATCH',headers:{Authorization:`Bearer ${jwt(admin)}`,'Content-Type':'application/json'},body:JSON.stringify({asesor_perfil_id:null})});assert.equal(direct.status,403,await direct.text())
// Dos conexiones reales: A retiene la venta; la puerta B debe fallar sin historial.
const holder=spawn(psql,base,opts)
holder.stdin.write(`begin;set application_name='atencion_holder';select 1 from public.contratos where id='${venta}' for update;\n`)
let lista=false
for(let n=0;n<40;n++){
  const state=spawnSync(psql,[...base,'-c',"select state from pg_stat_activity where application_name='atencion_holder'"],opts)
  if(state.stdout.trim()==='idle in transaction'){lista=true;break}
  await new Promise(resolve=>setTimeout(resolve,50))
}
assert.equal(lista,true,'La conexión A debe conservar el candado antes de llamar a B')
let r=await rpc('confirmar_cambio_responsabilidad_fn',{...args,p_motivo:'Corrección simultánea',p_version:pre.data.version});assert.equal(r.data.code,'PT409',JSON.stringify(r))
holder.stdin.end('rollback;\n')
await new Promise((resolve,reject)=>{holder.once('exit',code=>code===0?resolve():reject(Error('Holder falló')))})
const count=spawnSync(psql,[...base,'-c','select count(*) from crm.reasignaciones_analista'],opts);assert.equal(Number(count.stdout.trim()),baseline)
pre=await rpc('previsualizar_cambio_responsabilidad_fn',args)
// Dos confirmaciones simultáneas: exactamente una escribe y una queda obsoleta/bloqueada.
const body={...args,p_motivo:'Corrección confirmada por HTTP',p_version:pre.data.version}
const results=await Promise.all([rpc('confirmar_cambio_responsabilidad_fn',body),rpc('confirmar_cambio_responsabilidad_fn',body)])
assert.equal(results.filter(x=>x.status===200).length,1,JSON.stringify(results))
assert.equal(results.filter(x=>x.data.code==='PT409').length,1,JSON.stringify(results))
const state=spawnSync(psql,[...base,'-c',`select count(*) from crm.reasignaciones_analista;select capital from public.contratos where id='${venta}';`],opts)
assert.deepEqual(state.stdout.trim().split('\n'),[String(baseline+1),'150000.00'])
const atencion={p_accion:'atencion_cliente',p_id:cli,p_destino:b}
pre=await rpc('previsualizar_cambio_responsabilidad_fn',atencion,admin);assert.equal(pre.status,200)
r=await rpc('confirmar_cambio_responsabilidad_fn',{...atencion,p_motivo:'Atención completa desde portal',p_version:pre.data.version},admin);assert.equal(r.status,200,JSON.stringify(r))
console.log('PASS HTTP: preview; vendedor y anon denegados; admin UPDATE directo bloqueado; conflicto entre sesiones; dos confirmaciones/un historial; capital conservado; admin portal atención completa.')
