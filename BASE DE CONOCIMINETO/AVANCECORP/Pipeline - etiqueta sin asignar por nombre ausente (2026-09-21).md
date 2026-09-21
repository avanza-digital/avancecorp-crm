---
tags: [crm, pipeline, analista, diagnostico]
actualizado: 2026-09-21
estado: publicado-y-verificado
---

# Pipeline — «sin asignar» por nombre ausente

Miguel preguntó por qué los leads del pipeline del analista muestran «sin asignar»,
autorizó corregirlo y después indicó «publica». Publicado en
`https://crm.miavance.com/` y verificado el 21/09/2026 a las 12:55 Lima.

## Causa comprobada antes de la corrección

Las referencias de línea de este apartado corresponden al código diagnosticado.

- `CRM-Avance-Corp/app/src/screens/pipeline.tsx:125`: `LeadCard` decide entre
  nombre y «sin asignar» por `l.vendedor_nombre`, sin comprobar `l.vendedor_id`.
- `CRM-Avance-Corp/app/src/data/crm-api.ts:451`: `aLead` conserva `vendedor_id`
  pero no incorpora `vendedor_nombre`. La página integrada usa ese mapper
  (`crm-api.ts:762`).
- `CRM-Avance-Corp/app/src/data/use-cartera-paginada.ts`: concatena los elementos
  recibidos, sin resolver nombres con el equipo visible.
- `pipeline.tsx:444`: la sesión real dibuja directamente `servida.leads`;
  `pipeline.tsx:502` entrega cada elemento a `LeadCard`. Registrar los leads en
  el store con `conocerLeads` no sustituye estos objetos por los enriquecidos.
- `CRM-Avance-Corp/app/src/screens/cartera.tsx:143` ya resuelve los nombres
  mediante `ambito.vendedores` para la pantalla Leads; Pipeline omite ese paso.

Por tanto, un lead con responsable asignado puede mostrarse con la etiqueta
incorrecta porque al objeto de la tarjeta le falta el nombre. El aviso visual
no permite concluir que se haya perdido la asignación en la base de datos.

El cambio previo de Pipeline `dbfa9d6b` (Fase 4 «sin topes») pasó sus
columnas a la lectura paginada del servidor. Antecedente:
[[Leads sin foto inicial - Fase 4 del plan sin topes (2026-09-20)]].

## Corrección aplicada

Pipeline resuelve el nombre por `vendedor_id` con `ambito.vendedores` y lo pasa
a la tarjeta. Conserva como respaldo el nombre que ya pueda traer el lead.
La tarjeta reserva «sin asignar» para `vendedor_id == null`; si existe responsable
pero su nombre no está disponible, muestra «Analista asignado» en tono neutral.
No cambia las asignaciones, consultas, permisos ni paginación.

Se ajustó la prueba existente de página servida en `pipeline.test.tsx` para usar
filas sin nombre, como la respuesta real. Comprueba los tres estados y que cargar
más sigue funcionando. Antes de corregir, fallaba al buscar el nombre ANA;
después pasaron las seis pruebas del tablero.

## Verificación

- PASS: prueba focalizada de Pipeline, 6/6.
- PASS: `npm run check` completo: lint, TypeScript, 4.016 pruebas Vitest con
  cobertura, 4 pruebas de configuración de release, 8 del service worker,
  build, verificación del bundle y control de duplicación.
- PASS: `git diff --check`.
- Lint conserva cuatro advertencias previas de `coverflow-carousel.tsx`.
- PASS: CI de la PR #63, incluidos frontend, E2E y el control obligatorio `verify`.
- NOT RUN: recorrido humano autenticado en producción y consultas de leads reales;
  el smoke productivo de esta entrega verifica HTTP y los bytes del código servido.

Log conservado: `CRM-Avance-Corp/releases/crm-20260921T175252Z-b0d2ff89e288-evidencia/check.log`.

## Publicación autorizada y comprobada

- PR: `https://github.com/avanza-digital/avancecorp-crm/pull/63`.
- Revisión externa: `miguejbs98`, aprobada sobre `5e538358` a las 17:39:52 UTC.
- CI aprobado: `https://github.com/avanza-digital/avancecorp-crm/actions/runs/35633148405`.
- Commit publicado: `b0d2ff89e288927be01f7abc9d09b482e9a8f955` (squash de la PR).
- Main local, `avancecorp/main` y referencia remota iguales antes de construir
  y publicar; fuente construida en copia limpia. El árbol completo del squash
  es idéntico al de `5e538358`, cuyo frontend pasó los checks locales y de CI.
  Los cambios pendientes del taller conservaron su huella al sincronizar Main.
- Release: `crm-20260921T175252Z-b0d2ff89e288`.
- Build: `build-20260921T175251936Z`.
- ZIP SHA-256: `a6b8f33e21118759d2c77e471c13ea9d172ad6472bac2c4dfcd8dce740055d18`.
- ZIP y manifiesto: `CRM-Avance-Corp/releases/`, fuera del directorio público.
- Hostinger: subida correcta y solicitud aceptada; la versión pública y las
  descargas posteriores confirmaron el despliegue, sin necesitar purga.

**Smoke HTTP PASS:** 108 comprobaciones, cero fallos. Portada, versión y los
68 archivos JS/CSS son idénticos al artefacto. En total hay 96 respuestas con
bytes idénticos, una protección de `.htaccess` y once imágenes servidas como
imagen/HTTP 200 cuyos bytes difieren (compatibles con transformaciones del hosting;
no se afirma equivalencia de píxeles en esta comprobación). El ZIP devuelve 404
en CRM y portal. Dos lecturas de `version.json` confirmaron el mismo build.

Pipeline publicado: `assets/pipeline-C42UhrKr.js`, HTTP 200, SHA-256
`a1c46032ea00968daa436c316346b65acb3425fad0320883ec5860cb004be194`.

Evidencia en `CRM-Avance-Corp/releases/`:
`crm-20260921T175252Z-b0d2ff89e288.manifest.json`, `.hostinger.json` y `.http.json`.
Recuperación frontend: ZIP y manifiesto anterior
`crm-20260921T170501Z-526e728e31ff`, comprobados antes del despliegue.
No se aplicaron SQL, Edge Functions ni cambios del portal.

Esta actualización del acta es posterior al despliegue; no cambia el commit
de origen ni requiere otra publicación del frontend.

## Cierre de sesión

Miguel dio su conformidad («perfecto») y pidió guardar todo y cerrar la sesión.
La corrección queda publicada y verificada. El acta y su enlace desde [[Inicio]]
se guardan como checkpoint documental local; la fuente publicada sigue siendo
`b0d2ff89e288927be01f7abc9d09b482e9a8f955`.

Los logs de checks, CI y construcción, el estado de la entrega y el adaptador
de publicación se conservan en
`CRM-Avance-Corp/releases/crm-20260921T175252Z-b0d2ff89e288-evidencia/`,
con huellas SHA-256. Los ZIP, manifiestos y recibos permanecen en `releases/`.
Los trabajos pendientes de otras tareas se conservan en el taller sin incluirlos
en este checkpoint. La conformidad del usuario no sustituye el recorrido humano
autenticado que figura como NOT RUN.

Relacionado con [[Inicio]] y [[Plan de escalabilidad del CRM a data gigante]].
