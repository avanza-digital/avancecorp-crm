# Supervisor horizontal — evidencia de H2

23/09/2026 · Codex PRIMARY · **H2 CERRADA: cuatro etapas y doce tareas**.
Base `cf87e8087bf61ea5c58669d924e801526a04c779`, igual a `avancecorp/main`
al iniciar. Rama `codex/gestion-diaria-supervisor-horizontal` en la copia
existente `/private/tmp/avancecorp-release.hvdub4/repo`. Taller principal intacto.

[Plan canónico](GESTION-DIARIA.md) · [Especificación H1](SUPERVISOR-HORIZONTAL-H1-ESPECIFICACION-2026-09-23.md) ·
[Revisión y resolución](SUPERVISOR-HORIZONTAL-H2-REVISION-2026-09-23.md) ·
[Mismo tablero](https://www.figma.com/board/9Pg7jMDRg3UVbb4XfeM80L?node-id=18-19).

## Entrega por etapas

| Etapa | Resultado implementado | Evidencia |
|---|---|---|
| H2.1 | Cabecera compacta, cinco indicadores de personas y filtros juntos. El filtro no cambia los totales del equipo. | `supervisor.test.tsx`; densidad y captura DOM a 1512/1366. |
| H2.2 | Seis columnas, cero explícito, muestra insuficiente diferenciada, vencidas ordenables, selección por nombre y acceso completo a todas las filas. | Comparadores probados en ambas direcciones, empates estables, fila 11 alcanzable, texto accesible de motivos. |
| H2.3 | Región lateral con estado inicial y Resumen/Registro/Pendientes; un solo portal conserva identidad, filtros, páginas y scroll. | Error del resumen conserva Registro; revocación y cambios actor/rol/demo/día limpian. Ampliar/restaurar, teclado, ficha superpuesta y regreso. |
| H2.4 | Tabla y panel con scroll independiente; contenedor estrecho usa cajón modal, celdas rotuladas y filtros adaptables. | Diez/nueve filas típicas, nombres largos, tres motivos, cifras 999/321, móvil 390 × 844, reflow equivalente a 200 %. |

La tabla usa la respuesta autorizada existente. El panel conserva ocho métricas,
las trece horas 08–20, cifras desplegables y llamadas fuera de franja. Registro
individual se monta al visitarlo, queda oculto/inert al cambiar pestaña y usa
solo la persona seleccionada. Registro del equipo empieza en Todo, conserva
los selectores permitidos y no exporta. Actualizar vuelve a la primera página
sin borrar sus filtros; 42501 borra la lista y revalida el equipo.

Cortes y Otros avisos conservan sus proveedores y acciones actuales, accesibles
desde la franja inferior. Un aviso abre las llamadas de la persona validada;
al cerrar su diálogo el foco pasa al nuevo panel. La información de la vista
está disponible en una ventana de lectura de 480 px; H4 conserva la ampliación
del tratamiento compacto de cortes/avisos.

## Medidas y verificación visual

Datos de los screenshots y pruebas: **ficticios**. No se escribieron actividades
ni se copiaron datos privados desde producción.

Las pruebas miden geometría DOM con Plus Jakarta Sans cargada, menú contraído,
filas típicas de 44 px, texto mínimo 16 px y objetivos mínimos 44 px. La fila antigua
medida en H1 tenía 149 px; la nueva típica reduce 105 px (aproximadamente 70 %).
Nombres largos pueden aumentar la altura, con texto íntegro.

A 1512 × 805 se ven diez filas completas; a 1366 × 768, nueve. La undécima sigue
accesible con foco/scroll interno. No hay scroll de página ni desbordamiento
horizontal en esas condiciones. El gutter interno se reserva; el límite de dos
columnas aumenta si el scrollbar supera 16 px.

Móvil: 390 × 844. Reflow al 200 %: viewport CSS 756 × 402, equivalente al espacio de
1512 × 805 a zoom 200 %; se acredita reflujo y acceso, no un ajuste del control de
zoom del navegador del usuario. En ventanas bajas se permite flujo vertical.

## Gates

- **PASS** `npm run check`: 280 archivos de prueba, 4.192 tests; lint, TypeScript,
  cobertura, configuración de release, push tasa, build, verificación del bundle
  y duplicación. Cuatro advertencias de accesibilidad preexistentes en
  `coverflow-carousel.tsx`; ninguna nueva en H2.
- **PASS** banco dirigido tras revisión: 39 tests de supervisor, Registro y Dialog.
- **PASS E2E final local Docker: 29 passed / 0 failed**, sin reintentos: Gestión
  Diaria (equipo, analista, roles) y demo-roles. Incluye Restaurar con foco en el
  mismo botón, resize móvil→escritorio con selector enfocado y 26 filas intactas.
- **Corrida completa inicial: 234 passed / 3 failed / 26 skipped**. Fallaron dos
  arranques de demo-roles y la preparación de sesión de densidad 1366. Coincidió
  con cambios/HMR, sin atribuir causalidad no probada. Los cuatro archivos
  completos pertinentes, incluidos los tres fallos, se repitieron en el banco
  final 29/29 con código estable. No se presenta la primera corrida como PASS.
- **NOT RUN** `gate:realidad`: la ejecución terminó con «Falta SUPABASE_URL» en
  la copia aislada. No se infieren datos actuales de producción a partir de
  fixtures. Se probaron roster vacío, cero actividad, error y revocación.
- **NOT RUN / fuera de H2** instalación SQL, matriz RLS de la nueva RPC y
  despliegue. H2 no añade tablas, funciones ni políticas.

## Límites de entrega

H2 entrega la distribución navegable. H3 conserva su propio cierre: últimas
gestiones y listado paginado de tareas por analista con la RPC prevista en H3.3.
Por ahora Pendientes muestra agregados y señales confirmadas; cuando hay tareas
explica «Detalle de tareas no disponible», sin fingir lista vacía. H4–H6 siguen
pendientes. Las capacidades existentes de Registro y avisos se conservaron.

La imagen aprobada es referencia visual; no sustituye mediciones. No se publica
producto ni se marca F4 real como cerrado. La jornada 24/09, sábado 26/09 y tasa
baja OFF mantienen su seguimiento independiente.

## Capturas y datos conservados

| Condición | Ancho útil | Región desplazable de tabla | Filas completas | Scroll de página |
|---|---:|---|---:|---:|
| 1512 × 805 | 1400 px | x: 88, y: 244; 970 × 485 px | 10 | 0 |
| 1366 × 768 | 1254 px | x: 88, y: 244; 858 × 448 px | 9 | 0 |

La desaparición del scrollbar de página recupera 10 px respecto de la pantalla
antigua medida en H1. El panel mantiene 414/380 px; el gutter de la tabla ocupa
10 px en Chromium de Docker. Todos los primeros renglones típicos miden 44 px.
Cero textos pequeños y cero controles bajos en el muestreo DOM; sin overflow
horizontal de la tabla. Datos íntegros en el JSON enlazado abajo.

- [Escritorio 1512](assets/supervisor-h2-1512-2026-09-23.png).
- [Escritorio 1366](assets/supervisor-h2-1366-2026-09-23.png).
- [Móvil 390](assets/supervisor-h2-movil-2026-09-23.png).
- [Reflow al 200 %](assets/supervisor-h2-200-por-ciento-2026-09-23.png).
- [Nombre largo](assets/supervisor-h2-nombre-largo-2026-09-23.png).
- [Plan completo actualizado en Figma](assets/supervisor-horizontal-h2-cerrada-figma-2026-09-23.png).
- [Detalle de H2 cerrado en Figma](assets/supervisor-horizontal-h2-detalle-figma-2026-09-23.png).
- [Evidencia estructurada y hashes](SUPERVISOR-HORIZONTAL-H2-EVIDENCIA-2026-09-23.json).

Logs originales locales: `/private/tmp/gestion-diaria-horizontal-20260923/h2/`.
El cierre documental conserva las 72 tareas H1–H6 (24 completas/48 pendientes)
y las 76 casillas históricas F0–F6. H3 no se considera completada por reutilizar
Registro en H2: conserva sus pruebas de datos y la nueva lectura de tareas.

## Sincronización del plan

**PASS:** lectura posterior del mismo Figma: 24 tareas completas y 48 pendientes;
las 76 casillas originales conservan exactamente su texto. Sin diferencias
respecto de las tareas canónicas ni desbordamientos o solapamientos de texto.
Capturas del bloque completo y de H2 inspeccionadas. Plan canónico, mapa de nodos
y vault reflejan el mismo cierre. H3–H6 mantienen sus propios criterios de aceptación.
