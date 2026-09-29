ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md (its content is transcribed at the end).

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato obligatorio: VERDICT (PASS / CHANGES_REQUESTED / BLOCK), SUMMARY,
FINDINGS P0–P3 con evidencia (archivo:línea o fragmento citado de este encargo), TEST GAPS,
REGRESSION RISKS, RECOMMENDED NEXT ACTIONS, CONFIDENCE. Sin hallazgo sin evidencia; marca como
hipótesis lo no demostrado. Omite secciones vacías.

# Encargo: REFUTAR el CÓDIGO del «anexo de cronograma imprimible» antes de producción — LEVEL 3

Ya refutaste el plan v3 (CHANGES_REQUESTED). Cambios aplicados respecto a ese plan, por tus hallazgos:
- Liquidación final = fila `retorno` del cronograma SELLADO, validada (una sola, monto = capital, fecha ≥ vencimiento); si no cuadra, el anexo no se emite (409 ANEXO_CRONOGRAMA_INCOHERENTE).
- Entrega en JSON (`pdf_base64` + sha256 + bytes + nombre) por `functions.invoke`; el front verifica tamaño, cabecera %PDF- y hash, crea el Blob como application/pdf y abre la pestaña EN el clic (patrón ya existente `abrirVentanaContratoPdf`).
- Bitácora por impresión en `private.contrato_pdf_anexo_impresiones` (NO en public.audit_log: su CHECK de `operacion` es del portal y `bandeja_actividad` lo enseñaría al cliente). Sin snapshot (datos bancarios). Sin FK a contratos/contrato_pdfs (la eliminación auditada borra esas filas).
- Decisión de Miguel posterior al plan: «deja las firmas tal cual como están, implementa el documento tal cual como está» ⇒ el anexo lleva la firma impresa de Avance Corp y el texto «en la misma fecha de celebración», sin pie de procedencia visible. La procedencia vive en la bitácora.
- La «revisión vigente» es la que dice `private.contrato_pdf_estado_base` (trabajo más reciente, sellado y coherente con el ledger): una revisión nueva pendiente ⇒ ANEXO_SIN_PDF_SELLADO. Un sellado v1 (snapshot sin `snapshotVersion: 2`) ⇒ ANEXO_SIN_SNAPSHOT.
- La Edge acepta cualquier `template_version` del contrato sellado (no exige que sepa leerla: el anexo no la dibuja).

Verificación comunicada por el agente que lo implementó (sin revisar por ti todavía):
- Edge: `deno check` limpio, `deno test -A` 70/70 (goldens del anexo, contrato v9 byte-idéntico `6ffb935d…` 218 672 bytes, acción anexo con 401/403/409/502).
- Front: `npm run check` completo PASS (4 853 pruebas, build, bundle, dup); revisor a11y PASS (P3 aplicado: mensajes de la pestaña hablan del anexo, `lang=es`).
- Base: arnés local `run-test-contrato-pdf-v2-local.sh --run` ⇒ CONTRATO_PDF_V2_SQL_OK + RUNNER_OK con la migración incluida y el bloque nuevo de pruebas (permisos por catálogo, lectura del sellado, idempotencia, fuera de cartera, actor nulo, inexistente, plantilla inválida, ledger v1, pendiente sin asiento, bitácora solo añadir). ⚠️ Lección aplicada: ejecutar una función SIN EXECUTE bajo `set role` tumba el Postgres del banco; el permiso se acredita por `has_function_privilege`.
- e2e Docker: en curso (un crash de Chromium por carga del equipo; se relanza).
- NOT RUN: gate RLS completo contra banco con esquema de prod (`test-rls.mjs` no tiene casos de `contrato_pdf_*`); `gen:types` (solo tras aplicar en prod).

Refuta: autorización y orden de comprobaciones de la función; coherencia entre lo que devuelve la RPC y lo que exige `datosAnexoValidos` en la Edge; determinismo y tamaño de la respuesta JSON (base64 de ~165 KB); manejo de errores y códigos; validación del cronograma en `clasificarCronograma` frente a las formas reales del generador (simple: N `cuota` + 1 `retorno` a vencimiento+7 días; compuesto: 1 `devolucion` al vencimiento + 1 `retorno`); front (verificación de bytes, ventana, mensajes, demo); e2e; migración (preflight/postflight, grants, RLS, trigger, comentarios, reversa, registrador); lo que NO está probado.

