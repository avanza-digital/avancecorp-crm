# Citas — reparación de conexiones en local

Estado: implementación local de la primera parte de la auditoría. Sin instalación SQL remota, commit ni publicación de esta reparación. Las nuevas metas y el pronóstico continúan pendientes; no están resueltos por este cambio.

## Cambio preparado

- `crmQueryKeys.citasGerencia` queda dentro de la familia `reuniones` que invalidan las escrituras comerciales.
- Crear, cerrar, reprogramar, convertir, anular y reasignar disparan la actualización del detalle. Antes de invalidar se cancela su primera lectura en vuelo, para que una respuesta capturada antes de guardar no gane después.
- La consulta activa vuelve a leer cada 60 segundos, al volver a la ventana y al reconectar. No son actualizaciones instantáneas entre equipos. Conserva actor, mes y filtros; no consulta periódicamente en segundo plano.
- El adaptador acepta `estado_comercial` calculado por el servidor. Mantiene compatibilidad con V1/V2 anteriores mientras la candidata SQL no esté instalada.
- La candidata `20260912151320_crm_citas_consulta_nucleos.sql` centraliza cohorte, historial, estados y postventa en `private.citas_episodios`. Añade una sobrecarga que recibe los IDs de la cohorte y conserva la firma anterior delegando en ella. Los cierres se concentran en `private.conversion_cierres`, compartido por `conversion_episodios` y Citas; no se duplican sus reglas ni se calculan las otras ramas para descartarlas después.

La conversión vigente a un perfil cliente conserva su evidencia original en `crm.leads`/`public.perfiles` y el anulador canónico. Es una regla operativa aprobada: no se sustituye por el índice ponderado, no se exige un asiento histórico de asignación y no se infiere capital desde `monto_estimado`. Esta reparación no conecta un ticket ni un importe de depósito que el contrato actual no entrega.

## Conservación de comportamiento

Se conserva la cohorte por vencimiento del mes en Lima, todo su historial entre meses, enlaces de reprogramación del mismo lead, fecha de asistencia del resultado vinculado y corte del servidor. Depósitos siguen contando conversiones posteriores a asistir, con deduplicación por lead y exclusión de anulaciones. 10.000 filas se devuelven completas; 10.001 disparan error.

La única ampliación del JSON es el estado comercial canónico. El banco compara cada respuesta con la función anterior bajo la misma transacción y reloj, retirando sólo ese campo antes de exigir igualdad. Incluye las pruebas existentes de detalle y depósitos, más estados y cierres de todos los canales.

## Gobernanza y límites

Captura de catálogo: `fuentes-servidor.json`. No contiene filas de clientes ni credenciales. El lector previo tiene MD5 `2d39c2bfc0c7d30b9aaa42b2bcd1669f`.

Se registra exclusivamente el lector de Citas como consumidor mixto con razón y huella. El preflight exige las definiciones y ACL revisados y un sello previo válido. La migración conserva otras excepciones, otros contadores, permisos y tope; cualquier diferencia no prevista revierte la transacción. Los dos helpers nuevos quedan privados; el gate también comprueba sus ACL. Hay pruebas de deriva deliberada, fallo tardío y grants indebidos a los nuevos helpers.

El control global **sigue pendiente**: al inicio había 34 contadores frente al tope 30 y cuatro lectores ajenos sin corregir, además de Citas. Esta migración no aumenta el techo ni exime esas otras funciones. No equivale a un PASS global del sistema.

## Verificación realizada

