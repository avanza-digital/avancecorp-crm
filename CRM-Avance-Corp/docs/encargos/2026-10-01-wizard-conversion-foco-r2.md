ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo de revisión r2 (LEVEL 2: solo pantalla del CRM; segunda y última ronda, con evidencia nueva)

Eres el revisor secundario. Trabajas sin base de datos, sin red y sin poder abrir archivos: todo lo que debes juzgar está transcrito abajo. Tu trabajo es REFUTAR. NO FINDING WITHOUT EVIDENCE: cada hallazgo cita archivo, líneas o fragmento del diff; lo no demostrado se marca como hipótesis. Formato:

VERDICT: PASS | CHANGES_REQUESTED | BLOCK
SUMMARY
FINDINGS ([P0|P1|P2|P3] Título · File · Lines · Problem · Evidence · Impact · Recommendation)
TEST GAPS · REGRESSION RISKS · SECURITY RISKS (solo si aplican)
RECOMMENDED NEXT ACTIONS
CONFIDENCE: HIGH | MEDIUM | LOW

## Por qué hay segunda ronda

Tras tu r1 (CHANGES_REQUESTED, un P2) y una revisión de accesibilidad independiente, el cambio creció en tres puntos que no viste: (a) el envoltorio del documento cambió de diseño, (b) se tocó la primitiva compartida `ui/dialog.tsx`, (c) la ficha desarma la reapertura automática al primer gesto. Te pido juzgar SOLO lo nuevo y si alguna corrección abrió otro hueco.

## El fallo original (resumen)

Producción (`c6e65d9e`): ficha del lead → «Convertir a cliente» → modal de identidad → wizard «Nueva inversión». Al volver a la ventana, el wizard desaparecía y reaparecía el modal de identidad. Causa reproducida: `preparar_persona_lead_inversion_fn` escribe en el lead (`actualizado_en` cambia); al recuperar el foco el store resincroniza; `useDocumentoLead` lleva `lead.actualizado_en` en la clave con `gcTime: 0` → `isPending` → `InversionDesdeLead` pintaba el diálogo de carga y DESMONTABA `FormularioInversionDesdeLead` (con `InversionNueva` dentro, cuya persona vivía en estado local). Segundo camino: la relectura por foco devolvía el documento ya vinculado y cambiaba la `key`.

## Qué hice con tu r1

- [P2] Cerrar durante la carga/error no borraba la marca → ACEPTADO: el envoltorio limpia la marca en su cierre. Pruebas: «cerrar mientras todavía carga…» y «cerrar el aviso de que el documento no cargó…».
- Hipótesis «reutilización entre actores o leads» → la frontera existía (`lead-drawer.tsx`: `{l && <Ficha key={l.id} l={l} />}`; el cambio de cuenta pasa por `verificando` y remonta la app), pero la hice explícita: `DialogConvertir` monta `<InversionDesdeLead key={`${yo?.id}:${l.id}`} …>`. Prueba: «pasar a otro lead sin desmontar no arrastra la persona ni el documento del anterior».
- Hipótesis «retoma tras perder `puede_contratar`» → ACEPTADO en pantalla: la reapertura automática exige `puedeConvertir` (el mismo permiso que el botón) y no ocurre en un lead descartado. En el servidor ya estaba: el núcleo de inversión exige `private.puede_gestionar_contratos_crm()` (`20260924032042_crm_inversion_autorizacion_core.sql:123,184`; `20260924045245_crm_puertas_cliente_existente.sql:396`).
- Hueco «cancelar → iniciar otra → recargar» → ACEPTADO simplificando: la marca ya NO guarda `solicitud_id`, solo la persona; la solicitud la recupera el intento de `sessionStorage` (`InversionNueva`: `recuperarId = guardado.intento?.clave ?? origenLead?.solicitudId`). Prueba: «recargar tras cancelar muestra la cancelación; tras "Iniciar otra inversión", vuelve a elegir empresa sin resucitarla».
- Huecos de prueba (caché compartida, segundo observador, condiciones entregadas al abrir, descartado, otro analista) → cubiertos (ver lista de pruebas).

## Lo NUEVO que debes refutar

### (a) Envoltorio del documento: «copia de la ficha primero, se fija con el servidor o con la persona»

En r1 el formulario esperaba SIEMPRE una respuesta posterior al montaje (diálogo de carga en cada apertura). La revisión de accesibilidad mostró que eso creaba un relevo carga → formulario en toda apertura: el segundo diálogo nacía sin origen de foco y al cancelar el foco caía en `body` (antes volvía al botón «Convertir a cliente»). Diseño final:

```tsx
export function InversionDesdeLead(props: Propiedades) {
  const {yo} = useAuth()
  const [fijado, setFijado] = useState<DocumentoLead | null>(null)
  const documento = useDocumentoLead(props.l, fijado === null)   // activa=false ⇒ enabled:false
  const reciente = documento.isFetchedAfterMount && !documento.isError ? documento.data ?? null : null
  if (fijado === null && reciente) setFijado(reciente)
  // Hasta fijarlo vale la copia que la ficha ya tenía y la `key` deja que el servidor la corrija esa vez.
  const inicial = fijado ?? (documento.isPending || documento.isError ? null : documento.data ?? null)
  const cerrar = () => {if (yo) limpiarConversionAbierta(yo.id, props.l.id); props.onClose()}
  if (!inicial) return <Dialog open onClose={cerrar} …>…carga (role=status sr-only) / error (role=alert)…</Dialog>
  return <FormularioInversionDesdeLead key={`${inicial.tipo}:${inicial.numero}`} {...props} documentoInicial={inicial}
    alTenerPersona={() => setFijado(actual => actual ?? inicial)} />
}
// En FormularioInversionDesdeLead:
const hayPersona = persona !== null            // preparada ahora, retomada de la marca, o ya confirmada
const fijarDocumento = useRef(alTenerPersona); fijarDocumento.current = alTenerPersona
useEffect(() => {if (hayPersona) fijarDocumento.current()}, [hayPersona])
```

Invariantes que afirmo: (1) una vez `fijado`, `inicial` es constante y la consulta queda deshabilitada: ni resincronización, ni relectura por foco, ni cambio de clave remontan nada; (2) antes de fijar solo cabe UNA corrección (la respuesta del montaje) y solo si aún no hay persona; (3) si la identidad se prepara antes de que responda el servidor, el efecto fija la copia en uso y la respuesta tardía se ignora; (4) con error antes de fijar se muestra el diálogo de error (no se convierte con una copia sin confirmar).

Dudas concretas: ¿hay una ventana entre `setPersona(r)` y el efecto en la que una respuesta que llega justo entonces cambie la `key`? (El efecto corre tras el commit en que `persona` aparece; la respuesta del documento llega por un `setState` del observador de React Query.) Si esa carrera existe: el formulario se remonta, lee la marca (ya guardada ANTES de `setPersona`) y vuelve directo al wizard; `InversionNueva` se remonta recién nacido. ¿Algo peor que eso?

### (b) Primitiva compartida `ui/dialog.tsx` (afecta a TODOS los modales)