## DIFF completo frente a main 39509453 (edge ya commiteada en 829c4afd + árbol de trabajo)
```diff
diff --git a/CRM-Avance-Corp/app/src/components/app/contrato-detalle-pdf.test.tsx b/CRM-Avance-Corp/app/src/components/app/contrato-detalle-pdf.test.tsx
index 0c6a439d..bb896276 100644
--- a/CRM-Avance-Corp/app/src/components/app/contrato-detalle-pdf.test.tsx
+++ b/CRM-Avance-Corp/app/src/components/app/contrato-detalle-pdf.test.tsx
@@ -10,6 +10,7 @@ import type { ContratoPdfDatos } from '@/lib/contrato-pdf'
 const toast = vi.hoisted(() => ({ error: vi.fn() }))
 const archivoPdf = vi.hoisted(() => ({
   abrir: vi.fn(),
+  anexo: vi.fn(),
   archivar: vi.fn(),
   archivarDemo: vi.fn(),
   consultar: vi.fn(),
@@ -31,6 +32,7 @@ vi.mock('@/lib/contrato-pdf-archivo', async (importOriginal) => ({
   consultarEstadoContratoPdf: archivoPdf.consultar,
   ContratoPdfNoSelladoError: class ContratoPdfNoSelladoError extends Error {},
   etiquetaEstadoContratoPdf: (estado: string) => estado,
+  imprimirAnexoCronograma: archivoPdf.anexo,
   obtenerContratoPdfArchivado: archivoPdf.obtener,
   descargarArchivoContratoPdf: archivoPdf.descargar,
   verArchivoContratoPdf: archivoPdf.ver,
@@ -120,6 +122,16 @@ const archivo = {
   blob: new Blob(['%PDF-1.7\ndemo'], { type: 'application/pdf' }),
 }
 
+const anexo = {
+  contratoId: contrato.id,
+  contratoRevision: 1,
+  template: 'anexo-cronograma-v1',
+  nombreArchivo: 'Anexo-2026-01-000901-ROSA.pdf',
+  sha256: 'b'.repeat(64),
+  bytes: 17,
+  blob: new Blob(['%PDF-1.7\nanexo'], { type: 'application/pdf' }),
+}
+
 const { ContratoDetalle } = await import('./contrato-detalle')
 
 function render(elemento: ReactElement) {
@@ -155,6 +167,7 @@ describe('ContratoDetalle — PDF archivado', () => {
     archivoPdf.descargar.mockReset()
     archivoPdf.ver.mockReset()
     archivoPdf.abrir.mockReset().mockReturnValue({ close: vi.fn() })
+    archivoPdf.anexo.mockReset().mockResolvedValue(anexo)
   })
 
   it('en demo archiva una vez y descarga el objeto inmutable, no regenera directo', async () => {
@@ -320,6 +333,75 @@ describe('ContratoDetalle — PDF archivado', () => {
     expect(toast.error).toHaveBeenCalledWith('El navegador bloqueó la ventana del contrato PDF.')
     expect(archivoPdf.obtener).not.toHaveBeenCalled()
   })
+  // ── Anexo de cronograma: documento aparte que el analista imprime (28/09) ──
+  it('imprime el anexo de cronograma en una pestaña reservada en el clic, sin tocar el contrato', async () => {
+    const user = userEvent.setup()
+    consultas.contrato = contrato
+    const ventana = { close: vi.fn() }
+    archivoPdf.abrir.mockReturnValue(ventana)
+    render(
+      <Dialog open onClose={() => undefined} ariaLabel="Detalle del contrato">
+        <ContratoDetalle contratoId={contrato.id} onCerrar={() => undefined} />
+      </Dialog>,
+    )
+
+    await user.click(screen.getByRole('button', { name: 'Imprimir anexo de cronograma' }))
+
+    await waitFor(() => expect(archivoPdf.ver).toHaveBeenCalledWith(anexo, ventana))
+    expect(archivoPdf.abrir).toHaveBeenCalledWith(
+      'Preparando anexo de cronograma…',
+      'Preparando el anexo de cronograma desde el contrato sellado…',
+      'anexo de cronograma',
+    )
+    expect(archivoPdf.anexo).toHaveBeenCalledWith(contrato.id)
+    expect(archivoPdf.obtener).not.toHaveBeenCalled()
+    expect(archivoPdf.archivar).not.toHaveBeenCalled()
+    expect(ventana.close).not.toHaveBeenCalled()
+    expect(toast.error).not.toHaveBeenCalled()
+  })
+
+  it('si el contrato no tiene PDF sellado, cierra la pestaña y muestra el aviso del servidor', async () => {
+    const user = userEvent.setup()
+    consultas.contrato = contrato
+    const ventana = { close: vi.fn() }
+    archivoPdf.abrir.mockReturnValue(ventana)
+    archivoPdf.anexo.mockRejectedValue(
+      new Error('El contrato todavía no tiene su PDF sellado; genera primero el contrato PDF'),
+    )
+    render(
+      <Dialog open onClose={() => undefined} ariaLabel="Detalle del contrato">
+        <ContratoDetalle contratoId={contrato.id} onCerrar={() => undefined} />
+      </Dialog>,
+    )
+
+    await user.click(screen.getByRole('button', { name: 'Imprimir anexo de cronograma' }))
+
+    await waitFor(() =>
+      expect(toast.error).toHaveBeenCalledWith(
+        'El contrato todavía no tiene su PDF sellado; genera primero el contrato PDF',
+      ),
+    )
+    expect(ventana.close).toHaveBeenCalled()
+    expect(archivoPdf.ver).not.toHaveBeenCalled()
+    expect(screen.getByRole('button', { name: 'Imprimir anexo de cronograma' })).toBeEnabled()
+  })
+
+  it('en modo demo no ofrece el anexo (no hay contrato sellado del que sacarlo)', () => {
+    consultas.contrato = contrato
+    render(
+      <Dialog open onClose={() => undefined} ariaLabel="Detalle del contrato">
+        <ContratoDetalle
+          contratoId={contrato.id}
+          datos={{ contrato, cuotas: [], titulares: [], pdfDatos }}
+          onCerrar={() => undefined}
+        />
+      </Dialog>,
+    )
+
+    expect(screen.getByRole('button', { name: 'Ver contrato PDF' })).toBeInTheDocument()
+    expect(screen.queryByRole('button', { name: 'Imprimir anexo de cronograma' })).toBeNull()
+  })
+
   // ── El régimen documental anterior (2026-08-20) ────────────────────────────
   // «Ver contrato PDF» no muestra: si no hay documento, lo FABRICA. En un
   // contrato firmado antes del 19/08 eso acuñaba un segundo contrato para una
diff --git a/CRM-Avance-Corp/app/src/components/app/contrato-detalle.tsx b/CRM-Avance-Corp/app/src/components/app/contrato-detalle.tsx
index 41896820..a5187ddd 100644
--- a/CRM-Avance-Corp/app/src/components/app/contrato-detalle.tsx
+++ b/CRM-Avance-Corp/app/src/components/app/contrato-detalle.tsx
@@ -8,7 +8,7 @@ import { mensajeErrorEliminacionContrato } from '@/lib/contrato-pdf-archivo'
 // (mismo patrón que ContratoNuevo: el caller pone el Dialog, aquí va el panel).
 import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
 import { useQueryClient } from '@tanstack/react-query'
-import { Download, ExternalLink, FileText, LoaderCircle, RotateCcw, Trash2, WifiOff } from 'lucide-react'
+import { Download, ExternalLink, FileText, LoaderCircle, Printer, RotateCcw, Trash2, WifiOff } from 'lucide-react'
 import { toast } from 'sonner'
 import { Badge } from '@/components/ui/badge'
 import { Button } from '@/components/ui/button'
@@ -34,6 +34,7 @@ import { CODIGO_PRODUCTO_HISTORICO } from '@/components/app/producto-contrato-se
 import type { ContratoPdfDatos } from '@/lib/contrato-pdf'
 import {
   abrirVentanaContratoPdf,
+  AnexoCronogramaError,
   archivarContratoPdfConfirmado,
   consultarEstadoContratoPdf,
   CONTRATO_DOCUMENTO_DESDE_TEXTO,
@@ -41,6 +42,7 @@ import {
   descargarArchivoContratoPdf,
   esContratoRegimenAnterior,
   etiquetaEstadoContratoPdf,
+  imprimirAnexoCronograma,
   obtenerContratoPdfArchivado,
   verArchivoContratoPdf,
   type EstadoContratoPdf,
@@ -180,7 +182,7 @@ export function ContratoDetalle({ contratoId, onCerrar, datos,
   const [accionPdfUi, setAccionPdfUi] = useState<{
     contratoId: string
     secuencia: number
-    accion: 'ver' | 'descargar'
+    accion: 'ver' | 'descargar' | 'anexo'
   } | null>(null)
   const [estadoPdfUi, setEstadoPdfUi] = useState<EstadoPdfUi>(() => ({
     contratoId,
@@ -352,6 +354,47 @@ export function ContratoDetalle({ contratoId, onCerrar, datos,
     }
   }
 
+  // Anexo de cronograma: documento APARTE que el analista imprime cuando quiere
+  // (Miguel, 28/09/2026). La Edge lo dibuja desde los datos congelados del
+  // contrato sellado; aquí solo se abre en una pestaña. No existe en modo demo.
+  const ejecutarAnexo = async () => {
+    if (!contrato || accionPdf || pdfDatos) return
+    const contratoIdAccion = contratoId
+    const secuenciaAccion = ++secuenciaAccionPdfRef.current
+    const accionSigueVigente = () =>
+      contratoIdActualRef.current === contratoIdAccion
+      && secuenciaAccionPdfRef.current === secuenciaAccion
+    let ventanaAnexo: Window | null = null
+    try {
+      // La pestaña se reserva dentro del gesto del usuario, como en «Ver».
+      ventanaAnexo = abrirVentanaContratoPdf(
+        'Preparando anexo de cronograma…',
+        'Preparando el anexo de cronograma desde el contrato sellado…',
+        'anexo de cronograma',
+      )
+      setAccionPdfUi({ contratoId: contratoIdAccion, secuencia: secuenciaAccion, accion: 'anexo' })
+      const anexo = await imprimirAnexoCronograma(contratoId)
+      if (!accionSigueVigente()) {
+        ventanaAnexo.close()
+        return
+      }
+      verArchivoContratoPdf(anexo, ventanaAnexo)
+    } catch (error) {
+      ventanaAnexo?.close()
+      if (!accionSigueVigente()) return
+      if (!(error instanceof AnexoCronogramaError)) {
+        console.error('[contrato-pdf] No se pudo generar el anexo de cronograma', error)
+      }
+      toast.error(
+        error instanceof Error
+          ? error.message
+          : 'No se pudo generar el anexo de cronograma. Inténtalo nuevamente.',
+      )
+    } finally {
+      setAccionPdfUi((actual) => (actual?.secuencia === secuenciaAccion ? null : actual))
+    }
+  }
+
   // Totales con las mismas reglas del portal: las cuotas de interés excluyen el
   // retorno del capital; "Pagado" suma lo COBRADO real (monto_pagado) y
   // "Por pagar" excluye lo trasladado (ese capital vive en la renovación).
@@ -848,6 +891,24 @@ export function ContratoDetalle({ contratoId, onCerrar, datos,
               )}
               Descargar contrato PDF
             </Button>
+            {/* El anexo sale del snapshot sellado, no de los bytes del PDF: por
+                eso no se bloquea con `integridad_bloqueada` como Ver/Descargar. */}
+            {!pdfDatos && (
+              <Button
+                variant="outline"
+                size="sm"
+                disabled={eliminando || accionPdf != null}
+                onClick={() => void ejecutarAnexo()}
+              >
+                {accionPdf === 'anexo'
+                  ? (
+                  <LoaderCircle className="animate-spin" aria-hidden />
+                ) : (
+                  <Printer aria-hidden />
+                )}
+                Imprimir anexo de cronograma
+              </Button>
+            )}
           </>
         )}
         <Button variant="outline" size="sm" disabled={eliminando} onClick={onCerrar}>
diff --git a/CRM-Avance-Corp/app/src/lib/contrato-pdf-archivo.test.ts b/CRM-Avance-Corp/app/src/lib/contrato-pdf-archivo.test.ts
index 7769b228..72a583bb 100644
--- a/CRM-Avance-Corp/app/src/lib/contrato-pdf-archivo.test.ts
+++ b/CRM-Avance-Corp/app/src/lib/contrato-pdf-archivo.test.ts
@@ -8,11 +8,13 @@ vi.mock('./supabase', () => ({
 }))
 
 import {
+  AnexoCronogramaError,
   asegurarContratoPdfActualizado,
   archivarContratoPdfConfirmado,
   consultarEstadoContratoPdf,
   ContratoPdfNoSelladoError,
   eliminarContratoConPdf,
+  imprimirAnexoCronograma,
   obtenerContratoPdfArchivado,
 } from './contrato-pdf-archivo'
 
@@ -332,3 +334,95 @@ describe('cliente del archivo contractual server-side', () => {
     })
   })
 })
+
+// ── Anexo de cronograma (documento aparte, desde el snapshot sellado) ────────
+
+describe('anexo de cronograma imprimible', () => {
+  beforeEach(() => {
+    supabase.invoke.mockReset()
+  })
+
+  async function respuestaAnexo(contenido = '%PDF-1.7\nanexo de cronograma', overrides: Record<string, unknown> = {}) {
+    const blob = new Blob([contenido], { type: 'application/pdf' })
+    const bytes = new Uint8Array(await blob.arrayBuffer())
+    return {
+      anexo: {
+        contrato_id: CONTRATO_ID,
+        contrato_revision: 1,
+        contrato_template_version: 'contrato-aep-17-v9',
+        template: 'anexo-cronograma-v1',
+        nombre_archivo: 'Anexo-2026-01-000777-CLIENTE-PRUEBA.pdf',
+        sha256: await sha256(blob),
+        bytes: blob.size,
+        pdf_base64: btoa(String.fromCharCode(...bytes)),
+        ...overrides,
+      },
+    }
+  }
+
+  it('pide la acción «anexo» con JSON mínimo y entrega el PDF verificado por hash y tamaño', async () => {
+    supabase.invoke.mockResolvedValue({ data: await respuestaAnexo(), error: null })
+
+    const anexo = await imprimirAnexoCronograma(CONTRATO_ID)
+
+    expect(supabase.invoke).toHaveBeenCalledWith('crm-contrato-pdf-v2', {
+      body: { action: 'anexo', contratoId: CONTRATO_ID },
+    })
+    expect(anexo.nombreArchivo).toBe('Anexo-2026-01-000777-CLIENTE-PRUEBA.pdf')
+    expect(anexo.template).toBe('anexo-cronograma-v1')
+    expect(anexo.contratoRevision).toBe(1)
+    expect(anexo.blob.type).toBe('application/pdf')
+    expect(await anexo.blob.text()).toBe('%PDF-1.7\nanexo de cronograma')
+  })
+
+  it('rechaza un anexo cuyo hash o tamaño no coincide con lo declarado', async () => {
+    supabase.invoke.mockResolvedValue({
+      data: await respuestaAnexo(undefined, { sha256: 'f'.repeat(64) }),
+      error: null,
+    })
+    await expect(imprimirAnexoCronograma(CONTRATO_ID)).rejects.toThrow('hash')
+
+    supabase.invoke.mockResolvedValue({
+      data: await respuestaAnexo(undefined, { bytes: 9 }),
+      error: null,
+    })
+    await expect(imprimirAnexoCronograma(CONTRATO_ID)).rejects.toThrow('tamaño')
+  })
+
+  it('rechaza el anexo de otro contrato y respuestas con claves inesperadas', async () => {
+    supabase.invoke.mockResolvedValue({
+      data: await respuestaAnexo(undefined, { contrato_id: '11111111-1111-4111-8111-111111111111' }),
+      error: null,
+    })
+    await expect(imprimirAnexoCronograma(CONTRATO_ID)).rejects.toThrow('otro contrato')
+
+    supabase.invoke.mockResolvedValue({
+      data: await respuestaAnexo(undefined, { url: 'https://x.invalid' }),
+      error: null,
+    })
+    await expect(imprimirAnexoCronograma(CONTRATO_ID)).rejects.toThrow('formato esperado')
+  })
+
+  it('expone el código de negocio de la Edge (sin PDF sellado, sin snapshot, fuera de cartera)', async () => {
+    const respuesta = new Response(
+      JSON.stringify({
+        error: 'El contrato todavía no tiene su PDF sellado; genera primero el contrato PDF',
+        codigo: 'ANEXO_SIN_PDF_SELLADO',
+      }),
+      { status: 409, headers: { 'Content-Type': 'application/json' } },
+    )
+    supabase.invoke.mockResolvedValue({ data: null, error: new FunctionsHttpError(respuesta) })
+
+    const intento = imprimirAnexoCronograma(CONTRATO_ID)
+    await expect(intento).rejects.toBeInstanceOf(AnexoCronogramaError)
+    await expect(intento).rejects.toMatchObject({
+      codigo: 'ANEXO_SIN_PDF_SELLADO',
+      message: 'El contrato todavía no tiene su PDF sellado; genera primero el contrato PDF',
+    })
+  })
+
+  it('rechaza UUID no canónico antes de invocar la Edge', async () => {
+    await expect(imprimirAnexoCronograma(CONTRATO_ID.toUpperCase())).rejects.toThrow('canónico')
+    expect(supabase.invoke).not.toHaveBeenCalled()
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/lib/contrato-pdf-archivo.ts b/CRM-Avance-Corp/app/src/lib/contrato-pdf-archivo.ts
index 5bd3a3d4..e887e17c 100644
--- a/CRM-Avance-Corp/app/src/lib/contrato-pdf-archivo.ts
+++ b/CRM-Avance-Corp/app/src/lib/contrato-pdf-archivo.ts
@@ -409,7 +409,7 @@ export async function eliminarContratoConPdf(
   }
 }
 
-export function descargarArchivoContratoPdf(archivo: ArchivoContratoPdf): void {
+export function descargarArchivoContratoPdf(archivo: Pick<ArchivoContratoPdf, 'blob' | 'nombreArchivo'>): void {
   const url = URL.createObjectURL(archivo.blob)
   const enlace = document.createElement('a')
   enlace.href = url
@@ -422,18 +422,133 @@ export function descargarArchivoContratoPdf(archivo: ArchivoContratoPdf): void {
 }
 
 /** Debe llamarse sincrónicamente desde el click para conservar user activation. */
-export function abrirVentanaContratoPdf(): Window {
+export function abrirVentanaContratoPdf(
+  titulo = 'Preparando contrato PDF…',
+  mensaje = 'Verificando el archivo contractual privado…',
+  documento = 'contrato PDF',
+): Window {
   const ventana = window.open('about:blank', '_blank')
-  if (!ventana) throw new Error('El navegador bloqueó la ventana del contrato PDF.')
+  if (!ventana) throw new Error(`El navegador bloqueó la ventana del ${documento}.`)
   ventana.opener = null
-  ventana.document.title = 'Preparando contrato PDF…'
-  ventana.document.body.textContent = 'Verificando el archivo contractual privado…'
+  ventana.document.documentElement.lang = 'es'
+  ventana.document.title = titulo
+  ventana.document.body.textContent = mensaje
   return ventana
 }
 
-export function verArchivoContratoPdf(archivo: ArchivoContratoPdf, ventana: Window = abrirVentanaContratoPdf()): void {
+export function verArchivoContratoPdf(
+  archivo: Pick<ArchivoContratoPdf, 'blob'>,
+  ventana: Window = abrirVentanaContratoPdf(),
+): void {
   const url = URL.createObjectURL(archivo.blob)
   ventana.opener = null
   ventana.location.replace(url)
   window.setTimeout(() => URL.revokeObjectURL(url), 60_000)
 }
+
+// ── Anexo de cronograma: documento aparte, a demanda, desde el snapshot sellado ──
+//
+// Decisión de Miguel (28/09/2026): «todo sigue igual, solo que el añadido es que
+// el analista ahora puede imprimir este anexo». El contrato PDF no cambia. El
+// anexo lo dibuja la misma Edge desde los datos CONGELADOS del contrato sellado,
+// no se guarda, y llega en JSON (base64) con su hash para verificarlo aquí.
+
+const AnexoRespuestaSchema = v.strictObject({
+  anexo: v.strictObject({
+    contrato_id: v.string(),
+    contrato_revision: v.pipe(v.number(), v.integer(), v.minValue(1)),
+    contrato_template_version: v.pipe(v.string(), v.minLength(1)),
+    template: v.pipe(v.string(), v.minLength(1)),
+    nombre_archivo: v.pipe(v.string(), v.minLength(1), v.regex(/^Anexo-[A-Za-z0-9._-]+\.pdf$/)),
+    sha256: v.pipe(v.string(), v.regex(/^[0-9a-f]{64}$/)),
+    bytes: v.pipe(v.number(), v.integer(), v.minValue(6)),
+    pdf_base64: v.pipe(v.string(), v.minLength(8)),
+  }),
+})
+
+export type ArchivoAnexoCronograma = {
+  contratoId: string
+  contratoRevision: number
+  template: string
+  nombreArchivo: string
+  sha256: string
+  bytes: number
+  blob: Blob
+}
+
+/** Error de negocio del anexo, con el código que expone la Edge (ANEXO_*). */
+export class AnexoCronogramaError extends Error {
+  readonly codigo: string
+
+  constructor(mensaje: string, codigo: string) {
+    super(mensaje)
+    this.codigo = codigo
+  }
+}
+
+function base64ABytes(base64: string): Uint8Array {
+  const binario = atob(base64)
+  const bytes = new Uint8Array(binario.length)
+  for (let i = 0; i < binario.length; i++) bytes[i] = binario.charCodeAt(i)
+  return bytes
+}
+
+/**
+ * Pide a la Edge el anexo del contrato sellado y verifica hash y tamaño antes
+ * de entregar los bytes. Si el contrato no tiene PDF sellado, no tiene datos
+ * congelados aptos o está fuera de la cartera, lanza `AnexoCronogramaError`
+ * con el código del servidor.
+ */
+export async function imprimirAnexoCronograma(contratoId: string): Promise<ArchivoAnexoCronograma> {
+  exigirContratoIdCanonico(contratoId)
+  const { data, error } = await clienteSupabase().functions.invoke(CONTRATO_PDF_EDGE, {
+    body: { action: 'anexo', contratoId },
+  })
+  if (error) {
+    let mensaje = 'No se pudo preparar el anexo de cronograma.'
+    let codigo = 'ANEXO_RED'
+    if (error instanceof FunctionsHttpError) {
+      try {
+        const cuerpo = (await error.context.clone().json()) as unknown
+        if (cuerpo != null && typeof cuerpo === 'object') {
+          if ('error' in cuerpo && typeof cuerpo.error === 'string' && cuerpo.error.trim()) {
+            mensaje = cuerpo.error
+          }
+          if ('codigo' in cuerpo && typeof cuerpo.codigo === 'string' && cuerpo.codigo.trim()) {
+            codigo = cuerpo.codigo
+          }
+        }
+      } catch {
+        // La respuesta HTTP puede no ser JSON; conservamos el diagnóstico genérico.
+      }
+    }
+    throw new AnexoCronogramaError(mensaje, codigo)
+  }
+  const resultado = v.safeParse(AnexoRespuestaSchema, data)
+  if (!resultado.success) {
+    throw new Error('La respuesta del anexo no tiene el formato esperado.')
+  }
+  const anexo = resultado.output.anexo
+  if (anexo.contrato_id !== contratoId) {
+    throw new Error('El servidor respondió con el anexo de otro contrato.')
+  }
+  const bytes = base64ABytes(anexo.pdf_base64)
+  if (bytes.byteLength !== anexo.bytes) {
+    throw new Error('El anexo recibido no coincide con el tamaño declarado.')
+  }
+  // `bytes` nace de `new Uint8Array(n)`: su buffer es un ArrayBuffer exacto.
+  const blob = new Blob([bytes.buffer as ArrayBuffer], { type: 'application/pdf' })
+  await validarPdfBlob(blob)
+  if ((await sha256PdfHex(blob)) !== anexo.sha256) {
+    throw new Error('El anexo recibido no coincide con el hash declarado.')
+  }
+  return {
+    contratoId,
+    contratoRevision: anexo.contrato_revision,
+    template: anexo.template,
+    nombreArchivo: anexo.nombre_archivo,
+    sha256: anexo.sha256,
+    bytes: anexo.bytes,
+    blob,
+  }
+}
diff --git a/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/anexo-v1.ts b/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/anexo-v1.ts
new file mode 100644
index 00000000..a6dea7df
--- /dev/null
+++ b/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/anexo-v1.ts
@@ -0,0 +1,361 @@
+// Anexo de cronograma de liquidaciones parciales: documento APARTE del contrato.
+//
+// Decisión de Miguel (28/09/2026): «todo sigue igual, solo que el añadido es que
+// el analista ahora puede imprimir este anexo». El contrato PDF (template-v2,
+// contrato-aep-17-v9) no cambia ni un byte; este módulo dibuja, a demanda y
+// desde el snapshot SELLADO del contrato, el anexo del modelo «Propuesta de
+// Anexo para contrato de AEP» (septiembre 2026): datos del contrato, tabla de
+// liquidaciones parciales, liquidación final, naturaleza, prevalencia y firmas.
+//
+// El anexo no se guarda: con los datos congelados del contrato y esta versión
+// de plantilla, cada impresión produce los mismos bytes.
+import type {
+  Content,
+  ContentTable,
+  ContentText,
+  TDocumentDefinitions,
+} from "pdfmake/interfaces";
+import {
+  bloqueFirmas,
+  type ContratoPdfAssets,
+  type ContratoPdfDatos,
+  type Cotitular,
+  documentoDe,
+  fechaPartes,
+  montoVisible,
+  parrafo,
+  TIPOGRAFIA,
+  tituloClausula,
+} from "./template-v2.ts";
+
+export const ANEXO_TEMPLATE_VERSION = "anexo-cronograma-v1";
+
+export type ModalidadContrato =
+  | "mensual"
+  | "trimestral"
+  | "semestral"
+  | "anual";
+
+export interface AnexoPdfDatos {
+  contrato: {
+    numero: string;
+    capital: number;
+    moneda: "PEN" | "USD";
+    modalidad: ModalidadContrato;
+    tipoInteres: "simple" | "compuesto";
+    fechaInicio: string;
+    fechaVencimiento: string;
+  };
+  titular: ContratoPdfDatos["titular"];
+  analista: { nombreCompleto: string };
+  cotitulares: Cotitular[];
+  /** Cronograma contractual congelado con el PDF sellado. */
+  cronograma: Array<{
+    numeroCuota: number;
+    fechaProgramada: string;
+    montoProgramado: number;
+    tipo: string;
+  }>;
+}
+
+export function nombreArchivoAnexo(datos: AnexoPdfDatos): string {
+  const nombre = datos.titular.nombreCompleto
+    .normalize("NFD")
+    .replace(/[̀-ͯ]/g, "")
+    .replace(/[^A-Za-z0-9]+/g, "-")
+    .replace(/^-|-$/g, "")
+    .toUpperCase();
+  return `Anexo-${datos.contrato.numero}-${nombre}.pdf`;
+}
+
+function fechaLarga(iso: string): string {
+  const { dia, mes, anio } = fechaPartes(iso);
+  return `${dia} de ${mes} de ${anio}`;
+}
+
+function etiquetaModalidad(contrato: AnexoPdfDatos["contrato"]): string {
+  if (contrato.tipoInteres === "compuesto") {
+    return "Única, al vencimiento del contrato";
+  }
+  const etiquetas: Record<ModalidadContrato, string> = {
+    mensual: "Mensual",
+    trimestral: "Trimestral",
+    semestral: "Semestral",
+    anual: "Anual",
+  };
+  return etiquetas[contrato.modalidad];
+}
+
+type CeldaAnexo = {
+  text: string;
+  bold?: boolean;
+  alignment?: "left" | "center" | "right";
+};
+
+function tablaAnexo(
+  cabecera: string[],
+  filas: CeldaAnexo[][],
+  widths: Array<string | number>,
+): ContentTable {
+  const cuerpo: CeldaAnexo[][] = [
+    cabecera.map((text) => ({ text })),
+    ...filas,
+  ];
+  return {
+    table: {
+      headerRows: 1,
+      dontBreakRows: true,
+      widths,
+      body: cuerpo.map((fila, indice) =>
+        fila.map((celda) => ({
+          ...celda,
+          bold: indice === 0 || celda.bold === true,
+          color: indice === 0 ? "#ffffff" : "#15264d",
+          fillColor: indice === 0
+            ? "#183969"
+            : indice % 2 === 0
+            ? "#f2f5f8"
+            : "#ffffff",
+          margin: [4, 3, 4, 3],
+        }))
+      ),
+    },
+    layout: {
+      hLineColor: () => "#cbd5e1",
+      vLineColor: () => "#cbd5e1",
+      hLineWidth: () => 0.5,
+      vLineWidth: () => 0.5,
+    },
+    fontSize: TIPOGRAFIA.cuerpo,
+    margin: [0, 5, 0, 8],
+  };
+}
+
+function nombresAsociado(
+  titular: AnexoPdfDatos["titular"],
+  cotitulares: Cotitular[],
+): ContentText[] {
+  const fragmentos: ContentText[] = [
+    { text: titular.nombreCompleto, bold: true },
+  ];
+  cotitulares.forEach((cotitular, indice) => {
+    fragmentos.push(
+      { text: indice === cotitulares.length - 1 ? " y " : ", " },
+      { text: cotitular.nombreCompleto, bold: true },
+    );
+  });
+  return fragmentos;
+}
+
+type Cuota = AnexoPdfDatos["cronograma"][number];
+
+/**
+ * El anexo no puede contradecir el cronograma sellado (revisión de Codex,
+ * 28/09/2026): exige exactamente una fila `retorno`, con el capital del
+ * contrato y fechada en el vencimiento o después. Las demás filas son las
+ * liquidaciones parciales (interés simple: una `cuota` por periodo; compuesto:
+ * una `devolucion` al vencimiento). Cualquier otra forma aborta la emisión.
+ */
+export function clasificarCronograma(
+  datos: AnexoPdfDatos,
+): { parciales: Cuota[]; retorno: Cuota } {
+  const retornos = datos.cronograma.filter((cuota) => cuota.tipo === "retorno");
+  if (retornos.length !== 1) {
+    throw new TypeError(
+      "Cronograma incoherente para el anexo: se esperaba una única fila de retorno",
+    );
+  }
+  const retorno = retornos[0]!;
+  if (Math.abs(retorno.montoProgramado - datos.contrato.capital) > 0.005) {
+    throw new TypeError(
+      "Cronograma incoherente para el anexo: el retorno no coincide con la contribución",
+    );
+  }
+  if (retorno.fechaProgramada < datos.contrato.fechaVencimiento) {
+    throw new TypeError(
+      "Cronograma incoherente para el anexo: el retorno es anterior al vencimiento",
+    );
+  }
+  const parciales = datos.cronograma
+    .filter((cuota) => cuota.tipo !== "retorno")
+    .sort((a, b) =>
+      a.numeroCuota - b.numeroCuota ||
+      a.fechaProgramada.localeCompare(b.fechaProgramada)
+    );
+  return { parciales, retorno };
+}
+
+export function construirAnexoPdf(
+  datos: AnexoPdfDatos,
+  assets: ContratoPdfAssets,
+): TDocumentDefinitions {
+  const { contrato, titular, analista } = datos;
+  const cotitulares = datos.cotitulares ?? [];
+  const documento = documentoDe(titular);
+  const { parciales, retorno } = clasificarCronograma(datos);
+
+  const filasDatos: CeldaAnexo[][] = [
+    [{ text: "Número de contrato" }, { text: contrato.numero, bold: true }],
+    [{ text: "Fecha de inicio" }, {
+      text: fechaLarga(contrato.fechaInicio),
+      bold: true,
+    }],
+    [{ text: "Fecha de vencimiento" }, {
+      text: fechaLarga(contrato.fechaVencimiento),
+      bold: true,
+    }],
+    [{ text: "Monto de la contribución" }, {
+      text: montoVisible(contrato.capital, contrato.moneda),
+      bold: true,
+    }],
+    [{ text: "Modalidad de liquidaciones parciales" }, {
+      text: etiquetaModalidad(contrato),
+      bold: true,
+    }],
+    [{ text: "Analista Comercial" }, {
+      text: analista.nombreCompleto,
+      bold: true,
+    }],
+  ];
+
+  const filasParciales: CeldaAnexo[][] = parciales.length === 0
+    ? [[
+      { text: "—", alignment: "center" },
+      { text: "No se programan liquidaciones parciales" },
+      { text: "—", alignment: "center" },
+    ]]
+    : parciales.map((cuota, indice) => [
+      { text: String(indice + 1), alignment: "center" },
+      { text: fechaLarga(cuota.fechaProgramada) },
+      {
+        text: montoVisible(cuota.montoProgramado, contrato.moneda),
+        alignment: "right",
+      },
+    ]);
+
+  const contenido: Content[] = [
+    { text: "ANEXO", style: "titulo", margin: [0, 5, 0, 12] },
+    parrafo([
+      {
+        text:
+          "El presente Anexo forma parte integrante del Contrato de Asociación en Participación celebrado entre ",
+      },
+      { text: "AVANCE CORP S.A.C.", bold: true },
+      { text: ", en calidad de EL ASOCIANTE, y " },
+      ...nombresAsociado(titular, cotitulares),
+      {
+        text:
+          ", en calidad de EL ASOCIADO, y deberá ser interpretado y ejecutado conjuntamente con las disposiciones del referido contrato.",
+      },
+    ]),
+    tituloClausula("DATOS DEL CONTRATO"),
+    tablaAnexo(["Dato", "Detalle"], filasDatos, ["42%", "58%"]),
+    tituloClausula("CRONOGRAMA DE LIQUIDACIONES PARCIALES"),
+    parrafo(
+      "Durante la vigencia del contrato, EL ASOCIANTE efectuará liquidaciones parciales de resultados en las fechas que se indican a continuación:",
+    ),
+    tablaAnexo(
+      ["#", "Fecha de la liquidación", "Participación"],
+      filasParciales,
+      ["10%", "52%", "38%"],
+    ),
+    tituloClausula("LIQUIDACIÓN FINAL Y RESTITUCIÓN DE LA CONTRIBUCIÓN"),
+    parrafo(
+      "Al vencimiento del contrato, EL ASOCIANTE practicará la liquidación final correspondiente, considerando las participaciones que hubieran sido distribuidas durante la vigencia del contrato.",
+    ),
+    parrafo(
+      "Conforme a lo establecido en el numeral 5.3 del contrato, EL ASOCIANTE restituirá a EL ASOCIADO el saldo de la contribución determinado conforme a la liquidación final dentro de un plazo máximo de siete (7) días hábiles contados desde el vencimiento contractual.",
+    ),
+    tablaAnexo(
+      ["Concepto", "Fecha", "Monto"],
+      [[
+        { text: "Liquidación final y restitución de la contribución" },
+        { text: fechaLarga(retorno.fechaProgramada) },
+        {
+          text: montoVisible(retorno.montoProgramado, contrato.moneda),
+          alignment: "right",
+        },
+      ]],
+      ["46%", "32%", "22%"],
+    ),
+    tituloClausula("NATURALEZA DEL CRONOGRAMA"),
+    parrafo(
+      "El presente Anexo tiene por finalidad facilitar a EL ASOCIADO el seguimiento de las fechas en las que se practicarán liquidaciones parciales durante la vigencia del contrato, sin modificar la naturaleza asociativa del mismo ni sustituir las reglas de determinación de utilidades previstas en sus disposiciones.",
+    ),
+    tituloClausula("PREVALENCIA DEL CONTRATO"),
+    parrafo(
+      "En todo aquello que no se encuentre expresamente regulado en el presente Anexo, serán aplicables las disposiciones del Contrato de Asociación en Participación.",
+    ),
+    parrafo(
+      "En caso de discrepancia entre el presente Anexo y el contrato principal, prevalecerán las disposiciones de este último, especialmente aquellas referidas a la naturaleza asociativa de la relación, determinación de utilidades, liquidaciones parciales, liquidación final y restitución de la contribución.",
+    ),
+    parrafo(
+      "Las partes suscriben el presente Anexo en señal de conformidad, en la misma fecha de celebración del Contrato de Asociación en Participación.",
+      { margin: [0, 6, 0, 4] },
+    ),
+    bloqueFirmas(titular, documento, cotitulares),
+  ];
+
+  // Lienzo, membrete, cabecera, pie y estilos: espejo exacto del contrato
+  // (template-v2), para que el anexo se vea como una hoja más del mismo
+  // documento.
+  return {
+    info: {
+      title: `Anexo ${contrato.numero}`,
+      author: "Avance Corp S.A.C.",
+      subject: "Anexo de cronograma de liquidaciones parciales",
+      keywords: `anexo,cronograma,${contrato.numero},avance corp`,
+    },
+    pageSize: "A4",
+    pageMargins: [66, 126, 58, 94],
+    images: {
+      fondoContrato: assets.fondo,
+      firmaAsociante: assets.firmaAsociante,
+    },
+    background: () => ({
+      image: "fondoContrato",
+      width: 595.28,
+      height: 841.89,
+      absolutePosition: { x: 0, y: 0 },
+    }),
+    header: () => ({
+      text: contrato.numero,
+      alignment: "right",
+      color: "#183969",
+      bold: true,
+      fontSize: TIPOGRAFIA.cabecera,
+      margin: [0, 82, 58, 0],
+    }),
+    footer: (pagina, total) => ({
+      text: `${pagina} / ${total}`,
+      alignment: "right",
+      color: "#64748b",
+      fontSize: TIPOGRAFIA.pie,
+      margin: [0, 0, 58, 52],
+    }),
+    content: contenido,
+    defaultStyle: {
+      font: "Roboto",
+      fontSize: TIPOGRAFIA.cuerpo,
+      color: "#17233b",
+      lineHeight: 1.16,
+    },
+    styles: {
+      titulo: {
+        fontSize: TIPOGRAFIA.titulo,
+        bold: true,
+        alignment: "center",
+        color: "#183969",
+      },
+      clausula: {
+        fontSize: TIPOGRAFIA.clausula,
+        bold: true,
+        color: "#183969",
+      },
+      parrafo: {
+        alignment: "justify",
+        margin: [0, 0, 0, 4],
+      },
+    },
+  };
+}
diff --git a/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/handler.test.ts b/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/handler.test.ts
index 11809375..8a9544dd 100644
--- a/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/handler.test.ts
+++ b/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/handler.test.ts
@@ -1,5 +1,6 @@
 import { deepStrictEqual as assertEquals } from "node:assert";
 import {
+  ANEXO_PDF_TEMPLATE_VERSION,
   type BackendResult,
   CONTRATO_PDF_MAX_BYTES,
   CONTRATO_PDF_TEMPLATE_VERSION,
@@ -123,6 +124,7 @@ type FakeOptions = {
   downloadError?: { code?: string; message?: string; statusCode?: number };
   downloads?: Array<Blob | null>;
   render?: RenderResult | Error;
+  renderAnexo?: (RenderResult & { nombreArchivo: string }) | Error;
 };
 
 function fake(opciones: FakeOptions = {}) {
@@ -163,6 +165,20 @@ function fake(opciones: FakeOptions = {}) {
         },
       );
     },
+    renderizarAnexo: () => {
+      calls.push("render-anexo");
+      if (opciones.renderAnexo instanceof Error) {
+        return Promise.reject(opciones.renderAnexo);
+      }
+      return Promise.resolve(
+        opciones.renderAnexo ?? {
+          blob: new Blob(["%PDF-1.7\nanexo"], { type: "application/pdf" }),
+          sha256: "a".repeat(64),
+          bytes: 14,
+          nombreArchivo: "Anexo-2026-01-000777-CLIENTE-PRUEBA.pdf",
+        },
+      );
+    },
     storage: {
       subir: (_path, _blob) => {
         calls.push("upload");
@@ -1227,3 +1243,115 @@ Deno.test("delete anterior conserva su formato de respuesta y también archiva",
   });
   assertEquals(calls.join("|"), "auth|admin:contrato_eliminar_auditado");
 });
+
+// ── Acción «anexo»: documento aparte desde el snapshot sellado ─────────────
+
+const DATOS_ANEXO = {
+  contrato_id: CONTRATO_ID,
+  revision: 1,
+  template_version: CONTRATO_PDF_TEMPLATE_VERSION,
+  generado_en: "2026-08-17T20:00:00Z",
+  sha256: "b".repeat(64),
+  snapshot: { snapshotVersion: 2 },
+};
+
+Deno.test("anexo entrega el PDF en base64 con su hash, sin tocar Storage ni reservar", async () => {
+  const { deps, calls } = fake({
+    admin: [{ data: DATOS_ANEXO, error: null }],
+  });
+  const res = await crearHandlerContratoPdfV2(deps)(
+    request({ action: "anexo", contratoId: CONTRATO_ID }),
+  );
+  igual(res.status, 200, "anexo generado");
+  const json = await res.json();
+  igual(json.anexo.template, ANEXO_PDF_TEMPLATE_VERSION, "versión del anexo");
+  igual(json.anexo.contrato_revision, 1, "revisión sellada usada");
+  igual(json.anexo.sha256, "a".repeat(64), "hash del render");
+  igual(json.anexo.bytes, 14, "bytes del render");
+  igual(
+    json.anexo.nombre_archivo,
+    "Anexo-2026-01-000777-CLIENTE-PRUEBA.pdf",
+    "nombre saneado",
+  );
+  igual(atob(json.anexo.pdf_base64), "%PDF-1.7\nanexo", "bytes en base64");
+  igual(
+    calls.join(","),
+    "auth,admin:contrato_pdf_anexo_snapshot,render-anexo",
+    "solo lee el snapshot sellado y renderiza: ni reserva, ni sube, ni firma",
+  );
+});
+
+Deno.test("anexo sin PDF sellado y sin snapshot apto responden 409 con su código", async () => {
+  for (const hint of ["ANEXO_SIN_PDF_SELLADO", "ANEXO_SIN_SNAPSHOT"]) {
+    const { deps, calls } = fake({
+      admin: [{
+        data: null,
+        error: { code: "P0002", message: "sin pdf", hint },
+      }],
+    });
+    const res = await crearHandlerContratoPdfV2(deps)(
+      request({ action: "anexo", contratoId: CONTRATO_ID }),
+    );
+    igual(res.status, 409, `${hint}: conflicto de negocio`);
+    const json = await res.json();
+    igual(json.codigo, hint, `${hint}: código expuesto`);
+    assert(!calls.includes("render-anexo"), `${hint}: no renderiza`);
+  }
+});
+
+Deno.test("anexo fuera de cartera responde 403 sin revelar existencia", async () => {
+  const { deps } = fake({
+    admin: [{
+      data: null,
+      error: {
+        code: "42501",
+        message: "Contrato no encontrado o fuera de tu cartera",
+      },
+    }],
+  });
+  const res = await crearHandlerContratoPdfV2(deps)(
+    request({ action: "anexo", contratoId: CONTRATO_ID }),
+  );
+  igual(res.status, 403, "permiso denegado");
+  const json = await res.json();
+  igual(json.codigo, "ANEXO_DATOS", "código genérico");
+  igual(
+    json.error,
+    "Contrato no encontrado o fuera de tu cartera",
+    "mismo mensaje que el PDF",
+  );
+});
+
+Deno.test("anexo con cronograma incoherente responde 409 y con datos inválidos 502", async () => {
+  const incoherente = fake({
+    admin: [{ data: DATOS_ANEXO, error: null }],
+    renderAnexo: new TypeError("Cronograma incoherente para el anexo"),
+  });
+  const res1 = await crearHandlerContratoPdfV2(incoherente.deps)(
+    request({ action: "anexo", contratoId: CONTRATO_ID }),
+  );
+  igual(res1.status, 409, "cronograma incoherente");
+  igual((await res1.json()).codigo, "ANEXO_CRONOGRAMA_INCOHERENTE", "código");
+
+  const invalidos = fake({
+    admin: [{ data: { ...DATOS_ANEXO, extra: true }, error: null }],
+  });
+  const res2 = await crearHandlerContratoPdfV2(invalidos.deps)(
+    request({ action: "anexo", contratoId: CONTRATO_ID }),
+  );
+  igual(res2.status, 502, "clave inesperada en los datos sellados");
+  igual((await res2.json()).codigo, "ANEXO_DATOS_INVALIDOS", "código");
+  assert(
+    !invalidos.calls.includes("render-anexo"),
+    "no renderiza datos inválidos",
+  );
+});
+
+Deno.test("anexo exige sesión como el resto de acciones", async () => {
+  const { deps, calls } = fake({ sesion: null });
+  const res = await crearHandlerContratoPdfV2(deps)(
+    request({ action: "anexo", contratoId: CONTRATO_ID }),
+  );
+  igual(res.status, 401, "sin sesión");
+  assert(!calls.some((c) => c.startsWith("admin:")), "no toca el backend");
+});
diff --git a/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/handler.ts b/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/handler.ts
index 84d5180f..6dbd089e 100644
--- a/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/handler.ts
+++ b/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/handler.ts
@@ -1,3 +1,5 @@
+import { Buffer } from "node:buffer";
+
 export const CONTRATO_PDF_BUCKET = "contratos-generados";
 export const CONTRATO_DOCUMENTOS_BUCKET = "documentos";
 export const CONTRATO_PDF_TEMPLATE_VERSION = "contrato-aep-17-v9";
@@ -7,6 +9,8 @@ export const CONTRATO_PDF_MAX_REQUEST_BYTES = 2 * 1024;
 export type BackendError = {
   code?: string;
   message?: string;
+  /** `hint` de PostgREST: las funciones SQL lo usan como código de negocio. */
+  hint?: string;
   statusCode?: number;
 };
 export type BackendResult = { data: unknown; error: BackendError | null };
@@ -41,6 +45,11 @@ export type RenderResult = {
   bytes: number;
 };
 
+export type RenderAnexoResult = RenderResult & { nombreArchivo: string };
+
+/** Versión de la plantilla del anexo imprimible (documento aparte del contrato). */
+export const ANEXO_PDF_TEMPLATE_VERSION = "anexo-cronograma-v1";
+
 export interface DependenciasContratoPdfV2 {
   crearActor(token: string): ActorContratoPdfV2;
   rpcAdmin(
@@ -48,6 +57,14 @@ export interface DependenciasContratoPdfV2 {
     argumentos: Record<string, unknown>,
   ): Promise<BackendResult>;
   renderizar(snapshot: unknown, renderizadoEn: string): Promise<RenderResult>;
+  /**
+   * Anexo de cronograma: se dibuja a demanda desde el snapshot SELLADO del
+   * contrato y no se guarda (decisión de Miguel, 28/09/2026).
+   */
+  renderizarAnexo(
+    snapshot: unknown,
+    generadoEn: string,
+  ): Promise<RenderAnexoResult>;
   storage: StorageContratoPdfV2;
   origenesAdicionales?: readonly string[];
 }
@@ -548,6 +565,126 @@ function esConflictoObjeto(error: BackendError): boolean {
 }
 
 export function crearHandlerContratoPdfV2(deps: DependenciasContratoPdfV2) {
+  const CODIGOS_ANEXO = new Set([
+    "ANEXO_SIN_PDF_SELLADO",
+    "ANEXO_SIN_SNAPSHOT",
+  ]);
+
+  function datosAnexoValidos(valor: unknown): valor is {
+    contrato_id: string;
+    revision: number;
+    template_version: string;
+    generado_en: string;
+    sha256: string;
+    snapshot: Record<string, unknown>;
+  } {
+    return esObjeto(valor) &&
+      clavesExactas(valor, [
+        "contrato_id",
+        "revision",
+        "template_version",
+        "generado_en",
+        "sha256",
+        "snapshot",
+      ]) &&
+      uuidCanonico(valor.contrato_id) &&
+      Number.isInteger(valor.revision) && (valor.revision as number) >= 1 &&
+      // La versión del CONTRATO sellado solo se transporta: el anexo no la
+      // dibuja, y el CHECK de la base ya la acota. No se exige que esta edge
+      // sepa leerla (un sellado v3/v4 seguiría dando su anexo).
+      typeof valor.template_version === "string" &&
+      valor.template_version.length >= 1 &&
+      valor.template_version.length <= 80 &&
+      !tieneControl(valor.template_version) &&
+      fechaIso(valor.generado_en) &&
+      typeof valor.sha256 === "string" && /^[0-9a-f]{64}$/.test(valor.sha256) &&
+      esObjeto(valor.snapshot);
+  }
+
+  /**
+   * Anexo de cronograma: documento aparte, a demanda, desde el snapshot SELLADO.
+   * La RPC deja el asiento de bitácora (quién, cuándo, contrato, revisión,
+   * plantilla) y aplica la misma regla de lectura que el PDF. No hay Storage:
+   * los bytes viajan en JSON (base64) para que `functions.invoke` los entregue
+   * sin depender de cabeceras binarias ni de CORS expuesto.
+   */
+  async function anexo(
+    origin: string | null,
+    origenes: ReadonlySet<string>,
+    contratoId: string,
+    actorId: string,
+  ): Promise<Response> {
+    const resultado = await deps.rpcAdmin("contrato_pdf_anexo_snapshot", {
+      p_contrato_id: contratoId,
+      p_actor_id: actorId,
+      p_template: ANEXO_PDF_TEMPLATE_VERSION,
+    });
+    if (resultado.error) {
+      const hint = resultado.error.hint ?? "";
+      if (CODIGOS_ANEXO.has(hint)) {
+        return json(origin, origenes, {
+          error: hint === "ANEXO_SIN_PDF_SELLADO"
+            ? "El contrato todavía no tiene su PDF sellado; genera primero el contrato PDF"
+            : "El contrato no tiene datos congelados aptos para el anexo",
+          codigo: hint,
+        }, 409);
+      }
+      const status = statusErrorBackend(resultado.error);
+      return json(origin, origenes, {
+        error: status === 403
+          ? "Contrato no encontrado o fuera de tu cartera"
+          : ["55P03", "40P01"].includes(resultado.error.code ?? "")
+          ? "El contrato está siendo actualizado. Espera unos segundos y reintenta."
+          : "No se pudo preparar el anexo",
+        codigo: "ANEXO_DATOS",
+      }, status === 404 ? 409 : status);
+    }
+    if (!datosAnexoValidos(resultado.data)) {
+      return json(origin, origenes, {
+        error: "Datos del contrato sellado inválidos",
+        codigo: "ANEXO_DATOS_INVALIDOS",
+      }, 502);
+    }
+    let render: RenderAnexoResult;
+    try {
+      render = await deps.renderizarAnexo(
+        resultado.data.snapshot,
+        resultado.data.generado_en,
+      );
+    } catch (error) {
+      const incoherente = error instanceof TypeError;
+      return json(origin, origenes, {
+        error: incoherente
+          ? "El cronograma sellado no permite emitir el anexo"
+          : "No se pudo generar el anexo",
+        codigo: incoherente ? "ANEXO_CRONOGRAMA_INCOHERENTE" : "ANEXO_RENDER",
+      }, incoherente ? 409 : 503);
+    }
+    if (
+      render.bytes !== render.blob.size || render.bytes <= 5 ||
+      render.bytes > CONTRATO_PDF_MAX_BYTES ||
+      !nombreValido(render.nombreArchivo)
+    ) {
+      return json(origin, origenes, {
+        error: "No se pudo generar el anexo",
+        codigo: "ANEXO_RENDER",
+      }, 503);
+    }
+    const bytes = new Uint8Array(await render.blob.arrayBuffer());
+    return json(origin, origenes, {
+      anexo: {
+        contrato_id: contratoId,
+        contrato_revision: resultado.data.revision,
+        contrato_template_version: resultado.data.template_version,
+        template: ANEXO_PDF_TEMPLATE_VERSION,
+        nombre_archivo: render.nombreArchivo,
+        sha256: render.sha256,
+        bytes: render.bytes,
+        pdf_base64: Buffer.from(bytes).toString("base64"),
+      },
+    });
+  }
+
   const origenes = new Set(ORIGENES_PRODUCCION);
   for (const origen of deps.origenesAdicionales ?? []) origenes.add(origen);
 
@@ -594,7 +731,8 @@ export function crearHandlerContratoPdfV2(deps: DependenciasContratoPdfV2) {
     if (
       !esObjeto(cuerpo) || !clavesExactas(cuerpo, ["action", "contratoId"]) ||
       (cuerpo.action !== "ensure" && cuerpo.action !== "status" &&
-        cuerpo.action !== "delete" && cuerpo.action !== "delete-audited") ||
+        cuerpo.action !== "delete" && cuerpo.action !== "delete-audited" &&
+        cuerpo.action !== "anexo") ||
       !uuidCanonico(cuerpo.contratoId)
     ) {
       return json(
@@ -733,6 +871,10 @@ export function crearHandlerContratoPdfV2(deps: DependenciasContratoPdfV2) {
       });
     };
 
+    if (cuerpo.action === "anexo") {
+      return await anexo(origin, origenes, contratoId, sesion.id);
+    }
+
     if (cuerpo.action === "status") {
       const result = respuestaBackend(
         await actor.rpc("contrato_pdf_estado_fn", {
diff --git a/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/index.ts b/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/index.ts
index 05ac5eb1..06eeead2 100644
--- a/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/index.ts
+++ b/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/index.ts
@@ -5,7 +5,7 @@ import {
   type BackendResult,
   crearHandlerContratoPdfV2,
 } from "./handler.ts";
-import { renderizarContratoPdfV2 } from "./renderer.ts";
+import { renderizarAnexoPdfV1, renderizarContratoPdfV2 } from "./renderer.ts";
 import { crearStorageContratoPdfV2, errorBackend } from "./storage.ts";
 
 function env(nombre: string, alternativa?: string): string {
@@ -117,6 +117,7 @@ const handler = crearHandlerContratoPdfV2({
   crearActor,
   origenesAdicionales,
   renderizar: renderizarContratoPdfV2,
+  renderizarAnexo: renderizarAnexoPdfV1,
   async rpcAdmin(nombre, argumentos) {
     const { data, error } = await admin.schema("crm").rpc(nombre, argumentos);
     return resultado(data, error);
diff --git a/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/renderer.test.ts b/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/renderer.test.ts
index 7c3c9bb8..144ede27 100644
--- a/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/renderer.test.ts
+++ b/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/renderer.test.ts
@@ -1,13 +1,19 @@
 import {
+  ANEXO_PDF_RENDERER_VERSION,
   CONTRATO_PDF_RENDERER_VERSION,
   PDFMAKE_VENDOR_SHA256,
+  renderizarAnexoPdfV1,
   renderizarContratoPdfV2,
   validarSnapshotContratoV2,
   verificarAssetsContratoPdfV2,
   VFS_VENDOR_SHA256,
 } from "./renderer.ts";
-import { CONTRATO_PDF_TEMPLATE_VERSION } from "./handler.ts";
+import {
+  ANEXO_PDF_TEMPLATE_VERSION,
+  CONTRATO_PDF_TEMPLATE_VERSION,
+} from "./handler.ts";
 import { construirContratoPdf } from "./template-v2.ts";
+import { clasificarCronograma, construirAnexoPdf } from "./anexo-v1.ts";
 
 function assert(condicion: unknown, mensaje: string): asserts condicion {
   if (!condicion) throw new Error(mensaje);
@@ -564,3 +570,282 @@ Deno.test("template v9 hace caber cinco co-titulares (tope del CRM) en la hoja d
     `cinco co-titulares añaden a lo sumo una hoja (${paginasSin} → ${paginasCon})`,
   );
 });
+
+// ── Anexo de cronograma (documento aparte, anexo-cronograma-v1) ─────────────
+
+function cuota(
+  numero: number,
+  fecha: string,
+  monto: number,
+  tipo: string,
+) {
+  return {
+    id: `55555555-5555-4555-8555-5555555555${String(numero).padStart(2, "0")}`,
+    numeroCuota: numero,
+    fechaProgramada: fecha,
+    montoProgramado: monto,
+    tipo,
+  };
+}
+
+/** 12 cuotas mensuales de S/ 225 + retorno del capital 7 días tras el vencimiento. */
+const CRONOGRAMA_SIMPLE = [
+  ...[
+    "2026-09-17",
+    "2026-10-17",
+    "2026-11-17",
+    "2026-12-17",
+    "2027-01-17",
+    "2027-02-17",
+    "2027-03-17",
+    "2027-04-17",
+    "2027-05-17",
+    "2027-06-17",
+    "2027-07-17",
+    "2027-08-17",
+  ].map((fecha, indice) => cuota(indice + 1, fecha, 225, "cuota")),
+  cuota(13, "2027-08-24", 15000, "retorno"),
+];
+
+const SNAPSHOT_ANEXO = { ...SNAPSHOT, cronograma: CRONOGRAMA_SIMPLE };
+const TITULAR_ANEXO = { ...SNAPSHOT.titular, tipoDocumento: "DNI" as const };
+
+const ASSETS_ANEXO = {
+  fondo: "data:image/png;base64,fondo",
+  firmaAsociante: "data:image/png;base64,firma-kirk",
+};
+
+function textos(nodo: unknown, acumulado: string[] = []): string[] {
+  if (Array.isArray(nodo)) {
+    for (const hijo of nodo) textos(hijo, acumulado);
+  } else if (nodo && typeof nodo === "object") {
+    const objeto = nodo as Record<string, unknown>;
+    if (typeof objeto.text === "string") acumulado.push(objeto.text);
+    for (const clave of ["text", "stack", "columns", "table", "body"]) {
+      if (clave in objeto) textos(objeto[clave], acumulado);
+    }
+  }
+  return acumulado;
+}
+
+Deno.test("anexo v1 produce dos PDFs byte-idénticos con la fecha fija del sellado", async () => {
+  igual(
+    ANEXO_PDF_RENDERER_VERSION,
+    ANEXO_PDF_TEMPLATE_VERSION,
+    "renderer del anexo y handler versionados juntos",
+  );
+  const fecha = "2026-08-17T20:00:00.000Z";
+  const primero = await renderizarAnexoPdfV1(SNAPSHOT_ANEXO, fecha);
+  const segundo = await renderizarAnexoPdfV1(SNAPSHOT_ANEXO, fecha);
+  igual(primero.bytes, primero.blob.size, "tamaño medido");
+  igual(primero.sha256, segundo.sha256, "hash determinista");
+  igual(primero.bytes, segundo.bytes, "tamaño determinista");
+  igual(
+    primero.sha256,
+    "9639f4a48294c631434db945e2ae60057a8fd753b69389b1392ece00b71bc3dc",
+    "golden byte a byte del anexo v1 (12 cuotas, sin co-titulares)",
+  );
+  igual(primero.bytes, 165463, "tamaño golden del anexo v1");
+  igual(
+    primero.nombreArchivo,
+    "Anexo-2026-01-000777-CLIENTE-PRUEBA.pdf",
+    "nombre del archivo del anexo",
+  );
+  const a = new Uint8Array(await primero.blob.arrayBuffer());
+  igual(new TextDecoder().decode(a.slice(0, 5)), "%PDF-", "cabecera PDF");
+});
+
+Deno.test("anexo v1 no altera el contrato v9: mismo golden con o sin anexo cargado", async () => {
+  const contrato = await renderizarContratoPdfV2(
+    SNAPSHOT,
+    "2026-08-17T20:00:00.000Z",
+  );
+  igual(
+    contrato.sha256,
+    "6ffb935d939e4ba7f4c5822835d81cf6bac0a8b04bb1b011a1b629a9b1ffe1d8",
+    "el contrato sigue siendo byte a byte la v9",
+  );
+  igual(contrato.bytes, 218672, "tamaño golden v9 intacto");
+});
+
+Deno.test("anexo v1 imprime las parciales del cronograma sellado y el retorno como liquidación final", () => {
+  const definicion = construirAnexoPdf(
+    {
+      contrato: {
+        numero: "2026-01-000777",
+        capital: 15000,
+        moneda: "PEN",
+        modalidad: "mensual",
+        tipoInteres: "simple",
+        fechaInicio: "2026-08-17",
+        fechaVencimiento: "2027-08-17",
+      },
+      titular: TITULAR_ANEXO,
+      analista: { nombreCompleto: "ANALISTA PRUEBA" },
+      cotitulares: [{
+        nombreCompleto: "COTITULAR PRUEBA UNO",
+        tipoDocumento: "DNI",
+        documento: "40000001",
+      }],
+      cronograma: CRONOGRAMA_SIMPLE,
+    },
+    ASSETS_ANEXO,
+  );
+  const plano = textos(definicion.content).join("\n");
+  assert(plano.startsWith("ANEXO\n"), "título ANEXO");
+  assert(
+    plano.includes("CLIENTE PRUEBA\n y \nCOTITULAR PRUEBA UNO"),
+    "nombra al titular y al co-titular en la introducción",
+  );
+  assert(
+    plano.includes("17 de septiembre de 2026"),
+    "primera liquidación parcial",
+  );
+  assert(
+    plano.includes("17 de agosto de 2027"),
+    "última parcial (y vencimiento)",
+  );
+  igual(
+    (plano.match(/S\/ 225\.00/g) ?? []).length,
+    12,
+    "doce participaciones de S/ 225.00",
+  );
+  assert(
+    plano.includes("24 de agosto de 2027"),
+    "la liquidación final usa la fila retorno",
+  );
+  igual(
+    (plano.match(/S\/ 15,000\.00/g) ?? []).length,
+    2,
+    "la contribución aparece en datos y en la restitución",
+  );
+  assert(plano.includes("Mensual"), "modalidad legible");
+  assert(
+    plano.includes("numeral 5.3 del contrato"),
+    "remite al 5.3 del contrato",
+  );
+  assert(
+    plano.includes("EL ASOCIADO") && plano.includes("EL ASOCIANTE") &&
+      plano.includes("RUC N° 20611392088"),
+    "bloque de firmas de las dos partes",
+  );
+  igual(
+    (plano.match(/EL ASOCIADO$/gm) ?? []).length,
+    2,
+    "firman el titular y el co-titular",
+  );
+});
+
+Deno.test("anexo v1: interés compuesto lista la única liquidación al vencimiento", () => {
+  const definicion = construirAnexoPdf(
+    {
+      contrato: {
+        numero: "2026-01-000778",
+        capital: 15000,
+        moneda: "USD",
+        modalidad: "mensual",
+        tipoInteres: "compuesto",
+        fechaInicio: "2026-08-17",
+        fechaVencimiento: "2027-08-17",
+      },
+      titular: TITULAR_ANEXO,
+      analista: { nombreCompleto: "ANALISTA PRUEBA" },
+      cotitulares: [],
+      cronograma: [
+        cuota(1, "2027-08-17", 2700, "devolucion"),
+        cuota(2, "2027-08-24", 15000, "retorno"),
+      ],
+    },
+    ASSETS_ANEXO,
+  );
+  const plano = textos(definicion.content).join("\n");
+  assert(
+    plano.includes("Única, al vencimiento del contrato"),
+    "modalidad del compuesto",
+  );
+  assert(
+    plano.includes("US$ 2,700.00"),
+    "participación acumulada al vencimiento",
+  );
+  assert(!plano.includes("No se programan"), "sí hay una liquidación listada");
+});
+
+Deno.test("anexo v1 rechaza cronogramas que contradicen el contrato sellado", () => {
+  const base = {
+    contrato: {
+      numero: "2026-01-000777",
+      capital: 15000,
+      moneda: "PEN" as const,
+      modalidad: "mensual" as const,
+      tipoInteres: "simple" as const,
+      fechaInicio: "2026-08-17",
+      fechaVencimiento: "2027-08-17",
+    },
+    titular: TITULAR_ANEXO,
+    analista: { nombreCompleto: "ANALISTA PRUEBA" },
+    cotitulares: [],
+  };
+  const casos: Array<[string, typeof CRONOGRAMA_SIMPLE]> = [
+    ["sin retorno", CRONOGRAMA_SIMPLE.slice(0, 12)],
+    ["dos retornos", [
+      ...CRONOGRAMA_SIMPLE,
+      cuota(14, "2027-08-25", 15000, "retorno"),
+    ]],
+    ["retorno distinto del capital", [
+      ...CRONOGRAMA_SIMPLE.slice(0, 12),
+      cuota(13, "2027-08-24", 14999.99, "retorno"),
+    ]],
+    ["retorno antes del vencimiento", [
+      ...CRONOGRAMA_SIMPLE.slice(0, 12),
+      cuota(13, "2027-08-16", 15000, "retorno"),
+    ]],
+    ["la forma vieja del fixture (capital_interes)", SNAPSHOT.cronograma],
+  ];
+  for (const [nombre, cronograma] of casos) {
+    let error: unknown = null;
+    try {
+      clasificarCronograma({ ...base, cronograma });
+    } catch (e) {
+      error = e;
+    }
+    assert(error instanceof TypeError, `${nombre}: aborta con TypeError`);
+  }
+  const { parciales, retorno } = clasificarCronograma({
+    ...base,
+    cronograma: CRONOGRAMA_SIMPLE,
+  });
+  igual(parciales.length, 12, "doce parciales");
+  igual(retorno.fechaProgramada, "2027-08-24", "retorno identificado");
+});
+
+Deno.test("anexo v1 con 60 cuotas cabe en varias hojas sin romper filas", async () => {
+  const cuotas = Array.from({ length: 60 }, (_, indice) => {
+    const mes = indice + 1;
+    const anio = 2026 + Math.floor((7 + mes) / 12);
+    const mesCal = ((7 + mes) % 12) + 1;
+    return cuota(
+      mes,
+      `${anio}-${String(mesCal).padStart(2, "0")}-17`,
+      225,
+      "cuota",
+    );
+  });
+  const snapshot = {
+    ...SNAPSHOT,
+    contrato: { ...SNAPSHOT.contrato, fechaVencimiento: "2031-08-17" },
+    cronograma: [...cuotas, cuota(61, "2031-08-24", 15000, "retorno")],
+  };
+  const render = await renderizarAnexoPdfV1(
+    snapshot,
+    "2026-08-17T20:00:00.000Z",
+  );
+  assert(render.bytes > 0 && render.bytes < 400_000, "tamaño razonable");
+  const texto = new TextDecoder("latin1").decode(
+    new Uint8Array(await render.blob.arrayBuffer()),
+  );
+  igual(
+    (texto.match(/\/Type \/Page[^s]/g) ?? []).length,
+    4,
+    "cuatro hojas (60 cuotas + firmas)",
+  );
+});
diff --git a/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/renderer.ts b/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/renderer.ts
index 722e621c..cc0e1931 100644
--- a/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/renderer.ts
+++ b/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/renderer.ts
@@ -10,10 +10,18 @@ import {
   FONDO_SHA256,
 } from "./assets-v2.ts";
 import {
+  ANEXO_PDF_TEMPLATE_VERSION,
   CONTRATO_PDF_MAX_BYTES,
   CONTRATO_PDF_TEMPLATE_VERSION,
+  type RenderAnexoResult,
   type RenderResult,
 } from "./handler.ts";
+import {
+  ANEXO_TEMPLATE_VERSION,
+  type AnexoPdfDatos,
+  construirAnexoPdf,
+  nombreArchivoAnexo,
+} from "./anexo-v1.ts";
 import {
   construirContratoPdf,
   type ContratoPdfDatos,
@@ -21,6 +29,7 @@ import {
 } from "./template-v2.ts";
 
 export const CONTRATO_PDF_RENDERER_VERSION = CONTRATO_PDF_TEMPLATE_VERSION;
+export const ANEXO_PDF_RENDERER_VERSION = ANEXO_TEMPLATE_VERSION;
 export const CONTRATO_PDF_VFS_VERSION = "pdfmake-0.2.20-roboto-vfs-1";
 export const PDFMAKE_UPSTREAM_SHA256 =
   "bfd0e78ae7fd12ecf4ab0b4aae4b5eb3f97865b0ed5932f1d9e947fc91f54930";
@@ -553,3 +562,80 @@ export async function renderizarContratoPdfV2(
     bytes: blob.size,
   };
 }
+
+function datosAnexo(snapshot: SnapshotContratoV2): AnexoPdfDatos {
+  return {
+    contrato: {
+      numero: snapshot.contrato.numero,
+      capital: snapshot.contrato.capital,
+      moneda: snapshot.contrato.moneda,
+      modalidad: snapshot.contrato.modalidad,
+      tipoInteres: snapshot.contrato.tipoInteres,
+      fechaInicio: snapshot.contrato.fechaInicio,
+      fechaVencimiento: snapshot.contrato.fechaVencimiento,
+    },
+    titular: {
+      nombreCompleto: snapshot.titular.nombreCompleto,
+      tipoDocumento: snapshot.titular.tipoDocumento,
+      documento: snapshot.titular.documento,
+      domicilio: snapshot.titular.domicilio,
+      correo: snapshot.titular.correo,
+    },
+    analista: { nombreCompleto: snapshot.analista.nombreCompleto },
+    cotitulares: snapshot.cotitulares.map((cotitular) => ({
+      nombreCompleto: cotitular.nombreCompleto,
+      tipoDocumento: cotitular.tipoDocumento,
+      documento: cotitular.documento,
+    })),
+    cronograma: snapshot.cronograma.map((cuota) => ({
+      numeroCuota: cuota.numeroCuota,
+      fechaProgramada: cuota.fechaProgramada,
+      montoProgramado: cuota.montoProgramado,
+      tipo: cuota.tipo,
+    })),
+  };
+}
+
+/**
+ * Anexo de cronograma (documento aparte). Mismo snapshot sellado, mismos
+ * recursos verificados y misma fecha fija (la del sellado del contrato) ⇒
+ * mismos bytes en cada impresión para esta versión desplegada.
+ */
+export async function renderizarAnexoPdfV1(
+  snapshotRaw: unknown,
+  generadoEn: string,
+): Promise<RenderAnexoResult> {
+  if (ANEXO_PDF_RENDERER_VERSION !== ANEXO_PDF_TEMPLATE_VERSION) {
+    throw new Error("Versión del anexo desalineada entre handler y plantilla");
+  }
+  const snapshot = validarSnapshotContratoV2(snapshotRaw);
+  const fechaFija = fechaRender(generadoEn);
+  await verificarRecursos();
+  const datos = datosAnexo(snapshot);
+  const definicion = construirAnexoPdf(datos, {
+    fondo: FONDO_DATA_URL,
+    firmaAsociante: FIRMA_DATA_URL,
+  });
+  definicion.info = {
+    ...definicion.info,
+    creator: `crm-contrato-pdf-v2/${ANEXO_PDF_RENDERER_VERSION}`,
+    producer:
+      `pdfmake/0.2.20 ${CONTRATO_PDF_VFS_VERSION} ${CONTRATO_PDF_ASSETS_VERSION}`,
+    creationDate: fechaFija,
+    modDate: fechaFija,
+  };
+  const blob = await documentoComoBlob(definicion);
+  if (blob.size <= 5 || blob.size > CONTRATO_PDF_MAX_BYTES) {
+    throw new Error("El renderer del anexo produjo un tamaño inválido");
+  }
+  const bytes = new Uint8Array(await blob.arrayBuffer());
+  if (new TextDecoder().decode(bytes.slice(0, 5)) !== "%PDF-") {
+    throw new Error("El renderer del anexo no produjo un PDF");
+  }
+  return {
+    blob,
+    bytes: blob.size,
+    sha256: await sha256Bytes(bytes),
+    nombreArchivo: nombreArchivoAnexo(datos),
+  };
+}
diff --git a/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/storage.ts b/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/storage.ts
index c877b959..0f0416d4 100644
--- a/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/storage.ts
+++ b/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/storage.ts
@@ -13,6 +13,7 @@ export function errorBackend(error: unknown): BackendError | null {
   const valor = error as {
     code?: unknown;
     message?: unknown;
+    hint?: unknown;
     statusCode?: unknown;
     status?: unknown;
   };
@@ -35,6 +36,7 @@ export function errorBackend(error: unknown): BackendError | null {
   return {
     ...(code !== undefined ? { code } : {}),
     ...(typeof valor.message === "string" ? { message: valor.message } : {}),
+    ...(typeof valor.hint === "string" ? { hint: valor.hint } : {}),
     ...(statusCode !== undefined ? { statusCode } : {}),
   };
 }
diff --git a/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/template-v2.ts b/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/template-v2.ts
index d2c4a617..ceb54fb3 100644
--- a/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/template-v2.ts
+++ b/CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/template-v2.ts
@@ -107,7 +107,7 @@ const CENTENAS = [
 // Escala tipográfica del contrato. El cuerpo subió de 8.6 a 10 pt para que el
 // cliente lo lea sin esfuerzo; el resto acompaña en proporción y las firmas
 // quedan al mismo tamaño en las dos columnas (antes 8 pt vs 10.5 pt).
-const TIPOGRAFIA = {
+export const TIPOGRAFIA = {
   cuerpo: 9.6,
   clausula: 10.4,
   titulo: 15,
@@ -160,7 +160,7 @@ function montoEnLetras(capital: number, moneda: "PEN" | "USD"): string {
   }/100 ${unidad}`;
 }
 
