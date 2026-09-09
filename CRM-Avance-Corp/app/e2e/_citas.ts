import type { Page } from '@playwright/test'

/** Respuesta de la nueva RPC; nunca deriva filas de las métricas agregadas. */
export async function montarConsultaCitas(page: Page) {
  await page.route('**/rest/v1/rpc/citas_gerencia_consulta_fn',async route => {
    const {p_desde:desde,p_hasta:hasta}=route.request().postDataJSON()
    const id=(n:number) => `84000000-0000-4000-8000-${String(n).padStart(12,'0')}`
    const mes=desde.slice(0,7)
    const citas=[1,2,3].map(n => ({
      id:id(n),lead_id:id(n===3 ? 11 : 10),nombre:n===3 ? 'OTRO PROSPECTO' : 'PERSONA RECUPERADA',telefono:'+51900000001',
      analista_id:id(20),analista_nombre:'ANALISTA DE PRUEBA',supervisor_id:id(30),supervisor_nombre:'SUPERVISOR DE PRUEBA',
      vence_en:`${mes}-${n===2 ? '03' : '01'}T16:00:00Z`,estado:n===2 ? 'completada' : 'no_show',cancelada_por:null,
      modalidad:'virtual',origen:'referido',moneda:'PEN',monto_estimado:35000,resultado:n===2 ? 'interesado' : 'sin_clasificar',nota:'Datos ficticios de prueba',
      reagendada_de:n===2 ? id(1) : null,creado_en:n===2 ? `${mes}-01T18:00:00Z` : `${mes}-01T15:00:00Z`,
      asistencia_registrada_en:n===2 ? `${mes}-03T16:30:00Z` : null,cierre_posterior:false,
    }))
    await route.fulfill({json:{version:2,periodo:{desde,hasta},generado_en:'2026-09-04T15:00:00Z',citas,
      conversiones:[{lead_id:id(10),perfil_id:id(50),convertido_en:'2026-09-04T14:00:00Z'}],
      disponibilidad_depositos:'conversion_cliente',citas_clientes:0}})
  })
}
