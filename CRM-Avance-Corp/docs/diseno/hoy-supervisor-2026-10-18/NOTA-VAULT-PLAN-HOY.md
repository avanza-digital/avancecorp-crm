---
tags: [crm, hoy, supervisor, ui, plan, claude]
actualizado: 2026-10-18
estado: implementacion-local-y-plan-pendiente-de-goal
---

# Hoy supervisor - resultados diarios y plan por fases con Claude (2026-10-18)

Miguel aprobó «Resultados de hoy» en lugar de «Acompañar el cierre»: operaciones
y capital diario en PEN/USD, con detalle por analista. El aviso ámbar de leads
por repartir es independiente, lleva estado **Por asignar** y solo aparece con
pendientes confirmados; al quedar vacío no deja espacio.

La lectura diaria reutiliza Facturación, conserva el ámbito autorizado completo
y la atribución histórica. No publica cero a partir de errores, falta de datos
o un corte anterior a hoy. La demo usa sus contratos existentes sin inventar
cierres recientes. Implementado localmente; no publicado.

Miguel pidió terminar la iteración actual antes de entregar un plan y un objetivo
para Goal. El plan incluye a Claude como revisor independiente; Codex es el único
escritor. Después amplió el alcance del plan hasta crear el ZIP para publicar y
recalcó que quiere recibir el plan antes de ejecutarlo. El plan vigente tiene
ocho fases: indicadores, datos/actualización, acciones, interfaz, revisión de
Claude, validación integral, preparación de la revisión y creación/verificación
del ZIP con manifiesto SHA-256. No iniciar su ejecución hasta que Miguel la indique.
No se inició un Goal, no se generó todavía el ZIP ni se autorizó publicación.

Se mantiene la instrucción de trabajar en local sin navegador, control del
computador ni Docker. El paquete se comprobará con los comandos existentes
`release:crm` y `release:crm:verify`, desde una revisión limpia identificada y
con configuración pública de producción. Las comprobaciones productivas y E2E
que no se puedan ejecutar quedarán NOT RUN, visibles antes de publicar.
El objetivo termina en el ZIP comprobado; subirlo requiere el flujo posterior
de release. No se instala SQL por crear el paquete.

Documentos del repositorio:

- [Plan y objetivo para Goal](../../CRM-Avance-Corp/docs/diseno/hoy-supervisor-2026-10-18/PLAN-HOY-SUPERVISOR.md).
- [Implementación, review y verificación](../../CRM-Avance-Corp/docs/diseno/hoy-supervisor-2026-10-18/RESULTADOS-HOY-VERIFICACION.md).

Relacionadas: [[Hoy supervisor - direccion de jornada integrada localmente (2026-10-18)]] ·
[[Hoy supervisor - dos propuestas de indicadores comerciales (2026-10-18)]] ·
[[Hoy del supervisor - reparto compacto]].
