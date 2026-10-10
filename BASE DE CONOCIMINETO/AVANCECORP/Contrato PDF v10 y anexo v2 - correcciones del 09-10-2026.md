---
tags: [contratos, pdf, anexo, preparado-local]
fecha: 2026-10-10
---

# Contrato PDF v10 y anexo v2 - correcciones del 09-10-2026

**Preparado y verificado localmente; producción sin modificar.** Miguel pidió
aplicar las correcciones de `CRM-Avance-Corp/MODELO DE CONTRATO/CORRECIONES` y
preparar la publicación, con SQL visible y autorización antes de producción.

Contrato `contrato-aep-17-v10`: correos 8.1 y 14.2 a
`atencionalcliente@groupmascapital.com` y firma transparente original del Word.
Anexo `anexo-cronograma-v2`: «Número de cuenta destino» desde el snapshot sellado,
como texto y conservando ceros iniciales. La cuenta vigente del cliente no se
consulta para imprimir el anexo. Firma PNG 321×240, 42.323 bytes, SHA
`c3dcb1242301df96cb926930a82a019d4258d6a6e5d8ac3d01033b2e4cf90a6a`;
`fit:[93,65]` conserva proporción y trazos completos.

Los PDF sellados se conservan sin regenerar. Se admite lectura de v1–v9; v3/v4
se incorporan expresamente a la lista histórica para cumplir compatibilidad.
Las emisiones nuevas exigen igualdad estricta con la versión del renderer:
un trabajo v9 bajo Edge v10 no se dibuja ni se sella mal rotulado.

SQL `20261010154908_crm_contrato_pdf_plantilla_v10_correcciones.sql`, **NO aplicado
a producción**. Transaccional; solo convierte reservas v9 sin bytes/lease;
aborta con trabajos en proceso, subidos o reintentos con bytes. Dos cuerpos
privados vivos cambian únicamente su literal de versión. Preserva snapshots,
importes, cronogramas, fechas, documentos, ACL y OID en el banco verificado.
Reversa SQL conserva los CHECK ampliados y todos los documentos v10 emitidos.
La Edge de reversa genera v9/anexo v1, pero mantiene lectura v10: nunca volver
al binario v9 original sin esa compatibilidad.

PASS: 94 pruebas Deno Docker; 91 reversa Docker + typecheck; 4 Playwright Docker
con PDF reales; 32 frontend; 39 SQL aislado PostgreSQL17; banco completo del
núcleo PDF con RLS/concurrencia y auditoría real de anexo v2; 14 comparaciones de
texto (solo correos/fila cuenta), 75 páginas revisadas visualmente. Revisión
independiente por `scripts/claude-review`: CHANGES_REQUESTED inicial atendido y
PASS final, confianza alta. P3 opcional final también atendido.

NOT RUN: preflights generales seed/RLS por falta de SUPABASE_URL en esa consola;
rama Supabase remota/advisors y smoke productivo son gates de publicación
pendientes de entorno y autorización. Los tests de navegador simulan backend y
consumen PDF reales generados en Docker. El banco v10 usa dos cuerpos suplentes;
no se presenta como clon del catálogo productivo.

Paquete: `CRM-Avance-Corp/output/contrato-correcciones-20261010.zip`.
Muestras: `CRM-Avance-Corp/output/pdf/correcciones-20261010/`.
Procedimiento, reversa y pruebas:
`CRM-Avance-Corp/supabase/scripts/banco-pdf-v10/LEEME.md`.
Antes de publicar: integrar cambios remotos sin sobrescribirlos, Main local igual
a avancecorp/main, artefacto del commit verificado, ensayo en rama autorizada,
ventana sin emisiones, SQL exacto aprobado y postflight de hashes/documentos.

Relacionado: [[Anexo de cronograma en el contrato PDF - plan v10 (2026-09-28)]] ·
[[Contrato PDF - analista asignado y creador separados (2026-09-30)]] ·
[[Regimen documental del contrato 2026-08-20]].
