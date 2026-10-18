import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { mkdirSync, writeFileSync } from 'node:fs'
import { contratoPrueba } from '../f4/operaciones-fixture.mjs'
const { preparar, retirar, login, rpc, persona, contrato, servicio, anonimo, sql, http, diagnostico } =
  await import(process.argv.includes('--cloud') ? './auth-http-cloud.mjs' : './auth-http-local.mjs')

try {
  await preparar()
  const sesiones = new Map()
  for (const n of [1,2,3,4,5,6,7,8,9,11,12]) sesiones.set(n, await login(n))
  console.log('PASS: once cuentas ficticias iniciaron sesión mediante Auth real')
  const propio = rpc('cumplimiento_metas_v2_fn', { p_periodo: '2026-10-01' }, sesiones.get(2))
  assert.equal(propio.status, 200, JSON.stringify(propio.data))
  assert.ok(propio.data.capital_valoracion)
  assert.ok(propio.data.vendedores.every(v => v.vendedor_id === persona(2)))
  console.log('PASS: vendedor HTTP recibe su corte de capital y ninguna fila ajena')
  const citas = rpc('citas_gerencia_consulta_v2_fn', { p_desde: '2026-10-01', p_hasta: '2026-10-31' }, sesiones.get(1))
  assert.equal(citas.status, 200, JSON.stringify(citas.data))
  assert.ok(citas.data.gestion.capital.length > 0)
  assert.ok(citas.data.gestion.capital.every(k => k.analista_id === persona(2)))
  console.log('PASS: Citas HTTP conserva el ámbito del supervisor autenticado')
  const parametros = { p_periodo: '2026-10-01' }
  for (const n of [1,2,3,4,6,8,11,12]) {
    const viejo=rpc('cumplimiento_metas_fn', parametros, sesiones.get(n))
    const nuevo=rpc('cumplimiento_metas_v2_fn', parametros, sesiones.get(n))
    assert.equal(nuevo.status, viejo.status, `Ámbito mensual del actor ${n}`)
    if (nuevo.ok) {
      assert.deepEqual(nuevo.data.vendedores.map(v=>v.vendedor_id), viejo.data.vendedores.map(v=>v.vendedor_id))
      if (n===4) {
        const visibles=new Set([...viejo.data.vendedores.map(v=>v.vendedor_id),
          ...(viejo.data.fuera_ranking??[]).map(v=>v.persona_id)])
        assert.ok(nuevo.data.capital_valoracion.personas.length>0)
        assert.ok(nuevo.data.capital_valoracion.personas.every(v=>visibles.has(v.vendedor_id)),
          'Coordinación recibe únicamente productores visibles en la puerta mensual anterior')
      }
    }
  }
  const ajeno=rpc('capital_operaciones_valoradas_fn', { ...parametros, p_vendedor_id: persona(3) }, sesiones.get(2))
  assert.equal(ajeno.status, 403)
  const detalle=rpc('capital_operaciones_valoradas_fn', { ...parametros, p_vendedor_id: persona(2),
    p_corte_id: propio.data.capital_valoracion.corte_id }, sesiones.get(2))
  assert.equal(detalle.status, 200, JSON.stringify(detalle.data))
  assert.equal(detalle.data.total_pen, propio.data.capital_valoracion.personas.find(p=>p.vendedor_id===persona(2)).capital_valorado.equivalente_pen)
  const v1Sept=rpc('cumplimiento_metas_fn', { p_periodo:'2026-09-01' }, sesiones.get(1))
  const v2Sept=rpc('cumplimiento_metas_v2_fn', { p_periodo:'2026-09-01' }, sesiones.get(1))
  assert.deepEqual(v2Sept, v1Sept)
  console.log('PASS: ocho ámbitos conservan filas autorizadas, incluido Coordinación; detalle propio cuadra, ajeno denegado y septiembre idéntico')
  for (const n of [2,4,5,7,8,9]) {
    const denegado = rpc('citas_gerencia_consulta_v2_fn', { p_desde: '2026-10-01', p_hasta: '2026-10-31' }, sesiones.get(n))
    assert.equal(denegado.status, 403, `PII de Citas para actor ${n}: ${denegado.status}`)
  }
  for (const auth of [anonimo, ...sesiones.values()]) {
    const r = rpc('reconciliar_capital_valoraciones_fn', {}, auth)
    assert.ok([401,403].includes(r.status), `El navegador materializó: ${r.status}`)
    for (const nombre of ['reevaluar_cierre_capital_fn','suspender_capital_valorado_fn']) {
      const prohibido=rpc(nombre,{},auth)
      assert.ok([401,403].includes(prohibido.status), `${nombre}: ${prohibido.status}`)
    }
  }
  for (const n of [2,6,8]) {
    for (const [tabla,body] of Object.entries({capital_cortes_valorados:{base:[]},capital_valoraciones:{equivalente_pen:1},tipo_cambio_diario:{tasa:1}})) {
      const r=http(`/rest/${tabla}?select=*`,{method:'GET',auth:sesiones.get(n)})
      assert.equal(r.status,403,`Lectura global de ${tabla} por ${n}`)
      // La protección safeupdate cloud rechaza antes de evaluar permisos las
      // escrituras sin WHERE. El filtro mantiene la prueba de privilegios SQL.
      const filtro=tabla==='tipo_cambio_diario'?'fecha_corte=eq.2026-10-02':'id=not.is.null'
      const modificar=http(`/rest/${tabla}?${filtro}`,{method:'PATCH',auth:sesiones.get(n),body})
      assert.equal(modificar.status,403,`Escritura global de ${tabla} por ${n}`)
    }
  }
  const corregido=rpc('corregir_fecha_cierre_comercial',{p_contrato_id:contrato(2),p_fecha:'2026-10-05',p_motivo:'Corrección HTTP de la fecha comercial sintética'},sesiones.get(6))
  assert.equal(corregido.status,200,JSON.stringify(corregido.data))
  assert.equal(sql(`select equivalente_pen from crm.capital_valoraciones where fuente_id='${contrato(2)}' order by revision desc limit 1;`),'6200.00')
  const revision=sql(`select count(*) from crm.capital_valoraciones where fuente_id='${contrato(2)}';`)
  const sinPermiso=rpc('corregir_fecha_cierre_comercial',{p_contrato_id:contrato(2),p_fecha:'2026-10-06',p_motivo:'Intento de vendedor sin permiso'},sesiones.get(2))
  assert.equal(sinPermiso.status,403)
  assert.equal(sql(`select count(*) from crm.capital_valoraciones where fuente_id='${contrato(2)}';`),revision)
  console.log('PASS: HTTP no expone tablas globales; corrección autorizada agrega revisión y la denegada no cambia datos')
  const reevaluacion = rpc('reevaluar_cierre_capital_fn', {}, servicio)
  assert.equal(reevaluacion.status, 200, JSON.stringify(reevaluacion.data))
  assert.equal(reevaluacion.data.motivo, 'cron_no_configurado')
  assert.equal(sql('select count(*) from crm.periodos_cerrados;'), '0')
  console.log('PASS: navegador no materializa y servicio omite cierre sin cron configurado')

  // Flujo F4: preparar, releer/revisar y confirmar con sesión de cartera real.
  // Solo la configuración sintética usa réplica; ningún escritor ni gate del
  // producto se sustituye o deshabilita al ejecutar el recorrido.
  sql(`begin; set local session_replication_role=replica;
    insert into crm.inversionistas(id,perfil_id,responsable_relacion_id)
      values('${persona(80)}','${persona(7)}','${persona(2)}');
    insert into crm.inversionista_identificadores(inversionista_id,tipo_documento,documento_normalizado,documento_original,verificado,fuente)
      values('${persona(80)}','DNI','48000007','48000007',true,'fixture_http_tc');
    insert into crm.multiempresa_flags(nombre,activo) values('resolver_en_puertas',true),('inversiones_escritura',true);
    set local session_replication_role=origin; commit;`)
  const clave=randomUUID()
  const datos={ inversionista_id:persona(80), empresa:'avance',
    ...contratoPrueba(persona(7),persona(2),{inicio:'2026-10-02',capital:20000,moneda:'USD',numero:'2026-01-990002'}) }
  const solicitudPreparada=rpc('preparar_inversion_fn',{p_clave:clave,p_datos:datos},sesiones.get(2))
  assert.equal(solicitudPreparada.status,200,JSON.stringify(solicitudPreparada.data))
  assert.equal(solicitudPreparada.data.solicitud_id,clave)
  const revisionResponsable=rpc('revisar_solicitud_inversion_fn',{p_solicitud:clave,p_responsable_revisado:persona(2),
    p_revision_esperada:0,p_motivo:'Confirmar responsable de la inversión ficticia del banco TC'},sesiones.get(6))
  assert.equal(revisionResponsable.status,200,JSON.stringify(revisionResponsable.data))
  for (const n of [3,7,8,11]) {
    const r=rpc('confirmar_inversion_revisada_fn',{p_solicitud:clave,p_revision_datos_esperada:0},sesiones.get(n))
    assert.ok([403,404].includes(r.status),`Actor ajeno ${n} confirmó inversión: ${r.status}`)
  }
  const confirmado=rpc('confirmar_inversion_revisada_fn',{p_solicitud:clave,p_revision_datos_esperada:0},sesiones.get(2))
  assert.equal(confirmado.status,200,JSON.stringify(confirmado.data))
  const creado=sql(`select c.id from public.contratos c where numero_contrato='2026-01-990002';`)
  assert.match(creado,/^[0-9a-f-]{36}$/)
  assert.equal(sql(`select count(*) from crm.inversiones where contrato_id='${creado}';`),'1')
  assert.equal(sql(`select equivalente_pen from crm.capital_valoraciones where fuente_id='${creado}';`),'68000.00')
  const repetido=rpc('confirmar_inversion_revisada_fn',{p_solicitud:clave,p_revision_datos_esperada:0},sesiones.get(2))
  assert.equal(repetido.status,200,JSON.stringify(repetido.data))
  assert.equal(repetido.data.reintento,true)
  assert.equal(sql(`select count(*) from public.contratos where numero_contrato='2026-01-990002';`),'1')
  assert.equal(rpc('reconciliar_capital_valoraciones_fn',{},servicio).status,200)
  const corteConPrimera=rpc('cumplimiento_metas_v2_fn',parametros,sesiones.get(2)).data.capital_valoracion.corte_id
  console.log('PASS: F4 HTTP confirma USD 20 000 del 02/10 con S/ 68 000 inmediatos e idempotencia, usando los escritores nativos')
  // Un contrato que empieza después del registro toma la fecha comercial de
  // registro por el trigger vigente: esa segunda fecha aún no tiene BCRP.
  const inicioPosterior=sql("select (date_trunc('month',statement_timestamp() at time zone 'America/Lima')+interval '1 month 1 day')::date;")
  const otraClave=randomUUID()
  const segunda={inversionista_id:persona(80),empresa:'avance',...contratoPrueba(persona(7),persona(2),{
    inicio:inicioPosterior,capital:10000,moneda:'USD',numero:'2026-01-990003'})}
  segunda.cuenta.cci='99999999999999999993'
  segunda.cuenta.numero_cuenta='F4-USD-002'
  const segundaPreparada=rpc('preparar_inversion_fn',{p_clave:otraClave,p_datos:segunda},sesiones.get(2))
  assert.equal(segundaPreparada.status,200,JSON.stringify(segundaPreparada.data))
  const segundaConfirmada=rpc('confirmar_inversion_revisada_fn',{p_solicitud:otraClave,p_revision_datos_esperada:0},sesiones.get(2))
  assert.equal(segundaConfirmada.status,200,JSON.stringify(segundaConfirmada.data))
  const otroCreado=sql("select id from public.contratos where numero_contrato='2026-01-990003';")
  assert.match(otroCreado,/^[0-9a-f-]{36}$/)
  assert.equal(sql(`select count(*) from crm.capital_valoraciones where fuente_id='${otroCreado}';`),'0')
  const pendiente=rpc('reconciliar_capital_valoraciones_fn',{},servicio)
  assert.equal(pendiente.status,200,JSON.stringify(pendiente.data))
  const porValorar=rpc('cumplimiento_metas_v2_fn',parametros,sesiones.get(2))
  assert.equal(porValorar.data.capital_valoracion.corte_id,corteConPrimera)
  assert.ok(porValorar.data.capital_valoracion.cobertura.pendientes.cantidad>0)
  console.log('PASS: F4 HTTP confirma otra venta sin cotización y conserva el último ranking completo')
  const hoy=sql("select (statement_timestamp() at time zone 'America/Lima')::date;")
  const trabajos=rpc('tomar_fechas_tipo_cambio_fn',{p_limite:20},servicio)
  assert.equal(trabajos.status,200,JSON.stringify(trabajos.data))
  const trabajo=trabajos.data.find(j=>j.fecha_corte===hoy)
  assert.ok(trabajo,'La venta nueva dejó la fecha en la cola persistente')
  const evidencia={fecha_corte:hoy,politica:'sbs_punto_medio_7d_v1',publicacion_confirmada:hoy,
    fuente:'BCRP · SBS PD04639PD/PD04640PD',huella_respuestas:'d'.repeat(64),pares:Array.from({length:7},(_,i)=>({
      fecha:new Date(Date.parse(`${hoy}T12:00:00Z`)-i*86400000).toISOString().slice(0,10),compra:'3.1',venta:'3.1'}))}
  const resuelto=rpc('resolver_fecha_tipo_cambio_fn',{p_fecha:hoy,p_reserva:trabajo.reserva,p_evidencia:evidencia},servicio)
  assert.equal(resuelto.status,200,JSON.stringify(resuelto.data))
  const reconciliado=rpc('reconciliar_capital_valoraciones_fn',{},servicio)
  assert.equal(reconciliado.status,200,JSON.stringify(reconciliado.data))
  assert.equal(sql(`select equivalente_pen from crm.capital_valoraciones where fuente_id='${creado}';`),'68000.00')
  assert.equal(sql(`select equivalente_pen from crm.capital_valoraciones where fuente_id='${otroCreado}';`),'31000.00')
  assert.equal(sql(`select sum(equivalente_pen) from crm.capital_valoraciones where fuente_id in('${creado}','${otroCreado}');`),'99000.00')
  const aceptado=rpc('cumplimiento_metas_v2_fn',parametros,sesiones.get(2))
  assert.notEqual(aceptado.data.capital_valoracion.corte_id,corteConPrimera)
  assert.equal(aceptado.data.capital_valoracion.cobertura.pendientes.cantidad,0)
  console.log('PASS: servicio HTTP acepta segunda fecha a 3,10; primera venta conserva S/ 68 000, segunda S/ 31 000, suma S/ 99 000')
  if(process.argv.includes('--fixtures-rangos')) {
    sql(`begin; set local session_replication_role=replica;
      insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,fecha_inicio,
        fecha_vencimiento,categoria,producto_condicion_id,fecha_cierre_comercial,analista_cierre_id,creado_por)
      select '${contrato(50)}','TC-HTTP-AGOSTO',cliente_id,3000,'USD',modalidad,'2026-08-31',
        fecha_vencimiento,categoria,producto_condicion_id,'2026-08-31',analista_cierre_id,creado_por
        from public.contratos where id='${contrato(7)}';
      insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,fecha_inicio,
        fecha_vencimiento,categoria,producto_condicion_id,fecha_cierre_comercial,analista_cierre_id,creado_por)
      select '${contrato(51)}','TC-HTTP-SEPTIEMBRE',cliente_id,7000,'USD',modalidad,'2026-09-30',
        fecha_vencimiento,categoria,producto_condicion_id,'2026-09-30',analista_cierre_id,creado_por
        from public.contratos where id='${contrato(7)}';
      set local session_replication_role=origin;
      select private.inversion_vincular_fuente('${persona(60)}','${contrato(50)}',null,'${persona(6)}');
      select private.inversion_vincular_fuente('${persona(60)}','${contrato(51)}',null,'${persona(6)}'); commit;`)
    const directorio=new URL('../../../app/test-fixtures/capital-valorado/',import.meta.url)
    mkdirSync(directorio,{recursive:true})
    const meses={}
    for(const mes of ['2026-08-01','2026-09-01','2026-10-01']) {
      const r=rpc('facturacion_diaria_v2_fn',{p_mes:mes},sesiones.get(6))
      assert.equal(r.status,200,JSON.stringify(r.data))
      assert.ok(r.data.filas.length>0,`Sin fuentes para ${mes}`)
      meses[mes]=r.data
    }
    const pedido={p_desde:'2026-09-28',p_hasta:'2026-10-04',p_pagina:1,p_tamano:25,
      p_cortes:{'2026-10-01':meses['2026-10-01'].corte_id}}
    const lista=rpc('listar_operaciones_facturacion_v3_fn',pedido,sesiones.get(6))
    assert.equal(lista.status,200,JSON.stringify(lista.data))
    assert.ok(lista.data.filas.some(f=>f.fecha==='2026-09-30'))
    assert.ok(lista.data.filas.some(f=>f.fecha==='2026-10-02'))
    writeFileSync(new URL('facturacion-rangos.json',directorio),JSON.stringify({meses,pedido,lista:lista.data},null,2)+'\n')
    console.log('PASS: fixture de tres meses y detalle de semana mixta generados mediante HTTP/SQL reales, sin datos productivos')
  }
} catch (error) {
  diagnostico()
  throw error
} finally {
  retirar()
}
