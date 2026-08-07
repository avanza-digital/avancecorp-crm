---
tags: [crm, datos-reales, produccion, f2, en-curso]
actualizado: 2026-08-07
---

# CRM — conexión a datos reales (EN CURSO, 2026-07-15)

Objetivo: pasar el CRM (crm.miavance.com) de **modo demo** a **datos reales en producción**. Decidido por Miguel: mapear los asesores del portal como equipo, sembrar leads piloto, **alcance completo** (incluye Agenda, conversión lead→cliente y metas). Ver [[Acceso y roles del CRM]] para el equipo enrolado.

## Diagnóstico que originó esto
El CRM solo mostraba el Workspace en modo demo (`App.tsx`: `yo?.demo ? <Workspace/> : <DatosRealesPendientes/>`). Una cuenta real caía en "Datos reales aún no conectados". El store (`lib/store.tsx`) es 100% demo (sessionStorage), y solo existía UNA lectura real (`listarLeads` en `data/crm-api.ts`). Estrategia elegida (menor riesgo): **alimentar el store desde Supabase manteniendo el shape `StoreDataApi`** → las 6 pantallas quedan intactas.

## Bloque 1 — Equipo real ✅ (ver [[Acceso y roles del CRM]])
20 personas enroladas en `crm.equipo` (Carlos gerencia + Carmen/Jorge supervisores + 17 vendedores). Kirk pendiente (cuenta aparte).

## Bloque 2 — Cimientos de datos en la BD ✅ VERIFICADO (2026-07-15)
- **Migración `crm_lectura_equipo_y_actividades_fn`** (aditiva): 2 funciones `SECURITY DEFINER` (patrón de `clientes_basicos_fn`, GRANT solo authenticated):
  - **`crm.equipo_visible_fn()`** → roster con NOMBRES (une `crm.equipo`→`public.perfiles`, que la RLS de perfiles no deja leer directo). Scope EXACTO de la policy `equipo_select`.
  - **`crm.actividades_del_ambito_fn()`** → timeline del ámbito con `autor_nombre`. Scope EXACTO de `actividades_select`.
- **9 leads piloto** sembrados en `crm.leads` (3 al ANALISTA CRM DEMO para QA, 3 a Linda/Carmen, 2 a Astrid/Jorge, 1 "por repartir" en bandeja de Carmen). Todos con creador; el trigger `leads_before_insert` no rompió `creado_por`.
- **Verificación por rol (curl con JWT de las 3 cuentas QA):** GERENTE(gerencia)=9 leads/23 equipo · SUPERVISOR=3 leads/2 equipo · ANALISTA(vendedor)=3 leads/1 equipo. **Coincide exacto con lo esperado** → la seguridad por rol funciona de punta a punta.

## Estado de los bloques (al 2026-07-16)
Bloques 1-6 **HECHOS y en producción** (lectura real, acciones, y conversión lead→cliente + contrato).
El detalle de cada uno está más abajo. Lo que queda vivo está en §Pendientes reales.
- ~~Bloque 3-4 (lectura + gate)~~ ✅ · ~~Bloque 5 (mutaciones)~~ ✅ · ~~Bloque 6 (convertir + contrato)~~ ✅ desplegado 2026-07-16.
- **Agenda y metas** siguen sin fuente de datos real (la UI queda honesta: "muy pronto" / "meta por definir").
- **Deploy:** ya en crm.miavance.com; el demo NO entra al bundle de prod (verificado por grep).

## Bloque 3-4 — LECTURA real conectada ✅ VERIFICADO (2026-07-15)
- **`data/crm-api.ts`**: +`listarLeadsDelAmbito` (no paginada, `nota` incluida), +`listarEquipo` (rpc `equipo_visible_fn`), +`listarActividadesDelAmbito` (rpc). Validación Valibot en cada frontera.
- **`lib/database.types.ts`** (curado a mano): +las 2 RPCs nuevas en el schema `crm`.
- **`lib/store.tsx`**: `StoreProvider` ahora es adaptador — en sesión real (`yo && !yo.demo`) hace `Promise.all` de leads+equipo+actividades, resuelve `vendedor_nombre` con el roster y puebla el store manteniendo el shape `StoreDataApi`; las 6 pantallas quedan intactas. El cálculo de `ambito` del cliente sirve tal cual (org de 2 niveles, plano=recursivo).
- **`App.tsx`**: gate `yo?.demo` → `yo` (la cuenta real entra al Workspace).
- Verificado: typecheck OK, lint OK, **120/120 tests** (fixture `nota` añadida), arranque sin errores de consola.

## Bloque 5 (acciones) — HABILITADO + verificado (build/tests), falta prueba visual + deploy (2026-07-15)
> ⏳ HISTORIAL del 2026-07-15. El veto de `convertir` que se menciona aquí **ya no existe**: se levantó
> el 2026-07-16 (ver §Quién da de alta y §Bloque 6). Se conserva por trazabilidad.

