# F6 — Preparación para absorber Seguimiento

24/09/2026. **Cola completa implementada y verificada; retirada NOT RUN.**
F5 todavía no está publicada y verificada. El período obligatorio de siete días
estables no ha comenzado. Referencia: [plan de ejecución](EJECUCION-F4-1-F6-2026-09-24.md).
El [registro de observación](OBSERVACION-F3-F5.md) deja preparados el inicio,
las evidencias diarias y la conciliación de lectura sin atribuir días cumplidos.

## Capacidades que deben conservarse

Inspección del código vigente en la copia de F5. CodeGraph se consultó primero;
no localizó los componentes nuevos, por lo que se completó con lectura dirigida.
Las rutas siguientes son relativas a `CRM-Avance-Corp/app`.

| Capacidad actual | Evidencia | Equivalente y trabajo pendiente |
| --- | --- | --- |
| Entrada lateral y título de Seguimiento | `src/components/app/sidebar.tsx`, `topbar.tsx` | Retirar la entrada duplicada únicamente después del período estable. Gestión Diaria será el acceso único. |
| Vendedor, supervisor y gerencia; denegación a coordinación/directorio sin otro rol operativo | `src/lib/vistas.ts`, `vistas.test.ts` | Conservar exactamente esta matriz. La autorización de una RPC global no amplía por sí sola las vistas del directorio. |
| Modo SLA, error, demo y cambio de revisión | `src/screens/seguimiento.tsx`, `SlaOperacionBoundary` en `src/components/app/sla-operacion.tsx` | Reutilizar la misma frontera al trasladar la cola; no confundir una consulta fallida o el modo apagado con cero pendientes. |
| Cola completa, conteos del servidor y filtros de señal, etapa y analista | `ColaSlaPanel` y `useColaSlaPagina` en `src/data/sla-operacion-queries.ts` | Incorporar la cola existente a Gestión Diaria para cada rol. Reutilizar el componente y la RPC, sin crear otro contador. |
| Paginación 10/25/50 por cursor, anterior/siguiente, reinicio por invalidación o cursor vencido | `ColaSlaPanel` | Preservar páginas más allá de 100 y el foco al navegar. La cola de F3 (`src/screens/gestion-diaria/analista.tsx`, `LIMITE_COLA=100`) todavía no es equivalente. |
| Señales comerciales, revisiones, por repartir y todas las acciones | `ColaSlaPanel`, `src/lib/sla-operacion.ts` | Preservar señales visibles por rol y sus denominadores. Los pendientes de tareas de F4 y las tarjetas de F5 no sustituyen toda esta cola. |
| Abrir ficha con autorización vigente y error explícito | `ColaSlaPanel.abrirFicha`, `abrirLead` | Mantener comprobación al abrir; cerrar ficha conserva filtros, página y contexto de Gestión Diaria. |
| Enlaces `#/seguimiento` y `#/seguimiento/lead/<id>` | `src/lib/router.ts`, `src/App.tsx` | Preparar alias hacia la sección de cola de Gestión Diaria, conservando el lead y pasando por la matriz de roles. No redirigir a una pantalla que solo presenta el resumen. |
| Avisos con destino Seguimiento y textos «hay más» | `src/components/gestion-diaria/avisos-equipo.test.tsx`, `cola-de-hoy.tsx` | Cambiar destinos y mensajes al acceso equivalente; probar también avisos y enlaces ya guardados. |
| Confirmación de guardados SLA pendientes global y dentro de la ficha modal | `GuardadosSlaPendientesGlobal` en `App.tsx`, `EstadoSlaFicha` en `sla-operacion.tsx` | Conservar ambos montajes. La copia global es inaccesible cuando la ficha modal deja inerte el fondo; eliminar la pantalla antigua no autoriza eliminar esta protección. |

## Secuencia de implementación y publicación futura

1. Añadir un acceso explícito a la cola completa dentro de Gestión Diaria para
   vendedor, supervisor y gerencia, reutilizando `ColaSlaPanel` y su frontera.
   La fecha del tablero no convierte los pendientes actuales en una fotografía
   histórica. Mantener esa distinción visible.
