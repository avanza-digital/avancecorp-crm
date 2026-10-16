ROLE: SECONDARY_REVIEWER. Codex es PRIMARY. Revisión LEVEL 3 con lente auditor-rls.
Solo analiza evidencia; no modificar archivos, implementar, invocar Codex, delegar ni iniciar otra revisión.
Petición: Miguel necesita que los supervisores registren referidos y confirmó que al crearlos siempre quedan a cargo del propio supervisor, sin asignarlos a analistas. Otros orígenes mantienen opciones. Se interpreta la condición en el alta, como preguntamos; no es prohibición nueva de toda reasignación posterior.
Revisa la migración y frontend adjuntos: rol vigente, dueño obligatorio, acceso por RPC directa y documental, reintentos, SQL NULL, ACL, regresiones. El wrapper documental llama a crear_lead_si_disponible y no se modifica. Gerencia continúa sin referido.
CodeGraph se usó primero, localiza LeadNuevo y store.crearLead; índice anterior incompleto para SQL. Los extractos definitivos adjuntos son del worktree limpio desde main 82a995 y pg_get_functiondef de producción. Código fuente baseline abajo. JEV solo ordenó contexto; no decide permisos ni fórmula.
Evidencia ejecutada: npm run check PASS, 434 archivos/6994 pruebas; E2E Docker completo 439 passed/26 skipped/0 failed (17.2 minutos). Pruebas SQL con estructura productiva actual y rollback; resultado íntegro abajo. Fixture Storage solo metadatos; no es prueba de upload ni Auth HTTP. Gate realidad real: 10 mediciones, cero errores; dos divergencias previas fuera de alcance: ventas de bajas y clientes sin domicilio.
No se ha escrito en producción. No afirmar release completo; Auth/PostgREST cloud, advisors y promoción están pendientes. Ledger registra PREPARADA.
Devuelve VERDICT/SUMMARY/FINDINGS P0-P3 con evidencia, gaps pertinentes, NEXT ACTIONS y CONFIDENCE. Una revisión única, de solo lectura.

LENTE auditor-rls:
---
name: auditor-rls
description: Auditor de seguridad RLS del esquema crm. Usar PROACTIVAMENTE sobre toda migración SQL nueva que toque tablas, policies, funciones o grants del CRM, antes del gate de test-rls.
tools: Read, Grep, Glob
---

Eres un auditor de seguridad de PostgreSQL/Supabase especializado en RLS, revisando
migraciones del esquema `crm` de CRM-Avance-Corp. Responde SIEMPRE en español.

ROLE: SECONDARY_REVIEWER. Sigue `.ai/REVIEW_PROTOCOL.md`: solo analiza, no
modifiques archivos, no ejecutes agentes ni delegues o inicies otro review.
El PRIMARY adjunta contexto de CodeGraph y decide si esta consulta corresponde
al nivel de riesgo y al presupuesto compartido de 0–2 reviews de la tarea.

Contexto fijo del proyecto:
- Tres roles con visibilidad escalonada: comercial (solo su cartera/subárbol),
  coordinador, gerencia/lector global (`private.es_lector_global()`).
- PII sensible en `crm.leads`: DNI, teléfono, fecha_nacimiento, genero, monto_estimado.
- Ledger inmutable `crm.lead_asignaciones`; log inmutable `crm.actividades`.
- Reglas no negociables: RLS ON al crear la tabla; deny-by-default; sin policy DELETE
  (soft-delete `activo=false`); nada de tocar objetos de `public`; toda tabla `crm.*`
  lleva el trigger de auditoría `private.log_audit_crm` (o `private.log_audit_sin_secretos`,
  con las columnas a enmascarar, si guarda secretos: tokens, claves, contraseñas o credenciales).
- ⚠️ `crm.leads` tiene grants POR COLUMNA: columna nueva sin GRANT explícito = invisible
  para PostgREST (falla silenciosa conocida del proyecto).

Checklist de auditoría sobre cada `.sql` bajo revisión:

1. **RLS**: ¿toda tabla nueva tiene `ENABLE ROW LEVEL SECURITY` en el mismo bloque?
   ¿Las policies son deny-by-default (nada de `USING (true)` sin justificación)? ¿Existe
   alguna policy DELETE? (prohibido).
2. **Fugas entre roles**: ¿puede un comercial ver leads/clientes fuera de su subárbol?
   ¿Un miembro con `activo=false` conserva lecturas? ¿Alguna vista o función expone PII
   cross-rol? Compara contra los patrones ya aceptados (`clientes_basicos_fn` gateada).
3. **SECURITY DEFINER**: cada función definer debe tener `SET search_path` fijo,
   justificación escrita y gate interno de rol. Vistas: preferir invoker + función
   definer gateada (patrón del proyecto); `security_definer_view` es hallazgo ERROR.
4. **Grants**: mínimos necesarios; en `crm.leads`, grants por columna presentes para
   toda columna nueva. ¿Se revoca lo que sobra (hardening)? ¿`service_role` pierde o gana
   EXECUTE sin que el ledger lo documente?
5. **Inmutabilidad**: ¿la migración debilita triggers de inmutabilidad de actividades o
   del ledger de asignaciones?
6. **`public` intocable**: cualquier statement sobre objetos de `public` es hallazgo
   BLOQUEANTE salvo que el ledger documente OK explícito de Miguel.
7. **Matriz de pruebas**: ¿`supabase/scripts/test-rls.mjs` cubre los casos nuevos
   (permitido Y denegado por rol)? Si no, señalar exactamente qué casos faltan.
8. **Ledger**: ¿`MIGRACIONES.md` tiene la fila nueva con estado honesto?

Formato de salida: `.ai/REVIEW_PROTOCOL.md`, con VERDICT, hallazgos P0–P3,
archivo:línea, evidencia, impacto y fix propuesto. Si no hay hallazgos,
decláralo explícitamente junto con qué verificaste. No modifiques archivos.

DIFF frontend y ledger:
diff --git a/CRM-Avance-Corp/app/e2e/acciones-demo.spec.ts b/CRM-Avance-Corp/app/e2e/acciones-demo.spec.ts
index c2515728..278f8243 100644
--- a/CRM-Avance-Corp/app/e2e/acciones-demo.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/acciones-demo.spec.ts
@@ -29,19 +29,25 @@ test('crear lead: alta rápida, toast "(demo)" y abre la ficha del nuevo lead',
   await expect(page.getByRole('dialog', { name: 'LEAD PRUEBA E2E' })).toBeVisible()
 })
 
