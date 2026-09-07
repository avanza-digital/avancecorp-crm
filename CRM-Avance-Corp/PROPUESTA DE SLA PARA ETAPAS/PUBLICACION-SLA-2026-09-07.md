# Publicación del núcleo SLA y cola paginada

Autorización de Miguel: «haz los filtros de paginación, evitemos scrolls infinitos, y ya saquemos esto a producción» (06/09/2026, Lima). Las reglas aprobadas se conservan. No se exige un día de observación antes de activar.

## Estado de publicación

**Backend activo, publicación frontend en verificación.** En producción se aplicaron los cinco SQL, se reconstruyeron 831 contextos en cuatro lotes y se cerraron los helpers transitorios con N4. La comparación contra la foto original terminó con 0 pendientes sin contexto, 0 contextos incoherentes y 0 nuevos faltantes. El gate completo de gobernanza y N1/N2/N3 está OK. [Evidencia de producción sin PII: control, gate, cuatro lotes, comparación del stock y ledger canónico](../supabase/tests/sla-integracion/produccion-activacion-20260907.json).

Política operativa **v6**, control **activo / revisión 1**, primera activación **2026-09-07T04:03:49.941009Z**. La adopción corresponde a v6. La activación y los efectos registrados se conservan durante la verificación del frontend.

El primer artefacto de interfaz ya está publicado en `crm.miavance.com`:

| Campo | Valor confirmado |
|---|---|
| Commit fuente | `839aa7c8c01cecba3102fb3222408784a1e4b972` |
| Build | `build-20260907T035742935Z` |
| Release | `crm-20260907T035743Z-839aa7c8c01c` |

Hay un hotfix del frontend en curso antes del cierre de la entrega. Su commit, build, artefacto y verificación final aún no se registran: los identificadores anteriores describen únicamente el primer release publicado.

## Comportamiento entregable

- Cola de trabajo con 10 registros iniciales; tamaños 10/25/50, Anterior y Siguiente. Filtros por señal, etapa y analista dentro del ámbito autorizado. Los totales abarcan la población completa; las señales se pueden solapar.
- Estado SLA en la ficha; configuración y modo servidos por el mismo núcleo del servidor.
- Actividad, cierre y reprogramación con recibos transaccionales. Un reintento conserva la operación original. El formulario espera la confirmación antes de anunciar éxito. Contacto y siguiente tarea se guardan juntos.
- Los plazos de episodios existentes se conservan. La primera activación fija el inicio del seguimiento y la política de adopción para sus topes. No hay prórrogas retrospectivas ni descarte o reasignación automáticos.

## Orden de instalación

1. Terminar las pruebas e integrar la implementación en Main, incorporando cambios remotos sin sobrescribirlos. Verificar que Main y `avancecorp/main` apuntan al mismo commit y construir desde ese commit en un checkout limpio. Preservar cambios locales ajenos a SLA; no crear ramas de release ni forzar el push. Verificar el ZIP, su manifiesto, proyecto Supabase y ascendencia respecto al release vivo; conservar el ZIP anterior. **El artefacto verificable debe existir antes de modificar la base.**
2. Releer las huellas del esquema vigente. Aplicar el prerrequisito `20260907032338_crm_sla_prerrequisito_gobernanza.sql` y comprobar los cuatro controles de gobernanza. Reparar solo las causas demostradas; no omitir controles ni elevar topes.
3. Aplicar N1 `20260907001024_crm_sla_nucleo_operativo_lectura.sql`, N2 `20260907024903_crm_sla_nucleo_operativo_escritura.sql` y N3 `20260907025220_crm_sla_comandos_recibos.sql`, en ese orden. Leer cada postflight antes de continuar. El modo sigue en `legado`, revisión 0, primera activación y adopción null; estas migraciones no publican reglas ni activan. La interfaz previa continúa operativa.
4. Reconstruir únicamente contextos demostrables de tareas pendientes mediante `private.sla_reconstruir_contextos_lote`, con hasta 200 leads y commit independiente por lote. Establecer `lock_timeout=5s` y `statement_timeout=30s` fuera de la función. Guardar cobertura y motivos ambiguos fuera del repositorio, compararlos con el contraste y revisar cambios reales de cartera. No inventar episodios, autores ni fechas ni cancelar tareas. Un timeout revierte ese lote y exige revisar la causa.
5. Aplicar N4, `20260907031450_crm_sla_cierre_reconstruccion_contextos.sql`, solo después de guardar y revisar los lotes. Retira los helpers transitorios, conserva contextos/captura y comprueba el núcleo.
6. Desplegar el artefacto ya construido exclusivamente en `crm.miavance.com`. Verificar manifiesto, commit y archivos servidos; comprobar las pantallas con las RPC instaladas y el modo todavía en legado. Agenda conserva su consulta actual; la paginación nueva corresponde a la cola operativa y a las confirmaciones pendientes.
7. Desde una sesión real de **Gerencia**, revisar el resumen servido en Configuración y ejecutar `crm.publicar_reglas_sla_aprobadas_v2` con `expected_version` recién leído. No suplantar `auth.uid()` en SQL. La puerta exige última política vigente sin anexo, publica las cuatro reglas de forma atómica y preserva la primera gestión/contacto vigentes. Releer el resultado. No cambia el modo.
8. Activar desde esa sesión con la revisión vigente del control. Releer política, primera activación y adopción; comprobar las pantallas, la cola y los controles de integridad. Registrar los resultados exactos de instalación, artefacto y activación.

