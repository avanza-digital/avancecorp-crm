---
tags: [crm, rentabilidad, publicacion]
fecha: 2026-09-18
estado: sql-aplicado-front-en-publicacion
---

# El botón controla toda la exigencia de tasa

Miguel pidió: «ok el boton tiene que controlar todo por favor», después de
[[Modo observacion mantiene solicitud de tasa - diagnostico 2026-09-18]].

Implementación en CRM, portal y ocho funciones SQL. En observación
no se solicita ni consume aprobación y las solicitudes pendientes dejan de
bloquear conversión/alta. Al reactivar vuelve enforcement. Se conserva el
historial y se enlazan aprobaciones compatibles para que sigan sirviendo si
se reactiva después de convertir y antes de contratar. Conflictos o documentos
distintos no se enlazan y no bloquean observación.

Siguen vigentes identidad, permisos, origen del contrato, tasa positiva con
dos decimales, tope técnico y PDF. Renovación/upgrade conserva la base heredada
aunque supere el tope actual, hasta el máximo absoluto de 50 %. La consulta
productiva de solo lectura encontró dos contratos activos/vencidos >28 %.

Las pantallas refrescan el modo cada 30 segundos y al recuperar foco. Si se
reactiva con una tasa distinta y el campo queda fijo, muestra que es inválida
y permite confirmar la tasa vigente, sin sustituirla silenciosamente.

Verificación local: 3.697 pruebas CRM, build y gate integral; ocho E2E de tasas
en escritorio/móvil; SQL con modo efectivo, pendientes, aprobación previa,
herencia y reversa exacta; tres pruebas nuevas de portal. Los dos fallos del
banco completo del portal existían antes (83/85 baseline; 86/88 candidata).
Detalle y dictámenes en `CRM-Avance-Corp/supabase/scripts/rentabilidad-modo/`.

Migración aplicada en producción el 18/09/2026 a las 16:05 Lima:
`20260918210543_crm_modo_rentabilidad_integral.sql`.
La candidata verifica la definición completa de las ocho funciones antes de
reemplazarlas. No cambia la política elegida por Gerencia ni datos de negocio.
La prueba usa Docker y datos sintéticos, con las funciones/puertas vigentes
capturadas por SELECT. No equivale al ensayo remoto con matriz RLS/advisors.

La rama remota vacía no pudo reconstruir dos migraciones históricas que exigen
datos productivos en sus postflights. Se eliminó para detener el costo. El SQL
completo pasó en producción dentro de una transacción con `ROLLBACK` antes de
aplicarse; después se comprobaron hashes, capacidad pública, una solicitud
pendiente real sin bloqueo en observación y advisors con 0 errores.

Relacionado: [[Inicio]],
[[Plan Rentabilidad server-side - tasa decidida por politica 2026-09-06]],
[[Solicitud de tasa en el lead - publicada 2026-09-09]],
[[Rentabilidades menores a 15 - publicacion autorizada 2026-09-14]].
