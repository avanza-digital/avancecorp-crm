# Fase 0: preparación verificada el 23/10/2026

Estado: **listas preparadas; decisiones y correcciones de datos pendientes**.
Alcance autorizado: integrar los commits locales con `avancecorp/main` y preparar
los casos de la fase 0. No se aplicaron migraciones, reparaciones, permisos ni despliegues.

## Resultado actual

Consultas de producción en `dctqcbznekcyxhjujuci`, solo lectura, el 23/10 entre
10:57 y 10:59 Lima, con contraste adicional a las 11:12–11:13. Cada consulta usa
transacción READ ONLY y timeout. Las consultas principales usan REPEATABLE READ.
Son fotos independientes; el contraste de las 11:12 reprodujo en una sola
transacción los conteos 39 de septiembre + 2 antiguos + 4 retirados.

| Tema | Resultado comprobado | Consecuencia |
| --- | --- | --- |
| 45 fuentes de contrato sin inversión | Se reproduce el total, pero solo **41 contratos existen**; los otros **4 fueron eliminados** y tienen copia de auditoría CRM. | No tratar las 45 como contratos activos ni cargar un lote de 45. |
| 39 de septiembre | Contratos activos, no demo, estado `acreditada`, incluidos en el sello de septiembre. Ninguno tiene fila en `crm.inversiones` por su contrato. | Lista para decidir incorporación a cartera; revisar titular, responsable y vínculos antes de diseñar el lote. |
| 2 antiguos | Uno de marzo y otro de mayo; ambos `fuera_de_plazo`. | Decisión separada, sin incorporarlos automáticamente al lote de septiembre. |
| 4 de octubre | Sus contratos ya no existen; 3 acreditaciones guardan estado `acreditada`, 1 `operacion_cartera`. Dos tienen además registro en `inversiones_eliminadas` con `conversion_anulada=true`. | Revisar retiro/reemplazo. El estado guardado no demuestra que cuenten en el ranking; no se midió el resultado final del ranking. |
| 2 leads sin acreditación desde septiembre | Uno tiene contrato activo no demo e inversión vigente; el otro tiene perfil con nombre DEMO y carece de contrato, inversión y cierre externo. | No describirlos como dos ventas inexistentes. El primero requiere revisar atribución/enlace; el segundo, confirmar que es prueba. |
| 11 contratos sin copia CRM | **11 de 11** tienen evento DELETE en `public.audit_log` con fecha y cuenta autora. Corresponden a las 12 filas del ledger. | Se resuelve la afirmación «sin rastro». Conservar el ledger; el motivo comercial no se deduce del evento. |
| 6 leads con referencia a contrato eliminado | Se confirman 6 y los 6 tienen copia CRM. | Anexo para la fase 3; un contrato del mismo perfil no demuestra que sea reemplazo. |
| Datos personales | `authenticated` tiene SELECT de tabla y lectura efectiva de DNI, fecha de nacimiento y género. La policy de filas incluye Coordinación. | Falta definir roles y ámbito. No se probaron sesiones reales de todos los roles. |

### Contraste adicional antes de decidir

- **36 de los 39 titulares de septiembre no tienen otras inversiones; 3 sí.**
  Esos tres reúnen cuatro inversiones: una renovación de octubre, un upgrade de
  octubre y dos cierres externos en Qorilazo. Tener varias inversiones es válido;
  no se ha demostrado duplicidad. Quedan identificados en el informe nominal
  para revisar el ciclo y las fuentes antes de proponer un lote.
- En las **41 fuentes existentes**, no hay solicitudes por `lead_origen_id`
  ni filas en `inversiones_eliminadas` por esa fuente. Es una comprobación de esas
  rutas de enlace, no una prueba de que no existan vínculos por ninguna otra vía.
- El criterio de la función viva (episodios convertidos desde septiembre) y el
  criterio de fecha del lead devuelven **los mismos 2 casos** sin acreditación;
  diferencia simétrica cero.
- Los 11 DELETE ocurrieron entre **07/09 12:17 y 14/09 11:40 Lima**, antes de la
  instalación de la copia CRM el **15/09 21:44 Lima**, documentada en
  `supabase/migrations/MIGRACIONES.md` (sección `20260915222925`). Se confirmó
  el registro remoto real `20260916024417` y su complemento `20260916024423`.
  Son borrados históricos anteriores a esa protección. Esto cierra la búsqueda
  de rastro de estos 11 casos; no es una auditoría de todos los caminos de borrado.
- **RLS está activa** en `crm.leads` (FORCE RLS no). La puerta de actor activo
  es RESTRICTIVE y la selección de filas es PERMISSIVE; ambas se aplican a
  authenticated. `anon` no tiene USAGE del esquema ni SELECT de tabla/columnas.
  No se encontró `pgrst.db_schemas` en la configuración SQL consultada: la
  exposición efectiva de esquemas por la API no se verificó en esta tarea.

Capital nominal de los 39 contratos de septiembre: **S/ 1.059.272,88 y US$ 35.000,00**,
sin conversión entre monedas. Son importes de contratos, no un cálculo del capital
actual o del rendimiento.

