ROLE: SECONDARY_REVIEWER.

Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.

Eres el revisor secundario (LEVEL 2: cambio solo de pantalla en el CRM React + TanStack Query v5; sin
servidor ni permisos). Intenta REFUTAR; no confirmes por cortesía. Sin base ni red: todo está
transcrito. Responde con VERDICT (APPROVE / CHANGES_REQUESTED / BLOCK), SUMMARY, FINDINGS P0–P3 con
evidencia citada, RISKS / TEST GAPS, NEXT ACTIONS, CONFIDENCE. Sin hallazgo sin evidencia.

## Contexto medido (29/09/2026, producción)
`crm.solicitudes_tasa_fn`: 91.175 llamadas en 4 días = 45 % de todas las RPC del CRM (5–7 ms cada
una; el coste es el volumen, no el tiempo). Origen: `RespuestasTasaProvider` (analistas y supervisores,
~30 personas) con `refetchInterval: 15_000, refetchIntervalInBackground: true, staleTime: 0`, siempre,
haya o no una solicitud pendiente. Es el sistema de AVISO al analista cuando Gerencia responde su
solicitud de tasa: toast, sonido y notificación de escritorio; el aviso debe llegar también con la
pestaña oculta (por eso `refetchIntervalInBackground: true`), y hay coordinación entre pestañas con
`navigator.locks` (ver provider). Al crear una solicitud, `crm-queries.ts` invalida
`crmQueryKeys.rentabilidad()` (prefijo de la clave del provider) → refetch inmediato.
Postventa: `postventa-queries.ts` sondea estado/ficha/vencimientos cada 15 s con `staleTime 0`; su
función es detectar si Gerencia apaga la postventa (bandera F6); las escrituras llaman
`refrescarPostventa` (invalidación) y el servidor rechaza acciones con la postventa apagada.
`query-client.ts` global: `staleTime: 30_000, refetchOnWindowFocus: true`.

Objetivo aprobado por el dueño: −80 % de llamadas de tasas y −75 % de postventa, SIN que el aviso de
respuesta tarde más cuando el analista tiene una solicitud pendiente (≤ 15 s).

