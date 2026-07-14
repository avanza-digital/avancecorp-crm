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

La pantalla muestra una decisión resumida, métricas, bandejas, búsqueda, filtro por analista y detalle paginado. La vista inicial **Estado de base** conserva todas las filas del Excel y muestra explícitamente `Cliente en sistema` y `Contrato cargado`; las otras bandejas sirven para ejecutar acciones. Ofrece dos descargas:

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
