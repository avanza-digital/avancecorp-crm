---
tags: [crm, leads, rentabilidad, produccion]
fecha: 2026-09-09
estado: publicado-verificado
---

# Solicitud de tasa en el lead — publicada

La solicitud de aprobación de tasa ya está disponible en «Condiciones de
inversión» dentro de la ficha del lead de `crm.miavance.com`. Conserva el
recuadro que Miguel aprobó visualmente. La solicitud pendiente bloquea la
conversión en cliente de Avance; Gerencia usa la misma bandeja de aprobaciones.

Se completa el DNI antes de solicitar una excepción. La aprobación corresponde
a condiciones concretas, conserva su vigencia y requiere aceptar una
contraoferta cuando corresponde. La conversión enlaza la misma solicitud al
cliente y la creación del contrato consume la autorización una sola vez.

Miguel autorizó implementar/publicar, pidió una pausa segura, reanudó con
«sigue» y aprobó el SQL exacto y el costo del banco con «hazlo». Publicación
completada; no queda pendiente una nueva confirmación de esa autorización.

## Publicación y verificación

- Commit del artefacto: `8ccb0ca14fcf1f34e8e2158b11b1d88bf519b3f4`.
  Main original, aislado y `avancecorp/main` coincidían al publicar.
- Release `crm-20260909T171132Z-8ccb0ca14fcf`; build servido
  `build-20260909T171131381Z`. Ochenta archivos comprobados contra el manifiesto.
- Migración local `20260909042103_crm_solicitud_tasa_lead_preconversion.sql`,
  registro remoto `20260909165815`, incorporada por merge de la rama de prueba.
- Edge `crm-convertir-lead` v16: los seis archivos coinciden con los probados;
  las otras dieciséis funciones y las banderas conservaron su configuración.
- PASS: 3.140 pruebas frontend; Playwright 152 PASS/26 SKIP; Edge 67 Node + 5
  Deno; quince grupos SQL; flujo HTTP real y ámbitos de trece perfiles en banco.
  CI del commit publicado pasó. Login productivo público sin errores.
- FAIL documentado: suite RLS global, 41 fallos antes y 51 después sobre un banco
  reutilizado. Las diferencias corresponden a fixtures conservados,
  expectativas antiguas y una comparación textual incompatible con la guarda
  de tasa añadida. El gate global no se presenta como aprobado.
- NOT RUN: recorrido autenticado en producción, sin sesión disponible. El
  flujo se probó en banco y se comprobó la integridad del despliegue.

La rama temporal `ehzftpvxuwuzinvkyhzz` fue eliminada y su ausencia comprobada.
Los bancos ajenos F5/F7 permanecen intactos. El paquete anterior y las evidencias
se conservaron en `_DEV_NO_SUBIR/pausas/tasa-lead-2026-09-09/publicacion/`.

Registro técnico: `CRM-Avance-Corp/supabase/scripts/tasa-lead/PUBLICACION-2026-09-09.md`.
No borrar historial para revertir; después del primer uso se corrige hacia
delante según el procedimiento condicionado de esa carpeta.

Relacionado: [[Solicitud de tasa antes de convertir el lead - propuesta 2026-09-08]],
[[Solicitud de tasa en el lead - pausa segura 2026-09-09]],
[[Historial de decisiones de tasa de Gerencia]],
[[Main unico - sincronizacion y publicacion 2026-09-04]], [[Inicio]].
