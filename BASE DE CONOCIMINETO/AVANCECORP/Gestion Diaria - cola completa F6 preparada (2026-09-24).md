---
tags: [crm, gestion-diaria, f6, preparacion]
actualizado: 2026-09-24
---

# Cola completa preparada para Gestión Diaria

Continúa [[Gestion Diaria - F4.1 apagada y F5 en desarrollo (2026-09-24)]].
**Preparación aditiva verificada, sin publicar ni retirar Seguimiento.**

**Ampliación de F6 solicitada por Miguel el 24/09:** integrar para gerencia la
UX/UI horizontal ya aprobada e implementada para supervisores. Reutilizar
cabecera y resumen compactos, tabla comparativa y detalle lateral, filtros y
navegación con contexto y foco conservados; adaptar los datos y las acciones a
toda la operación, equipos y supervisores, pulso y hábitos y recorrido hasta
analista, registro y ficha. Conservar las cifras y permisos de F5.

Esta integración gerencial está **implementada y validada localmente**.
Véase [[Gestion Diaria - UX horizontal de gerencia preparada (2026-09-25)]];
revisión normal de GitHub y publicación pendientes.
Es una entrega obligatoria añadida al goal y puede prepararse durante la
observación. Requiere evidencia visual, legibilidad/densidad, móvil/teclado y
regresión de los recorridos; los PASS anteriores de la cola no acreditan el
alcance nuevo. El período de siete días sigue condicionando la retirada final.
El plan ejecutable está en `EJECUCION-F4-1-F6-2026-09-24.md` y
`PREPARACION-F6-2026-09-24.md`; enlaza con
[[Gestion Diaria - F5 publicada y F6 en observacion (2026-09-24)]].

Analista, supervisor y gerencia pueden acceder a la cola completa desde Gestión
Diaria. Reutiliza consultas, filtros, conteos del servidor y páginas por cursor
de 10/25/50. La fecha del resumen no cambia los pendientes actuales; se explica
en pantalla. La ruta admite ficha de lead y conserva página/filtros al cerrarla.
Recargar o cambiar de sección reinicia la cola, como el módulo anterior.

Se preservan Seguimiento, su menú, sus enlaces antiguos y los guardados SLA
pendientes. No se modifica SQL ni la política de roles. Coordinación y directorio
no obtienen acceso al módulo por el nuevo enlace.

La primera regresión encontró tres fallos de densidad (68 px de desbordamiento).
El acceso se integró en la cabecera del supervisor, sin reducir texto ni cambiar
las tolerancias de pruebas. Evidencia: gate 4.393/297 PASS, cola/equipo/cortes
19/19 PASS, nueve recorridos de cola PASS. Dos reviews independientes PASS;
una hipótesis de altura fija en gerencia se descartó con su CSS real. La
regresión completa terminó con Chromium 265/0/26 y WebKit 14/0 PASS, sin
reintentos. La configuración WebKit está versionada; lint/tipos finales PASS. El primer
FAIL permanece documentado, junto con las limitaciones de las pruebas de UI.

F5 fue integrada externamente en Main `8da4bcf3` sin revisión APPROVED.
Miguel autorizó después usar esa integración para publicar F5. SQL y frontend
quedaron verificados desde `b402a7f1` el 24/09 a las 21:57:11 Lima. Véase
[[Gestion Diaria - F5 publicada y F6 en observacion (2026-09-24)]].

El PR #97 fue integrado externamente en Main `3b792867` el 24/09 a las
22:22:44 Lima, con sus tres controles PASS y sin revisión APPROVED. El árbol
coincide con el candidato. La preparación F6 continúa sin publicar; el cotejo
HTTPS posterior confirma F5 `b402a7f1`. Los siete días
reales empiezan en ese T0 y no se cumplen antes del 01/10 a las 21:57:11 Lima.
La retirada exige estabilidad acreditada y ausencia de incidencias relevantes;
el corte del sábado 26/09 sigue pendiente. No solicitar otra conformidad manual.

Evidencia: `CRM-Avance-Corp/docs/gestion-diaria/f6-preparacion-2026-09-24/ACTA.md`,
`REVISION-F6-PREPARACION-2026-09-24.md`, `PREPARACION-F6-2026-09-24.md` y
`OBSERVACION-F3-F5.md`. Rama propia `codex/gestion-diaria-f6-preparacion-20260924`
en la copia separada ya autorizada. Véase [[Inicio]].
