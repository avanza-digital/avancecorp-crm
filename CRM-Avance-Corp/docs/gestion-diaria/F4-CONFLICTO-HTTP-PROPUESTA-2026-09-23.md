# F4 — quinto SQL para resolver el conflicto HTTP

Estado al 23/09/2026: **prueba local PASS; autorización y ensayo remotos pendientes**.
Miguel reanudó el trabajo. Producción conserva política v1 con cortes OFF y todavía
no tiene los cuatro SQL finales de F4 ni este correctivo.

## Problema y resultado esperado

Dos gerentes que guardan desde la misma versión pueden competir por publicar una
política o cambiar el control de avisos. Una solicitud debe confirmar y la otra
recibir un conflicto definitivo que pida recargar. El ensayo remoto descubrió que
PostgREST 14.5 reintenta `40001` indefinidamente; la segunda petición vence por
timeout. El banco local anterior, con 16.2, no reproducía ese fallo.

El correctivo devuelve `PT409`, que PostgREST convierte en HTTP 409. Conserva el
mensaje de recarga, los locks, la comprobación de versión, reglas y permisos.
La causa y solución están documentadas por
[Supabase](https://supabase.com/docs/guides/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b)
y el contrato de errores por [PostgREST 14](https://docs.postgrest.org/en/v14/references/errors.html).

## Archivo exacto propuesto

[`20260923021512_crm_gestion_diaria_conflicto_http.sql`](../../supabase/migrations/20260923021512_crm_gestion_diaria_conflicto_http.sql)

SHA-256: `428e6a19951afc12315b61c760ba679e37e0399ca4aa0d44dde7f938ce3ad18a`.

| Objeto | Cambio |
|---|---|
| `crm.publicar_politica_gestion_diaria(integer,timestamptz,jsonb,text)` | Un código `40001` → `PT409`. |
| `crm.controlar_avisos_gestion_diaria(integer,boolean,text)` | Un código `40001` → `PT409`. |
| `private.assert_gestion_diaria_configuracion()` | Las dos huellas de las RPC anteriores. |

La transacción exige las huellas previas exactas, un único punto de sustitución,
las huellas nuevas esperadas y los mismos propietarios, ACL, argumentos, retorno,
volatilidad, SECURITY DEFINER y configuración. Después ejecuta los gates de
Gestión Diaria y SLA y solicita recargar el esquema. No contiene DML de negocio,
no publica políticas ni activa cortes. Los cuatro SQL ya aprobados quedan intactos.

## Evidencia obtenida

| Verificación | Resultado y alcance |
|---|---|
| SQL directo de los dos conflictos | PASS: `PT409`, configuración sin cambios. |
| Gates y 24 mutantes | PASS, transacción de prueba revertida íntegramente. |
| Instalación local | Solo tres funciones cambiadas; atributos, permisos e historial conservados. |
| Dos sesiones Auth y lecturas paralelas | PASS, dos respuestas 200 realmente medidas. |
| Carrera de publicación de política en PostgREST 14.5 | PASS: dos solicitudes observadas en el lock a los 123 ms; respuestas 200 + 409/PT409. |
| Carrera de control de avisos en PostgREST 14.5 | PASS: dos solicitudes observadas en el lock a los 123 ms; respuestas 200 + 409/PT409. |
| `check:scripts`, `seed:preflight`, `test:rls:preflight`, `test:edge-preflight` | PASS el 23/09; los preflights de seed/RLS usan los valores ficticios de CI y no abren conexiones. |
| Correctivo en Supabase remoto | NOT RUN: falta autorización de este quinto archivo. |

Final HTTP local: `2026-09-23T14:20:11.911Z` (09:20 Lima). Evidencia privada en
`/private/tmp/gestion-diaria-f4-http.WQNCJc/conflicto-http/`: `ensayo.json`,
`reanudacion-sql.log`, `instalado-local.json`, `diagnostico-transporte.json` y
`concurrencia-diagnostico-43.json` / `concurrencia-diagnostico-44.json`.
Los secretos, fixtures y volcados permanecen fuera de Git y de la publicación.
Logs de los cuatro controles: `/private/tmp/gd-f4-{check-scripts,seed-preflight,rls-preflight,edge-preflight}-20260923.log`.
El primer intento de scripts no pudo abrir localhost dentro del sandbox; pasó
con el permiso de ejecución correspondiente. Seed requirió los valores ficticios
que define CI; la repetición con esa configuración pasó sin conexiones.

El código de aplicación sigue idéntico al verificado en `e0ab5216`: 4.158 tests
en 277 archivos y 234 E2E Docker PASS, 26 SKIPPED, cero fallos. No atribuir esas
pruebas a una nueva ejecución del 23/09. Las dos matrices remotas anteriores
(2.196/0 cada una), roles y carga acreditan los cuatro SQL; no acreditan aún el
quinto. Los dictámenes previos de Claude son CHANGES_REQUESTED, con resolución
documentada del PRIMARY; no se los presenta como PASS ni se pide otro por acuerdo.

## Autorización adicional y ejecución

Se solicita autorización **solo para este quinto SQL exacto**, primero en un
banco sintético de Supabase y después, únicamente con ensayo completo PASS, por
merge de rama a producción manteniendo los cortes OFF. La autorización previa
cubre los cuatro archivos originales, conciliación, organización
`fzxtxnkvslpcsscxqfbr`, banco hasta US$1 y `$release-crm`; sigue vigente.

La rama anterior está eliminada. Consumo horario estimado: US$0,048; presupuesto
restante estimado: US$0,952, sujeto al coste real y al tope total US$1. No es una
factura. La recreación será sintética y aislada, con coste cotizado y cierre al
terminar; se conserva la rama de la otra tarea.

1. Refrescar Main, catálogo, permisos, Edge Functions e historial productivos.
   Producción tiene 341 migraciones: desde la pausa aparecieron
   `20260922233545`, `20260923002033` y `20260923012825`, de la otra tarea.
   La conciliación administrativa de etapa 3 ya está hecha: no repetirla.
2. Recrear banco con datos sintéticos y destinos propios; instalar los cuatro
   SQL originales y este quinto únicamente después de su autorización.
3. Completar gates, matriz RLS, Auth/HTTP, concurrencia real y advisors. Conservar
   auditorías; adaptar los fixtures que suponían versión 1 a versiones vigentes.
4. Cotejar que el diferencial publicable contiene exactamente los cinco SQL de
   F4 y que no revierte avances ajenos. Merge SQL con cortes OFF y comprobación
   posterior en producción. No `apply_migration` directo a producción.
5. Integrar commits en Main, comprobar igualdad con `avancecorp/main`, construir
   y verificar el ZIP, publicar mediante `$release-crm` y comprobar bytes servidos.
6. Política futura por gerencia, con tasa baja NULL hasta F5; observar la primera
   jornada real antes de declarar F4 terminado. Eliminar el banco de pago propio.

Si un gate falla, no fusionar. Tras publicar, mantener o devolver avisos a OFF por
el control auditado si fuera necesario; conservar historia. No recuperar el bucle
reponiendo `40001` ni borrar políticas para simular un estado inicial.

Los dos avisos INFO originales de índices quedan para revisión posterior según
el [acta remota](F4-CIERRE-ENSAYO-REMOTO-2026-09-22.md); esta corrección no los cambia.
Retoma previa: [acta de pausa](F4-PAUSA-2026-09-22.md).
