# Seguimiento como módulo propio

Estado: implementado y verificado localmente; **esta revisión visual no se ha publicado**. Commit de implementación: `311a212ea9330511fb861c12e07d45801ccd4758`. La publicación SLA anterior sigue documentada en [PUBLICACION-SLA-2026-09-07.md](PUBLICACION-SLA-2026-09-07.md).

Miguel pidió mejorar visualmente Seguimiento, conocer la vista de Supervisor y separarlo del Resumen de Gerencia. Después pidió guardar los cambios en commits.

## Decisión y alcance

La ruta `#/seguimiento` tiene una entrada «Seguimiento» en el menú para Gerencia, Supervisor y Analista. Reutiliza el núcleo SLA y las RPC vigentes; no introduce calculadoras, políticas, tablas ni migraciones. Muestra la situación actual de la cartera, independiente del período y origen elegidos para los resultados de Gerencia.

| Rol | Nueva experiencia | Alcance de datos |
|---|---|---|
| Gerencia | La cola sale completamente de Resumen y se abre desde Seguimiento. | Cartera global autorizada. |
| Supervisor | El módulo ocupa su pantalla propia; Hoy conserva Agenda y un acceso «Abrir seguimiento». | Su equipo y descendencia recursiva autorizada por el servidor. |
| Analista | Puede entrar al módulo y conserva la cola de trabajo en Hoy. | Solo su cartera. |

Se conserva el cierre general del mundo Leads. Directorio, Coordinador y Superadmin que solo administra roles no ganan acceso a esta vista. El modo legado y los errores del núcleo siguen teniendo estados explícitos; no se inventa una cola operativa con datos de demo.

## Revisión visual y cambios

1. **Resumen anterior, capturado en producción:** la cola ocupaba el espacio anterior a los indicadores y aparecía bajo filtros de período/origen que no la controlaban. La captura privada de esta revisión se guardó fuera del repositorio porque contiene datos reales. La vista anterior del Supervisor se comprobó en código; no se inició sesión con una cuenta real de Supervisor.
2. **Módulo en escritorio:** prioridades seleccionables con conteos del servidor, filtros por etapa y analista, columnas de oportunidad/responsable, acción, fecha y apertura de ficha. Los colores distinguen la acción y el texto conserva su significado. El botón «Limpiar filtros» restablece la consulta sin alterar el tamaño de página.
3. **Módulo en móvil:** las prioridades pasan a un selector nativo, las filas se reorganizan y el título permanece completo. Se corrigió la alineación de «Por página» y su flecha. Las capturas siguientes utilizan datos sintéticos.

El filtro Analista ahora ofrece únicamente vendedores activos del roster autorizado. Antes incluía gerentes y supervisores, aunque la consulta filtra por analista asignado. Los conteos de señales pueden solaparse; no se suman ni se presentan como total de oportunidades. El total de la lista procede de la respuesta del servidor.

Se conserva la paginación 10/25/50 con Anterior/Siguiente, sin acumular filas, y el reinicio del cursor al filtrar o invalidar. Se conservan la apertura de fichas fuera de la carga inicial, sus controles de acceso y los estados de carga/error. Las acciones comerciales continúan dentro de la ficha.

## Evidencia

- Suite completa: 2939 pruebas en 202 archivos; controles de tipos correctos y lint sin errores, con cuatro avisos preexistentes de otro componente.
- E2E SLA: 9/9 casos. Incluyen navegación, ámbito global/equipo simulado, filtros combinados, conteos solapados, páginas y fichas. Los dos casos de Gerencia/Supervisor se repitieron después del ajuste visual final: 2/2, sin desbordamiento ni errores de página; título móvil medido con `scrollWidth <= clientWidth`.
- La comprobación usa backend simulado para probar la interfaz; no sustituye las pruebas RLS/SQL de la publicación anterior ni certifica una nueva publicación.
- [Registro de comprobación y huellas de capturas](modulo-seguimiento-20260907/verificacion.json).

### Gerencia, escritorio

![Gerencia: módulo Seguimiento con datos sintéticos](modulo-seguimiento-20260907/gerencia-desktop.png)

### Supervisor, escritorio

![Supervisor: módulo Seguimiento con datos sintéticos de su equipo](modulo-seguimiento-20260907/supervisor-desktop.png)

### Supervisor, móvil

![Supervisor: seguimiento adaptado a móvil](modulo-seguimiento-20260907/supervisor-mobile.png)

La tipografía, el navy institucional, los controles y el menú parten del diseño existente. Las capturas permiten evaluar composición y legibilidad; no constituyen una certificación completa de accesibilidad. Para publicar se requiere construir un artefacto desde el commit que se sincronice con `avancecorp/main` y verificar el servicio después del despliegue.
