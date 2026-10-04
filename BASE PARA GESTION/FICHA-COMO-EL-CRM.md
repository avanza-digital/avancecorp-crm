# Ficha de la base con las piezas del CRM y de Gestión Diaria (pedido de Miguel, 03/10 noche)

«Me gusta la ficha, pero que se adapte más a la ficha que ya tenemos en el CRM y en Gestión Diaria.»

## Decisiones de Miguel (03/10)
1. **Forma:** ancha (1120 px, dos columnas) con el lenguaje de la ficha del lead (`lead-drawer.tsx`).
2. **«¿Qué pasó con la llamada?»: UNA sola pieza** compartida por Mi día, la ficha del CRM y la base (nada de copias).
3. **«No contactar» y «Reactivar» en un pie fijo**, como «Descartar · Convertir».
4. Sin WhatsApp: solo Llamar y Copiar número (la puerta de la base solo registra llamadas).
5. **Pieza APROBADA** (03/10 noche): «me gusta mucho cómo se ve».

## Avance
- Paso 1 ☑ `f9f87685` · Paso 2 ☑ `8706aacc` (rama `crm/base-gestion-ficha-crm` sobre el vivo `3e248407`). `npm run check` PASS (5696);
  E2E Docker 45 pasan + 1 rojo previo (`gestion-diaria-vuelta.spec.ts:11`, fecha fija del 30/09).
- Pasos 3 y 4 ☑ `736f528f` (cabecera, DATOS, selector compartido, línea de tiempo, Llamar/Copiar, pie fijo). Ficha real
  comparada con la pieza a 1440 y 390: igual (sin WhatsApp; sin «Lead creado»: la base no trae `creado_en`).
  `revisor-a11y`: CHANGES_REQUESTED (7 P2) → aplicado → APPROVE. `npm run check` PASS (5714); E2E Docker 20/20
  (`base-gestion-ficha`, `gestion-diaria-resultado`, `acciones-demo`) + cierre 25 pasan / 1 rojo previo
  (`gestion-diaria-vuelta.spec.ts:11`). **✅ PUBLICADO 03/10 ~22:35 Lima** (`/release-crm`): otra sesión había publicado `6b1c2538` (#181,
  «Gestionado» en la ficha) a las 21:56 → rearmado con cherry-pick encima (rama `crm/base-gestion-ficha-crm-sobre-vivo`,
  limpio; su cambio en `lead-drawer.tsx` sigue entero) → check PASS 5737, E2E 33/33, preflight OK, smoke OK.
  `build-20261004T033439267Z`, commit `0e28f3a7` = VIVO. Respaldo `rescue/base-gestion-ficha-crm-20261003`. **PR #183**
  (choca con la #181 solo en `lead-drawer.tsx`). P3 abiertos (opcionales): `tabIndex` de la región solo en lg; «Reintentando…».

Pieza visual a escala real: `../ui-playground/ficha-base-gestion.html` (fuera del repo).

## Plan (rutas bajo `app/src/`; un commit por paso, sobre la rama publicada `crm/base-gestion-f2`)
1. **Selector compartido** `components/gestion-diaria/selector-resultado.tsx` (controlado: `valor`, `abierto`,
   `onElegir`, `onAlternar`, `dentro`, `nombre` con prefijo `resultado-llamada-`, `detalles?`, `deshabilitado`,
   `invalido`, `describedBy`). Sale de `registrar-resultado.tsx` (:78-84, :105-107, :140-157, :193-217, :314, :357-363);
   el listener de atajos y el foco van dentro. `focoInicial` NO entra (se queda en `Sheet` y en la tarjeta).
   `ui/radio-group.tsx` gana `describedBy` opcional. Gestión Diaria lo monta dentro del mismo `<fieldset disabled>`.
   Red: `registrar-resultado.test.tsx` y e2e `gestion-diaria-resultado/-analista/-vuelta` SIN tocarlos.
2. **`components/app/linea-de-tiempo.tsx`** (`CLASE_HITO`, `FilaActividad`, `GrupoEtapa`, `EsqueletoLinea`,
   `LineaDeTiempo`) y **`components/app/fila-dato.tsx`** (`Fila`), sacados de `lead-drawer.tsx` (:1073, :1517-1763)
   sin cambiar textos ni roles. `iconoActividad(a)` en `actividad-visual.ts` por `metadata.evento` (reactivación →
   ArchiveRestore, no contactar → Ban: hoy son `tipo='nota'`); `etiquetaActividadBase` rotula «No contactar».
3. **La base usa el selector** (`intento-base.tsx`): mismas reglas (rellamada ≤ 10 días, aviso del 3.er intento,
   `p_operacion_id` por contenido). Ajustar `ficha-base.test.tsx` (:51, :76-78, :101, :111) y
   `e2e/base-gestion-ficha.spec.ts` (:49-52): con la lista contraída, un atajo distinto se ignora.
4. **Cabecera, DATOS, historial, contacto y pie**: Avatar + nombre + chips `Badge` (descarte, etapa máxima, origen) +
   «hace N días / descartado»; DATOS con `Fila`; historial con `LineaDeTiempo` (sin agrupar cuando se busca);
   Llamar con `CLASE_ACCION` exportada (NO `AccionesContacto`: registra por la puerta normal y mete el lead en el
   store); `SheetFooter` con los dos botones. No pasar `ariaLabel` al `Sheet` (el nombre accesible es el del lead).

Cierre: `npm run check` (incluye `dup`) + E2E Docker de `gestion-diaria-resultado`, `-analista`, `-vuelta`,
`acciones-demo`, `sla-operacion` y `base-gestion-ficha` → `revisor-a11y` → `/release-crm` (lo invoca Miguel).