El orden de esta entrega es explícito, no el orden lexicográfico de los archivos: **prerrequisito → N1 → N2 → N3 → lotes → N4 → frontend → publicación de reglas → activación**. No aplicar todas las migraciones ciegamente en una sola pasada.

La foto del contraste tenía política v5 con bases 1/8/15/20 días, primera gestión de 120 minutos y primer contacto de 1440. La publicación creó v6 y la activación dejó el control en revisión 1 con adopción de v6. Son resultados releídos después de las operaciones, no valores forzados. El orden anterior se conserva como protocolo; instalación, reconstrucción, cierre y activación ya están completados.

## Reglas comerciales aprobadas

| Etapa | Seguimiento | Base / tope | Prórroga por conversación | Margen de compromiso |
|---|---:|---:|---:|---:|
| Nuevo | 1 día | 1 / 3 días | Ninguna | 4 horas |
| Contactado | 3 días | 8 / 16 días | 4 días, máximo 2 | 1 día |
| Reunión agendada | 3 días | 15 / 18 días | Ninguna | 2 días |
| Propuesta enviada | 5 días | 20 / 27 días | 7 días, máximo 1 | 1 día |

Reloj corrido. La conversación debe ocurrir en las últimas 24 horas del plazo aplicable y conservar el mismo episodio antes y después del gesto completo. Una tarea pendiente puede cubrir el seguimiento, limitada por su fecha más el margen y por el tope de etapa. Tres reprogramaciones eliminan esa cobertura. Tercer ingreso en la misma etapa/ciclo o vencimiento operativo requieren revisión.

## Estado de validación

La instalación y activación del backend ya están acreditadas por la ejecución y lectura posteriores registradas por el coordinador de la publicación. El primer frontend está publicado; el cierre del hotfix y su smoke final permanecen pendientes. Las pruebas locales siguientes son evidencia complementaria y no sustituyen esas verificaciones del servicio.

N2: 23/23 pruebas en banco integral PG17 con funciones, permisos y controles reales; 7,145 s de casos, 8,014 s incluyendo preparación. Incluye concurrencia de publicación y gestión, apagado, reconstrucción idempotente, falta de evidencia, cierre y contingencia. Detalles y alcance en [runbook N2](../supabase/tests/sla-operacion/README.md). Las pruebas de N1, N3 y prerrequisito se registran en sus artefactos de evidencia y en [MIGRACIONES.md](../supabase/migrations/MIGRACIONES.md); una prueba local no acredita uso en producción.

Validación final previa a integrar: N1 47/47, N3 21/21 en instalación fresca (6,296 s), prerrequisito con reversa/reaplicación exactas y cuatro controles verdes sin elevar topes. Frontend: 2895 pruebas en 201 archivos (15,51 s), typecheck correcto y lint sin errores, con cuatro advertencias preexistentes. [Evidencia integral y SHA-256 de los cinco SQL](../supabase/tests/sla-integracion/evidencia-20260907.json). El banco no ejecuta PostgREST, Auth HTTP ni scheduler: el smoke posterior debe comprobar el servicio real. La carrera específica de adquisición de ámbito v1 se cierra con el invariante de bloqueo y huella; no se afirma haber forzado determinísticamente esa intercalación. `npm run gate:sla:produccion` verifica los siete controles y el cierre de los helpers de reconstrucción.

