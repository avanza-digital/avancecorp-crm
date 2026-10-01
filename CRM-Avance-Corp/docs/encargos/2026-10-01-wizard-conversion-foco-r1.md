ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo de revisión (LEVEL 2: solo pantalla del CRM, sin SQL ni permisos nuevos)

Eres el revisor secundario. Trabajas sin base de datos, sin red y sin poder abrir archivos: todo lo que debes juzgar está transcrito abajo. Tu trabajo es REFUTAR: busca cómo este cambio rompe algo, deja pasar el fallo original o abre un riesgo. NO FINDING WITHOUT EVIDENCE: cada hallazgo cita archivo, líneas o fragmento del diff; lo no demostrado se marca como hipótesis. Responde con este formato:

VERDICT: PASS | CHANGES_REQUESTED | BLOCK
SUMMARY
FINDINGS ([P0|P1|P2|P3] Título · File · Lines · Problem · Evidence · Impact · Recommendation)
TEST GAPS · REGRESSION RISKS · SECURITY RISKS (solo si aplican)
RECOMMENDED NEXT ACTIONS
CONFIDENCE: HIGH | MEDIUM | LOW

## El fallo (producción, crm.miavance.com, build vivo `c6e65d9e`)

Ficha del lead (`#/cartera/lead/<id>`) → «Convertir a cliente» → modal «Registrar la inversión del lead» (identidad) → «Continuar a Nueva inversión» → wizard (Acceso · Condiciones «Crear contrato de…» · Revisión). En el paso 2, si el analista cambia a otra aplicación y vuelve al navegador, el wizard desaparece y reaparece el modal de identidad. Pierde lo escrito.

## Causa raíz (reproducida con dos pruebas que FALLAN contra `c6e65d9e`)

Código vivo de `inversion-desde-lead.tsx` (antes del cambio):

```tsx
export function InversionDesdeLead(props: Propiedades) {
  const documento = useDocumentoLead(props.l)
  if (documento.isPending || documento.isError || !documento.data) return <Dialog …>…cargando/error…</Dialog>
  return <FormularioInversionDesdeLead key={`${props.l.id}:${documento.data.tipo}:${documento.data.numero}`} {...props} documentoInicial={documento.data} />
}
// FormularioInversionDesdeLead guarda la persona preparada en estado LOCAL:
const [preparada, setPersona] = useState<…|null>(null)
if (persona) return <InversionNueva key={`${yo.id}:${l.id}:${persona.inversionista_id}`} … />
```

y de `useDocumentoLead`:

```ts
queryKey: ['crm', 'leads', 'documento', yo?.id, lead.id, lead.actualizado_en],
enabled: Boolean(yo && !yo.demo), retry: false, staleTime: 0, gcTime: 0,
// refetchOnWindowFocus: true es el default del QueryClient
```

1. «Continuar a Nueva inversión» llama a `crm.preparar_persona_lead_inversion_fn`, que hace `update crm.leads set inversionista_id=…, nombre_completo=…` → el trigger cambia `actualizado_en` EN EL SERVIDOR. El store del front no se entera.
2. Al volver a la ventana, `store.tsx` resincroniza la cartera (`focus`/`visibilitychange` → `resincronizarReal`). El lead llega con otro `actualizado_en` → la clave de la consulta cambia → `gcTime: 0`, sin datos → `isPending` → el envoltorio pinta el diálogo «Documento del lead» → `FormularioInversionDesdeLead` se DESMONTA (con `InversionNueva` y `ContratoNuevo` dentro) → al cargar se monta de nuevo con `preparada = null` → modal de identidad.
3. Segundo camino, misma consecuencia: la relectura por foco (misma clave) devuelve el documento YA vinculado (otro `numero`) → cambia la `key` → remonta.

Lo que NO era la causa (verificado leyendo el código): la máquina de auth ignora el eco del listener con el mismo usuario (`listo.on.SESION_CAMBIO`: solo `sinUsuario` o `esOtroUsuario` transicionan; test «el eco del listener (mismo usuario ya confirmado) NO dispara otra verificación»), `REVALIDAR` por foco es silencioso (`faseDe('revalidando') === 'listo'`) y `aplicarResultado` conserva la MISMA referencia de `yo` si nada cambió. Un TOKEN_REFRESHED tras 1 h no remonta la app.

## Qué ya existía y NO se toca

`InversionNueva` (compartida por cartera, venta cruzada y lead) ya persiste en `sessionStorage`, por actor/persona/lead/solicitud: el intento (clave y token de idempotencia), el borrador de acceso (paso 1) y el borrador de condiciones (paso 2, sin datos sensibles de cuenta nueva ni co-titulares, por decisión previa). Al montarse recupera el intento, consulta la solicitud en el servidor y rehidrata `ContratoNuevo` con el borrador de la misma revisión. Su consulta `conversionQ` (`contexto_conversion_inversion_fn(p_lead, p_persona)`, `refetchOnWindowFocus: 'always'`, cada 15 s) es el control de revocación y NO remonta nada; se deja como está. Si responde 42501/PT409 llama `onRevocado`.

Servidor (sin cambios), `crm.contexto_conversion_inversion_fn(p_lead, p_persona)`:

```sql
select * into v_l from crm.leads where id=p_lead and activo;
if not found or not coalesce((private.rol_crm((select auth.uid()))='gerencia' or
  v_l.vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))),false) then
  raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='42501';
end if;
v_ctx:=private.inversion_persona_lectura(coalesce(p_persona,v_l.inversionista_id));
v_persona:=(v_ctx->>'inversionista_id')::uuid;
if private.inversionista_canonica(v_l.inversionista_id) is distinct from v_persona then
  raise exception 'El lead no corresponde a la persona consultada' using errcode='42501';
end if;
```

## El arreglo (diff completo más abajo)

1. `InversionDesdeLead`: el documento solo PRECARGA la identidad. Se FIJA en estado con la primera respuesta posterior al montaje (`isFetchedAfterMount`, porque la ficha comparte la misma consulta y su copia en caché puede ser anterior) y deja de leerse (`useDocumentoLead(l, activa=false)`). Sin `key` por documento. Una vez pintado el formulario, ninguna relectura ni cambio de clave lo desmonta.
2. Marca «conversión abierta» en `sessionStorage` (`crm:f5:conversion-abierta:<actor>:<lead>` → `{version, actor, lead, inversionista_id, solicitud_id}`, solo identificadores, validada con valibot). Se guarda al preparar la identidad; se borra al cerrar el diálogo, al confirmar la inversión, al revocarse el acceso y, globalmente, al salir (`limpiarIntentosInversion()` sin actor, que `auth.tsx` ya llama en SIGNED_OUT y en `salir`). `FormularioInversionDesdeLead` la lee al montarse: si existe, va directo a `InversionNueva` sin pedir identidad (el servidor revalida persona↔lead y ámbito en `contexto_conversion_inversion_fn`).
3. `Ficha` (lead-drawer): tras recargar la página (la ficha vuelve por el hash), si hay marca reabre el diálogo de conversión sola, pero espera a conocer las condiciones de tasa (`condicionesLead !== null`), porque `ContratoNuevo` toma `condicionesIniciales` solo al montarse. Vuelve a mirar la marca en ese momento.
4. Decisiones deliberadas, dime si alguna es un error:
   - NO se puso `refetchOnWindowFocus: false` en `conversionQ` ni en el store: son el control de revocación y la frescura de la cartera, y no remontan.
   - NO se borra la marca en «Cancelar solicitud»: el wizard sigue abierto mostrando «Solicitud cancelada»; recargar ahí restaura esa misma pantalla (verdad del servidor). Los borradores van por id de solicitud y no se reutilizan.
   - NO se borra la marca al desmontar (solo en cierres explícitos): recargar no ejecuta limpiezas de React, y así cualquier remontaje imprevisto también retoma el wizard. Efecto lateral aceptado: si el analista navega fuera con el wizard abierto (atrás del navegador) y vuelve a ese lead en la misma pestaña, el wizard se reabre.
   - Los datos sensibles del paso 2 (cuenta bancaria nueva, co-titulares) siguen sin persistirse: tras RECARGAR hay que reescribirlos; tras volver a la ventana se conservan porque ya nada se desmonta.

## Verificación ejecutada (worktree limpio desde `c6e65d9e`)

- Reproducción: `inversion-desde-lead-foco.test.tsx` (lector REAL del documento, solo se simula el transporte) → 2 pruebas FALLABAN contra `c6e65d9e` mostrando «Registrar la inversión del lead»; con el arreglo pasan.
- `npm run check` (oxlint + tsc + cobertura + build + bundle + dup): PASS, 330 archivos / 5169 pruebas.
- E2E Docker (`acceso-avance-ux.spec.ts` + `lead-documento.spec.ts`): 14/14 PASS, incluido el caso nuevo de foco + recarga en el paso 2 (Chromium real, backend sintético).
- Dos pruebas existentes de `lead-drawer-convertir.test.tsx` simulaban «reabrir» desmontando SIN cerrar y luego pulsaban «Continuar a Nueva inversión»; con la marca eso es una recarga y el wizard se retoma directo, así que se ajustaron a ese contrato (ver diff).

## Preguntas concretas para refutar

1. ¿Queda algún camino por el que volver a la ventana (resincronización del store, relectura por foco, refresco de token, `recargar()` tras confirmar) desmonte `FormularioInversionDesdeLead` o `InversionNueva`?
2. `if (fijado === null && reciente) setFijado(reciente)` durante el render y, en `Ficha`, `setRetomarConversion(false)` + `setDialogo(...)` durante el render: ¿algún bucle, doble apertura o problema con StrictMode?
3. ¿La marca puede abrir el wizard de una persona equivocada o saltarse un control? (otra cuenta en la misma pestaña, lead reasignado, identidad fusionada, marca manipulada, modo demo).
4. ¿Algún camino deja la marca huérfana de forma que el wizard reaparezca cuando no debe, o la borra cuando debía conservarse?
5. Esperar a `condicionesLead` para reabrir: ¿puede dejar el wizard sin reabrir en un caso normal, o abrirlo sin condiciones?
6. ¿Se puede crear una solicitud o un contrato duplicado por culpa de la retoma? (el intento conserva clave y token; la retoma no llama a `preparar_persona_lead_inversion_fn` ni a `preparar_inversion_fn`).
7. `useDocumentoLead(lead, activa)`: al fijar, la consulta queda deshabilitada con `gcTime: 0`. ¿Afecta al otro observador de la misma clave (la sección Datos de la ficha, que llama `useDocumentoLead(l)` sin segundo argumento)?
8. ¿Faltan pruebas para alguna rama del cambio?

