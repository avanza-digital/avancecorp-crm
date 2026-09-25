# Realidad productiva al preparar F5

Consulta del 24/09/2026 a las 17:29:58 Lima, transaccion de solo lectura.
Se reprodujeron los nueve supuestos de `supabase/scripts/gate-realidad.mjs`
y se llamo a `crm.alarma_conversion_fn` bajo el rol de servicio, sin identidad humana.
El CLI por PostgREST sigue **NOT RUN**; esta evidencia acredita las consultas SQL.

| Supuesto | Resultado | Evaluacion |
| --- | ---: | --- |
| Periodos con metas | 21 | PASS |
| Vendedores efectivos sin supervisor activo | 0 | PASS |
| Leads activos | 2.302 | PASS |
| Actividades | 15.938 | PASS |
| Tareas pendientes activas | 1.322 | PASS |
| Miembros operativos activos | 22 | PASS |
| Clientes activos sin domicilio legal | 290 | DIVERGENCIA PREEXISTENTE |
| Revisiones de metas bajo el sello | 0 | PASS |
| Conversion entre cinco caminos | Coincide: divisor 1.327, numerador 93,85, 7,07 % | PASS |

La primera consulta de domicilio reprodujo `42P01`: el script actual busca
`crm.perfiles`, relacion inexistente; la fuente correcta para este conteo es
`public.perfiles`. Se corrigio exclusivamente la consulta de auditoria.
Los 290 domicilios pendientes son una condicion de contratacion existente,
no una cifra de F5 ni un problema creado por su tablero. No se completaron datos
por suposicion ni se modifico ese flujo durante esta tarea.

Esta auditoria confirma que hay datos reales para el tablero. Las pruebas F5
tambien cubren vacios, errores, revocacion, autores fuera del roster y ausencia
de historia. No atribuye a produccion resultados de funciones F5 aun no instaladas.

[SQL ejecutada](realidad-productiva.sql) - [resultado agregado](realidad-productiva.json).
