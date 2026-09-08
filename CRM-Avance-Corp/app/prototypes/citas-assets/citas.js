import { CITAS, EQUIPO, ESTADOS, defaults, rango, fechaValida, errorFiltros, filtrar, ordenar, agruparAnalistas, csv } from './model.mjs'

const $ = (id) => document.getElementById(id)
const escape = (s) => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))
const icon = (name) => `<img src="./citas-assets/${name}.svg" alt="">`
const fecha = (value, largo = false) => new Intl.DateTimeFormat('es-PE', {day:'numeric',month:largo ? 'long' : 'short', timeZone:'America/Lima'}).format(new Date(`${value}T12:00:00-05:00`))
const fechaCompleta = (value) => new Intl.DateTimeFormat('es-PE', {day:'numeric',month:'short',year:'numeric',timeZone:'America/Lima'}).format(new Date(`${value}T12:00:00-05:00`))
const dinero = (c) => `${c.moneda === 'PEN' ? 'S/' : 'US$'} ${new Intl.NumberFormat('es-PE').format(c.monto)}`
const persona = (c) => EQUIPO.find(p => p.id === c.analista)
const iniciales = (nombre) => nombre.split(' ').map(n => n[0]).slice(0,2).join('')
const badge = (c) => `<span class="badge ${c.estado}">${icon(ESTADOS[c.estado].icon)}${ESTADOS[c.estado].label}</span>`
const proximo = (c) => c.cerrado ? 'Cierre registrado' : ESTADOS[c.estado].next
const contexto = (c) => c.cerrado ? 'Cierre posterior a la cita' : c.estado === 'vencida' ? 'Resultado aún no registrado' : c.estado === 'programada' ? 'Cita por realizar' : c.nuevaFecha ? `Nueva fecha: ${fecha(c.nuevaFecha)}` : c.estado === 'realizada' ? c.resultado : 'Ver contexto en el detalle'
let filtros = defaults()
let vista = 'bandeja'
let pagina = 1
const TAMANO = 8
let visibles = []
let toastTimer
let anuncioTimer
const textoSiCambia = (el, text) => { if(el.textContent !== text) el.textContent = text }

function opciones(id, valores) {
  $(id).insertAdjacentHTML('beforeend', valores.map(v => `<option value="${escape(typeof v === 'string' ? v : v.id)}">${escape(typeof v === 'string' ? v : v.nombre)}</option>`).join(''))
}
opciones('equipo', [...new Set(EQUIPO.map(p => p.supervisor))])
opciones('analista', EQUIPO)
opciones('origen', [...new Set(CITAS.map(c => c.origen))].sort())
opciones('resultado', [...new Set(CITAS.map(c => c.resultado))].sort())
$('status-options').innerHTML = Object.entries(ESTADOS).map(([k,v]) => `<label><input type="checkbox" name="estados" value="${k}">${v.label}</label>`).join('')

function sincronizar() {
  for (const [key,value] of Object.entries(filtros)) {
    const control = $('filters').elements.namedItem(key)
    if (control && key !== 'estados' && control.value !== value) control.value = value
  }
  $('sort').value = filtros.sort
  document.querySelectorAll('[name=estados]').forEach(c => { c.checked = filtros.estados.includes(c.value) })
  for (const option of $('analista').options) {
    const p = EQUIPO.find(p => p.id === option.value)
    option.disabled = !!(p && filtros.equipo && p.supervisor !== filtros.equipo)
  }
  $('custom-dates').hidden = filtros.periodo !== 'custom'
  $('min').disabled = $('max').disabled = !filtros.moneda
}

