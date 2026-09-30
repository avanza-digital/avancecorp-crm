# Leads - DNI CE y pasaporte sin recortes (2026-09-30)

Estado: implementado y probado localmente; SIN PUBLICAR. El usuario autorizó
ampliar el guardado de base y probar en un banco aislado, con publicación aparte.

El alta de leads limitaba el DNI a ocho caracteres; la edición borraba letras
y recortaba a ocho dígitos. Un CE podía quedar guardado como otro DNI. La
conversión rechazaba correctamente ese número distinto. El arreglo conserva
esa defensa y añade el selector DNI/CE/pasaporte al alta y a la edición.

`crm.leads.dni` sigue siendo exclusivamente DNI. CE/pasaporte se guardan en la
[[Identidad unificada del CRM]], conservando el número completo y sus ceros.
Ficha y conversión consultan el mismo documento canónico; si falla esa consulta,
no se sustituye silenciosamente por el DNI antiguo. Guardar documento y otros
campos es atómico y el formulario espera la confirmación real.

Un documento ya reconocido solo lo corrige Administración, con motivo y auditoría,
mediante la puerta existente descrita en
[[Correccion administrativa del documento de clientes]]. El formulario muestra
ese permiso. Si hay enlaces históricos o varios documentos que impiden dejar
el lead coherente, se exige conciliación y se revierte toda la operación.
No se modificaron registros reales ni se adivinaron números que ya se recortaron.

Migración: `20260930193325_crm_documentos_lead.sql`, cuatro RPC y un validador
privado, sin cambios a tablas/policies/triggers/public. Preflight de diez huellas
de las funciones existentes. Banco Docker sintético `lead_documentos_20260930`.
44 aserciones SQL, concurrencia de dos sesiones y reversa/reaplicación PASS.
`npm run check`: 4958 tests, tipos, lint, build y bundle PASS; 33 E2E focales Docker
PASS. Acta vigente y resultados de regresión general en
`CRM-Avance-Corp/supabase/scripts/lead-documentos/README.md`.

La revisión inicial de Claude pidió cambios que se incorporaron y comprobaron;
el intento final terminó sin dictamen válido y NO cuenta como aprobación.
Rama remota, matriz HTTP RLS completa y advisors pendientes antes de publicar.
Relación: [[Conversion de lead con Nueva inversion - preparado 2026-09-19]].


## Preparación y espera de publicación

Miguel pidió preparar la publicación y autorizó banco remoto hasta US$1. Después
indicó «espera mi aviso para publicar, deja todo preparado mientras»: **esperar
nuevo aviso para producción**. Código integrado sin perder Coordinación: 5.021
pruebas PASS, Docker 298 PASS / 26 omitidas, SQL final 52 PASS. Review evaluado y
guardas adicionales probadas. No se hizo push, merge SQL ni deploy.

Banco remoto propio eliminado: replay histórico falló y Storage no tenía tenant
config (HTTP 400). Aplicación candidata remota, matriz HTTP y advisors NOT RUN;
resolver ese prerrequisito al retomar. Acta técnica y próximos pasos en
`CRM-Avance-Corp/supabase/scripts/lead-documentos/README.md`. Se conserva paquete
preparado y copia Git limpia para integrar sin alterar trabajos del checkout
habitual. El contrato del caso se conserva; falta ingresar el CE real completo
mediante corrección administrativa cuando se publique.

Relacionadas: [[Main unico - sincronizacion y publicacion 2026-09-04]] y
[[Identidad unificada de inversionistas - plan pendiente]].