## Diff completo (rama `crm/sondeo-adaptativo` sobre avancecorp/main 43606c00)
```diff
diff --git a/CRM-Avance-Corp/app/src/components/app/respuestas-tasa-provider.test.tsx b/CRM-Avance-Corp/app/src/components/app/respuestas-tasa-provider.test.tsx
index 457da97e..b687b44a 100644
--- a/CRM-Avance-Corp/app/src/components/app/respuestas-tasa-provider.test.tsx
+++ b/CRM-Avance-Corp/app/src/components/app/respuestas-tasa-provider.test.tsx
@@ -52,6 +52,12 @@ describe('ciclo de sesión de las respuestas del analista', () => {
     dobles.consulta = { ...dobles.consulta, isFetchedAfterMount: false, data: [respuesta()] }
     const vista = render(<RespuestasTasaProvider><Probe /></RespuestasTasaProvider>)
     expect(dobles.query).toHaveBeenCalledWith(expect.objectContaining({ queryKey: ['crm', 'rentabilidad', 'respuestas-analista', 'v-provider'], refetchIntervalInBackground: true }))
+    // Ritmo adaptativo: 2 min en reposo; 15 s solo con una solicitud propia pendiente de Gerencia.
+    const opciones = dobles.query.mock.calls.at(-1)![0] as { refetchInterval: (q: { state: { data?: SolicitudTasa[] | undefined } }) => number }
+    expect(opciones.refetchInterval({ state: { data: [respuesta()] } })).toBe(120_000)
+    expect(opciones.refetchInterval({ state: { data: undefined } })).toBe(120_000)
+    expect(opciones.refetchInterval({ state: { data: [respuesta({ estado: 'pendiente', estado_efectivo: 'pendiente', resuelta_por: null, resuelta_en: null })] } })).toBe(15_000)
+    expect(opciones.refetchInterval({ state: { data: [respuesta({ estado: 'pendiente', estado_efectivo: 'pendiente', solicitada_por: 'v-otro' })] } })).toBe(120_000)
     expect(dobles.toast).not.toHaveBeenCalled()
     dobles.consulta = { ...dobles.consulta, isFetchedAfterMount: true, dataUpdatedAt: 2,
       data: [respuesta(), respuesta({ id: 'ajena', solicitada_por: 'v-otro', cliente_nombre: 'NO REVELAR' })] }
diff --git a/CRM-Avance-Corp/app/src/components/app/respuestas-tasa-provider.tsx b/CRM-Avance-Corp/app/src/components/app/respuestas-tasa-provider.tsx
index e27579c7..3396c701 100644
--- a/CRM-Avance-Corp/app/src/components/app/respuestas-tasa-provider.tsx
+++ b/CRM-Avance-Corp/app/src/components/app/respuestas-tasa-provider.tsx
@@ -8,8 +8,8 @@ import { AUTH_CLEARED_EVENT } from '@/lib/seguridad'
 import { escribirHash, leerHash } from '@/lib/router'
 import {
   claveRegistroRespuestas, claveRespuestaTasa, conBloqueoRespuestas, crearSonidoRespuesta,
-  esRespuestaPropia, guardarRegistroRespuestas, incorporarRespuestas, leerRegistroRespuestas,
-  recibeRespuestasTasa, tituloRespuestaTasa, type RegistroRespuestasTasa,
+  esRespuestaPropia, guardarRegistroRespuestas, incorporarRespuestas, intervaloConsultaRespuestas,
+  leerRegistroRespuestas, recibeRespuestasTasa, tituloRespuestaTasa, type RegistroRespuestasTasa,
 } from '@/lib/respuestas-tasa'
 import { RespuestasTasaContext } from '@/lib/respuestas-tasa-context'
 import { DialogoRespuestasTasa } from './respuestas-tasa'
@@ -38,7 +38,10 @@ function RespuestasDeCuenta({ cuentaId, children }: { cuentaId: string; children
     queryFn: ({ signal }) => listarSolicitudesTasa(null, signal, { soloMias: true, limite: 500 }),
     enabled: !apagado,
     staleTime: 0,
-    refetchInterval: 15_000,
+    // Ritmo adaptativo: 15 s solo mientras hay una solicitud propia pendiente; 2 min en reposo.
+    // Sigue en segundo plano porque el aviso de escritorio y el sonido se entregan con la
+    // pestaña oculta; al volver a la pestaña se consulta al instante (staleTime 0).
+    refetchInterval: (query) => intervaloConsultaRespuestas(query.state.data, cuentaId),
     refetchIntervalInBackground: true,
   })
   const solicitudes = useMemo(() => (consulta.data ?? [])
diff --git a/CRM-Avance-Corp/app/src/data/postventa-queries.ts b/CRM-Avance-Corp/app/src/data/postventa-queries.ts
index 1b019ad2..7f5998f8 100644
--- a/CRM-Avance-Corp/app/src/data/postventa-queries.ts
+++ b/CRM-Avance-Corp/app/src/data/postventa-queries.ts
@@ -5,7 +5,11 @@ import type { EmpresaInversion } from '@/lib/inversionistas'
 import { queryClient } from '@/lib/query-client'
 
 export const postventaKeys = {actor: (actor: string) => ['crm', 'postventa', actor] as const}
-const vigente = {staleTime: 0, gcTime: 0, retry: false, refetchInterval: 15_000,
+// Cada 60 s (antes 15) y solo con la pestaña visible: el sondeo únicamente detecta si Gerencia
+// apaga la postventa; las escrituras ya refrescan (refrescarPostventa), al volver a la pestaña se
+// consulta al instante y el servidor rechaza cualquier acción con la postventa apagada.
+export const POSTVENTA_REFRESCO_MS = 60_000
+const vigente = {staleTime: 0, gcTime: 0, retry: false, refetchInterval: POSTVENTA_REFRESCO_MS,
   refetchOnMount: 'always' as const, refetchOnWindowFocus: 'always' as const, refetchOnReconnect: 'always' as const}
 export function usePostventa(actor: string, habilitada = true) {
   return useQuery({...vigente, queryKey: [...postventaKeys.actor(actor), 'estado'],
diff --git a/CRM-Avance-Corp/app/src/lib/respuestas-tasa.test.ts b/CRM-Avance-Corp/app/src/lib/respuestas-tasa.test.ts
index 2ffb8783..43a72bef 100644
--- a/CRM-Avance-Corp/app/src/lib/respuestas-tasa.test.ts
+++ b/CRM-Avance-Corp/app/src/lib/respuestas-tasa.test.ts
@@ -3,7 +3,7 @@ import type { SolicitudTasa } from '@/data/crm-api'
 import {
   claveRegistroRespuestas, claveRespuestaTasa, conBloqueoRespuestas, crearSonidoRespuesta,
   esRespuestaPropia, guardarRegistroRespuestas, incorporarRespuestas, leerRegistroRespuestas,
-  recibeRespuestasTasa, tituloRespuestaTasa,
+  intervaloConsultaRespuestas, recibeRespuestasTasa, tituloRespuestaTasa,
 } from './respuestas-tasa'
 
 function solicitud(cambios: Partial<SolicitudTasa> = {}): SolicitudTasa {
@@ -119,3 +119,22 @@ describe('registro local de respuestas de tasa', () => {
     vi.unstubAllGlobals()
   })
 })
+
+describe('ritmo de consulta de respuestas', () => {
+  const pendiente = (cambios: Partial<SolicitudTasa> = {}) =>
+    solicitud({ estado: 'pendiente', estado_efectivo: 'pendiente', resuelta_por: null, resuelta_en: null, ...cambios })
+
+  it('pregunta cada 15 s solo mientras hay una solicitud propia pendiente de Gerencia', () => {
+    expect(intervaloConsultaRespuestas([pendiente()], 'v-1')).toBe(15_000)
+    expect(intervaloConsultaRespuestas([solicitud(), pendiente()], 'v-1')).toBe(15_000)
+  })
+
+  it('en reposo pregunta cada 2 min: sin datos, sin solicitudes, resueltas, vencidas o ajenas', () => {
+    expect(intervaloConsultaRespuestas(undefined, 'v-1')).toBe(120_000)
+    expect(intervaloConsultaRespuestas([], 'v-1')).toBe(120_000)
+    expect(intervaloConsultaRespuestas([solicitud()], 'v-1')).toBe(120_000)
+    expect(intervaloConsultaRespuestas([pendiente({ estado_efectivo: 'vencida' })], 'v-1')).toBe(120_000)
+    expect(intervaloConsultaRespuestas([pendiente({ es_mia: false })], 'v-1')).toBe(120_000)
+    expect(intervaloConsultaRespuestas([pendiente({ solicitada_por: 'v-2' })], 'v-1')).toBe(120_000)
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/lib/respuestas-tasa.ts b/CRM-Avance-Corp/app/src/lib/respuestas-tasa.ts
index f0bbfc70..24190283 100644
--- a/CRM-Avance-Corp/app/src/lib/respuestas-tasa.ts
+++ b/CRM-Avance-Corp/app/src/lib/respuestas-tasa.ts
@@ -9,6 +9,19 @@ export function esRespuestaPropia(s: SolicitudTasa, cuentaId: string): boolean {
     && !!s.resuelta_en && Number.isFinite(Date.parse(s.resuelta_en))
 }
 
+export const CONSULTA_RESPUESTAS_ACTIVA_MS = 15_000
+export const CONSULTA_RESPUESTAS_REPOSO_MS = 120_000
+
+// Solo una solicitud PROPIA que sigue pendiente de Gerencia justifica preguntar cada 15 s
+// (`estado_efectivo`: una pendiente ya vencida no espera respuesta). El resto del tiempo,
+// 2 min: medido el 29/09/2026, este sondeo era el 45 % de todas las llamadas del CRM al
+// servidor. Una solicitud creada desde otra pestaña entra en el ritmo activo en la
+// siguiente consulta de reposo.
+export function intervaloConsultaRespuestas(solicitudes: readonly SolicitudTasa[] | undefined, cuentaId: string): number {
+  const pendiente = (solicitudes ?? []).some(s => s.es_mia && s.solicitada_por === cuentaId && s.estado_efectivo === 'pendiente')
+  return pendiente ? CONSULTA_RESPUESTAS_ACTIVA_MS : CONSULTA_RESPUESTAS_REPOSO_MS
+}
+
 // La decisión de Gerencia se conserva aunque después se consuma o venza la tasa.
 export function tituloRespuestaTasa(s: SolicitudTasa): string {
   if (s.tasa_maxima_autorizada == null) return 'Tu solicitud de tasa fue rechazada'
```

