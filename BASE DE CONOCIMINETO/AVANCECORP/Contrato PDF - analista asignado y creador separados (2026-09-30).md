---
tags: [crm, contratos, pdf, analista, incidente, publicado]
fecha: 2026-09-30
estado: publicado y verificado
---

# PDF: analista asignado y creador separados

Publicado por PR [#154](https://github.com/avanza-digital/avancecorp-crm/pull/154),
Main `b1751d7d04b7b50b4b77677b51030b1d9820f9a3`.
Migración `20260930235814_crm_pdf_analista_asignado` fusionada desde
rama Supabase; Edge PDF versión 27, JWT activado. Sin publicación de frontend.

La cláusula 14.2 toma `public.contratos.analista_cierre_id` y el nombre,
teléfono y correo del mismo perfil. `creado_por` conserva la autoría.
Snapshot 3 añade `contrato.analistaId`; el renderer admite estrictamente
v2 y v3. Los documentos históricos son inmutables: reasignar una cartera
por sí solo no reescribe sus PDFs.

Contrato 2026-01-001519: revisión 3 sellada y descargada con KELLY VEGA,
verificada visualmente y mediante SHA256. Número, condiciones económicas,
cuentas y las dos versiones anteriores conservados. Se emitió desde
«Corregir contrato» en la sesión administrativa, sin cambiar los valores:
sólo cambia la marca de actualización del contrato; la UI renueva los UUID
del cronograma, conservando todas sus fechas, importes y estados.

PASS: 73 pruebas Deno, 15 SQL, 287 RLS remotas, HTTP real y E2E Docker
(15 passed, 13 skipped, 0 failed). Claude se intentó sin VERDICT válido;
no equivale a una aprobación. Advisors sin incremento de avisos.
Rama temporal eliminada. Acta local:
`CRM-Avance-Corp/releases/pdf-analista-PUBLICADO.md`.

Desplegar siempre la Edge dual antes del SQL. Un rebase de Supabase también
repone/reconstruye la Edge del padre: cotejar nuevamente los archivos.
La reversa SQL debe conservar el renderer dual para seguir leyendo v3.
En bancos vacíos, una migración ajena puede exigir catálogos no personales;
copiar su configuración vigente sin inventar pesos ni copiar clientes.

Relacionadas: [[PDF contractual privado e inmutable 2026-08-17]],
[[Contrato PDF - cuentas con origen portal bloqueaban el PDF (2026-09-29)]],
[[Plantilla v9 del PDF - cotitulares en el contrato (2026-09-14)]], [[Inicio]].
