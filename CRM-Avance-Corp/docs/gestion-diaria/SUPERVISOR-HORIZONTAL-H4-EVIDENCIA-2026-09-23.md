# H4 — cortes y avisos en la vista horizontal

**Estado: H4 COMPLETA — cuatro etapas y doce tareas verificadas.** Rama local
`codex/gestion-diaria-supervisor-horizontal`, copia aislada
`/private/tmp/avancecorp-release.hvdub4/repo`. Base Main `cf87e808`; checkpoint
anterior `8130e745`. Producto H4 guardado en `186e00f1`. Sin publicación.

## Objetivo y alcance

Integrar los cortes de llamadas y los avisos operativos en la vista horizontal
del supervisor para identificar qué requiere atención y actuar con menos
desplazamiento. Mostrar estado real, conservar «Lo estoy atendiendo» y
«Posponer 1 hora», y abrir el registro del analista correcto. Mantener permisos
y reglas actuales, evitar notificaciones duplicadas y actualizar el mismo
archivo de Figma con evidencia.

H4 modifica presentación y conexión de consultas existentes. No añade RPC,
migración, política RLS, horario, objetivo ni regla de recuperación. El archivo
SQL de H3 conserva SHA-256
`a61d0b30be5781f9f04b6486b2eaa1599c9bcada5d2e5ce35ddab2bc7acdba73`.
La migración H3 continúa sin instalarse en producción.

## Auditoría de las doce tareas

| Tarea | Implementación y evidencia |
|---|---|
| H4.1.1 · Franja y detalle bajo demanda | `FranjaCortesSupervisor` ocupa 44 px a 1512 × 805; la región de página no tiene scroll adicional. `EstadoCortesEquipo` usa disclosures con todas las personas del corte, aunque la tabla esté filtrada. Medidas y capturas conservadas. |
| H4.1.2 · Estado y jornada reales | La foto de equipo aporta horarios, política y estados. Programado, evaluado, evaluación pendiente, OFF, no laborable, contrato ausente y error tienen presentación diferenciada. La consulta de avisos se separa por actor y día Lima, rechazando otra jornada. |
| H4.1.3 · Conservar reglas | La presentación no calcula objetivos ni recuperación; muestra lo recibido. Pruebas con objetivo 27, nulos, un corte y jornada terminada. No hay texto ilustrativo fijo de cortes desactivados. |
| H4.2.1 · Seguimiento existente | Los botones respetan estado y `puede_posponer` del servidor. No se crea otra acción ni permiso. La escritura usa el proveedor e idempotencia existentes. |
| H4.2.2 · Espera, resultado y fallo | Estado de confirmación, botones bloqueados, error recuperable y refresco esperado tras la escritura. Reintento conserva UUID. Foco se recupera en estado confirmado o botón tras el fallo. |
| H4.2.3 · Persistencia sin reavisos | Abrir/cerrar la lista no remonta el proveedor. E2E de aplazamiento/reconocimiento/reapertura; prueba de popup único y rechazo de entrega reclamada por otra sesión. |
| H4.3.1 · Analista correcto | Lista, popup y pendientes de campana comparten `MiembrosAvisoCorte`. E2E selecciona BRUNO, abre aviso de ANA y exige filtro RPC de ANA y Llamadas. Aviso antiguo con persona retirada no crea pedido. |
| H4.3.2 · Un proveedor | Se conserva la instancia global de `GestionDiariaAvisosProvider`; ningún proveedor nuevo. Dos observadores del hook comparten una consulta. |
| H4.3.3 · Lista cuando falla popup | Error de presentación explica cómo atender desde la lista, que conserva personas y acciones. E2E comprueba el camino y que abrir paneles no crea otra entrega. |
| H4.4.1 · Otros pendientes | Pestaña compacta consume la lista compartida de campana, incluido contrato sin `diarias/contexto`. Carga, error del libro y pospuestos se dicen explícitamente; un error no se presenta como cero. |
| H4.4.2 · Navegación y contexto | E2E de aviso → registro → ficha superpuesta → mismo filtro/foco. Enlace a Seguimiento cierra selección; al volver se pide elegir persona. |
| H4.4.3 · Sincronización y permisos | Reconocer/aplazar refresca consultas confirmadas; Actualizar consulta cortes/libro y evita descargar todo el store con fuente diaria. Pruebas de cambio remoto, roles/demo, otro actor, día distinto y 42501. |