function chips() {
  const activos = []
  if (filtros.q) activos.push(['q', `Búsqueda: ${filtros.q}`])
  if (filtros.equipo) activos.push(['equipo', `Equipo: ${filtros.equipo}`])
  if (filtros.analista) activos.push(['analista', `Analista: ${EQUIPO.find(p=>p.id===filtros.analista)?.nombre}`])
  filtros.estados.forEach(e => activos.push([`estado:${e}`, ESTADOS[e].label]))
  for (const [key,label] of [['modalidad','Modalidad'],['origen','Origen'],['resultado','Resultado']]) if (filtros[key]) activos.push([key,`${label}: ${filtros[key]}`])
  if (filtros.seguimiento) activos.push(['seguimiento', $('seguimiento').selectedOptions[0].textContent])
  if (filtros.moneda) activos.push(['moneda', filtros.moneda === 'PEN' ? 'Soles' : 'Dólares'])
  if (filtros.min !== '') activos.push(['min', `Desde ${filtros.min} ${filtros.moneda}`])
  if (filtros.max !== '') activos.push(['max', `Hasta ${filtros.max} ${filtros.moneda}`])
  $('chips').innerHTML = activos.map(([key,label])=>`<button class="chip" data-remove="${key}" aria-label="Quitar ${escape(label)}">${escape(label)}${icon('x')}</button>`).join('')
  const n = activos.filter(([k])=>!['q','equipo','analista'].includes(k)).length
  $('more-label').textContent = n ? `Más filtros · ${n} ${n===1?'activo':'activos'}` : 'Más filtros'
  const [desde,hasta] = rango(filtros)
  $('scope').textContent = fechaValida(desde) && fechaValida(hasta) ? `${fechaCompleta(desde)} – ${fechaCompleta(hasta)} · fecha prevista` : filtros.periodo === 'todos' ? 'Todas las fechas del ejemplo' : 'Completa el rango de fechas'
}

function stats(error) {
  const counts = [
    ['Citas en tu consulta', visibles.length, 'list', '', 'Cada registro representa una cita'],
    ['Vencidas sin resultado', visibles.filter(c=>c.estado==='vencida').length, 'circle-alert', 'warning', 'Requieren registrar qué ocurrió'],
    ['Programadas', visibles.filter(c=>c.estado==='programada').length, 'calendar-clock', '', 'Por realizar, dentro de tu consulta'],
    ['Realizadas', visibles.filter(c=>c.estado==='realizada').length, 'circle-check', 'success', 'Con resultado registrado'],
  ]
  $('stats').innerHTML = counts.map(([label,n,img,tone,note])=>`<div class="stat ${tone}"><div class="stat-top">${icon(img)}${label}</div><div class="stat-number">${error ? '—' : n}<small>${n === 1 && !error ? 'cita' : 'citas'}</small></div><p class="stat-note">${error ? 'Corrige la consulta para ver el total' : note}</p></div>`).join('')
}

function quickFilters(error) {
  const base = filtrar({...filtros,estados:[]})
  const grupos = [['','Todas'],['vencida','Sin resultado'],['programada','Programadas'],['realizada','Realizadas'],['no_show','No asistieron']]
  $('quick-filters').innerHTML = '<span class="quick-label">Ver por estado</span>' + grupos.map(([k,label]) => {
    const n = k ? base.filter(c=>c.estado===k).length : base.length
    const activo = k ? filtros.estados.length === 1 && filtros.estados[0] === k : !filtros.estados.length
    return `<button class="quick-filter" data-quick="${k}" aria-pressed="${activo}">${label}<span>${error ? '—' : n}</span></button>`
  }).join('')
}

