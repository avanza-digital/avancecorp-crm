---
fecha: 2026-09-08
estado: publicado-verificado-2026-09-09
tags: [crm, citas, gerencia, conversion, regla-negocio]
---

# Depósito acreditado por conversión a cliente

Miguel aclaró expresamente: **«se sabe que alguien depositó cuando se le convierte en cliente»**. Resuelve el pendiente de [[Citas Gerencia - integracion local y deposito pendiente 2026-09-08]]. No volver a pedir una validación bancaria adicional para el conteo de este indicador.

Fuente técnica identificada en servidor: `crm.convertir_lead(uuid,uuid)` valida el perfil cliente y guarda conjuntamente `etapa='convertido'`, `perfil_id` y `convertido_en`, además de la actividad de conversión. Sigue [[Capacidad única de conversión de leads (2026-09-03)]].

La lectura V2 de Citas toma conversiones vigentes de los leads de la consulta, con perfil de rol cliente y fecha hasta el corte; excluye anuladas mediante `private.cierre_anulado`. Inactivar el acceso del cliente no revierte la conversión. El cierre externo sin vínculo a un cliente del portal no se equipara automáticamente a esta regla.

En el recorrido acordado de [[Citas Gerencia - tablero horizontal y flujo por persona 2026-09-08]], la conversión tiene que ser posterior a la asistencia a una cita reprogramada y vinculada al mismo lead. Se cuenta cada lead una vez. Puede seguirse fuera del mes/semana de la cita original hasta el corte. No se incorporan personas ajenas a la etapa anterior.

La fecha visible es **Fecha de conversión**, no una hora bancaria inferida. El monto estimado no se presenta como abonado. Los conteos/porcentajes ya pueden funcionar con esta fuente sin necesitar un importe monetario.

Migración local nueva `20260909015744_crm_citas_deposito_por_conversion_cliente.sql`; no modifica la anterior versionada. Frontend admite V1 y V2; fuente V1 conserva «Sin verificar». La demo general no modela el vínculo cliente, por lo que sigue sin evidencia de conversión; las pruebas de V2 sí simulan la secuencia completa dentro de la app.

Ensayo inicial local: gate frontend, 3.150 pruebas, 7 E2E y banco SQL de permisos/consulta/volumen/conversiones. Revisión Claude evaluada por Codex. Evidencia inicial: `UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/integracion/conversion-cliente/README.md`.

**Publicado y aplicado en producción el 9 de septiembre.** Ver [[Citas Gerencia - publicacion y verificacion 2026-09-09]] para commit, versiones remotas, ensayos específicos, prueba de lectura real y las limitaciones del banco general (65 fallos; no se declaró aprobado). El artefacto limpio finalmente publicado pasó 3.127 tests y 147 E2E, con 26 omitidas por la suite. El banco temporal autorizado fue eliminado.
