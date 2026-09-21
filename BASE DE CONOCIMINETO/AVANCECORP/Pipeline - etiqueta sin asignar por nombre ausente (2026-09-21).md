---
tags: [crm, pipeline, analista, diagnostico]
actualizado: 2026-09-21
estado: corregido-y-verificado-localmente-sin-publicar
---

# Pipeline — «sin asignar» por nombre ausente

Miguel preguntó por qué los leads del pipeline del analista muestran «sin asignar»
y después autorizó corregirlo. Corrección implementada y verificada localmente
el 21/09/2026, pendiente de publicación.

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

El último cambio de Pipeline es `dbfa9d6b` (Fase 4 «sin topes»), que pasó sus
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
- NOT RUN: recorrido visual en navegador, E2E completo y consultas productivas;
  no se requieren cambios de servidor para esta corrección de presentación.

Log local: `/private/tmp/avancecorp-pipeline-check-20260921.log`.
No se realizó commit, push ni despliegue durante la corrección.

Relacionado con [[Inicio]] y [[Plan de escalabilidad del CRM a data gigante]].