function fila(c) {
  const p = persona(c)
  return `<tr class="${c.estado === 'vencida' ? 'urgent' : ''}">
    <td><button class="name-button" data-detail="${escape(c.id)}">${escape(c.nombre)}</button><span class="subline">${escape(c.id)} · ${escape(c.origen)}</span></td>
    <td><span class="date-main">${fecha(c.fecha)}</span><span class="subline time">${escape(c.hora)} · ${escape(c.modalidad)}</span></td>
    <td><div class="person"><span class="avatar" aria-hidden="true">${escape(iniciales(p.nombre))}</span><div><span class="owner-name">${escape(p.nombre)}</span><span class="subline">${escape(p.supervisor)}</span></div></div></td>
    <td>${badge(c)}<span class="subline">${escape(c.estado==='realizada' ? c.resultado : contexto(c))}</span></td>
    <td><div class="next-line"><div><strong>${escape(proximo(c))}</strong><span class="subline">${escape(dinero(c))} estimados</span></div><button class="row-open" data-detail="${escape(c.id)}" aria-label="Ver detalle de ${escape(c.nombre)}">${icon('chevron-right')}</button></div></td>
  </tr>`
}
function card(c) {
  const p = persona(c)
  return `<article class="cita-card ${c.estado === 'vencida' ? 'urgent' : ''}"><div class="card-top"><span>${fecha(c.fecha)} · ${escape(c.hora)}</span>${badge(c)}</div><button class="name-button" data-detail="${escape(c.id)}">${escape(c.nombre)}</button><div class="card-meta"><span>${escape(c.modalidad)}</span><span>${escape(c.origen)}</span><span>${escape(dinero(c))} estimados</span></div><p class="card-owner">${escape(p.nombre)} <span class="subline">Equipo de ${escape(p.supervisor)}</span></p><div class="card-bottom"><div><p>${escape(proximo(c))}</p><span class="subline">${escape(c.id)}</span></div><button class="button" data-detail="${escape(c.id)}" aria-label="Ver detalle de ${escape(c.nombre)}">Ver detalle ${icon('chevron-right')}</button></div></article>`
}
function bandeja() {
  const paginaFilas = visibles.slice((pagina-1)*TAMANO,pagina*TAMANO)
  return `<div class="table-scroll desktop-list"><table class="citas-table"><caption class="sr-only">Citas ficticias que coinciden con la consulta. Todas las horas son de Lima.</caption><thead><tr><th class="prospect" scope="col">Prospecto / origen</th><th class="date" scope="col">Fecha prevista</th><th class="owner" scope="col">Analista / supervisor</th><th class="status" scope="col">Estado de la cita</th><th class="action" scope="col">Siguiente paso</th></tr></thead><tbody>${paginaFilas.map(fila).join('')}</tbody></table></div><div class="mobile-cards">${paginaFilas.map(card).join('')}</div>`
}
function agenda() {
  const ordenadas = ordenar(visibles,'fecha')
  const dias = [...new Set(ordenadas.map(c=>c.fecha))]
  return `<div class="day-list">${dias.map(dia=>{
    const citas = ordenadas.filter(c=>c.fecha===dia)
    return `<section class="day-group"><h3 class="day-heading">${fecha(dia,true)}<small>${dia==='2026-09-07' ? 'Hoy en el ejemplo · ' : ''}${citas.length} ${citas.length===1?'cita':'citas'}</small></h3><div class="day-events">${citas.map(c=>`<article class="event"><div class="event-top"><strong class="time">${escape(c.hora)} · ${escape(c.modalidad)}</strong>${badge(c)}</div><button class="name-button" data-detail="${escape(c.id)}">${escape(c.nombre)}</button><p class="subline">${escape(c.origen)} · ${escape(dinero(c))} estimados</p><div class="event-bottom"><span>${escape(persona(c).nombre)}</span><button class="row-open" data-detail="${escape(c.id)}" aria-label="Ver detalle de ${escape(c.nombre)}">${icon('chevron-right')}</button></div></article>`).join('')}</div></section>`
  }).join('')}</div>`
}
function resultados() {
  const personas = agruparAnalistas(visibles)
  const total = (campo) => personas.reduce((s,p)=>s+p[campo],0)
  return `<div class="insights"><p class="insights-note">Solo citas que cumplen los filtros. Selecciona un analista para abrir su bandeja. «Otras» reúne reprogramadas y canceladas.</p><div class="table-scroll" tabindex="0" role="region" aria-label="Resultados por analista, tabla desplazable"><table class="citas-table results-table"><caption class="sr-only">Conteos por analista de las citas filtradas. Se ordenan por pendientes sin resultado, luego por realizadas.</caption><thead><tr><th scope="col">Analista / equipo</th><th scope="col">Citas</th><th scope="col">Realizadas</th><th scope="col">Sin resultado</th><th scope="col">Programadas</th><th scope="col">No asistió</th><th scope="col">Otras</th></tr></thead><tbody>${personas.map(p=>`<tr><th scope="row"><button class="name-button" data-analyst="${p.id}">${escape(p.nombre)}</button><span class="subline">${escape(p.supervisor)}</span></th><td><strong>${p.total}</strong></td><td>${p.realizadas}</td><td style="color:${p.vencidas?'var(--red)':'inherit'}"><strong>${p.vencidas}</strong></td><td>${p.programadas}</td><td>${p.noShow}</td><td>${p.otras}</td></tr>`).join('')}</tbody><tfoot><tr><th scope="row">Total de tu consulta</th>${['total','realizadas','vencidas','programadas','noShow','otras'].map(k=>`<td>${total(k)}</td>`).join('')}</tr></tfoot></table></div><p class="field-help" style="padding:10px 14px 0">Esta propuesta muestra conteos de ejemplo. La realización y la asistencia del CRM conservarán sus bases comerciales actuales.</p></div>`
}

