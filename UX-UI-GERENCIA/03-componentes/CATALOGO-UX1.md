# UX1 — Catálogo preparado para el bloque A

Revisión: 6 de septiembre de 2026. Alcance: componentes de Figma para Resumen y Conversiones. Correspondencia documental con el CRM; no es una sincronización automática con React ni una implementación.

## Base conservada

Se conservaron nueve familias con 30 variantes. Se añadieron tres composiciones propias con nueve presentaciones: seis indicadores visuales, un período compacto y dos paneles de analistas. Resultado del bloque: **12 familias, 39 presentaciones** (11 conjuntos de variantes y un componente individual).

| Familia | Presentaciones | Figma | Correspondencia con el código actual | Decisión |
| --- | --- | --- | --- | --- |
| CRM/Acción | 8: primario/contorno × normal/hover/foco/deshabilitado | [51:2](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=51-2) | `components/ui/button.tsx` | Conservar. Etiqueta y estado explícitos; objetivo táctil de 44 px. |
| CRM/Cabecera | 2: escritorio/móvil | [60:49](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=60-49) | `components/app/topbar.tsx` | Conservar título visible, identidad y controles conocidos. |
| Gerencia/Período | 2: escritorio/móvil | [58:2](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=58-2) | `periodo-context.tsx`, `area-consulta-gerencia.tsx` | Conservar contexto y comportamiento existentes. |
| Gerencia/Pestaña | 3: normal/seleccionada/foco | [56:2](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=56-2) | `screens/hoy/ranking-vendedores.tsx` | Conservar. El piloto de Ranking continúa en el bloque B/UX3. |
| Gerencia/Fila de Ranking | 2: escritorio/móvil | [61:42](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=61-42) | `components/common/tabla.tsx`, `ranking-vendedores.tsx` | Conservar base, moneda, orden y acceso al detalle; revisar densidad en UX3. |
| Gerencia/Detalle lateral | 2: escritorio/móvil | [63:46](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=63-46) | `screens/hoy/ranking-detalle.tsx`, `components/ui/sheet.tsx` | Reutilizar panel y regreso. La matriz completa de foco y estados sigue pendiente. |
| Gerencia/Indicador | 3: disponible/cargando/no disponible | [77:22](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=77-22) | `components/gerencia/indicador-gerencia.tsx` | Conservar etiqueta, valor y contexto. Es una instancia dentro del nuevo indicador visual. |
| Gerencia/Estado del dato | 5: carga/vacío/error/sin base/sin TC | [79:29](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=79-29) | `components/common/estado-panel.tsx`, `aviso-degradacion.tsx`, `components/ui/skeleton.tsx` | Conservar y documentar su aplicación a 292 px. |
| Gerencia/Atención | 3: con pendientes/sin pendientes/capacidad actual | [80:25](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=80-25) | `components/gerencia/atencion-citas.tsx`, avisos de Gerencia | Reutilizar; distinguir pendientes de capacidad actual. |
| **Gerencia/Indicador visual** | **6: capital/conversión/citas × escritorio/móvil** | [156:133](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=156-133) | `IndicadorGerencia`, `Card`, `Progress`, gráficos existentes | Nueva composición sobre piezas propias. Barras y notas ya propuestas; no añade un cálculo de negocio. |
| **Gerencia/Período compacto** | **1: móvil** | [158:1598](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=158-1598) | `AreaConsultaGerencia`, contexto de período y `Button` | Nueva composición del contexto móvil existente: rango, origen y acceso a filtros. |
| **Gerencia/Conversión por analista** | **2: escritorio/móvil** | [164:563](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=164-563) | `GerenciaEChart`, `ValoresGrafico`, `comparacion-analistas.tsx` | Nueva composición de las barras propias, con base junto al nombre y acceso a comparación. |

