---
tags: [auditoria, crm, deuda-tecnica, calidad]
actualizado: 2026-07-10
veredicto: compila-y-funciona-no-listo-para-datos-reales
---

# Deuda técnica CRM — fuera de DB (2026-07-10)

Unión de **dos análisis independientes** hechos el mismo día sobre `CRM-Avance-Corp/app` (código React/TypeScript, sin tocar base de datos):

- **Análisis A (multi-agente, estructural):** 5 auditores en paralelo + verificación. Enfoque: mantenibilidad (duplicación, archivos gigantes, fronteras de datos, tests, errores).
- **Análisis B (readiness para datos reales):** enfoque en qué falta antes de conectar datos de verdad. Aportó **mediciones ejecutadas** (cobertura real, avisos de accesibilidad) y un hallazgo de proceso (trabajo sin commit).

Que dos revisiones independientes lleguen a lo mismo por caminos distintos **sube la confianza**. Donde discreparon, gana la lectura conservadora (ver Auth).

> **Estado base (sano):** compila, TypeScript y lint pasan, **51/51 pruebas** en verde, `npm audit` = 0 vulnerabilidades. La higiene del código es buena (TS estricto, sin `any`, sin supresiones, sin TODOs). La deuda es de **escalado**, no de suciedad. Complementa a [[Auditoría CRM 2026-07-10]] (que cubre DB/RLS/escalabilidad).

## Reconciliación de los dos análisis

**Coinciden (alta confianza):**
- **Cobertura de tests.** A dijo "cero tests de UI; `auth` y el store casi sin cubrir". B lo **midió sobre todo `src`**: ~17% líneas, ~13% funciones, **auth y pantallas al 0%**. Y explica el espejismo: la nota hermana reportaba "100%… en el núcleo cubierto" — era 100% de **4 utilidades**, no del proyecto. Configuración del gate: `vitest.config.ts` mide solo esas 4.
- **Accesibilidad.** A dijo "los modales no atrapan el foco de verdad; reglas de accesibilidad apagadas". B **activó las reglas → 26 avisos**, varios funcionales.
- **Observabilidad.** Ambos: los registros terminan solo en la consola del navegador y el borrado de datos sensibles es parcial.

**Donde B afinó mejor que A (importante):**
- **Carrera en autenticación.** El auditor de A **encontró la línea exacta** (`auth.tsx:231`, `confirmarSesion()`) pero la clasificó como *"benigna, porque el servidor siempre reconsulta la verdad"*. B llegó a la conclusión opuesta y **correcta para producción**: aunque el dato del servidor sea correcto, la validación en curso **no se cancela al cerrar sesión**, así que la interfaz y la caché pueden quedar mostrando **temporalmente al usuario anterior** tras un logout o cambio de cuenta. → Se adopta la severidad de B (**Alta, bloqueante**). Es un buen ejemplo de por qué dos perspectivas > una: A fue demasiado indulgente.

**Lo que A aporta y B no listó (complementario, no contradictorio):**
- Duplicación de reglas de negocio, archivos gigantes, fronteras de datos sin tipar, errores enrutados por texto, y quick wins de tipado (detalle abajo).

## Paso 0 — Riesgo de proceso (desbloquea todo lo demás)

Confirmado en git: **44 archivos, +4.224 / −719, nada en el área de commit.** Y lo más grave (sin seguimiento en git):
- **el propio CI** (`.github/workflows/`) — *existe en disco pero no está en el repositorio*;
- **toda la capa de datos** (`src/data/`), **casi toda la librería interna** (`auth-context`, `observabilidad`, `seguridad`, `validacion`, `roles`, `router`, `store-context`, `query-client`), **todos los tests**, el `error-boundary`, `contacto.tsx` y `vitest.config.ts`.

**Traducción:** gran parte del trabajo nuevo —incluidos los tests que dan el 51/51 y los dos flujos de CI— **existe solo en esta computadora, no en el repositorio**. Si se sube ahora, el remoto no tendría ni el CI ni ese código; y como el CI no está versionado, **ningún gate protege nada todavía**. → Primer paso: un commit ordenado que meta CI + código + tests, revisando antes que **no** entren secretos (`.env`) ni carpetas de trabajo (`output/`, `tmp/`, `.codex/`, `.codegraph/`).

## Registro unificado priorizado

