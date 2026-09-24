# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: gestion-diaria-cortes.spec.ts >> H4: popup único, cierre conserva pendiente y abre el registro correcto
- Location: e2e/gestion-diaria-cortes.spec.ts:126:1

# Error details

```
Error: expect(locator).toBeVisible() failed

Locator: getByRole('button', { name: 'Ocultar menú' })
Expected: visible
Timeout: 10000ms
Error: element(s) not found

Call log:
  - Expect "toBeVisible" with timeout 10000ms
  - waiting for getByRole('button', { name: 'Ocultar menú' })

```

```yaml
- region "Notifications alt+T"
- dialog "Primer corte de llamadas":
  - heading "Primer corte de llamadas" [level=2]
  - paragraph: 2026-09-24 · Corte de las 11:30, Lima. 1 analistas por revisar.
  - paragraph: Estas personas quedaron por debajo del mínimo. Reconocer o posponer el aviso conserva el resultado del corte.
  - paragraph: Han registrado llamadas 4 de 4 analistas hoy. No se infiere asistencia ni feriados.
  - list:
    - listitem:
      - strong: ANA H4
      - paragraph: 1 llamadas al corte · mínimo 3 · 1 llamadas en la ventana de recuperación
      - paragraph: "Primera llamada de hoy: 11:00 Lima."
      - button "Ver registro de ANA H4"
  - paragraph: Pendiente de atención.
  - button "Lo estoy atendiendo"
  - button "Posponer 1 hora"
  - paragraph: Puedes posponer una sola vez por una hora. No habrá reaviso al terminar la jornada ni al día siguiente. La lista conserva el pendiente.
  - button "Cerrar sin reconocer"
```

# Test source

