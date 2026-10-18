import test from 'node:test'
import assert from 'node:assert/strict'
import { seleccionarPendientes, exigirRevisionRechazos, operacionesFase6, conciliarFotografia, verificarFase6, restaurarRetencion, cargarDefinicionOperativa } from './formulario3.fase6.mjs'
import { cargarDefinicion, WORKFLOW_ID } from './formulario3.workflow.mjs'
import { operacionesFase5 } from './formulario3.fase5.mjs'
import { conciliarRespuesta, pendienteDeFila, resumirImportacion, prepararFila, COLUMNAS } from './formulario3.mjs'

const fila = i => ({ json:{fila:i+2,huella:i.toString(16).padStart(64,'0'),campania:'Formulario 3',mapeo_correcto:true,payload:{filas:[{fila:i+2,campania_origen:'Formulario 3',canal:'FORMULARIO'}]}} })
function aplicar(w,ops) {
  const copia=JSON.parse(JSON.stringify(w))
  for(const op of ops) {
    if(op.type==='setWorkflowSettings') {copia.settings={...op.settings};continue}
    const n=copia.nodes.find(n=>n.name===op.nodeName)
    if(op.parameters)Object.assign(n.parameters,op.parameters)
    if('disabled' in op)n.disabled=op.disabled
  }
  return copia
}
const nuevo=()=>structuredClone({...cargarDefinicion(),id:WORKFLOW_ID,active:false,activeVersionId:null})

test('el generador operativo reproduce fase 6 sin publicar ni mutar el canon histórico',()=>{
  const antes=JSON.stringify(cargarDefinicion())
  const w=cargarDefinicionOperativa()
  assert.ok(verificarFase6(w,{enviar:true,programar:true}))
  assert.equal(w.active,false)
  assert.equal(w.settings.saveDataSuccessExecution,'none')
  assert.equal(JSON.stringify(cargarDefinicion()),antes)
})

