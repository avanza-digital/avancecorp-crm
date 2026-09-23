# Gestión Diaria F4 — cinco SQL publicados OFF

Los conflictos del PR #76 quedaron resueltos integrando Main `8097ca8c` y
preservando el trabajo de la otra sesión. Código de aplicación verificado:
4.170 tests y 234 E2E Docker PASS (26 SKIPPED).

Los cinco SQL autorizados ya están en producción mediante merge Supabase.
Matrices remotas antes/después: 2.221/0 cada una; contratos SQL, 24 mutantes,
seis roles HTTP, dos carreras 200 + 409/PT409 y carga de 2.200 leads/15.400
actividades PASS. P95 sintético entre 2,567 y 3,519 segundos.

Verificación productiva: 346 migraciones; las seis columnas de las 341 previas
intactas y las 114 sentencias nuevas exactas. Las 737 funciones coinciden con
el candidato, 21 Edge Functions conservadas, seis gates PASS. Política v1 OFF,
tasa baja NULL, cero entregas; cron y Auth intactos, sin fixtures copiados.

Banco propio eliminado a las 11:22 Lima y ausencia confirmada. Coste acumulado
estimado ~US$0,070, por debajo de US$1; la rama ajena `banco-f7` quedó intacta.
Avisos de índices y los dos WARN de rendimiento de políticas internas registrados
en el acta; no hubo errores de seguridad nuevos.

Pendiente: revisión/fusión del PR #76, release desde Main igual al remoto,
smoke, política futura por gerencia y primera jornada real. GitHub exige una
aprobación y revisión de propietario de código por regla organizativa 20216285.
No se usó fusión administrativa. Sitio vigente respaldado:
`build-20260923T020403114Z`, 114 archivos cotejados.

Plan: `CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md`.
Acta: `CRM-Avance-Corp/docs/gestion-diaria/F4-REANUDACION-2026-09-23.md`.
[[Inicio]] · [[Gestion Diaria F4 - correctivo HTTP verificado y pendiente de autorizacion (2026-09-23)]]
· [[Gestion Diaria F4 - etapa 3 publicada con cortes OFF (2026-09-22)]]