## Diff completo (worktree vs `c6e65d9e`)

```diff
diff --git a/CRM-Avance-Corp/app/e2e/acceso-avance-ux.spec.ts b/CRM-Avance-Corp/app/e2e/acceso-avance-ux.spec.ts
index 13b97b7e..44231876 100644
--- a/CRM-Avance-Corp/app/e2e/acceso-avance-ux.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/acceso-avance-ux.spec.ts
@@ -175,12 +175,70 @@ test('corregir el correo permite continuar y un conflicto conocido conserva el f
     return route.fallback()
   })
   await acceso.getByRole('button', {name: 'Revisar acceso Avance'}).click()
   await expect(acceso.getByRole('alert')).toContainText('Los datos cambiaron')
   await expect(acceso.getByLabel('Correo de acceso Avance')).toHaveValue('corregido@example.invalid')
   await expect(page.getByRole('dialog', {name: 'Actualización pendiente'})).toHaveCount(0)
   await acceso.getByRole('button', {name: 'Revisar acceso Avance'}).click()
   await expect(acceso.getByRole('definition').filter({hasText: /^corregido@example\.invalid$/})).toBeVisible()
   await expect(acceso.getByRole('button', {name: 'Completar acceso Avance'})).toBeEnabled()
   await acceso.getByRole('button', {name: 'Completar acceso Avance'}).click()
   await expect(page.getByRole('dialog', {name: /Crear contrato de/})).toBeVisible()
 })
+
+test('volver a la ventana y recargar la página en las condiciones del contrato conservan el wizard y lo escrito', async ({page}) => {
+  const lead = leadReal({
+    vendedor_id: UID, nombre_completo: 'CLIENTE SINTÉTICO DE FOCO', dni: '71309001',
+    etapa: 'propuesta_enviada', monto_estimado: 20000,
+  })
+  const backend = await montarBackendReal(page, {rolCrm: 'vendedor', leads: [lead]})
+  await loginReal(page)
+  await page.goto('/#/cartera')
+  await page.getByRole('row', {name: `Abrir ficha de ${lead.nombre_completo}`, exact: true}).click()
+  const ficha = page.getByRole('dialog', {name: lead.nombre_completo, exact: true})
+  const llamadas = {identidad: 0, preparar: 0}
+  page.on('request', request => {
+    if (request.url().endsWith('/rpc/preparar_persona_lead_inversion_fn')) llamadas.identidad++
+    if (request.url().endsWith('/rpc/preparar_inversion_fn')) llamadas.preparar++
+  })
+  const acceso = await abrirConversionAvance(page, ficha)
+  await acceso.getByLabel('Apellidos', {exact: true}).fill('PRUEBA')
+  await acceso.getByLabel('Nombres', {exact: true}).fill('PERSONA')
+  await acceso.getByLabel('Correo de acceso Avance').fill('persona-foco@example.invalid')
+  await acceso.getByLabel('Domicilio legal').fill('Av. Javier Prado Este 123, San Isidro, Lima')
+  await acceso.getByRole('button', {name: 'Revisar acceso Avance'}).click()
+  await acceso.getByRole('button', {name: 'Completar acceso Avance'}).click()
+  const contrato = page.getByRole('dialog', {name: /Crear contrato de/})
+  const pasos = {name: 'Progreso de primera inversión Avance'}
+  await expect(contrato.getByRole('navigation', pasos)).toContainText('Paso 2 de 3')
+  await contrato.getByLabel('Capital', {exact: true}).fill('23000')
+  await contrato.getByLabel('N° de contrato', {exact: true}).fill('000719')
+  await contrato.getByRole('radio', {name: /BCP.*8901/i}).check()
+
+  // Preparar la identidad ESCRIBIÓ en el lead: el servidor ya tiene otra fecha de
+  // actualización y la cartera la trae al volver a la ventana. Antes eso cambiaba la
+  // consulta del documento, desmontaba el wizard y reaparecía el modal de identidad.
+  backend.leads = backend.leads.map(l => ({...l, actualizado_en: '2026-07-02T00:00:00.000Z'}))
+  // La ficha relee el documento con el lead nuevo: es la señal de que la resincronización llegó a pantalla.
+  const relectura = page.waitForResponse(r => r.url().endsWith('/rpc/documento_lead_fn'))
+  await page.evaluate(() => {
+    document.dispatchEvent(new Event('visibilitychange', {bubbles: true}))
+    window.dispatchEvent(new Event('focus'))
+  })
+  await relectura
+  await expect(contrato.getByRole('navigation', pasos)).toContainText('Paso 2 de 3')
+  await expect(contrato.getByLabel('Capital', {exact: true})).toHaveValue('23000')
+  await expect(contrato.getByLabel('N° de contrato', {exact: true})).toHaveValue('000719')
+  await expect(page.getByRole('dialog', {name: 'Convertir a cliente'})).toHaveCount(0)
+
+  // Recargar: la ficha vuelve por la URL y reabre el wizard donde estaba, sin pedir otra vez la identidad.
+  await page.reload()
+  const retomado = page.getByRole('dialog', {name: /Crear contrato de/})
+  await expect(retomado.getByRole('navigation', pasos)).toContainText('Paso 2 de 3')
+  await expect(retomado.getByLabel('Capital', {exact: true})).toHaveValue('23000')
+  await expect(retomado.getByLabel('N° de contrato', {exact: true})).toHaveValue('000719')
+  await expect(retomado.getByRole('radio', {name: /BCP.*8901/i})).toBeChecked()
+  await retomado.getByRole('button', {name: 'Revisar inversión'}).click()
+  await expect(page.getByRole('dialog', {name: 'Revisar inversión'}).getByRole('navigation', pasos)).toContainText('Paso 3 de 3')
+  // Una sola identidad y una sola solicitud en todo el recorrido: nada se duplicó.
+  expect(llamadas).toEqual({identidad: 1, preparar: 1})
+})
diff --git a/CRM-Avance-Corp/app/src/components/app/inversion-desde-lead-foco.test.tsx b/CRM-Avance-Corp/app/src/components/app/inversion-desde-lead-foco.test.tsx
new file mode 100644
index 00000000..1ae590fa
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/app/inversion-desde-lead-foco.test.tsx
@@ -0,0 +1,159 @@
+// Volver a la ventana o recargar la página no puede devolver al analista al
+// modal de identidad. Aquí el lector del documento es el REAL (solo se simula el
+// transporte): el fallo vivía en cómo su clave y su resultado decidían qué
+// diálogo se pinta.
+import {useEffect,useState} from 'react'
+import {beforeEach,describe,expect,it,vi} from 'vitest'
+import {act,render,screen,waitFor} from '@testing-library/react'
+import userEvent from '@testing-library/user-event'
+import {QueryClient,QueryClientProvider,focusManager} from '@tanstack/react-query'
+import {AuthContext,type AuthContextValue} from '@/lib/auth-context'
+import {StoreDataContext} from '@/lib/store-context'
+import type {StoreDataApi} from '@/lib/store'
+import type {Lead} from '@/lib/tipos'
+import {guardarIntentoInversion,leerConversionAbierta,leerIntentoInversion,nuevoIntentoInversion} from '@/lib/inversion-solicitud'
+import {ACTOR_F5,PERSONA_F5,FUENTE_F5} from '@/test/fixtures/f5'
+import {InversionDesdeLead} from './inversion-desde-lead'
+
+const api=vi.hoisted(()=>({persona:vi.fn(),contexto:vi.fn(),documento:vi.fn(),montajes:{n:0,desmontajes:0}}))
+vi.mock('@/lib/supabase',()=>({sb:{schema:()=>({rpc:(_nombre:string,args:{p_lead_id:string})=>{
+  const respuesta=Promise.resolve().then(()=>({data:api.documento(args.p_lead_id),error:null}))
+  return Object.assign(respuesta,{abortSignal:()=>respuesta})
+}})}}))
+vi.mock('@/data/inversion-solicitud-api',async original=>({...await original<typeof import('@/data/inversion-solicitud-api')>(),
+  prepararPersonaLeadInversion:api.persona,obtenerContextoConversionInversion:api.contexto}))
+// El wizard tiene su propia suite. Aquí solo importa si SOBREVIVE montado, con
+// lo que el analista ya escribió, y para qué persona y solicitud se abre.
+vi.mock('./inversion-nueva',()=>({InversionNueva:(p:{persona:string;origenLead:{solicitudId:string|null};
+  onCerrar:()=>void;onConfirmada:()=>void;onRevocado:()=>void})=>{
+  const [capital,setCapital]=useState('')
+  useEffect(()=>{api.montajes.n++;return()=>{api.montajes.desmontajes++}},[])
+  return <div role="dialog" aria-label="Nueva inversión">
+    <span data-testid="persona">{p.persona}</span><span data-testid="solicitud">{p.origenLead.solicitudId??'sin solicitud'}</span>
+    <label>Capital del contrato<input value={capital} onChange={e=>setCapital(e.target.value)}/></label>
+    <button onClick={p.onCerrar}>Cerrar y continuar después</button>
+    <button onClick={p.onConfirmada}>Confirmar inversión</button>
+    <button onClick={p.onRevocado}>Perder el acceso</button>
+  </div>
+}}))
+
+const LEAD='55555555-5555-4555-8555-555555555555'
+const OTRO_ACTOR='77777777-7777-4777-8777-777777777777'
+const lead:Lead={id:LEAD,nombre_completo:'PERSONA PRUEBA FOCO',telefono:'999888777',correo:'persona@pruebas.example',
+  dni:null,etapa:'propuesta_enviada',origen:'landing',monto_estimado:5000,moneda:'PEN',
+  vendedor_id:ACTOR_F5,vendedor_nombre:'ANALISTA F5',creado_en:'2026-09-01T12:00:00Z',
+  actualizado_en:'2026-10-01T15:00:00Z',activo:true}
+const sinVincular={lead_id:LEAD,inversionista_id:null,identificador_id:null,tipo:'DNI',numero:null,puede_corregir:false}
+const vinculado={...sinVincular,inversionista_id:PERSONA_F5,identificador_id:FUENTE_F5,numero:'93334444'}
+
+beforeEach(()=>{
+  vi.resetAllMocks();sessionStorage.clear();api.montajes.n=0;api.montajes.desmontajes=0
+  api.documento.mockReturnValue(sinVincular)
+  // Preparar la identidad ESCRIBE en el lead (inversionista_id): desde aquí el
+  // servidor responde con el documento vinculado y otra fecha de actualización.
+  api.persona.mockImplementation(async(leadId:string)=>{
+    api.documento.mockReturnValue(vinculado)
+    return {inversionista_id:PERSONA_F5,lead_id:leadId,solicitud_id:null}
+  })
+})
+function montar(actor=ACTOR_F5){
+  const qc=new QueryClient({defaultOptions:{queries:{retry:false}}}),onClose=vi.fn(),recargar=vi.fn().mockResolvedValue(true)
+  const auth={yo:{id:actor,rol:'vendedor',nombre_completo:'ANALISTA F5',demo:false,puede_contratar:true}} as AuthContextValue
+  const store={recargar} as unknown as StoreDataApi
+  const arbol=(l:Lead)=><QueryClientProvider client={qc}><AuthContext.Provider value={auth}><StoreDataContext.Provider value={store}>
+    <InversionDesdeLead l={l} onClose={onClose}/>
+  </StoreDataContext.Provider></AuthContext.Provider></QueryClientProvider>
+  const vista=render(arbol(lead))
+  return {user:userEvent.setup(),onClose,recargar,unmount:vista.unmount,conLead:(l:Lead)=>vista.rerender(arbol(l))}
+}
+async function llegarAlWizard(user:ReturnType<typeof userEvent.setup>){
+  await user.type(await screen.findByLabelText('Documento'),'93334444')
+  await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
+  await user.type(await screen.findByLabelText('Capital del contrato'),'25000')
+}
+const sigueElWizard=async()=>{
+  // Deja terminar cualquier relectura antes de mirar: el fallo aparecía DESPUÉS de cargar.
+  await waitFor(()=>expect(screen.queryByText('Documento del lead')).not.toBeInTheDocument())
+  expect(screen.queryByText('Registrar la inversión del lead')).not.toBeInTheDocument()
+  expect(screen.getByLabelText('Capital del contrato')).toHaveValue('25000')
+  expect(api.montajes).toEqual({n:1,desmontajes:0})
+}
+
+describe('Volver a la ventana con el wizard abierto',()=>{
+  it('la resincronización de la cartera (lead con otra fecha de actualización) conserva el wizard',async()=>{
+    const {user,conLead}=montar()
+    await llegarAlWizard(user)
+    // Es lo que hace el store al recuperar el foco: mismo lead, fila más reciente.
+    conLead({...lead,actualizado_en:'2026-10-01T15:00:42Z'})
+    await sigueElWizard()
+  })
+
+  it('recuperar el foco no vuelve a leer el documento ni toca el wizard',async()=>{
+    const {user}=montar()
+    await llegarAlWizard(user)
+    const lecturas=api.documento.mock.calls.length
+    await act(async()=>{focusManager.setFocused(false);focusManager.setFocused(true)})
+    await sigueElWizard()
+    expect(api.documento).toHaveBeenCalledTimes(lecturas)
+    focusManager.setFocused(undefined)
+  })
+
+  it('lo escrito en la identidad tampoco se pierde si la cartera se resincroniza antes de continuar',async()=>{
+    const {user,conLead}=montar()
+    await user.type(await screen.findByLabelText('Documento'),'93334444')
+    conLead({...lead,actualizado_en:'2026-10-01T15:00:42Z'})
+    await waitFor(()=>expect(screen.queryByText('Documento del lead')).not.toBeInTheDocument())
+    expect(screen.getByLabelText('Documento')).toHaveValue('93334444')
+  })
+})
+
+describe('Recargar la página con el wizard abierto',()=>{
+  it('lo retoma para la misma persona sin volver a pedir la identidad',async()=>{
+    const primera=montar()
+    await llegarAlWizard(primera.user)
+    // Recargar no avisa a nadie: el diálogo desaparece sin pasar por su cierre.
+    primera.unmount()
+    montar()
+    expect(await screen.findByTestId('persona')).toHaveTextContent(PERSONA_F5)
+    expect(screen.queryByText('Registrar la inversión del lead')).not.toBeInTheDocument()
+    expect(api.persona).toHaveBeenCalledOnce()
+  })
+
+  it('cerrarlo a propósito sí vuelve a pedir la identidad la próxima vez',async()=>{
+    const primera=montar()
+    await llegarAlWizard(primera.user)
+    await primera.user.click(screen.getByRole('button',{name:'Cerrar y continuar después'}))
+    expect(primera.onClose).toHaveBeenCalledOnce()
+    expect(leerConversionAbierta(ACTOR_F5,LEAD)).toBeNull()
+    primera.unmount()
+    montar()
+    expect(await screen.findByText('Registrar la inversión del lead')).toBeInTheDocument()
+  })
+
+  it('confirmar la inversión deja de retomarlo y recarga la cartera',async()=>{
+    const {user,recargar,onClose}=montar()
+    await llegarAlWizard(user)
+    await user.click(screen.getByRole('button',{name:'Confirmar inversión'}))
+    expect(leerConversionAbierta(ACTOR_F5,LEAD)).toBeNull()
+    expect(recargar).toHaveBeenCalledOnce();expect(onClose).not.toHaveBeenCalled()
+  })
+
+  it('perder el acceso lo cierra y borra también la solicitud guardada en la pestaña',async()=>{
+    const {user,onClose}=montar()
+    await llegarAlWizard(user)
+    guardarIntentoInversion(nuevoIntentoInversion(ACTOR_F5,PERSONA_F5,FUENTE_F5,{inversionista_id:PERSONA_F5,lead_id:LEAD,empresa:'avance'}))
+    await user.click(screen.getByRole('button',{name:'Perder el acceso'}))
+    expect(onClose).toHaveBeenCalledOnce()
+    expect(leerConversionAbierta(ACTOR_F5,LEAD)).toBeNull()
+    expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5,LEAD)).toBeNull()
+  })
+
+  it('otra cuenta en la misma pestaña no hereda el wizard',async()=>{
+    const primera=montar()
+    await llegarAlWizard(primera.user)
+    primera.unmount()
+    montar(OTRO_ACTOR)
+    expect(await screen.findByText('Registrar la inversión del lead')).toBeInTheDocument()
+    expect(screen.queryByTestId('persona')).not.toBeInTheDocument()
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/components/app/inversion-desde-lead.tsx b/CRM-Avance-Corp/app/src/components/app/inversion-desde-lead.tsx
index f37145eb..86c1032a 100644
--- a/CRM-Avance-Corp/app/src/components/app/inversion-desde-lead.tsx
+++ b/CRM-Avance-Corp/app/src/components/app/inversion-desde-lead.tsx
@@ -1,91 +1,105 @@
 import { useEffect, useRef, useState } from 'react'
 import { useQuery } from '@tanstack/react-query'
 import { Button } from '@/components/ui/button'
 import { Dialog, DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
 import { Input } from '@/components/ui/input'
 import { Label } from '@/components/ui/label'
 import { Select } from '@/components/ui/select'
 import { useAuth } from '@/lib/auth-context'
 import { useCRMData } from '@/lib/store-context'
 import type { Lead } from '@/lib/tipos'
 import { TIPOS_DOCUMENTO, TIPOS_DOCUMENTO_K, validarDocumento, type TipoDocumento } from '@/lib/documento'
-import { limpiarIntentosInversion } from '@/lib/inversion-solicitud'
+import { guardarConversionAbierta, leerConversionAbierta, limpiarConversionAbierta, limpiarIntentosInversion,
+  type ConversionAbierta } from '@/lib/inversion-solicitud'
 import { mensajeDeError, type CondicionesTasaLead } from '@/data/crm-api'
 import { prepararPersonaLeadInversion, obtenerContextoConversionInversion } from '@/data/inversion-solicitud-api'
 import { PanelCargando, PanelError } from '@/components/common/estado-panel'
 import { InversionNueva } from './inversion-nueva'
 import { useDocumentoLead, type DocumentoLead } from '@/data/documento-lead'
 
 type Propiedades = { l: Lead; condicionesTasa?: CondicionesTasaLead | undefined; onClose: () => void }
 
 export function InversionDesdeLead(props: Propiedades) {
-  const documento = useDocumentoLead(props.l)
-  if (documento.isPending || documento.isError || !documento.data) return <Dialog open onClose={props.onClose} ariaLabel="Convertir a cliente">
+  // El documento solo PRECARGA la identidad y se fija con la primera respuesta.
+  // Preparar la identidad escribe en el lead: al volver a la ventana la cartera
+  // se resincroniza, la consulta cambia de clave (o de resultado) y, si de ella
+  // dependiera qué se pinta, el wizard se desmontaría con todo lo ya escrito.
+  const [fijado, setFijado] = useState<DocumentoLead | null>(null)
+  const documento = useDocumentoLead(props.l, fijado === null)
+  // Solo vale una respuesta posterior a abrir: la ficha comparte esta consulta y
+  // su copia puede ser anterior a una corrección del documento.
+  const reciente = documento.isFetchedAfterMount && !documento.isError ? documento.data ?? null : null
+  if (fijado === null && reciente) setFijado(reciente)
+  const inicial = fijado ?? reciente
+  if (!inicial) return <Dialog open onClose={props.onClose} ariaLabel="Convertir a cliente">
     <DialogHeader><DialogTitle>Documento del lead</DialogTitle></DialogHeader>
     <DialogBody>{documento.isError
       ? <PanelError mensaje="No se pudo consultar el documento vinculado. Vuelve a intentarlo." onReintentar={() => void documento.refetch()} reintentando={documento.isFetching} />
       : <PanelCargando />}</DialogBody>
     <DialogFooter><Button variant="outline" onClick={props.onClose}>Volver a la ficha</Button></DialogFooter>
   </Dialog>
-  return <FormularioInversionDesdeLead key={`${props.l.id}:${documento.data.tipo}:${documento.data.numero}`} {...props} documentoInicial={documento.data} />
+  return <FormularioInversionDesdeLead {...props} documentoInicial={inicial} />
 }
 
 /** Adaptación de identidad; los campos y el guardado de la inversión pertenecen
  * exclusivamente a InversionNueva, igual que al entrar desde Cartera. */
 function FormularioInversionDesdeLead({l, condicionesTasa, onClose, documentoInicial}: Propiedades & { documentoInicial: DocumentoLead }) {
   const {yo} = useAuth()
   const {recargar} = useCRMData()
   const [tipo, setTipo] = useState<TipoDocumento>(documentoInicial.tipo)
   const [documento, setDocumento] = useState(documentoInicial.numero ?? '')
   const reconocido = documentoInicial.inversionista_id !== null
   const [nombre, setNombre] = useState(l.nombre_completo)
-  const [preparada, setPersona] = useState<Awaited<ReturnType<typeof prepararPersonaLeadInversion>> | null>(null)
+  // Tras recargar la página con el wizard abierto se retoma sin volver a pedir la
+  // identidad: InversionNueva la comprueba en el servidor al montarse.
+  const [preparada, setPersona] = useState<ConversionAbierta | null>(() => yo ? leerConversionAbierta(yo.id, l.id) : null)
   const confirmada = useQuery({queryKey: ['crm','conversion-confirmada',yo?.id,l.id],
     queryFn: ({signal}) => obtenerContextoConversionInversion(l.id, undefined, signal),
     enabled: l.etapa === 'convertido', retry: false, staleTime: 0, gcTime: 0})
   const persona = preparada ?? (confirmada.data?.solicitud_id ? {
     inversionista_id: confirmada.data.persona.inversionista_id, solicitud_id: confirmada.data.solicitud_id,
   } : null)
   const [ocupado, setOcupado] = useState(false)
   const [error, setError] = useState<string | null>(null)
   const enviando = useRef(false)
   const montado = useRef(true)
   useEffect(() => {montado.current = true; return () => {montado.current = false}}, [])
   if (!yo) return null
   if (persona) return <InversionNueva key={`${yo.id}:${l.id}:${persona.inversionista_id}`} actor={yo.id}
     persona={persona.inversionista_id} origenLead={{id: l.id, solicitudId: persona.solicitud_id, condiciones: condicionesTasa,
       monto: l.monto_estimado ?? null, moneda: l.moneda, tipoDocumento: confirmada.data?.documento_tipo ?? tipo}}
-    onCerrar={onClose} onConfirmada={() => {void recargar()}}
-    onRevocado={() => {limpiarIntentosInversion(yo.id, persona.inversionista_id, l.id); onClose()}} />
+    onCerrar={() => {limpiarConversionAbierta(yo.id, l.id); onClose()}}
+    onConfirmada={() => {limpiarConversionAbierta(yo.id, l.id); void recargar()}}
+    onRevocado={() => {limpiarConversionAbierta(yo.id, l.id); limpiarIntentosInversion(yo.id, persona.inversionista_id, l.id); onClose()}} />
   const cerrar = () => {if (!enviando.current) onClose()}
   if (l.etapa === 'convertido') return <Dialog open onClose={cerrar} ariaLabel="Inversión del lead">
     <DialogHeader><DialogTitle>Inversión del lead</DialogTitle></DialogHeader>
     <DialogBody>{confirmada.isError ? <PanelError mensaje={mensajeDeError(confirmada.error, 'No se pudo consultar la inversión.')}
       onReintentar={() => void confirmada.refetch()} reintentando={confirmada.isFetching} /> : confirmada.isPending ? <PanelCargando />
       : <p>Esta conversión se registró con el flujo anterior. Consulta su inversión en Cartera.</p>}</DialogBody>
     <DialogFooter><Button variant="outline" onClick={cerrar}>Volver a la ficha</Button></DialogFooter>
   </Dialog>
   return <Dialog open onClose={cerrar} ariaLabel="Convertir a cliente">
     <DialogHeader><DialogTitle>Registrar la inversión del lead</DialogTitle></DialogHeader>
     <form onSubmit={e => {
       e.preventDefault()
       if (enviando.current) return
       const doc = validarDocumento(tipo, documento)
       if (!doc.ok) {setError(doc.error); return}
       if (nombre.trim().length < 2) {setError('Completa el nombre de la persona.'); return}
       enviando.current = true; setOcupado(true); setError(null)
       void prepararPersonaLeadInversion(l.id, tipo, doc.valor, nombre.trim()).then(r => {
         if (r.lead_id !== l.id) throw new Error('No se pudo verificar el lead de esta inversión.')
-        if (montado.current) setPersona(r)
+        if (montado.current) {guardarConversionAbierta(yo.id, l.id, r); setPersona(r)}
       }).catch(e => {if (montado.current) setError(mensajeDeError(e, 'No se pudo verificar la identidad.'))})
         .finally(() => {enviando.current = false; if (montado.current) setOcupado(false)})
     }}>
       <DialogBody className="space-y-4">
         <p className="text-sm text-muted-foreground">Confirma la identidad para abrir Nueva inversión. El lead se convertirá en cliente al confirmar su inversión.</p>
         <div className="space-y-1"><Label htmlFor="conversion-nombre">Nombre completo</Label>
           <Input id="conversion-nombre" required maxLength={180} value={nombre} disabled={ocupado} onChange={e => setNombre(e.target.value)} /></div>
         <div className="grid gap-3 sm:grid-cols-2">
           <div className="space-y-1"><Label htmlFor="conversion-tipo">Tipo de documento</Label>
             <Select id="conversion-tipo" value={tipo} disabled={ocupado || reconocido} onChange={e => setTipo(e.target.value as TipoDocumento)}>
               {TIPOS_DOCUMENTO_K.map(k => <option key={k} value={k}>{TIPOS_DOCUMENTO[k].etiqueta}</option>)}
             </Select></div>
diff --git a/CRM-Avance-Corp/app/src/components/app/lead-drawer-convertir.test.tsx b/CRM-Avance-Corp/app/src/components/app/lead-drawer-convertir.test.tsx
index 5fda940d..877a5ee5 100644
--- a/CRM-Avance-Corp/app/src/components/app/lead-drawer-convertir.test.tsx
+++ b/CRM-Avance-Corp/app/src/components/app/lead-drawer-convertir.test.tsx
@@ -1,24 +1,24 @@
 // Formulario compartido desde el lead. SQL/Auth se prueban en el banco aislado.
 import {beforeEach,describe,expect,it,vi} from 'vitest'
 import {act,fireEvent,render,screen,waitFor} from '@testing-library/react'
 import userEvent from '@testing-library/user-event'
 import {QueryClient,QueryClientProvider} from '@tanstack/react-query'
 import {AuthContext,type AuthContextValue} from '@/lib/auth-context'
 import {StoreDataContext} from '@/lib/store-context'
 import type {StoreDataApi} from '@/lib/store'
 import type {Lead} from '@/lib/tipos'
 import {CrmApiError,type CrearContratoInput} from '@/data/crm-api'
 import type {CuotaCronograma} from '@/lib/cronograma'
-import {guardarIntentoInversion,leerIntentoInversion,nuevoIntentoInversion,type DatosInversion,type SolicitudInversion} from '@/lib/inversion-solicitud'
+import {guardarIntentoInversion,leerConversionAbierta,leerIntentoInversion,nuevoIntentoInversion,type DatosInversion,type SolicitudInversion} from '@/lib/inversion-solicitud'
 import {ACTOR_F5,PERSONA_F5,PERFIL_F5,FUENTE_F5,fichaF5} from '@/test/fixtures/f5'
 import {DialogConvertir} from './lead-drawer'
 
 const api=vi.hoisted(()=>({persona:vi.fn(),contexto:vi.fn(),ficha:vi.fn(),preparar:vi.fn(),consultar:vi.fn(),
   corregir:vi.fn(),confirmar:vi.fn(),cancelar:vi.fn(),acceso:vi.fn(),subir:vi.fn(),bienvenida:vi.fn(),convertirAnterior:vi.fn(),documento:vi.fn()}))
 vi.mock('@/data/documento-lead',()=>({useDocumentoLead:api.documento}))
 vi.mock('@/data/inversion-solicitud-api',async original=>({...await original<typeof import('@/data/inversion-solicitud-api')>(),
   prepararPersonaLeadInversion:api.persona,obtenerContextoConversionInversion:api.contexto,
   prepararSolicitudInversion:api.preparar,consultarSolicitudInversion:api.consultar,
   corregirSolicitudInversion:api.corregir,confirmarSolicitudInversion:api.confirmar,cancelarSolicitudInversion:api.cancelar,
   completarAccesoInversion:api.acceso,subirComprobanteInversion:api.subir,enviarBienvenidaInversion:api.bienvenida}))
 vi.mock('@/data/inversionistas-api',async original=>({...await original<typeof import('@/data/inversionistas-api')>(),obtenerFichaInversionista:api.ficha}))
@@ -46,25 +46,25 @@ const lead:Lead={id:LEAD,nombre_completo:'PERSONA PRUEBA CONVERSIÓN',telefono:'
   vendedor_id:ACTOR_F5,vendedor_nombre:'ANALISTA F5',creado_en:'2026-09-01T12:00:00Z',activo:true}
 let vigente:SolicitudInversion|null
 let perfil:string|null
 let correoFicha:string|null
 const preparada=(clave:string,datos:DatosInversion):SolicitudInversion=>({solicitud_id:clave,lead_id:LEAD,estado:'preparada',
   inversion_id:null,inversionista_id:PERSONA_F5,inversionista_origen_id:PERSONA_F5,identidad_fusionada:false,
   responsable_esperado_id:ACTOR_F5,responsable_actual_id:ACTOR_F5,requiere_revision_responsable:false,
   revision_datos:0,revision_responsable:0,hash_datos:'huella',necesita_portal:datos.empresa==='avance'&&!perfil,
   comprobante_bucket:datos.empresa==='avance'?null:'f4-comprobantes',comprobante_ruta:datos.evidencia?.ruta??null,resultado:null,datos})
 beforeEach(()=>{
   vi.resetAllMocks();sessionStorage.clear();vigente=null;perfil=null;correoFicha=fichaF5.persona.correo
   api.documento.mockImplementation((l:Lead)=>({data:{lead_id:l.id,inversionista_id:null,identificador_id:null,
-    tipo:l.documento?.tipo??'DNI',numero:l.documento?.numero??l.dni??null,puede_corregir:false},isPending:false,isError:false}))
+    tipo:l.documento?.tipo??'DNI',numero:l.documento?.numero??l.dni??null,puede_corregir:false},isPending:false,isError:false,isFetchedAfterMount:true}))
   api.persona.mockImplementation(async(leadId:string)=>({inversionista_id:PERSONA_F5,lead_id:leadId,solicitud_id:vigente?.solicitud_id??null}))
   api.contexto.mockImplementation(async()=>({...fichaF5,solicitud_id:vigente?.solicitud_id??null,documento_tipo:'DNI',persona:{...fichaF5.persona,perfil_id:perfil,correo:correoFicha}}))
   api.cancelar.mockImplementation(async()=>{vigente={...vigente!,estado:'cancelada'};return vigente})
   api.preparar.mockImplementation(async i=>{vigente=preparada(i.clave,i.datos);if(i.datos.alta_portal)correoFicha=i.datos.alta_portal.correo;return vigente})
   api.consultar.mockImplementation(async()=>{if(!vigente)throw new CrmApiError('Solicitud no encontrada','P0002');return vigente})
   api.corregir.mockImplementation(async i=>{vigente={...vigente!,datos:i.correccion.datos,revision_datos:vigente!.revision_datos+1,necesita_portal:!perfil};if(i.correccion.datos.alta_portal)correoFicha=i.correccion.datos.alta_portal.correo;return vigente})
   api.acceso.mockImplementation(async()=>{perfil=PERFIL_F5;vigente={...vigente!,necesita_portal:false};return {ok:true,solicitud_id:vigente.solicitud_id,perfil_id:perfil}})
   api.confirmar.mockImplementation(async()=>{
     const resultado={ok:true as const,solicitud_id:vigente!.solicitud_id,inversion_id:FUENTE_F5,inversionista_id:PERSONA_F5,
       empresa:vigente!.datos!.empresa,fuente:vigente!.datos!.empresa==='avance'?{id:FUENTE_F5}:{cierre_id:FUENTE_F5}}
     vigente={...vigente!,estado:'confirmada',inversion_id:FUENTE_F5,resultado};return resultado
   })
@@ -78,25 +78,25 @@ function montar(datos:Partial<Lead>={}){
   const vista=render(<QueryClientProvider client={qc}><AuthContext.Provider value={auth}><StoreDataContext.Provider value={store}>
     <DialogConvertir l={{...lead,...datos}} onClose={onClose}/>
   </StoreDataContext.Provider></AuthContext.Provider></QueryClientProvider>)
   return {...vista,user:userEvent.setup(),onClose,recargar,convertir,qc}
 }
 async function entrar(user:ReturnType<typeof userEvent.setup>,empresa:string){
   await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
   await user.click(await screen.findByRole('button',{name:empresa}))
 }
 
 describe('Documento vinculado al convertir',()=>{
   it.each([['CE','001234567'],['PASAPORTE','AB12345678']] as const)('precarga y utiliza %s aunque el DNI legado esté vacío',async(tipo,numero)=>{
-    api.documento.mockReturnValue({data:{lead_id:LEAD,tipo,numero,inversionista_id:PERSONA_F5,identificador_id:FUENTE_F5,puede_corregir:false}})
+    api.documento.mockReturnValue({data:{lead_id:LEAD,tipo,numero,inversionista_id:PERSONA_F5,identificador_id:FUENTE_F5,puede_corregir:false},isFetchedAfterMount:true})
     const {user}=montar({dni:null})
     expect(screen.getByLabelText('Tipo de documento')).toHaveValue(tipo)
     expect(screen.getByLabelText('Documento')).toHaveValue(numero)
     expect(screen.getByLabelText('Documento')).toBeDisabled()
     await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
     expect(api.persona).toHaveBeenCalledWith(LEAD,tipo,numero,lead.nombre_completo)
   })
 
   it('un error al consultar identidad no permite convertir con el DNI antiguo',()=>{
     api.documento.mockReturnValue({data:undefined,isError:true,refetch:vi.fn()})
     montar()
     expect(screen.getByText(/No se pudo consultar el documento vinculado/)).toBeInTheDocument()
@@ -236,27 +236,28 @@ describe('Recuperar el primer acceso rechazado',()=>{
       vigente=preparada(otraClave,i.datos);correoFicha=i.datos.alta_portal.correo
       throw new CrmApiError('Este lead ya tiene una solicitud: retómala antes de crear otra','P0409')
     })
     api.consultar.mockImplementation(async id=>{
       if(id!==vigente?.solicitud_id)throw new CrmApiError('Solicitud no encontrada','P0002')
       return vigente
     })
     const primera=montar();await entrar(primera.user,'Avance');llenarAcceso()
     await primera.user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
     await screen.findByRole('button',{name:'Retomar solicitud registrada'})
     let user=primera.user
     if(reabrir){
+      // Desmontar sin cerrar es recargar la página: el wizard se retoma sin volver a pedir la identidad.
       primera.unmount();user=montar().user
-      await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
       await screen.findByRole('button',{name:'Retomar solicitud registrada'})
+      expect(api.persona).toHaveBeenCalledOnce()
     }
     expect(screen.queryByLabelText('Nombres')).not.toBeInTheDocument()
     await user.click(screen.getByRole('button',{name:'Retomar solicitud registrada'}))
     await screen.findByRole('button',{name:'Completar acceso Avance'})
     expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5,LEAD)?.clave).toBe(otraClave)
     expect(api.preparar).toHaveBeenCalledOnce();expect(api.acceso).not.toHaveBeenCalled()
   })
   it('conserva el token del primer envío si la lectura falla con 22023 después de guardar',async()=>{
     api.preparar.mockImplementationOnce(async i=>{
       vigente=preparada(i.clave,i.datos);correoFicha=i.datos.alta_portal.correo
       throw new CrmApiError('Lectura rechazada después de preparar','22023')
     })
@@ -394,24 +395,46 @@ describe('Convertir a cliente usa Nueva inversión',()=>{
     await screen.findByRole('heading',{name:'Condiciones del contrato compartido'})
     expect(screen.getByTestId('origen-tasa')).toHaveTextContent(LEAD);expect(screen.getByTestId('analista')).toHaveTextContent(ACTOR_F5)
     expect(api.confirmar).not.toHaveBeenCalled();expect(recargar).not.toHaveBeenCalled();expect(convertir).not.toHaveBeenCalled()
     expect(api.bienvenida).not.toHaveBeenCalled()
     await user.click(screen.getByRole('button',{name:'Revisar contrato compartido'}))
     await user.click(await screen.findByRole('button',{name:'Confirmar inversión'}))
     await screen.findByRole('heading',{name:'Inversión confirmada'})
     expect(api.confirmar).toHaveBeenCalledWith(vigente!.solicitud_id,1);expect(recargar).toHaveBeenCalledOnce()
     await waitFor(()=>expect(api.bienvenida).toHaveBeenCalledExactlyOnceWith(vigente!.solicitud_id))
     expect(vigente!.datos!.contrato).not.toHaveProperty('analista_cierre_id');expect(vigente!.datos!.contrato).not.toHaveProperty('cliente_id')
     expect(api.convertirAnterior).not.toHaveBeenCalled()
   })
+  it('recargar la página en las condiciones del contrato retoma el wizard y el contrato se crea una sola vez',async()=>{
+    const primera=montar();await entrar(primera.user,'Avance')
+    await primera.user.type(screen.getByLabelText('Nombres'),'PERSONA');await primera.user.type(screen.getByLabelText('Apellidos'),'PRUEBA CONVERSIÓN')
+    await primera.user.type(screen.getByLabelText('Domicilio legal'),'AVENIDA SINTETICA 123 LIMA')
+    await primera.user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
+    await primera.user.click(await screen.findByRole('button',{name:'Completar acceso Avance'}))
+    await screen.findByRole('heading',{name:'Condiciones del contrato compartido'})
+    const clave=vigente!.solicitud_id
+    // Recargar no pasa por el cierre del diálogo: la pestaña conserva la solicitud y que el wizard estaba abierto.
+    primera.unmount()
+    const {user,recargar}=montar()
+    await screen.findByRole('heading',{name:'Condiciones del contrato compartido'})
+    expect(screen.queryByRole('button',{name:'Continuar a Nueva inversión'})).not.toBeInTheDocument()
+    expect(api.contexto).toHaveBeenLastCalledWith(LEAD,PERSONA_F5,expect.any(AbortSignal))
+    expect(api.consultar).toHaveBeenCalledWith(clave,expect.any(AbortSignal))
+    await user.click(screen.getByRole('button',{name:'Revisar contrato compartido'}))
+    await user.click(await screen.findByRole('button',{name:'Confirmar inversión'}))
+    await screen.findByRole('heading',{name:'Inversión confirmada'})
+    expect(api.persona).toHaveBeenCalledOnce();expect(api.preparar).toHaveBeenCalledOnce();expect(api.acceso).toHaveBeenCalledOnce()
+    expect(api.confirmar.mock.calls).toEqual([[clave,1]]);expect(recargar).toHaveBeenCalledOnce()
+    expect(leerConversionAbierta(ACTOR_F5,LEAD)).toBeNull()
+  })
   it('guarda y recupera el acceso; señala domicilio inválido y permite corregir el correo antes de crear la cuenta',async()=>{
     const primera=montar();await entrar(primera.user,'Avance')
     expect(screen.getByRole('navigation',{name:'Progreso de primera inversión Avance'})).toHaveTextContent('Paso 1 de 3')
     await primera.user.type(screen.getByLabelText('Apellidos'),'PRUEBA')
     await primera.user.type(screen.getByLabelText('Nombres'),'PERSONA')
     await primera.user.clear(screen.getByLabelText('Correo de acceso Avance'))
     await primera.user.type(screen.getByLabelText('Correo de acceso Avance'),'persona-correcta@example.invalid')
     await primera.user.type(screen.getByLabelText('Domicilio legal'),'Av. Corta 1')
     expect(screen.getByRole('status')).toHaveTextContent('Borrador guardado')
     await primera.user.click(screen.getByRole('button',{name:'Cerrar y continuar después'}))
     expect(primera.onClose).toHaveBeenCalledOnce();expect(api.preparar).not.toHaveBeenCalled()
     primera.unmount()
@@ -485,26 +508,28 @@ describe('Convertir a cliente usa Nueva inversión',()=>{
     const esperado=boton==='Usar correo de la ficha'?'ficha-nueva@example.invalid':'anterior@example.invalid'
     expect(vigente!.datos!.alta_portal!.correo).toBe(esperado);expect(correoFicha).toBe(esperado)
     expect(api.corregir).toHaveBeenCalledOnce();expect(api.acceso).not.toHaveBeenCalled()
   })
   it('un borrador anterior muestra el correo actual de la ficha y permite usarlo',async()=>{
     prepararAccesoPendiente()
     const primera=montar();await primera.user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
     await primera.user.click(await screen.findByRole('button',{name:'Corregir datos de acceso'}))
     await primera.user.type(screen.getByLabelText('Nombres',{exact:true}),' EXTRA')
     primera.unmount()
     correoFicha='ficha-actual@example.invalid'
     vigente={...vigente!,revision_datos:1,datos:{...vigente!.datos!,alta_portal:{...vigente!.datos!.alta_portal!,correo:correoFicha}}}
-    const segunda=montar();await segunda.user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
+    // Desmontar sin cerrar es recargar la página: vuelve directo al acceso, con su borrador.
+    const segunda=montar()
     expect(await screen.findByLabelText('Correo de acceso Avance')).toHaveValue('anterior@example.invalid')
+    expect(screen.queryByRole('button',{name:'Continuar a Nueva inversión'})).not.toBeInTheDocument()
     expect(screen.getByText('ficha-actual@example.invalid')).toBeInTheDocument()
     await segunda.user.click(screen.getByRole('button',{name:'Usar correo de la ficha'}))
     expect(screen.getByLabelText('Correo de acceso Avance')).toHaveValue('ficha-actual@example.invalid')
     expect(screen.getByLabelText('Nombres',{exact:true})).toHaveValue('PERSONA EXTRA')
     await segunda.user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
     await screen.findByRole('button',{name:'Completar acceso Avance'})
     expect(vigente!.datos!.alta_portal!.correo).toBe(correoFicha)
   })
   it.each(['P0409','PT409','22023','P0429','55P03'])('rechazo definitivo %s conserva lo escrito y permite volver a corregir',async(codigo)=>{
     prepararAccesoPendiente()
     const {user}=montar();await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
     await user.click(await screen.findByRole('button',{name:'Corregir datos de acceso'}))
diff --git a/CRM-Avance-Corp/app/src/components/app/lead-drawer-retomar-conversion.test.tsx b/CRM-Avance-Corp/app/src/components/app/lead-drawer-retomar-conversion.test.tsx
new file mode 100644
index 00000000..4d0076e9
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/app/lead-drawer-retomar-conversion.test.tsx
@@ -0,0 +1,133 @@
+// Recargar la página con el wizard de conversión abierto: la ficha lo reabre sola,
+// pero solo cuando ya conoce las condiciones de tasa (el contrato las toma al
+// montarse) y solo si la marca de ESTA pestaña sigue ahí.
+import { beforeEach, describe, expect, it, vi } from 'vitest'
+import { render, screen } from '@testing-library/react'
+import userEvent from '@testing-library/user-event'
+import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
+import { PanelActionsContext, PanelStateContext, StoreDataContext } from '@/lib/store-context'
+import type { PanelesActions, StoreDataApi } from '@/lib/store'
+import type { Lead } from '@/lib/tipos'
+import { guardarConversionAbierta, limpiarConversionAbierta } from '@/lib/inversion-solicitud'
+import type { EstadoCondicionesLead } from './condiciones-tasa-lead'
+import { LeadDrawer } from './lead-drawer'
+
+vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() } }))
+vi.mock('@/data/documento-lead', () => ({ useDocumentoLead: () => ({ data: undefined, isPending: false, isError: false }) }))
+vi.mock('@/data/cliente-existente-api', () => ({ buscarClienteExistente: vi.fn(), obtenerContextoClienteExistente: vi.fn(),
+  cuentasClienteExistente: vi.fn(), datosLegalesClienteExistente: vi.fn(), contratosUpgradeClienteExistente: vi.fn() }))
+vi.mock('@/data/crm-queries', () => ({
+  useHistorialLead: () => ({ data: undefined, dataUpdatedAt: 0, hasNextPage: false, isFetchingNextPage: false,
+    isPending: false, error: null, fetchNextPage: vi.fn(), refetch: vi.fn() }),
+  usePoliticaRentabilidad: () => ({ data: undefined, isPending: true, isError: false }),
+  useSolicitudesTasa: () => ({ data: [], isPending: true, isError: false }),
+  useCierresEstado: () => ({ data: [] }),
+  useConversionEstado: () => ({ data: undefined, isError: false }),
+  useAnularCierreAvance: () => ({ mutateAsync: vi.fn() }),
+  useConvertirLeadExterno: () => ({ mutateAsync: vi.fn() }),
+  useCuentasBancariasCliente: () => ({ data: [], isPending: false, isError: false, isFetching: false, refetch: vi.fn() }),
+}))
+vi.mock('@/data/sla-operacion-queries', () => ({ useEstadosSlaV2: () => ({ data: { modo: 'legado', filas: [] }, error: null }) }))
+// Las condiciones de tasa llegan cuando la prueba lo decide, como en la ficha real.
+vi.mock('./condiciones-tasa-lead', () => ({
+  SolicitudTasaLeadPlegable: ({ onCambio }: { onCambio: (estado: EstadoCondicionesLead | null) => void }) =>
+    <button onClick={() => onCambio({ bloqueo: null } as EstadoCondicionesLead)}>Llegan las condiciones</button>,
+}))
+vi.mock('./inversion-desde-lead', () => ({
+  InversionDesdeLead: ({ onClose }: { onClose: () => void }) =>
+    <div role="dialog" aria-label="Wizard de conversión"><button onClick={onClose}>Cerrar el wizard</button></div>,
+}))
+vi.mock('./inversion-desde-lead-demo', () => ({
+  InversionDesdeLeadDemo: () => <div role="dialog" aria-label="Wizard de conversión demo" />,
+}))
+
+const VENDEDOR = '11111111-1111-4111-8111-111111111111'
+const OTRO = '22222222-2222-4222-8222-222222222222'
+const LEAD: Lead = {
+  id: '33333333-3333-4333-8333-333333333333', nombre_completo: 'PERSONA EN CONVERSIÓN', telefono: '+51987654321', correo: null,
+  etapa: 'propuesta_enviada', origen: 'landing', monto_estimado: 5000, moneda: 'PEN', categoria_interes: null, vendedor_id: VENDEDOR,
+  vendedor_nombre: 'ANALISTA A', asignado_supervisor_id: null, creado_en: '2026-09-01T12:00:00.000Z', activo: true, dni: '70000021',
+  distrito: null, nota: null, motivo_descarte: null,
+}
+const PERSONA = { inversionista_id: '44444444-4444-4444-8444-444444444444', solicitud_id: null }
+const actions: PanelesActions = { abrirLead: vi.fn(), abrirNuevoLead: vi.fn(), cerrarPaneles: vi.fn() }
+
+function montar({ lead = LEAD, demo = false }: { lead?: Lead; demo?: boolean } = {}) {
+  const sesion = { fase: 'listo', yo: { id: VENDEDOR, nombre_completo: 'ANALISTA A', rol: 'vendedor', demo, puede_contratar: true },
+    error: null, entrar: async () => ({ ok: true }), entrarDemo: () => undefined, reintentar: () => undefined,
+    salir: async () => undefined } as unknown as AuthContextValue
+  const api = {
+    lead: (id: string) => (id === lead.id ? lead : undefined), ambito: { leads: [lead], vendedores: [], esGlobal: false },
+    actividadesDe: () => [], tareasDe: () => [], crearTarea: vi.fn(), anularTarea: vi.fn(), editarLead: vi.fn(),
+    reasignar: vi.fn(), cambiarEtapa: vi.fn(), registrarActividad: vi.fn(), anularCierreAvance: vi.fn(),
+    cierresEstado: [], recargar: vi.fn(async () => true), reabrir: vi.fn(),
+  } as unknown as StoreDataApi
+  render(
+    <AuthContext.Provider value={sesion}>
+      <StoreDataContext.Provider value={api}>
+        <PanelStateContext.Provider value={{ leadAbiertoId: lead.id, nuevoLeadAbierto: false, etapaInicial: 'nuevo', telefonoInicial: null }}>
+          <PanelActionsContext.Provider value={actions}><LeadDrawer /></PanelActionsContext.Provider>
+        </PanelStateContext.Provider>
+      </StoreDataContext.Provider>
+    </AuthContext.Provider>,
+  )
+  return userEvent.setup()
+}
+const wizard = () => screen.queryByRole('dialog', { name: 'Wizard de conversión' })
+const lleganLasCondiciones = (user: ReturnType<typeof userEvent.setup>) =>
+  user.click(screen.getByRole('button', { name: 'Llegan las condiciones' }))
+beforeEach(() => { vi.clearAllMocks(); sessionStorage.clear() })
+
+describe('la ficha retoma el wizard de conversión tras recargar', () => {
+  it('lo reabre sola en cuanto conoce las condiciones de tasa, no antes', async () => {
+    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
+    const user = montar()
+    expect(wizard()).not.toBeInTheDocument()
+    await lleganLasCondiciones(user)
+    expect(wizard()).toBeInTheDocument()
+  })
+
+  it('sin wizard abierto antes de recargar, la ficha no abre nada', async () => {
+    const user = montar()
+    await lleganLasCondiciones(user)
+    expect(wizard()).not.toBeInTheDocument()
+  })
+
+  it('el wizard de otra cuenta o de otro lead no se abre en esta ficha', async () => {
+    guardarConversionAbierta(OTRO, LEAD.id, PERSONA)
+    guardarConversionAbierta(VENDEDOR, OTRO, PERSONA)
+    const user = montar()
+    await lleganLasCondiciones(user)
+    expect(wizard()).not.toBeInTheDocument()
+  })
+
+  it('si la marca desaparece mientras llegan las condiciones, no reaparece', async () => {
+    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
+    const user = montar()
+    limpiarConversionAbierta(VENDEDOR, LEAD.id)
+    await lleganLasCondiciones(user)
+    expect(wizard()).not.toBeInTheDocument()
+  })
+
+  it('cerrado a mano no se reabre cuando las condiciones vuelven a cambiar', async () => {
+    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
+    const user = montar()
+    await lleganLasCondiciones(user)
+    await user.click(screen.getByRole('button', { name: 'Cerrar el wizard' }))
+    expect(wizard()).not.toBeInTheDocument()
+    await lleganLasCondiciones(user)
+    expect(wizard()).not.toBeInTheDocument()
+  })
+
+  it('un lead ya convertido no espera condiciones: no las tiene', () => {
+    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
+    montar({ lead: { ...LEAD, etapa: 'convertido' } })
+    expect(wizard()).toBeInTheDocument()
+  })
+
+  it('el modo demo nunca retoma un wizard real', () => {
+    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
+    montar({ demo: true, lead: { ...LEAD, etapa: 'convertido' } })
+    expect(screen.queryByRole('dialog', { name: /Wizard de conversión/ })).not.toBeInTheDocument()
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/components/app/lead-drawer.tsx b/CRM-Avance-Corp/app/src/components/app/lead-drawer.tsx
index 7e6d6e41..32b5d346 100644
--- a/CRM-Avance-Corp/app/src/components/app/lead-drawer.tsx
+++ b/CRM-Avance-Corp/app/src/components/app/lead-drawer.tsx
@@ -1,17 +1,18 @@
 import { useDocumentoLead } from '@/data/documento-lead'
 import { TIPOS_DOCUMENTO, TIPOS_DOCUMENTO_K, type TipoDocumento } from '@/lib/documento'
 import { SolicitudTasaLeadPlegable, type EstadoCondicionesLead } from './condiciones-tasa-lead'
 import { InversionDesdeLead } from './inversion-desde-lead'
 import { InversionDesdeLeadDemo } from './inversion-desde-lead-demo'
+import { leerConversionAbierta } from '@/lib/inversion-solicitud'
 import { VentaCruzada } from './venta-cruzada'
 import { buscarClienteExistente, type BusquedaCliente } from '@/data/cliente-existente-api'
 import type { CondicionesTasaLead } from '@/data/crm-api'
 import { fechaSla, puedeRegistrarGestionSla, type AvisoSla } from '@/lib/sla-operacion'
 import { useEstadosSlaV2 } from '@/data/sla-operacion-queries'
 import { EstadoSlaFicha } from '@/components/app/sla-operacion'
 import { RegistrarResultado } from '@/components/gestion-diaria/registrar-resultado'
 // Ficha del lead (drawer derecho) — F1b. Se monta UNA vez en App.tsx y se abre
 // desde cualquier pantalla vía usePanelesActions().abrirLead(id). Write-gating doble:
 // la UI oculta acciones (directorio = solo lectura total) y el store re-valida.
 // Los errores de validación del store ({ok:false, error} SIN toast) se muestran
 // inline en los forms o con toast.error en acciones sueltas.
@@ -163,24 +164,34 @@ function Ficha({ l }: { l: Lead }) {
   const enMiEquipo = tieneAnalista && ambito.vendedores.some((m) => m.perfil_id === l.vendedor_id)
   const operaEquipo = escribe && can(rol, 'verEquipo') && enMiEquipo
   const puedeConvertir =
     escribe && (yo?.puede_contratar ?? false) && (seraMiCliente || (operaGlobal && tieneAnalista) || operaEquipo)
   const esTerminal = l.etapa === 'convertido' || l.etapa === 'descartado'
   const [dialogo, setDialogo] = useState<'convertir' | 'descartar' | null>(null)
   // Reabrir el descarte de alguien que ya es cliente no reabre nada: se muestra quién es y se
   // ofrece su venta cruzada. Vive aquí y no en el banner: el reabrir optimista pasa el lead a
   // «Nuevo» (y desmonta el banner) antes de que el servidor responda.
   const [clienteDelLead, setClienteDelLead] = useState<BusquedaCliente | null>(null)
   const [condicionesLead, setCondicionesLead] = useState<EstadoCondicionesLead | null>(null)
   const bloqueoTasa = condicionesLead?.bloqueo ?? (condicionesLead ? null : 'Verifica las condiciones de inversión antes de convertir.')
+  // Recargar la página con el wizard de conversión abierto lo retoma. Espera a
+  // conocer las condiciones de tasa: el contrato las toma al montarse. Si no
+  // llegan, «Convertir a cliente» lo retoma igual, sin volver a pedir la identidad.
+  const conversionAbierta = () => Boolean(yo && !yo.demo && leerConversionAbierta(yo.id, l.id))
+  const [retomarConversion, setRetomarConversion] = useState(conversionAbierta)
+  if (retomarConversion && (condicionesLead !== null || esTerminal || !tieneAnalista)) {
+    setRetomarConversion(false)
+    // Se vuelve a mirar la marca: quien ya cerró el wizard a mano no quiere que reaparezca.
+    if (conversionAbierta()) setDialogo(actual => actual ?? 'convertir')
+  }
   // Señal header → Datos: el badge "Sin capital estimado" abre el modo edición
   // de la sección Datos sin duplicar su estado (contador incremental).
   const [pedirEditarDatos, setPedirEditarDatos] = useState(0)
   const [componiendoGestion, setComponiendoGestion] = useState(false)
   const [tareaAviso, setTareaAviso] = useState<Tarea | null>(null)
   const refEtapa = useRef<HTMLDivElement>(null)
   const refDatos = useRef<HTMLDivElement>(null)
   const refActividad = useRef<HTMLDivElement>(null)
   async function actuarSobreAviso(aviso: AvisoSla) {
     if (aviso.bucket === 'tarea_vencida') {
       try {
         const tarea = aviso.tarea_id ? await obtenerTareaParaRevision(l.id, aviso.tarea_id) : null
diff --git a/CRM-Avance-Corp/app/src/data/documento-lead.ts b/CRM-Avance-Corp/app/src/data/documento-lead.ts
index f64b91f9..a10c7029 100644
--- a/CRM-Avance-Corp/app/src/data/documento-lead.ts
+++ b/CRM-Avance-Corp/app/src/data/documento-lead.ts
@@ -5,28 +5,30 @@ import type { Lead } from '@/lib/tipos'
 import { DocumentoLeadSchema, type DocumentoLead } from '@/lib/documento-lead'
 export type { DocumentoLead } from '@/lib/documento-lead'
 import { CrmApiError } from './crm-api'
 import { respuestaInversionistas } from './inversionistas-api'
 export async function obtenerDocumentoLead(lead: string, signal?: AbortSignal): Promise<DocumentoLead> {
   if (!sb) throw new CrmApiError('La conexión no está disponible.', 'SUPABASE_NOT_CONFIGURED')
   const consulta = sb.schema('crm').rpc('documento_lead_fn', { p_lead_id: lead })
   const documento = respuestaInversionistas(DocumentoLeadSchema, await (signal ? consulta.abortSignal(signal) : consulta))
   if (documento.lead_id !== lead) throw new CrmApiError('El documento no corresponde al lead consultado.', 'DOCUMENTO_LEAD_CONTRACT')
   return documento
 }
 
-/** Solo al abrir una ficha/conversión; nunca una consulta extra por fila de cartera. */
-export function useDocumentoLead(lead: Lead) {
+/** Solo al abrir una ficha/conversión; nunca una consulta extra por fila de cartera.
+ * `activa` en falso deja de leer: quien ya fijó el documento no necesita relecturas. */
+export function useDocumentoLead(lead: Lead, activa = true) {
   const { yo } = useAuth()
   const consulta = useQuery({
     queryKey: ['crm', 'leads', 'documento', yo?.id, lead.id, lead.actualizado_en],
     queryFn: ({ signal }) => obtenerDocumentoLead(lead.id, signal),
-    enabled: Boolean(yo && !yo.demo), retry: false, staleTime: 0, gcTime: 0,
+    enabled: Boolean(yo && !yo.demo) && activa, retry: false, staleTime: 0, gcTime: 0,
   })
   const demo: DocumentoLead = {
     lead_id: lead.id, inversionista_id: null, identificador_id: null,
     tipo: lead.documento?.tipo ?? 'DNI', numero: lead.documento?.numero ?? lead.dni ?? null,
     puede_corregir: false,
   }
   return { ...consulta, data: yo?.demo ? demo : consulta.data,
-    isPending: Boolean(!yo?.demo && consulta.isPending), isError: Boolean(!yo?.demo && consulta.isError) }
+    isPending: Boolean(!yo?.demo && consulta.isPending), isError: Boolean(!yo?.demo && consulta.isError),
+    isFetchedAfterMount: Boolean(yo?.demo) || consulta.isFetchedAfterMount }
 }
diff --git a/CRM-Avance-Corp/app/src/lib/inversion-solicitud.test.ts b/CRM-Avance-Corp/app/src/lib/inversion-solicitud.test.ts
index 2bf7a39e..ca4bd800 100644
--- a/CRM-Avance-Corp/app/src/lib/inversion-solicitud.test.ts
+++ b/CRM-Avance-Corp/app/src/lib/inversion-solicitud.test.ts
@@ -1,14 +1,15 @@
 import {describe,it,expect} from 'vitest'
 import {datosAvanceRevisados,mismoContenidoInversion,guardarBorradorAcceso,guardarBorradorCondiciones,guardarIntentoInversion,
+  guardarConversionAbierta,leerConversionAbierta,limpiarConversionAbierta,
   leerBorradorAcceso,leerBorradorCondiciones,leerIntentoInversion,limpiarIntentosInversion,nuevoIntentoInversion,
   solicitudCorresponde,SolicitudInversionSchema,type DatosBorradorCondiciones,type SolicitudInversion,type DatosInversion} from './inversion-solicitud'
 import * as v from 'valibot'
 const base: DatosInversion={inversionista_id:'11111111-1111-4111-8111-111111111111',empresa:'avance'}
 describe('Contenido de una solicitud F5',()=>{
   it('releer JSONB con otro orden no exige corregir; cambiar importe u orden de cuotas sí',()=>{
     const a={...base,contrato:{capital:1500,moneda:'PEN'},cuenta:{banco:'BCP',tipo:'nueva'},cronograma:[1,2]}
     const b={...base,cuenta:{tipo:'nueva',banco:'BCP'},contrato:{moneda:'PEN',capital:1500},cronograma:[1,2]}
     expect(mismoContenidoInversion(a,b)).toBe(true)
     expect(mismoContenidoInversion(a,{...b,contrato:{...b.contrato,capital:1600}})).toBe(false)
     expect(mismoContenidoInversion(a,{...b,cronograma:[2,1]})).toBe(false)
   })
@@ -157,13 +158,45 @@ describe('Contenido de una solicitud F5',()=>{
   it('un flujo no adopta la solicitud del otro: la de venta cruzada solo corresponde a la venta cruzada',()=>{
     const s=v.parse(SolicitudInversionSchema,{solicitud_id:base.inversionista_id,estado:'preparada',inversion_id:null,
       inversionista_id:base.inversionista_id,inversionista_origen_id:base.inversionista_id,identidad_fusionada:false,
       responsable_esperado_id:null,responsable_actual_id:null,requiere_revision_responsable:false,revision_datos:0,
       revision_responsable:0,hash_datos:'h',necesita_portal:false,comprobante_bucket:null,comprobante_ruta:null,resultado:null,
       datos:base,puerta:'cliente_existente',analista_cierre_id:'22222222-2222-4222-8222-222222222222'})
     expect(solicitudCorresponde(s,base.inversionista_id,{ventaCruzada:true})).toBe(true)
     expect(solicitudCorresponde(s,base.inversionista_id)).toBe(false)
     const {puerta:_puerta,...propia}=s
     expect(solicitudCorresponde(propia as SolicitudInversion,base.inversionista_id)).toBe(true)
     expect(solicitudCorresponde(propia as SolicitudInversion,base.inversionista_id,{ventaCruzada:true})).toBe(false)
   })
+  it('la conversión abierta se retoma solo para su actor y su lead; revocar un lead no la toca y salir las borra todas',()=>{
+    sessionStorage.clear()
+    const actor='22222222-2222-4222-8222-222222222222',otro='55555555-5555-4555-8555-555555555555'
+    const lead='33333333-3333-4333-8333-333333333333',otroLead='66666666-6666-4666-8666-666666666666'
+    const persona={inversionista_id:base.inversionista_id,solicitud_id:null}
+    guardarConversionAbierta(actor,lead,persona)
+    guardarConversionAbierta(actor,otroLead,{...persona,solicitud_id:otro})
+    expect(leerConversionAbierta(actor,lead)).toEqual(persona)
+    expect(leerConversionAbierta(actor,otroLead)).toEqual({...persona,solicitud_id:otro})
+    expect(leerConversionAbierta(otro,lead)).toBeNull()
+    // Solo identificadores: nada de lo que el analista escribe viaja en la marca.
+    expect(Object.keys(JSON.parse(sessionStorage.getItem(`crm:f5:conversion-abierta:${actor}:${lead}`)!)).sort())
+      .toEqual(['actor','inversionista_id','lead','solicitud_id','version'])
+    limpiarIntentosInversion(actor,base.inversionista_id,lead)
+    expect(leerConversionAbierta(actor,lead)).toEqual(persona)
+    limpiarConversionAbierta(actor,lead)
+    expect(leerConversionAbierta(actor,lead)).toBeNull()
+    expect(leerConversionAbierta(actor,otroLead)).not.toBeNull()
+    limpiarIntentosInversion()
+    expect(leerConversionAbierta(actor,otroLead)).toBeNull()
+  })
+  it('una marca dañada, de otra versión o copiada a otra clave equivale a no tenerla',()=>{
+    sessionStorage.clear()
+    const actor='22222222-2222-4222-8222-222222222222',lead='33333333-3333-4333-8333-333333333333'
+    const clave=`crm:f5:conversion-abierta:${actor}:${lead}`
+    const marca={version:1,actor,lead,inversionista_id:base.inversionista_id,solicitud_id:null}
+    sessionStorage.setItem(clave,'{no es json');expect(leerConversionAbierta(actor,lead)).toBeNull()
+    sessionStorage.setItem(clave,JSON.stringify({...marca,version:2}));expect(leerConversionAbierta(actor,lead)).toBeNull()
+    sessionStorage.setItem(clave,JSON.stringify({...marca,inversionista_id:'no-es-uuid'}));expect(leerConversionAbierta(actor,lead)).toBeNull()
+    sessionStorage.setItem(clave,JSON.stringify({...marca,lead:base.inversionista_id}));expect(leerConversionAbierta(actor,lead)).toBeNull()
+    sessionStorage.setItem(clave,JSON.stringify(marca));expect(leerConversionAbierta(actor,lead)).not.toBeNull()
+  })
 })
diff --git a/CRM-Avance-Corp/app/src/lib/inversion-solicitud.ts b/CRM-Avance-Corp/app/src/lib/inversion-solicitud.ts
index 391562fc..6ecef93f 100644
--- a/CRM-Avance-Corp/app/src/lib/inversion-solicitud.ts
+++ b/CRM-Avance-Corp/app/src/lib/inversion-solicitud.ts
@@ -166,24 +166,57 @@ export function leerBorradorCondiciones(actor: string, persona: string, origen:
       Boolean(r.output.venta_cruzada) === esVentaCruzada(origen) &&
       r.output.solicitud === solicitud && r.output.revision === revision) return r.output.datos
   } catch { /* No usar datos corruptos para reconstruir un contrato. */ }
   return null
 }
 export function limpiarBorradorCondiciones(actor?: string, persona?: string, origen?: OrigenIntento): void {
   const prefijo = !actor ? PREFIJO_CONDICIONES : !persona ? `${PREFIJO_CONDICIONES}${actor}:`
     : `${PREFIJO_CONDICIONES}${actor}:${persona}:${tramoOrigen(origen)}:`
   try {for (const k of Object.keys(sessionStorage)) if (k.startsWith(prefijo)) sessionStorage.removeItem(k)}
   catch { /* El bloqueo de almacenamiento no puede impedir cerrar sesión. */ }
 }
 
+const PREFIJO_CONVERSION = 'crm:f5:conversion-abierta:'
+const ConversionAbiertaSchema = v.object({
+  version: v.literal(1), actor: Uuid, lead: Uuid, inversionista_id: Uuid, solicitud_id: v.nullable(Uuid),
+})
+export type ConversionAbierta = Pick<v.InferOutput<typeof ConversionAbiertaSchema>, 'inversionista_id' | 'solicitud_id'>
+const claveConversion = (actor: string, lead: string) => `${PREFIJO_CONVERSION}${actor}:${lead}`
+
+/** El wizard de conversión de este lead está abierto en ESTA pestaña: al recargar
+ * se retoma sin volver a pedir la identidad. Solo identificadores; el servidor
+ * vuelve a comprobar la persona y el ámbito al abrirlo. */
+export function guardarConversionAbierta(actor: string, lead: string, persona: ConversionAbierta): void {
+  try {
+    sessionStorage.setItem(claveConversion(actor, lead), JSON.stringify(v.parse(ConversionAbiertaSchema, {
+      version: 1, actor, lead, inversionista_id: persona.inversionista_id, solicitud_id: persona.solicitud_id,
+    })))
+  } catch { /* Sin almacenamiento el wizard sigue abierto; solo no se retoma tras recargar. */ }
+}
+export function leerConversionAbierta(actor: string, lead: string): ConversionAbierta | null {
+  try {
+    const raw = sessionStorage.getItem(claveConversion(actor, lead))
+    const r = raw ? v.safeParse(ConversionAbiertaSchema, JSON.parse(raw)) : null
+    if (r?.success && r.output.actor === actor && r.output.lead === lead) {
+      return {inversionista_id: r.output.inversionista_id, solicitud_id: r.output.solicitud_id}
+    }
+  } catch { /* Una marca dañada equivale a no tenerla: se vuelve a pedir la identidad. */ }
+  return null
+}
+export function limpiarConversionAbierta(actor?: string, lead?: string): void {
+  const prefijo = !actor ? PREFIJO_CONVERSION : !lead ? `${PREFIJO_CONVERSION}${actor}:` : claveConversion(actor, lead)
+  try {for (const k of Object.keys(sessionStorage)) if (k.startsWith(prefijo)) sessionStorage.removeItem(k)}
+  catch { /* El bloqueo de almacenamiento no puede impedir cerrar sesión. */ }
+}
+
 /** Solo en esta sesión del navegador: sobrevive a recarga/cierre de diálogo.
  * El contenido nunca viaja a logs, y se elimina al salir o perder acceso. */
 export function guardarIntentoInversion(intento: IntentoInversion): void {
   const validado = v.parse(IntentoSchema, intento)
   sessionStorage.setItem(clave(validado.actor, validado.persona,
     validado.venta_cruzada ? {ventaCruzada: true} : validado.datos.lead_id), JSON.stringify(validado))
 }
 export function leerIntentoInversion(actor: string, persona: string, origen?: OrigenIntento): IntentoInversion | null {
   const raw = sessionStorage.getItem(clave(actor, persona, origen))
   if (!raw) return null
   const lead = leadDe(origen)
   try {
@@ -191,24 +224,27 @@ export function leerIntentoInversion(actor: string, persona: string, origen?: Or
     if (r.success && r.output.actor === actor && r.output.persona === persona && r.output.datos.lead_id === lead
       && Boolean(r.output.venta_cruzada) === esVentaCruzada(origen)) return r.output
   } catch { /* nunca mostrar el contenido corrupto */ }
   throw new Error('No se pudo leer la solicitud pendiente. Conserva esta sesión y solicita revisión.')
 }
 export function limpiarIntentosInversion(actor?: string, persona?: string, origen?: OrigenIntento): void {
   const lead = leadDe(origen)
   const prefijo = actor ? `${PREFIJO}${actor}:${esVentaCruzada(origen) ? `ce-${persona ?? ''}` : lead ? `lead-${lead}` : persona ?? ''}` : PREFIJO
   try {for (const k of Object.keys(sessionStorage)) if (k.startsWith(prefijo)) sessionStorage.removeItem(k)}
   catch { /* El bloqueo de almacenamiento no puede impedir cerrar sesión. */ }
   limpiarBorradorAcceso(actor, persona, origen)
   limpiarBorradorCondiciones(actor, persona, origen)
+  // Al salir o perder el acceso no queda ningún wizard por retomar. El de UN lead
+  // lo cierra quien lo abrió: aquí «Iniciar otra inversión» sigue con él abierto.
+  if (!actor) limpiarConversionAbierta()
 }
 export function nuevoIntentoInversion(actor: string, persona: string, id: string, datos: DatosInversion, origen?: string | null,
   ventaCruzada?: {busqueda_id: string; motivo: string}): IntentoInversion {
   const bytes = crypto.getRandomValues(new Uint8Array(24))
   return {version: 1, actor, persona, clave: id, datos, ...(origen ? {reinversion_origen_id: origen} : {}),
     ...(ventaCruzada ? {venta_cruzada: ventaCruzada} : {}),
     token: Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('')}
 }
 export const jsonInversion = (datos: unknown): Json => datos as Json
 
 /** JSONB no conserva el orden de claves; el orden de arrays sí es contractual. */
 export function mismoContenidoInversion(a: DatosInversion, b: DatosInversion): boolean {
```