| Comprobación | Resultado |
| --- | --- |
| `npm run check` en `app` | PASS: lint, tipos, 3.465 tests en 240 archivos, configuración de release, build, bundle y duplicación. Cuatro avisos de accesibilidad existentes en `coverflow-carousel.tsx` ajeno al cambio. |
| Tests focalizados de Citas/caché/store | PASS: 105. Incluyen QueryClient/observadores reales y respuestas antiguas que llegan después de las escrituras y de dos recargas sucesivas. |
| `playwright test e2e/citas-gerencia.spec.ts` | PASS: 3. Filtros/navegación, RPC ausente sin cifras ficticias y refresco al minuto conservando semana. Backend simulado. |
| `python3 supabase/scripts/test-citas-nucleos-local.py` | PASS: SQL exacto en PG17 desechable, paridad, todos los estados, anulaciones, corte inclusivo, límites, roles/ACL, deriva y rollback. |
| `npm run check:scripts` | PASS. |
| `npm run test:edge-preflight` | PASS. |
| `seed:preflight`, `test:rls:preflight`, `gate:realidad` | NOT RUN: falta `SUPABASE_URL` en ese entorno de comandos. |
| Replay/matriz completa RLS, advisors y planes con volúmenes de rama | NOT RUN: candidata aún sin instalar en una rama autorizada. |
| Revisión independiente | Dos dictámenes CHANGES_REQUESTED evaluados por Codex. Correcciones y pruebas finales completadas; no hubo un PASS independiente ni aprobación de despliegue. Ver `decision-review.md`. |

El banco local carga las funciones capturadas sin cambiar su fuente. Sus tablas son mínimas; Auth, pesos y atribución de cartera son simulados. Prueba contratos y guardias, no sustituye la infraestructura completa de Supabase ni el gate de producción. Se detiene al terminar y no escucha por TCP. Evidencia: `verificacion-sql-local.json`.

El banco también compara íntegramente los núcleos anteriores contra los nuevos mediante EXCEPT ALL, incluidos pesos y fechas, con ámbitos global/propio, período fijo/nulo y selección vacía/no vacía (también ID inexistente, duplicado y NULL). `planes-volumen-local.json` contiene EXPLAIN ANALYZE de 20.000 leads, 60.040 tareas, 20.000 asignaciones y 3.000 operaciones en cinco años. Lector nuevo aproximadamente 30 ms, anterior aproximadamente 2 ms. Se ensayaron también 10.000 citas de 2.500 leads con cierres/reagendas: aproximadamente 774 ms nuevo frente a 552 ms anterior. Se midieron ambas versiones de los núcleos por ámbito/período: sus costes y variación están en `decision-review.md`. Son referencias locales con dependencias simuladas, no tiempos garantizados del servidor.

Decisiones sobre el review: `estado_comercial: null` continúa rechazado porque indica un contrato incompleto; sólo el campo ausente permite compatibilidad. Un estado nuevo también sería rechazado por el picklist de `estado`, por lo que aceptar null no resuelve esa migración. El test de precedencia del servidor ya existía y se adjunta. La carrera propuesta para recargas sucesivas no se reprodujo: el test nuevo termina con el último dato, sin invalidación pendiente. No se añadió serialización que demore ese último refresco. Foco/reconexión ahora respetan la frescura de 30 s y la invalidación comercial garantiza explícitamente el prefijo de Citas, sin doble refetch por sus ancestros.

## Pendientes funcionales

El usuario confirmó 1,25 citas por lead, 70% entrevistas y 70% depósitos. La base incluye leads asignados sin citas y excluye el registro manual propio. Aún falta confirmar alcance de esa exclusión sobre actividades/resultados, entrevistas repetidas frente a personas únicas, atribución/mes de resultados, semana acumulada y período del ticket. Las preguntas se enviaron durante esta tarea; no se han recibido respuestas.

El módulo actual conserva la meta histórica 3/125% y su base de leads con cita. No presentarlo como la implementación de 1,25. El Control de Superadmin sigue siendo un borrador; aún no aplica reglas a los lectores. Ticket/proyección necesitan hechos de capital por moneda y atribución, no montos estimados.

Antes de instalar: ensayar SQL en rama con esquema completo y RLS/advisors, medir los consumidores anteriores, resolver el gate global y confirmar el SQL exacto según el procedimiento del proyecto. El frontend es compatible con el servidor actual. No cambia firmas RPC de `crm` ni tablas, por lo que esta candidata no requiere regeneración de tipos.