Las rutas abreviadas parten de `CRM-Avance-Corp/app/src`; período, consulta e indicadores pertenecen a `components/gerencia`. Las fuentes completas y los motores de gráficos se encuentran en el [inventario de reutilización](../02-f0-auditoria/continuacion-2026-09-06/inventario-reutilizacion.md). La navegación de código comenzó con CodeGraph; sus resultados insuficientes se completaron con lecturas puntuales.

## Fundamentos

- 72 variables existentes: 36 primitivas, 20 de color y 16 de geometría, en tres colecciones. Se conservan alias, valores y correspondencia CSS. Los tokens semánticos tienen alcances de uso; no se añadieron colores nuevos.
- Ocho estilos de texto y dos de efectos. Plus Jakarta Sans en la estructura general; IBM Plex Sans en reportes. En las ocho vistas nuevas se corrigieron fuentes Inter/JetBrains Mono heredadas de las capturas.
- En las tres familias nuevas, las pinturas sólidas de relleno/borde se vinculan a variables. La comprobación de texto pequeño sobre sus superficies blancas no encontró contrastes inferiores a 4.5:1.
- No se extendió el verde como nueva señal de éxito. Los gráficos usan navy/azul con cantidades y etiquetas; el significado no depende sólo del color.

La revisión de estos componentes no certifica accesibilidad del CRM completo. Teclado, foco, lectores de pantalla, zoom, movimiento y estados reales se comprueban al implementar, según UX4/UX6.

## Anatomía y reglas de uso

**Indicador visual.** Escritorio 370 × 248; móvil 292 × 198. Capital conserva moneda, TC y meta comparable. Conversión conserva mes, base automática y objetivo. Citas muestra dos conteos; no se interpreta realizada/pactada como conversión ni se dibuja un embudo. Las barras comparten escala dentro de cada comparación; sus denominadores son escalas gráficas del ejemplo, no fórmulas nuevas. No truncar un resultado que supere la meta.

**Período compacto.** 292 × 94. El rango y origen permanecen visibles; «Ver filtros» tiene 44 px de alto. Abrir/cerrar el panel se demuestra en el prototipo. Cambiar valores, aplicar y recalcular siguen siendo comportamientos del frontend existente, pendientes de integración visual.

**Conversión por analista.** Escritorio 724 × 284, ampliable al ancho del panel; móvil 292 × 284. Nombre, base y porcentaje visibles en cada fila; barras desde cero, con escala común. El ejemplo compara Carla/Bruno. La elección libre y sus detalles se reutilizarán del CRM durante la implementación.

**Estados.** [Muestras móviles](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=160-29) con cinco instancias de la familia existente. En la instancia sin TC se aclara que S/ y US$ se muestran separados, mientras el equivalente y su avance esperan el TC. Esa adaptación es local a la muestra; no modifica el código ni el maestro histórico. Cero comprobado y lectura parcial/actualizando están especificados como reglas; su cobertura visual completa sigue en UX4.

## Recursos externos y diferencias pendientes

Figma MCP verificó ocho bibliotecas disponibles y buscó indicador, período y conversión por analista. Las consultas de este bloque no devolvieron una alternativa pertinente. Se reutilizó la biblioteca propia. Los recursos ya investigados en F0 conservan sus decisiones; no se compraron kits ni se instalaron dependencias.

No se encontraron archivos Code Connect en `app/src`. Las nuevas composiciones todavía no existen como equivalentes exactos en React. La implementación deberá reutilizar ECharts, controles y consultas presentes, adaptar su presentación y verificar las cifras originales; no sustituir la base por una librería nueva. Las propiedades de texto heredadas se contrastaron también con el texto real renderizado para evitar dar por aplicada una edición sólo porque cambió el valor de una propiedad.

## Entrega y aceptación

Catálogo y variantes preparados para el bloque A; revisión visual de Resumen/Conversiones pendiente con Miguel. Ver [resultado y evidencia](../04-propuestas/revision-ux1-ux2-2026-09-06/README.md). Las tablas/formularios de otros módulos, todos los estados y los recorridos completos conservan sus fases UX3–UX6. F0 no se cierra sin prioridades de uso y observación humana.