function render(retrasarAviso=false) {
  const error = errorFiltros(filtros) || (['min','max'].some(id=>$(id).validity.badInput) ? 'Introduce montos válidos, iguales o mayores que cero.' : '')
  visibles = error ? [] : ordenar(filtrar(filtros), filtros.sort)
  pagina = Math.max(1,Math.min(pagina,Math.ceil(visibles.length/TAMANO)))
  $('filter-error').hidden = !error
  textoSiCambia($('filter-error'), error)
  for (const id of ['desde','hasta','min','max']) { $(id).removeAttribute('aria-invalid'); $(id).setAttribute('aria-describedby', ['min','max'].includes(id) ? 'amount-help' : 'date-help') }
  if(error) for(const id of (error.includes('fecha') ? ['desde','hasta'] : ['min','max'])) { $(id).setAttribute('aria-invalid','true');$(id).setAttribute('aria-describedby', `${$(id).getAttribute('aria-describedby')} filter-error`) }
  chips(); stats(error); quickFilters(error)
  const titles = {bandeja:'Todas las citas',agenda:'Agenda por día',resultados:'Resultados por analista'}
  $('view-title').textContent = vista === 'bandeja' && filtros.estados.length === 1 ? ESTADOS[filtros.estados[0]].label : titles[vista]
  const aviso = error ? 'Consulta pendiente de corregir.' : `${visibles.length} de ${CITAS.length} citas del ejemplo · ${vista === 'resultados' ? 'ordenadas por pendientes y realizadas' : vista === 'agenda' ? 'orden cronológico · hora de Lima' : 'según tus filtros'}`
  clearTimeout(anuncioTimer)
  if(retrasarAviso) anuncioTimer=setTimeout(()=>textoSiCambia($('result-count'),aviso),250)
  else textoSiCambia($('result-count'),aviso)
  $('sort').disabled = vista !== 'bandeja'
  $('sort').parentElement.hidden = vista !== 'bandeja'
  $('export').disabled = !visibles.length || !!error
  $('view-panel').setAttribute('aria-labelledby',`tab-${vista}`)
  document.querySelectorAll('[data-view]').forEach(t=>{t.setAttribute('aria-selected',String(t.dataset.view===vista));t.tabIndex=t.dataset.view===vista?0:-1})
  $('view-panel').innerHTML = error ? `<div class="empty">${icon('circle-alert')}<h3>Revisa los filtros de tu consulta</h3><p>${escape(error)}</p><button class="button" data-correct>Corregir filtros</button></div>`
    : !visibles.length ? `<div class="empty">${icon('search')}<h3>No hay citas con esta combinación</h3><p>Prueba otro período o quita alguno de los filtros de arriba.</p><button class="button" data-reset>Restablecer consulta</button></div>`
    : vista === 'agenda' ? agenda() : vista === 'resultados' ? resultados() : bandeja()
  const paginas = Math.ceil(visibles.length/TAMANO)
  $('pagination').hidden = vista !== 'bandeja' || !visibles.length
  $('pagination').innerHTML = `<span>Mostrando ${(pagina-1)*TAMANO+1}–${Math.min(pagina*TAMANO,visibles.length)} de ${visibles.length} citas</span><div class="page-buttons"><button class="button" data-page="-1" aria-label="Página anterior" ${pagina===1?'disabled':''}>${icon('chevron-left')}</button><span>${pagina} / ${paginas}</span><button class="button" data-page="1" aria-label="Página siguiente" ${pagina>=paginas?'disabled':''}>${icon('chevron-right')}</button></div>`
  $('footer-total').textContent = 'Las 3 vistas comparten tus filtros.'
}
function cambiarVista(v, focus=false) { vista=v; render(); if(focus) $('view-panel').focus() }
function reset() { filtros=defaults();pagina=1;sincronizar();render() }
function quitar(key) {
  if(key.startsWith('estado:')) filtros.estados=filtros.estados.filter(e=>e!==key.slice(7))
  else filtros[key]=''
  if(key==='moneda') filtros.min=filtros.max=''
  pagina=1;sincronizar();render()
  $('result-count').setAttribute('tabindex','-1');$('result-count').focus()
}
function toast(text) { $('toast').hidden=false;$('toast').textContent=text;textoSiCambia($('announcement'),text);clearTimeout(toastTimer);toastTimer=setTimeout(()=>{$('toast').hidden=true},4500) }