Se cablearon las mutaciones (insertarLead/actualizarLead/insertarActividad + `persistir` optimista con resync + trigger `trg_leads_reasignacion` + `aErrorApi`). Tras la **revisión adversarial** quedaron GATED OFF hasta cerrar 5 bugs; **los 5 están arreglados y el gate está ABIERTO** para real (excepto `convertir`, que seguía vetado hasta el bloque 6):
1. ✅ **Textos "(demo)"**: TODOS los toasts de éxito ("Lead creado/Cambios guardados/Actividad registrada/Reasignado/Descartado/Contacto/Convertido…") en `lead-drawer`/`lead-nuevo`/`contacto`/`hoy/supervisor` + el detalle de conversión del store se condicionaron a `yo?.demo`. Bundle de prod: cada `(demo)` queda detrás del guard `?.demo?` → código muerto en real (demo deshabilitado).
2. ✅ **Guard de sesión en el resync**: `epocaRef` se incrementa en CADA corrida del efecto de datos (login/cambio de usuario/logout/reintento); `resincronizarReal` captura su época y descarta el resultado si cambió → una resync rezagada de A ya no repuebla el store de B (fuga de PII cerrada).
3. ✅ **Rollback honesto**: `resincronizarReal()` devuelve `boolean` (si aplicó); el toast solo dice "se restauró el estado anterior" cuando de verdad se aplicó, si no dice "Sin conexión… recarga la página".
4. ✅ **Carga inicial fallida NO silenciosa**: nuevo `StoreEstado {cargando,error,reintentar}` (contexto `StoreEstadoContext` + `useStoreEstado`); `App.tsx` pinta splash mientras carga y una pantalla `ErrorCargaReal` (WifiOff + Reintentar + Cerrar sesión) en fallo, nunca el CRM vacío.
5. ✅ **Nota del descarte preservada**: en real, además del `actualizarLead(descartado)`, se inserta una actividad `'nota'` con `Descarte · <motivo> — <nota libre>` (el motivo ya viaja en la columna `motivo_descarte`).
- **Tests unitarios:** `store-real.test.tsx` (8 casos, mock de `@/data/crm-api`): gate abierto, `convertir` sigue gated, rollback honesto/offline, estado.error+reintento, descarte real (nota como actividad + fallo parcial honesto). Total **128/128**; typecheck+lint+build OK.
- **Aplicado en BD que ya estaba:** `grant insert on crm.actividades to authenticated` + trigger `trg_leads_reasignacion` (F0).

### Arreglo extra tras auditoría adversarial (2026-07-15)
Una auditoría (3 lentes × verificación, 16 hallazgos) encontró un bug **ALTA** en mi fix de la nota del descarte: eran DOS escrituras no atómicas (`actualizarLead` + `insertarActividad`); si la 2ª fallaba tras la 1ª, el lead quedaba descartado pero el toast mentía "se restauró" y la nota se perdía en silencio. **Arreglado (migration-free):** el fallo del insert de la nota se captura aparte → `toast.warning('Lead descartado, pero no se pudo guardar la nota…')`, sin revertir ni mentir. La **atomicidad real** (un RPC `crm.descartar_lead` SECURITY INVOKER) queda para el **bloque 6** (ya toca BD).
- **Tradeoffs conocidos que quedan anotados (no cambié código prod a ciegas antes de la prueba visual):** (a) UI optimista muestra toast de éxito síncrono y, si el servidor rechaza, un 2º toast de rollback → dos toasts en pantalla; (b) resyncs concurrentes son last-writer (dos mutaciones en vuelo → parpadeo transitorio, se corrige solo). Bajo volumen piloto, aceptables.