2. Conservar temporalmente ambos accesos mientras se comprueba equivalencia.
   Verificar filtros, conteos, páginas, acciones, apertura de ficha y permisos.
3. Registrar la fecha/hora y el commit de publicación verificada de F5. Desde
   ese instante acumular al menos siete días reales de estabilidad de F3–F5.
   Una prueba sintética, la conformidad anterior o siete días desde F4 no
   sustituyen esta observación. Registrar incidencias y su cierre con evidencia.
4. Una vez acreditado el período y sin incidencias bloqueantes pendientes,
   convertir rutas antiguas en alias seguros, retirar la entrada lateral y el
   contenedor de pantalla duplicados. Conservar componentes compartidos,
   datos, RPC, permisos y guardados pendientes.
5. Ejecutar gates, revisión proporcional, Docker E2E, publicación desde Main
   verificado y comprobación viva de enlaces antiguos. Actualizar el mismo
   tablero de Figma y el vault con el acta final.

## Pruebas exigidas antes de retirar

| Caso | Resultado requerido | Estado F6 |
| --- | --- | --- |
| Matriz de roles, sesión revocada y cambio de cuenta | Mismos permisos, sin datos anteriores visibles ni nuevas capacidades | NOT RUN |
| 101 o más oportunidades, filtros y páginas 10/25/50 | Poder llegar a todas; conteos completos del servidor y cursor válido | NOT RUN |
| Caducidad del cursor, nueva gestión y actualización | Reiniciar posición sin omisiones ni duplicados; error recuperable | NOT RUN |
| Acceso antiguo directo, con lead, recarga y atrás/adelante | Llegar a la cola/ficha autorizada y conservar el contexto al cerrar | NOT RUN |
| Avisos antiguos y actuales, recuperación de guardados pendientes | Destino equivalente y acciones accesibles también dentro del modal | NOT RUN |
| SLA apagado, demo, vacío real y error de red | Estados distintos, sin ceros inferidos | NOT RUN |
| Teclado, foco, móvil y zoom | Acceso completo a filtros, páginas y ficha | NOT RUN |
| Siete días reales F3–F5, acta y ausencia de incidencias abiertas relevantes | Evidencia temporal verificable y decisión de retirada registrada | NOT RUN |

Reutilizar como base `src/components/app/sla-operacion.test.tsx`,
`src/lib/vistas.test.ts`, `src/lib/router.test.ts` y `e2e/sla-operacion.spec.ts`,
ampliando los recorridos de Gestión Diaria. Que estos tests anteriores pasen no
acredita la futura redirección.

## Recuperación

La absorción propuesta no elimina datos ni RPC. Ante una regresión de acceso,
restablecer la entrada y el contenedor de Seguimiento del artefacto anterior
verificado, conservando Gestión Diaria. Comprobar enlaces y permisos después de
restaurar. No eliminar los alias ni el código compartido durante la observación.

**Criterio de cierre:** cola equivalente demostrada, siete días acreditados,
retirada y publicación verificadas. Este documento prepara ese trabajo; no lo
declara ejecutado.

## Preparación implementada después del inventario

La rama `codex/gestion-diaria-f6-preparacion-20260924`, sobre el árbol F5
integrado en Main `8da4bcf3`, añade `#/gestion-diaria/cola[/lead/<id>]` y
reutiliza exactamente `ColaSlaPanel` y su frontera mediante `ColaSeguimiento`.
El resumen parcial ofrece «Ver todas las oportunidades». El supervisor usa
su cabecera existente para conservar la densidad. Ambos accesos y enlaces
antiguos siguen disponibles; no se implementó todavía su redirección final.

La matriz anterior enumera los gates de la retirada futura. La evidencia de
preparación queda separada en [ACTA.md](f6-preparacion-2026-09-24/ACTA.md):
permisos de UI, cambios de cuenta, cursor vencido, revocación, páginas 10/25/50
hasta 105 oportunidades, ficha fuera del lote, teclado/móvil, estados vacíos,
SLA apagado, demo y enlaces actuales. Las pruebas de alias futuros, publicación
y período real continúan NOT RUN. No hay SQL ni cambios de política de permisos.