-test('supervisor: crea un lead propio y lo convierte sin asignarlo a un analista', async ({ page }) => {
+for (const origen of ['oficina', 'referido']) {
+test(`supervisor: crea un lead propio de ${origen} y lo convierte sin asignarlo a un analista`, async ({ page }) => {
   await entrarDemo(page, 'Supervisor')
   await page.getByRole('button', { name: /nuevo lead/i }).click()
   const modal = page.getByRole('dialog', { name: 'Nuevo lead' })
   await modal.getByLabel('Nombre completo *').fill('LEAD PROPIO SUPERVISOR E2E')
   await modal.getByLabel('Teléfono *', { exact: true }).fill('987111333')
   await modal.getByLabel('Capital estimado *').fill('5000')
-  await modal.getByLabel('Origen *').selectOption('oficina')
   const responsable = modal.getByRole('combobox', { name: 'Responsable comercial' })
   await expect(responsable).toHaveValue('')
   await responsable.selectOption({ label: 'Yo — lead propio' })
   const responsableId = await responsable.inputValue()
   expect(responsableId).not.toBe('')
+  if (origen === 'referido') await responsable.selectOption('d-v1')
+  await modal.getByLabel('Origen *').selectOption(origen)
+  if (origen === 'referido') {
+    await expect(modal.getByLabel('Responsable comercial')).toBeDisabled()
+    await expect(modal.getByText('El referido queda a tu cargo automáticamente.')).toBeVisible()
+  }
   await modal.getByRole('button', { name: /crear lead/i }).click()
 
   const drawer = page.getByRole('dialog', { name: 'LEAD PROPIO SUPERVISOR E2E' })
@@ -62,6 +68,7 @@ test('supervisor: crea un lead propio y lo convierte sin asignarlo a un analista
   await page.getByRole('button',{name:'Cerrar',exact:true}).click()
   await expect(drawer.getByRole('button',{name:/Convertir a cliente/i})).toHaveCount(0)
 })
+}
 
 test('editar lead: cambia el monto y confirma con toast "(demo)"', async ({ page }) => {
   await entrarDemo(page, 'Analista')
diff --git a/CRM-Avance-Corp/app/src/components/app/lead-nuevo.test.tsx b/CRM-Avance-Corp/app/src/components/app/lead-nuevo.test.tsx
index 070fbe70..2ca0d7dc 100644
--- a/CRM-Avance-Corp/app/src/components/app/lead-nuevo.test.tsx
+++ b/CRM-Avance-Corp/app/src/components/app/lead-nuevo.test.tsx
@@ -200,12 +200,53 @@ describe('LeadNuevo — documento sin recortes', () => {
 })
 
 describe('LeadNuevo — responsable comercial del supervisor', () => {
+  it.each([true, false])('registra su referido automáticamente, sin analistas a cargo (demo=%s)', async (demo) => {
+    const { crearLead, actions } = montar({ rol: 'supervisor', demo })
+    completarBaseReal('referido')
+    expect(screen.queryByRole('combobox', { name: 'Responsable comercial' })).not.toBeInTheDocument()
+    expect(screen.getByLabelText('Responsable comercial')).toHaveValue(SESION.yo!.nombre_completo)
+    expect(screen.getByLabelText('Responsable comercial')).toBeDisabled()
+    expect(screen.getByText('El referido queda a tu cargo automáticamente.')).toBeInTheDocument()
+    fireEvent.click(screen.getByRole('button', { name: 'Crear lead' }))
+    await waitFor(() => expect(crearLead).toHaveBeenCalledWith(expect.objectContaining({
+      vendedor_id: SESION.yo!.id, origen: 'referido',
+    })))
+    await waitFor(() => expect(actions.abrirLead).toHaveBeenCalledWith('lead-nuevo-1'))
+  })
+
+  it('cambiar a Referido ignora el analista elegido y conserva esa selección para otros orígenes', async () => {
+    const miembro = { perfil_id: 'analista-equipo', nombre_completo: 'ANALISTA EQUIPO', rol_crm: 'vendedor', activo: true, supervisor_id: SESION.yo!.id } satisfies Miembro
+    const { crearLead } = montar({ rol: 'supervisor', demo: false, vendedores: [miembro] })
+    completarBaseReal('formulario')
+    fireEvent.change(screen.getByLabelText('Responsable comercial'), { target: { value: miembro.perfil_id } })
+    fireEvent.change(screen.getByLabelText('Origen *'), { target: { value: 'referido' } })
+    expect(screen.getByLabelText('Responsable comercial')).toBeDisabled()
+    fireEvent.change(screen.getByLabelText('Origen *'), { target: { value: 'oficina' } })
+    expect(screen.getByRole('combobox', { name: 'Responsable comercial' })).toHaveValue(miembro.perfil_id)
+    fireEvent.change(screen.getByLabelText('Origen *'), { target: { value: 'referido' } })
+    fireEvent.click(screen.getByRole('button', { name: 'Crear lead' }))
+    await waitFor(() => expect(crearLead).toHaveBeenCalledWith(expect.objectContaining({ vendedor_id: SESION.yo!.id, origen: 'referido' })))
+  })
+
+  it('si el servidor rechaza el referido, conserva el formulario y no anuncia éxito', async () => {
+    const { actions } = montar({ rol: 'supervisor', demo: false, crearLeadImpl: () => ({
+      ok: true, id: 'referido-fallido', persistido: Promise.resolve({ ok: false, error: 'Acceso CRM revocado' }),
+    }) })
+    completarBaseReal('referido')
+    fireEvent.click(screen.getByRole('button', { name: 'Crear lead' }))
+    await waitFor(() => expect(screen.getByText('Acceso CRM revocado')).toBeInTheDocument())
+    expect(actions.abrirLead).not.toHaveBeenCalled()
+    expect(toast.success).not.toHaveBeenCalled()
+    expect(screen.getByLabelText('Origen *')).toHaveValue('referido')
+    expect(screen.getByLabelText('Nombre completo *')).toHaveValue('ANA NUEVO LEAD')
+  })
+
   it.each([true, false])('crea un lead propio sin analistas a cargo (demo=%s)', async (demo) => {
     const { crearLead, actions } = montar({ rol: 'supervisor', demo })
     const responsable = screen.getByRole('combobox', { name: 'Responsable comercial' })
     expect(responsable).toHaveValue('')
     expect(screen.getByRole('option', { name: 'Yo — lead propio' })).toHaveValue(SESION.yo!.id)
-    expect(screen.queryByRole('option', { name: 'Referido' })).not.toBeInTheDocument()
+    expect(screen.getByRole('option', { name: 'Referido' })).toBeInTheDocument()
     completarBaseReal('oficina')
     fireEvent.change(responsable, { target: { value: SESION.yo!.id } })
     fireEvent.click(screen.getByRole('button', { name: 'Crear lead' }))
@@ -605,8 +646,7 @@ describe('LeadNuevo — disponibilidad P-048', () => {
 })
 
 describe('LeadNuevo — orígenes del alta manual (2026-09-01)', () => {
-  // LANDING y FORMULARIO también pueden declararse a mano. Referido conserva
-  // su regla propia: solo lo declara el analista, a su nombre.
+  // Referido se registra a nombre del analista o supervisor que lo consigue.
   it('el analista ve todos los orígenes activos', () => {
     montar()
     const opciones = [...screen.getByLabelText('Origen *').querySelectorAll('option')]
@@ -615,12 +655,12 @@ describe('LeadNuevo — orígenes del alta manual (2026-09-01)', () => {
     expect(opciones).toEqual(['referido', 'landing', 'formulario', 'formulario_3', 'oficina'])
   })
 
-  it('un supervisor ve LANDING y FORMULARIO, pero no Referido', () => {
+  it('un supervisor también puede registrar su Referido', () => {
     montar({ rol: 'supervisor' })
     const opciones = [...screen.getByLabelText('Origen *').querySelectorAll('option')]
       .map((opcion) => opcion.value)
       .filter((valor) => valor !== '')
-    expect(opciones).toEqual(['landing', 'formulario', 'formulario_3', 'oficina'])
+    expect(opciones).toEqual(['referido', 'landing', 'formulario', 'formulario_3', 'oficina'])
   })
 
   it('gerencia ve LANDING y FORMULARIO, pero tampoco Referido', () => {
diff --git a/CRM-Avance-Corp/app/src/components/app/lead-nuevo.tsx b/CRM-Avance-Corp/app/src/components/app/lead-nuevo.tsx
index 644e9612..82e233f6 100644
--- a/CRM-Avance-Corp/app/src/components/app/lead-nuevo.tsx
+++ b/CRM-Avance-Corp/app/src/components/app/lead-nuevo.tsx
@@ -269,6 +269,7 @@ function FormularioNuevoLead({
   const [moneda, setMoneda] = useState<Moneda>('PEN')
   const [categoria, setCategoria] = useState<CategoriaInteres | null>(null)
   const [vendedorId, setVendedorId] = useState('')
+  const referidoPropio = origen === 'referido'
   const [nota, setNota] = useState('')
   const [errores, setErrores] = useState<Record<string, string>>({})
   const [errorGeneral, setErrorGeneral] = useState<string | null>(null)
@@ -719,7 +720,7 @@ function FormularioNuevoLead({
         monto_estimado: montoNum,
         moneda,
         categoria_interes: categoria,
-        vendedor_id: puedeElegirVendedor ? vendedorId || null : (yo?.id ?? null),
+        vendedor_id: puedeElegirVendedor && !referidoPropio ? vendedorId || null : (yo?.id ?? null),
         nota: nota.trim() || null,
       })
       if (res.ok && res.id) {
@@ -1124,12 +1125,10 @@ function FormularioNuevoLead({
                 <option value="" disabled>
                   Selecciona…
                 </option>
-                {/* Decisión de Miguel (2026-09-01): LANDING y FORMULARIO
-                    también pueden declararse en el alta manual. Referido
-                    conserva su regla especial: solo lo registra el analista,
-                    a su propio nombre, porque esa etiqueta mueve su conversión. */}
+                {/* Referido: analista o supervisor, siempre a su propio nombre.
+                    El servidor vuelve a comprobar rol y responsabilidad. */}
                 {ORIGENES
-                  .filter((o) => o.k !== 'referido' || yo?.rol === 'vendedor')
+                  .filter((o) => o.k !== 'referido' || yo?.rol === 'vendedor' || yo?.rol === 'supervisor')
                   .map((o) => (
                     <option key={o.k} value={o.k}>
                       {o.label}
@@ -1174,7 +1173,7 @@ function FormularioNuevoLead({
             </Campo>
           </div>
           <Campo label="Responsable comercial" htmlFor="nl-vendedor">
-            {puedeElegirVendedor ? (
+            {puedeElegirVendedor && !referidoPropio ? (
               <Select
                 id="nl-vendedor"
                 value={vendedorId}
@@ -1192,7 +1191,7 @@ function FormularioNuevoLead({
               <>
                 <Input id="nl-vendedor" value={yo?.nombre_completo ?? ''} disabled readOnly />
                 <p className="text-[11px] text-muted-foreground">
-                  El lead se te asigna automáticamente.
+                  {referidoPropio ? 'El referido queda a tu cargo automáticamente.' : 'El lead se te asigna automáticamente.'}
                 </p>
               </>
             )}
diff --git a/CRM-Avance-Corp/app/src/lib/store-mutaciones.test.tsx b/CRM-Avance-Corp/app/src/lib/store-mutaciones.test.tsx
index 2337d9ff..21ef13ea 100644
--- a/CRM-Avance-Corp/app/src/lib/store-mutaciones.test.tsx
+++ b/CRM-Avance-Corp/app/src/lib/store-mutaciones.test.tsx
@@ -87,6 +87,26 @@ describe('mutaciones del store demo', () => {
   afterAll(() => vi.unstubAllEnvs())
 
   describe('crearLead', () => {
+    it.each(['vendedor', 'supervisor'] as const)('el %s registra su referido sin destino explícito y nunca lo deja en reparto', async (rol) => {
+      const { api, mutar } = await montarStore(rol)
+      const creado = mutar((a) => a.crearLead(inputBase({ origen: 'referido', vendedor_id: null })))
+      expect(creado.ok).toBe(true)
+      expect(api().lead(creado.id!)).toMatchObject({ origen: 'referido', vendedor_id: DEMO_YO[rol].id, asignado_supervisor_id: null })
+    })
+
+    it.each(['d-v1', 'd-v3', 'd-sup2'])('el supervisor no puede registrar el referido a nombre de %s', async (destino) => {
+      const { api, mutar } = await montarStore('supervisor')
+      const creado = mutar((a) => a.crearLead(inputBase({ origen: 'referido', vendedor_id: destino })))
+      expect(creado).toMatchObject({ ok: false, codigo: 'solo_autoasignar' })
+      expect(api().leads).toHaveLength(20)
+    })
+
+    it('Gerencia sigue sin poder registrar un referido aunque indique un analista', async () => {
+      const { api, mutar } = await montarStore('gerencia')
+      expect(mutar((a) => a.crearLead(inputBase({ origen: 'referido' })))).toMatchObject({ ok: false, codigo: 'sin_permiso' })
+      expect(api().leads).toHaveLength(20)
+    })
+
     it.each([['CE', '001234567'], ['PASAPORTE', 'AB12345678']] as const)('conserva %s en la identidad y rechaza un duplicado', async (tipo, numero) => {
       const { api, mutar } = await montarStore('vendedor')
       const creado = mutar((a) => a.crearLead(inputBase({ documento: { tipo, numero } })))
diff --git a/CRM-Avance-Corp/app/src/lib/store.tsx b/CRM-Avance-Corp/app/src/lib/store.tsx
index aff18364..cb4b928b 100644
--- a/CRM-Avance-Corp/app/src/lib/store.tsx
+++ b/CRM-Avance-Corp/app/src/lib/store.tsx
@@ -2408,6 +2408,16 @@ export function StoreProvider({ children }: { children: ReactNode }): JSX.Elemen
             error: 'Selecciona un canal concreto: Landing, Formulario, Formulario 3, Referido o Walking',
           }
         }
+        // Espejo de crear_lead_si_disponible: Referido solo nace a nombre
+        // del analista o supervisor que lo registra, también sin destino explícito.
+        const referidoPropio = input.origen === 'referido'
+        if (referidoPropio && rol !== 'vendedor' && rol !== 'supervisor') {
+          return { ok: false, codigo: 'sin_permiso', campo: 'origen', error: 'Solo analistas y supervisores pueden registrar sus propios referidos' }
+        }
+        if (referidoPropio && input.vendedor_id != null && input.vendedor_id !== yo?.id) {
+          return { ok: false, codigo: 'solo_autoasignar', error: 'El referido debe quedar a tu cargo' }
+        }
+        const vendedorSolicitado = referidoPropio ? yo?.id : input.vendedor_id
         // En creación ambos campos son obligatorios incluso en runtime. El
         // validador compartido acepta `undefined` a propósito porque también
         // valida PATCHes parciales; por eso este guard vive antes de llamarlo.
@@ -2467,7 +2477,7 @@ export function StoreProvider({ children }: { children: ReactNode }): JSX.Elemen
         // Espejo de la policy leads_insert: sin can('reasignar') el lead solo
         // puede nacer asignado a uno mismo (parkear es de supervisor/gerencia).
         // El gate de permisos corre ANTES del dedup: sin permiso no hay sondeo.
-        if (!can(rol, 'reasignar') && (input.vendedor_id ?? null) !== (yo?.id ?? null)) {
+        if (!can(rol, 'reasignar') && (vendedorSolicitado ?? null) !== (yo?.id ?? null)) {
           return {
             ok: false,
             codigo: 'solo_autoasignar',
@@ -2479,12 +2489,12 @@ export function StoreProvider({ children }: { children: ReactNode }): JSX.Elemen
         // Resuelve el analista SIN tragar ids inválidos (mismo criterio que reasignar()).
         let vendedor_id: string | null = null
         let vendedor_nombre: string | null = null
-        if (input.vendedor_id) {
-          const m = equipo.find((x) => x.perfil_id === input.vendedor_id)
+        if (vendedorSolicitado) {
+          const m = equipo.find((x) => x.perfil_id === vendedorSolicitado)
           if (m) {
             vendedor_id = m.perfil_id
             vendedor_nombre = m.nombre_completo
-          } else if (yo && input.vendedor_id === yo.id) {
+          } else if (yo && vendedorSolicitado === yo.id) {
             // Usuario (demo o sesión real) fuera de EQUIPO_DEMO: se auto-asigna igual.
             vendedor_id = yo.id
             vendedor_nombre = yo.nombre_completo
diff --git a/CRM-Avance-Corp/supabase/migrations/MIGRACIONES.md b/CRM-Avance-Corp/supabase/migrations/MIGRACIONES.md
index d31c7f67..a238efdc 100644
--- a/CRM-Avance-Corp/supabase/migrations/MIGRACIONES.md
+++ b/CRM-Avance-Corp/supabase/migrations/MIGRACIONES.md
@@ -1,3 +1,21 @@
+## 20261016174128 — Referidos propios de supervisores
+
+**PREPARADA; NO APLICADA EN PRODUCCIÓN.** Decisión de Miguel, 16/10/2026:
+el supervisor puede registrar referidos, siempre a su propio cargo al darlos
+de alta. `crm.crear_lead_si_disponible` admite Referido para analista o supervisor,
+normaliza el destino omitido al actor y rechaza cualquier destino ajeno, incluido
+un analista del equipo. Gerencia y los demás roles conservan el rechazo.
+
+Cambio protegido por huella productiva `b6ec8dddaa8ab81b9248a79f4de3a51f`;
+resultado `145b30a30e69807a1838c1b960a0675d`. Misma firma, ACL, SECURITY DEFINER,
+search_path, candados y revalidación de rol; el envoltorio documental hereda
+el control. No toca objetos de public, policies, datos, fórmulas ni sellos.
+Formulario y store reflejan la misma regla. No requiere regenerar tipos.
+
+Ver [kit local](../scripts/supervisores-referidos/LEEME.md),
+[alcance y verificación](../../docs/plans/supervisores-referidos/VERIFICACION.md).
+La promoción requiere rama Supabase, matriz Auth/PostgREST y advisors.
+
 ## 20261016162937 — Ventas propias de supervisores y aporte al equipo
 
 **APLICADA EN PRODUCCIÓN el 16/10/2026**, mediante merge de la rama validada.

ARCHIVO supabase/migrations/20261016174128_crm_supervisores_referidos_propios.sql
1: -- Referidos propios de supervisores. Decisión de Miguel, 16/10/2026.
2: -- Solo cambia la autorización del alta; conserva firma, ACL, candados,
3: -- idempotencia, validaciones, origen inmutable y revalidación de rol vigente.
4: begin;
5: set local lock_timeout = '5s';
6: do $cambio$
7: declare
8:   v_oid oid := to_regprocedure('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)');
9:   v_def text;
10: begin
11:   if (select md5(prosrc) from pg_catalog.pg_proc where oid=v_oid)
12:       is distinct from 'b6ec8dddaa8ab81b9248a79f4de3a51f' then
13:     raise exception 'PREFLIGHT: cambió el alta de leads revisada';
14:   end if;
15:   v_def := pg_get_functiondef(v_oid);
16:   v_def := replace(v_def, $antes$  -- D8 (2026-08-11) · «solo los vendedores a su propio nombre»: el ROL se
17:   -- cierra aquí; el NOMBRE (autoasignación) ya lo fuerza el bloque de destino
18:   -- de más abajo, que rechaza con 42501 cualquier p_vendedor_id ajeno.
19:   if p_origen = 'referido' and v_rol <> 'vendedor' then
20:     raise exception using
21:       errcode = '42501',
22:       message = 'Un referido lo registra el vendedor que lo consiguio, a su propio nombre';
23:   end if;
24: $antes$, $despues$  -- Referidos propios (Miguel, 16/10/2026): también Supervisión.
25:   -- El bloque de destino exige que el responsable sea el actor.
26:   if p_origen = 'referido' and v_rol not in ('vendedor', 'supervisor') then
27:     raise exception using
28:       errcode = '42501',
29:       message = 'Solo analistas y supervisores pueden registrar sus propios referidos';
30:   end if;
31: $despues$);
32:   v_def := replace(v_def, $antes$  -- El vendedor solo se autoasigna. Supervisor puede parkear en su propia
33:   -- bandeja o elegir dentro de su subarbol. Gerencia puede elegir cualquier
34:   -- destino operativo activo o dejar el lead en la cola global.
35:   if v_rol = 'vendedor' then$antes$, $despues$  -- Todo referido se autoasigna: un destino omitido también significa el actor.
36:   -- Los demás orígenes conservan el reparto de Supervisión y Gerencia.
37:   if v_rol = 'vendedor' or (v_rol = 'supervisor' and p_origen = 'referido') then$despues$);
38:   execute v_def;
39: end $cambio$;
40: commit;
41: 

ARCHIVO supabase/scripts/supervisores-referidos/vivo/crear_lead_si_disponible.sql
1: CREATE OR REPLACE FUNCTION crm.crear_lead_si_disponible(p_nombre_completo text, p_telefono text, p_origen text, p_monto_estimado numeric, p_moneda text, p_id uuid DEFAULT NULL::uuid, p_correo text DEFAULT NULL::text, p_dni text DEFAULT NULL::text, p_genero text DEFAULT NULL::text, p_fecha_nacimiento date DEFAULT NULL::date, p_distrito text DEFAULT NULL::text, p_etapa text DEFAULT 'nuevo'::text, p_categoria_interes text DEFAULT NULL::text, p_vendedor_id uuid DEFAULT NULL::uuid, p_nota text DEFAULT NULL::text, p_telefono_alternativo text DEFAULT NULL::text)
2:  RETURNS jsonb
3:  LANGUAGE plpgsql
4:  SECURITY DEFINER
5:  SET search_path TO ''
6:  SET lock_timeout TO '5s'
7: AS $function$
8: declare
9:   v_actor uuid := (select auth.uid());
10:   v_rol text;
11:   v_rol_actual text;
12:   v_id uuid := coalesce(p_id, pg_catalog.gen_random_uuid());
13:   v_nombre text := nullif(pg_catalog.btrim(p_nombre_completo), '');
14:   v_telefono text := private.normalizar_telefono(p_telefono);
15:   v_alt_bruto text := nullif(pg_catalog.btrim(p_telefono_alternativo), '');
16:   v_alt text;
17:   v_dni text := nullif(pg_catalog.btrim(p_dni), '');
18:   v_correo text := nullif(pg_catalog.btrim(p_correo), '');
19:   v_genero text := nullif(pg_catalog.btrim(p_genero), '');
20:   v_distrito text := nullif(pg_catalog.btrim(p_distrito), '');
21:   v_categoria text := nullif(pg_catalog.btrim(p_categoria_interes), '');
22:   v_nota text := nullif(pg_catalog.btrim(p_nota), '');
23:   v_vendedor uuid := p_vendedor_id;
24:   v_supervisor uuid;
25:   v_disponibilidad jsonb;
26:   v_existente crm.leads%rowtype;
27:   v_hoy_lima date := (pg_catalog.clock_timestamp() at time zone 'America/Lima')::date;
28: begin
29:   v_rol := private.rol_crm(v_actor);
30:   if v_actor is null or v_rol is null
31:      or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
32:     raise exception using errcode = '42501', message = 'Acceso CRM revocado';
33:   end if;
34: 
35:   if v_nombre is null then
36:     raise exception using errcode = '22023', message = 'El nombre es obligatorio';
37:   end if;
38:   if v_telefono is null or v_telefono !~ '^\+519[0-9]{8}$' then
39:     return pg_catalog.jsonb_build_object(
40:       'estado', 'error',
41:       'detalle', 'telefono_invalido'
42:     );
43:   end if;
44: 
45:   -- EL SEGUNDO NUMERO (opcion A). Admite celular, fijo peruano o cualquier pais,
46:   -- via la MISMA regla que el conector y el front. No participa del dedup: la
47:   -- identidad del lead sigue siendo `telefono`.
48:   if v_alt_bruto is not null then
49:     select c.e164 into v_alt from private.canonizar_contacto(v_alt_bruto) c;
50:     if v_alt is null then
51:       raise exception using
52:         errcode = '22023',
53:         message = 'Segundo telefono invalido: celular peruano, fijo peruano (014457890) o internacional con +codigo de pais';
54:     end if;
55:     -- Si repite al principal no aporta un canal nuevo: se guarda vacio en vez de
56:     -- enseñar el mismo numero dos veces en la ficha.
57:     if v_alt = v_telefono then
58:       v_alt := null;
59:     end if;
60:   end if;
61: 
62:   if v_dni is not null and v_dni !~ '^[0-9]{8}$' then
63:     raise exception using errcode = '22023', message = 'El DNI debe tener exactamente 8 digitos';
64:   end if;
65:   if p_origen not in ('referido', 'landing', 'formulario','formulario_3', 'oficina', 'otro', 'web', 'campania', 'whatsapp') then
66:     raise exception using errcode = '22023', message = 'Origen invalido';
67:   end if;
68: 
69:   -- Alta manual: cuatro canales concretos. Los heredados se leen,
70:   -- pero no se eligen al crear. Referido conserva sus permisos propios.
71:   if p_origen is null or p_origen not in ('referido', 'landing', 'formulario','formulario_3', 'oficina') then
72:     raise exception using
73:       errcode = '42501',
74:       message = 'Selecciona un canal concreto: Landing, Formulario, Formulario 3, Referido o Walking';
75:   end if;
76: 
77:   -- D8 (2026-08-11) · «solo los vendedores a su propio nombre»: el ROL se
78:   -- cierra aquí; el NOMBRE (autoasignación) ya lo fuerza el bloque de destino
79:   -- de más abajo, que rechaza con 42501 cualquier p_vendedor_id ajeno.
80:   if p_origen = 'referido' and v_rol <> 'vendedor' then
81:     raise exception using
82:       errcode = '42501',
83:       message = 'Un referido lo registra el vendedor que lo consiguio, a su propio nombre';
84:   end if;
85: 
86:   if p_etapa not in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada') then
87:     raise exception using errcode = '22023', message = 'Un lead no puede nacer en etapa terminal';
88:   end if;
89:   if p_monto_estimado is null
90:      or p_monto_estimado <= 0
91:      or p_monto_estimado > 9999999999.99
92:      or p_monto_estimado <> pg_catalog.trunc(p_monto_estimado, 2) then
93:     raise exception using errcode = '22023', message = 'Capital estimado invalido';
94:   end if;
95:   if p_moneda not in ('PEN', 'USD') then
96:     raise exception using errcode = '22023', message = 'Moneda invalida';
97:   end if;
98:   if v_genero is not null and v_genero not in ('F', 'M') then
99:     raise exception using errcode = '22023', message = 'Genero invalido';
100:   end if;
101:   if v_categoria is not null and v_categoria not in ('nuevo', 'renovacion', 'upgrade') then
102:     raise exception using errcode = '22023', message = 'Categoria de interes invalida';
103:   end if;
104:   if p_fecha_nacimiento is not null
105:      and (
106:        p_fecha_nacimiento < date '1900-01-01'
107:        or p_fecha_nacimiento > (v_hoy_lima - interval '18 years')::date
108:      ) then
109:     raise exception using errcode = '22023', message = 'El lead debe tener al menos 18 anos';
110:   end if;
111: 
112:   -- El vendedor solo se autoasigna. Supervisor puede parkear en su propia
113:   -- bandeja o elegir dentro de su subarbol. Gerencia puede elegir cualquier
114:   -- destino operativo activo o dejar el lead en la cola global.
115:   if v_rol = 'vendedor' then
116:     if v_vendedor is not null and v_vendedor is distinct from v_actor then
117:       raise exception using errcode = '42501', message = 'Solo puedes crear leads asignados a ti mismo';
118:     end if;
119:     v_vendedor := v_actor;
120:     v_supervisor := null;
121:   elsif v_vendedor is null and v_rol = 'supervisor' then
122:     v_supervisor := v_actor;
123:   else
124:     v_supervisor := null;
125:   end if;
126: 
127:   if v_vendedor is not null then
128:     if not exists (
129:       select 1
130:       from private.vendedor_ids_visibles(v_actor) visible(perfil_id)
131:       where visible.perfil_id = v_vendedor
132:     ) then
133:       raise exception using errcode = '42501', message = 'El analista destino esta fuera de tu ambito';
134:     end if;
135:     if not private.es_destino_crm_activo(
136:       v_vendedor,
137:       array['vendedor', 'supervisor']::text[]
138:     ) then
139:       raise exception using errcode = '22023', message = 'El analista destino no puede recibir leads';
140:     end if;
141:   end if;
142: 
143:   -- La identidad optimista funciona también como llave idempotente: si el
144:   -- commit llegó pero la respuesta de red se perdió, repetir el MISMO payload
145:   -- antes de una mutación posterior confirma el alta anterior en vez de
146:   -- pintarla como un contacto ajeno.
147:   perform pg_catalog.pg_advisory_xact_lock(
148:     pg_catalog.hashtextextended('avancecrm:lead:id:' || v_id::text, 0)
149:   );
150:   -- F2.b (b1): orden total documento -> identidad -> contactos. Con la bandera
151:   -- apagada el helper no toma ningún lock (paridad exacta).
152:   perform private.identidad_bloquear_documento('DNI', v_dni);
153:   perform private.identidad_bloquear_persona('DNI', v_dni);
154:   perform private.bloquear_contactos_lead(array[v_telefono], array[v_dni]);
155: 
156:   -- Un administrador puede desactivar la membresia mientras esta sesion
157:   -- espera un contacto. El permiso se vuelve a consultar DESPUES de todos
158:   -- los locks para que una sesion revocada no alcance a insertar al despertar.
159:   v_rol_actual := private.rol_crm(v_actor);
160:   if v_rol_actual is distinct from v_rol
161:      or v_rol_actual not in ('vendedor', 'supervisor', 'gerencia') then
162:     raise exception using errcode = '42501', message = 'Acceso CRM revocado';
163:   end if;
164: 
165:   if v_vendedor is not null then
166:     if not exists (
167:       select 1
168:       from private.vendedor_ids_visibles(v_actor) visible(perfil_id)
169:       where visible.perfil_id = v_vendedor
170:     ) then
171:       raise exception using errcode = '42501', message = 'El analista destino esta fuera de tu ambito';
172:     end if;
173:     if not private.es_destino_crm_activo(
174:       v_vendedor,
175:       array['vendedor', 'supervisor']::text[]
176:     ) then
177:       raise exception using errcode = '22023', message = 'El analista destino no puede recibir leads';
178:     end if;
179:   end if;
180: 
181:   select l.* into v_existente
182:   from crm.leads l
183:   where l.id = v_id;
184: 
185:   if found then
186:     if v_existente.creado_por is not distinct from v_actor
187:        and v_existente.nombre_completo is not distinct from v_nombre
188:        and v_existente.telefono is not distinct from v_telefono
189:        -- El segundo numero entra en la comparacion idempotente: sin esto, un
190:        -- reintento que SOLO cambia el alternativo se confirmaria como «ya
191:        -- creado» y el dato nuevo se perderia sin decir nada.
192:        and v_existente.telefono_alternativo is not distinct from v_alt
193:        and v_existente.correo is not distinct from v_correo
194:        and v_existente.dni is not distinct from v_dni
195:        and v_existente.genero is not distinct from v_genero
196:        and v_existente.fecha_nacimiento is not distinct from p_fecha_nacimiento
197:        and v_existente.distrito is not distinct from v_distrito
198:        and v_existente.origen is not distinct from p_origen
199:        and v_existente.etapa is not distinct from p_etapa
200:        and v_existente.monto_estimado is not distinct from p_monto_estimado
201:        and v_existente.moneda is not distinct from p_moneda
202:        and v_existente.categoria_interes is not distinct from v_categoria
203:        and v_existente.vendedor_id is not distinct from v_vendedor
204:        and v_existente.asignado_supervisor_id is not distinct from v_supervisor
205:        and v_existente.nota is not distinct from v_nota
206:        and v_existente.activo = true then
207:       return pg_catalog.jsonb_build_object('estado', 'creado', 'lead_id', v_id);
208:     end if;
209: 
210:     raise exception using
211:       errcode = '22023',
212:       message = 'El identificador de esta alta ya fue usado con datos distintos';
213:   end if;
214: 
215:   v_disponibilidad := private.verificar_disponibilidad_lead_impl(v_telefono, v_dni);
216: 
217:   if v_disponibilidad ->> 'estado' is distinct from 'libre' then
218:     return v_disponibilidad;
219:   end if;
220: 
221:   insert into crm.leads (
222:     id,
223:     nombre_completo,
224:     telefono,
225:     telefono_alternativo,
226:     correo,
227:     dni,
228:     genero,
229:     fecha_nacimiento,
230:     distrito,
231:     origen,
232:     etapa,
233:     monto_estimado,
234:     moneda,
235:     categoria_interes,
236:     vendedor_id,
237:     asignado_supervisor_id,
238:     nota,
239:     activo,
240:     creado_por,
241:     alta_manual
242:   ) values (
243:     v_id,
244:     v_nombre,
245:     v_telefono,
246:     v_alt,
247:     v_correo,
248:     v_dni,
249:     v_genero,
250:     p_fecha_nacimiento,
251:     v_distrito,
252:     p_origen,
253:     p_etapa,
254:     p_monto_estimado,
255:     p_moneda,
256:     v_categoria,
257:     v_vendedor,
258:     v_supervisor,
259:     v_nota,
260:     true,
261:     v_actor,
262:     true
263:   );
264: 
265:   return pg_catalog.jsonb_build_object('estado', 'creado', 'lead_id', v_id);
266: end;
267: $function$
268: ;
269: 

ARCHIVO supabase/scripts/supervisores-referidos/prueba.sql
1: create temporary table catalogo_antes as
2: select oid,prosrc,proacl,prosecdef,provolatile,proconfig from pg_proc
3: where pronamespace in ('crm'::regnamespace,'private'::regnamespace);
4: create temporary table leads_antes as select * from crm.leads;
5: create temporary table politicas_antes as select * from pg_policy;
6: set local role authenticated;
7: select pg_temp.sesion('sup1');
8: select pg_temp.rechaza('select pg_temp.alta(1)','42501','la regla anterior rechaza referidos del supervisor');
9: reset role;
10: 
11: -- MIGRACION
12: 
13: select pg_temp.exigir((select md5(prosrc) from pg_proc where oid='crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure)='145b30a30e69807a1838c1b960a0675d','huella nueva exacta');
14: select pg_temp.exigir(not exists(select 1 from catalogo_antes a join pg_proc p using(oid)
15:   where row(a.proacl,a.prosecdef,a.provolatile,a.proconfig) is distinct from row(p.proacl,p.prosecdef,p.provolatile,p.proconfig)),'ACL y atributos de todas las funciones intactos');
16: select pg_temp.exigir((select count(*) from catalogo_antes a join pg_proc p using(oid) where a.prosrc is distinct from p.prosrc)=1,'solo cambia una función');
17: select pg_temp.exigir(not exists((select * from pg_policy except select * from politicas_antes) union all (select * from politicas_antes except select * from pg_policy)),'ninguna policy cambia');
18: select pg_temp.exigir(not exists(select * from crm.leads except select * from leads_antes),'migración no reescribe leads');
19: 
20: set local role authenticated;
21: select pg_temp.sesion('sup1');
22: select pg_temp.exigir(pg_temp.alta(1)->>'estado'='creado','supervisor crea referido sin destino');
23: select pg_temp.exigir((select vendedor_id=auth.uid() and creado_por=auth.uid() and asignado_supervisor_id is null and origen='referido' and alta_manual from crm.leads where id=md5('referido-1')::uuid),'referido conserva autor y dueño, fuera de reparto');
24: select pg_temp.exigir(pg_temp.alta(1,'referido',auth.uid())->>'lead_id'=md5('referido-1')::uuid::text,'reintento con dueño explícito confirma la misma alta');
25: select pg_temp.exigir((select count(*) from crm.leads where id=md5('referido-1')::uuid)=1,'reintento no duplica');
26: select pg_temp.exigir(pg_temp.alta(2,'referido',auth.uid())->>'estado'='creado','supervisor crea referido con dueño propio explícito');
27: select pg_temp.rechaza($q$select pg_temp.alta(3,'referido',(select id from actores where clase='vend1'))$q$,'42501','rechaza referido para analista propio');
28: select pg_temp.rechaza($q$select pg_temp.alta(3,'referido',(select id from actores where clase='vend2'))$q$,'42501','rechaza referido para analista ajeno');
29: select pg_temp.rechaza($q$select pg_temp.alta(3,'referido',(select id from actores where clase='sup2'))$q$,'42501','rechaza referido para otro supervisor');
30: select pg_temp.rechaza($q$select pg_temp.alta(1,'oficina')$q$,'22023','misma llave con otro origen rechazada');
31: select pg_temp.rechaza($q$update crm.leads set origen='oficina' where id=md5('referido-1')::uuid$q$,'P0409','origen del referido permanece inmutable');
32: select pg_temp.rechaza($q$insert into crm.leads(nombre_completo,telefono,origen,vendedor_id) values('INTENTO DIRECTO','900009999','referido',(select id from actores where clase='vend1'))$q$,'42501','INSERT directo sigue revocado');
33: 
34: do $otros$ declare origen text; n integer:=10; r jsonb; begin
35:   foreach origen in array array['oficina','landing','formulario','formulario_3'] loop
36:     r:=pg_temp.alta(n,origen,(select id from actores where clase='vend1'));
37:     perform pg_temp.exigir(r->>'estado'='creado',origen||' conserva asignación al equipo');
38:     n:=n+1;
39:     r:=pg_temp.alta(n,origen);
40:     perform pg_temp.exigir((select vendedor_id is null and asignado_supervisor_id=auth.uid() from crm.leads where id=(r->>'lead_id')::uuid),origen||' conserva bandeja de reparto');
41:     n:=n+1;
42:   end loop;
43: end $otros$;
44: select pg_temp.sesion('sin_equipo');
45: select pg_temp.exigir(pg_temp.alta(30)->>'estado'='creado','supervisor sin analistas crea su referido');
46: select pg_temp.sesion('vend1');
47: select pg_temp.exigir(pg_temp.alta(31)->>'estado'='creado','analista conserva su referido propio');
48: select pg_temp.rechaza($q$select pg_temp.alta(32,'referido',(select id from actores where clase='sup1'))$q$,'42501','analista no crea referido para supervisor');
49: select pg_temp.exigir(not exists(select 1 from crm.leads where id=md5('referido-1')::uuid),'analista no lee referido del supervisor');
50: select pg_temp.sesion('sup2');
51: select pg_temp.exigir(not exists(select 1 from crm.leads where id=md5('referido-1')::uuid),'otro supervisor no lee el referido');
52: do $roles$ declare rol text; begin
53:   foreach rol in array array['gerencia','coordinador','directorio','cliente','desconocido'] loop
54:     perform pg_temp.sesion(rol);
55:     perform pg_temp.rechaza('select pg_temp.alta(40)','42501','referido denegado a '||rol);
56:   end loop;
57: end $roles$;
58: 
59: -- DNI, CE y pasaporte pasan por el mismo control de autoría.
60: select pg_temp.sesion('sup1');
61: do $documentos$ declare tipo text; n integer:=50; r jsonb; datos jsonb; begin
62:   foreach tipo in array array['DNI','CE','PASAPORTE'] loop
63:     datos:=jsonb_build_object('id',md5('referido-'||n)::uuid,'nombre_completo','REFERIDO DOCUMENTADO',
64:       'telefono',(900000000+n)::text,'origen','referido','monto_estimado',20000,'moneda','PEN');
65:     r:=crm.crear_lead_documento_fn(datos,tipo,case tipo when 'CE' then '009616050' else (96000000+n)::text end);
66:     perform pg_temp.exigir(r->>'estado'='creado','alta con documento '||tipo);
67:     perform pg_temp.exigir((select vendedor_id=auth.uid() and creado_por=auth.uid() and asignado_supervisor_id is null from crm.leads where id=(r->>'lead_id')::uuid),'dueño propio con documento '||tipo);
68:     perform pg_temp.exigir(crm.crear_lead_documento_fn(datos,tipo,case tipo when 'CE' then '009616050' else (96000000+n)::text end)=r,'reintento documental '||tipo);
69:     perform pg_temp.rechaza(format('select crm.crear_lead_documento_fn(%L::jsonb,%L,%L)',
70:       datos||jsonb_build_object('vendedor_id',(select id from actores where clase='vend1')),tipo,
71:       case tipo when 'CE' then '009616050' else (96000000+n)::text end),'42501','envoltorio no permite otro dueño: '||tipo);
72:     n:=n+1;
73:   end loop;
74: end $documentos$;
75: select pg_temp.exigir(crm.crear_lead_si_disponible('REFERIDO DUPLICADO','900000001','referido',20000,'PEN')->>'estado'<>'creado','otro id no duplica el mismo contacto');
76: reset role;
77: 
78: savepoint baja_perfil;
79: select pg_temp.sesion('desconocido');
80: select set_config('crm.op_privilegiada','on',true);
81: update public.perfiles set activo=false where id=(select id from actores where clase='sup1');
82: select set_config('crm.op_privilegiada','',true);
83: select pg_temp.exigir((select not activo from public.perfiles where id=(select id from actores where clase='sup1')),'fixture confirma baja de perfil');
84: set local role authenticated;
85: select pg_temp.sesion('sup1');
86: select pg_temp.rechaza('select pg_temp.alta(60)','42501','perfil inactivo no crea referido con mismo JWT');
87: rollback to baja_perfil;
88: savepoint baja_equipo;
89: select pg_temp.sesion('desconocido');
90: select set_config('crm.op_privilegiada','on',true);
91: update crm.equipo set activo=false where perfil_id=(select id from actores where clase='para_baja');
92: select set_config('crm.op_privilegiada','',true);
93: select pg_temp.exigir((select not activo from crm.equipo where perfil_id=(select id from actores where clase='para_baja')),'fixture confirma baja de membresía');
94: set local role authenticated;
95: select pg_temp.sesion('sup1');
96: select pg_temp.sesion('para_baja');
97: select pg_temp.rechaza('select pg_temp.alta(61)','42501','membresía inactiva no crea referido con mismo JWT');
98: rollback to baja_equipo;
99: savepoint cambio_rol;
100: select pg_temp.sesion('desconocido');
101: select set_config('crm.op_privilegiada','on',true);
102: update crm.equipo set rol_crm='gerencia' where perfil_id=(select id from actores where clase='para_cambio');
103: select set_config('crm.op_privilegiada','',true);
104: set local role authenticated;
105: select pg_temp.sesion('para_cambio');
106: select pg_temp.rechaza('select pg_temp.alta(62)','42501','cambiar a Gerencia retira el alta de referido con el mismo JWT');
107: rollback to cambio_rol;
108: 
109: set local role supabase_admin;
110: -- ACL productiva leída el 16/10: postgres tiene ALL WITH GRANT OPTION en Storage.
111: grant all on storage.buckets,storage.objects to postgres with grant option;
112: insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
113: values('f4-comprobantes','f4-comprobantes',false,10485760,array['application/pdf']) on conflict(id) do nothing;
114: set local role postgres;
115: select pg_temp.sesion('sup1');
116: do $conversion$ declare r jsonb; c jsonb; persona uuid; solicitud uuid:=gen_random_uuid(); datos jsonb; begin
117:   execute 'set local role authenticated';
118:   persona:=(crm.preparar_persona_lead_inversion_fn(md5('referido-1')::uuid,'DNI','96000001','REFERIDO SINTETICO')->>'inversionista_id')::uuid;
119:   datos:=jsonb_build_object('inversionista_id',persona,'lead_id',md5('referido-1')::uuid,'empresa','qorilazo',
120:     'monto',20000,'moneda','PEN','fecha_comercial',current_date,'vence_en',(current_date+interval '12 months')::date,
121:     'plazo_meses',12,'tasa_anual',15,'numero_transaccion','REF-SUP-QA','referencia','CERTIFICADO FICTICIO',
122:     'evidencia',jsonb_build_object('ruta',persona||'/'||solicitud||'/comprobante.pdf'));
123:   perform crm.preparar_inversion_fn(solicitud,datos);
124:   execute 'set local role supabase_admin';
125:   -- Solo metadatos sintéticos de Storage; las RPC comerciales se invocan como authenticated.
126:   insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',datos#>>'{evidencia,ruta}',
127:     '{"size":128,"mimetype":"application/pdf"}'::jsonb);
128:   execute 'set local role authenticated';
129:   r:=crm.confirmar_inversion_revisada_fn(solicitud,0);
130:   perform pg_temp.exigir(r->>'inversion_id' is not null,'referido del supervisor se convierte por la puerta compartida vigente');
131:   perform pg_temp.exigir(crm.confirmar_inversion_revisada_fn(solicitud,0)->>'inversion_id'=r->>'inversion_id','reintento de conversión no duplica inversión');
132:   perform pg_temp.exigir((select etapa='convertido' and vendedor_id=auth.uid() from crm.leads where id=md5('referido-1')::uuid),'conversión conserva el supervisor');
133:   c:=crm.cartera_inversionistas_filtrada_fn(p_texto=>'96000001');
134:   perform pg_temp.exigir(c->'filas'->0->>'responsable_id'=auth.uid()::text,'Cartera conserva responsable del referido');
135:   c:=crm.cumplimiento_metas_fn(date_trunc('month',current_date)::date);
136:   perform pg_temp.exigir(exists(select 1 from jsonb_array_elements(c->'fuera_ranking') f,
137:     jsonb_array_elements(f->'detalles') d where f->>'persona_id'=auth.uid()::text
138:     and d->>'moneda'='PEN' and d->>'categoria'='nuevo' and (d->>'capital_real')::numeric=20000
139:     and (d->>'contratos_real')::int=1),'venta referida aparece en producción propia para aportar al equipo');
140: end $conversion$;
141: reset role;
142: 
143: -- REVERSA
144: 
145: select pg_temp.exigir((select md5(prosrc) from pg_proc where oid='crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure)='b6ec8dddaa8ab81b9248a79f4de3a51f','reversa restaura función exacta');
146: set local role authenticated;
147: select pg_temp.sesion('sup1');
148: select pg_temp.exigir(exists(select 1 from crm.leads where id=md5('referido-1')::uuid),'reversa conserva referidos creados');
149: select pg_temp.rechaza('select pg_temp.alta(70)','42501','reversa restaura rechazo anterior');
150: reset role;
151: 
152: -- REAPLICACION
153: 
154: set local role authenticated;
155: select pg_temp.sesion('sup1');
156: select pg_temp.exigir(pg_temp.alta(70)->>'estado'='creado','reaplicación habilita de nuevo el alta propia');
157: reset role;

ARCHIVO supabase/scripts/supervisores-referidos/semilla.sql
1: -- Banco exclusivo vacío, estructura productiva, datos sintéticos y ROLLBACK.
2: do $guardia$ begin
3:   if current_database() <> 'supervisores_referidos_20261016'
4:      or current_user <> 'postgres'
5:      or current_setting('session_replication_role') <> 'origin'
6:      or exists(select 1 from crm.equipo)
7:      or exists(select 1 from crm.leads)
8:      or exists(select 1 from public.contratos) then
9:     raise exception 'Solo se permite el banco local exclusivo y vacío';
10:   end if;
11: end $guardia$;
12: 
13: insert into crm.productos_inversion(codigo,es_legacy,permite_altas_legacy,estado,archivado_en)
14: values('HISTORICO-SIN-CATALOGO',true,true,'archivado',now());
15: insert into crm.sla_politicas(version,vigente_desde,zona_horaria,tipo_reloj,primera_gestion_minutos,primer_contacto_minutos)
16: values(1,'2000-01-01','America/Lima','corrido',60,120);
17: insert into crm.sla_politica_etapas(politica_id,etapa,maximo_minutos)
18: select id,'nuevo',120 from crm.sla_politicas;
19: insert into crm.conversion_pesos(vigente_desde,peso_referido,peso_renovacion,nota)
20: values('2000-01-01',0.15,0.15,'Prueba sintética de referidos');
21: insert into crm.multiempresa_flags(nombre,activo)
22: values('resolver_en_puertas',true),('inversiones_escritura',true),('ficha_360_neutral',true),
23:   ('postventa_neutral',true),('potencial_lead',true),('metricas_multiempresa_sombra',false);
24: insert into crm.empresas(clave,nombre_legal,nombre_visible,activa,monedas,crea_contrato_avance,requiere_portal,exige_numero_transaccion,fuente_capital)
25: values('qorilazo','Cooperativa sintética','Cooperativa sintética',true,array['PEN'],false,false,true,'cierres_externos');
26: insert into crm.politica_rentabilidad(version,vigente_desde,tasa_base_nueva,tope_tecnico,vigencia_solicitud_dias,modo)
27: values(1,'2000-01-01',15,28,1,'enforcement');
28: 
29: create temporary table actores(clase text primary key,id uuid not null default gen_random_uuid());
30: insert into actores(clase) values('gerencia'),('coordinador'),('directorio'),('sup1'),('sup2'),('sin_equipo'),('para_baja'),('para_cambio'),('vend1'),('vend2'),('cliente');
31: grant select on actores to authenticated;
32: insert into auth.users(id,email) select id,id::text||'@referidos.example.invalid' from actores;
33: insert into public.perfiles(id,nombre_completo,correo,rol,activo,tipo_documento,debe_cambiar_password,titular_distinto,titular_distinto_usd)
34: select id,'PRUEBA '||clase,id::text||'@referidos.example.invalid',
35:   case when clase='cliente' then 'cliente' when clase='directorio' then 'directorio'
36:     when clase in ('vend1','vend2') then 'analista' else 'comercial' end,
37:   true,'DNI',false,false,false from actores;
38: insert into crm.equipo(perfil_id,rol_crm,activo)
39: select id,case when clase in ('sup1','sup2','sin_equipo','para_baja','para_cambio') then 'supervisor' else clase end,true
40: from actores where clase in ('gerencia','directorio','coordinador','sup1','sup2','sin_equipo','para_baja','para_cambio');
41: insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
42: select a.id,'vendedor',s.id,true from actores a join actores s
43:   on s.clase=case a.clase when 'vend1' then 'sup1' when 'vend2' then 'sup2' end
44: where a.clase in ('vend1','vend2');
45: 
46: create function pg_temp.sesion(p_clase text) returns void language sql as $f$
47:   select set_config('request.jwt.claim.sub',coalesce((select id::text from actores where clase=p_clase),''),true);
48:   select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from actores where clase=p_clase),'role','authenticated')::text,true);
49: $f$;
50: create function pg_temp.exigir(p_ok boolean,p_mensaje text) returns void language plpgsql as $f$
51: begin
52:   if p_ok is not true then raise exception 'FAIL: %',p_mensaje; end if;
53:   raise notice 'PASS: %',p_mensaje;
54: end $f$;
55: create function pg_temp.rechaza(p_sql text,p_codigo text,p_mensaje text) returns void language plpgsql as $f$
56: declare codigo text;
57: begin
58:   begin execute p_sql; exception when others then get stacked diagnostics codigo=returned_sqlstate; end;
59:   perform pg_temp.exigir(codigo=p_codigo,p_mensaje||' ['||coalesce(codigo,'sin rechazo')||']');
60: end $f$;
61: create function pg_temp.alta(p_n integer,p_origen text default 'referido',p_destino uuid default null) returns jsonb language sql as $f$
62:   select crm.crear_lead_si_disponible(p_nombre_completo=>'REFERIDO SINTETICO',p_telefono=>(900000000+p_n)::text,
63:     p_origen=>p_origen,p_monto_estimado=>20000,p_moneda=>'PEN',p_id=>md5('referido-'||p_n)::uuid,
64:     p_dni=>(96000000+p_n)::text,p_vendedor_id=>p_destino);
65: $f$;

ARCHIVO supabase/scripts/supervisores-referidos/ensayar.py
1: """Prueba transaccional en banco local exclusivo; nunca acepta producción."""
2: from pathlib import Path
3: import subprocess
4: import sys
5: 
6: BASE = Path(__file__).resolve().parent
7: MIGRACION = BASE.parent.parent / 'migrations/20261016174128_crm_supervisores_referidos_propios.sql'
8: def cuerpo(ruta):
9:     lineas = ruta.read_text().splitlines()
10:     assert lineas.count('begin;') == 1 and lineas.count('commit;') == 1
11:     return '\n'.join(l for l in lineas if l not in ('begin;', 'commit;'))
12: 
13: sql = "begin; set local role postgres; set local statement_timeout='120s'; set local jit=off; set local timezone='America/Lima';\n"
14: sql += (BASE / 'semilla.sql').read_text()
15: sql += (BASE / 'prueba.sql').read_text().replace('-- MIGRACION', cuerpo(MIGRACION)).replace('-- REVERSA', cuerpo(BASE / 'reversa.sql')).replace('-- REAPLICACION', cuerpo(MIGRACION))
16: sql += "\nrollback;\ndo $$ begin if exists(select 1 from crm.leads) or exists(select 1 from crm.equipo) then raise exception 'El banco no quedó vacío'; end if; end $$;\n"
17: if '--sql' in sys.argv:
18:     print(sql)
19:     raise SystemExit(0)
20: r = subprocess.run(['docker','exec','-i','avancecorp-coordinacion-pg-actual','psql','-X','-qAt',
21:     '-U','supabase_admin','-d','supervisores_referidos_20261016','-v','ON_ERROR_STOP=1','-f','-'],
22:     input=sql,text=True,capture_output=True)
23: print('\n'.join(l for l in r.stderr.splitlines() if 'PASS:' in l) if r.returncode == 0 else r.stderr[-10000:])
24: raise SystemExit(r.returncode)

ARCHIVO supabase/scripts/supervisores-referidos/reversa.sql
1: -- Reversa sin borrar referidos ya creados. Revisar dependencias antes de publicar.
2: begin;
3: set local lock_timeout = '5s';
4: do $reversa$
5: declare
6:  v_oid oid := to_regprocedure('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)');
7:  v_def text;
8: begin
9:  if (select md5(prosrc) from pg_catalog.pg_proc where oid=v_oid)
10:      is distinct from '145b30a30e69807a1838c1b960a0675d' then
11:    raise exception 'PREFLIGHT: cambió el alta de referidos revisada';
12:  end if;
13:  v_def := pg_get_functiondef(v_oid);
14:  v_def := replace(v_def, $antes$  -- Referidos propios (Miguel, 16/10/2026): también Supervisión.
15:   -- El bloque de destino exige que el responsable sea el actor.
16:   if p_origen = 'referido' and v_rol not in ('vendedor', 'supervisor') then
17:     raise exception using
18:       errcode = '42501',
19:       message = 'Solo analistas y supervisores pueden registrar sus propios referidos';
20:   end if;
21: $antes$, $despues$  -- D8 (2026-08-11) · «solo los vendedores a su propio nombre»: el ROL se
22:   -- cierra aquí; el NOMBRE (autoasignación) ya lo fuerza el bloque de destino
23:   -- de más abajo, que rechaza con 42501 cualquier p_vendedor_id ajeno.
24:   if p_origen = 'referido' and v_rol <> 'vendedor' then
25:     raise exception using
26:       errcode = '42501',
27:       message = 'Un referido lo registra el vendedor que lo consiguio, a su propio nombre';
28:   end if;
29: $despues$);
30:  v_def := replace(v_def, $antes$  -- Todo referido se autoasigna: un destino omitido también significa el actor.
31:   -- Los demás orígenes conservan el reparto de Supervisión y Gerencia.
32:   if v_rol = 'vendedor' or (v_rol = 'supervisor' and p_origen = 'referido') then$antes$, $despues$  -- El vendedor solo se autoasigna. Supervisor puede parkear en su propia
33:   -- bandeja o elegir dentro de su subarbol. Gerencia puede elegir cualquier
34:   -- destino operativo activo o dejar el lead en la cola global.
35:   if v_rol = 'vendedor' then$despues$);
36:  execute v_def;
37: end $reversa$;
38: commit;
39: 

ARCHIVO supabase/scripts/supervisores-referidos/LEEME.md
1: # Referidos propios de supervisores
2: 
3: Decisión de Miguel, 16/10/2026: al crear un referido, su responsable siempre es
4: el supervisor que lo registra. Un destino omitido se convierte en su propio UUID;
5: un destino explícito distinto se rechaza, incluso si pertenece a su equipo.
6: 
7: El cambio solo amplía el alta de Referido para Supervisión. Los demás orígenes,
8: la gestión posterior del lead, el origen inmutable, la conversión, las metas y
9: el ranking conservan sus reglas. No crea una meta individual nueva.
10: 
11: ## Ensayo local
12: 
13: Desde la raíz CRM:
14: 
15: ```sh
16: python3 supabase/scripts/supervisores-referidos/ensayar.py
17: ```
18: 
19: Solo acepta la base vacía `supervisores_referidos_20261016` del contenedor
20: `avancecorp-coordinacion-pg-actual`. Se restauró la estructura productiva sin
21: datos, leída el 16/10/2026. `semilla.sql` inserta únicamente fixtures sintéticos.
22: El administrador prepara fixtures/DDL y los metadatos de un comprobante; todas
23: las operaciones comerciales y pruebas de acceso usan `SET LOCAL ROLE authenticated`
24: con identidades distintas. Triggers y RLS permanecen activos. Al final revierte
25: datos y DDL y exige que el banco siga vacío.
26: 
27: `prueba.sql` cubre permisos de roles, autor/dueño, ausencia de bandeja, supervisor
28: sin equipo, intentos de asignar a terceros, DNI/CE/pasaporte, idempotencia,
29: duplicados, INSERT directo revocado, lectura ajena, baja de perfil y membresía,
30: cambio de rol, asignación original de otros canales, conversión cooperativa por
31: el formulario compartido actual, atribución en Cartera y producción propia,
32: reversa/reaplicación y paridad de ACL/policies.
33: 
34: `vivo/crear_lead_si_disponible.sql` conserva la definición previa cotejada con
35: producción. `reversa.sql` solo acepta la huella de esta migración y restaura
36: exactamente esa definición. No borra los referidos que ya se hubieran registrado.
37: 
38: ## Promoción
39: 
40: NO aplicar directamente a producción. Validar sobre rama Supabase, con Auth y
41: PostgREST reales, comparar advisors y promover por merge. Publicar el frontend
42: desde main verificado siguiendo el procedimiento de release. Una sesión web
43: anterior seguirá sin ofrecer la opción hasta recargarse.

ARCHIVO docs/plans/supervisores-referidos/sql-local.log
1: psql:<stdin>:74: NOTICE:  PASS: la regla anterior rechaza referidos del supervisor [42501]
2: psql:<stdin>:117: NOTICE:  PASS: huella nueva exacta
3: psql:<stdin>:119: NOTICE:  PASS: ACL y atributos de todas las funciones intactos
4: psql:<stdin>:120: NOTICE:  PASS: solo cambia una función
5: psql:<stdin>:121: NOTICE:  PASS: ninguna policy cambia
6: psql:<stdin>:122: NOTICE:  PASS: migración no reescribe leads
7: psql:<stdin>:126: NOTICE:  PASS: supervisor crea referido sin destino
8: psql:<stdin>:127: NOTICE:  PASS: referido conserva autor y dueño, fuera de reparto
9: psql:<stdin>:128: NOTICE:  PASS: reintento con dueño explícito confirma la misma alta
10: psql:<stdin>:129: NOTICE:  PASS: reintento no duplica
11: psql:<stdin>:130: NOTICE:  PASS: supervisor crea referido con dueño propio explícito
12: psql:<stdin>:131: NOTICE:  PASS: rechaza referido para analista propio [42501]
13: psql:<stdin>:132: NOTICE:  PASS: rechaza referido para analista ajeno [42501]
14: psql:<stdin>:133: NOTICE:  PASS: rechaza referido para otro supervisor [42501]
15: psql:<stdin>:134: NOTICE:  PASS: misma llave con otro origen rechazada [22023]
16: psql:<stdin>:135: NOTICE:  PASS: origen del referido permanece inmutable [P0409]
17: psql:<stdin>:136: NOTICE:  PASS: INSERT directo sigue revocado [42501]
18: psql:<stdin>:147: NOTICE:  PASS: oficina conserva asignación al equipo
19: psql:<stdin>:147: NOTICE:  PASS: oficina conserva bandeja de reparto
20: psql:<stdin>:147: NOTICE:  PASS: landing conserva asignación al equipo
21: psql:<stdin>:147: NOTICE:  PASS: landing conserva bandeja de reparto
22: psql:<stdin>:147: NOTICE:  PASS: formulario conserva asignación al equipo
23: psql:<stdin>:147: NOTICE:  PASS: formulario conserva bandeja de reparto
24: psql:<stdin>:147: NOTICE:  PASS: formulario_3 conserva asignación al equipo
25: psql:<stdin>:147: NOTICE:  PASS: formulario_3 conserva bandeja de reparto
26: psql:<stdin>:149: NOTICE:  PASS: supervisor sin analistas crea su referido
27: psql:<stdin>:151: NOTICE:  PASS: analista conserva su referido propio
28: psql:<stdin>:152: NOTICE:  PASS: analista no crea referido para supervisor [42501]
29: psql:<stdin>:153: NOTICE:  PASS: analista no lee referido del supervisor
30: psql:<stdin>:155: NOTICE:  PASS: otro supervisor no lee el referido
31: psql:<stdin>:161: NOTICE:  PASS: referido denegado a gerencia [42501]
32: psql:<stdin>:161: NOTICE:  PASS: referido denegado a coordinador [42501]
33: psql:<stdin>:161: NOTICE:  PASS: referido denegado a directorio [42501]
34: psql:<stdin>:161: NOTICE:  PASS: referido denegado a cliente [42501]
35: psql:<stdin>:161: NOTICE:  PASS: referido denegado a desconocido [42501]
36: psql:<stdin>:178: NOTICE:  PASS: alta con documento DNI
37: psql:<stdin>:178: NOTICE:  PASS: dueño propio con documento DNI
38: psql:<stdin>:178: NOTICE:  PASS: reintento documental DNI
39: psql:<stdin>:178: NOTICE:  PASS: envoltorio no permite otro dueño: DNI [42501]
40: psql:<stdin>:178: NOTICE:  PASS: alta con documento CE
41: psql:<stdin>:178: NOTICE:  PASS: dueño propio con documento CE
42: psql:<stdin>:178: NOTICE:  PASS: reintento documental CE
43: psql:<stdin>:178: NOTICE:  PASS: envoltorio no permite otro dueño: CE [42501]
44: psql:<stdin>:178: NOTICE:  PASS: alta con documento PASAPORTE
45: psql:<stdin>:178: NOTICE:  PASS: dueño propio con documento PASAPORTE
46: psql:<stdin>:178: NOTICE:  PASS: reintento documental PASAPORTE
47: psql:<stdin>:178: NOTICE:  PASS: envoltorio no permite otro dueño: PASAPORTE [42501]
48: psql:<stdin>:179: NOTICE:  PASS: otro id no duplica el mismo contacto
49: psql:<stdin>:187: NOTICE:  PASS: fixture confirma baja de perfil
50: psql:<stdin>:190: NOTICE:  PASS: perfil inactivo no crea referido con mismo JWT [42501]
51: psql:<stdin>:197: NOTICE:  PASS: fixture confirma baja de membresía
52: psql:<stdin>:201: NOTICE:  PASS: membresía inactiva no crea referido con mismo JWT [42501]
53: psql:<stdin>:210: NOTICE:  PASS: cambiar a Gerencia retira el alta de referido con el mismo JWT [42501]
54: psql:<stdin>:244: NOTICE:  PASS: referido del supervisor se convierte por la puerta compartida vigente
55: psql:<stdin>:244: NOTICE:  PASS: reintento de conversión no duplica inversión
56: psql:<stdin>:244: NOTICE:  PASS: conversión conserva el supervisor
57: psql:<stdin>:244: NOTICE:  PASS: Cartera conserva responsable del referido
58: psql:<stdin>:244: NOTICE:  PASS: venta referida aparece en producción propia para aportar al equipo
59: psql:<stdin>:285: NOTICE:  PASS: reversa restaura función exacta
60: psql:<stdin>:288: NOTICE:  PASS: reversa conserva referidos creados
61: psql:<stdin>:289: NOTICE:  PASS: reversa restaura rechazo anterior [42501]
62: psql:<stdin>:334: NOTICE:  PASS: reaplicación habilita de nuevo el alta propia

ARCHIVO docs/plans/supervisores-referidos/jev-contexto.json
1: {
2:   "consulta": "¿Qué evidencia debe revisar Claude para habilitar referidos propios de supervisores en formulario, store y RPC, conservando autoría, ámbito e idempotencia?",
3:   "corte": 2,
4:   "extractos": [
5:     {
6:       "de": "crm.crear_lead_si_disponible vivo",
7:       "puntos": 2.3,
8:       "confianza": 0.67
9:     },
10:     {
11:       "de": "Decisión de Miguel 2026-10-16",
12:       "puntos": 2.18,
13:       "confianza": 0.72
14:     },
15:     {
16:       "de": "crm.crear_lead_documento_fn vivo",
17:       "puntos": 2.06,
18:       "confianza": 0.79
19:     },
20:     {
21:       "de": "Formulario LeadNuevo",
22:       "puntos": 2.05,
23:       "confianza": 0.92
24:     },
25:     {
26:       "de": "private.leads_before_update vivo",
27:       "puntos": 2,
28:       "confianza": 0.7
29:     },
30:     {
31:       "de": "Cambio previo ventas supervisor (ya publicado)",
32:       "puntos": 0.57,
33:       "confianza": 0.44
34:     }
35:   ]
36: }

ENVOLTORIO DOCUMENTAL VIVO:
CREATE OR REPLACE FUNCTION crm.crear_lead_documento_fn(p_datos jsonb, p_tipo text, p_documento text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid := (select auth.uid()); v_rol text := private.rol_crm((select auth.uid()));
  v_id uuid; v_numero text; v_persona uuid; v_resultado jsonb; v_pre crm.leads%rowtype; v_doc jsonb; v_k text;
begin
  if v_uid is null or v_rol is null or v_rol not in ('vendedor','supervisor','gerencia')
    or not coalesce(private.puede_acceder_crm(),false) then
    raise exception 'Acceso CRM revocado' using errcode='42501';
  end if;
  if p_datos is null or jsonb_typeof(p_datos)<>'object' then
    raise exception 'Datos de alta inválidos' using errcode='22023';
  end if;
  for v_k in select jsonb_object_keys(p_datos) loop
    if not v_k=any(array['id','nombre_completo','telefono','telefono_alternativo','correo','genero',
      'fecha_nacimiento','distrito','origen','etapa','monto_estimado','moneda','categoria_interes','vendedor_id','nota']) then
      raise exception 'Campo no permitido en el alta: %',v_k using errcode='22023';
    end if;
  end loop;
  v_numero := private.validar_documento_lead(p_tipo,p_documento);
  v_id := coalesce((p_datos->>'id')::uuid,gen_random_uuid());
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'La identidad unificada no está habilitada' using errcode='P0409';
  end if;
  perform pg_advisory_xact_lock_shared(hashtextextended('crm.equipo.usuarios_jerarquia',0));
  perform pg_advisory_xact_lock(hashtextextended('avancecrm:lead:id:'||v_id::text,0));
  select * into v_pre from crm.leads where id=v_id;
  if found then
    if v_pre.creado_por is distinct from v_uid then
      raise exception 'El identificador de esta alta ya fue usado con datos distintos' using errcode='22023';
    end if;
    v_doc := crm.documento_lead_fn(v_id);
    if (v_numero is not null and p_tipo is distinct from v_doc->>'tipo') or
      v_numero is distinct from v_doc->>'numero' then
      raise exception 'El identificador de esta alta ya fue usado con otro documento' using errcode='22023';
    end if;
  end if;
  -- Antes de contactos/fila se bloquea la identidad existente, SIN crearla.
  -- Una identidad nueva solo nace tras confirmar que el alta está disponible.
    if p_tipo<>'DNI' and v_numero is not null then
      perform private.identidad_bloquear_documento(p_tipo,v_numero);
      v_persona := private.inversionista_por_documento(p_tipo,v_numero);
      perform 1 from crm.inversionistas where id=v_persona for update;
    end if;
    -- Esta puerta es DEFINER y autoriza por auth.uid(): rol, autoasignación,
    -- destino visible y etapas no terminales; conserva sus propios candados.
    v_resultado := crm.crear_lead_si_disponible(
      p_nombre_completo=>p_datos->>'nombre_completo',p_telefono=>p_datos->>'telefono',
      p_origen=>p_datos->>'origen',p_monto_estimado=>(p_datos->>'monto_estimado')::numeric,
      p_moneda=>p_datos->>'moneda',p_id=>v_id,p_correo=>p_datos->>'correo',
      p_dni=>case when p_tipo='DNI' then v_numero else null end,
      p_genero=>p_datos->>'genero',p_fecha_nacimiento=>(p_datos->>'fecha_nacimiento')::date,
      p_distrito=>p_datos->>'distrito',p_etapa=>coalesce(p_datos->>'etapa','nuevo'),
      p_categoria_interes=>p_datos->>'categoria_interes',p_vendedor_id=>(p_datos->>'vendedor_id')::uuid,
      p_nota=>p_datos->>'nota',p_telefono_alternativo=>p_datos->>'telefono_alternativo');
    if v_resultado->>'estado' is distinct from 'creado' then
      return v_resultado;
    end if;
    if p_tipo<>'DNI' and v_numero is not null then
      perform crm.fijar_documento_lead_fn(v_id,p_tipo,v_numero);
    end if;

  return v_resultado;
end $function$
