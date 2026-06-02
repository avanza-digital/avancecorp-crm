---
tags: [feature, pagos, notificaciones]
actualizado: 2026-06-01
---

# Notificaciones de pagos

**Implementado 2026-05-26.** El cliente recibe aviso por **3 canales** (novedad in-portal + push + correo) en dos eventos:

1. **Pago realizado** — al registrar un pago en `/admin/pagos` (manual o por import de Excel). Lo dispara `pagos.js` (admin) tras pagar/importar.
2. **Recordatorio 3 días antes** de la fecha programada — vía **cron diario** a las **09:00 Perú** (14:00 UTC).

## Cómo funciona
- Edge **`notificar-pagos`** (`verify_jwt:false`; auth = token admin **o** `x-cron-secret` validado contra Vault).
- **`pg_cron` + `pg_net`**: job `recordatorio-cuotas-3d` hace `net.http_post` a la edge con el secreto del Vault (`cron_notif_secret`), comparado por la RPC `verificar_cron_secret` (SECURITY DEFINER, solo `service_role`).
- **Idempotencia:** sellos `notif_pago_enviada_en` / `recordatorio_3d_enviado_en` en `cronograma_pagos`. `revertirPago` limpia el sello. Soporta `dry_run`.

## Notas relacionadas
[[Realtime de novedades]] · [[Arquitectura del portal]] · [[Inicio]]
