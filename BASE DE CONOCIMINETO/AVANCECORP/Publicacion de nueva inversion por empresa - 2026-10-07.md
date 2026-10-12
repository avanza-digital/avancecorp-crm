---
tags: [crm, inversiones, continuidad, publicacion]
estado: publicado
---

# Publicación de nueva inversión por empresa — 07/10/2026

**Regla vigente confirmada por Miguel:** si el cliente tiene una inversión
vigente en Qorilazo y nunca invirtió en Avance ni Prodelco, Nueva inversión
permite solo Avance/Prodelco y Upgrade usa solo el origen vigente de Qorilazo.
Reinversión permanece separada. Esto sustituye el bloqueo global de #206.

La corrección de la ficha multiempresa de Cartera y su formulario se publicó
con [PR #214](https://github.com/avanza-digital/avancecorp-crm/pull/214), commit
`8e7524ed2a3fd7a0ecbd3366d9a3300c42b01228`, build `build-20261007T054814889Z`.

Artefacto `crm-20261007T054815Z-8e7524ed2a3f.zip`; SHA-256
`a76511adb2ae07db608acb00f8078545ebaeec4ea484ec0b7e2355c64204ae90`.

6.305 tests y 32 E2E locales PASS, 2 E2E repetidos PASS, Claude PASS, GitHub PASS,
preflight PASS, 155 archivos HTTPS comprobados y caso real de la captura PASS.
Se abrieron los formularios sin enviar operaciones. No hubo SQL nuevo.

La elegibilidad usa cantidades del resumen completo, no saldo activo/página
visible. El servidor excluye fuentes demo de ese resumen. Solicitudes ya
enviadas conservan su UUID y recuperación. Lead y venta cruzada siguen con su
contexto anterior, sin historial por empresa; no se declara enforcement SQL
atómico entre sesiones. gate:realidad NOT RUN (sin SUPABASE_URL en la copia),
con comprobación visual real de la ficha tras publicar.

Evidencia local: `CRM-Avance-Corp/output/inversion-por-empresa-20261007/PUBLICADO.md`.
Artefacto/manifiesto: `CRM-Avance-Corp/releases/`.

Relacionadas: [[Upgrade cooperativo separado de reinversion (2026-10-06)]] ·
[[Upgrade es un contrato aparte, no una modificacion (2026-09-21)]] ·
[[Plan por fases - inversion por empresa y ranking de cartera (2026-09-26)]].