function detalle(id) {
  const c = CITAS.find(c=>c.id===id)
  if(!c) return
  const p=persona(c)
  const fields=[['Fecha prevista',`${fecha(c.fecha,true)} de 2026`],['Hora de Lima',c.hora],['Analista',p.nombre],['Supervisor',p.supervisor],['Modalidad',c.modalidad],['Origen del prospecto',c.origen],['Monto estimado',dinero(c)],['Teléfono ficticio',c.telefono]]
  $('detail-content').innerHTML=`<div class="drawer-header"><div class="dialog-heading"><div><p class="eyebrow">Detalle de cita · ${escape(c.id)}</p><h2 id="detail-title">${escape(c.nombre)}</h2></div><button class="icon-button" data-close="detail" aria-label="Cerrar detalle">${icon('x')}</button></div>${badge(c)}</div><div class="drawer-body"><div class="drawer-callout"><h3>${escape(proximo(c))}</h3><p>${c.estado==='vencida' ? `La hora prevista ya pasó. ${escape(p.nombre)} debe registrar si la cita se realizó o qué ocurrió.` : c.cerrado ? 'El ejemplo registra un cierre posterior a la hora prevista de esta cita.' : escape(contexto(c))}</p></div><h3>Información de la cita</h3><dl class="detail-grid">${fields.map(([k,v])=>`<div><dt>${k}</dt><dd>${escape(v)}</dd></div>`).join('')}</dl><section class="detail-section"><h3>Resultado y seguimiento</h3><p>${escape(c.resultado)}.</p>${c.nuevaFecha?`<p><strong>Reprogramada para el ${fecha(c.nuevaFecha,true)} de 2026.</strong> La fecha prevista de este registro se conserva para mantener su historia.</p>`:''}${c.seguimiento?'<p>Seguimiento comercial pendiente después de la cita.</p>':''}</section><section class="detail-section"><h3>Contexto comercial</h3><p>${escape(c.nota)}</p></section><div class="drawer-actions"><button class="button" data-analyst="${p.id}">${icon('users')}Citas de ${escape(p.nombre.split(' ')[0])}</button><button class="button" data-agenda="${escape(c.id)}">${icon('calendar-days')}Ubicar en agenda</button></div><p class="detail-note">Registro ficticio de la propuesta. Aquí Gerencia consulta el contexto; el registro de resultados seguirá el flujo y los permisos del CRM.</p></div>`
  $('detail').showModal()
}