```tsx
onOpenAutoFocus={(evento) => {
  const activo = document.activeElement
  const origen = activo instanceof HTMLElement && activo !== document.body ? activo : null
  origenFoco.current = origen
  // Sin origen (un diálogo releva a otro, o se abre solo) el ámbito es la capa abierta de debajo.
  ambitoFoco.current = origen?.closest<HTMLElement>('[role="dialog"]')
    ?? Array.from(document.querySelectorAll<HTMLElement>('[data-slot="dialog"], [data-slot="sheet"]'))
      .filter((capa) => capa !== contenido.current).pop()
    ?? null
  if (focoInicial?.current) { evento.preventDefault(); focoInicial.current.focus({ preventScroll: true }) }
}}
onCloseAutoFocus={(evento) => {           // SIN CAMBIOS
  if (focoAlCerrar) { evento.preventDefault(); requestAnimationFrame(() => focoAlCerrar.current?.focus({ preventScroll: true })); return }
  const origen = origenFoco.current, ambito = ambitoFoco.current
  origenFoco.current = null; ambitoFoco.current = null
  if (!origen?.isConnected && !ambito?.isConnected) return
  evento.preventDefault()
  requestAnimationFrame(() => {
    const destino = origen?.isConnected && !origen.matches(':disabled, [aria-disabled="true"]') ? origen : ambito?.isConnected ? ambito : null
    destino?.focus({ preventScroll: true })
    if (document.activeElement !== destino && ambito?.isConnected) ambito.focus({ preventScroll: true })
  })
}}
```

Único cambio de conducta: cuando el diálogo se abre con el foco en `body` y hay OTRA capa abierta (`data-slot="dialog"` o `"sheet"`), al cerrarse enfoca esa capa en vez de no hacer nada. Mutante comprobado: sin el respaldo, la prueba «un diálogo que releva a otro dentro de la ficha devuelve el foco a la ficha al cerrarse» FALLA (el foco se quedaba en `body`). ¿Ves un caso donde el respaldo robe el foco o enfoque una capa equivocada? (diálogos apilados, un diálogo que se abre mientras otro se está cerrando, `Sheet` no modal, capa de debajo oculta/inerte).

### (c) Ficha: reapertura automática desarmable

```tsx
const conversionAbierta = () => Boolean(yo && !yo.demo && leerConversionAbierta(yo.id, l.id))
const [retomarConversion, setRetomarConversion] = useState(conversionAbierta)
if (retomarConversion && puedeConvertir && (condicionesLead !== null || l.etapa === 'convertido')) {
  setRetomarConversion(false)
  if (conversionAbierta()) setDialogo(actual => actual ?? 'convertir')
}
// Un modal que aparece solo le quita el foco a quien ya está trabajando en la ficha.
useEffect(() => {
  if (!retomarConversion) return
  const desarmar = () => setRetomarConversion(false)
  window.addEventListener('keydown', desarmar, true)
  window.addEventListener('pointerdown', desarmar, true)
  return () => { window.removeEventListener('keydown', desarmar, true); window.removeEventListener('pointerdown', desarmar, true) }
}, [retomarConversion])
```

Si se desarma, «Convertir a cliente» sigue retomando el wizard sin pedir identidad (la marca sigue ahí y `FormularioInversionDesdeLead` la lee al montarse). ¿Algún caso en que el desarme deje la marca huérfana de modo dañino, o en que el gesto que desarma sea el propio clic de «Convertir a cliente» y rompa algo?

## Verificación ejecutada sobre el código FINAL (worktree limpio desde `c6e65d9e`)

- Vitest de las suites del flujo: 86/86 (`dialog.test.tsx`, `inversion-desde-lead-foco.test.tsx`, `lead-drawer-retomar-conversion.test.tsx`, `lead-drawer-convertir.test.tsx`) + `inversion-solicitud.test.ts`.
- 13 mutantes, los 13 cazados y el original restaurado byte a byte: cierre sin limpiar marca · fijar cualquier copia · no fijar con el servidor · no fijar al tener persona · sin `key` · no guardar la marca · confirmar sin limpiar · retomar sin permiso · sin esperar condiciones · sin re-mirar la marca · sin desarme · sin frontera cuenta/lead · diálogo sin ámbito de respaldo.
- E2E Docker (Chromium real, backend sintético), caso nuevo «volver a la ventana y recargar la página en las condiciones del contrato…»: paso 2 con datos → resincronización con `actualizado_en` nuevo → sigue en paso 2 con los datos; token VENCIDO en `localStorage` + foco → renovación real (`/auth/v1/token?grant_type=refresh_token` 200) → sigue en paso 2; `page.reload()` → la ficha reabre el wizard en el paso 2 con capital, número y cuenta; una sola llamada a identidad y una sola a preparar; al cerrar el wizard retomado el foco queda en la ficha. Sin el arreglo ese caso falla al volver a la ventana (mutante comprobado).
- `npm run check` y la suite e2e COMPLETA: corriendo al escribir este encargo (la r1 pasó check 330 archivos / 5.177 pruebas y e2e 14/14 con el diseño anterior).

## Diff completo FINAL (worktree vs `c6e65d9e`)