## Tipos relevantes (`data/crm-api.ts`)
```ts
export type EstadoSolicitudTasa = 'pendiente' | 'aprobada' | 'aprobada_con_tope' | 'rechazada'
  | 'aceptada_por_analista' | 'declinada_por_analista' | 'consumida' | 'vencida'
// SolicitudTasa: { id, es_mia: boolean, solicitada_por: string, resuelta_por: string|null, resuelta_en: string|null,
//   estado: EstadoSolicitudTasa, estado_efectivo: EstadoSolicitudTasa, tasa_solicitada, tasa_maxima_autorizada, cliente_nombre, ... }
// listarSolicitudesTasa(null, signal, { soloMias: true, limite: 500 }) → SolicitudTasa[]
```

## Verificación hecha
Unit: `respuestas-tasa.test.ts` (nuevo describe «ritmo de consulta»: pendiente propia → 15 s; sin datos,
vacío, resueltas, vencidas, ajenas → 2 min) y `respuestas-tasa-provider.test.tsx` (la opción
`refetchInterval` pasada a useQuery devuelve 120 s en reposo y 15 s con pendiente propia; ajena → 120 s):
20/20 PASS. `npm run check` completo y E2E Docker (respuestas-tasa, notificaciones-tasa,
solicitud-tasa, f6-postventa) en curso.

