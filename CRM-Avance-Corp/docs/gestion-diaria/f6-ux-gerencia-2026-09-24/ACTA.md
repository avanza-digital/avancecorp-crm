# F6 — Integración horizontal de gerencia

**Publicada y verificada el 25/09/2026.** [Acta productiva](PUBLICACION-2026-09-25.md).
Fuente propia `0aab1d50`, integrada sin conflictos con Main `3027028d`
(PR #100 ajeno a esta tarea) en `60ae8015`. Mejoras finales de foco y pruebas
en `4a4cb1ec`, código probado y conservado en la publicación.
Rama `codex/gestion-diaria-f6-ux-gerencia-20260924`, en la copia separada
autorizada. [Contrato](CONTRATO.md) y [plan F6](../PREPARACION-F6-2026-09-24.md).
[PR #101](https://github.com/avanza-digital/avancecorp-crm/pull/101): integrado
en `f9196dba` sin revisión APPROVED; Miguel autorizó expresamente su publicación
tomando esa integración manual como aprobación. [Estado productivo y evidencia](PUBLICACION-2026-09-25.md).

## Comportamiento

Gerencia conserva sus ocho indicadores, el día anterior completo y la
referencia histórica. La cabecera reúne fecha, registro general y seguimiento.
La tabla inicial compara equipos; elegir uno muestra sus analistas en el área
principal y el resumen o registro en el panel lateral. En ancho insuficiente,
el detalle usa el diálogo adaptable ya probado en supervisión.

Hábitos permite buscar y comparar personas, filtrar por equipo y ordenar por
llamadas, contacto, mediana o proporción de cortes a tiempo. El detalle mantiene
contacto personal/equipo/operación, distribución, cortes, primera llamada,
huecos y sus intervalos, y silencios de apertura/cierre. La alerta de tasa baja
sigue apagada. Las ventanas continúan siendo 7, 14 y 30 días.

Los filtros no recalculan los totales globales. Los pendientes conservan su
fecha actual. Se mantienen los autores fuera del organigrama, los registros sin
autor, el CSV de filas cargadas y el recorrido hasta la ficha autorizada.
No hay cambios en SQL, RPC, RLS, dependencias ni roles autorizados.

Abrir una ficha, ampliar/restaurar o redimensionar conserva filtros, páginas
y estado del panel. Volver a la operación conserva la búsqueda de equipos.
Una fecha o ventana de hábitos distinta inicia otro contexto y reinicia sus
filtros y selección locales. Cambiar de identidad descarta la memoria anterior.

Después de visitar el registro general, se conserva montado y oculto al volver
al registro del equipo o analista. Esto preserva filtros y páginas; la primera
página puede seguir refrescándose cada minuto. F5 ya mantenía ambos registros
montados; la nueva vista difiere el general hasta que se solicita y no consulta
un registro por cada fila.

## Revisión independiente y correcciones

Primera revisión: **CHANGES_REQUESTED**. Se aceptaron y corrigieron:

- P1: una denegación del Pulso podía dejar Hábitos visible.
- P2: la denegación de un registro no se propagaba a toda la vista.
- P2: los enlaces de regreso podían perder el foco al desmontar el panel.
- P3: origen de foco con ratón en WebKit y detalle del equipo al ensanchar.

Una denegación `42501` en Pulso, Hábitos, detalle o Registro ahora retira toda
la vista. Persiste al cambiar de pestaña o fecha. «Verificar sesión» reinicia
la aplicación y sus consultas; no recupera páginas anteriores desde la caché.
Los errores de red mantienen la acción «Reintentar» existente.
El PRIMARY comprobó `main.tsx` y `lib/query-client.ts`: un QueryClient en
memoria, sin persistencia, y limpieza al perder Auth. El aviso de Registro
se propaga desde un efecto (`registro-actividad.tsx`), no durante su render.

El refresco del registro oculto se acepta por la conservación de contexto
descrita arriba. La segunda revisión dirigida dio **PASS**. Su hipótesis de
orden de foco se contrastó con WebKit: 10/0, incluidos los regresos móviles a
operación y equipo. Se aceptaron además sus mejoras opcionales de foco al
revocar y enlace con tecla modificadora, ya cubiertas por el gate y WebKit
finales. Se ocultó el selector de período al denegar el acceso; pausar también
el polling queda como mejora de eficiencia, sin exposición de datos.
[Revisión 1](REVIEW-1.md), [revisión 2](REVIEW-2.md). No se abre otra consulta.

## Evidencia ejecutada

| Control | Resultado y límite |
| --- | --- |
| Gate anterior a las correcciones de revisión | PASS: 4.396 tests / 297 archivos; lint, tipos, cobertura, release-config, push, build, bundle y duplicación |
| Componentes después de las correcciones | PASS: 26 tests; incluye denegación entre pestañas, registros general/individual, cambio de cuenta, carga y vacío |
| Chromium dirigido después de las correcciones | PASS: 9 / 0, Docker, sin reintentos; antes de integrar Main #100 |
| WebKit dirigido inicial | PASS: 7 / 0, Docker, sin reintentos; anterior a las correcciones de revisión |
| WebKit después de las correcciones de revisión | PASS: 9 / 0 sobre `60ae8015`, sin reintentos |
| Gate final con Main #100 y mejoras opcionales (`4a4cb1ec`) | PASS: 4.421 tests / 298 archivos, resto de controles incluidos |
| WebKit final (`4a4cb1ec`) | PASS: 10 / 0, Docker, un worker, sin reintentos |
| Chromium completo (`4a4cb1ec`) | PASS: 270 / 0; 26 omisiones previstas, Docker, dos workers, sin reintentos (10,1 min) |
| Publicación de esta integración y retirada de Seguimiento | NOT RUN |

La primera corrida de WebKit coincidió con el gate integral y falló durante
el arranque/splash. Se detuvo únicamente el contenedor de esta tarea; la
corrida aislada con un worker completó 7/0. No se atribuye aquel intento como
PASS. La primera iteración de Chromium encontró dos fallos de foco/semántica,
corregidos antes del 7/0 y del 9/0 posteriores.

Las capturas usan datos sintéticos. `capturas-chromium/` conserva operación,
equipo, analista, hábitos, detalle ampliado y móvil; `capturas-webkit/` conserva
la comprobación adicional del motor WebKit. Se inspeccionaron visualmente
legibilidad, separación entre tabla y detalle y ausencia de desbordamiento.
Las 26 omisiones son las previstas en `clientes.spec.ts` y `contratos.spec.ts`.
El lint conserva cinco advertencias anteriores en archivos compartidos que este
cambio no modifica. Los E2E comprueban también densidad sin scroll de página en escritorio,
teclado/foco, filtros, 26 registros paginados, Escape de ficha anidada, fechas,
exportación, error y revocación. No sustituyen las pruebas reales de RLS de F5.

## Publicación y cierre pendiente de F6

La validación y la revisión independiente están cerradas. El [mismo Figma](https://www.figma.com/board/9Pg7jMDRg3UVbb4XfeM80L),
el plan y el vault reflejan la UX publicada desde `f9196dba`: 81/81 archivos
servidos y ocho comprobaciones productivas PASS. La autorización específica
para F6 y el acceso Hostinger quedaron resueltos. [Acta productiva](PUBLICACION-2026-09-25.md)
y [validación técnica](VALIDACION.json).
La retirada de Seguimiento requiere siete días reales estables desde el T0
de F5: **no antes del 01/10/2026 a las 21:57:11 Lima**. La publicación no
acredita por sí sola esa observación.
