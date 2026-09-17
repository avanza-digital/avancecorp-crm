# Conciliación de clientes

## Propósito

Pantalla administrativa de solo lectura para comparar una base mensual de Excel con los clientes y contratos existentes en el CRM. Está pensada principalmente para Gloria y también está disponible para superadmin.

La función es distinta de [[Importador de clientes]]: conciliar informa qué existe, qué falta y qué requiere revisión, pero no crea usuarios, contratos ni modifica registros.

## Acceso y flujo

- Entrada desde **Administración → Clientes → Conciliar base**.
- La administradora puede arrastrar o elegir un archivo `.xlsx`, `.xls` o `.csv` de hasta 15 MB.
- Al seleccionar el archivo, el análisis comienza automáticamente.
- Se detecta una hoja con las columnas de DNI y número de contrato; la hoja `JUNIO` tiene prioridad cuando existe.
- Se procesan como máximo 5,000 filas por archivo.
- El archivo se lee en el navegador y al CRM solo se consultan las coincidencias necesarias bajo la sesión y las políticas RLS vigentes.
- El resultado se organiza en bandejas de trabajo: **Sin usuario**, **Sin contrato**, **Coincidencias**, **Revisar** y **Todos**.

## Criterio de conciliación

La comparación usa conjuntamente:

1. DNI normalizado a dígitos.
2. [[Número de contrato]] normalizado al formato canónico `AAAA-MM-000000`.

No se usa el nombre como llave. El nombre y el analista sirven para informar y detectar diferencias.

Estados posibles por fila:

- Coincidencia completa: el DNI y el contrato pertenecen al mismo perfil cliente.
- Usuario sin contrato: existe el perfil cliente por DNI, pero el contrato no está registrado.
- Contrato con DNI distinto: existe el contrato, pero no se encontró un perfil cliente con el DNI del Excel.
- Contrato vinculado a otro DNI: existen tanto el DNI como el contrato, pero pertenecen a perfiles diferentes.
- Sin usuario ni contrato: no existe ninguna de las dos coincidencias.

También se señalan documentos o contratos con formato dudoso, contratos duplicados dentro del Excel y diferencias entre el analista del Excel y el analista asignado en el CRM.

Los documentos vacíos, múltiples, en notación científica, con longitud inválida o con formato decimal ambiguo no se cruzan como usuarios. Para el entregable rápido, un cliente queda bloqueado si cualquiera de sus filas presenta conflicto, si participa en una celda con varios DNI, si falta cliente/analista o si esos datos difieren entre filas del mismo DNI.

## Entregable

La pantalla muestra una decisión resumida, métricas, bandejas, búsqueda, filtro por analista y detalle paginado. La vista inicial **Estado de base** conserva todas las filas del Excel y muestra explícitamente `Cliente en sistema` y `Contrato cargado`; las otras bandejas sirven para ejecutar acciones. En las hojas de detalle del **Reporte completo**, **Fecha contrato (Excel)** conserva el valor de la columna `FECHA CONTRATO` de la base adjuntada (por ejemplo, `15/06/2026`). No toma esta fecha de `contratos.fecha_inicio` en el CRM. Ofrece dos descargas:

- **Clientes sin usuario:** una fila por DNI, solo clientes seguros para gestionar; incluye cliente, DNI, contratos, analista y filas de origen.
- **Reporte completo:** auditoría con las hojas siguientes.

- Resumen
- Clientes sin usuario
- Documentos por revisar
- Contratos no registrados
- Coincidencias
- Revisar
- Detalle completo

Las celdas de texto se protegen contra ejecución accidental de fórmulas en Excel.

## Permisos y seguridad

- La pantalla exige un perfil activo con rol `admin` o `superadmin`, de acuerdo con [[Acceso y roles del CRM]].
- Las consultas a `perfiles`, `contratos` y el catálogo legacy de asesores respetan RLS.
- No usa service role ni operaciones `INSERT`, `UPDATE` o `DELETE`.
- No requiere una migración nueva: `perfiles.id` identifica al usuario y `contratos.cliente_id` enlaza el contrato con ese perfil.

## Validación inicial

Con `Contratos Junio 2026.xlsx`, validado el 2026-07-13 contra el estado de la base en ese momento:

