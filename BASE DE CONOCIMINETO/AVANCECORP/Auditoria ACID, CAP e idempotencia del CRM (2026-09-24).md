# Auditoría ACID, CAP e idempotencia del CRM (24/09/2026)

Miguel preguntó si la base cumple ACID, cómo está frente al teorema CAP y la
idempotencia, y pidió investigar con agentes qué más hacer. Todo se midió en
producción (solo lecturas) y en el código de `avancecorp/main` (`929fbbcc`).

## Veredicto

- **ACID: sí en la base, con dos huecos en pantallas.** Postgres 17 en un solo
  nodo; `fsync`, `synchronous_commit`, `full_page_writes`, `data_checksums` y
  `archive_mode` encendidos. 740 funciones, ninguna con `COMMIT` ni `dblink`:
  cada llamada es todo-o-nada. `crm`: 84 tablas, todas con PK y RLS, 209 FK,
  394 `check`, 0 restricciones sin validar. Aislamiento `read committed` con 115
  funciones que usan `FOR UPDATE` y 81 con candados por clave.
  - La **D** se probó sola: el 19/09 a las 16:12 UTC el servidor se reinició sin
    apagarse bien y la recuperación terminó en 0,12 s sin perder datos. Queda
    sin explicar **por qué** se cayó.
  - Los huecos son de **pantalla**: el descarte del analista (update del lead
    + nota, dos llamadas, `lib/store.tsx:2717`) y la corrección de datos del
    cliente (tres escrituras, `components/app/cliente-form.tsx:310-355`).
- **CAP: el sistema es CP.** Sin conexión, las escrituras fallan en el acto (no
  hay reintento automático ni cola sin conexión: `retry:false` en
  `lib/query-client.ts`). Las lecturas son eventuales, hasta ~30 s (no hay
  Realtime). El puente de landing es AP (marca de agua + reintento, no pierde
  nada). Los correos de Resend no tienen cola: si Resend cae, se pierden.
- **Idempotencia: buena.** De unas 95 escrituras del front, 53 llevan clave o
  versión, 39 son idempotentes por naturaleza y 3 duplican algo menor (notas,
  reconocimientos). Las 40 RPC que insertan sin clave se protegen por estado,
  versión esperada, `unique` o hash. Los cron aguantan correr dos veces.

## 🔑 Lo no obvio

- `crm.descartar_lead` **solo sirve a Coordinación y Gerencia sobre la cola
  global**, no al vendedor con su lead. El descarte del analista NO tiene RPC
  atómica. La plantilla para hacerla es `registrar_llamada_v4`, que ya descarta
  un lead propio con su actividad y un recibo idempotente.
- `crm-convertir-lead` ya no tiene uso en producción (último llamado 19/09); las
  conversiones van por `crm-inversion-portal` + `crm-inversion-bienvenida`.
- El cron `crm-cierre-mes-diario` está **en pausa a propósito** (agosto
  reabierto, ver [[Cierre de mes]]). Si no se reactiva, setiembre no se sella el
  01/10.

## Hecho

- **PR #92** — el botón «Agendar» (`contacto.tsx`) creaba dos tareas con un doble
  clic. Guarda + botón deshabilitado; dos tests verificados con mutante. Unitarias
  4283/4283, typecheck, lint, e2e en Docker 22/22. Codex: PASS.

## Recomendaciones (por prioridad)

**P1**
1. **Tiempo agotado en el SLA:** `avisos_sla_resumen_v2_fn` lleva 14 201 llamadas,
   media 719 ms, máximo 7 996 ms (el tope es 8 s) y 39 GB escritos a disco temporal.
   Hay unos 60 tiempos agotados al día. Causa: `private.sla_operacion_leads` consulta
   el veto de persona lead por lead dentro de un bucle. Es la principal sospecha de
   la presión de memoria.
2. **`public.audit_log` se puede reescribir:** anon y authenticated tienen
   UPDATE/DELETE (solo los frena que no haya policy), `service_role` tiene
   UPDATE/DELETE/TRUNCATE y no hay trigger. Arreglo: revocar esos permisos y
   añadir un trigger de solo-añadir como el de las tablas de `crm`.
3. **Reinicio sucio del 19/09:** revisar las métricas del panel o abrir ticket, y
   correr `ANALYZE` (se perdieron las estadísticas: `perfiles` figura con 20 filas
   y tiene 539).
4. **Cierre de mes antes del 01/10:** Miguel decide C1/C2 de agosto, se vuelve a
   sellar y se reactiva el cron.

**P2**
5. RPC de descarte atómico para el analista; también arregla la cadena
   «cerrar tarea + descartar por No responde» (`cerrar-tarea.tsx:365-391`).