```ts
  3293 |       const body = (req.postDataJSON() ?? {}) as {
  3294 |         p_analista_id?: string
  3295 |         p_capacidad_leads_objetivo?: number | null
  3296 |       }
  3297 |       const analistaId = String(body.p_analista_id ?? '')
  3298 |       const capacidadCruda = body.p_capacidad_leads_objetivo
  3299 |       const capacidad = capacidadCruda == null ? null : Number(capacidadCruda)
  3300 |       estado.ultimaActualizacionCapacidad = { analistaId, capacidad }
  3301 |       actualizarCapacidadMock(estado.metricas.distribucion, analistaId, capacidad)
  3302 |       return json(route, [{
  3303 |         perfil_id: analistaId,
  3304 |         capacidad_leads_objetivo: capacidad,
  3305 |       }])
  3306 |     }
  3307 | 
  3308 |     // ── leads ──
  3309 |     if (p === '/rest/v1/rpc/editar_lead_fn' && method === 'POST') {
  3310 |       estado.llamadas.rpcEditarLead += 1
  3311 |       if (estado.fallarProximaEdicionTelefono) {
  3312 |         estado.fallarProximaEdicionTelefono = false
  3313 |         return json(route, { code: '23505', message: 'duplicate key', details: 'uq_leads_telefono_vivo' }, 400)
  3314 |       }
  3315 |       const body = (req.postDataJSON() ?? {}) as { p_lead_id?: string; p_cambios?: Partial<LeadReal> }
  3316 |       if (!body.p_lead_id || !body.p_cambios) {
  3317 |         return json(route, { code: '22023', message: 'Faltan datos de la edición' }, 400)
  3318 |       }
  3319 |       if (!estado.leads.some((lead) => lead.id === body.p_lead_id)) {
  3320 |         return json(route, { code: 'P0002', message: 'Lead no encontrado' }, 400)
  3321 |       }
  3322 |       estado.leads = estado.leads.map((lead) => lead.id === body.p_lead_id ? { ...lead, ...body.p_cambios } : lead)
  3323 |       return json(route, null)
  3324 |     }
  3325 |     if (p === '/rest/v1/leads') {
  3326 |       if (method === 'GET') {
  3327 |         estado.llamadas.getLeads += 1
  3328 |         if (estado.leadsSiempreCaido) return json(route, { message: 'server down' }, 500)
  3329 |         if (estado.fallarProximaCargaLeads) {
  3330 |           estado.fallarProximaCargaLeads = false
  3331 |           return json(route, { message: 'server down' }, 500)
  3332 |         }
  3333 |         const idPedido = url.searchParams.get('id')
  3334 |         if (idPedido?.startsWith('eq.')) {
  3335 |           return json(route, estado.leads.filter((lead) => lead.id === idPedido.slice(3)
  3336 |             && (url.searchParams.get('activo') !== 'eq.true' || lead.activo)))
  3337 |         }
  3338 |         // `fueraDelBoot`: simula un lead que la FOTO inicial no trae (tope de
  3339 |         // MAX_LEADS_AMBITO) pero que su lectura por id sí sirve (RLS lo ve).
  3340 |         return json(route, estado.leads.filter((lead) => !lead.fueraDelBoot))
  3341 |       }
  3342 |       if (method === 'POST') {
  3343 |         estado.llamadas.insertLeadDirecto += 1
  3344 |         return json(route, { message: 'El alta directa de leads es una vía legacy' }, 500)
  3345 |       }
  3346 |       if (method === 'PATCH') {
  3347 |         estado.llamadas.patchLead += 1
  3348 |         if (estado.fallarProximoPatch) {
  3349 |           estado.fallarProximoPatch = false
  3350 |           return json(route, { code: '', message: 'update rechazado', details: '' }, 400)
  3351 |         }
  3352 |         // Servidor con estado: aplica el update a la fila (el resync lo refleja).
  3353 |         const idFiltro = (url.searchParams.get('id') ?? '').replace(/^eq\./, '')
  3354 |         const cambios = (req.postDataJSON() ?? {}) as Partial<LeadReal>
  3355 |         estado.leads = estado.leads.map((l) => (l.id === idFiltro ? { ...l, ...cambios } : l))
  3356 |         return json(route, [{ id: idFiltro }])
  3357 |       }
  3358 |     }
  3359 | 
  3360 |     // ── actividades ──
  3361 |     if (p === '/rest/v1/actividades' && method === 'POST') {
  3362 |       estado.llamadas.insertActividad += 1
  3363 |       if (estado.fallarProximoInsertActividad) {
  3364 |         estado.fallarProximoInsertActividad = false
  3365 |         return json(route, { code: '', message: 'actividad rechazada', details: '' }, 400)
  3366 |       }
  3367 |       return json(route, [], 201)
  3368 |     }
  3369 | 
  3370 |     // Fail-closed: cualquier otra cosa NO debe salir a prod.
  3371 |     return json(route, { message: `E2E: ruta no mockeada ${method} ${p}` }, 500)
  3372 |   })
  3373 | 
  3374 |   return estado
  3375 | }
  3376 | 
  3377 | /** Inicia sesión REAL vía el formulario (supabase-js guarda la sesión solo).
  3378 |  * `esperarWorkspace: false` para los escenarios en los que la carga inicial cae
  3379 |  * A PROPÓSITO: ahí el CRM pinta su pantalla de error en vez del workspace, así
  3380 |  * que esperar el menú lateral sería esperar algo que no debe existir. */
  3381 | export async function loginReal(
  3382 |   page: Page,
  3383 |   { esperarWorkspace = true }: { esperarWorkspace?: boolean } = {},
  3384 | ): Promise<void> {
  3385 |   // Mismo motivo que en entrarDemo: animaciones instantáneas o los asserts
  3386 |   // de tiles/paneles pillan estados de tránsito bajo carga.
  3387 |   await page.emulateMedia({ reducedMotion: 'reduce' })
  3388 |   await page.goto('/')
  3389 |   await page.locator('#correo').fill('qa-real@avancecorp.pe')
  3390 |   await page.locator('#clave').fill('cualquier-cosa')
  3391 |   await page.getByRole('button', { name: /^Entrar$/ }).click()
  3392 |   if (!esperarWorkspace) return
> 3393 |   await expect(page.getByRole('button', { name: 'Ocultar menú' })).toBeVisible({ timeout: 10_000 })
       |                                                                    ^ Error: expect(locator).toBeVisible() failed
  3394 | }
  3395 | 
  3396 | /** Transporte de la ruta compartida para las suites de UI sin backend.
  3397 |  * SQL, Auth y Storage reales se cubren en e2e-integration y en el banco HTTP. */
  3398 | export async function montarConversionCompartida(page:Page) {
  3399 |   const persona='11111111-1111-4111-8111-111111111111'
  3400 |   let nombre='PERSONA SINTÉTICA',leadId:string|null=null,perfil:string|null=null
  3401 |   let solicitud:Record<string,unknown>|null=null
  3402 |   await page.route('**/rest/v1/rpc/*',async route=>{
  3403 |     const fn=new URL(route.request().url()).pathname.split('/').at(-1),b=route.request().postDataJSON()
  3404 |     if(fn==='preparar_persona_lead_inversion_fn'){
  3405 |       nombre=b.p_nombre;leadId=b.p_lead
  3406 |       return route.fulfill({json:{inversionista_id:persona,lead_id:leadId,solicitud_id:solicitud?.solicitud_id??null}})
  3407 |     }
  3408 |     if(fn==='contexto_conversion_inversion_fn')return route.fulfill({json:{solicitud_id:solicitud?.solicitud_id??null,documento_tipo:'DNI',persona:{inversionista_id:persona,perfil_id:perfil,
  3409 |       nombre,correo:'persona@pruebas.example',telefono:'999888777',responsable_id:UID,responsable_nombre:'ANALISTA DEL LEAD'},
  3410 |       capacidades:{nueva_inversion:true,motivo_no_operable:null}}})
  3411 |     if(fn==='preparar_inversion_fn'){
  3412 |       solicitud={solicitud_id:b.p_clave,lead_id:leadId,estado:'preparada',inversion_id:null,inversionista_id:persona,
  3413 |         inversionista_origen_id:persona,identidad_fusionada:false,responsable_esperado_id:UID,responsable_actual_id:UID,
  3414 |         requiere_revision_responsable:false,revision_datos:0,revision_responsable:0,hash_datos:'prueba',
  3415 |         necesita_portal:!perfil,comprobante_bucket:null,comprobante_ruta:null,resultado:null,datos:b.p_datos}
  3416 |       return route.fulfill({json:solicitud})
  3417 |     }
  3418 |     if(fn==='solicitud_inversion_fn')return route.fulfill({json:solicitud})
  3419 |     return route.fallback()
  3420 |   })
  3421 |   await page.route('**/functions/v1/crm-inversion-portal',route=>{
  3422 |     perfil='cccccccc-cccc-4ccc-8ccc-cccccccccccc'
  3423 |     solicitud={...solicitud,necesita_portal:false}
  3424 |     return route.fulfill({json:{ok:true,solicitud_id:solicitud.solicitud_id,perfil_id:perfil,reintento:false}})
  3425 |   })
  3426 | }
  3427 | 
  3428 | /** Abre Avance dentro de Nueva inversión después de confirmar la identidad. */
  3429 | export async function abrirConversionAvance(page: Page, drawer: Locator): Promise<Locator> {
  3430 |   await montarConversionCompartida(page)
  3431 |   await drawer.getByRole('button', { name: /Convertir a cliente/i }).click()
  3432 |   const documento=page.getByLabel('Documento',{exact:true})
  3433 |   if(!await documento.inputValue())await documento.fill('93334444')
  3434 |   await page.getByRole('button',{name:'Continuar a Nueva inversión'}).click()
  3435 |   await page.getByRole('button',{name:'Avance',exact:true}).click()
  3436 |   const dialogo = page.getByRole('dialog', { name: 'Acceso Avance' })
  3437 |   await expect(dialogo).toBeVisible()
  3438 |   return dialogo
  3439 | }
  3440 | 
```