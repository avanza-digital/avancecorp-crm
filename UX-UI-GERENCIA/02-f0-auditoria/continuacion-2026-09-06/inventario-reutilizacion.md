# F0 — Inventario de reutilización del frontend

Fecha: 6 de septiembre de 2026. Auditoría y preparación de UX1; implementación pausada.

Miguel reiteró que el CRM ya tiene mucho desarrollo y buenas librerías React, y que deben aprovecharse. Se conserva como dirección visual la propuesta «UI-UX (2) · Resumen / desktop» (Figma 112:14).

## Resultado

La base existente cubre diez necesidades de la mejora. Se inventariaron 16 archivos UI, 14 comunes y 16 de Gerencia: son archivos TypeScript de esas carpetas, excluidos tests y demos; no equivalen a 46 componentes ni a una revisión exhaustiva de todo el CRM.

| Necesidad | Base existente | Decisión | Fuente |
| --- | --- | --- | --- |
| Marca y navegación | BrandLockup · Sidebar · Topbar · Lucide | Conservar identidad, destinos y controles conocidos; ajustar únicamente la jerarquía y el espacio. | [brand.tsx](../../../CRM-Avance-Corp/app/src/components/app/brand.tsx), [sidebar.tsx](../../../CRM-Avance-Corp/app/src/components/app/sidebar.tsx), [topbar.tsx](../../../CRM-Avance-Corp/app/src/components/app/topbar.tsx) |
| Indicadores | IndicadorGerencia · Card · Progress | Ampliar la presentación para comparar resultado y meta. Conservar valor, período, base y moneda originales. | [indicador-gerencia.tsx](../../../CRM-Avance-Corp/app/src/components/gerencia/indicador-gerencia.tsx), [card.tsx](../../../CRM-Avance-Corp/app/src/components/ui/card.tsx), [progress.tsx](../../../CRM-Avance-Corp/app/src/components/ui/progress.tsx) |
| Gráficos de Gerencia | GerenciaEChart · barras/líneas · ValoresGrafico | Reutilizar el motor activo en Resumen, Citas y Conversiones. Ya maneja tamaño del contenedor, carga diferida y movimiento reducido. | [echart.tsx](../../../CRM-Avance-Corp/app/src/components/gerencia/echart.tsx), [echart-lazy.tsx](../../../CRM-Avance-Corp/app/src/components/gerencia/echart-lazy.tsx), [valores-grafico.tsx](../../../CRM-Avance-Corp/app/src/components/gerencia/valores-grafico.tsx), [resumen-gerencia.tsx](../../../CRM-Avance-Corp/app/src/screens/hoy/resumen-gerencia.tsx), [inteligencia-comercial.tsx](../../../CRM-Avance-Corp/app/src/screens/hoy/inteligencia-comercial.tsx) |
| Gráficos Recharts | ChartContainer · ChartTooltip · GraficasGerencia | Biblioteca y componentes disponibles. No se encontró una referencia de producción a GraficasGerencia fuera de su definición; revisar encaje antes de activar ese panel. | [chart.tsx](../../../CRM-Avance-Corp/app/src/components/ui/chart.tsx), [graficas-gerencia.tsx](../../../CRM-Avance-Corp/app/src/screens/hoy/graficas-gerencia.tsx) |
| Período y regreso | PeriodoGerenciaProvider · ConsultaGerencia · AreaConsultaGerencia | Conservar el contexto de reportes y la recuperación por vista; adaptar la presentación móvil. No extender esa garantía a todas las pantallas. | [periodo-context.tsx](../../../CRM-Avance-Corp/app/src/components/gerencia/periodo-context.tsx), [consulta-context.ts](../../../CRM-Avance-Corp/app/src/components/gerencia/consulta-context.ts), [area-consulta-gerencia.tsx](../../../CRM-Avance-Corp/app/src/components/gerencia/area-consulta-gerencia.tsx) |
| Tablas y listas | TablaEnvoltura · Th/Td · Paginación · lista de Ranking | Ajustar densidad, nombres y acción principal; mantener orden, búsqueda, filtros y operaciones existentes. | [tabla.tsx](../../../CRM-Avance-Corp/app/src/components/common/tabla.tsx), [paginacion.tsx](../../../CRM-Avance-Corp/app/src/components/common/paginacion.tsx), [ranking-vendedores.tsx](../../../CRM-Avance-Corp/app/src/screens/hoy/ranking-vendedores.tsx), [mi-cartera.tsx](../../../CRM-Avance-Corp/app/src/screens/mi-cartera.tsx) |
| Formularios | Input · Select · Textarea · Label · Button · LeadNuevo | Reordenar campos y resolver el ancho de Capital estimado en móvil. Conservar validaciones y acciones del CRM. | [input.tsx](../../../CRM-Avance-Corp/app/src/components/ui/input.tsx), [select.tsx](../../../CRM-Avance-Corp/app/src/components/ui/select.tsx), [textarea.tsx](../../../CRM-Avance-Corp/app/src/components/ui/textarea.tsx), [label.tsx](../../../CRM-Avance-Corp/app/src/components/ui/label.tsx), [lead-nuevo.tsx](../../../CRM-Avance-Corp/app/src/components/app/lead-nuevo.tsx) |
| Paneles y foco | Dialog · Sheet sobre Radix · detalle de Ranking | Aprovechar los paneles existentes. El retorno de foco de Cartera sigue siendo un hallazgo pendiente; la biblioteca por sí sola no lo valida. | [dialog.tsx](../../../CRM-Avance-Corp/app/src/components/ui/dialog.tsx), [sheet.tsx](../../../CRM-Avance-Corp/app/src/components/ui/sheet.tsx), [ranking-detalle.tsx](../../../CRM-Avance-Corp/app/src/screens/hoy/ranking-detalle.tsx) |
| Carga, errores y avisos | Skeleton · PanelVacio/Cargando/Error · AvisoDegradacion · Sonner | Reutilizar estados y reintentos; una consulta incompleta no debe verse como cero ni una escritura incierta como éxito. | [skeleton.tsx](../../../CRM-Avance-Corp/app/src/components/ui/skeleton.tsx), [estado-panel.tsx](../../../CRM-Avance-Corp/app/src/components/common/estado-panel.tsx), [aviso-degradacion.tsx](../../../CRM-Avance-Corp/app/src/components/common/aviso-degradacion.tsx), [main.tsx](../../../CRM-Avance-Corp/app/src/main.tsx) |
| Movimiento | GSAP · @gsap/react · GerenciaMotion | Mantener animaciones breves y la preferencia de movimiento reducido. La animación debe ayudar a leer y seguir una acción. | [motion.tsx](../../../CRM-Avance-Corp/app/src/components/gerencia/motion.tsx) |

