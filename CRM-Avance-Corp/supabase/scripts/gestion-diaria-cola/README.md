# Gestión diaria: cola de trabajo

Migración `20260930190028_crm_gestion_diaria_cola_trabajo.sql` aplicada por
merge de la rama validada el 30/09/2026. Evidencia remota y de publicación en
`docs/encargos/gestion-diaria-cola/RELEASE.md`.

## Comportamiento

La actividad tipificada confirmada determina el avance de la vuelta del día de
Lima, por autor, tenencia y ciclo. Los pendientes conservan la prioridad de
atención del núcleo SLA, también para el supervisor que llama a sus propios
leads. Los gestionados quedan al final por hora. Un compromiso posterior a la
llamada reabre el turno a su hora; una tarea anterior no se cierra por mover la
fila. Los descartados, inactivos, reasignados y con No contactar no se rescatan
como gestiones pendientes. Deshacer invalida el avance, sin borrar la llamada.

Los grupos de trabajo terminado conservan el motivo de entrada acreditado por
la primera gestión del día y sus hechos previos. Una conversación contestada no
se declara todavía «sin conversación» como estado actual. Las señales y el
reloj de conversación conservan su fuente anterior.

La RPC pagina después de ordenar la cola completa. Devuelve conteos, página,
ancla elegida, siguiente pendiente y próximo cambio. La selección puede seguir
una fila a otro grupo, pero una clave ajena nunca amplía el ámbito. Las tareas de
clientes siguen siendo filas distintas por tarea y exclusivamente del responsable.

El navegador guarda sólo navegación, con clave por actor y día confirmado por
el servidor. La llamada en curso conserva persona y tarea. Tras confirmar el
guardado inicia una consulta con una revisión nueva; ninguna respuesta previa
al guardado se reutiliza como actual. No oculta leads con marcas locales: otra
gestión o un deshacer desde la ficha se refleja al releer. El formulario mantiene el
reintento del mismo guardado ante una respuesta fallida. La vuelta completada
permite revisar filas manualmente sin iniciar otra vuelta automáticamente.

## Banco local y reproducción

`ensayar.mjs` sólo acepta el contenedor `avancecorp-gd-cola-20260930-pg167` y la
base `gestion_diaria_cola_20260930`, con comentario
`BANCO SINTETICO Gestion diaria cola 20260930 / sin produccion`. No recibe URLs,
credenciales ni destinos externos. No abrir puertos ni conectar a producción.

Se preparó un contenedor aislado (`--network none`, PGDATA en tmpfs) con la
imagen ya disponible `public.ecr.aws/supabase/postgres:17.6.1.167`, usando el
esquema y fixtures sintéticos del banco local `conversion_tipos_v3_20260927`.
La copia no contiene cartera productiva: seis leads base, diez perfiles de
prueba; las pruebas crean su volumen dentro de transacciones con rollback.
El dump de arranque de esta sesión está en
`/private/tmp/gestion-diaria-cola-sintetica.dump` (no versionado). Incluye las ACL
restauradas y la cola v3. Al reconstruirlo se necesitan los roles locales
`crm_metricas_bridge` y `crm_gestion_diaria_lector`; restaurar sin dueño y poner
el comentario del banco antes del ensayo. No usar un dump de clientes reales.

`preparar.mjs --solo-banco-local` documenta la reparación **inicial** de la
plantilla antigua sin privilegios. Sus snapshots `fixtures/acl*.json` son sólo
metadatos de catálogo obtenidos por lectura el 30/09/2026; no incluyen claves ni
usuarios. Sólo aplicarlo al bootstrap, antes de instalar la candidata: su
restauración de permisos no conoce las funciones nuevas. `ensayar.mjs` instala
la candidata dentro del banco y es el comando de regresión habitual:

```sh
node supabase/scripts/gestion-diaria-cola/ensayar.mjs
```

