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

F5 fue integrada externamente en Main `8da4bcf3` sin una revisión APPROVED
registrada. Sus controles pasaron, pero SQL/frontend no están publicados.
Hostinger ya está accesible con el token autorizado y guardado en Llavero;
la herramienta de despliegue está disponible. Falta resolver la condición de
revisión GitHub antes de publicar. No solicitar otra conformidad de negocio.

Los siete días reales de F3–F5 todavía no empiezan. T0 exige SQL promovida,
frontend publicado y verificación viva; solo después puede retirarse el módulo
anterior. El corte del sábado 26/09 sigue pendiente.

Evidencia: `CRM-Avance-Corp/docs/gestion-diaria/f6-preparacion-2026-09-24/ACTA.md`,
`REVISION-F6-PREPARACION-2026-09-24.md`, `PREPARACION-F6-2026-09-24.md` y
`OBSERVACION-F3-F5.md`. Rama propia `codex/gestion-diaria-f6-preparacion-20260924`
en la copia separada ya autorizada. Véase [[Inicio]].
