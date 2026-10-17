# Evidencia del paso 3a «SLA por filas» (17/10/2026)

Copia de los informes que respaldan las 3 migraciones (`20261017054425`, `…054426`, `…054427`). Los datos crudos (banco Docker,
arnés de carga, CSV y JSON de cada réplica, salidas del verificador) quedan fuera del repositorio, en la copia aislada
`~/dev/avancecorp-crm-foto-sla/CRM-Avance-Corp/supabase/scripts/foto-sla/` (plan «foto del SLA», Fase 3). Las rutas que citan
estos informes son relativas a esa carpeta.

| Archivo | Qué es |
|---|---|
| `01-ensayo-migraciones-v2.md` | Ensayo de M1–M3 v2 en el banco: pasos, equivalencia (9.193 comparaciones, 0 diferencias), mutantes 26/26, memoria |
| `02-verificador-independiente-v1.md` | Verificador independiente sobre la v1 (H1 orden de empates, H2 sellos): todo corregido en la v2 |
| `03-codex-migraciones-v1.md` | Codex sobre la v1: CHANGES_REQUESTED, corregido en la v2 |
| `04-codex-cierre-v2.md` | Codex de cierre sobre la v2: CHANGES_REQUESTED, corregido en el kit v3, gate, 2×2 y Gestión Diaria |
| `05-kit-v3.md` | Kit v3: registradores y reversas validan la transición del historial; reproducción cronológica |
| `11-kit-v4.md` | Kit v4 (VIGENTE): las reversas se registran solas en su transacción; orden global; NULL; 49/49 pasos |
| `12-codex-verificacion-kit-v3.md` | Verificación estrecha de Codex sobre el kit v3, el gate, el 2×2 y Gestión Diaria: lo que pidió está en el kit v4 |
| `06-gate-rls-completo.md` | `test:rls` completo ANTES/DESPUÉS en stack local con el volcado de producción del 17/10: PASS |
| `07-carga-concurrente.md` | Carga ABABAB ANTES vs M3: memoria baja; veredicto NO PASA solo por el p95 de `estado` |
| `08-estado-2x2-y-gestion-diaria.md` | 2×2 con sonda dedicada: `estado` gasta la misma CPU; carga con Gestión Diaria |
| `10-cadenas-completas.md` | Las 239 cadenas «hasta el final» del verificador, completas: 5.733 páginas, 0 diferencias |
| `09-produccion-verificar-ANTES-20261017.txt` | `verificar.sql` corrido por Miguel en producción el 17/10: `SERIE=ANTES` |
