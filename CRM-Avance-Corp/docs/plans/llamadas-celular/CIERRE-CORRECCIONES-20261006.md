# PR #190 — correcciones e integración del 06/10/2026

**VERDICT: correcciones verificadas; no equivale a autorización de publicación ni de activación de C1.**

Miguel encargó a Codex corregir el informe del #190 y entregar el resultado a Jhosep. Se conserva la rama de
Jhosep `crm/llamadas-190-integrar-jhosep-20261006` hasta `93374fb4` y se integra `main` hasta `afae7b59`.
Las once migraciones de Jhosep quedan inmutables. La correctiva es la **duodécima**, `20261006162813`.

## Correcciones

1. El conflicto de router queda resuelto por el aporte de Jhosep: `consultaCitas` conserva su posición y
   `llamadaOrigenId` queda al final. La normalización de `App.tsx` también conserva el origen.
2. Un número con lead abierto ajeno, `no_contactar`, persona vetada o cliente activo no produce una llamada comercial,
   aunque exista un descartado reutilizable. El veto se comprueba también si la política permite números desconocidos.
3. El antiguo dueño y su supervisor no pueden ver, descartar ni reasociar una llamada ajena sobre su descarte.
   Gerencia conserva acceso. Quien toma el lead accede desde entonces. Una llamada propia de supervisor no desaparece
   de su historial al descartar el lead mientras conserve permiso sobre él.
4. La ingesta ancla los leads coincidentes antes de decidir candidatos y atención; después de esperar una reasignación
   usa el estado confirmado. La carrera con dos conexiones espera y no guarda una candidatura obsoleta.
5. Al enlazar un resultado se retiran sus intenciones anteriores en la misma transacción. Reservar X y luego enlazar Y
   ya no deja una intención que intente reutilizar el resultado cuando llegue X.
6. NUL, sustitutos Unicode sueltos y números no finitos se envían como carga nula a la puerta: conservan autenticación y
   cuota y reciben 400; no fallan al convertir a jsonb con un 503. Unicode válido sigue admitido.
7. Bandeja/detalle conservan el origen añadido por Jhosep en la décima; la duodécima lo añade a resueltas y marcas.
   La encuesta usa v5 con origen y vía, conserva el recibo al perder la respuesta y mantiene v4 para llamadas sin origen.
8. Fuente real con RPC tipadas, validación de respuesta, caché por actor, cursores sin pérdida de microsegundos,
   estados de carga/error, reintento y paginación. Una respuesta sin origen no se presenta como lista operativa.
9. Una encuesta abierta desde «Llamar» recibe el origen que llega al colgar sin cambiar su identidad ni pisar otra llamada.
   Motivos nuevos de `no_enlazado` tienen texto seguro y no convierten un resultado ya guardado en falso fallo.
10. Foco estable tras descartar/elegir, colores de texto con contraste y anuncio de resultados de la búsqueda.
11. Se conserva la undécima de Jhosep: salud sin horas exactas del latido, y guía de macro con latido cada seis horas.
    Se añade el índice de la FK de asignación señalado por advisors.

## Verificación

| Comprobación | Resultado |
| --- | --- |
| `npm run check`, app integrada | **PASS**: 389 archivos, 6.245 tests; lint, tipos, cobertura, build, release-config, bundle y duplicación |
| E2E Docker local | **PASS**: 17/17; resultado, vuelta de llamada, analista y nueva pestaña Celular (descarte, foco y resueltas) |
| `npm run test:llamadas:local` | **PASS**: 415/415; doce migraciones, oráculos anteriores, cinco mutantes de la correctiva, carreras y reversas |
| Edge: check + tests | **PASS**: 17/17 |
| Mutantes Edge | **PASS**: 18/18 detectados |
| `check:scripts`, seed y RLS preflight | **PASS**; el check HTTP necesitó permiso para escuchar en localhost |
| Banco con esquema completo | **PASS del bloque de llamadas**: 197 ✓, 0 ✗, 0 saltadas. v5 compuesta con v4 real |
| Matriz RLS global del banco | **FAIL conocido**: 8/3014, mismos ocho fallos de antes del PR; no declarar gate global verde |
| Aplicación y registradores 10/11/12 | **PASS**; registrador12 repetible y coteja los siete cuerpos y fuente exacta |
| Reversa12 y reaplicación en esquema completo | **PASS**: vuelve a la huella exacta de las once. La reversa se niega tras altas/uso |
| Advisors oficiales Splinter, solo lectura local | 0 ERROR; 32 WARN heredados. Llamadas: solo 18 INFO (7 RLS sin policies por diseño y 11 índices sin uso); FK de asignación cubierta |
| Tipos generados desde banco integrado | **PASS**: coinciden con el archivo entregado; sin objetos eliminados del esquema |

Los ocho fallos de fondo son: una expectativa de fila bancaria, tres de R2/hito de activación y cuatro por la bandera
`potencial_lead` ya encendida. El contraste previo del mismo banco fue 8/2817 sin llamadas y 8/3005 con las nueve.
No se modificaron esos módulos para ocultar los fallos.

Los tipos incorporan también ocho puertas B9/B10 que ya estaban en el esquema de producción pero faltaban en `main`.
CLI local 2.117.0 omite `__InternalSupabase.PostgrestVersion`; esa metadata es la única retirada, no una RPC ni tabla.
Se ejecutó también el gate de realidad sobre el **banco local**: no certifica la configuración de producción.

## Revisión independiente

Claude, como `SECONDARY_REVIEWER` mediante `scripts/claude-review`, pidió corregir el veto con política permisiva y
la visibilidad de la llamada propia de supervisor. Ambos casos quedaron corregidos, con controles positivos y mutantes.
Se verificó que los INSERT actuales de enlaces no usan `ON CONFLICT DO NOTHING` y que cumplir una intención tolera
su retirada; la limpieza del trigger es atómica con esos escritores. `persona_vetada` real devuelve `EXISTS`, no NULL.

El intento de segunda revisión devolvió una respuesta incompleta/sin `VERDICT`, rechazada por el wrapper: **no se
contabiliza como PASS**. La integración posterior de la rama de Jhosep se verificó con los gates indicados arriba.

## Límites y siguiente paso

- Los locks cubren cambios sobre las filas coincidentes existentes; no serializan todas las altas de otro lead,
  cambios simultáneos de teléfono ni cambios externos de rol/cliente. Un conflicto de locks sigue siendo reintentable.
- El banco está en modo SLA `legado`. **NOT RUN**: gate de realidad en producción, otra configuración SLA de producción,
  aplicación/despliegue productivo y prueba de un celular físico.
- F4-c (tarjeta de celulares), F4-d (piloto C1) y F4-e (supervisión/gerencia) conservan los planes de Jhosep; no se declaran
  terminados por conectar la pestaña del analista.
- Antes de publicar: resolver o aceptar explícitamente los ocho fallos de fondo según el gate del proyecto, comprobar el
  modo SLA real y ejecutar el procedimiento de publicación autorizado. No activar C1 antes de su runbook.
- Orden SQL: las once de Jhosep → `20261006162813_crm_llamadas_celular_cierre_revision.sql` → registrador de cada una.
  Reversa sin uso: cierre-revision → salud-sin-hora → bandeja-con-origen → resueltas-paginadas → las anteriores.
  Tras altas/uso, apagar y corregir hacia adelante. La reversa no modifica el historial de migraciones automáticamente.

Las credenciales y evidencias completas del banco permanecen locales; no se suben al repositorio.
