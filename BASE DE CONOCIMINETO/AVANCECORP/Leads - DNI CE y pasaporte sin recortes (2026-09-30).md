# Leads - DNI CE y pasaporte sin recortes (2026-09-30)

Estado: **PUBLICADO y verificado** en https://crm.miavance.com el 30/09/2026.
Miguel autorizó la publicación con «dale ya pouedes», y precisó «Solo documentos;
mantener F1 pendiente». La pausa anterior queda levantada para documentos.

El alta limitaba el DNI a ocho caracteres; la edición borraba letras y recortaba
números. Un CE podía terminar guardado como otro DNI y la conversión lo rechazaba.
Ahora alta y edición permiten DNI/CE/pasaporte y conservan el número completo.
`crm.leads.dni` sigue siendo exclusivamente DNI. CE/pasaporte se guardan en la
[[Identidad unificada del CRM]], conservando sus ceros y letras admitidas.
Ficha y conversión consultan el mismo documento canónico; si falla la consulta,
se bloquea el guardado/conversión y se permite reintentar. Documento y ficha se
guardan atómicamente y el formulario espera la confirmación real.

Un documento reconocido solo lo corrige Administración, con motivo y auditoría,
mediante [[Correccion administrativa del documento de clientes]]. No basta el
rol gerencia del CRM. Identidades ambiguas o enlaces históricos incoherentes se
rechazan sin cambios parciales. No se adivinan documentos históricos truncados.
El caso comunicado requiere ingresar el CE real completo mediante esa corrección;
el contrato se conserva, no se elimina ni se vuelve a crear.

## Publicación comprobada

- PR151 fusionado: Main `be280b6c51e5dd58139ae8c91eb1b4598696852c`.
- El preflight rechazó su ascendencia tras el squash. Se aplicó la excepción
  de rescate desde el vivo, con árbol idéntico a Main y preflight PASS.
- Fuente realmente publicada: `6a9ad5e685a2c595924cc0bccf2df31678e36948`.
- Build `build-20260930T225943345Z`;
  ZIP `crm-20260930T225944Z-6a9ad5e685a2.zip`;
  SHA-256 `caf2408ef5689a6068e436b4eeefd5163015819601b067cb22634e7ac0627b80`.
- Hostinger MCP success. HTTP 200, 94 hashes de archivos y portada PASS.
- Chrome: acceso y selector DNI/CE/pasaporte verificados; formulario cancelado.
- SQL `20260930193325` publicado mediante merge_branch y catálogo cotejado.
  Sin cambios a tablas/policies/triggers/public, Edge ni buckets.
- Banco temporal autorizado eliminado; advisors sin avisos nuevos.
- F1 Llamadas sigue pendiente, con sus módulos preservados y sin activar.

Check final: 5100 tests PASS. Docker: 298 PASS, 26 omitidas, 0 fallos.
SQL remoto 52, HTTP real 12, RLS contractual 287 e identidad D5 30: PASS.
Concurrencia, reversa/reaplicación y equivalencia de árboles: PASS.
Las observaciones de Claude se evaluaron con evidencia; no se obtuvo ni se
atribuye una aprobación independiente PASS.

Acta final: `CRM-Avance-Corp/docs/publicaciones/documentos-lead-2026-09-30.md`.
Artefactos y recibos saneados en `CRM-Avance-Corp/releases/`. Las actas previas
bajo `supabase/scripts/lead-documentos` conservan estados de preparación como
historial; esta nota y el acta final registran la publicación efectiva.

Relacionadas: [[Main unico - sincronizacion y publicacion 2026-09-04]],
[[Conversion de lead con Nueva inversion - preparado 2026-09-19]] y
[[Identidad unificada de inversionistas - plan pendiente]].
