# Analista asignado en el PDF contractual

Autorización de Miguel: «Sí, corrige, prueba y publica» (30/09/2026).
Preparación de publicación; no declarar publicado hasta verificar Edge, SQL y
la nueva revisión del contrato solicitado.

## Causa y alcance

La ficha mostraba `analista_cierre_id`, pero el snapshot del PDF consultaba
`creado_por`; el renderer además exigía que ambos fueran iguales. Una venta
creada por A y asignada a B imprimía el nombre y contacto de A en la cláusula 14.2.

El snapshot 3 añade `contrato.analistaId` y toma todos los datos del perfil
asignado. `creadoPor` conserva la autoría histórica. El renderer valida v2 como
antes y exige la nueva identidad para v3; mismo layout y plantilla v9. Los dos
núcleos del anexo aceptan v2/v3. Sin analista o contacto completo, se rechaza la
emisión. No se cambian atribuciones, carteras, condiciones económicas ni permisos.

Los PDFs existentes permanecen congelados. Corregir uno emitido requiere una
revisión nueva por la puerta existente `crm.actualizar_numero_contrato_pdf_v3`,
guardando exactamente el mismo número, notas y categoría. Nunca actualizar un
snapshot existente, reabrir un trabajo bloqueado ni sobrescribir Storage.

## Validación

- PASS: 73 pruebas Deno del renderer y handler; tipos de `index.ts`/renderer.
- PASS: 15 aserciones SQL sobre PostgreSQL real aislado y reversa/reaplicación.
  Reproduce creador A/asignada B, contactos coherentes, igualdad de condiciones,
  dos revisiones, histórico intacto, anexos v2/v3, inmutabilidad, actor ajeno,
  ACL y ausencia de analista/contacto. Toda la transacción se revierte.
- PASS: PDF real sintético renderizado y extraído con Poppler; aparecen nombre,
  teléfono y correo de B y no los de A. Inspección visual de cláusula 14.2.
- PASS: RLS remoto oficial `test-rls.mjs --contratos`: 287 aserciones.
- PASS: E2E local en Docker, contratos/alta/detalle/anexo: 15 passed,
  13 skipped, 0 failed. Los omitidos no cuentan como aprobados.
- PASS: `check:scripts`, `seed:preflight`, `test:rls:preflight`,
  `test:edge-preflight` y Deno check.
- PASS: HTTP real de Edge: emisión, descarga con SHA256, status, anexo,
  rechazo sin sesión y actor ajeno. PDF y anexo extraídos con Poppler muestran
  el analista asignado y no el creador. Reemisión probada con actor Administración.
- PASS: 1.004 objetos comparados: sólo cambian los cuerpos de las tres funciones
  previstas, con ACL/propietarios intactos. Columnas, grants por columna,
  índices, policies, RLS y triggers coinciden. Advisors sin avisos nuevos
  atribuibles al cambio; índices sin uso adicionales corresponden al banco vacío.
- Revisión independiente LEVEL 3 intentada con `scripts/claude-review`, rol
  SECONDARY_REVIEWER/auditor-rls y evidencia saneada. El wrapper terminó sin
  VERDICT válido: **no se cuenta como aprobación**. Decide y verifica el PRIMARY.

Banco local `pdf_analista_20260930`, Docker `supabase_db_crm-avance-corp-local`,
marcador `BANCO SINTETICO PDF analista 20260930 / sin produccion`. Creado desde
el banco sintético de documentos, con las funciones de anexo y las dos ACL de
snapshot/corrección alineadas con producción. Las tres funciones base tienen
las huellas exactas exigidas por el preflight. `fixture.sql` crea un contrato
nuevo con catálogo legacy válido y reasigna mediante la RPC auditada; no apaga
triggers. Para repetir, desde la raíz del CRM:

```sh
node supabase/scripts/pdf-analista/banco.mjs
cd supabase/functions/crm-contrato-pdf-v2
deno test --allow-read renderer.test.ts handler.test.ts
deno check index.ts renderer.ts
```

La inyección de un responsable nulo es un caso de datos legados dentro de un
savepoint del banco; no es una operación permitida al usuario. El ensayo no
modifica perfiles, atribuciones ni contratos reales.

## Secuencia de publicación y reversa

1. Rama Supabase temporal sin clientes: esquema/ACL/historial cotejados, sólo
   esta migración nueva. Incorporar cambios que aparezcan en producción.
2. **Después de cada rebase volver a desplegar y cotejar la Edge candidata**:
   Supabase rebase también repone las funciones del padre. Un ensayo remoto
   detectó el renderer antiguo y bloqueó el snapshot v3; se conserva ese intento
   de prueba y se emite una revisión nueva tras reinstalar la Edge dual.
3. Pasar SQL, HTTP, RLS y advisors; mantener las otras 21 Edge y cinco buckets.
4. PR aprobado y Main local = `avancecorp/main`. Desplegar sólo la Edge PDF dual
   desde ese commit, conservando `verify_jwt=true`. No se publica frontend.
5. Merge de la rama SQL ya probada. Verificar las tres funciones, el historial
   y la Edge viva. No aplicar DDL directamente a producción.
6. Emitir la revisión autorizada con los mismos metadatos. Descargar y verificar
   identidad/contactos, SHA256, condiciones y conservación de las anteriores.
7. Eliminar la rama temporal dentro del tope de US$1 ya autorizado.

`reversa.sql` restaura exactamente las tres funciones previas. Conservar el
renderer dual incluso después de la reversa: los snapshots 3 ya emitidos deben
seguir abriendo. Las firmas públicas no cambian; no hay tipos de API que regenerar.
La Edge es exclusiva del CRM: no existe un espejo versionado del PDF en
`_supabase_functions`, y no se agrega otro bundle duplicado.
