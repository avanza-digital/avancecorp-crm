---
tags: [crm, inversiones, continuidad, upgrade]
estado: publicado-y-verificado
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
frontend y navegador Docker probados. **SQL y frontend publicados y verificados en producción.**

Miguel autorizó el SQL exacto y publicar. PR #208 fusionado en `62a375f0`.
La rama remota pasó 3.076 aserciones RLS, SQL propio y HTTP/Storage reales;
se verificaron siete huellas productivas y permisos, conservando historial y
22 Edge Functions. La rama temporal ya se eliminó. #209 ya está integrado y
deja Celular cerrado mientras termina su servidor. La otra sesión integró
#212 conservando la ascendencia del release vivo y publicó desde Main limpio
`3bdfded2c813`, igual al remoto. Build `build-20261007T045430720Z`.
Main con #210 pasó 6.286 pruebas y Docker F5 13/13. El gate Docker completo
propio terminó con 369 PASS, 1 flaky y 26 omitidos; #211 corrige la espera de
ese caso y pasó aislado sin reintentos. Postflight SQL final 07/10 05:01 UTC PASS.
Comprobación independiente HTTPS de 155 archivos PASS. En fichas productivas
de Qorilazo y Prodelco se verificaron Upgrade habilitado, Reinversión separada
y Nueva inversión deshabilitada, sin crear operaciones financieras. Evidencia
y capturas sin datos personales: `CRM-Avance-Corp/output/upgrade-cooperativas-20261006/deploy/`.
PR #211 de sincronización de E2E sigue abierto con CI PASS; no cambia el producto. Estado de retoma y límites: `CRM-Avance-Corp/docs/encargos/2026-10-06-upgrade-cooperativas-RETOMA.md`.

Guía y evidencia: `CRM-Avance-Corp/supabase/scripts/upgrade-cooperativas/README.md`.

El bloqueo global de nueva inversión se corrige según la decisión posterior de
[[Nueva inversion por empresa y upgrade vigente (2026-10-07)]].

Relacionadas: [[Nueva inversion por empresa y upgrade vigente (2026-10-07)]] ·
[[Upgrade es un contrato aparte, no una modificacion (2026-09-21)]] ·
[[F6 - implementación de postventa (2026-09-10)]].