## Refuta
R1. TanStack Query v5: ¿`refetchInterval` como función recibe `query` con `state.data` tipado y se
reevalúa tras cada fetch (para pasar de 2 min a 15 s en cuanto aparece una pendiente)? ¿Un valor
`false`/0 en algún camino apagaría el sondeo por accidente?
R2. Casos donde el aviso llegaría MÁS TARDE que hoy con el analista esperando: solicitud creada en otra
pestaña/dispositivo (esta pestaña tarda ≤ 2 min en enterarse), respuesta de Gerencia a una solicitud cuyo
`estado_efectivo` no es 'pendiente' pero sigue esperando (¿existe ese estado?), error de red (¿qué
intervalo aplica cuando `state.data` es de un fetch previo y el último falló?).
R3. `estado_efectivo === 'pendiente'` vs `estado === 'pendiente'`: ¿cuál es correcto para «espera
respuesta de Gerencia»? ¿Una solicitud `aprobada_con_tope` que espera «aceptar/declinar» del analista
debe seguir a 15 s? (hoy el aviso se dispara con `esRespuestaPropia` = resuelta_por+resuelta_en).
R4. Postventa a 60 s: ¿algún flujo depende de detectar en < 60 s el apagado de F6 o un cambio de
`fichaPostventa`/`vencimientos` hecho por OTRO usuario? ¿`refrescarPostventa` cubre todas las
escrituras de postventa (postventa-envios.ts)?
R5. ¿Alguna prueba existente (unit o e2e) asume 15 s? (Las e2e citadas usan `page.reload()`.)
