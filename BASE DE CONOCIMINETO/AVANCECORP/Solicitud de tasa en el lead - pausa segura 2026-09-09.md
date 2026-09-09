---
tags: [crm, leads, rentabilidad, pausa]
fecha: 2026-09-09
estado: publicado-registro-historico-de-pausa
---

# Solicitud de tasa en el lead — pausa segura

**Cierre del 09/09/2026:** publicación completada y verificada. Estado vigente en [[Solicitud de tasa en el lead - publicada 2026-09-09]]. SQL, Edge y frontend publicados desde `8ccb0ca`; release `crm-20260909T171132Z-8ccb0ca14fcf`. La rama temporal fue eliminada. Main local y remoto sincronizados en `0a6e9f7`; trabajo ajeno preservado. Evidencia y límites de la matriz general en el registro técnico de publicación.

## Historial anterior a la publicación

Los apartados siguientes describen la pausa y la reanudación anteriores; sus pendientes ya fueron resueltos o documentados en la nota vigente.

Miguel pidió «pongamos pausa al trabajo, en un punto seguro claro». Se guardó el
respaldo descrito abajo. Después indicó **«sigue»** y el trabajo se reanudó el
09/09. Esta funcionalidad **todavía no está en producción**. La pausa descrita
en el paquete conserva valor histórico; ya no es una instrucción de detenerse.

Relacionado: [[Solicitud de tasa antes de convertir el lead - propuesta 2026-09-08]],
[[Inicio]], [[Main unico - sincronizacion y publicacion 2026-09-04]].

## Punto de retoma histórico

- Diseño local aceptado y conexión real implementada: solicitud desde el lead,
  bloqueo antes de crear cliente, misma bandeja de Gerencia y conservación de la
  aprobación/condiciones hasta su consumo al crear el contrato.
- Copia de trabajo: `/private/tmp/avancecorp-tasa-lead-real-20260908`.
- Base integrada: `a7f6434b4a3aebc4b87cfc77c0f849f4b880f0f3` de `avancecorp/main`.
- Sin commit/push de este cambio, SQL productivo, despliegue Edge ni publicación frontend.
  El trabajo ajeno del workspace principal se conserva.
- Respaldo duradero verificado: [paquete y pasos exactos](../../_DEV_NO_SUBIR/pausas/tasa-lead-2026-09-09/README.md).
  Incluye ZIP de 25 archivos completos, huellas, patch, SQL y logs; permite retomar
  aunque se pierda la carpeta temporal.

## Qué faltaba al reanudar

La validación posterior a la revisión pasó: **3.136 pruebas** de frontend,
38 enfocadas, 67 Node + 5 Deno de Edge y **15 grupos SQL**. También pasó una
carrera de dos sesiones reales: la solicitud obliga a esperar y la conversión
se rechaza sin reserva parcial. Reversa, rechazo de política RLS alterada y
reaplicación comprobados. Recorrido nuevo verificado en escritorio/celular.
La suite Playwright anterior dejó cinco fallos; se resolvieron y sus casos
pasaron dentro de una revalidación de **34/34**. No se presenta como una segunda
ejecución de toda la suite.

Claude entregó **CHANGES_REQUESTED**. Codex evaluó sus hallazgos y verificó las
correcciones: DNI antes de enviar una excepción, autor que conserva su respuesta
al tope en su bandeja tras reasignación, Gerencia que conserva solicitudes de
leads inactivos, guardia de la política RLS, mensajes y accesibilidad. Los dos
riesgos P1 eran caminos no vistos por el reviewer: se comprobaron con código
vivo y pruebas de cliente conocido y bandeja sin cliente. No se pidió otro PASS.
Detalle en `supabase/scripts/tasa-lead/REVISION.md` de la copia de trabajo.

Miguel respondió **«hazlo»** a la solicitud explícita de aprobar el SQL adjunto y
el banco temporal de US$0,01344/hora. Ambos están autorizados; no volver a pedir
esa confirmación. Ensayo remoto en curso en `tasa-lead-publicacion-20260909`,
proyecto `ehzftpvxuwuzinvkyhzz`, rama `d14a5bcc-532f-40b5-bdc0-5bc4b51d6618`.
Eliminar esta rama al terminar. No tocar `banco-f7`.

La creación automática falló en el historial antiguo, como el banco de Citas.
Se reconstruyó el esquema actual sin datos de personas y se repuso el registro
de 265 migraciones. Está en curso la comparación previa y los gates remotos.
Todavía no se aplicó el cambio de tasa en producción.

Nuevo respaldo con correcciones y SQL para revisión:
`_DEV_NO_SUBIR/pausas/tasa-lead-2026-09-09/reanudacion/`.
El ZIP inicial de la pausa conserva sus bytes y su huella originales.

El detalle de pruebas, límites, bancos locales y recuperación está en el paquete.
La autorización incluye el SQL exacto mostrado (SHA-256
`113a436ec25f13105d7321f527bbeb583d74c09feffb408ab3a8616ea418ca55`),
el costo de la rama y completar la publicación tras verificarla.