6. Evitar que un cambio pise a otro en leads y tareas: comparar cada campo antes de
   escribirlo. Se puede hacer solo en pantalla, sin migración. Después, `editar_lead_fn_v2`.
   En 30 días hubo 22 cambios al mismo lead por otra persona en menos de 2 minutos.
7. Corrección del cliente en una sola RPC (documento + datos) y el correo al
   final con «Reintentar». Cierra además el atajo del analista: su policy permite
   cualquier columna y la regla del domicilio legal solo vive en la pantalla.
8. La rama `banco-f7` está viva desde el 01/09 (`MIGRATIONS_FAILED`) y llama a
   producción a la hora del cron (recibe 401). Borrarla o apagar su cron, mover
   las 2 URL fijas a vault y guardar el resultado de los cron HTTP (pg_net lo
   borra a las 6 h).
9. `idle_in_transaction_session_timeout` y `lock_timeout` para `postgres` y
   `service_role`, que hoy heredan 0: una sesión abierta puede retener candados
   sin límite.
10. Encender la protección contra contraseñas filtradas en Auth (panel).

**P3**
11. Correos: retirar `crm-convertir-lead` (cerrar → observar → derribar), barrer
    con cron las bienvenidas en `pendiente`, y crear un outbox general solo si
    `crear-cliente` vuelve a usarse. Para recuperar correos perdidos, comparar
    primero con el registro de envíos de Resend.
12. Duplicados menores: el reconocimiento de alertas (trigger nuevo, sin tocar el
    sellado que fija un md5) y `corregir_cierre_externo` sin cambios. En
    producción hoy no hay ningún duplicado.
13. Limpieza:
    - 9 PDF de contratos eliminados (datos personales: decidir si se guardan).
    - 3 trabajos de PDF muertos.
    - 1 reserva de conversión «descartado» con efectos iniciados.
    - `respaldo_cierre_agosto_2026` sin RLS.
    - 53 FK sin índice.
    - `audit_log` ocupa el 57 % de la base y no tiene retención.
    - `cron.job_run_details` nunca se purga.
14. Reglas que viven solo en pantalla:
    - modalidad de la reunión;
    - resultado comercial al cerrarla;
    - motivo de cancelación;
    - confirmación de cita con el reloj del navegador;
    - ventana legal de contacto L–S 07–20, que solo valida el camino v4.

Todo lo que toque tablas, RLS o la `api` va con plan corto y OK de Miguel,
banco Docker con el gate RLS antes y después, y review de Codex. Relacionado:
[[PLAN MAESTRO del servidor (P-055) - de la deuda a la capa semantica]] ·
[[Analisis de propuesta SLA por etapas - 2026-09-06]] · [[Inicio]].

## ✅ P1 #1 y #2 EN PRODUCCIÓN (25/09/2026, ~02:00–02:08 UTC)

Los aplicó Miguel con `!` tras ensayarlos en prod (deshechos), en un banco Docker propio a
paridad y con dos revisiones. Cambios en la PR #96 (`fde86d24`).

- **#1 SLA:** el veto de contacto se consulta en lote. La función de la cartera global pasó
  de 6,6 s a **1,1 s**, con 0 filas distintas frente a la versión anterior. Las RPC reales como
  gerencia, antes → después:

  | RPC | Antes | Después |
  |---|---|---|
  | avisos del SLA | 4,7 s | **1,6 s** |
  | cola de acción | 5,1 s | **2,0 s** |
  | equipo de Gestión Diaria | 4,7 s | **1,6 s** |

  Ya no rozan el tope de 8 s.
- **#2 bitácora:** `public.audit_log` es de solo añadir. Las API no pueden editarla, borrarla
  ni vaciarla, y un trigger lo impide también al dueño. Borrar un usuario sigue funcionando:
  anonimiza su rastro (probado también por la API de Auth). Cuesta ~9 µs por fila de su historial.
- **Qué aportaron las revisiones:** el auditor RLS pidió exigir que el perfil ya esté borrado y
  comparar la fila entera. Codex cazó que comparar solo en jsonb confunde un NULL de SQL con un
  `'null'::jsonb`: ahora se compara también con tipos.
- **Pendientes:**
  - Registrar las dos versiones en `supabase_migrations`: el clasificador me bloqueó preparar el
    script; lo decide Miguel.
  - Fusionar la #96.
  - Seguir con P1 #3 (reinicio del 19/09 + `ANALYZE`) y #4 (cierre de mes antes del 01/10).
- 🔑 Los tiempos agotados del SLA venían de UNA función llamada 2302 veces por consulta, no de
  la carga. Medir por piezas (`explain analyze` de cada llamada interna) lo encontró en minutos.
