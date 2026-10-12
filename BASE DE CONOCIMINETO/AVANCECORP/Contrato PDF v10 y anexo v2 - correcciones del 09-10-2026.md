---
tags: [contratos, pdf, anexo, publicado]
fecha: 2026-10-10
---

# Contrato PDF v10 y anexo v2 - correcciones del 09-10-2026

**Publicado y verificado en producción, 10/10/2026.** Miguel pidió aplicar y publicar
las correcciones de `CRM-Avance-Corp/MODELO DE CONTRATO/CORRECIONES`, autorizó una
rama Supabase temporal hasta US$1 y la excepción de administrador para PR #250.
Main local y `avancecorp/main` coinciden en `5616d1e834c4c9e28e0fb7caeee2b3eae0a02498`.
La Edge v10 se desplegó a las 16:56:46 UTC y el SQL se fusionó desde la rama
ensayada tras 534 segundos de drenaje. Postflight 17:07 UTC PASS: 66 reservas
pasaron a v10, 298 PDF vigentes conservaron todas sus columnas y 3.107 ACL
permanecieron iguales. El ensayo remoto y las 319 aserciones RLS pasaron.

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

SQL `20261010154908_crm_contrato_pdf_plantilla_v10_correcciones.sql`, **aplicado
una vez por merge_branch**, migración 462/462. Transaccional; solo convierte reservas v9 sin bytes/lease;
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

Ensayo Supabase remoto PASS: catálogo 9/9 y ACL iguales antes de la candidata;
ciclo v9→v10→v9→v10; HTTP real con datos ficticios para emisión, anexo, histórico,
denegaciones y cambio de cuenta vigente sin alterar el anexo sellado. Advisors
sin avisos nuevos; suite CRM Node24: 6.611 pruebas PASS. Los tests de navegador
simulan backend y consumen PDF reales de Docker. No se crearon contratos de
prueba en producción: emisión productiva de prueba NOT RUN. Producción verificó
catálogo, identidad de código, seis descargas históricas SHA/bytes y anónimo 401.

El merge creó Edge 29, bundle `6b76ecb125c535d628075ac6d9fcdc941dea53e427beb7382a6d7a0be343a707`.
Sus diez módulos coinciden byte a byte con Main y la Edge 28 ensayada; las otras
22 funciones conservaron SHA/JWT. La revisión operativa CHANGES_REQUESTED se
cerró con evidencia de guardas del bundle v9 vivo, leases/errores, intentos cero,
ausencia de objetos en las 66 reservas y drenaje antes del merge. No cambiar ni
omitir ese gate en futuras publicaciones: el SQL no consulta Storage bajo lock.

Paquete: `CRM-Avance-Corp/output/contrato-correcciones-20261010.zip`.
Muestras: `CRM-Avance-Corp/output/pdf/correcciones-20261010/`.
Procedimiento, reversa y pruebas:
`CRM-Avance-Corp/supabase/scripts/banco-pdf-v10/LEEME.md`.
Acta: `CRM-Avance-Corp/supabase/scripts/banco-pdf-v10/PUBLICACION.md`.
La reversa preparada conserva lectura de documentos v10. No desplegar directamente
el binario v9 antiguo. La rama temporal se eliminó a las 17:09 UTC y su ausencia
se confirmó; credencial local retirada. Observación adicional de 137 s PASS,
sin reservas antiguas rezagadas. Uso estimado US$0,0129, dentro del límite de US$1.

Relacionado: [[Anexo de cronograma en el contrato PDF - plan v10 (2026-09-28)]] ·
[[Contrato PDF - analista asignado y creador separados (2026-09-30)]] ·
[[Regimen documental del contrato 2026-08-20]].
