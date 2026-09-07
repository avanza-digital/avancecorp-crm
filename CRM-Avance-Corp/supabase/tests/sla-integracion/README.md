# Banco integral SLA: esquema real, sin datos de clientes

El banco restaura el esquema completo F7 (PostgreSQL remoto 17.6, dump 17.10) en PostgreSQL 17.10 nativo. Todo el esquema CRM, sus autoridades, vetos, writers, triggers, RLS, owners y membresías son reales. Se siembran únicamente siete actores y una política histórica sintéticos. Las altas de prueba usan `crm.crear_lead_si_disponible` y los cierres usan las RPC reales.

No acepta URL de conexión ni host de red. PostgreSQL escucha sólo en un socket privado de `/private/tmp/sla-integracion-*`, puerto lógico 55485, sin TCP. El export remoto es sólo lectura, separado del runner. `schema.sql`, `metadata.json` y `gobernanza.json` se conservan fuera del repositorio; no contienen filas de la cartera. La metadata de cron no ejecuta tareas: se adapta únicamente `database` al nombre de cada clon, manteniendo horario/comando/estado. Las piezas administradas no disponibles y las dos funciones superpuestas desde producción se enumeran en `manifest.json`.

## Reproducción

Desde la raíz del worktree, con PostgreSQL 17 instalado:

```sh
python3 CRM-Avance-Corp/supabase/scripts/test-sla-integracion-local.py \
  --schema /private/tmp/sla-esquema-integral/schema.sql \
  --metadata /private/tmp/sla-esquema-integral/metadata.json \
  --governance /private/tmp/sla-esquema-integral/gobernanza.json \
  --prepare-sla --test-prerequisite --all-sla --keep
```

El comando emite el socket. Después:

```sh
python3 CRM-Avance-Corp/supabase/scripts/test-sla-comandos-local.py \
  --socket /private/tmp/sla-integracion-SOCKET_EMITIDO \
  --template sla_integracion --output /private/tmp/sla-n3-resultados.json
```

Para la suite N2, crear el banco con `--prepare-sla --keep` sin `--all-sla`; el runner N2 instala sus fuentes en un clon propio. La suite N1 reducida sigue siendo útil para los oráculos puros y el recorrido de 211 elementos; este banco añade integración con el esquema completo.

## Prerrequisito de gobernanza

Los cuatro gates estaban rojos antes de SLA tanto en F7 como en producción. El prerrequisito se genera con Supabase CLI y se aplica explícitamente **antes de N1**:

- `crear_contrato`: se retira exclusivamente una variable muerta que invocaba `es_analista`; la autoridad sigue siendo `private.puede_registrar_ventas`. Sale su exención obsoleta; techo6 intacto, censo5.
- Cuatro contadores de identidad: documentos e impacto se sirven por proveedores privados del núcleo de identidad; las preguntas, filtros y autoridad permanecen iguales. El bloqueo obtiene su cardinalidad con `ROW_COUNT`; los umbrales mayor que1 usan `EXISTS ... OFFSET 1`. Censo34→30, techo30 intacto, sin nuevas exenciones.
- Las cuatro tablas de rentabilidad amplían sus auditores existentes a INSERT/UPDATE/DELETE, manteniendo todos los guards de inmutabilidad. No se añaden exenciones de auditoría.
- F7 recertifica el cuerpo exacto de integración de identidad ya presente; conserva estado cerrado permanente, ventana, fecha, ACL y único caller.
- Se recertifican seis exenciones analíticas ya existentes: cuatro operaciones de reparto afectadas por identidad/veto y dos lectores/selladores de conversión que siguen consumiendo el núcleo. Sus cuerpos no se reescriben. El sello se actualiza dentro de la migración.

`fuentes-gobernanza-previas.json` y `fuentes-analitica-previas.json` guardan las definiciones, hashes y declaraciones revisadas de producción. La migración aborta si esas fuentes cambian. F7 difería de producción sólo en dos de esos cuerpos (`cerrar_periodo` y `conversion_mensual_sin_cartera_fn`); el runner superpone las fuentes exactas de producción localmente y registra ambos hashes. No se modificó ningún banco remoto.

