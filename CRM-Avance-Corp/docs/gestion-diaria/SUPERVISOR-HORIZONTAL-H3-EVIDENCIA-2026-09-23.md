# Supervisor horizontal: H3 cerrada

**23/09/2026 · cuatro etapas y doce tareas completas.** Resumen, Registro y
Pendientes están conectados; el contexto se conserva al cambiar de pestaña,
ampliar y regresar desde la ficha. La consulta nueva está instalada y verificada
**sólo en un banco local aislado**. No se publicó en producción.

[Plan canónico](GESTION-DIARIA.md) · [Figma actualizado](https://www.figma.com/board/9Pg7jMDRg3UVbb4XfeM80L?node-id=18-27) ·
[Evidencia JSON](SUPERVISOR-HORIZONTAL-H3-EVIDENCIA-2026-09-23.json) ·
[Revisión y resolución](SUPERVISOR-HORIZONTAL-H3-REVISION-2026-09-23.md).

## Entrega por etapa

| Etapa | Resultado comprobado |
| --- | --- |
| H3.1 Resumen | Métricas del roster completo, ocho cifras y 13 horas existentes; últimas tres gestiones desde la misma primera página de Registro → Todo. Estado de lectura independiente y hora de consulta. |
| H3.2 Registro y ficha | Montaje bajo demanda; cuatro pestañas internas, filtros y cursor conservados. La ficha superpuesta devuelve el foco y mantiene las páginas. Ámbito de equipo separado. |
| H3.3 Pendientes | Todas/Vencidas, páginas de 25, totales previos al filtro, tres referencias y apertura sólo del lead autorizado. Backend invoker/RLS y validación estricta sin descartar filas dañadas. |
| H3.4 Contexto | Caché por identidad, rol, demo, día, persona, filtro y apertura; respuesta tardía no cruza ámbitos. 42501 cancela y limpia todas las variantes de la lista y revalida equipo. Refresco y selección conservan contexto. |

La lista se consulta al visitar Pendientes. Una página se actualiza cada minuto
mientras está visible; con dos o más, todas quedan congeladas y se informa su
antigüedad. Actualizar empieza desde cero, conservando el filtro. Las páginas
no prometen una transacción histórica: inserciones/reprogramaciones pueden
mover tareas. Se deduplican IDs y se conserva la hora de cada consulta.

Se distingue ausencia confirmada de error, permiso revocado y función no
instalada. Un fallo de red al cargar más puede conservar filas anteriores con
aviso; jamás se usa una respuesta parcial como prueba de lista completa.

## Backend y compatibilidad

Nueva migración: `20260923234404_crm_gestion_diaria_pendientes_supervisor.sql`.
SHA-256: `a61d0b30be5781f9f04b6486b2eaa1599c9bcada5d2e5ce35ddab2bc7acdba73`.

`crm.gestion_diaria_pendientes_fn` y su núcleo son INVOKER, search_path vacío,
EXECUTE sólo authenticated y guard interno que exige supervisor activo. El
analista debe pertenecer al roster activo canónico. El helper de pertenencia se
comparte con el agregado de equipo, cuya paridad completa antes/después está
probada para supervisor, gerencia/global, puente inactivo y ciclo.

Se filtra por responsable de la tarea, independientemente del propietario
actual del lead. Perfil y postventa se incluyen bajo RLS sin revelar sus IDs
privados. Lead oculto conserva la tarea con referencia nula. Resumen y página
comparten sentencia; orden por vencimiento/UUID y cursor con microsegundos.
No se cambiaron tablas, políticas, grants de columnas ni reglas de negocio.

[Banco reproducible y reversa](../../supabase/scripts/gestion-diaria-horizontal/README.md).
La copia HTTP y su contenedor propios se retiraron al finalizar. La copia SQL
H3 conserva el candidato; el banco F4 original y producción permanecieron intactos.

## Verificación

| Control | Resultado |
| --- | --- |
| `npm run check` final | **PASS**, 4.244 pruebas / 284 archivos; lint, tipos, cobertura, configuración, worker, build, bundle y duplicación. |
| E2E completo, Docker local | **PASS**, 241 aprobadas / 0 fallos / 26 omitidas, 9,8 min. |
| E2E dirigido final tras ajustes menores | **PASS**, 14/14, 32,3 s; supervisor, registro por rol, pendientes y densidad H2. |
| Capturas finales de escritorio y móvil | **PASS**, 4/4 E2E, 11,3 s; espera explícita del menú colapsado, sin cambios del producto. Inspección visual satisfactoria. |
| SQL / RLS / paridad / reversa / replay | **PASS**, 1.008 tareas en 11 páginas; tres anclas, límites, empate, vacío, integridad, concurrencia, referencia revocada, roles, actor/miembro inactivo, anon y núcleo directo. 7 mutantes nuevos y 9 anteriores. |
| HTTP real PostgREST 14.5 | **PASS**, 1.008/11, cuatro roles denegados, ajeno, anon, 22023 y revocación con el mismo JWT. |
| Tipos | **PASS**, generados desde la copia instalada y cotejados con el miembro RPC del cliente. |
| Scripts / Edge | **PASS**, `check:scripts`, sintaxis de scripts H3 y `test:edge-preflight`. |
| Seed/RLS preflight | **PASS offline**, variables sintéticas de loopback; no se abrió conexión. El primer intento sin variables se detuvo como estaba previsto. |
| Lint de SQL H3 | **PASS**, sin avisos en funciones nuevas; el catálogo completo conserva 32 funciones con avisos anteriores, incluidos seis errores por vault/cron ausentes en la copia. No se presenta como un PASS global. |
| Revisión independiente | **PASS de Claude**, confianza MEDIUM; observaciones P3 y huecos de evidencia tratados en el acta. |
| Figma | **PASS**, 36/72 tareas completas, otras 36 pendientes y 76 casillas originales intactas. Lectura posterior y capturas inspeccionadas sin recortes/solapamientos. |

En el fixture local, cinco lecturas de 25 elementos sobre 1.008 tareas tardaron
19,386 / 11,132 / 12,148 / 11,588 / 11,015 ms bajo authenticated. No representan
latencia ni carga de producción. Resumen y Registro comparten una consulta;
seleccionar una fila no descarga sus pendientes. Sin consultas de tareas por fila.

Durante la preparación hubo un ensayo HTTP detenido hasta completar la caché
de PostgREST (503) y una medición concurrente con la reversa que no encontró la
función. Se corrigió la espera del servicio y se ejecutaron los comandos SQL
secuencialmente. Las corridas finales citadas arriba pasaron. No son fallos
ocultados de una suite final ni resultados atribuidos al entorno productivo.

## Límites y siguiente fase

- `gate:realidad`: **NOT RUN**, falta SUPABASE_URL en la copia. No se conectaron
  secretos de producción para sustituir ese gate.
- Matriz general remota `test-rls.mjs` y advisors hosted: **NOT RUN**, no se creó
  un candidato hosted. Sí se ejecutó la matriz SQL/HTTP pertinente en la copia
  local autorizada. H6 revalidará el candidato contra la base vigente.
- Lectores NVDA/VoiceOver humanos: **NOT RUN**. Sí se probaron semántica, teclado,
  foco, mobile/reflow y controles de 44 px. Se conservan cinco warnings de lint
  anteriores (cuatro coverflow y una celda Contacto H2), sin desactivar reglas.
- La primera página compartida del Registro puede reutilizarse durante 60 s.
  Si Actualizar coincide con una petición ya en curso, se une a ella. La hora
  de consulta queda visible; no se usa esta lectura para confirmar escrituras.
- Sin publicación, PR ni merge productivo. H6 instala primero el SQL aditivo
  comprobado y después su cliente desde Main verificado. H4–H6 siguen pendientes.
- La jornada real de F4, cortes del 24/09 y sábado 26/09, conserva su seguimiento;
  tasa baja sigue OFF. Jev no se integró en esta interfaz.

Siguiente paso: **H4.1, compactar el estado de los cortes e integrar avisos**.
La copia de trabajo sigue en `/private/tmp/avancecorp-release.hvdub4/repo`, rama
`codex/gestion-diaria-supervisor-horizontal`; base Main `cf87e808`, checkpoint H2
`e6cc6c5b`. El taller principal conserva sus cambios ajenos.

## Capturas

[Pendientes en escritorio](assets/supervisor-horizontal-h3-escritorio-2026-09-23.png) ·
[Pendientes en móvil](assets/supervisor-horizontal-h3-movil-2026-09-23.png) ·
[Plan completo actualizado](assets/supervisor-horizontal-h3-cerrada-figma-2026-09-23.png) ·
[Detalle H3 en Figma](assets/supervisor-horizontal-h3-detalle-figma-2026-09-23.png).

Los datos de las capturas son ficticios. Los registros de ejecución saneados
están en [evidencias-h3-2026-09-23](evidencias-h3-2026-09-23/).