Las pruebas de pantalla interceptan RPC con datos ficticios y pasan por el
adaptador real de la app; no representan una nueva ejecución SQL/RLS ni una
prueba con supervisores productivos. Las restricciones de backend se conservan
y cuentan con la evidencia histórica de F4 y H3, que no se vuelve a atribuir a H4.

## Verificación

- Dirigido Docker después del review: **14 PASS / 0 fallos**, sin reintentos;
  seis recorridos H4 y ocho de postventa.
- Primera suite completa: **245 PASS / 1 FAIL / 26 omitidas**. Falló la
  conservación de ficha de postventa durante un error de actualización; el
  archivo completo pasó después sin modificar producto ni prueba de postventa.
  Causa intermitente no demostrada; no atribuirle una corrección H4.
- Primer gate integral: **4.268 PASS / 287 archivos**, build y demás pasos PASS.
- Gate posterior al review: un worker no arrancó por `ERANGE` al leer
  `node_modules/css-tree`; 286 archivos pasaron, ejecución marcada FAIL.
  El mismo gate terminó PASS con dos workers: **4.272 pruebas / 287 archivos**, lint, tipos, cobertura, release-config, push-tasa, build, bundle y duplicación.
- Suite final completa Docker: **247 PASS / 0 fallos / 26 omitidas**, 9,6 minutos, cero retries. Incluye postventa sin cambios.
- Figma: **48 completas / 24 pendientes**, 76 casillas históricas sin cambios, cero solapamientos, desbordes o discrepancias. Capturas general y H4 inspeccionadas: PASS.
- Comprobación pre-commit del producto: lint y typecheck PASS.

Los E2E usan Docker Playwright 1.61.1 local, dos workers y cero retries.
No se ejecutan en GitHub. `gate:realidad`: **NOT RUN**, falta `SUPABASE_URL`
en la copia aislada. SQL/RLS remoto, advisors hosted, supervisión real y
NVDA/VoiceOver humano: **NOT RUN** en H4. No se cargaron secretos productivos.

## Revisión y accesibilidad

Una revisión de Claude mediante el wrapper: **CHANGES_REQUESTED / MEDIUM**.
Codex resolvió los cuatro P2 y los tres P3 con evidencia; no se atribuye PASS
del reviewer. [Dictamen y resolución](SUPERVISOR-HORIZONTAL-H4-REVISION-2026-09-23.md).

Capturas finales de producto inspeccionadas: texto de 16 px, controles de
44 px, franja compacta, detalle legible y scroll interior del diálogo. Prueba
de teclado, devolución de foco, móvil de 390 px y reflow a 756 × 402 sin
desbordamiento horizontal. Safari y lectores humanos quedan sin ejecutar.

- [Franja de escritorio](assets/supervisor-h4-franja-escritorio-2026-09-23.png).
- [Detalle de cortes](assets/supervisor-h4-cortes-detalle-2026-09-23.png).
- [Móvil](assets/supervisor-h4-cortes-movil-2026-09-23.png).
- [Medidas](evidencias-h4-2026-09-23/medidas-h4.json).

## Plan y siguiente fase

Actualizado el [mismo bloque H4 de Figma](https://www.figma.com/board/9Pg7jMDRg3UVbb4XfeM80L?node-id=18-35)
con las 76 tareas históricas F0–F6 conservadas. El cierre
de H4 lleva el supervisor horizontal a 48/72 tareas. H5 mantiene la revisión
integral del rediseño y H6 la entrega, publicación y aceptación operativa.
La jornada real de F4 y su seguimiento no se cierran con estos ensayos.
Tasa baja continúa OFF; Jev no está integrado.

Evidencia estructurada y huellas: [JSON H4](SUPERVISOR-HORIZONTAL-H4-EVIDENCIA-2026-09-23.json).
[Plan general en Figma](assets/supervisor-horizontal-h4-cerrada-figma-2026-09-23.png) · [Detalle H4](assets/supervisor-horizontal-h4-detalle-figma-2026-09-23.png).