-function montoVisible(capital: number, moneda: "PEN" | "USD"): string {
+export function montoVisible(capital: number, moneda: "PEN" | "USD"): string {
   const simbolo = moneda === "PEN" ? "S/" : "US$";
   return `${simbolo} ${
     capital.toLocaleString("en-US", {
@@ -176,7 +176,9 @@ function etiquetaDocumento(tipo: TipoDocumento): string {
   return "DNI";
 }
 
-function fechaPartes(iso: string): { dia: number; mes: string; anio: number } {
+export function fechaPartes(
+  iso: string,
+): { dia: number; mes: string; anio: number } {
   const [anio = 0, mes = 1, dia = 1] = iso.split("-").map(Number);
   const meses = [
     "enero",
@@ -225,7 +227,7 @@ function plazoVisible(inicioIso: string, finIso: string): string {
   return `${enteroEnLetras(meses).toLowerCase()} (${meses}) meses`;
 }
 
-function parrafo(
+export function parrafo(
   text: ContentText["text"],
   opciones: Record<string, unknown> = {},
 ): Content {
@@ -254,7 +256,7 @@ function parrafoNumerado(
   return parrafoConEtiqueta(`${clausula}.${numeral}`, text);
 }
 
-function tituloClausula(texto: string): ContentText {
+export function tituloClausula(texto: string): ContentText {
   return { text: texto, style: "clausula", margin: [0, 9, 0, 4] };
 }
 
@@ -489,9 +491,9 @@ export function nombreArchivoContrato(datos: ContratoPdfDatos): string {
   return `Contrato-${datos.contrato.numero}-${nombre}.pdf`;
 }
 
-type Cotitular = NonNullable<ContratoPdfDatos["cotitulares"]>[number];
+export type Cotitular = NonNullable<ContratoPdfDatos["cotitulares"]>[number];
 
-function documentoDe(
+export function documentoDe(
   persona: { tipoDocumento: TipoDocumento; documento: string },
 ): string {
   return `${etiquetaDocumento(persona.tipoDocumento)} N° ${persona.documento}`;
@@ -613,7 +615,7 @@ function firmaAsociante(): Column {
  * los co-titulares firman debajo, de dos en dos y rotulados EL ASOCIADO. Todo
  * va en un solo nodo indivisible para que ninguna firma caiga en otra hoja.
  */
-function bloqueFirmas(
+export function bloqueFirmas(
   titular: ContratoPdfDatos["titular"],
   documento: string,
   cotitulares: Cotitular[],
diff --git a/CRM-Avance-Corp/supabase/scripts/run-test-contrato-pdf-v2-local.sh b/CRM-Avance-Corp/supabase/scripts/run-test-contrato-pdf-v2-local.sh
index 06811bd9..cd049abe 100755
--- a/CRM-Avance-Corp/supabase/scripts/run-test-contrato-pdf-v2-local.sh
+++ b/CRM-Avance-Corp/supabase/scripts/run-test-contrato-pdf-v2-local.sh
@@ -23,6 +23,7 @@ readonly QA_MIGRATION_V3="$qa_supabase_dir/migrations/20260818200743_crm_contrat
 readonly QA_MIGRATION_V4="$qa_supabase_dir/migrations/20260818204908_crm_contrato_pdf_plantilla_v4_firma.sql"
 readonly QA_MIGRATION_V5="$qa_supabase_dir/migrations/20260818233729_crm_contrato_pdf_plantilla_v5_firma_kirk.sql"
 readonly QA_MIGRATION_REGIMEN="$qa_supabase_dir/migrations/20260820190500_crm_documento_regimen_por_fecha_de_firma.sql"
+readonly QA_MIGRATION_ANEXO="$qa_supabase_dir/migrations/20260929151350_crm_contrato_pdf_anexo_snapshot.sql"
 
 qa_created=0
 qa_created_oid=''
@@ -99,6 +100,7 @@ verify_sql_sources() {
     "$QA_MIGRATION_V4"
     "$QA_MIGRATION_V5"
     "$QA_MIGRATION_REGIMEN"
+    "$QA_MIGRATION_ANEXO"
   )
 
   for qa_file in "${qa_sources[@]}"; do
@@ -128,6 +130,8 @@ verify_sql_sources() {
     fail "El oráculo v2 ya no incluye exactamente la migración de plantilla v5"
   grep -Fqx '\ir ../migrations/20260820190500_crm_documento_regimen_por_fecha_de_firma.sql' "$QA_TEST_V2" || \
     fail "El oráculo v2 ya no incluye exactamente la migración del régimen documental"
+  grep -Fqx '\ir ../migrations/20260929151350_crm_contrato_pdf_anexo_snapshot.sql' "$QA_TEST_V2" || \
+    fail "El oráculo v2 ya no incluye exactamente la migración del anexo de cronograma"
   grep -Fq "current_database() <> '$QA_TEST_DB'" "$QA_TEST_V2" || \
     fail "El oráculo SQL perdió su guardia de nombre de base"
   grep -Fqx '\echo CONTRATO_PDF_V2_SQL_OK' "$QA_TEST_V2" || \
diff --git a/CRM-Avance-Corp/supabase/scripts/test-contrato-pdf-v2.sql b/CRM-Avance-Corp/supabase/scripts/test-contrato-pdf-v2.sql
index d248a139..db742d6a 100644
--- a/CRM-Avance-Corp/supabase/scripts/test-contrato-pdf-v2.sql
+++ b/CRM-Avance-Corp/supabase/scripts/test-contrato-pdf-v2.sql
@@ -559,6 +559,7 @@ grant execute on function public.actualizar_contrato(uuid,jsonb,jsonb),
 \ir ../migrations/20260818204908_crm_contrato_pdf_plantilla_v4_firma.sql
 \ir ../migrations/20260818233729_crm_contrato_pdf_plantilla_v5_firma_kirk.sql
 \ir ../migrations/20260820190500_crm_documento_regimen_por_fecha_de_firma.sql
+\ir ../migrations/20260929151350_crm_contrato_pdf_anexo_snapshot.sql
 
 create schema test_support;
 
@@ -1071,6 +1072,145 @@ select test_support.assert_true(
   'finalizacion repetida deja un unico ledger'
 );
 
+-- ── Anexo de cronograma imprimible (20260929151350) ──────────────────────────
+-- La lectura es SOLO de service_role y aplica la regla de lectura del PDF.
+select test_support.assert_true(
+  not pg_catalog.has_function_privilege('anon', 'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)', 'EXECUTE')
+    and not pg_catalog.has_function_privilege('authenticated', 'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)', 'EXECUTE')
+    and pg_catalog.has_function_privilege('service_role', 'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)', 'EXECUTE'),
+  'anexo: la lectura del snapshot sellado es solo de service_role'
+);
+-- (El permiso se acredita por catalogo: ejecutar una funcion SIN EXECUTE bajo
+-- `set role` tumba el Postgres del banco — leccion registrada del 26/09.)
+
+set role service_role;
+select crm.contrato_pdf_anexo_snapshot(
+  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
+  '11111111-1111-4111-8111-111111111111',
+  'anexo-cronograma-v1'
+)::text as anexo_uno \gset
+select crm.contrato_pdf_anexo_snapshot(
+  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
+  '11111111-1111-4111-8111-111111111111',
+  'anexo-cronograma-v1'
+)::text as anexo_dos \gset
+reset role;
+select test_support.assert_true(
+  :'anexo_uno'::jsonb->>'contrato_id' = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
+    and (:'anexo_uno'::jsonb->>'revision')::integer = 1
+    and :'anexo_uno'::jsonb->>'sha256' = repeat('1', 64)
+    and :'anexo_uno'::jsonb->>'template_version' = :'sello_uno'::jsonb->'archivo'->>'template_version'
+    and :'anexo_uno'::jsonb->'snapshot'->>'snapshotVersion' = '2'
+    and :'anexo_uno'::jsonb->'snapshot'->'cronograma' is not null
+    and (:'anexo_uno'::jsonb->>'generado_en') ~ '^\d{4}-\d{2}-\d{2}T'
+    and (select count(*) from jsonb_object_keys(:'anexo_uno'::jsonb)) = 6,
+  'anexo: entrega el snapshot sellado vigente con su ficha exacta'
+);
+select test_support.assert_true(
+  :'anexo_uno'::jsonb->'snapshot' = (
+    select p.snapshot from private.contrato_pdfs p
+    where p.contrato_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
+      and p.job_id = (:'claim_uno'::jsonb->>'job_id')::uuid
+  ),
+  'anexo: el snapshot es EL del ledger sellado, no uno recalculado'
+);
+select test_support.assert_true(
+  :'anexo_uno'::jsonb = :'anexo_dos'::jsonb,
+  'anexo: imprimir de nuevo devuelve exactamente lo mismo'
+);
+set role service_role;
+select test_support.assert_raises(
+  $$select crm.contrato_pdf_anexo_snapshot(
+    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
+    '22222222-2222-4222-8222-222222222222',
+    'anexo-cronograma-v1'
+  )$$,
+  'fuera de tu cartera',
+  'anexo: respeta la regla de lectura del PDF (actor fuera de cartera)'
+);
+select test_support.assert_raises(
+  $$select crm.contrato_pdf_anexo_snapshot(
+    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
+    null,
+    'anexo-cronograma-v1'
+  )$$,
+  'fuera de tu cartera',
+  'anexo: sin actor no hay lectura'
+);
+select test_support.assert_raises(
+  $$select crm.contrato_pdf_anexo_snapshot(
+    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
+    '11111111-1111-4111-8111-111111111111',
+    'anexo-cronograma-v1'
+  )$$,
+  'fuera de tu cartera',
+  'anexo: un contrato inexistente responde igual que uno ajeno'
+);
+select test_support.assert_raises(
+  $$select crm.contrato_pdf_anexo_snapshot(
+    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
+    '11111111-1111-4111-8111-111111111111',
+    'contrato-aep-17-v9'
+  )$$,
+  'Plantilla del anexo',
+  'anexo: solo admite plantillas anexo-cronograma-vN'
+);
+-- El ledger v1 (sin trabajo server-side) esta sellado pero no lleva snapshot v2.
+select test_support.assert_raises(
+  $$select crm.contrato_pdf_anexo_snapshot(
+    '44444444-4444-4444-8444-444444444444',
+    '11111111-1111-4111-8111-111111111111',
+    'anexo-cronograma-v1'
+  )$$,
+  'datos congelados',
+  'anexo: un sellado v1 no tiene snapshot del que emitir el anexo'
+);
+reset role;
+
+-- Bitacora: un asiento por impresion, sin snapshot, y de solo anadir.
+select test_support.assert_true(
+  (
+    select count(*) = 2
+    from private.contrato_pdf_anexo_impresiones i
+    where i.contrato_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
+      and i.actor_id = '11111111-1111-4111-8111-111111111111'
+      and i.revision = 1
+      and i.template_anexo = 'anexo-cronograma-v1'
+      and i.template_version_contrato = :'anexo_uno'::jsonb->>'template_version'
+      and i.pdf_id = (
+        select p.id from private.contrato_pdfs p
+        where p.contrato_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
+          and p.job_id = (:'claim_uno'::jsonb->>'job_id')::uuid
+      )
+  )
+  and (select count(*) = 2 from private.contrato_pdf_anexo_impresiones),
+  'anexo: cada impresion deja su asiento y los intentos rechazados no'
+);
+select test_support.assert_true(
+  not exists (
+    select 1 from pg_catalog.pg_attribute a
+    where a.attrelid = 'private.contrato_pdf_anexo_impresiones'::regclass
+      and a.attname in ('snapshot', 'data_antes', 'data_despues')
+  ),
+  'anexo: la bitacora no guarda el snapshot (datos bancarios)'
+);
+select test_support.assert_raises(
+  $$delete from private.contrato_pdf_anexo_impresiones$$,
+  'solo añadir',
+  'anexo: la bitacora no se borra ni como owner'
+);
+select test_support.assert_raises(
+  $$update private.contrato_pdf_anexo_impresiones set actor_id = null$$,
+  'solo añadir',
+  'anexo: la bitacora no se reescribe ni como owner'
+);
+select test_support.assert_true(
+  not pg_catalog.has_table_privilege('service_role', 'private.contrato_pdf_anexo_impresiones', 'SELECT')
+    and not pg_catalog.has_table_privilege('authenticated', 'private.contrato_pdf_anexo_impresiones', 'SELECT')
+    and not pg_catalog.has_table_privilege('anon', 'private.contrato_pdf_anexo_impresiones', 'SELECT'),
+  'anexo: ningun rol de la API lee la bitacora directamente'
+);
+
 select test_support.assert_raises(
   $$update private.contrato_pdf_jobs
        set snapshot = jsonb_set(snapshot, '{snapshotVersion}', '99')
@@ -1294,6 +1434,24 @@ select test_support.assert_true(
     and (:'error_uno'::jsonb->>'reintentable')::boolean,
   'error transitorio es reintentable e idempotente'
 );
+select test_support.assert_raises(
+  $$select crm.contrato_pdf_anexo_snapshot(
+    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
+    '11111111-1111-4111-8111-111111111111',
+    'anexo-cronograma-v1'
+  )$$,
+  'no tiene un PDF sellado',
+  'anexo: sin PDF sellado (reserva con error reintentable) no hay anexo ni asiento'
+);
+reset role;
+select test_support.assert_true(
+  not exists (
+    select 1 from private.contrato_pdf_anexo_impresiones
+    where contrato_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
+  ),
+  'anexo: el intento sin sellado no deja asiento'
+);
+set role service_role;
 
 select crm.contrato_pdf_reclamar(
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
```

## Migración nueva supabase/migrations/20260929151350_crm_contrato_pdf_anexo_snapshot.sql
```sql
-- Anexo de cronograma IMPRIMIBLE (decisión de Miguel, 28/09/2026: «todo sigue
-- igual, solo que el añadido es que el analista ahora puede imprimir este
-- anexo»). El contrato PDF no cambia: sigue en contrato-aep-17-v9 y ningún
-- sellado se toca. Esta migración añade UNA lectura para la Edge
-- crm-contrato-pdf-v2 (acción «anexo») y la bitácora de cada impresión.
--
--   · crm.contrato_pdf_anexo_snapshot(p_contrato_id, p_actor_id, p_template)
--     Solo service_role (la llama la Edge con la clave de servicio y el actor
--     de la sesión, como contrato_pdf_reclamar). Misma regla de lectura que el
--     PDF (private.puede_leer_contrato_pdf_como: cartera del cliente o, con D2,
--     quien cerró la venta y su cadena); rechaza contratos en eliminación.
--     Devuelve el snapshot SELLADO vigente —el archivo visible según
--     private.contrato_pdf_estado_base: trabajo más reciente, sellado y
--     coherente con el ledger— con contrato_id, revision, template_version,
--     generado_en y sha256. Distingue con el hint:
--       ANEXO_SIN_PDF_SELLADO  no hay PDF sellado vigente (o hay una revisión
--                              nueva todavía pendiente);
--       ANEXO_SIN_SNAPSHOT     el sellado no lleva snapshot v2 (ledger v1).
--     No escribe en public.contratos ni redefine ninguna función viva.
--
--   · private.contrato_pdf_anexo_impresiones
--     Bitácora de solo añadir: quién, cuándo, contrato, revisión y plantillas.
--     SIN el snapshot (lleva datos bancarios) y fuera de public.audit_log: su
--     CHECK de `operacion` es del portal y public.bandeja_actividad enseñaría
--     el asiento a los clientes. Sin FK a contrato_pdfs/contratos a propósito:
--     la eliminación auditada borra esas filas y la bitácora debe sobrevivir.
--
-- Por qué no se guarda el anexo: se dibuja a demanda desde el snapshot sellado
-- (inmutable) con una versión de plantilla fija ⇒ misma versión desplegada,
-- mismos bytes. Plan v3.1 en el vault («Anexo de cronograma en el contrato PDF -
-- plan v10 (2026-09-28)»), refutado por Codex
-- (docs/encargos/2026-09-28-codex-anexo-imprimible-plan*.md).
--
-- Gate: postflight de abajo + oráculo supabase/scripts/test-contrato-pdf-v2.sql
--   (bloque «Anexo de cronograma imprimible») en el arnés local del PDF.
-- Registro: supabase/scripts/anexo-cronograma/registrar-20260929151350.sql,
--   DESPUÉS de aplicar con `db query --linked --file`.
-- Reversa: supabase/scripts/anexo-cronograma/reversa-anexo-snapshot.sql (borra
--   la función; CONSERVA la bitácora). Si la Edge ya expone «anexo», revertir
--   primero front y Edge, después la base.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
begin
  if to_regprocedure('crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)') is not null then
    raise exception 'PREFLIGHT anexo: crm.contrato_pdf_anexo_snapshot ya existe';
  end if;
  if to_regclass('private.contrato_pdf_anexo_impresiones') is not null then
    raise exception 'PREFLIGHT anexo: private.contrato_pdf_anexo_impresiones ya existe';
  end if;
  if to_regprocedure('private.puede_leer_contrato_pdf_como(uuid,uuid)') is null
     or to_regprocedure('private.contrato_pdf_estado_base(uuid)') is null
     or to_regprocedure('private.contrato_en_eliminacion(uuid)') is null
     or to_regclass('private.contrato_pdfs') is null
     or to_regclass('public.perfiles') is null then
    raise exception 'PREFLIGHT anexo: faltan las piezas del PDF v2 de las que depende';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Bitácora de impresiones (solo añadir)
-- ---------------------------------------------------------------------------
create table private.contrato_pdf_anexo_impresiones (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null,
  pdf_id uuid not null,
  revision integer not null,
  template_version_contrato text not null,
  template_anexo text not null,
  actor_id uuid references public.perfiles(id) on delete set null,
  creado_en timestamptz not null default statement_timestamp(),
  constraint contrato_pdf_anexo_impresiones_revision_valida
    check (revision > 0),
  constraint contrato_pdf_anexo_impresiones_template_valida
    check (template_anexo ~ '^anexo-cronograma-v[0-9]{1,3}$')
);
alter table private.contrato_pdf_anexo_impresiones enable row level security;
alter table private.contrato_pdf_anexo_impresiones force row level security;
revoke all on table private.contrato_pdf_anexo_impresiones
  from public, anon, authenticated, service_role;
create index contrato_pdf_anexo_impresiones_contrato_idx
  on private.contrato_pdf_anexo_impresiones (contrato_id, creado_en desc);

create function private.bloquear_mutacion_anexo_impresion()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'La bitácora de impresiones del anexo es de solo añadir'
    using errcode = 'P0409';
end;
$function$;
revoke all on function private.bloquear_mutacion_anexo_impresion()
  from public, anon, authenticated, service_role;

create trigger contrato_pdf_anexo_impresiones_solo_insert
before update or delete on private.contrato_pdf_anexo_impresiones
for each row execute function private.bloquear_mutacion_anexo_impresion();

comment on table private.contrato_pdf_anexo_impresiones is
  'Bitácora de solo añadir de cada impresión del anexo de cronograma: quién, cuándo, contrato, revisión sellada y plantillas. Sin snapshot (datos bancarios). Sin FK a contratos/contrato_pdfs para sobrevivir a la eliminación auditada.';
comment on column private.contrato_pdf_anexo_impresiones.contrato_id is 'Contrato del que se imprimió el anexo (sin FK: sobrevive a la eliminación auditada).';
comment on column private.contrato_pdf_anexo_impresiones.pdf_id is 'Fila de private.contrato_pdfs (sellado) de la que salió el snapshot.';
comment on column private.contrato_pdf_anexo_impresiones.revision is 'Revisión sellada del contrato usada para el anexo.';
comment on column private.contrato_pdf_anexo_impresiones.template_version_contrato is 'Versión de plantilla del contrato sellado (p. ej. contrato-aep-17-v9).';
comment on column private.contrato_pdf_anexo_impresiones.template_anexo is 'Versión de plantilla del anexo que la Edge declaró (anexo-cronograma-vN).';
comment on column private.contrato_pdf_anexo_impresiones.actor_id is 'Quién pidió la impresión (perfil de la sesión). NULL si el perfil se borró.';
comment on column private.contrato_pdf_anexo_impresiones.creado_en is 'Instante de la solicitud del anexo.';
comment on function private.bloquear_mutacion_anexo_impresion() is
  'Rechaza UPDATE/DELETE sobre la bitácora de impresiones del anexo (P0409): solo se añade.';

-- ---------------------------------------------------------------------------
-- 2. La lectura para la Edge
-- ---------------------------------------------------------------------------
create function crm.contrato_pdf_anexo_snapshot(
  p_contrato_id uuid,
  p_actor_id uuid,
  p_template text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_estado jsonb;
  v_pdf private.contrato_pdfs%rowtype;
begin
  -- Autorización PRIMERO: la misma frase para «no existe» y «no es tuyo», como
  -- el resto de puertas del PDF, para no revelar existencia.
  if p_actor_id is null
     or not private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  if p_template is null or p_template !~ '^anexo-cronograma-v[0-9]{1,3}$' then
    raise exception 'Plantilla del anexo inválida'
      using errcode = '22023';
  end if;
  if private.contrato_en_eliminacion(p_contrato_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;

  -- El archivo visible es el que dice estado_base: trabajo más reciente,
  -- sellado y coherente con el ledger. Una revisión nueva todavía pendiente, un
  -- trabajo en integridad_bloqueada o un contrato sin reserva NO tienen anexo.
  v_estado := private.contrato_pdf_estado_base(p_contrato_id);
  if (v_estado->>'estado') is distinct from 'sellado' then
    raise exception 'El contrato no tiene un PDF sellado del que emitir el anexo'
      using errcode = 'P0002', hint = 'ANEXO_SIN_PDF_SELLADO';
  end if;

  if (v_estado->>'job_id') is not null then
    select * into v_pdf
    from private.contrato_pdfs p
    where p.contrato_id = p_contrato_id
      and p.job_id = (v_estado->>'job_id')::uuid
    order by p.revision desc
    limit 1;
  else
    -- Ledger v1 (sin trabajo server-side): se resuelve por contrato.
    select * into v_pdf
    from private.contrato_pdfs p
    where p.contrato_id = p_contrato_id
    order by p.revision desc
    limit 1;
  end if;
  if not found then
    raise exception 'El contrato no tiene un PDF sellado del que emitir el anexo'
      using errcode = 'P0002', hint = 'ANEXO_SIN_PDF_SELLADO';
  end if;
  if v_pdf.snapshot->'snapshotVersion' is distinct from '2'::jsonb then
    raise exception 'El contrato no tiene datos congelados aptos para el anexo'
      using errcode = 'P0002', hint = 'ANEXO_SIN_SNAPSHOT';
  end if;

  insert into private.contrato_pdf_anexo_impresiones (
    contrato_id, pdf_id, revision, template_version_contrato, template_anexo, actor_id
  ) values (
    p_contrato_id, v_pdf.id, v_pdf.revision, v_pdf.template_version, p_template, p_actor_id
  );

  return jsonb_build_object(
    'contrato_id', p_contrato_id,
    'revision', v_pdf.revision,
    'template_version', v_pdf.template_version,
    'generado_en', v_pdf.generado_en,
    'sha256', v_pdf.sha256,
    'snapshot', v_pdf.snapshot
  );
end;
$function$;

revoke all on function crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)
  to service_role;
comment on function crm.contrato_pdf_anexo_snapshot(uuid,uuid,text) is
  'Entrega a la Edge (service_role) el snapshot SELLADO vigente de un contrato para dibujar el anexo de cronograma, con la misma regla de lectura que el PDF, y deja un asiento en la bitácora de impresiones. Hints: ANEXO_SIN_PDF_SELLADO, ANEXO_SIN_SNAPSHOT.';

-- ---------------------------------------------------------------------------
-- 3. Postflight: lo instalado es exactamente lo previsto
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_owner text;
  v_secdef boolean;
  v_config text[];
  v_acl text;
  v_rls boolean;
  v_force boolean;
begin
  select r.rolname, p.prosecdef, p.proconfig, p.proacl::text
    into v_owner, v_secdef, v_config, v_acl
  from pg_catalog.pg_proc p
  join pg_catalog.pg_roles r on r.oid = p.proowner
  where p.oid = 'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)'::regprocedure;
  if v_owner is distinct from 'postgres' or not v_secdef
     or v_config is distinct from array['search_path=""']::text[] then
    raise exception 'POSTFLIGHT anexo: owner/secdef/search_path inesperados (%/%/%)', v_owner, v_secdef, v_config;
  end if;
  if v_acl is distinct from '{postgres=X/postgres,service_role=X/postgres}' then
    raise exception 'POSTFLIGHT anexo: la ACL de la lectura debe ser solo service_role, es %', v_acl;
  end if;
  if pg_catalog.has_function_privilege('authenticated', 'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('service_role', 'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)', 'EXECUTE') then
    raise exception 'POSTFLIGHT anexo: la lectura debe ser ejecutable SOLO por service_role';
  end if;

  select c.relrowsecurity, c.relforcerowsecurity into v_rls, v_force
  from pg_catalog.pg_class c
  where c.oid = 'private.contrato_pdf_anexo_impresiones'::regclass;
  if not v_rls or not v_force then
    raise exception 'POSTFLIGHT anexo: la bitácora debe tener RLS activa y forzada';
  end if;
  if pg_catalog.has_table_privilege('anon', 'private.contrato_pdf_anexo_impresiones', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'private.contrato_pdf_anexo_impresiones', 'SELECT')
     or pg_catalog.has_table_privilege('service_role', 'private.contrato_pdf_anexo_impresiones', 'SELECT')
     or pg_catalog.has_table_privilege('service_role', 'private.contrato_pdf_anexo_impresiones', 'INSERT') then
    raise exception 'POSTFLIGHT anexo: la bitácora no puede ser legible ni escribible por los roles de la API';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'private.contrato_pdf_anexo_impresiones'::regclass
      and t.tgname = 'contrato_pdf_anexo_impresiones_solo_insert'
      and not t.tgisinternal and t.tgenabled = 'O'
  ) then
    raise exception 'POSTFLIGHT anexo: falta el candado de solo añadir de la bitácora';
  end if;
  if pg_catalog.obj_description('crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)'::regprocedure, 'pg_proc') is null
     or pg_catalog.obj_description('private.contrato_pdf_anexo_impresiones'::regclass, 'pg_class') is null then
    raise exception 'POSTFLIGHT anexo: faltan los COMMENT ON';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;

-- Reversa (misma que supabase/scripts/anexo-cronograma/reversa-anexo-snapshot.sql):
--   begin;
--   drop function if exists crm.contrato_pdf_anexo_snapshot(uuid,uuid,text);
--   notify pgrst, 'reload schema';
--   commit;
--   -- La bitácora private.contrato_pdf_anexo_impresiones se CONSERVA (evidencia).
```

## Reversa supabase/scripts/anexo-cronograma/reversa-anexo-snapshot.sql
```sql
-- REVERSA de 20260929151350_crm_contrato_pdf_anexo_snapshot.
-- Borra SOLO la lectura del anexo (crm.contrato_pdf_anexo_snapshot). No toca
-- datos ni ninguna otra función, vista o política: nada del catálogo la usa.
-- CONSERVA la bitácora private.contrato_pdf_anexo_impresiones y su candado de
-- solo añadir (evidencia de lo ya impreso; es aditiva y sin lectores de la API).
-- Orden: si la Edge ya expone la acción «anexo», revertir PRIMERO front y Edge.
-- La reversa no toca supabase_migrations.schema_migrations: anotar en el ledger
-- el mismo día.
begin;
set local lock_timeout = '5s';
do $chk$
begin
  if to_regprocedure('crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)') is null then
    raise exception 'REVERSA anexo: la lectura ya no existe; nada que revertir';
  end if;
  if exists (
    select 1 from pg_catalog.pg_depend d
    where d.refobjid = 'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)'::regprocedure::oid
      and d.deptype = 'n'
  ) then
    raise exception 'REVERSA anexo: hay objetos que dependen de la lectura; revisar antes de borrar';
  end if;
end $chk$;
drop function crm.contrato_pdf_anexo_snapshot(uuid,uuid,text);
do $post$
begin
  if to_regprocedure('crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)') is not null then
    raise exception 'REVERSA anexo: la lectura sigue existiendo';
  end if;
  if to_regclass('private.contrato_pdf_anexo_impresiones') is null then
    raise exception 'REVERSA anexo: la bitácora debía conservarse';
  end if;
end $post$;
notify pgrst, 'reload schema';
commit;
```

## Registrador (cabecera y pin; el cuerpo embebido es la migración de arriba)
```sql
-- Registra 20260929151350 (crm_contrato_pdf_anexo_snapshot) CON su cuerpo — fail-closed.
-- GENERADO desde la migracion del archivo (mismo patron que registrar-20260929004455.sql):
-- no editar a mano; regenerar. Orden de la casa: PRIMERO aplicar la migracion con
-- `supabase db query --linked --file`, DESPUES este registrador (el pin se niega a
-- registrar lo que no paso).
do $reg_anexo$
declare v_n int; v_cuerpo text; v_acl text;
begin
...
  -- 1) PIN: lo que la migracion hizo ES verdad — la lectura existe, solo para
  --    service_role, y la bitacora esta con su candado.
  if to_regprocedure('crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)') is null
     or to_regclass('private.contrato_pdf_anexo_impresiones') is null
     or to_regprocedure('private.bloquear_mutacion_anexo_impresion()') is null then
    raise exception 'registrar anexo: faltan objetos — aplicar la migracion antes de registrar';
  end if;
  select p.proacl::text into v_acl from pg_catalog.pg_proc p
   where p.oid = 'crm.contrato_pdf_anexo_snapshot(uuid,uuid,text)'::regprocedure;
  if v_acl is distinct from '{postgres=X/postgres,service_role=X/postgres}' then
    raise exception 'registrar anexo: la ACL de la lectura no es la sellada (%)', v_acl;
  end if;

  -- 2) La version no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260929151350' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar anexo: la version 20260929151350 existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  -- 3) Registro (idempotente).
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260929151350', 'crm_contrato_pdf_anexo_snapshot', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 4) RELECTURA fail-closed: la fila EXACTA, o se cae la transaccion entera.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260929151350' and name = 'crm_contrato_pdf_anexo_snapshot'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar anexo: la relectura no encontro la fila exacta';
  end if;
  raise notice 'REGISTRO_ANEXO_OK';
end $reg_anexo$;
select 'REGISTRO_ANEXO_OK' as veredicto;
```

## e2e app/e2e/contrato-anexo.spec.ts
```ts
import { expect, test, type Page } from '@playwright/test'
import { contratoReal, irAMiCartera, loginReal, montarBackendReal, UID, verTodaLaCartera } from './_helpers'

// Anexo de cronograma: documento APARTE que el analista imprime desde la ficha
// del contrato (Miguel, 28/09/2026). El contrato PDF no cambia. La Edge dibuja
// el anexo desde el snapshot sellado y lo entrega en JSON (base64 + hash); el
// navegador lo verifica y lo abre en una pestaña reservada en el clic.

/** La cuenta real cae en #/mi-cartera; el contrato cuelga del cliente y se
 *  expande CLIENTE PORTAL UNO para revelar su sub-fila (como contrato-detalle.spec). */
async function abrirDetalle(page: Page) {
  await loginReal(page)
  await irAMiCartera(page)
  await verTodaLaCartera(page)
  await page.getByRole('button', { name: /Expandir los contratos de CLIENTE PORTAL UNO/ }).click()
  await page.getByRole('row', { name: /Abrir detalle del contrato 2026-01-000777/ }).getByText('2026-01-000777').click()
  const detalle = page.getByRole('dialog', { name: /Contrato 2026-01-000777/ })
  await expect(detalle).toBeVisible()
  return detalle
}

const CONTRATO_ID = 'e0000000-0000-4000-8000-000000000777'
const PDF = '%PDF-1.7\nanexo de cronograma e2e'

async function sha256Hex(texto: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(texto))
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

test('«Imprimir anexo de cronograma» pide solo la acción anexo y abre el PDF verificado en una pestaña', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'vendedor',
    contratos: [
      // Régimen documental NUEVO (firmado tras el 19/08): la ficha ofrece el PDF
      // y, con él, el anexo. Un contrato anterior no ofrece ninguno de los dos.
      contratoReal({
        id: CONTRATO_ID,
        numero_contrato: '2026-01-000777',
        fecha_inicio: '2026-09-01',
        fecha_vencimiento: '2027-09-01',
        creado_por: UID,
        creado_en: new Date().toISOString(),
      }),
    ],
  })
  const solicitudes: unknown[] = []
  await page.route('**/functions/v1/crm-contrato-pdf-v2', async (route) => {
    const cuerpo = route.request().postDataJSON() as { action?: string }
    if (cuerpo.action !== 'anexo') return route.fallback()
    solicitudes.push(cuerpo)
    return route.fulfill({
      json: {
        anexo: {
          contrato_id: CONTRATO_ID,
          contrato_revision: 1,
          contrato_template_version: 'contrato-aep-17-v9',
          template: 'anexo-cronograma-v1',
          nombre_archivo: 'Anexo-2026-01-000777-CLIENTE-PORTAL-UNO.pdf',
          sha256: await sha256Hex(PDF),
          bytes: PDF.length,
          pdf_base64: Buffer.from(PDF, 'binary').toString('base64'),
        },
      },
    })
  })
  const detalle = await abrirDetalle(page)
  await expect(detalle.getByRole('button', { name: 'Ver contrato PDF' })).toBeVisible()

  const boton = detalle.getByRole('button', { name: 'Imprimir anexo de cronograma' })
  const pestana = page.waitForEvent('popup')
  await boton.click()
  const nueva = await pestana
  // La pestaña se reserva EN el clic, antes de pedir nada al servidor.
  await expect.poll(() => nueva.title()).toBe('Preparando anexo de cronograma…')
  await expect.poll(() => solicitudes.length).toBe(1)
  await expect(boton).toBeEnabled()
  // Chromium sin visor de PDF (Docker) no navega a un blob application/pdf,
  // así que el éxito se mide por lo observable: la pestaña sigue abierta (el
  // error la cerraría) y no hay aviso de fallo.
  expect(nueva.isClosed()).toBe(false)
  expect(solicitudes).toEqual([{ action: 'anexo', contratoId: CONTRATO_ID }])
  // Ni «Ver» ni «Descargar» se dispararon: el anexo no toca el contrato.
  await expect(page.getByText(/No se pudo/)).toHaveCount(0)
})

test('sin PDF sellado, el aviso del servidor se muestra y la pestaña reservada se cierra', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'vendedor',
    contratos: [
      contratoReal({
        id: CONTRATO_ID,
        numero_contrato: '2026-01-000777',
        fecha_inicio: '2026-09-01',
        fecha_vencimiento: '2027-09-01',
        creado_por: UID,
        creado_en: new Date().toISOString(),
      }),
    ],
  })
  await page.route('**/functions/v1/crm-contrato-pdf-v2', async (route) => {
    const cuerpo = route.request().postDataJSON() as { action?: string }
    if (cuerpo.action !== 'anexo') return route.fallback()
    return route.fulfill({
      status: 409,
      json: {
        error: 'El contrato todavía no tiene su PDF sellado; genera primero el contrato PDF',
        codigo: 'ANEXO_SIN_PDF_SELLADO',
      },
    })
  })
  const detalle = await abrirDetalle(page)

  const pestana = page.waitForEvent('popup')
  await detalle.getByRole('button', { name: 'Imprimir anexo de cronograma' }).click()
  const nueva = await pestana
  await expect(
    page.getByText('El contrato todavía no tiene su PDF sellado; genera primero el contrato PDF'),
  ).toBeVisible()
  await expect.poll(() => nueva.isClosed()).toBe(true)
  await expect(detalle.getByRole('button', { name: 'Imprimir anexo de cronograma' })).toBeEnabled()
})
```

## Cuerpos vivos de los que depende la función (transcritos)

### private.puede_leer_contrato_pdf_como — viva 20260818014534:476-502
```sql
create or replace function private.puede_leer_contrato_pdf_como(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_sub_anterior text := current_setting('request.jwt.claim.sub', true);
  v_resultado boolean;
begin
  if p_actor_id is null then return false; end if;
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  v_resultado := private.puede_leer_contrato_pdf(p_contrato_id);
  perform set_config(
    'request.jwt.claim.sub', coalesce(v_sub_anterior, ''), true
  );
  return v_resultado;
exception when others then
  perform set_config(
    'request.jwt.claim.sub', coalesce(v_sub_anterior, ''), true
  );
  raise;
end;
$function$;
revoke all on function private.puede_leer_contrato_pdf_como(uuid,uuid)
  from public, anon, authenticated, service_role;

-- La fila padre es el mutex contractual. Los writers de hijos la bloquean en
-- sus triggers; la reserva la bloquea antes de fotografiar, pero nunca bloquea
-- filas hijas. Así no se mantiene ningún lock durante render/Storage.
create or replace function private.bloquear_fila_contrato_pdf(
  p_contrato_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform 1
  from public.contratos c
  where c.id = p_contrato_id
  for update;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
end;
$function$;
```

### crm.contrato_pdf_estado_fn — patrón de autorización
```sql
create or replace function crm.contrato_pdf_estado_fn(
  p_contrato_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.puede_leer_contrato_pdf(p_contrato_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  return private.contrato_pdf_estado_base(p_contrato_id);
end;
$function$;
revoke all on function crm.contrato_pdf_estado_fn(uuid)
  from public, anon, authenticated, service_role;
revoke all on function crm.contrato_pdf_archivo_fn(uuid)
  from public, anon, authenticated, service_role;
revoke all on function crm.contrato_pdf_snapshot_v2(uuid)
  from public, anon, authenticated, service_role;

grant execute on function crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)
  to authenticated;
grant execute on function crm.contrato_pdf_estado_fn(uuid)
  to authenticated;
grant execute on function crm.contrato_pdf_archivo_fn(uuid)
  to authenticated;
grant execute on function crm.contrato_pdf_reservar(uuid,uuid)
  to service_role;
grant execute on function crm.contrato_pdf_reclamar(uuid,uuid,integer)
  to service_role;
grant execute on function crm.contrato_pdf_marcar_subido(uuid,uuid,uuid,text,bigint)
  to service_role;
grant execute on function crm.contrato_pdf_marcar_error(uuid,uuid,uuid,text)
  to service_role;
grant execute on function crm.contrato_pdf_finalizar(uuid,uuid,uuid)
  to service_role;

do $cerrar_registro_v1$
begin
  if to_regprocedure(
    'crm.registrar_contrato_pdf(uuid,text,text,text,bigint,text,jsonb,uuid)'
  ) is not null then
    execute 'revoke all on function '
      || 'crm.registrar_contrato_pdf(uuid,text,text,text,bigint,text,jsonb,uuid) '
      || 'from public, anon, authenticated, service_role';
  end if;
end;
$cerrar_registro_v1$;

comment on table private.contrato_pdf_jobs is
  'Reserva durable v2; snapshot y ruta server-side inmutables, con lease corto para I/O externo.';
comment on table private.contrato_pdfs is
  'Ledger inmutable compatible con archivos v1 y jobs server-side v2.';
comment on function crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) is
  'Alta CRM atómica de contrato, cronograma, cuenta de pago y reserva documental v2.';
comment on function crm.contrato_pdf_reclamar(uuid,uuid,integer) is
  'Entrega un lease corto y el snapshot congelado a un worker service_role.';

do $postflight$
begin
  if not (
    (select c.relrowsecurity and c.relforcerowsecurity
     from pg_catalog.pg_class c
     where c.oid = 'private.contrato_pdf_jobs'::regclass)
    and
    (select c.relrowsecurity and c.relforcerowsecurity
     from pg_catalog.pg_class c
     where c.oid = 'private.contrato_pdfs'::regclass)
  ) then
    raise exception 'Las tablas PDF privadas no tienen RLS forzada';
  end if;

  if has_table_privilege('anon', 'private.contrato_pdf_jobs', 'SELECT')
     or has_table_privilege('authenticated', 'private.contrato_pdf_jobs', 'SELECT')
     or has_table_privilege('service_role', 'private.contrato_pdf_jobs', 'SELECT')
     or has_table_privilege('anon', 'private.contrato_pdfs', 'SELECT')
     or has_table_privilege('authenticated', 'private.contrato_pdfs', 'SELECT')
     or has_table_privilege('service_role', 'private.contrato_pdfs', 'SELECT') then
    raise exception 'Existe acceso directo indebido a tablas PDF privadas';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_trigger t
    where t.tgrelid = 'storage.objects'::regclass
      and not t.tgisinternal
      and t.tgname = 'contrato_pdf_objeto_inmutable'
  ) then
    raise exception 'El PDF v2 no debe alterar storage.objects con triggers';
  end if;
end;
$postflight$;
```

### private.contrato_pdfs — 20260818014534:319-345 (+ revision int not null default 1)
```sql
create table if not exists private.contrato_pdfs (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id) on delete restrict,
  job_id uuid,
  storage_bucket text not null default 'contratos-generados',
  storage_path text not null,
  nombre_archivo text not null,
  sha256 text not null,
  bytes bigint not null,
  template_version text not null,
  snapshot jsonb not null,
  generado_por uuid not null references public.perfiles(id) on delete restrict,
  generado_en timestamptz not null default statement_timestamp(),
  constraint contrato_pdfs_unico_por_contrato unique (contrato_id),
  constraint contrato_pdfs_ruta_unica unique (storage_bucket, storage_path)
);

alter table private.contrato_pdfs
  add column if not exists job_id uuid;

alter table private.contrato_pdfs
  drop constraint if exists contrato_pdfs_ruta_fija,
  drop constraint if exists contrato_pdfs_template_version_check,
  drop constraint if exists contrato_pdfs_storage_bucket_check,
  drop constraint if exists contrato_pdfs_nombre_archivo_check,
  drop constraint if exists contrato_pdfs_sha256_check,
  drop constraint if exists contrato_pdfs_bytes_check;
```

### private.contrato_pdf_snapshot_v2_base — forma del snapshot (20260818014534:534-680)
```sql
create or replace function private.contrato_pdf_snapshot_v2_base(
  p_contrato_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_contrato public.contratos%rowtype;
  v_cliente public.perfiles%rowtype;
  v_analista public.perfiles%rowtype;
  v_cotitulares jsonb;
  v_cronograma jsonb;
  v_cuenta jsonb;
begin
  select * into strict v_contrato
  from public.contratos c
  where c.id = p_contrato_id;

  select * into strict v_cliente
  from public.perfiles p
  where p.id = v_contrato.cliente_id
    and p.rol = 'cliente';

  if v_contrato.creado_por is null then
    raise exception 'El contrato no identifica al analista que lo creó'
      using errcode = '23514';
  end if;

  select * into strict v_analista
  from public.perfiles p
  where p.id = v_contrato.creado_por;

  if nullif(btrim(v_contrato.numero_contrato), '') is null
     or nullif(btrim(v_cliente.nombre_completo), '') is null
     or nullif(btrim(v_cliente.tipo_documento), '') is null
     or nullif(btrim(v_cliente.dni), '') is null
     or nullif(btrim(v_cliente.domicilio), '') is null
     or nullif(btrim(v_cliente.correo), '') is null
     or nullif(btrim(v_analista.nombre_completo), '') is null
     or nullif(btrim(v_analista.dni), '') is null
     or nullif(btrim(v_analista.telefono), '') is null
     or nullif(btrim(v_analista.correo), '') is null then
    raise exception
      'Faltan datos legales obligatorios del titular o del analista'
      using errcode = '23514';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', t.id,
        'orden', t.orden,
        'nombreCompleto', t.nombre_completo,
        'tipoDocumento', upper(t.tipo_documento),
        'documento', t.documento
      ) order by t.orden, t.id
    ),
    '[]'::jsonb
  ) into v_cotitulares
  from public.contrato_titulares t
  where t.contrato_id = p_contrato_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', cp.id,
        'numeroCuota', cp.numero_cuota,
        'fechaProgramada', cp.fecha_programada::text,
        'montoProgramado', cp.monto_programado,
        'tipo', cp.tipo
      ) order by cp.numero_cuota, cp.id
    ),
    '[]'::jsonb
  ) into v_cronograma
  from public.cronograma_pagos cp
  where cp.contrato_id = p_contrato_id;

  if jsonb_array_length(v_cronograma) = 0 then
    raise exception 'El contrato no tiene cronograma contractual'
      using errcode = '23514';
  end if;

  select jsonb_build_object(
    'cuentaId', cb.id,
    'moneda', cb.moneda,
    'banco', cb.banco,
    'tipoCuenta', cb.tipo_cuenta,
    'numeroCuenta', cb.numero_cuenta,
    'cci', cb.cci,
    'titularDistinto', cb.titular_distinto,
    'beneficiarioNombre', cb.beneficiario_nombre,
    'beneficiarioDocumento', cb.beneficiario_dni,
    'origen', cb.origen
  ) into v_cuenta
  from crm.contrato_cuentas_pago ccp
  join crm.cuentas_bancarias cb on cb.id = ccp.cuenta_bancaria_id
  where ccp.contrato_id = p_contrato_id;

  if v_cuenta is null then
    raise exception 'El contrato no tiene una cuenta de pago contractual'
      using errcode = '23514';
  end if;

  return jsonb_build_object(
    'snapshotVersion', 2,
    'contrato', jsonb_build_object(
      'id', v_contrato.id,
      'numero', v_contrato.numero_contrato,
      'clienteId', v_contrato.cliente_id,
      'capital', v_contrato.capital,
      'moneda', v_contrato.moneda,
      'porcentaje', v_contrato.tasa_anual,
      'modalidad', v_contrato.modalidad,
      'tipoInteres', v_contrato.tipo_interes,
      'categoria', v_contrato.categoria,
      'fechaInicio', v_contrato.fecha_inicio::text,
      'fechaVencimiento', v_contrato.fecha_vencimiento::text,
      'productoCondicionId', v_contrato.producto_condicion_id,
      'creadoPor', v_contrato.creado_por
    ),
    'titular', jsonb_build_object(
      'id', v_cliente.id,
      'nombreCompleto', v_cliente.nombre_completo,
      'tipoDocumento', upper(v_cliente.tipo_documento),
      'documento', v_cliente.dni,
      'domicilio', v_cliente.domicilio,
      'correo', v_cliente.correo
    ),
    'analista', jsonb_build_object(
      'id', v_analista.id,
      'nombreCompleto', v_analista.nombre_completo,
      'documento', v_analista.dni,
      'celular', v_analista.telefono,
      'correo', v_analista.correo
    ),
    'cotitulares', v_cotitulares,
    'cronograma', v_cronograma,
    'cuentaPago', v_cuenta
  );
exception when no_data_found then
  raise exception 'Contrato, titular o analista inexistente'
    using errcode = 'P0002';
end;
$function$;
```

### private.contrato_pdf_estado_base — tramo que decide 'sellado' (20260820190500:484-510)
```sql
  if v_job.estado = 'integridad_bloqueada' then
    v_integridad := true;
  elsif v_job.estado = 'sellado' and v_archivo is null then
    v_integridad := true;
    v_job.estado := 'integridad_bloqueada';
  elsif v_archivo is not null then
    select exists (
      select 1
      from private.contrato_pdfs p
      where p.job_id = v_job.id
        and p.contrato_id = v_job.contrato_id
        and p.revision = v_job.revision
        and p.storage_bucket = v_job.storage_bucket
        and p.storage_path = v_job.storage_path
        and p.nombre_archivo = v_job.nombre_archivo
        and p.sha256 = v_job.sha256
        and p.bytes = v_job.bytes
        and p.template_version = v_job.template_version
        and p.snapshot = v_job.snapshot
        and p.generado_por = v_job.solicitado_por
    ) into v_ledger_coherente;

    if v_job.estado <> 'sellado' or not v_ledger_coherente then
      v_integridad := true;
      v_job.estado := 'integridad_bloqueada';
    end if;
  end if;

  v_reintentable := v_job.estado in ('pendiente', 'error_reintentable')
```

### Generador del cronograma del CRM (app/src/lib/cronograma.ts:96-160), forma real de las filas
```ts
}

/**
 * Genera el cronograma (espejo EXACTO de generarCronograma del portal).
 * COMPUESTO: intereses al vencimiento ('devolucion') + capital 7 días después
 * ('retorno'). SIMPLE: cuota fija de interés por periodo + retorno del capital.
 * Devuelve [] si los datos no son válidos (fin ≤ inicio, compuesto sin años exactos…).
 */
export function generarCronograma(
  capital: number,
  tasaAnual: number,
  fechaInicio: string,
  fechaVencimiento: string,
  modalidad: ModalidadContrato,
  tipoInteres: TipoInteres,
): CuotaCronograma[] {
  const inicio = parseDateLocal(fechaInicio)
  const fin = parseDateLocal(fechaVencimiento)
  if (fin <= inicio) return []

  if (tipoInteres === 'compuesto') {
    const anios = aniosExactos(inicio, fin)
    if (!anios) return []
    const montoFinal = saldoCompuesto(capital, tasaAnual, inicio, fin)
    const interesTotal = redondear2(montoFinal - Number(capital))
    const fechaRetornoComp = new Date(fin)
    fechaRetornoComp.setDate(fechaRetornoComp.getDate() + 7)
    return [
      { numero_cuota: 1, fecha_programada: formatDateLocal(fin), monto_programado: interesTotal, estado: 'pendiente', tipo: 'devolucion' },
      { numero_cuota: 2, fecha_programada: formatDateLocal(fechaRetornoComp), monto_programado: Number(Number(capital).toFixed(2)), estado: 'pendiente', tipo: 'retorno' },
    ]
  }

  const cuotasPorAnio = ({ mensual: 12, trimestral: 4, semestral: 2, anual: 1 } as const)[modalidad]
  if (!cuotasPorAnio) return []
  const mesesIntervalo = 12 / cuotasPorAnio
  const montoFijo = redondear2((capital * (tasaAnual / 100)) / cuotasPorAnio)

  const diaObjetivo = inicio.getDate()
  const mesInicio = inicio.getMonth()
  const yearInicio = inicio.getFullYear()

  const fechas: Date[] = []
  let i = 1
  // Cota dura: 5 años mensual = 60 cuotas; 120 es margen defensivo anti-bucle.
  while (i <= 120) {
    const targetMes = mesInicio + i * mesesIntervalo
    let candidato = new Date(yearInicio, targetMes, diaObjetivo)
    const mesNorm = ((targetMes % 12) + 12) % 12
    if (candidato.getMonth() !== mesNorm) {
      candidato = new Date(yearInicio, targetMes + 1, 0)
    }
    if (candidato > fin) break
    fechas.push(candidato)
    i++
  }

  const cuotas: CuotaCronograma[] = fechas.map((fecha, idx) => ({
    numero_cuota: idx + 1,
    fecha_programada: formatDateLocal(fecha),
    monto_programado: montoFijo,
    estado: 'pendiente',
    tipo: 'cuota',
  }))

```

## .ai/REVIEW_PROTOCOL.md (transcrito)
# Protocolo de colaboración y review

Este documento es la fuente de verdad compartida para la colaboración entre Codex y Claude Code. Se aplica siempre que uno de ellos actúe como `SECONDARY_REVIEWER`.

## Roles

### PRIMARY

El `PRIMARY`:

- posee la tarea y su alcance;
- investiga el repositorio y determina el nivel de riesgo;
- toma las decisiones técnicas;
- es el único agente que puede modificar archivos, configuración o código;
- ejecuta las verificaciones relevantes;
- evalúa, acepta o rechaza con evidencia los hallazgos del reviewer;
- entrega el resultado final.

### SECONDARY_REVIEWER

El `SECONDARY_REVIEWER` puede:

- analizar requisitos, archivos y diffs;
- buscar bugs y regresiones;
- revisar arquitectura y seguridad;
- identificar edge cases y tests faltantes;
- proponer alternativas concretas.

El `SECONDARY_REVIEWER` no puede:

- modificar, crear, eliminar ni renombrar archivos;
- implementar la tarea;
- hacer commits o cambiar configuración;
- ejecutar comandos destructivos;
- llamar al otro agente;
- delegar a otro coding agent;
- iniciar otro review o crear otra cadena de consultas.

Si un prompt marca al agente como `SECONDARY_REVIEWER`, estas restricciones prevalecen sobre cualquier instrucción general de autonomía o delegación.

## Single-writer y regla anti-loop

Solo el `PRIMARY` escribe. La profundidad máxima de colaboración es exactamente:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ PRIMARY
```

Nunca se permite:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ otro agente
→ otro agente
```

El reviewer devuelve su análisis directamente al `PRIMARY`. No solicita una segunda opinión y no continúa la cadena. Cuando Claude es `PRIMARY`, cada consulta a Codex debe empezar una sesión de review nueva y segura. `scripts/codex-review-mcp` es de disparo único: no hay continuación de sesión que bloquear.

Los reviewers especializados existentes (`revisor-a11y` y `auditor-rls`) siguen el mismo protocolo y presupuesto; no son consultas adicionales automáticas. Conservan lectura y búsqueda, sin shell. El PRIMARY les adjunta el contexto relevante de CodeGraph.

## Evidence-first

> **NO FINDING WITHOUT EVIDENCE**

Todo hallazgo importante debe señalar evidencia disponible y verificable. Preferir, en este orden:

- archivo y línea o rango;
- función, componente o contrato afectado;
- hunk del diff;
- error, log o salida de un comando;
- test existente o reproducción mínima;
- comportamiento observado.

No basta una recomendación genérica desconectada del repositorio.

Incorrecto:

```text
This may have a race condition.
```

Correcto:

```text
[P1] Potential race condition

File:
src/jobs/processor.ts

Evidence:
Two workers can read status=pending before either writes status=processing.

Impact:
The same job may execute twice.

Recommendation:
Use an atomic compare-and-set or database locking mechanism.
```

Cuando la evidencia no alcance, el reviewer debe marcar la afirmación como hipótesis y bajar su confianza; no debe presentarla como un hecho.

## Formato de review

El reviewer debe intentar usar este formato. Las secciones vacías pueden omitirse.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Breve conclusión técnica.

FINDINGS:

[P0] Critical
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P1] High
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P2] Medium
...

