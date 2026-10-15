---
tags: [crm, formulario-3, origenes, coordinacion, publicado]
actualizado: 2026-10-15
---

# Formulario 3 — origen nativo publicado

**Publicado y verificado el 15/10/2026.** `formulario_3` está en la misma columna `crm.leads.origen`, con los mismos permisos, altas, importación, bandejas, responsables, tareas, inversión y conversión. Tiene identidad y métricas propias; comparte el turno operativo Formulario. Repartir usa tabla por origen/supervisora. Ficha confirmada visualmente por Miguel: solo Formulario 3 como origen.

116 leads pasaron a origen nativo; cero legados residuales. Un convertido y su acreditación abierta conservan los demás datos. Se comprobaron huellas idénticas de responsables, historial, tareas, inversiones, contratos, solicitudes y fotos selladas. No se repitió el reparto de Excel ni se deshicieron movimientos posteriores del equipo.

Web publicada desde `avancecorp/main` limpio `597cab1cbfe68d53a2742073cfc7fc3292901af5` (PR #294), build `build-20261015T212300418Z`. A `20261015171407`, Edge v26/frontend, recarga confirmada y B `20261015173031`, en ese orden. Archivos exactos de SQL registrados. 126 comprobaciones HTTP, cuatro roles de lectura SQL y conciliación PASS. Captura humana de ficha PASS; smoke visual completo de todas las pantallas en sesión productiva NOT RUN, cubiertas por E2E Docker previo.

n8n sigue activo cada cinco minutos, misma versión, contrato y 152 recibos. El servidor normaliza el payload anterior sin reconectar credenciales. No se crean tareas ni solicitudes duplicadas por el cambio de origen.

La rama remota probada ya estaba retirada. Autorización explícita de Miguel para SQL/Edge además de `$release-crm`; promoción escalonada de los SQL exactos más registro, como en fase 4. Sin nuevo recurso de pago. No restaurar cliente antiguo después de B sin evaluar compatibilidad.

[Acta técnica y huellas](../../CRM-Avance-Corp/docs/FORMULARIO3-ORIGEN-NATIVO-PUBLICADO.md) · [Figma actualizado](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=2-34).

Relacionado: [[Formulario 3 - origen nativo preparado (2026-10-15)]] (histórico de ensayo), [[Canales de origen de leads CRM]], [[Formulario 3 - reparto corregido segun Excel (2026-10-15)]], [[Formulario 3 - fase 6 carga y activación (2026-10-15)]], [[Formulario 3 - plan de integración en CRM y activación (2026-10-14)]].