### 🔴 Bloqueantes antes de datos reales
1. **Carrera de sesión (auth/logout).** `auth.tsx:231`. La validación en curso no se cancela al cerrar sesión/cambiar de cuenta → identidad o rol anterior puede reaparecer en pantalla/caché unos instantes. *Arreglo:* máquina de estados con "generación de sesión" que invalida lo viejo → **XState v5** (los procesos se cancelan solos al cambiar de estado).
2. **Red de tests real.** Cobertura ~17% global, **auth y pantallas 0%**; el store de 697 líneas tiene una sola prueba (`store.test.tsx:29`, comprueba que cargan los fixtures). *Arreglo:* medir todo `src` (`coverage.include: ['src/**']` — en **Vitest 4** `coverage.all` ya no existe); cubrir auth, mutaciones del store y flujos principales con **Vitest + RTL + MSW**, y **Playwright** para E2E por rol.
3. **Frontera de datos sin tipar** *(de A; B lo dejó fuera por considerarlo "DB", pero es código cliente).* El cliente Supabase no tiene tipos (`supabase.ts:19`), así que **el rol del usuario se decide sobre datos sin verificar** (`auth.tsx:46-83`); en `crm-api.ts:199` los datos entran con doble conversión forzada. Es justo el código que interpretará los datos reales. *Arreglo:* `supabase gen types` + validación en el borde con **Valibot**.

### 🟠 Mantenibilidad (no bloquea, pero es la fricción diaria)
4. **Reglas de negocio duplicadas.** La regla "capital en soles y dólares nunca se suman" está reescrita en **8 sitios** con 3 formas distintas; "días desde una fecha" en **5** (`pipeline.tsx:28`, `equipo.tsx:61`, `directorio.tsx:71`, `lead-drawer.tsx:88`); `esAbierto`/lista de etapas terminales definidas pero **sin exportar** (`inteligencia.ts:11,14`) y recopiadas; etiquetas de origen en 5 archivos; paleta de colores en 5 con nombres distintos. *Arreglo:* exportar los ayudantes de `inteligencia.ts`, centralizar; vigilar con **jscpd**.
5. **Archivos que hacen demasiado.** El store concentra 8 operaciones en un bloque de ~313 líneas (`store.tsx:373-686`); `lead-drawer.tsx` tiene 637 líneas y 9 componentes; pantallas de 450-550 líneas mezclan cálculo y presentación. *Arreglo:* separar cálculo (funciones puras testeables) de presentación; para el estado, **Zustand + Immer**.

### 🟡 Medias
6. **Accesibilidad.** Modales sin trampa de foco ni fondo inerte (`sheet.tsx:31`); tarjetas del pipeline solo con ratón, no teclado (`pipeline.tsx:69`); reglas apagadas (`.oxlintrc.json` — solo 2 activas) → 26 avisos al encender. *Arreglo:* **Radix** para diálogos/menús + encender **oxlint jsx-a11y** (`plugins: ["jsx-a11y"]`).
7. **Observabilidad a un destino real.** Hoy los errores solo van a la consola. *Arreglo:* **@sentry/react**, portando el borrado de datos sensibles ya existente a su `beforeSend`.
8. **Errores enrutados por texto.** La interfaz adivina a qué campo pertenece un error leyendo palabras del mensaje (`lead-nuevo.tsx:172`); reformular el texto rompe el enlace en silencio. *Arreglo:* que las operaciones devuelvan un código de campo, no un texto.

### 🟢 Bajas
9. **Documentación desactualizada** *(de B).* `README.md:7` dice que no hay lógica de negocio; `app/README.md` sigue siendo la plantilla de Vite; `qa/LEEME.md:3` no refleja el estado real.
10. **Fuentes de verdad duplicadas** *(quick wins de tipado, ~1-2 h).* `EtapaActiva`, `ORIGENES`, listas de etapas terminales y roles escritas a mano donde el compilador podría garantizarlas.
11. **Detalles.** Contadores de antigüedad que no se refrescan solos en Equipo/Pipeline/Directorio (no usan el reloj reactivo que sí usan Vendedor/Supervisor); botón "Reintentar" del error-boundary que repite el fallo; badge de notificaciones fijo en 0.

## Herramientas acordadas (ver conversación 2026-07-10)

Auth → **XState v5** · Tests → **Vitest + RTL + MSW + Playwright** (+ `coverage.include`) · Frontera → **gen types + Valibot** · Accesibilidad → **Radix + oxlint jsx-a11y** · Observabilidad → **Sentry** · Gate de commits → **Lefthook** · Estado → **Zustand + Immer** · Vigilar duplicación → **jscpd**. Verificado con Context7 que XState 5.x y Vitest 4.x son las versiones vigentes y que `coverage.all` fue retirado en Vitest 4.

## Notas relacionadas

[[Auditoría CRM 2026-07-10]] · [[Auditorías del portal]] · [[Arquitectura del portal]] · [[Rol Directorio]] · [[Inicio]]
