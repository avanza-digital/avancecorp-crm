---
tags: [crm, contratos, pdf, analista, incidente]
fecha: 2026-09-30
estado: correccion autorizada y probada, pendiente de publicacion
---

# PDF: analista asignado y creador separados

El PDF tomaba al creador del contrato aunque la ficha ya mostraba al analista
asignado. La cláusula 14.2 debe tomar `public.contratos.analista_cierre_id` con
el nombre, teléfono y correo del mismo perfil. `creado_por` sigue siendo autoría.

Snapshot 3 añade `contrato.analistaId`; la Edge admite estrictamente v2 y v3.
Los documentos históricos no se reescriben. La corrección de uno ya emitido se
realiza por la revisión auditada existente, conservando número y condiciones.
Una reasignación de cartera por sí sola no reescribe los PDFs congelados.

Migración `20260930235814_crm_pdf_analista_asignado.sql`; evidencia en
`CRM-Avance-Corp/supabase/scripts/pdf-analista/README.md`. Desplegar la Edge dual
antes del merge SQL, incluso después de un rebase de Supabase: el rebase también
repone la Edge del padre. La reversa SQL mantiene el renderer dual para leer v3.

Relacionadas: [[PDF contractual privado e inmutable 2026-08-17]],
[[Contrato PDF - cuentas con origen portal bloqueaban el PDF (2026-09-29)]],
[[Plantilla v9 del PDF - cotitulares en el contrato (2026-09-14)]], [[Inicio]].
