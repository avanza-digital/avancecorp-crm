---
tags: [crm, contratos, pdf, cuentas-bancarias, incidente]
fecha: 2026-09-29
estado: edge publicada; desbloqueo del contrato 001470 pendiente de Miguel
---

# Contrato PDF: las cuentas con origen «portal» bloqueaban el PDF (2026-09-29)

## Qué pasó

Miguel pidió «2026-01-001470 genérame el contrato». El contrato (1 000 000 PEN, 22 % anual, nuevo,
firmado 28/09, creado el 29/09 18:24 Lima con la cuenta admin) tenía su job de PDF en
`integridad_bloqueada` con `ultimo_error = INTEGRIDAD_SNAPSHOT_INVALIDO`, sin bytes.

**Causa.** La migración `20260925210000` (cuentas compartidas CRM↔portal, 25/09) amplió el CHECK de
`crm.cuentas_bancarias.origen` a `perfil / contrato / portal`, y el front ya lo aceptaba, pero el
validador del snapshot en la edge `crm-contrato-pdf-v2` (`renderer.ts`, `validarSnapshotContratoV2`)
seguía admitiendo solo `perfil` y `contrato`. Un `TypeError` del validador se clasifica como
integridad y deja el job en un estado **terminal** (el trigger `proteger_job_contrato_pdf` no permite
salir de `integridad_bloqueada`; `crear_job_contrato_pdf_base` no crea otro job si ya hay uno).

Alcance medido en prod: 6 cuentas activas con origen `portal`; 2 contratos pagan a una de ellas:
`001486` (job `pendiente` del 25/09, habría caído igual al abrirlo) y `001470` (bloqueado).

## Qué se hizo

- Edge `crm-contrato-pdf-v2`: el validador acepta `portal` con comparación **estricta** (Codex P2:
  `String(["portal"])` colaría un arreglo). Sin cambio de plantilla: los tres orígenes rinden el mismo
  golden v9 (test nuevo en `renderer.test.ts`, deno 72/72). Commit `febabcc0` en `main` local.
- Publicada desde `CRM-Avance-Corp/` con `functions deploy --use-api`; contrastada por descarga:
  10/10 módulos vivos = árbol; arranca (sin sesión responde `SESION`).
- Codex (SECONDARY_REVIEWER, LEVEL 3): BLOCK por la coerción → corregido; de acuerdo en NO subir a v10
  y en NO abrir una transición `integridad_bloqueada → pendiente`.

## Cómo se desbloquea 001470 (paso de Miguel)

`integridad_bloqueada` no se reabre: se crea una **revisión 2** y `contrato_pdf_estado_base` lee la
última. La vía viva es la corrección de metadatos del **portal admin → Contratos → 001470 → Editar →
Guardar** (mismo número): llama a `crm.actualizar_numero_contrato_pdf_v3` → revisión 2 `pendiente`
con snapshot fresco → `ensure` → sellado. Efectos de re-guardar el mismo número: una fila en
`audit_log`, `actualizado_en`, la revisión nueva; no toca capital/tasa/fechas/cronograma/analista.
`001486` se auto-sana al abrir el contrato («Ver PDF»).

Verificar después (solo lectura): última revisión `sellado` con sha256 y bytes, revisión 1 conservada,
`fecha_cierre_comercial` intacta (2026-09-28).

## Lección

Toda ampliación de un CHECK que viaje dentro del **snapshot del PDF** exige tocar el validador de la
edge en la misma PR; si no, el fallo no es un error reintentable sino un bloqueo terminal. Ver
[[Cuentas bancarias por contrato]], [[PDF contractual privado e inmutable 2026-08-17]],
[[Numero de contrato - prefijos 2024 2025 y 2026 preparados (2026-09-19)]].
