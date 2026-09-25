---
tags: [crm, gestion-diaria, f6, preparacion]
actualizado: 2026-09-24
---

# Cola completa preparada para Gestión Diaria

Continúa [[Gestion Diaria - F4.1 apagada y F5 en desarrollo (2026-09-24)]].
**Preparación aditiva verificada, sin publicar ni retirar Seguimiento.**

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

La preparación F6 está en el PR #97, en borrador, sin publicar. Los siete días
reales empiezan en ese T0 y no se cumplen antes del 01/10 a las 21:57:11 Lima.
La retirada exige estabilidad acreditada y ausencia de incidencias relevantes;
el corte del sábado 26/09 sigue pendiente. No solicitar otra conformidad manual.

Evidencia: `CRM-Avance-Corp/docs/gestion-diaria/f6-preparacion-2026-09-24/ACTA.md`,
`REVISION-F6-PREPARACION-2026-09-24.md`, `PREPARACION-F6-2026-09-24.md` y
`OBSERVACION-F3-F5.md`. Rama propia `codex/gestion-diaria-f6-preparacion-20260924`
en la copia separada ya autorizada. Véase [[Inicio]].