## Librerías declaradas

Versiones solicitadas por package.json, no una recomendación de actualización ni una afirmación de última versión. No se instalaron ni actualizaron dependencias.

| Librería | Rango declarado |
| --- | --- |
| react | ^19.2.7 |
| react-dom | ^19.2.7 |
| tailwindcss | ^4.3.2 |
| echarts | ^6.1.0 |
| recharts | ^3.8.0 |
| @radix-ui/react-dialog | ^1.1.19 |
| @radix-ui/react-hover-card | ^1.1.19 |
| lucide-react | ^1.24.0 |
| gsap | ^3.15.0 |
| @gsap/react | ^2.1.2 |
| @tanstack/react-query | ^5.101.2 |
| sonner | ^2.0.7 |
| class-variance-authority | ^0.7.1 |
| clsx | ^2.1.1 |
| tailwind-merge | ^3.6.0 |

## Decisiones que pasan a UX1/UX2

1. Vincular cada pieza de la propuesta de Resumen con su componente actual antes de crear variantes.
2. Priorizar ECharts en las pantallas gerenciales donde ya está integrado. Recharts permanece disponible; no activar el panel antiguo sin revisar su pertinencia, datos y recorrido.
3. Aprovechar la marca, navegación, estructura de consulta, tablas/listas, paneles y estados existentes. Ajustar su presentación según la auditoría, sin reemplazos masivos.
4. Mantener las fuentes servidas, fórmulas, períodos, bases y monedas. Más visualización no significa crear indicadores nuevos.
5. Investigar recursos de Figma sólo para necesidades concretas que la base actual no resuelva; documentar la correspondencia con el código.

## Límites de la comprobación

Se consultó CodeGraph primero. Algunas consultas devolvieron fuentes ajenas a los componentes nuevos; se completó la revisión con búsquedas y lecturas puntuales de las rutas faltantes, sin reindexar.

Los importadores y llamadas se contrastaron en el código actual. La presencia de una librería no acredita que todos sus componentes se monten en la pantalla activa. La revisión estática tampoco acredita teclado, lector de pantalla, foco o todos los estados.

El retorno de foco de Cartera continúa como hallazgo UX0-06. Los dos recorridos móviles de esta continuación no reprodujeron el riesgo de que Resumen heredara el desplazamiento de Cartera; son comprobaciones del agente, sin tiempo ni éxito humano.