$('filters').addEventListener('submit',e=>e.preventDefault())
$('filters').addEventListener('input',e=>{
  const target=e.target
  if(!target.name) return
  if(target.name==='estados') filtros.estados=[...document.querySelectorAll('[name=estados]:checked')].map(c=>c.value)
  else filtros[target.name]=target.value
  if(target.name==='equipo' && filtros.analista && EQUIPO.find(p=>p.id===filtros.analista)?.supervisor!==filtros.equipo) filtros.analista=''
  if(target.name==='moneda') filtros.min=filtros.max=''
  pagina=1;sincronizar();render(['search','number','date'].includes(target.type))
})
$('sort').addEventListener('change',e=>{filtros.sort=e.target.value;pagina=1;render()})
$('clear').addEventListener('click',reset)
$('proposal-open').addEventListener('click',()=>$('proposals').showModal())
document.querySelector('[role=tablist]').addEventListener('keydown',e=>{
  if(!['ArrowLeft','ArrowRight','Home','End'].includes(e.key))return
  e.preventDefault()
  const tabs=[...document.querySelectorAll('[data-view]')]
  const index=tabs.findIndex(t=>t.dataset.view===vista)
  const next=e.key==='Home'?0:e.key==='End'?tabs.length-1:(index+(e.key==='ArrowRight'?1:-1)+tabs.length)%tabs.length
  cambiarVista(tabs[next].dataset.view);tabs[next].focus()
})
document.addEventListener('click',e=>{
  const b=e.target.closest('button')
  if(!b)return
  if(b.dataset.view)cambiarVista(b.dataset.view)
  if(b.dataset.proposal){$('proposals').close();cambiarVista(b.dataset.proposal);$(`tab-${vista}`).focus()}
  if(b.dataset.close)$(b.dataset.close).close()
  if(b.dataset.detail)detalle(b.dataset.detail)
  if('quick' in b.dataset){filtros.estados=b.dataset.quick?[b.dataset.quick]:[];pagina=1;sincronizar();render();document.querySelector(`[data-quick="${b.dataset.quick}"]`).focus()}
  if(b.dataset.remove)quitar(b.dataset.remove)
  if('reset' in b.dataset){reset();$('search').focus()}
  if('correct' in b.dataset){if(filtros.periodo==='custom')$('desde').focus();else{$('advanced').open=true;$('min').focus()}}
  if(b.dataset.page){pagina+=Number(b.dataset.page);render();$('view-panel').focus();$('view-title').scrollIntoView({block:'start'})}
  if(b.dataset.analyst){if($('detail').open)$('detail').close();filtros.analista=b.dataset.analyst;pagina=1;sincronizar();cambiarVista('bandeja',true)}
  if(b.dataset.agenda){$('detail').close();filtros.q=b.dataset.agenda;pagina=1;sincronizar();cambiarVista('agenda',true)}
})
$('export').addEventListener('click',()=>{
  if(!visibles.length)return
  const url=URL.createObjectURL(new Blob([csv(visibles)],{type:'text/csv;charset=utf-8;'}))
  const a=document.createElement('a');a.href=url;a.download='citas-ejemplo-filtradas.csv';document.body.append(a);a.click();a.remove()
  setTimeout(()=>URL.revokeObjectURL(url),1000)
  toast(`Se exportaron ${visibles.length} citas ficticias de tu consulta.`)
})
sincronizar();render()