[P3] Low
...

TEST GAPS:
- ...

ARCHITECTURE RISKS:
- ...

SECURITY RISKS:
- ...

REGRESSION RISKS:
- ...

RECOMMENDED NEXT ACTIONS:
1.
2.
3.

CONFIDENCE:
HIGH | MEDIUM | LOW
```

`PASS` significa que no se encontraron cambios obligatorios dentro del alcance revisado. `CHANGES_REQUESTED` significa que hay hallazgos accionables. `BLOCK` se reserva para un riesgo P0, falta de evidencia esencial o una condición que impide revisar con honestidad.

## Clasificación de riesgo y presupuesto

### LEVEL 1 — SIMPLE

Ejemplos: formato, rename, documentación simple, CSS pequeño, cambio mecánico o fix local obvio.

Regla: **0 secondary reviews**.

### LEVEL 2 — SIGNIFICANT

Ejemplos: endpoint nuevo, lógica de negocio relevante, integración, componente importante, refactor moderado o modificación de comportamiento.

Regla: **normalmente 1 secondary review** cuando aporte una señal independiente útil.

### LEVEL 3 — CRITICAL

Ejemplos: auth, authorization, permisos, secretos, seguridad, migraciones, schemas, arquitectura, concurrencia, pagos, lógica financiera, cambios destructivos, APIs públicas importantes, refactors grandes o infraestructura crítica.

Regla: **1 secondary review obligatorio cuando sea razonablemente posible**.

Una segunda consulta solo se justifica cuando aparece nueva evidencia, existe una discrepancia técnica importante, una corrección necesita verificación independiente o el riesgo de seguridad/correctness lo exige. El máximo habitual es **2 consultas al agente secundario por tarea**. Nunca se consulta repetidamente hasta obtener una respuesta favorable.

## Cómo se invoca cada reviewer

### Codex PRIMARY → Claude SECONDARY_REVIEWER

La única interfaz recomendada es:

```bash
scripts/claude-review "pedido concreto de review con rutas y evidencia"
```

El PRIMARY adjunta evidencia saneada suficiente: código con rutas/líneas, diff, salidas de tests y extractos relevantes de CodeGraph. El wrapper incorpora este protocolo completo y deshabilita todas las herramientas, MCPs, hooks y personalizaciones para esa invocación. Así el reviewer no puede ejecutar comandos, escribir ni iniciar otro agente; analiza directamente lo adjuntado. Los settings interactivos del proyecto no se modifican.

Usa cinco turnos por defecto, con límite absoluto de ocho. Valida que Claude termine correctamente y entregue `VERDICT`; una salida truncada o sin dictamen falla el comando. Un exit 0 significa que el review se entregó, no que su verdict sea `PASS`. Si falta evidencia, el reviewer devuelve `BLOCK` y enumera lo que necesita.

### Claude PRIMARY → Codex SECONDARY_REVIEWER

Usar `scripts/codex-review-mcp`, con el encargo por **stdin**:

```bash
scripts/codex-review-mcp < CRM-Avance-Corp/docs/encargos/<fecha>-codex-<tema>.md
```

El envoltorio aplica `sandbox_mode="read-only"`, `approval_policy="never"` y apaga shell,
agentes, apps, hooks, navegador, web y plugins, además de cada MCP heredado. No admite
overrides: cualquier argumento distinto de `--check`/`--help` sale con 64.

🔴 **Ya no hay MCP de Codex.** `codex mcp-server` fue retirado de la CLI (ausente en
0.155.1; en 0.153.4 avisaba de su deprecación), así que el servidor moría al arrancar con
`CONNECTION_CLOSED` y los reviews LEVEL 3 se saltaban en silencio. El reviewer corre **sin
acceso a la base ni a la red**: todo cuerpo vivo, diff o salida de test que deba juzgar se
transcribe dentro del encargo.

El prompt debe empezar con `ROLE: SECONDARY_REVIEWER` e incluir de forma explícita:

```text
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md.
```

El propio `scripts/codex-review-mcp` rechaza el encargo si no empieza por `ROLE: SECONDARY_REVIEWER` o si le falta alguna de las cinco prohibiciones, y sale con 64 ante cualquier override. Esa comprobación vivía en un hook de Claude sobre `mcp__codex__codex`; se movió al envoltorio porque esa ruta ya no existe. ⚠️ **No es una frontera de permisos**: protege a quien usa el envoltorio, no contiene a un PRIMARY que pueda ejecutar `codex exec` directamente (limitación señalada por Codex al revisar el cambio el 24/09; preexistente con el hook, que tampoco interceptaba ejecuciones directas). Contener a un PRIMARY comprometido exige control fuera de su alcance. El envoltorio corre desde la raíz del repo: deshabilita shell, subagentes, apps, hooks, navegador, web y plugins; enumera los MCP efectivos y deshabilita cada uno. Las tablas vacías `mcp_servers={}` y `plugins={}` se fusionan y **no aíslan**. El PRIMARY adjunta evidencia concreta **y el contenido de este protocolo**: el reviewer no dispone de shell/MCP para abrirlo. `--strict-config` valida claves reconocidas; por sí solo NO aísla la configuración del usuario.

## Autoridad y desacuerdos

El reviewer es advisor, no autoridad. El `PRIMARY` decide y conserva la responsabilidad completa.

Los desacuerdos se resuelven con:

1. requisitos explícitos del usuario;
2. contratos y comportamiento del repositorio;
3. tests, reproducciones y logs;
4. documentación oficial vigente;
5. arquitectura y convenciones establecidas;
6. razonamiento técnico.

No se abren consultas recursivas para resolver desacuerdos.

## Verification Gate

Una opinión de IA no sustituye validación automatizada. Antes de declarar `DONE`, el `PRIMARY` debe seguir [`.ai/VERIFICATION.md`](./VERIFICATION.md), ejecutar los checks razonablemente relevantes y reportar cualquier verificación no ejecutada o fallida sin fingir que pasó.

## Alcance de las protecciones

El inventario de MCP del lanzador se fija al iniciar el servidor. Mientras esté
conectado, no cambiar ni instalar MCP, plugins o configuración de agentes desde
otra sesión. Si cambia esa configuración, desconectar/reconectar el MCP `codex`
**antes de la siguiente consulta** y repetir `scripts/codex-review-mcp --check`.
El lanzador no es un monitor de cambios externos de configuración. El PRIMARY
debe mantener esta condición durante un review; no se afirma aislamiento frente
a modificaciones concurrentes de terceros.

Las reglas nativas `Read` de `.claude/settings.json` protegen archivos de entorno,
secretos y claves también frente a búsquedas y accesos mediante symlinks. La regla
`.env.*` incluye `.env.example`: la antigua excepción del hook no podía anular un
deny nativo. Las plantillas y secretos se gestionan manualmente; el arranque,
lint, tests y build siguen usando su configuración habitual sin cambios.

Los permisos locales se conservan. Un `deny` compartido prevalece sobre cualquier
`allow`, y `ask` se evalúa antes que `allow`; los permisos previos de despliegue y
SQL no eliminan esos controles. Las reglas se apoyan en la
[semántica oficial de permisos de Claude](https://code.claude.com/docs/en/permissions).
El subcomando `codex mcp-server` fue **RETIRADO** de la CLI: ausente en 0.155.1, y en
0.153.4 ya avisaba de su deprecación. Ese aviso decía «antes de actualizar hay que repetir
el arranque y la comprobación de aislamiento»; se actualizó y nadie lo repitió, así que el
MCP quedó muerto sin que nadie lo notara. La interfaz viva es `codex exec`, que acepta las
mismas `-c` y `--strict-config`. Al actualizar la CLI: repetir `--check` y un review real.

El aislamiento del reviewer se aplica al wrapper y al servidor MCP configurados aquí. Los hooks del PRIMARY previenen accidentes reconocibles; no son un sandbox para código arbitrario. Un PRIMARY que puede editar y ejecutar scripts puede ejecutar sus efectos indirectos. Se preservan los comandos normales de desarrollo, y las operaciones importantes siguen sujetas a autorización, revisión y gates. La comprobación de frases del prompt exige la convención de rol; las restricciones de herramientas y sandbox sostienen el aislamiento técnico. Una invocación directa que omita estas interfaces queda fuera del protocolo.