test('limita a 25 huellas únicas y conserva enlaces incluso con filas repetidas',()=>{
  const items=Array.from({length:128},(_,i)=>fila(i))
  items.splice(3,0,items[1])
  const originales=JSON.stringify(items)
  for(const hora of [0,300000,600000,1792044000000]) {
    const lote=seleccionarPendientes(items,hora)
    assert.equal(lote.length,25)
    assert.equal(new Set(lote.map(i=>i.json.huella)).size,25)
    for(const i of lote)assert.equal(items[i.pairedItem.item].json.huella,i.json.huella)
  }
  assert.equal(JSON.stringify(items),originales)
  assert.deepEqual(seleccionarPendientes([],0),[])
  const mal=fila(1);mal.json.payload.filas[0].canal='LANDING'
  assert.throws(()=>seleccionarPendientes([mal],0))
})
test('restituye toda la preparación tras fase5, sin cambiar credenciales, grafo ni recibos',()=>{
  const base=nuevo(),f5=aplicar(base,operacionesFase5(base,{fila:2}))
  const ops=operacionesFase6(f5)
  const f6=aplicar(f5,ops)
  assert.equal(f6.nodes.find(n=>n.name==='Preparar leads').parameters.jsCode,base.nodes.find(n=>n.name==='Preparar leads').parameters.jsCode)
  assert.doesNotMatch(f6.nodes.find(n=>n.name==='Control del envío').parameters.jsonOutput,/fila_objetivo|huella_objetivo/)
  assert.match(f6.nodes.find(n=>n.name==='Control del envío').parameters.jsonOutput,/enviar_crm:false,simular_registro:true/)
  assert.deepEqual(f6.connections,base.connections)
  assert.deepEqual(f6.nodes.map(n=>n.credentials),base.nodes.map(n=>n.credentials))
  assert.ok(f6.nodes.find(n=>n.name==='Cada 5 minutos').disabled)
  assert.ok(f6.nodes.find(n=>n.name==='Importar en CRM').disabled)
  assert.doesNotThrow(()=>operacionesFase6(f6,{enviar:true}))
  const publicar=aplicar(f6,operacionesFase6(f6,{enviar:true,programar:true,guardarExitos:true}))
  assert.equal(publicar.nodes.find(n=>n.name==='Cada 5 minutos').disabled,false)
  assert.equal(publicar.nodes.find(n=>n.name==='Importar en CRM').disabled,false)
  assert.equal(publicar.settings.saveDataSuccessExecution,'all')
  assert.equal(publicar.settings.errorWorkflow,'4jfthNhVJLiZUeIo')
  assert.equal(publicar.settings.executionTimeout,180)
  assert.equal(publicar.settings.saveDataErrorExecution,'all')
  assert.ok(verificarFase6(publicar,{enviar:true,programar:true,guardarExitos:true}))
})
test('la transición rechaza código ajeno, publicación activa y cambios en destino o intervalo',()=>{
  for(const cambiar of [
    w=>{w.active=true},
    w=>{w.activeVersionId='publicado'},
    w=>{w.nodes.find(n=>n.name==='Preparar leads').parameters.jsCode+='\nreturn []'},
    w=>{w.nodes.find(n=>n.name==='Importar en CRM').parameters.url='https://otro.invalid'},
    w=>{w.nodes.find(n=>n.name==='Cada 5 minutos').parameters.rule.interval[0].minutesInterval=1},
  ]) {const w=nuevo();cambiar(w);assert.throws(()=>operacionesFase6(w))}
  assert.throws(()=>operacionesFase6(nuevo(),{programar:true}))
  const w=nuevo();delete w.nodes.find(n=>n.name==='Importar en CRM').parameters.contentType
  delete w.nodes.find(n=>n.name==='Cada 5 minutos').parameters.rule.interval[0].minutesInterval
  assert.doesNotThrow(()=>operacionesFase6(w))
})
test('rechaza desactivar confirmaciones, errores silenciados, cambios de modo, columnas y credenciales',()=>{
  for(const cambiar of [
    w=>{w.nodes.find(n=>n.name==='Registrar resultado').disabled=true},
    w=>{w.nodes.find(n=>n.name==='Omitir filas confirmadas').disabled=true},
    w=>{w.nodes.find(n=>n.name==='Resumen de importación').onError='continueRegularOutput'},
    w=>{w.nodes.find(n=>n.name==='Seleccionar lote rotativo').parameters.mode='runOnceForEachItem'},
    w=>{w.nodes.find(n=>n.name==='Registrar resultado').parameters.columns={}},
    w=>{w.nodes.find(n=>n.name==='Leer leads filtrados').credentials.googleSheetsOAuth2Api.id='otra'},
    w=>{w.settings.errorWorkflow='otro'},
    w=>{w.settings.executionTimeout=600},
    w=>{w.nodes.find(n=>n.name==='Tiempo disponible').parameters.conditions.conditions[0].leftValue='={{ true }}'},
  ]) {const w=nuevo();cambiar(w);assert.throws(()=>operacionesFase6(w))}
})
test('la retención final exige la versión activa comprobada y solo cambia ajustes',()=>{
  const w=nuevo(),preparado=aplicar(w,operacionesFase6(w,{enviar:true,programar:true,guardarExitos:true}))
  const activo={...preparado,active:true,versionId:'verificada',activeVersionId:'verificada'}
  const ops=restaurarRetencion(activo,'verificada')
  assert.equal(ops.length,1)
  const final=aplicar(activo,ops)
  assert.deepEqual(final.nodes,activo.nodes)
  assert.deepEqual(final.connections,activo.connections)
  assert.ok(verificarFase6(final,{enviar:true,programar:true,guardarExitos:false}))
  assert.throws(()=>restaurarRetencion(activo,'anterior'))
  const silencioso=structuredClone(activo);delete silencioso.settings.errorWorkflow
  assert.throws(()=>verificarFase6(silencioso,{enviar:true,programar:true,guardarExitos:true}))
})
test('inválidos se dirigen a revisión antes del HTTP y cada recibo se escribe dentro del bucle',()=>{
  const w=nuevo(),a=w.connections
  assert.ok(a.some(c=>c.source==='Datos válidos'&&c.sourceIndex===0&&c.target==='Importar en CRM'))
  assert.ok(a.some(c=>c.source==='Datos válidos'&&c.sourceIndex===1&&c.target==='Marcar para revisión'))
  assert.ok(a.some(c=>c.source==='Preparar recibo'&&c.target==='Registrar resultado'))
  assert.ok(a.some(c=>c.source==='Registrar resultado'&&c.target==='Conservar recibo'))
  assert.ok(a.some(c=>c.source==='Conservar recibo'&&c.target==='Procesar de una en una'))
  const invalido=fila(1);invalido.json.mapeo_correcto=false
  assert.equal(seleccionarPendientes([invalido],0)[0].json.mapeo_correcto,false)
  const real=prepararFila({row_number:2,[COLUMNAS.nombre]:'PERSONA SINTÉTICA',[COLUMNAS.telefono]:'999000111',[COLUMNAS.moneda]:'soles',[COLUMNAS.capital]:'capital desconocido'})
  real.huella='a'.repeat(64)
  assert.equal(real.mapeo_correcto,false)
  assert.equal(seleccionarPendientes([{json:real}],0).length,1)
})
test('el gate posterior detecta código no aplicado y cubre todo el código piloto',()=>{
  const w=nuevo(),ops=operacionesFase6(w,{enviar:true})
  for(const op of operacionesFase5(w,{fila:2}).filter(op=>op.parameters?.jsCode))assert.ok(ops.some(x=>x.nodeName===op.nodeName&&x.parameters?.jsCode))
  for(const nombre of ['Seleccionar lote rotativo','Resumen de importación']){
    const incompleto=aplicar(w,ops)
    incompleto.nodes.find(n=>n.name===nombre).parameters.jsCode=w.nodes.find(n=>n.name===nombre).parameters.jsCode
    assert.throws(()=>verificarFase6(incompleto,{enviar:true}))
  }
})
test('un fallo intermedio no confirma esa fila ni impide conciliar las demás',()=>{
  const filas=[fila(0).json,fila(1).json,fila(2).json]
  const recibos=[],resultados=[]
  for(const [i,f] of filas.entries()) {
    try {const r=conciliarRespuesta(i===1?{}:{resultados:[{fila:f.fila,resultado:'importado',estado:'IMPORTADO'}]},f);recibos.push(r);resultados.push(r)}
    catch {resultados.push(pendienteDeFila(f))}
  }
  assert.equal(recibos.length,2)
  assert.throws(()=>resumirImportacion(resultados,false),/pendientes/)
  assert.deepEqual(conciliarFotografia(filas,recibos).conteos,{importado:2,pendiente:1})
})
test('conciliación cuenta filas, comparte recibo de huella repetida y reconoce una edición pendiente',()=>{
  const a=fila(0).json,b={...a,fila:20},c={...a,fila:21,huella:'f'.repeat(64)}
  const r={...conciliarRespuesta({resultados:[{fila:a.fila,resultado:'importado',estado:'IMPORTADO'}]},a)}
  assert.deepEqual(conciliarFotografia([a,b,c],[r]).conteos,{importado:2,pendiente:1})
  assert.equal(conciliarFotografia([a,b,c],[r]).huellas_unicas,2)
  assert.throws(()=>conciliarFotografia([a],[r,r]))
  assert.deepEqual(conciliarFotografia([c],[r]).recibos_sin_fila,[{fila:2,resultado:'importado'}])
  assert.throws(()=>conciliarFotografia([{...a,huella:'mal'}],[r]))
})
test('un rechazo conserva su recibo definitivo y genera error sin incluir datos de contacto',()=>{
  const f=fila(0).json
  const r=conciliarRespuesta({resultados:[{fila:f.fila,resultado:'rechazado',estado:'Detalle privado'}]},f)
  assert.equal(conciliarFotografia([f],[r]).conteos.rechazado,1)
  assert.throws(()=>exigirRevisionRechazos(resumirImportacion([r],false),[r]),e=>/Filas rechazadas/.test(e.message)&&!e.message.includes('Detalle privado'))
  const ok={fila:3,resultado:'duplicado'}
  assert.equal(exigirRevisionRechazos(resumirImportacion([ok],false),[ok]).resultados.duplicado,1)
})