- 182 filas de contratos
- 175 filas con documento evaluable y 7 documentos por revisar
- 162 clientes válidos únicos
- 80 clientes con usuario y 82 sin usuario
- 83 contratos encontrados y 99 no registrados
- 77 filas donde DNI y contrato corresponden al mismo cliente antes de aplicar alertas adicionales
- 5 filas con contrato existente y DNI distinto
- 78 clientes sin usuario listos para el entregable rápido; 4 se excluyen hasta revisar sus datos

Estas cifras son una línea base de prueba; pueden cambiar cuando se creen usuarios o contratos en el CRM.

## Implementación

- Página: `public_html/admin/conciliacion.html`
- Orquestación y exportación: `public_html/js/admin/conciliacion.js`
- Núcleo puro de normalización y estados: `public_html/js/admin/conciliacion-core.js`
- Estilos: `public_html/css/conciliacion.css`
- Pruebas: `public_html/tests/conciliacion-core.test.mjs`

Estado al 2026-07-14: segunda iteración implementada, verificada contra el Excel real y la base de producción, y desplegada en `https://miavance.com/admin/conciliacion.html` con el service worker `avance-v98`. La vista inicial ahora es **Estado de base**: para cada fila del Excel muestra si el DNI está en el CRM y si el número de contrato está cargado. Página, CSS, JS, núcleo y `_helpers.js` quedaron idénticos byte a byte entre local y producción.

El 2026-07-15 se corrigió el origen de la fecha después de revisar una captura de la base maestra: el **Reporte completo** ahora muestra **Fecha contrato (Excel)** a partir de la columna `FECHA CONTRATO` del archivo adjuntado. Esta versión reemplaza la implementación anterior que usaba `fecha_inicio` del CRM. Se desplegó como `conciliacion.js?v=5`, `conciliacion-core.js?v=4` y service worker `avance-v100`; página, módulos y SW quedaron idénticos byte a byte entre local y producción, y el ZIP respondió 404.

## Cuentas mancomunadas (2026-09-17)

La administradora reportó que los contratos mancomunados salían como «No evaluable» y en **Revisar**: el Excel trae los dos DNI en la celda y el conciliador solo conocía al titular principal (`contratos.cliente_id`). Desde esta versión el conciliador también lee `contrato_titulares` (ver [[Cuentas mancomunadas]]):

- **Celda con varios DNI** + contrato registrado: si los DNI son exactamente los titulares del sistema (principal + co-titulares, en cualquier orden) → **Coincidencia completa · mancomunada**. Se evalúa por el principal, y «Cliente en sistema» y el documento muestran a los dos.
- Si un DNI no es titular, si el sistema registra otro titular que el Excel no trae, o si el contrato no tiene co-titulares → sigue en **Revisar** con el motivo exacto.
- **Una fila por titular** con el mismo contrato: ya no alerta «contrato repetido». La fila del co-titular sale **Coincidencia completa · co-titular** («Co-titular · sin acceso propio») y no cuenta como cliente sin usuario.
- El reporte agrega la columna **Cuenta mancomunada** y el conteo en el Resumen.

Pagos no necesitó cambio: la exportación pone en «Titular de la cuenta» al beneficiario cuando la cuenta está marcada como de titular distinto. En prod (17/09) hay 19 contratos mancomunados activos: 15 cuentas en nombre del principal y 4 en nombre del co-titular, todas registradas así. El sistema no puede detectar una cuenta del co-titular que se cargó sin marcar «titular distinto».

Versiones: `conciliacion-core.js?v=5`, `conciliacion.js?v=8`. Pruebas: `tests/conciliacion-core.test.mjs` 22/22.

**Publicado el 2026-09-17 (~12:50 Lima).** Portal `c73e734` (push a `avanzadigitald/avancecorp-portal` main). ZIP `portal-20260917T174211Z-c73e734.zip`, SHA-256 `9a058de61f4f284daf3ba35f0469d419c83df02809ff11845fe114e7942791c5`: 93 archivos, idéntico en lista al sitio vivo; preflight aprobado. Tras la purga: 77/77 archivos html/js/css/json idénticos al ZIP, tres lecturas estables de `conciliacion.js?v=8` y `conciliacion-core.js?v=5`, ZIP 404. El preflight marcó `clientes.js` como distinto: era una copia vieja de la URL sin `?v` en la CDN, no trabajo ajeno. Sin cambio de service worker (HTML network-first, JS por URL versionada). Rollback: republicar `portal-20260907T205351Z-497a5df.zip` no sirve (le falta trabajo posterior); revertir `c73e734` y reconstruir.