El rollback restaura las cinco fuentes intervenidas y las declaraciones originales. Devuelve también los cuatro fallos preexistentes; se ejecuta después de la contingencia SLA. La prueba automatizada verifica fuente exacta tras rollback/reaplicación, los cuatro rojos originales, retorno a verde, privacidad de proveedores y equivalencia de bloqueo con NULL/vacío/duplicados/ID inexistente. Los timeouts son 5s de lock y30s de sentencia.

## N3: hallazgos corregidos y controles

El banco encontró un fallo real que la compilación no detecta: el trigger diferido de confirmación era INVOKER y, al COMMIT fuera de la RPC DEFINER, perdía acceso a los recibos privados. Se cambió ese trigger a DEFINER con owner postgres y search_path vacío. No se concedió acceso de tabla a usuarios.

Los cierres v1 guardan el lead efectivamente bloqueado. Si una tarea entra en ámbito entre las dos lecturas y no se tomó ese lock, abortan con P0409 antes de adquirir un lock de lead después del de tarea. El camino de postventa sin lead se conserva. El gate privado `assert_sla_comandos()` vigila ACL/RLS, FKs diferidas, confirmación al COMMIT, candados y hashes de esos tres writers.

La suite N3 cubre 21 casos: respuesta persistida e idéntica en retry; payload conflictivo; pérdida de ámbito; permisos; actividad+siguiente atómica y rollback sin residuos; reserva sin respuesta; recibo inmutable; carreras iguales/distintas sobre un lead; los cinco comandos v2; v1 directo y concurrente; restauración de GUC; dos gestos en modo activo (siguiente reunión0 prórrogas, siguiente llamada1); y sabotajes de gate que deben fallar.

Una fecha de actividad futura enviada por cliente se acepta y se **reemplaza** por el reloj servidor en el trigger real después del lock. La prueba verifica el valor persistido; no se alteró ese contrato.

La carrera específica de adquisición de ámbito entre los dos SELECT v1 se corrigió por el invariante explícito del lock y se selló por hash. La prueba concurrente v1+v2 cubre el orden normal; no se afirma haber forzado de forma determinista esa intercalación exacta sin instrumentar los writers.

La integración no reproduce workers Supabase, scheduler, PostgREST o Auth HTTP. Esas comprobaciones corresponden al smoke de publicación. El dump no demuestra paridad global de F7/producción: los guards exactos protegen las funciones pertinentes revisadas.

## Foto privada y reconstrucción del stock antes del cierre R4

`scripts/sla-stock/01-foto-pendientes.sql` captura sólo IDs/ciclo de tareas pendientes de leads abiertos sin contexto. Guardar el objeto `foto` íntegro en archivo privado. `preparar-stock-sla.py --foto FOTO --salida /private/tmp/CARPETA_NUEVA` conserva sus bytes y SHA, genera lotes de hasta200 leads y una consulta final contra esa misma foto. El preparador no conecta ni ejecuta SQL.

Cada lote de `02-reconstruir-lote.template.sql` abre su transacción y fija los timeouts **antes** de ejecutar el writer: `SET LOCAL lock_timeout='5s'` y `SET LOCAL statement_timeout='30s'`. Se ejecuta bajo legado después de N2 y antes de R4. La salida es agregada por motivo. La verificación separa tareas originales reconstruidas, tareas que salieron del stock/cambiaron de ciclo, faltantes originales, nuevos faltantes y contextos incoherentes; nunca reemplaza la foto original por la actual.

Pipeline ensayado con alta y tarea auténticas de fixture anteriores a N2:1 original→1 reconstruida; retry→1 existente; faltantes0, incoherencias0, nuevos faltantes0. El comando de cierre R4 se aplica después de completar y revisar esa comparación. La foto real permanece fuera del repositorio y los informes públicos usan sólo agregados.
