---
tags: [crm, inversiones, continuidad, upgrade]
estado: preparado-no-publicado
---

# Upgrade cooperativo separado de reinversión

Miguel confirmó el 06/10/2026: **«Sí, upgrade y reinversión separados»** para
Qorilazo y Prodelco. La falta del botón era real: solo Avance tenía upgrade.

El upgrade cooperativo registra dinero adicional como una nueva inversión y un
depósito nuevo, vinculados a un origen vigente de la misma persona y empresa.
Conserva el capital y las condiciones originales. Su tipo y origen son
inmutables, recuperables e independientes de la reinversión. Una inversión
vencida mantiene reinversión, no upgrade. No se copian automáticamente las
reglas de tasa heredada de Avance a las cooperativas.

Se preparó `20261006221545_crm_upgrade_cooperativas.sql` con el nuevo tipo, RPC,
historial y respuesta de conflicto concurrente. Banco SQL, carreras reales,
frontend y navegador Docker probados. **Todavía no aplicado/publicado.**
Guía y evidencia: `CRM-Avance-Corp/supabase/scripts/upgrade-cooperativas/README.md`.

Relacionadas: [[Nueva inversion - bloqueo global y continuidad del cliente (2026-10-06)]] ·
[[Upgrade es un contrato aparte, no una modificacion (2026-09-21)]] ·
[[F6 - implementación de postventa (2026-09-10)]].