> Nota del 01/10/2026 (migración `20261001154153_crm_cartera_filtro_gestion`):
> a `fixtures/acl.json` se le AÑADIÓ a mano la firma de 13 argumentos de
> `crm.cartera_filtrada_fn` (con `p_gestion`), junto a la de 12 que ya traía. No
> viene de una lectura de producción: es para que `preparar.mjs`, que revoca todo
> y solo repone lo que el snapshot nombra, no deje esa función sin `EXECUTE` en
> una plantilla posterior a la migración (cada entrada se resuelve con
> `to_regprocedure`, así que sirve en los dos estados). Cuando la migración esté
> publicada, regenerar el snapshot desde producción y retirar la firma de 12.
>
> Nota del 01/10/2026 (migración `20261001212341_crm_cartera_filtro_potencial`):
> por el mismo motivo se AÑADIERON a mano la firma de 14 argumentos (con
> `p_potencial`) y su ayudante `private.cartera_potencial_fn()`. Sin ellas, una
> plantilla posterior a esa migración dejaría la cartera sin `EXECUTE` para
> `authenticated`. Al regenerar el snapshot desde producción, retirar las firmas
> de 12 y 13.

- `prueba.sql`: 530 leads, orden antes de paginar, llamadas repetidas, ancla,
  salto de página, reintento programado, límites de Lima, deshacer, exclusiones
  y fin de vuelta. Usa el escritor real v4 para llamadas y programación.
- `roles.sql`: altas con la RPC real, supervisor con cartera propia, llamada
  contestada, grupo conservado después de dos intentos y cierre de tarea,
  metadata histórica no UUID, ancla que cambia de grupo, reasignación autenticada por gerencia
  con triggers activos y compromiso exigible, tareas de clientes por responsable.
- `ensayar.mjs`: llamadas rechazadas en conexiones independientes como la API;
  rol, sesión, miembro inactivo, parámetros y ayudantes privados. Ejecuta los
  asserts previos de cola v3 y núcleo SLA. Es la matriz específica de esta RPC,
  complementaria a `test-rls.mjs`, cuyo preflight no prueba esta nueva puerta.

La cirugía de fixtures (datos antiguos, tareas históricas, estados terminales)
queda dentro del rollback; no se desactivan guardas en la migración. La imagen
local anterior `17.6.1.105` se reinició en una prueba de EXECUTE denegado; el
mismo banco en `17.6.1.167` pasa. Esto no es una instrucción de cambiar producción.

La muestra JSON de contrato del frontend se obtiene de SQL real en el ensayo.
Los tipos se generaron con postgres-meta v0.99.0 contra ese catálogo y se
incorporó únicamente la nueva RPC, conservando otros cambios del árbol.

## Verificación y publicación

El gate de frontend es `npm --prefix app run check`. Los E2E se ejecutan con
`npm --prefix app run test:e2e:docker` en Docker local. El spec nuevo es
`e2e/gestion-diaria-vuelta.spec.ts`: fallo/reintento, ancla entre páginas,
actualizar, salir/volver, recargar, resultado/hora y cierre de vuelta. Intercepta
el transporte, por lo que la autorización la acredita la matriz SQL aparte.
Incluye selección de otra fila con Enter bajo latencia y foco en el siguiente.

La evidencia y las decisiones del reviewer están en
`docs/encargos/gestion-diaria-cola/`. La publicación debe aplicar primero la
migración en rama Supabase vigente, comprobar matriz/advisors contra ese esquema
y luego publicar el frontend desde el commit verificado. Este ensayo local no
se presenta como aplicación o verificación remota.

Reversa: volver al frontend previo y retirar únicamente
`crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text)`,
`private.gestion_diaria_cola_filas(uuid,text,timestamptz)` y
`private.gestion_diaria_cola_hechos(uuid,timestamptz)`, en ese orden. No hay datos
que revertir; las actividades y tareas siguen en sus fuentes habituales.
