# Gestión Diaria F4 — publicado y cortes programados

El 23/09 se cerraron el ensayo remoto, la instalación de cinco SQL y el release
autorizado con `$release-crm`. PR #76 fusionado. Fuente productiva exacta:
`6bf0e84a6ea1f9da0477569da312d06a3a2a2064`, Main limpio e igual al remoto al
publicar. Build `build-20260923T163253090Z`, https://crm.miavance.com.

ZIP `releases/crm-20260923T163254Z-6bf0e84a6ea1.zip`.
SHA-256 `0800772132124f9451c3ca1b9452a979e15957695f60b020014ee6a815d37945`.
113 archivos cotejados por HTTPS/MCP; smoke de gerencia PASS: configuración,
registro de actividad y persistencia tras recarga. Respaldo anterior verificado
de 114 archivos conservado fuera del web root. No republicar por añadir actas.

**V2 programada mediante la sesión real de gerencia para el 24/09, 00:00 Lima.**
Hoy v1 OFF. Cortes 11:30 y 16:00; mínimo inicial 3, crecimiento 150 %, piso 8,
techo 30; sábado mínimo 3 y un corte. Contacto 45 %/25 %, muestra 5.
**Tasa muy baja NULL/OFF hasta F5**, por decisión expresa de Miguel.
Una sola v2, actor gerencia, motivo y cadena a v1 comprobados; control del canal
sin cambios. Un aviso transitorio de conflicto apareció durante el guardado,
seguido de éxito: no se repitió el envío y no hay duplicados. Causa no atribuida
sin traza HTTP; observar si reaparece en una edición legítima futura.

Pruebas: 4.170 tests, 234 E2E PASS/26 SKIPPED, matrices remotas 2.221/0 antes
y después; contratos SQL, 24 mutantes, seis roles HTTP, dos carreras 200+409 y
carga sintética PASS. Producción: 346 migraciones, 341 anteriores intactas,
737 funciones, seis gates y 21 Edge Functions conservadas. Banco F4 eliminado,
coste acumulado estimado ~US$0,070 de US$1; banco ajeno intacto.

**F4 sigue pendiente de la primera jornada real:** el 24/09 cotejar ambos
cortes con supervisión, ámbito del equipo, popup/campana/lista, reconocer y
aplazar una vez entre sesiones/dispositivos, sin duplicados ni reaviso al cierre.
Seguimiento del sábado 26/09 para corte único/mínimo 3. No simular actividad real
ni declarar PASS por anticipado. F4.1/TypeSafe y F5 permanecen fuera.
Dos INFO de índices y dos WARN de rendimiento de políticas internas diferidos.

Plan: `CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md`.
Acta y recuperación: `CRM-Avance-Corp/docs/gestion-diaria/F4-REANUDACION-2026-09-23.md`.
[[Inicio]] · [[Gestion Diaria F4 - cinco SQL publicados OFF y PR 76 sin conflictos (2026-09-23)]]
· [[Gestion Diaria F4 - etapa 3 publicada con cortes OFF (2026-09-22)]]