### Suite E2E Playwright (2026-07-15) — "prueba todo con Playwright"
`app/e2e/`: **22 tests verde (3× sin flakiness)**.
- `acciones-demo.spec.ts` (8): crear/editar/mover/descartar+nota/reabrir/actividad/reasignar/convertir en demo, cada uno con su toast "(demo)" correcto y la nota del descarte en el timeline.
- `acciones-real.spec.ts` (8) + `_helpers.ts`: **ruta REAL con TODO el host Supabase interceptado (`page.route`, fail-closed, backend CON ESTADO)** → login real vía formulario (supabase-js guarda su sesión), `getUser`+`resolverRol`+`cargarReal` mockeados; cero escritura en prod. Cubre: workspace real sin marca "(demo)", gate abierto (POST real), creación rechazada (rollback honesto), rollback con mapeo de mensaje 23505 + reversión del valor, descarte real (nota como actividad, contadores), descarte con nota fallida (aviso honesto sin "se restauró"), `convertir` sigue VETADO en real, carga caída → `ErrorCargaReal`+Reintentar.
- **Cosmético pendiente (fuera de los 5 bugs):** trigger `trg_leads_cambio_etapa` escribe el detalle con KEYS crudas (`nuevo → contactado`), no labels → en real el timeline muestra keys tras el resync. Arreglarlo es migración de BD, diferido.
- **DESPLEGADO EN PROD 2026-07-15** (build `index-CKrhWMgO.js`, verificado en vivo: hash nuevo, JS/CSS 200, ZIP 404 en ambos dominios, asset viejo 404, CSP/HSTS OK, apunta a `dctqcbznekcyxhjujuci`, sin demo). **crm.miavance.com pasó de solo-consulta a ACCIONES reales habilitadas** (crear/editar/mover/descartar/reabrir/actividad/reasignar; convertir sigue vetado → bloque 6).
- **FALTA:** prueba visual de Miguel con cuentas QA (ya ESCRIBE en `crm.leads` real) + commit selectivo del CRM (working tree sin commitear: store.tsx/App.tsx/componentes + e2e/* + store-real.test.tsx).

## DEPLOY a producción — VISTA real EN VIVO (2026-07-15)
- **crm.miavance.com sirve el CRM real de CONSULTA.** `npm run build` (demo fuera del bundle por `import.meta.env.DEV=false`; botón demo y datos demo ausentes, verificado por grep del bundle) → ZIP de `dist/` (index.html raíz + `.htaccess`) → `deploy-hostinger-mcp.mjs deploy crm.miavance.com`. Verificado en vivo: sirve `index-BBnj4XQs.js`, assets 200, ZIP→404, apunta a `dctqcbznekcyxhjujuci`.
- **Fix pre-deploy:** los "(demo)" VISIBLES del `lead-drawer.tsx` (botón/diálogo Convertir, Reabrir, banner terminal) se condicionaron a `yo?.demo` (los `toast.success` con "(demo)" se dejaron: solo se disparan tras acción exitosa → en real están bloqueados → nunca aparecen). Bundle limpio (0 "(demo)" estáticos).
- **Acciones siguen GATED** en prod (muy pronto). El CRM real es de solo consulta hasta el bloque de acciones.
- **Probar en prod:** login con QA gerente (`avancecorp26+crm-gerente@gmail.com`/`Avance.Gerente2026`) ve todo (23 equipo + 9 leads); QA analista ve 3. El equipo real entra con su credencial de portal (cartera vacía salvo asignaciones piloto).

## Quién da de alta clientes/contratos — historial y decisión vigente

La decisión del 2026-07-16 —“el alta la hace el vendedor, a veces el supervisor; gerencia nunca”— fue **reemplazada por Miguel el 2026-08-07**. La regla vigente es: **Gerencia puede ejecutar todas las operaciones del CRM, incluido convertir leads, corregir clientes y crear/editar contratos, sobre todo el ámbito**. Ver el alcance y las fronteras en [[Acceso y roles del CRM#Decisión 2026-08-07 — Gerencia operativa global]].
Y: "**analista y comercial son lo mismo, no distingas**; usa `analista` para el CRM".

**Verificado contra prod — no hay nada que unificar, ya está unificado:**
- Los 19 de la fuerza de ventas (Carmen, Jorge + 17 vendedores) **ya son `analista`**. Carlos es `directorio`.
- Los **únicos 3 `comercial`** de toda la BD son las cuentas QA demo. `comercial` es un **rol MUERTO**:
  no aparece en ninguna policy ni función, y el **portal ni siquiera lo deja entrar** ("Rol de usuario no válido").
- ⚠️ **NO pasar la fuerza de ventas a `comercial`**: `analista` es la llave de 8 cosas del servidor
  (incl. `crear_contrato`). Se quedarían sin alta de contratos y sin ver su propia cartera.

**Para la fuerza de ventas**, el servidor conserva las dos condiciones históricas de `public.crear_contrato`:
1. **Rol de portal:** `es_analista() OR es_admin()`.
2. **Cartera:** el cliente debe ser propio (`asesor_perfil_id = auth.uid()`, o lo registró con asesor nulo).

**Gerencia tiene una tercera vía, acotada al CRM:** `private.rol_crm(auth.uid()) = 'gerencia'`. No necesita
convertirse en admin del portal ni apropiarse de la cartera. En conversión, vendedor/supervisor siguen
exigiendo responsabilidad propia; Gerencia puede cerrar un lead ajeno solo si ya tiene analista asignado,
y ese analista se conserva como asesor del nuevo cliente.

La brecha histórica entre el rol CRM `gerencia` y el rol de portal `directorio` se resuelve sin elevar a
Carlos a administrador del portal: la nueva frontera de servidor autoriza a Gerencia por su enrolamiento
CRM activo, exige que el lead tenga analista asignado y conserva a ese analista como responsable. Así se
evita crear clientes huérfanos y se mantiene la atribución comercial. **Está activa en producción desde
el 2026-08-07**: migración remota `20260807180637`, edges `crm-convertir-lead` v8 / `crear-cliente` v26 y
frontend `crm-20260807T182333Z-ea53f103ab2c`.

## Notas técnicas clave
- **rol_crm** CHECK = vendedor|supervisor|gerencia; directorio entra por fallback lector-global (no por crm.equipo).
- Las cuentas `+crm-*` (DEMO) siguen en `crm.equipo` como **QA** (tenemos sus claves) — retirar antes del go-live.
- La cartera de clientes (158 del portal) ya se proyecta viva vía `crm.clientes_basicos` (no hay que sembrarla).

## Pendientes reales (2026-07-16)
**Para que la fuerza de ventas trabaje SOLO en el CRM** (decisión de Miguel), falta portar del área de
analista del portal. Verificado: el analista NUNCA tuvo pagos/documentos/novedades/conciliación/
renovaciones (eso es de admin) → apagar su pantalla no pierde nada de eso. Lo que sí falta:
1. ✅ **CERRADO 2026-07-27 — datos bancarios.** *(Estado real al reabrirlo: el formulario y la regla
   "al menos una cuenta" YA existían desde el `dddca46` del 2026-07-17 — esta nota se quedó vieja. Lo
   que seguía roto era otra cosa, y peor: la regla vivía **solo en el navegador** y las 14 columnas se
   escribían en un **SEGUNDO UPDATE**, después de crear la cuenta de Auth y de mandar el correo de
   bienvenida. Un POST directo con sesión de vendedor, un bundle viejo o un fallo de red dejaban un
   cliente REAL, con su correo ya enviado, sin cuenta donde cobrar — el código incluso tenía un aviso
   terminal dedicado a ese estado, o sea que se sabía que pasaba.)*
   **Ahora la frontera es del SERVIDOR y las columnas entran en el MISMO INSERT del cliente:**
   `_shared/bancarios.mjs` (módulo puro, 19 tests con `node --test`, espejo campo por campo de
   `app/src/lib/cliente-form-logica.ts`) lo usan las DOS puertas de alta —`crm-convertir-lead` (lo
   **exige**, fail-closed) y `crear-cliente` (**opcional**, para que el portal siga byte-idéntico)—.
   Desaparece el segundo paso y con él el estado "creado sin bancarios". Comprobado en prod: **0
   clientes creados desde el CRM hasta hoy**, así que no hubo nada que reparar. `importar-clientes`
   (la 3ª puerta, del portal) ya exigía banco/tipo/número/CCI desde siempre.
   ⚠️ **Queda un hueco ADYACENTE, sin cerrar y con decisión pendiente de Miguel:** *corregir* sigue
   siendo un `PATCH` crudo a `public.perfiles` bajo RLS (`actualizarClientePortal`), así que el mismo
   asesor que creó al cliente puede, dentro de su ventana de 5 h, dejar las 14 columnas en NULL con
   una llamada a mano — la regla "al menos una" ahí sigue viviendo solo en el navegador. Cerrarlo de
   verdad exige un **trigger/CHECK en `public.perfiles`**, que es tabla del PORTAL en producción y
   necesita su OK explícito (y ojo: un CHECK a secas rompería filas legacy sin cuenta).
2. **Corregir** cliente/contrato (el portal les da 5 h de autoservicio; el CRM no tiene nada).
3. **Ver detalle + cronograma** del propio cliente (permiso ya dado en BD; es solo pantalla).
4. **Pantalla de clientes** en el CRM (hoy "Cartera" es de LEADS; convertido el lead, el cliente desaparece)
   + entrada "crear contrato para cliente existente" → es lo que vuelve **"Omitir por ahora"** un atajo
   legítimo en vez de una trampa (hoy, si omites, el lead queda cerrado y el contrato no se puede retomar).
5. **Cuentas mancomunadas** (co-titulares).

**Riesgo vivo hoy:** las 3 cuentas QA `+crm-*` siguen en `crm.equipo` — la demo de gerencia **ve los 9 leads
reales** y puede crear clientes reales con correo real. Además **3 leads reales cuelgan de la cuenta QA**
(Mariana Quispe, Diego Fernández, Lucía Mendoza): hoy **ningún vendedor real los puede trabajar**.

**Otros (actualizado 2026-08-07):** la habilitación segura de Gerencia ya está aplicada y verificada en
producción · `cronograma.ts` trunca en silencio a 120 cuotas
(el portal no) · el `<input type=date>` sin `min`/`max` acepta año de 2 dígitos → 19xx.

## Relacionadas
[[Acceso y roles del CRM]] · [[F0 Cimientos BD del CRM]] · [[Deploy a Hostinger]] · [[CRM Avance Corp P-054]]
