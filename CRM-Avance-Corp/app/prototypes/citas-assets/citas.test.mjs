import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import {JSDOM} from 'jsdom'
import {CITAS,EQUIPO,defaults,filtrar,ordenar,errorFiltros,agruparAnalistas,csv,CORTE} from './model.mjs'

test('el escenario separa las vencidas y las futuras usando la hora de Lima',()=>{
  assert.equal(CITAS.length,40)
  assert.equal(new Set(CITAS.map(c=>c.id)).size,40)
  for(const c of CITAS){
    const instante=Date.parse(`${c.fecha}T${c.hora}:00-05:00`)
    if(c.estado==='programada')assert.ok(instante>Date.parse(CORTE))
    else assert.ok(instante<Date.parse(CORTE))
    assert.ok(EQUIPO.some(p=>p.id===c.analista&&p.supervisor===c.supervisor))
  }
})
test('supervisor, estados y modalidad se cruzan y conservan los límites del filtro',()=>{
  const filas=filtrar({...defaults(),equipo:'Claudia Ríos',estados:['vencida','programada'],modalidad:'Virtual'})
  assert.deepEqual(filas.map(c=>c.nombre),['Patricia Montes','Carolina Ponce'])
  assert.equal(filtrar({...defaults(),equipo:'Claudia Ríos',analista:'diego'}).length,0)
})
test('búsqueda por nombre ignora tildes y el teléfono admite formato compacto',()=>{
  assert.equal(filtrar({...defaults(),q:'elena caceres'})[0].id,'C-2609-003')
  assert.equal(filtrar({...defaults(),q:'000000103'})[0].nombre,'Elena Cáceres')
  assert.equal(filtrar({...defaults(),q:'C-2609-003'}).length,1)
  assert.equal(filtrar({...defaults(),q:'persona que no existe'}).length,0)
})
test('rango inclusivo, hoy y fechas inválidas',()=>{
  const f={...defaults(),periodo:'custom',desde:'2026-09-07',hasta:'2026-09-07'}
  assert.equal(filtrar(f).length,3)
  assert.deepEqual(filtrar(f),filtrar({...defaults(),periodo:'hoy'}))
  assert.equal(filtrar({...f,desde:'2026-09-08'}).length,0)
  assert.match(errorFiltros({...f,desde:''}),/dos fechas/)
  assert.match(errorFiltros({...f,desde:'abc',hasta:'zzz'}),/fechas válidas/)
  assert.match(errorFiltros({...f,desde:'2026-02-31'}),/fechas válidas/)
  assert.ok(filtrar({...defaults(),periodo:'pasada'}).every(c=>c.fecha<='2026-09-06'))
  assert.equal(filtrar({...defaults(),periodo:'todos'}).length,40)
})
test('montos con límites inclusivos no mezclan monedas y validan errores',()=>{
  const filas=filtrar({...defaults(),moneda:'USD',min:'15000',max:'25000'})
  assert.ok(filas.length>0)
  assert.ok(filas.every(c=>c.moneda==='USD'&&c.monto>=15000&&c.monto<=25000))
  assert.equal(filtrar({...defaults(),moneda:'USD',min:'50000',max:'1'}).length,0)
  assert.match(errorFiltros({...defaults(),moneda:'PEN',min:'-1'}),/montos válidos/)
  assert.match(errorFiltros({...defaults(),moneda:'PEN',min:'Infinity'}),/montos válidos/)
})
test('resultado, origen y seguimiento nunca incorporan cierres no realizados',()=>{
  const filas=filtrar({...defaults(),seguimiento:'cerrado'})
  assert.equal(filas.length,4)
  assert.ok(filas.every(c=>c.estado==='realizada'&&c.cerrado))
  assert.ok(filtrar({...defaults(),seguimiento:'pendiente'}).every(c=>!c.cerrado&&c.estado==='realizada'))
  assert.ok(filtrar({...defaults(),origen:'Referido',resultado:'Interesado'}).every(c=>c.origen==='Referido'&&c.resultado==='Interesado'))
})
test('el desglose por analista reconcilia cada estado y el orden no muta datos',()=>{
  const base=filtrar({...defaults(),equipo:'Javier Vega'})
  const grupos=agruparAnalistas(base)
  assert.equal(grupos.reduce((s,p)=>s+p.total,0),base.length)
  for(const p of grupos)assert.equal(p.realizadas+p.vencidas+p.programadas+p.noShow+p.otras,p.total)
  const antes=base.map(c=>c.id)
  assert.equal(ordenar(base,'prioridad')[0].estado,'vencida')
  assert.deepEqual(base.map(c=>c.id),antes)
  const asc=ordenar(base,'fecha')
  assert.deepEqual(ordenar(base,'reciente'),[...asc].reverse())
  assert.equal(ordenar(base,'nombre')[0].nombre,'Alonso Medina')
})
test('CSV incluye todas las filas filtradas, escapa comillas y bloquea fórmulas',()=>{
  const filas=filtrar({...defaults(),estados:['realizada']})
  const salida=csv(filas)
  assert.equal(salida.split('\r\n').length,13)
  assert.match(salida,/Prospecto ficticio/)
  assert.ok(!salida.includes('C-2609-001'))
  const protegido=csv([{...filas[0],nombre:'=HYPERLINK("bad")'}])
  assert.ok(protegido.includes('"\'=HYPERLINK(""bad"")"'))
  assert.ok(csv([{...filas[0],nombre:' =1+1'}]).includes('"\' =1+1"'))
})

