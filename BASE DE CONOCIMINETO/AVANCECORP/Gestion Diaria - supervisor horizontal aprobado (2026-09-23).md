# Gestión Diaria — supervisor horizontal aprobado

Miguel considera que la vista de supervisión exige demasiado desplazamiento
vertical. Aprobó el nuevo prototipo horizontal («perfecto perfecto») y pidió
un plan para desarrollarlo, con apoyo de Claude/Jev si hacía falta, recordando
que debe actualizarse **el mismo archivo de Figma**.

**Estado: H1–H3 CERRADAS; H4–H6 pendientes; sin publicación.**

**Retoma guardada:** Miguel aprobó el plan de H4 y pidió detenerse para seguir
en unas horas. H4 sigue sin implementar; retomar desde **H4.1**. H3 está en
`fa23ab5e`, después del checkpoint H2 `e6cc6c5b`. Ubicación y objetivo completos:
`CRM-Avance-Corp/docs/gestion-diaria/SUPERVISOR-HORIZONTAL-RETOMA.md`.
Respaldo incremental de la rama en
`/Users/usuario/.local/share/avancecorp-checkpoints/supervisor-horizontal-2026-09-23.bundle`.
Figma conserva 36/72 completas y el plan H4 pendiente en el mismo tablero.

El [PR #85](https://github.com/avanza-digital/avancecorp-crm/pull/85) está fusionado
desde el 23/09 a las 21:35 UTC, Main `e0bdfe124c48ab32617c72402e320c7e9963dc3b`.
Se retomó desde ese cierre; no se publicó producto por esta planificación.

## Plan y referencia

- [Mismo tablero de Figma, bloque Supervisor horizontal](https://www.figma.com/board/9Pg7jMDRg3UVbb4XfeM80L?node-id=18-2).
- Plan canónico: `CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md`,
  sección «Supervisor horizontal — diseño aprobado y plan de desarrollo».
- Correspondencia de nodos: `FIGMA-PLAN.json` → `supervisorHorizontal`.
- Referencia: `assets/supervisor-horizontal-aprobado-2026-09-23.png`, dentro
  de esa carpeta. Imagen ficticia; no cambia los contratos de datos del CRM.

Por petición posterior de Miguel, el tablero desarrolla la imagen aprobada en
**seis fases H1–H6, 24 etapas y 72 tareas**, cada fase con objetivo específico,
dependencia, entregable y criterio de cierre. Las etapas tienen tareas y
resultado propio. Las fases son preparación/especificación; vista horizontal;
panel conectado; cortes/avisos; verificación; entrega/aceptación.
H1–H3 completan doce etapas y 36 tareas; quedan 36 tareas de H4–H6 pendientes. El plan general conserva su revisión histórica; H1 tiene revisión
independiente y resolución registradas en su propia acta.
Composición inspeccionada y 76 casillas originales conservadas, sin alterar F4–F6.

## Decisiones duraderas

Tabla a la izquierda y panel a la derecha, aproximadamente 70/30. Cabecera e
indicadores compactos. Resumen/Registro/Pendientes dentro del panel. Cortes y
otros avisos en una franja con detalle bajo demanda. Meta de diez filas a
1512 × 805 para contenido típico; nombres largos pueden ocupar más altura.
Texto mínimo 16 px, controles 44 px, adaptación para móvil y zoom.

Claude revisó el plan mediante el wrapper: **CHANGES_REQUESTED**, confianza
MEDIUM. Codex incorporó las observaciones con evidencia en
`SUPERVISOR-HORIZONTAL-REVISION-2026-09-23.md`; no hubo segunda revisión ni se
afirma PASS del reviewer. Jev no es necesario para este cambio de interfaz.

El panel debe sobrevivir a un fallo temporal del resumen, separar pestañas
externas/internas y conservar filtros y cursor. Selección ligada a actor, día
Lima y persona. Comparar personas desde la tabla no debe robar el foco.
Resumen usa el equipo presentado completo, no las filas filtradas. «Ver
pendientes» abre el listado de la persona: H1 decidió una RPC nueva de lectura
paginada en H3.3, ya implementada y comprobada en banco local, sin cambios de reglas ni RLS.
Registro del equipo muestra solo Registro, con espacio ampliable.

Próximo paso: **H4.1**, estado compacto de cortes e integración de avisos. H1 se ejecutó en
la copia aislada `/private/tmp/avancecorp-release.hvdub4/repo`, rama
`codex/gestion-diaria-supervisor-horizontal`, Main verificado `cf87e808` (#86).
El taller principal permanece intacto. H2 modifica producto solamente en la copia aislada.

Especificación: `CRM-Avance-Corp/docs/gestion-diaria/SUPERVISOR-HORIZONTAL-H1-ESPECIFICACION-2026-09-23.md`.
Datos, medidas y cada acción definidos; evidencia y revisión en esa carpeta.
En H1 la fila anterior medía 149 px; se especificó una fila típica de 44 px. A 1512 × 805: tabla 960,
separación 16, panel 414; diez filas típicas. Panel mínimo 380; a 1366 × 768,
nueve filas típicas. Texto de 16 px y controles de 44 px. H2 verificó la densidad; las regiones de tabla miden 970/858 px en Chromium
(sin scrollbar de página), con filas típicas 44 px y panel 414/380 px.

Las fuentes actuales no ofrecen una página propia estricta de tareas por
analista: se especificó `crm.gestion_diaria_pendientes_fn` para H3.3, con
autorización, paginación, estados y pruebas de paridad/permisos. No se instaló
SQL ni se publicó producto durante H1. Pruebas de producto durante H1: NOT RUN por alcance
documental; H2 tiene los resultados indicados abajo. Figma mantiene el mismo archivo y las 76 casillas originales.

F4 conserva la primera jornada real del 24/09 (11:30 y 16:00 Lima) y seguimiento
del sábado 26/09. Tasa baja OFF hasta F5. No reinstalar SQL ni generar actividad
productiva ficticia. La aceptación de la imagen no cierra el recorrido de uso.

[[Gestion Diaria - plan vivo en Figma y mejora visual (2026-09-23)]] ·
[[Fundamentos UX del CRM]] ·
[[Gestion Diaria F4 - publicado y cortes programados para el 24-09 (2026-09-23)]] ·
[[Inicio]]

## Cierre H2 — 23/09/2026

Las cuatro etapas y doce tareas de H2 están cerradas: cabecera/KPI, seis columnas,
panel estable y adaptación. `npm run check`: 4.192 tests en 280 archivos y build PASS.
E2E final Docker 29/29; suite completa inicial 234 PASS/3 FAIL/26 omitidos, con los
archivos de los tres fallos repetidos dentro del banco final. No ocultar ese historial.
`gate:realidad` NOT RUN por falta de SUPABASE_URL en la copia. Sin SQL ni publicación.

Claude: CHANGES_REQUESTED/MEDIUM; Codex resolvió foco/accesibilidad con evidencia.
Acta y capturas: `CRM-Avance-Corp/docs/gestion-diaria/SUPERVISOR-HORIZONTAL-H2-EVIDENCIA-2026-09-23.md`.
Portal estable conserva Registro al ampliar/resize; lista con 42501 vacía y revalida.
Aviso→Registro transfiere el foco tras cerrar el diálogo auxiliar. Las medidas
son 10 filas a 1512 × 805 y 9 a 1366 × 768; móvil 390 y reflow al 200 % verificados.

H3.3 sigue pendiente: el listado de tareas no existe todavía en el panel. H2
muestra agregados y señales con disponibilidad explícita. H4–H6 conservan su alcance.

## H3 cerrada: panel conectado

Cuatro etapas y doce tareas verificadas en la misma copia aislada. H2 quedó
conservada en el checkpoint local `e6cc6c5b` antes de iniciar H3.

Últimas tres gestiones comparten Registro → Todo; no descargan otra fuente.
Registro, filtros, páginas y retorno desde ficha conservan contexto. Pendientes
se carga al visitarlo: Todas/Vencidas y 25 elementos por página. Desde la segunda
página se pausa toda la actualización automática; Actualizar reinicia y conserva
el filtro. Una denegación 42501 elimina las páginas y variantes de caché del
analista. Error, vacío y RPC no instalada se distinguen.

La nueva RPC invoker comparte roster con equipo; no cambia políticas ni reglas.
SQL/RLS y HTTP real recorrieron 1.008 tareas en 11 páginas, incluidas referencias
lead/perfil/postventa, tareas con lead ya oculto, revocación y núcleo directo.
Paridad completa de equipo antes/después, puente inactivo/ciclo, errores,
reversa/replay y tipos PASS. Banco local propio; producción no instalada.

Gate integral: **4.244 pruebas PASS**. E2E Docker completo: **241 PASS / 0 fallos /
26 omitidas**; dirigido final: **14/14 PASS**. Claude **PASS, MEDIUM**, con P3
resueltos o documentados. Reality gate y matriz remota general/advisors hosted
NOT RUN; ver acta para límites. Sin lectores humanos NVDA/VoiceOver.

Figma actualizado y capturas inspeccionadas: **36/72 completas**, otras 36
pendientes, 76 casillas históricas intactas. Acta:
`CRM-Avance-Corp/docs/gestion-diaria/SUPERVISOR-HORIZONTAL-H3-EVIDENCIA-2026-09-23.md`.
H4–H6, publicación y aceptación productiva permanecen pendientes; no cierran
la jornada real de F4 ni activan tasa baja o Jev.

[[Gestion Diaria - plan vivo en Figma y mejora visual (2026-09-23)]] · [[Inicio]]