Validación local final del hotfix en curso: **2918/2918 pruebas en 201 archivos, 17,21 s**; typecheck correcto; lint sin errores y cuatro advertencias preexistentes de coverflow. Store 62/62, incluidas 14 regresiones nuevas; API 45/45. La recomprobación E2E de siete casos y la identificación/lectura del artefacto final publicado quedan pendientes de confirmación. Estos resultados no cambian los identificadores del primer release.

El contraste previo está en [CONTRASTE-CARTERA-2026-09-06.md](CONTRASTE-CARTERA-2026-09-06.md). El contrato técnico está en [CONTRATO-V2.md](auditoria-r2/CONTRATO-V2.md).

## Registro de migraciones y avisos del servicio

MCP aplicó los SQL con versiones operativas distintas a sus filenames. Se reconciliaron únicamente las cinco columnas `version` del ledger con las versiones canónicas del commit, sin ejecutar nuevamente los SQL ni cambiar `name`, `statements`, `created_by`, `idempotency_key` o `rollback`:

| Pieza | Versión operativa aplicada | Versión canónica registrada |
|---|---|---|
| Prerrequisito | `20260907035818` | `20260907032338` |
| N1 | `20260907035837` | `20260907001024` |
| N2 | `20260907035851` | `20260907024903` |
| N3 | `20260907035906` | `20260907025220` |
| N4 | `20260907040053` | `20260907031450` |

La reconciliación terminó correctamente con [reconciliar-ledger-sla.sql](../supabase/scripts/reconciliar-ledger-sla.sql), SHA-256 `72421c3d80be8fd7584678de15a8c3345ecb097d4eef40ca3b2c5303c4ff06f2`. Sus controles exigieron cinco nombres únicos, una sentencia por fila, SHA-256 idéntico al SQL comprometido y destinos libres; verificaron después que los demás campos permanecían intactos. El [mapping y ensayo local](../supabase/tests/sla-integracion/reconciliacion-ledger-20260907.json) conserva las versiones operativas originales. Esta reparación evita que la CLI interprete estos cinco artefactos como pendientes; la reproducción desde cero sigue requiriendo el orden explícito del prerrequisito.

Los nuevos avisos asociados al diseño SLA se interpretan con su ámbito concreto:

- **RLS activada sin policies en tablas privadas:** el acceso directo queda cerrado de forma intencional. Los consumidores usan las RPC autorizadas; no se debe crear una policy abierta para silenciar el aviso.
- **Funciones SECURITY DEFINER accesibles a authenticated:** son puertas explícitas con `search_path` fijo, ACL controlada y comprobación de rol/ámbito en el núcleo. Los gates certifican ese contrato; el aviso por el patrón no autoriza ampliar grants.
- **FK del control sin índice adicional:** nace en la tabla singleton del control, de una sola fila. No introduce un problema de escala en ese diseño; no corresponde añadir un índice por reflejo.
- **Índices nuevos aún sin uso registrado:** la ausencia inicial de estadísticas no demuestra que sobren. Se conservan los índices del núcleo y se revisan con uso representativo; no se eliminan durante esta publicación.

Estas decisiones son específicas de esos avisos. Una nueva policy, grant, cambio de owner o crecimiento fuera del singleton requiere otra revisión.

## Recuperación

Si la interfaz presenta una regresión, volver al ZIP anterior conservado. Para suspender las señales operativas, usar la puerta de configuración para volver a `legado` con la revisión vigente; esta acción conserva la primera activación, las políticas y los recibos. No borrar el historial, reescribir plazos ni retirar los comandos mientras el frontend publicado los utilice.

Si falla un hook estructural y el modo no basta, la contingencia ensayada [rollback-sla-operacion-hooks.sql](../supabase/scripts/rollback-sla-operacion-hooks.sql) exige legado y retira solo captura/adjudicación, conservando avance automático, autorización, clocks, locks fuertes y las firmas que invocan N3/v1. El gate bloquea reactivar mientras falten esos hooks. Registrar el intervalo sin captura: la recuperación requiere una migración revisada y reconstrucción/verificación de ese intervalo. Los presupuestos consumidos y la primera activación permanecen. La reversa del prerrequisito es distinta: restaura las definiciones previas y sus cuatro controles rojos conocidos; se reserva para una reversa completa revisada, no para apagar SLA.

Una respuesta de red perdida se recupera desde la lista de confirmaciones pendientes: reenvía la misma operación y payload. No crear otro UUID para conseguir un segundo efecto. La memoria del navegador es por actor y pestaña; cerrar sesión o perder ese almacenamiento requiere revisar el historial antes de volver a registrar.