test('interfaz: filtros compartidos, paginación, errores, limpieza y teclado',async()=>{
  const html=await readFile(new URL('../citas-gerencia.html',import.meta.url),'utf8')
  const dom=new JSDOM(html,{url:'http://localhost/citas-gerencia.html'})
  const style=dom.window.document.createElement('style')
  style.textContent=await readFile(new URL('./citas.css',import.meta.url),'utf8')
  dom.window.document.head.append(style)
  globalThis.document=dom.window.document
  const $=id=>document.getElementById(id)
  dom.window.HTMLElement.prototype.scrollIntoView=function(){}
  // JSDOM no implementa la capa modal del navegador. Este doble solo permite
  // verificar contenido y navegación; foco, bloqueo del fondo y Escape se
  // comprueban por separado en Chrome con el diálogo nativo.
  dom.window.HTMLDialogElement.prototype.showModal=function(){this.open=true}
  dom.window.HTMLDialogElement.prototype.close=function(){this.open=false}
  await import('./citas.js')
  const cambiar=(id,value)=>{$(id).value=value;$(id).dispatchEvent(new dom.window.Event('input',{bubbles:true}))}
  const click=selector=>document.querySelector(selector).click()
  assert.match($('result-count').textContent,/40 de 40/)
  click('[data-page="1"]')
  assert.match($('pagination').textContent,/9–16/)
  cambiar('equipo','Claudia Ríos')
  assert.match($('pagination').textContent,/1–8/)
  cambiar('analista','ana')
  cambiar('equipo','Javier Vega')
  assert.equal($('analista').value,'')
  assert.equal($('analista').querySelector('[value="ana"]').disabled,true)
  click('[data-quick="vencida"]')
  assert.match($('result-count').textContent,/3 de 40/)
  click('[data-view="agenda"]')
  assert.equal(document.querySelectorAll('.event').length,3)
  assert.equal(dom.window.getComputedStyle($('pagination')).display,'none')
  assert.equal(dom.window.getComputedStyle($('sort').parentElement).display,'none')
  click('[data-view="resultados"]')
  assert.equal(document.querySelectorAll('.results-table tbody tr').length,3)
  click('[data-analyst="diego"]')
  assert.equal($('tab-bandeja').getAttribute('aria-selected'),'true')
  assert.match($('result-count').textContent,/1 de 40/)
  cambiar('moneda','USD');cambiar('min','50000');cambiar('max','1')
  assert.equal($('filter-error').hidden,false)
  assert.match($('min').getAttribute('aria-describedby'),/filter-error/)
  assert.equal($('export').disabled,true)
  assert.match($('stats').textContent,/—/)
  assert.match($('quick-filters').textContent,/—/)
  cambiar('moneda','PEN')
  assert.equal($('min').value,'')
  assert.equal($('max').value,'')
  cambiar('search','<img src=x onerror=alert(1)>')
  assert.match($('view-panel').textContent,/No hay citas/)
  assert.equal($('chips').querySelector('[onerror]'),null)
  click('#clear')
  assert.equal($('min').disabled,true)
  assert.match($('result-count').textContent,/40 de 40/)
  $('tab-bandeja').dispatchEvent(new dom.window.KeyboardEvent('keydown',{key:'ArrowRight',bubbles:true}))
  assert.equal($('tab-agenda').getAttribute('aria-selected'),'true')
  assert.equal(document.activeElement,$('tab-agenda'))
  click('#clear')
  const checks=[...document.querySelectorAll('[name=estados]')].slice(0,2)
  for(const c of checks){c.checked=true;c.dispatchEvent(new dom.window.Event('input',{bubbles:true}))}
  assert.match($('result-count').textContent,/16 de 40/)
  click('[data-quick="realizada"]')
  assert.equal(document.querySelectorAll('[name=estados]:checked').length,1)
  click('#clear')
  const nombreOriginal=EQUIPO[0].nombre
  EQUIPO[0].nombre='<img data-untrusted="1"> & Asesor'
  const original={...CITAS[0]}
  Object.assign(CITAS[0],{nombre:'<img data-untrusted="1"> & Prospecto',resultado:'<img data-untrusted="1">',nota:'<img data-untrusted="1">'})
  for(const view of ['bandeja','agenda','resultados']){
    click(`[data-view="${view}"]`)
    assert.equal(document.querySelector('[data-untrusted]'),null)
    assert.ok($('view-panel').textContent.includes('<img data-untrusted="1"> & Asesor'))
  }
  click('[data-view="bandeja"]')
  click('[data-detail="C-2609-001"]')
  assert.equal($('detail').open,true)
  assert.equal(document.querySelector('[data-untrusted]'),null)
  assert.match($('detail-content').textContent,/& Prospecto/)
  click('[data-agenda="C-2609-001"]')
  assert.equal($('detail').open,false)
  assert.equal($('tab-agenda').getAttribute('aria-selected'),'true')
  assert.match($('result-count').textContent,/1 de 40/)
  // La rama de citas realizadas muestra el resultado dentro del contexto.
  CITAS[0].estado='realizada'
  click('[data-detail="C-2609-001"]')
  assert.equal(document.querySelector('[data-untrusted]'),null)
  assert.ok(document.querySelector('.drawer-callout').textContent.includes('<img data-untrusted="1">'))
  click('[data-close="detail"]')
  Object.assign(CITAS[0],original);EQUIPO[0].nombre=nombreOriginal
  dom.window.close()
  delete globalThis.document
})

test('todos los recursos locales referidos existen',async()=>{
  const html=await readFile(new URL('../citas-gerencia.html',import.meta.url),'utf8')
  for(const match of html.matchAll(/(?:src|href)="\.\/citas-assets\/([^"]+)"/g)) await readFile(new URL(match[1],import.meta.url))
})