```diff
diff --git a/CRM-Avance-Corp/app/e2e/acceso-avance-ux.spec.ts b/CRM-Avance-Corp/app/e2e/acceso-avance-ux.spec.ts
index 13b97b7e..ed70b728 100644
--- a/CRM-Avance-Corp/app/e2e/acceso-avance-ux.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/acceso-avance-ux.spec.ts
@@ -179,8 +179,85 @@ test('corregir el correo permite continuar y un conflicto conocido conserva el f
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
+  await expect(page.getByRole('dialog', {name: /Registrar la inversión del lead|Documento del lead/})).toHaveCount(0)
+
+  // Más de una hora con la pestaña oculta: el token ya venció y Auth lo renueva al volver.
+  // La renovación de la misma cuenta no puede remontar nada.
+  const renovacion = page.waitForResponse(r => r.url().includes('/auth/v1/token') && r.url().includes('grant_type=refresh_token'))
+  await page.evaluate(() => {
+    const llave = Object.keys(localStorage).find(k => k.startsWith('sb-') && k.endsWith('-auth-token'))!
+    const sesion = JSON.parse(localStorage.getItem(llave)!)
+    localStorage.setItem(llave, JSON.stringify({...sesion, expires_at: Math.floor(Date.now() / 1000) - 60}))
+    document.dispatchEvent(new Event('visibilitychange', {bubbles: true}))
+    window.dispatchEvent(new Event('focus'))
+  })
+  expect((await renovacion).ok()).toBe(true)
+  await expect(contrato.getByRole('navigation', pasos)).toContainText('Paso 2 de 3')
+  await expect(contrato.getByLabel('Capital', {exact: true})).toHaveValue('23000')
+  await expect(contrato.getByLabel('N° de contrato', {exact: true})).toHaveValue('000719')
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
+  // El wizard se reabrió solo, sin botón que lo abriera: al cerrarlo el foco vuelve a la ficha.
+  await page.getByRole('dialog', {name: 'Revisar inversión'}).getByRole('button', {name: 'Cerrar y continuar después'}).click()
+  await expect(page.getByRole('dialog', {name: 'Revisar inversión'})).toHaveCount(0)
+  await expect(ficha).toBeFocused()
+})
diff --git a/CRM-Avance-Corp/app/src/components/app/inversion-desde-lead-foco.test.tsx b/CRM-Avance-Corp/app/src/components/app/inversion-desde-lead-foco.test.tsx
new file mode 100644
index 00000000..68c5e68c
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/app/inversion-desde-lead-foco.test.tsx
@@ -0,0 +1,256 @@
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
+import {guardarConversionAbierta,guardarIntentoInversion,leerConversionAbierta,leerIntentoInversion,nuevoIntentoInversion} from '@/lib/inversion-solicitud'
+import {useDocumentoLead,type DocumentoLead} from '@/data/documento-lead'
+import {ACTOR_F5,PERSONA_F5,FUENTE_F5} from '@/test/fixtures/f5'
+import {InversionDesdeLead} from './inversion-desde-lead'
+
+const api=vi.hoisted(()=>({persona:vi.fn(),contexto:vi.fn(),documento:vi.fn(),montajes:{n:0,desmontajes:0}}))
+// `documento` puede devolver el dato, una promesa que nunca responde (carga) o una rechazada (caída).
+vi.mock('@/lib/supabase',()=>({sb:{schema:()=>({rpc:(_nombre:string,args:{p_lead_id:string})=>{
+  const respuesta=Promise.resolve().then(()=>api.documento(args.p_lead_id)).then(data=>({data,error:null}))
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
+const sinVincular:DocumentoLead={lead_id:LEAD,inversionista_id:null,identificador_id:null,tipo:'DNI',numero:null,puede_corregir:false}
+const vinculado:DocumentoLead={...sinVincular,inversionista_id:PERSONA_F5,identificador_id:FUENTE_F5,numero:'93334444'}
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
+/** La sección Datos de la ficha lee el MISMO documento, con la misma clave. */
+function OtraLectura({l}:{l:Lead}){
+  const documento=useDocumentoLead(l)
+  return <span data-testid="otra-lectura">{documento.data?.numero??'sin documento'}</span>
+}
+function montar({actor=ACTOR_F5,sembrar,conFicha=false}:{actor?:string;sembrar?:(qc:QueryClient)=>void;conFicha?:boolean}={}){
+  const qc=new QueryClient({defaultOptions:{queries:{retry:false}}}),onClose=vi.fn(),recargar=vi.fn().mockResolvedValue(true)
+  sembrar?.(qc)
+  const auth={yo:{id:actor,rol:'vendedor',nombre_completo:'ANALISTA F5',demo:false,puede_contratar:true}} as AuthContextValue
+  const store={recargar} as unknown as StoreDataApi
+  const arbol=(l:Lead)=><QueryClientProvider client={qc}><AuthContext.Provider value={auth}><StoreDataContext.Provider value={store}>
+    {conFicha&&<OtraLectura l={l}/>}<InversionDesdeLead l={l} onClose={onClose}/>
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
+  it('la ficha sigue releyendo su documento por su cuenta sin tocar el wizard',async()=>{
+    const {user,conLead}=montar({conFicha:true})
+    await llegarAlWizard(user)
+    expect(screen.getByTestId('otra-lectura')).toHaveTextContent('sin documento')
+    conLead({...lead,actualizado_en:'2026-10-01T15:00:42Z'})
+    await waitFor(()=>expect(screen.getByTestId('otra-lectura')).toHaveTextContent('93334444'))
+    await sigueElWizard()
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
+describe('El documento que precarga la identidad',()=>{
+  /** La ficha ya leyó este documento: su copia está en caché cuando se abre la conversión. */
+  const enCache=(documento:DocumentoLead)=>(qc:QueryClient)=>
+    qc.setQueryData(['crm','leads','documento',ACTOR_F5,LEAD,lead.actualizado_en],documento)
+  /** El servidor tarda: la prueba decide cuándo responde. */
+  function servidorLento(){
+    let responder!:(documento:DocumentoLead)=>void
+    api.documento.mockReturnValue(new Promise(r=>{responder=r}))
+    // React Query avisa a sus observadores en la siguiente vuelta: se espera dentro del act.
+    return (documento:DocumentoLead)=>act(async()=>{responder(documento);await new Promise(r=>setTimeout(r,20))})
+  }
+
+  it('abre con la copia de la ficha sin esperar y, si el servidor trae otro documento, se queda con el del servidor',async()=>{
+    const responder=servidorLento()
+    montar({sembrar:enCache({...sinVincular,numero:'11111111'})})
+    expect(screen.getByLabelText('Documento')).toHaveValue('11111111')
+    expect(screen.queryByText('Documento del lead')).not.toBeInTheDocument()
+    await responder({...sinVincular,tipo:'CE',numero:'001234567'})
+    expect(screen.getByLabelText('Documento')).toHaveValue('001234567')
+    expect(screen.getByLabelText('Tipo de documento')).toHaveValue('CE')
+  })
+
+  it('si el servidor confirma la misma copia, lo ya escrito no se pierde',async()=>{
+    const responder=servidorLento()
+    const {user}=montar({sembrar:enCache(sinVincular)})
+    await user.type(screen.getByLabelText('Documento'),'93334444')
+    await responder(sinVincular)
+    expect(screen.getByLabelText('Documento')).toHaveValue('93334444')
+  })
+
+  it('si la identidad se prepara antes de que el servidor responda, la respuesta tardía no remonta el wizard',async()=>{
+    const responder=servidorLento()
+    const {user}=montar({sembrar:enCache(sinVincular)})
+    await llegarAlWizard(user)
+    // Llega ya vinculado (otro número): antes de fijarse, eso habría cambiado la `key`.
+    await responder(vinculado)
+    await sigueElWizard()
+  })
+
+  it('cancelar la identidad devuelve el foco al botón que la abrió',async()=>{
+    function Pantalla(){
+      const [abierto,setAbierto]=useState(false)
+      return <><button onClick={()=>setAbierto(true)}>Convertir a cliente</button>
+        {abierto&&<InversionDesdeLead l={lead} onClose={()=>setAbierto(false)}/>}</>
+    }
+    const qc=new QueryClient({defaultOptions:{queries:{retry:false}}});enCache(sinVincular)(qc)
+    const auth={yo:{id:ACTOR_F5,rol:'vendedor',nombre_completo:'ANALISTA F5',demo:false,puede_contratar:true}} as AuthContextValue
+    render(<QueryClientProvider client={qc}><AuthContext.Provider value={auth}>
+      <StoreDataContext.Provider value={{recargar:vi.fn()} as unknown as StoreDataApi}><Pantalla/></StoreDataContext.Provider>
+    </AuthContext.Provider></QueryClientProvider>)
+    const user=userEvent.setup(),boton=screen.getByRole('button',{name:'Convertir a cliente'})
+    await user.click(boton)
+    // Con la copia de la ficha el formulario es el PRIMER diálogo: conserva su origen.
+    await user.click(await screen.findByRole('button',{name:'Cancelar'}))
+    await waitFor(()=>expect(boton).toHaveFocus())
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
+    // La solicitud la trae el intento guardado, que es quien sigue sus cambios.
+    expect(screen.getByTestId('solicitud')).toHaveTextContent('sin solicitud')
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
+  it('cerrar mientras todavía carga el documento también deja de retomarlo',async()=>{
+    guardarConversionAbierta(ACTOR_F5,LEAD,PERSONA_F5)
+    api.documento.mockReturnValue(new Promise(()=>undefined))
+    const {user,onClose}=montar()
+    await user.click(screen.getByRole('button',{name:'Volver a la ficha'}))
+    expect(onClose).toHaveBeenCalledOnce()
+    expect(leerConversionAbierta(ACTOR_F5,LEAD)).toBeNull()
+  })
+
+  it('cerrar el aviso de que el documento no cargó también deja de retomarlo',async()=>{
+    guardarConversionAbierta(ACTOR_F5,LEAD,PERSONA_F5)
+    api.documento.mockRejectedValue(new TypeError('Conexión interrumpida'))
+    const {user,onClose}=montar()
+    expect(await screen.findByText(/No se pudo consultar el documento vinculado/)).toBeInTheDocument()
+    expect(screen.queryByTestId('persona')).not.toBeInTheDocument()
+    await user.click(screen.getByRole('button',{name:'Volver a la ficha'}))
+    expect(onClose).toHaveBeenCalledOnce()
+    expect(leerConversionAbierta(ACTOR_F5,LEAD)).toBeNull()
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
+    montar({actor:OTRO_ACTOR})
+    expect(await screen.findByText('Registrar la inversión del lead')).toBeInTheDocument()
+    expect(screen.queryByTestId('persona')).not.toBeInTheDocument()
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/components/app/inversion-desde-lead.tsx b/CRM-Avance-Corp/app/src/components/app/inversion-desde-lead.tsx
index f37145eb..c1f8c2b1 100644
--- a/CRM-Avance-Corp/app/src/components/app/inversion-desde-lead.tsx
+++ b/CRM-Avance-Corp/app/src/components/app/inversion-desde-lead.tsx
@@ -4,64 +4,94 @@ import { Button } from '@/components/ui/button'
 import { Dialog, DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
 import { Input } from '@/components/ui/input'
 import { Label } from '@/components/ui/label'
 import { Select } from '@/components/ui/select'
 import { useAuth } from '@/lib/auth-context'
 import { useCRMData } from '@/lib/store-context'
 import type { Lead } from '@/lib/tipos'
 import { TIPOS_DOCUMENTO, TIPOS_DOCUMENTO_K, validarDocumento, type TipoDocumento } from '@/lib/documento'
-import { limpiarIntentosInversion } from '@/lib/inversion-solicitud'
+import { guardarConversionAbierta, leerConversionAbierta, limpiarConversionAbierta, limpiarIntentosInversion } from '@/lib/inversion-solicitud'
 import { mensajeDeError, type CondicionesTasaLead } from '@/data/crm-api'
 import { prepararPersonaLeadInversion, obtenerContextoConversionInversion } from '@/data/inversion-solicitud-api'
 import { PanelCargando, PanelError } from '@/components/common/estado-panel'
 import { InversionNueva } from './inversion-nueva'
 import { useDocumentoLead, type DocumentoLead } from '@/data/documento-lead'
 
 type Propiedades = { l: Lead; condicionesTasa?: CondicionesTasaLead | undefined; onClose: () => void }
 
 export function InversionDesdeLead(props: Propiedades) {
-  const documento = useDocumentoLead(props.l)
-  if (documento.isPending || documento.isError || !documento.data) return <Dialog open onClose={props.onClose} ariaLabel="Convertir a cliente">
+  // El documento solo PRECARGA la identidad y se FIJA: con la primera respuesta
+  // posterior a abrir o, antes, en cuanto hay persona. Preparar la identidad escribe
+  // en el lead: al volver a la ventana la cartera se resincroniza, la consulta
+  // cambia de clave (o de resultado) y, si de ella dependiera qué se pinta, el
+  // wizard se desmontaría con todo lo ya escrito.
+  const {yo} = useAuth()
+  const [fijado, setFijado] = useState<DocumentoLead | null>(null)
+  const documento = useDocumentoLead(props.l, fijado === null)
+  const reciente = documento.isFetchedAfterMount && !documento.isError ? documento.data ?? null : null
+  if (fijado === null && reciente) setFijado(reciente)
+  // Hasta fijarlo vale la copia que la ficha ya tenía (el formulario abre sin
+  // esperar) y la `key` deja que la respuesta del servidor la corrija esa vez.
+  const inicial = fijado ?? (documento.isPending || documento.isError ? null : documento.data ?? null)
+  // Cerrar a mano mientras carga también es cerrar: una retoma pendiente no se reabre sola.
+  const cerrar = () => {if (yo) limpiarConversionAbierta(yo.id, props.l.id); props.onClose()}
+  if (!inicial) return <Dialog open onClose={cerrar} ariaLabel="Convertir a cliente">
     <DialogHeader><DialogTitle>Documento del lead</DialogTitle></DialogHeader>
     <DialogBody>{documento.isError
-      ? <PanelError mensaje="No se pudo consultar el documento vinculado. Vuelve a intentarlo." onReintentar={() => void documento.refetch()} reintentando={documento.isFetching} />
-      : <PanelCargando />}</DialogBody>
-    <DialogFooter><Button variant="outline" onClick={props.onClose}>Volver a la ficha</Button></DialogFooter>
+      ? <div role="alert"><PanelError mensaje="No se pudo consultar el documento vinculado. Vuelve a intentarlo." onReintentar={() => void documento.refetch()} reintentando={documento.isFetching} /></div>
+      : <><p role="status" className="sr-only">Consultando el documento del lead…</p><PanelCargando /></>}</DialogBody>
+    <DialogFooter><Button variant="outline" onClick={cerrar}>Volver a la ficha</Button></DialogFooter>
   </Dialog>
-  return <FormularioInversionDesdeLead key={`${props.l.id}:${documento.data.tipo}:${documento.data.numero}`} {...props} documentoInicial={documento.data} />
+  return <FormularioInversionDesdeLead key={`${inicial.tipo}:${inicial.numero}`} {...props} documentoInicial={inicial}
+    alTenerPersona={() => setFijado(actual => actual ?? inicial)} />
 }
 
 /** Adaptación de identidad; los campos y el guardado de la inversión pertenecen
  * exclusivamente a InversionNueva, igual que al entrar desde Cartera. */
-function FormularioInversionDesdeLead({l, condicionesTasa, onClose, documentoInicial}: Propiedades & { documentoInicial: DocumentoLead }) {
+function FormularioInversionDesdeLead({l, condicionesTasa, onClose, documentoInicial, alTenerPersona}: Propiedades & {
+  documentoInicial: DocumentoLead; alTenerPersona: () => void
+}) {
   const {yo} = useAuth()
   const {recargar} = useCRMData()
   const [tipo, setTipo] = useState<TipoDocumento>(documentoInicial.tipo)
   const [documento, setDocumento] = useState(documentoInicial.numero ?? '')
   const reconocido = documentoInicial.inversionista_id !== null
   const [nombre, setNombre] = useState(l.nombre_completo)
-  const [preparada, setPersona] = useState<Awaited<ReturnType<typeof prepararPersonaLeadInversion>> | null>(null)
+  // Tras recargar la página con el wizard abierto se retoma sin volver a pedir la
+  // identidad: InversionNueva la comprueba en el servidor al montarse y recupera
+  // su solicitud del intento guardado, no de aquí.
+  const [preparada, setPersona] = useState<{inversionista_id: string; solicitud_id: string | null} | null>(() => {
+    const retomada = yo ? leerConversionAbierta(yo.id, l.id) : null
+    return retomada ? {inversionista_id: retomada, solicitud_id: null} : null
+  })
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
+  // Con persona (recién preparada, retomada o ya confirmada) el wizard está abierto:
+  // desde aquí ninguna respuesta tardía del documento puede remontarlo.
+  const hayPersona = persona !== null
+  const fijarDocumento = useRef(alTenerPersona)
+  fijarDocumento.current = alTenerPersona
+  useEffect(() => {if (hayPersona) fijarDocumento.current()}, [hayPersona])
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
@@ -71,17 +101,17 @@ function FormularioInversionDesdeLead({l, condicionesTasa, onClose, documentoIni
       e.preventDefault()
       if (enviando.current) return
       const doc = validarDocumento(tipo, documento)
       if (!doc.ok) {setError(doc.error); return}
       if (nombre.trim().length < 2) {setError('Completa el nombre de la persona.'); return}
       enviando.current = true; setOcupado(true); setError(null)
       void prepararPersonaLeadInversion(l.id, tipo, doc.valor, nombre.trim()).then(r => {
         if (r.lead_id !== l.id) throw new Error('No se pudo verificar el lead de esta inversión.')
-        if (montado.current) setPersona(r)
+        if (montado.current) {guardarConversionAbierta(yo.id, l.id, r.inversionista_id); setPersona(r)}
       }).catch(e => {if (montado.current) setError(mensajeDeError(e, 'No se pudo verificar la identidad.'))})
         .finally(() => {enviando.current = false; if (montado.current) setOcupado(false)})
     }}>
       <DialogBody className="space-y-4">
         <p className="text-sm text-muted-foreground">Confirma la identidad para abrir Nueva inversión. El lead se convertirá en cliente al confirmar su inversión.</p>
         <div className="space-y-1"><Label htmlFor="conversion-nombre">Nombre completo</Label>
           <Input id="conversion-nombre" required maxLength={180} value={nombre} disabled={ocupado} onChange={e => setNombre(e.target.value)} /></div>
         <div className="grid gap-3 sm:grid-cols-2">
diff --git a/CRM-Avance-Corp/app/src/components/app/lead-drawer-convertir.test.tsx b/CRM-Avance-Corp/app/src/components/app/lead-drawer-convertir.test.tsx
index 5fda940d..fd713067 100644
--- a/CRM-Avance-Corp/app/src/components/app/lead-drawer-convertir.test.tsx
+++ b/CRM-Avance-Corp/app/src/components/app/lead-drawer-convertir.test.tsx
@@ -4,17 +4,17 @@ import {act,fireEvent,render,screen,waitFor} from '@testing-library/react'
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
@@ -50,17 +50,17 @@ let correoFicha:string|null
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
@@ -82,25 +82,39 @@ function montar(datos:Partial<Lead>={}){
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
 
+  it('pasar a otro lead sin desmontar no arrastra la persona ni el documento del anterior',async()=>{
+    const {user,rerender}=montar()
+    await entrar(user,'Qorilazo')
+    // Mismo número de documento a propósito: lo único que separa a los dos leads es su id.
+    const qc=new QueryClient({defaultOptions:{queries:{retry:false}}})
+    const auth={yo:{id:ACTOR_F5,rol:'vendedor',nombre_completo:'ANALISTA F5',demo:false,puede_contratar:true}} as AuthContextValue
+    rerender(<QueryClientProvider client={qc}><AuthContext.Provider value={auth}>
+      <StoreDataContext.Provider value={{recargar:vi.fn(),equipo:[]} as unknown as StoreDataApi}>
+        <DialogConvertir l={{...lead,id:OTRO_LEAD,nombre_completo:'OTRA PERSONA'}} onClose={vi.fn()}/>
+      </StoreDataContext.Provider></AuthContext.Provider></QueryClientProvider>)
+    expect(await screen.findByLabelText('Nombre completo')).toHaveValue('OTRA PERSONA')
+    expect(screen.queryByLabelText('Número de operación del depósito')).not.toBeInTheDocument()
+  })
+
   it('un error al consultar identidad no permite convertir con el DNI antiguo',()=>{
     api.documento.mockReturnValue({data:undefined,isError:true,refetch:vi.fn()})
     montar()
     expect(screen.getByText(/No se pudo consultar el documento vinculado/)).toBeInTheDocument()
     expect(screen.queryByRole('button',{name:'Continuar a Nueva inversión'})).not.toBeInTheDocument()
     expect(api.persona).not.toHaveBeenCalled()
   })
 })
@@ -240,19 +254,20 @@ describe('Recuperar el primer acceso rechazado',()=>{
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
@@ -287,16 +302,33 @@ describe('Convertir a cliente usa Nueva inversión',()=>{
     expect(api.cancelar).toHaveBeenCalledWith(id,0);expect(api.confirmar).not.toHaveBeenCalled();expect(recargar).not.toHaveBeenCalled()
     await user.click(screen.getByRole('button',{name:'Iniciar otra inversión'}))
     expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5,LEAD)).toBeNull()
     await user.click(screen.getByRole('button',{name:'Qorilazo'}))
     expect(screen.getByLabelText('Número de operación del depósito')).toHaveValue('')
     await llenarCoop(user);expect(vigente!.solicitud_id).not.toBe(id)
     expect(vigente!.datos?.empresa).toBe('qorilazo')
   })
+  it('recargar tras cancelar muestra la cancelación; tras «Iniciar otra inversión», vuelve a elegir empresa sin resucitarla',async()=>{
+    const primera=montar();await entrar(primera.user,'Prodelco');await llenarCoop(primera.user)
+    await primera.user.click(screen.getByRole('button',{name:'Cancelar solicitud'}))
+    await primera.user.click(screen.getByRole('button',{name:'Confirmar cancelación'}))
+    await screen.findByRole('heading',{name:'Solicitud cancelada'})
+    // Desmontar sin cerrar es recargar la página: se retoma la misma pantalla, la que dice el servidor.
+    primera.unmount()
+    const segunda=montar()
+    await screen.findByRole('heading',{name:'Solicitud cancelada'})
+    await segunda.user.click(screen.getByRole('button',{name:'Iniciar otra inversión'}))
+    segunda.unmount()
+    montar()
+    expect(await screen.findByRole('button',{name:'Qorilazo'})).toBeInTheDocument()
+    expect(screen.queryByRole('heading',{name:'Solicitud cancelada'})).not.toBeInTheDocument()
+    expect(screen.queryByRole('button',{name:'Continuar a Nueva inversión'})).not.toBeInTheDocument()
+    expect(api.persona).toHaveBeenCalledOnce();expect(api.preparar).toHaveBeenCalledOnce()
+  })
   it('una lectura fallida conserva campos y comprobante hasta recuperar permisos',async()=>{
     const {user,qc}=montar();await entrar(user,'Prodelco')
     await user.type(screen.getByLabelText('Número de operación del depósito'),'NO-PERDER-001')
     const archivo=new File(['datos'],'comprobante.png',{type:'image/png'})
     await user.upload(screen.getByLabelText('Comprobante PDF, JPG o PNG (hasta 10 MB)'),archivo)
     api.contexto.mockRejectedValueOnce(new CrmApiError('Fallo temporal','55P03'))
     await act(async()=>{await qc.invalidateQueries({queryKey:['crm','inversionistas',ACTOR_F5]})})
     expect(await screen.findByRole('alert')).toHaveTextContent('Conservamos tus datos')
@@ -398,16 +430,38 @@ describe('Convertir a cliente usa Nueva inversión',()=>{
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
@@ -489,18 +543,20 @@ describe('Convertir a cliente usa Nueva inversión',()=>{
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
diff --git a/CRM-Avance-Corp/app/src/components/app/lead-drawer-retomar-conversion.test.tsx b/CRM-Avance-Corp/app/src/components/app/lead-drawer-retomar-conversion.test.tsx
new file mode 100644
index 00000000..f3632599
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/app/lead-drawer-retomar-conversion.test.tsx
@@ -0,0 +1,177 @@
+// Recargar la página con el wizard de conversión abierto: la ficha lo reabre sola,
+// pero solo cuando ya conoce las condiciones de tasa (el contrato las toma al
+// montarse), con el mismo permiso que el botón y solo si la marca de ESTA pestaña
+// sigue ahí.
+import { beforeEach, describe, expect, it, vi } from 'vitest'
+import { act, render, screen } from '@testing-library/react'
+import userEvent from '@testing-library/user-event'
+import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
+import { PanelActionsContext, PanelStateContext, StoreDataContext } from '@/lib/store-context'
+import type { PanelesActions, StoreDataApi } from '@/lib/store'
+import type { Lead } from '@/lib/tipos'
+import type { CondicionesTasaLead } from '@/data/crm-api'
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
+// Las condiciones de tasa llegan cuando la prueba lo decide y, como en la ficha real,
+// sin que nadie toque nada: es una consulta que termina, no un gesto de la persona.
+const tasa = vi.hoisted(() => ({ avisar: null as ((estado: EstadoCondicionesLead | null) => void) | null }))
+vi.mock('./condiciones-tasa-lead', () => ({
+  SolicitudTasaLeadPlegable: ({ onCambio }: { onCambio: (estado: EstadoCondicionesLead | null) => void }) => {
+    tasa.avisar = onCambio
+    return <p>Condiciones de tasa</p>
+  },
+}))
+vi.mock('./inversion-desde-lead', () => ({
+  InversionDesdeLead: ({ onClose, condicionesTasa }: { onClose: () => void; condicionesTasa?: CondicionesTasaLead }) =>
+    <div role="dialog" aria-label="Wizard de conversión">
+      <span data-testid="tasa-al-abrir">{condicionesTasa?.tasa_anual ?? 'sin condiciones'}</span>
+      <button onClick={onClose}>Cerrar el wizard</button>
+    </div>,
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
+const PERSONA = '44444444-4444-4444-8444-444444444444'
+const actions: PanelesActions = { abrirLead: vi.fn(), abrirNuevoLead: vi.fn(), cerrarPaneles: vi.fn() }
+
+function montar({ lead = LEAD, demo = false, puedeContratar = true }: { lead?: Lead; demo?: boolean; puedeContratar?: boolean } = {}) {
+  const sesion = { fase: 'listo', yo: { id: VENDEDOR, nombre_completo: 'ANALISTA A', rol: 'vendedor', demo, puede_contratar: puedeContratar },
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
+const lleganLasCondiciones = () => act(() => {
+  tasa.avisar?.({ condiciones: { tasa_anual: 18 }, bloqueo: null } as EstadoCondicionesLead)
+})
+beforeEach(() => { vi.clearAllMocks(); sessionStorage.clear(); tasa.avisar = null })
+
+describe('la ficha retoma el wizard de conversión tras recargar', () => {
+  it('lo reabre sola en cuanto conoce las condiciones de tasa, no antes, y se las entrega al abrir', async () => {
+    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
+    montar()
+    expect(wizard()).not.toBeInTheDocument()
+    await lleganLasCondiciones()
+    expect(wizard()).toBeInTheDocument()
+    expect(screen.getByTestId('tasa-al-abrir')).toHaveTextContent('18')
+  })
+
+  it('sin wizard abierto antes de recargar, la ficha no abre nada', async () => {
+    montar()
+    await lleganLasCondiciones()
+    expect(wizard()).not.toBeInTheDocument()
+  })
+
+  it('el wizard de otra cuenta o de otro lead no se abre en esta ficha', async () => {
+    guardarConversionAbierta(OTRO, LEAD.id, PERSONA)
+    guardarConversionAbierta(VENDEDOR, OTRO, PERSONA)
+    montar()
+    await lleganLasCondiciones()
+    expect(wizard()).not.toBeInTheDocument()
+  })
+
+  it('si la marca desaparece mientras llegan las condiciones, no reaparece', async () => {
+    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
+    montar()
+    limpiarConversionAbierta(VENDEDOR, LEAD.id)
+    await lleganLasCondiciones()
+    expect(wizard()).not.toBeInTheDocument()
+  })
+
+  it('cerrado a mano no se reabre cuando las condiciones vuelven a cambiar', async () => {
+    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
+    const user = montar()
+    await lleganLasCondiciones()
+    await user.click(screen.getByRole('button', { name: 'Cerrar el wizard' }))
+    expect(wizard()).not.toBeInTheDocument()
+    await lleganLasCondiciones()
+    expect(wizard()).not.toBeInTheDocument()
+  })
+
+  it.each([['una tecla', (user: ReturnType<typeof userEvent.setup>) => user.keyboard('a')],
+    ['un clic', (user: ReturnType<typeof userEvent.setup>) => user.click(screen.getByText('Condiciones de tasa'))],
+  ] as const)('si la persona ya está usando la ficha (%s), el wizard no aparece solo; el botón lo retoma', async (_gesto, gesto) => {
+    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
+    const user = montar()
+    await gesto(user)
+    await lleganLasCondiciones()
+    expect(wizard()).not.toBeInTheDocument()
+    await user.click(screen.getByRole('button', { name: /Convertir a cliente/ }))
+    expect(wizard()).toBeInTheDocument()
+  })
+
+  it('un lead ya convertido no espera condiciones: no las tiene', () => {
+    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
+    montar({ lead: { ...LEAD, etapa: 'convertido' } })
+    expect(wizard()).toBeInTheDocument()
+  })
+
+  it('quien ya no puede contratar no ve reabrirse el wizard aunque lleguen las condiciones', async () => {
+    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
+    montar({ puedeContratar: false })
+    await lleganLasCondiciones()
+    expect(wizard()).not.toBeInTheDocument()
+    expect(screen.queryByRole('button', { name: /Convertir a cliente/ })).not.toBeInTheDocument()
+  })
+
+  it('un lead que pasó a otro analista no reabre el wizard del anterior', async () => {
+    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
+    montar({ lead: { ...LEAD, vendedor_id: OTRO, vendedor_nombre: 'ANALISTA B' } })
+    await lleganLasCondiciones()
+    expect(wizard()).not.toBeInTheDocument()
+  })
+
+  it('un lead descartado no reabre nada', () => {
+    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
+    montar({ lead: { ...LEAD, etapa: 'descartado', motivo_descarte: 'sin_interes' } })
+    expect(wizard()).not.toBeInTheDocument()
+  })
+
+  it('el modo demo nunca retoma un wizard real', () => {
+    guardarConversionAbierta(VENDEDOR, LEAD.id, PERSONA)
+    montar({ demo: true, lead: { ...LEAD, etapa: 'convertido' } })
+    expect(screen.queryByRole('dialog', { name: /Wizard de conversión/ })).not.toBeInTheDocument()
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/components/app/lead-drawer.tsx b/CRM-Avance-Corp/app/src/components/app/lead-drawer.tsx
index 7e6d6e41..9eec7455 100644
--- a/CRM-Avance-Corp/app/src/components/app/lead-drawer.tsx
+++ b/CRM-Avance-Corp/app/src/components/app/lead-drawer.tsx
@@ -1,13 +1,14 @@
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
@@ -167,16 +168,39 @@ function Ficha({ l }: { l: Lead }) {
   const esTerminal = l.etapa === 'convertido' || l.etapa === 'descartado'
   const [dialogo, setDialogo] = useState<'convertir' | 'descartar' | null>(null)
   // Reabrir el descarte de alguien que ya es cliente no reabre nada: se muestra quién es y se
   // ofrece su venta cruzada. Vive aquí y no en el banner: el reabrir optimista pasa el lead a
   // «Nuevo» (y desmonta el banner) antes de que el servidor responda.
   const [clienteDelLead, setClienteDelLead] = useState<BusquedaCliente | null>(null)
   const [condicionesLead, setCondicionesLead] = useState<EstadoCondicionesLead | null>(null)
   const bloqueoTasa = condicionesLead?.bloqueo ?? (condicionesLead ? null : 'Verifica las condiciones de inversión antes de convertir.')
+  // Recargar la página con el wizard de conversión abierto lo retoma, con el mismo
+  // permiso que sus botones. Espera a conocer las condiciones de tasa: el contrato
+  // las toma al montarse (un convertido ya no las tiene; un descartado no convierte).
+  // Si no llegan, «Convertir a cliente» lo retoma igual, sin volver a pedir la identidad.
+  const conversionAbierta = () => Boolean(yo && !yo.demo && leerConversionAbierta(yo.id, l.id))
+  const [retomarConversion, setRetomarConversion] = useState(conversionAbierta)
+  if (retomarConversion && puedeConvertir && (condicionesLead !== null || l.etapa === 'convertido')) {
+    setRetomarConversion(false)
+    // Se vuelve a mirar la marca: quien ya cerró el wizard a mano no quiere que reaparezca.
+    if (conversionAbierta()) setDialogo(actual => actual ?? 'convertir')
+  }
+  // Un modal que aparece solo le quita el foco a quien ya está trabajando en la ficha:
+  // al primer gesto la retoma queda para el botón, que tampoco vuelve a pedir la identidad.
+  useEffect(() => {
+    if (!retomarConversion) return
+    const desarmar = () => setRetomarConversion(false)
+    window.addEventListener('keydown', desarmar, true)
+    window.addEventListener('pointerdown', desarmar, true)
+    return () => {
+      window.removeEventListener('keydown', desarmar, true)
+      window.removeEventListener('pointerdown', desarmar, true)
+    }
+  }, [retomarConversion])
   // Señal header → Datos: el badge "Sin capital estimado" abre el modo edición
   // de la sección Datos sin duplicar su estado (contador incremental).
   const [pedirEditarDatos, setPedirEditarDatos] = useState(0)
   const [componiendoGestion, setComponiendoGestion] = useState(false)
   const [tareaAviso, setTareaAviso] = useState<Tarea | null>(null)
   const refEtapa = useRef<HTMLDivElement>(null)
   const refDatos = useRef<HTMLDivElement>(null)
   const refActividad = useRef<HTMLDivElement>(null)
@@ -1847,19 +1871,20 @@ export function Timeline({ l, escribe, activa, puedeRegistrarGestion, componiend
 
 // ── Diálogos de cierre ────────────────────────────────────────────────────────
 
 /** El botón sólo aporta el origen; la inversión usa el flujo compartido. */
 export function DialogConvertir({l,onClose,condicionesTasa}: {
   l:Lead;onClose:()=>void;condicionesTasa?:CondicionesTasaLead|undefined;bloqueoTasa?:string|null
 }) {
   const {yo}=useAuth()
+  // La clave es la frontera del documento fijado y de la persona preparada: nunca pasan a otra cuenta ni a otro lead.
   return yo?.demo
     ? <InversionDesdeLeadDemo l={l} onClose={onClose} condicionesTasa={condicionesTasa}/>
-    : <InversionDesdeLead l={l} onClose={onClose} condicionesTasa={condicionesTasa}/>
+    : <InversionDesdeLead key={`${yo?.id}:${l.id}`} l={l} onClose={onClose} condicionesTasa={condicionesTasa}/>
 }
 
 function DialogDescartar({ l, onClose }: { l: Lead; onClose: () => void }) {
   const { descartar } = useCRMData()
   const { yo } = useAuth()
   const [motivo, setMotivo] = useState<MotivoDescarte>('sin_interes')
   const [nota, setNota] = useState('')
 
diff --git a/CRM-Avance-Corp/app/src/components/ui/dialog.test.tsx b/CRM-Avance-Corp/app/src/components/ui/dialog.test.tsx
index d0a82213..a897fa61 100644
--- a/CRM-Avance-Corp/app/src/components/ui/dialog.test.tsx
+++ b/CRM-Avance-Corp/app/src/components/ui/dialog.test.tsx
@@ -61,9 +61,32 @@ describe('foco de Dialog controlado sin Trigger', () => {
     await usuario.click(screen.getByRole('button', { name: 'Revisar solicitud' }))
     await usuario.click(screen.getByRole('button', { name: 'Resolver' }))
     await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Revisión' })).not.toBeInTheDocument())
     const ficha = screen.getByRole('dialog', { name: 'Ficha' })
     await waitFor(() => expect(ficha).toHaveFocus())
     await usuario.tab()
     expect(screen.getByRole('button', { name: 'Otra acción de la ficha' })).toHaveFocus()
   })
+
+  it('un diálogo que releva a otro dentro de la ficha devuelve el foco a la ficha al cerrarse', async () => {
+    // El segundo nace cuando el botón enfocado del primero ya no existe: no tiene origen.
+    function Relevo() {
+      const [paso, setPaso] = useState<'cerrado' | 'carga' | 'formulario'>('cerrado')
+      return <Sheet open onClose={() => undefined}><SheetTitle>Ficha</SheetTitle>
+        <button onClick={() => setPaso('carga')}>Convertir a cliente</button>
+        {paso === 'carga' && <Dialog open onClose={() => setPaso('cerrado')}>
+          <DialogTitle>Cargando</DialogTitle><button onClick={() => setPaso('formulario')}>Llega el documento</button>
+        </Dialog>}
+        {paso === 'formulario' && <Dialog open onClose={() => setPaso('cerrado')}>
+          <DialogTitle>Formulario</DialogTitle><button onClick={() => setPaso('cerrado')}>Cancelar</button>
+        </Dialog>}
+      </Sheet>
+    }
+    const usuario = userEvent.setup()
+    render(<Relevo />)
+    await usuario.click(screen.getByRole('button', { name: 'Convertir a cliente' }))
+    await usuario.click(screen.getByRole('button', { name: 'Llega el documento' }))
+    await usuario.click(await screen.findByRole('button', { name: 'Cancelar' }))
+    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Formulario' })).not.toBeInTheDocument())
+    await waitFor(() => expect(screen.getByRole('dialog', { name: 'Ficha' })).toHaveFocus())
+  })
 })
diff --git a/CRM-Avance-Corp/app/src/components/ui/dialog.tsx b/CRM-Avance-Corp/app/src/components/ui/dialog.tsx
index 24f304f5..25beb54b 100644
--- a/CRM-Avance-Corp/app/src/components/ui/dialog.tsx
+++ b/CRM-Avance-Corp/app/src/components/ui/dialog.tsx
@@ -51,17 +51,21 @@ export function Dialog({ open, onClose, children, ariaLabel, className, focoAlCe
           <RadixDialog.Content
             ref={contenido}
             onEscapeKeyDown={(evento) => protegerEscapeAnidado(evento, contenido.current)}
             onKeyDown={(evento) => cerrarEscapeAnidado(evento, onClose)}
             onOpenAutoFocus={(evento) => {
               const activo = document.activeElement
               const origen = activo instanceof HTMLElement && activo !== document.body ? activo : null
               origenFoco.current = origen
-              ambitoFoco.current = origen?.closest<HTMLElement>('[role="dialog"]') ?? null
+              // Sin origen (un diálogo releva a otro, o se abre solo) el ámbito es la capa abierta de debajo.
+              ambitoFoco.current = origen?.closest<HTMLElement>('[role="dialog"]')
+                ?? Array.from(document.querySelectorAll<HTMLElement>('[data-slot="dialog"], [data-slot="sheet"]'))
+                  .filter((capa) => capa !== contenido.current).pop()
+                ?? null
               if (focoInicial?.current) {
                 evento.preventDefault()
                 focoInicial.current.focus({ preventScroll: true })
               }
             }}
             onCloseAutoFocus={(evento) => {
               if (focoAlCerrar) {
                 evento.preventDefault()
diff --git a/CRM-Avance-Corp/app/src/data/documento-lead.ts b/CRM-Avance-Corp/app/src/data/documento-lead.ts
index f64b91f9..a10c7029 100644
--- a/CRM-Avance-Corp/app/src/data/documento-lead.ts
+++ b/CRM-Avance-Corp/app/src/data/documento-lead.ts
@@ -9,24 +9,26 @@ import { respuestaInversionistas } from './inversionistas-api'
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
index 2bf7a39e..e975342b 100644
--- a/CRM-Avance-Corp/app/src/lib/inversion-solicitud.test.ts
+++ b/CRM-Avance-Corp/app/src/lib/inversion-solicitud.test.ts
@@ -1,10 +1,11 @@
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
@@ -161,9 +162,40 @@ describe('Contenido de una solicitud F5',()=>{
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
+    guardarConversionAbierta(actor,lead,base.inversionista_id)
+    guardarConversionAbierta(actor,otroLead,otro)
+    expect(leerConversionAbierta(actor,lead)).toBe(base.inversionista_id)
+    expect(leerConversionAbierta(actor,otroLead)).toBe(otro)
+    expect(leerConversionAbierta(otro,lead)).toBeNull()
+    // Solo de quién es: ni la solicitud ni nada de lo que el analista escribe viaja en la marca.
+    expect(Object.keys(JSON.parse(sessionStorage.getItem(`crm:f5:conversion-abierta:${actor}:${lead}`)!)).sort())
+      .toEqual(['actor','inversionista_id','lead','version'])
+    limpiarIntentosInversion(actor,base.inversionista_id,lead)
+    expect(leerConversionAbierta(actor,lead)).toBe(base.inversionista_id)
+    limpiarConversionAbierta(actor,lead)
+    expect(leerConversionAbierta(actor,lead)).toBeNull()
+    expect(leerConversionAbierta(actor,otroLead)).toBe(otro)
+    limpiarIntentosInversion()
+    expect(leerConversionAbierta(actor,otroLead)).toBeNull()
+  })
+  it('una marca dañada, de otra versión o copiada a otra clave equivale a no tenerla',()=>{
+    sessionStorage.clear()
+    const actor='22222222-2222-4222-8222-222222222222',lead='33333333-3333-4333-8333-333333333333'
+    const clave=`crm:f5:conversion-abierta:${actor}:${lead}`
+    const marca={version:1,actor,lead,inversionista_id:base.inversionista_id}
+    sessionStorage.setItem(clave,'{no es json');expect(leerConversionAbierta(actor,lead)).toBeNull()
+    sessionStorage.setItem(clave,JSON.stringify({...marca,version:2}));expect(leerConversionAbierta(actor,lead)).toBeNull()
+    sessionStorage.setItem(clave,JSON.stringify({...marca,inversionista_id:'no-es-uuid'}));expect(leerConversionAbierta(actor,lead)).toBeNull()
+    sessionStorage.setItem(clave,JSON.stringify({...marca,lead:base.inversionista_id}));expect(leerConversionAbierta(actor,lead)).toBeNull()
+    sessionStorage.setItem(clave,JSON.stringify(marca));expect(leerConversionAbierta(actor,lead)).toBe(base.inversionista_id)
+  })
 })
diff --git a/CRM-Avance-Corp/app/src/lib/inversion-solicitud.ts b/CRM-Avance-Corp/app/src/lib/inversion-solicitud.ts
index 391562fc..b0a78c4e 100644
--- a/CRM-Avance-Corp/app/src/lib/inversion-solicitud.ts
+++ b/CRM-Avance-Corp/app/src/lib/inversion-solicitud.ts
@@ -170,16 +170,46 @@ export function leerBorradorCondiciones(actor: string, persona: string, origen:
 }
 export function limpiarBorradorCondiciones(actor?: string, persona?: string, origen?: OrigenIntento): void {
   const prefijo = !actor ? PREFIJO_CONDICIONES : !persona ? `${PREFIJO_CONDICIONES}${actor}:`
     : `${PREFIJO_CONDICIONES}${actor}:${persona}:${tramoOrigen(origen)}:`
   try {for (const k of Object.keys(sessionStorage)) if (k.startsWith(prefijo)) sessionStorage.removeItem(k)}
   catch { /* El bloqueo de almacenamiento no puede impedir cerrar sesión. */ }
 }
 
+const PREFIJO_CONVERSION = 'crm:f5:conversion-abierta:'
+const ConversionAbiertaSchema = v.object({version: v.literal(1), actor: Uuid, lead: Uuid, inversionista_id: Uuid})
+const claveConversion = (actor: string, lead: string) => `${PREFIJO_CONVERSION}${actor}:${lead}`
+
+/** El wizard de conversión de este lead está abierto en ESTA pestaña: al recargar
+ * se retoma sin volver a pedir la identidad. Solo guarda de QUIÉN es (la persona);
+ * la solicitud la recupera el intento, que es el que sigue sus cambios, y el
+ * servidor vuelve a comprobar la persona y el ámbito al abrirlo. */
+export function guardarConversionAbierta(actor: string, lead: string, inversionista: string): void {
+  try {
+    sessionStorage.setItem(claveConversion(actor, lead), JSON.stringify(v.parse(ConversionAbiertaSchema, {
+      version: 1, actor, lead, inversionista_id: inversionista,
+    })))
+  } catch { /* Sin almacenamiento el wizard sigue abierto; solo no se retoma tras recargar. */ }
+}
+/** La persona del wizard abierto, o null si no hay nada que retomar. */
+export function leerConversionAbierta(actor: string, lead: string): string | null {
+  try {
+    const raw = sessionStorage.getItem(claveConversion(actor, lead))
+    const r = raw ? v.safeParse(ConversionAbiertaSchema, JSON.parse(raw)) : null
+    if (r?.success && r.output.actor === actor && r.output.lead === lead) return r.output.inversionista_id
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
@@ -195,16 +225,19 @@ export function leerIntentoInversion(actor: string, persona: string, origen?: Or
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
```