## Dos leads: tratamiento pendiente

- **Caso con inversión:** el historial muestra conversión el 16/09. El contrato actual
  se creó el 06/10 con fecha comercial 16/09 y la inversión tiene
  `es_primera_conversion=false`. El lead tiene `contrato_id=NULL` y no existe
  acreditación. No crear un segundo contrato ni una segunda inversión. Confirmar
  atribución y preparar el tratamiento compatible con septiembre ya sellado.
- **Caso con nombre DEMO:** conversión del 18/09 por la cuenta de Miguel. Nombre e
  historial sugieren prueba; no se tomó esa inferencia como decisión comercial ni
  se anuló nada.

La definición viva de `private.conversion_sincronizar_lead` busca una solicitud
confirmada con inversión marcada como primera conversión, un contrato explícitamente
enlazado en el lead o un cierre externo inicial. No basta con que exista un contrato
del mismo perfil. Esto explica por qué no se debe intentar crear otra venta para
resolver el primer caso. La causa histórica exacta requiere revisar la solicitud
original y cualquier reemplazo; no se ha dado por demostrada.

La definición viva de `private.conversion_exclusion_fuente` devuelve
`fuente_retirada` cuando el contrato ya no existe. No se invocó ninguna función
que escriba datos.

## Entregables y reproducción

- `fase-0-listas.sql`: contratos existentes sin inversión, dos leads, contratos sin
  copia CRM, seis referencias y meses cerrados.
- `fase-0-trazabilidad.sql`: historial de los dos leads, borrados en la bitácora del
  portal y permisos efectivos. Resuelve los casos por condición, sin UUID personales fijos.
- `fase-0-fuentes-retiradas.sql`: descompone las 45 fuentes y enumera las cuatro eliminadas.
- `fase-0-contraste.sql`: otras inversiones por titular, solicitudes, eliminaciones,
  comparación de criterios de conversión y metadatos RLS.
- `fase-0-contexto.sql`: fuentes de las otras inversiones y versiones remotas de auditoría.
- Informe nominal local:
  `CRM-Avance-Corp/output/fase-0-candados-2026-10-23/LISTAS-PARA-MIGUEL.html`.
- Evidencia nominal local: `evidencia.json` y `contraste.json` en esa misma carpeta,
  ignorada por Git. El enmascarado de texto libre es parcial; esos archivos son privados.

Los SQL contienen solo lecturas de tablas/catálogos y límites locales de sesión.
Sus resultados tienen nombres e información comercial: deben guardarse fuera de Git.
Los UUID distinguen entidades; un mismo número de contrato puede aparecer en más de
un UUID eliminado. No deduplicar el informe solo por número de contrato.

## Decisiones concretas

1. Si los 39 contratos de septiembre deben incorporarse a la cartera, conservando
   acreditaciones y sello, con revisión individual de los tres titulares que ya
   tienen otras inversiones; qué tratamiento separar para los dos contratos antiguos.
2. Si la venta del caso con inversión debe acreditarse al analista de su episodio,
   y si el caso DEMO es prueba. Se entregan nombres e historial en el informe local.
3. Qué roles y ámbitos pueden ver DNI, fecha de nacimiento y género.

Estas decisiones no equivalen a autorizar SQL todavía no preparado. Primero se
prepara y prueba cada corrección, con sus precondiciones; después se presenta la
aplicación concreta conforme a las reglas del proyecto.

## Verificación y límites

Revisión secundaria: Claude devolvió CHANGES_REQUESTED. Se incorporaron el
contraste por titular, solicitudes y eliminaciones; la cronología de la auditoría;
los metadatos RLS; y la comparación de criterios de conversión. Se precisó que
varias inversiones por titular no prueban duplicidad. No se solicitó otro dictamen;
la validación final de esas ampliaciones corresponde al PRIMARY.

- PASS: consultas ejecutadas en producción dentro de transacciones de solo lectura.
- PASS: comprobación cruzada de contratos existentes, inversiones, acreditaciones,
  copias de eliminación y eventos DELETE del portal.
- PASS: 11 eventos de borrado corresponden a los 11 UUID, sin fusionar por número.
- PASS: contraste adicional ejecutado; criterios del lead y del episodio coinciden.
- PASS: JSON/Python heredados con sintaxis válida; anclas, IDs y tablas HTML comprobados;
  importes cotejados con aritmética decimal; archivos nominales ignorados por Git.
- NOT RUN: reparaciones y migraciones; no forman parte de esta preparación.
- NOT RUN: pruebas funcionales del CRM, E2E y build; no cambia código de producto.
- No se ha verificado la visibilidad de cartera o ranking mediante sesiones reales.
- El dump heredado `catalogo-estructura.sql` dispara dos avisos de whitespace en
  `git diff --check` (1680–1681), dentro del literal SQL de `btrim`. Se conserva
  el contenido de esa evidencia; eliminar esos caracteres alteraría el literal.

Relacionado: [[Auditoria de tablas - reglas basicas de Postgres en crm y private (2026-10-22)]].
