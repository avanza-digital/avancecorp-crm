# Refactor de tablas y datos del CRM (2026-07-17)

Pedido de Miguel: menos scroll en Clientes (columnas compactas), refactorizar los
datos de Contratos y también Equipo, con análisis completo de qué refactorizar.
Ejecutado con auditoría multi-agente (63 hallazgos → plan de 12 pasos), 6 etapas
de implementación y revisión adversarial final (49 agentes; 8 confirmados, todos
arreglados). Commit selectivo: `0b681f6` en `main`.

## Qué cambió

- **Primitivas compartidas nuevas** (`components/common/`): `tabla.tsx`
  (TablaEnvoltura/TheadCrm/Th/Td — la densidad vive en DOS constantes,
  `DENSIDAD_TH='px-3 py-2'` y `DENSIDAD_TD='px-3 py-1.5'`; cambiarlas compacta
  TODAS las tablas), `estado-panel.tsx` (PanelCargando/PanelError/PanelVacio,
  textos SIEMPRE por props — los copys son negocio), `paginacion.tsx` +
  `lib/paginacion.ts` (página de 50, clamp).
- **Clientes/Cartera compactas**: fila ~57→~35 px (sin avatar decorativo,
  truncados con `title`, botones `xs`, responsive por prioridad: Documento
  `md`, Correo `lg`, Registrado `xl`; Ventana/Acciones/Asesor nunca se ocultan).
- **Contratos**: migrado a TanStack Query (`useContratos`/`useClientes` en
  `data/crm-queries.ts`; claves `cronograma(id)`/`titulares(id)`/
  `clienteDetalle(id)` CUELGAN del prefijo de su lista → una invalidación de
  `contratos()` cubre el detalle). `VistaContratos` única demo/real con
  buscador + filtro de estado + paginación (lógica pura en
  `lib/contratos-vista.ts`), fila clicable accesible, columnas Ventana/Acciones
  solo con `puede_contratar`, reloj de 5 h solo en filas propias
  (`useVentana(esMia ? … : null)`), Registrado ahora CON año.
  `lib/contratos-catalogo.ts` = fuente única de categorías/modalidades/estados.
- **Equipo**: E2E propios por primera vez (`e2e/equipo.spec.ts`, 4 specs);
  índice de actividad compartido (una indexada por render); tabla comparativa
  densa para gerencia/directorio, cards densas para supervisor.
- **Rendimiento**: recharts (104 kB gzip) fuera del chunk Hoy vía lazy de
  GraficasGerencia — los vendedores ya no lo descargan.
- **`fechaHora` unificada en `lib/format.ts`** (CON año, tolerante a null).

## Reglas nuevas que hay que respetar al tocar esto

- **Siembra de formularios de corrección** (cliente-form, contrato-corregir):
  exige `isSuccess && !isFetching && isFetchedAfterMount`. El último flag es
  VITAL: sin red el refetch queda `paused` (isFetching=false) y sembrar la
  copia cacheada haría que el guardado pise co-titulares/bancarios corregidos
  por otra sesión (el UPDATE viaja con el set completo).
- **El error solo gana sin data**: en Clientes/Contratos/ContratoDetalle un
  refetch de fondo fallido (foco + retry:false) NO debe tumbar lo ya pintado —
  patrón `isError && data == null`.
- **Corregir cliente invalida también `contratos()`**: `cliente_nombre` viaja
  denormalizado en la vista de contratos.
- Los E2E van por roles/textos accesibles: mantener `<table>/<th>/<tr>`
  semánticos y los nombres accesibles (`aria-label="Corregir datos"`, th
  `Ventana` con `aria-label="Ventana de corrección"`).

## Descartes deliberados (no hacer sin leer el porqué)

Migrar el store de leads a TanStack Query, partir ClienteForm, centralizar el
guard demo (protege el tree-shaking del bundle), fusionar dialog/sheet, reloj
compartido para useVentana (el guard ya evita timers en filas vencidas), toggle
de densidad (YAGNI). Detalle en el plan de auditoría del 2026-07-17.

## Deploy y la carrera de sesiones

El deploy de esta sesión (build `B_1N5Mgr` desde worktree aislado del commit)
fue pisado en ~1 minuto por el deploy de la sesión paralela (`BiFPTs47`,
build del árbol combinado: este refactor + su refactor de orígenes de leads).
Resultado final verificado por sha256: producción = árbol combinado, que ya
estaba verde (309 unitarios, 55 E2E). Lección en [[Deploy a Hostinger]]:
mirar el hash vivo INMEDIATAMENTE antes y después de desplegar; dos deploys
del CRM en la misma ventana se resuelven por "el último gana" y los assets
viejos quedan colgados (la extracción no purga).

Relacionado: [[CRM conexión a datos reales]] · [[Acceso y roles del CRM]] ·
[[Deploy a Hostinger]]
