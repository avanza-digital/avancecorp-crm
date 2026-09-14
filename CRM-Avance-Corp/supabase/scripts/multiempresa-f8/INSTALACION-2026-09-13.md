# F8 — paquete para instalar el piloto apagado

Estado: **preparado para aprobación del SQL; sin instalar ni activar**.
La preparación incluye las dos candidatas ya versionadas, sus pruebas locales,
una lectura actual de compatibilidad y el procedimiento de rama. La nueva
lectura no sustituye al ensayo remoto ni declara G7 cerrado.

## Qué se propone instalar

| Orden | SQL exacto | SHA-256 |
|---|---|---|
| 1 | [Control F8 apagado](../../migrations/20260913215240_crm_f8_piloto_controlado.sql) | `0807e59bcaccfbce8d7af02dc67fcfa8a64686305aaa976d4840af16c86c18fe` |
| 2 | [Exclusión de fuentes demo](../../migrations/20260914025926_crm_f8_excluir_fuentes_demo.sql) | `0f7daa10f1e1ac1d71501795d0f0d45c64e58fa263426c7e27a56f5c0e73dc08` |

La primera crea el control temporal y la lista privada de participantes, que
nace vacía. La segunda evita que las fuentes de prueba bloqueen la cobertura o
aparezcan en la operación multiempresa. Conserva los registros de prueba y todos
los movimientos reales. Las comisiones continúan fuera del CRM.

El permiso solicitado cubre ensayar estas dos versiones en una rama exclusiva,
y después instalarlas apagadas mediante el ciclo del proyecto si los controles
pasan. No cubre configurar personas, encender el piloto ni generar inversiones
reales. La autorización del lote anterior de diez enlaces ya fue ejecutada; ese
SQL no pertenece a este paquete y no se repite.

## Compatibilidad comprobada ahora

[Captura revisada sin PII](instalacion/base-produccion-revisada-2026-09-13.json)
obtenida el 13/09 a las 23:25 Lima. Combina [precondiciones](preflight-instalacion.sql)
y [paridad ampliada](paridad-instalacion.sql) en una misma transacción de solo
lectura, mediante `verificar-base-instalacion.mjs --consulta`. `proyecto` y
`procedencia` los añade el ejecutor a partir del `project_id` usado realmente en
MCP; no son una identidad atestiguada por PostgreSQL. Se conserva también la
[captura inicial](instalacion/preflight-produccion-2026-09-13.json) de las 23:08.

- Las 14 definiciones previas examinadas coinciden con las candidatas y sus
  propietarios son `postgres`. Coinciden también las 14 ACL esperadas. El NULL
  esperado del trigger demo significa su ACL por defecto preexistente; no se
  omite esa comprobación ni se cambia la autorización. La captura inicial solo
  exigía las cinco ACL del control: esta limitación se corrigió tras la revisión.
- F3 ON; F4/F5/F6/F7 OFF. Control, membresías y exclusión demo todavía ausentes.
- 598 fuentes: 593 reales sin brechas de identidad y cinco demo, cuatro con
  brechas. La protección de la marca demo existe y `es_demo` continúa NOT NULL.
- Historial actual: 279 migraciones, última `20260913213842`; MD5 del conjunto
  de versiones/nombres/arrays exactos: `2ba1ba0b80a0d553f4579833acb853ab`.
- 630 funciones/procedimientos en public/private/crm; huella agregada de
  definición, propietario, configuración, comentario y ACL efectiva:
  `2e36c8294d3de5927df16e6d6701a6bd`.

Estas huellas son una referencia del corte, no un permiso reutilizable de
instalación. Las cifras económicas pueden variar con ventas normales. Se exige
cero brechas reales al verificar el momento de instalación, sin congelar los
conteos ni alterar datos para hacerlos coincidir con una captura vieja.

## Cómo resolver la instalación de la rama

La rama F8 anterior se detuvo al reproducir una migración histórica que exige
datos de equipo. Su restauración sintética probó el control, pero omitió FK
externas y no reprodujo el historial completo: **no es base válida de merge**.
Esa rama ya fue eliminada.

Hay un precedente comprobado en [la instalación F5](../f5/INSTALACION-2026-09-09.md):
reconstruir en una rama exclusiva el esquema vigente del padre, cotejar su
estructura y permisos y solo después copiar allí su registro exacto. El
[informe de Leads del 13/09](../FILTRO-LEADS-VERIFICACION-2026-09-13.md) documenta
otro ciclo completado desde una base de 278 migraciones. La base actual tiene
279; no se reutilizan aquellos dumps, registros ni excepciones como aprobación.

Secuencia para el ensayo, después de aprobar el SQL:

1. Crear una rama F8 exclusiva, sin datos del padre, dentro del coste autorizado.
   Confirmar el coste vigente antes de crearla; si cambió, informar a Miguel.
   No reutilizar ni modificar las ramas de Citas o `banco-f7`.
2. Observar el replay y su error concreto. Si vuelve a fallar, obtener una copia
   **solo de estructura** de public/crm/private del padre y conservar el registro
   exacto de migraciones en `/private/tmp/avancecorp-f8-instalacion-<fecha>/`,
   directorio 0700 y archivos 0600, fuera de Git. Revisar que esos archivos no
   contengan secretos antes de adjuntar evidencia. No copiar clientes, cuentas
   Auth, depósitos ni documentos reales.
3. Registrar primero los objetos y filas de ledger que dejó el replay parcial.
   Preparar y revisar una limpieza limitada al ref de **esa rama desechable**;
   nunca ejecutar sobre el padre ni sobre otra rama. Inventariar dependencias
   externas antes de limpiar: no usar `DROP SCHEMA ... CASCADE` a ciegas ni
   eliminar schemas administrados. Si no se puede obtener un destino vacío
   verificable sin dañar objetos administrados, detener y replantear el ensayo.
   Exigir public/crm/private listos para restaurar y ledger con **cero filas**;
   no combinar objetos ni entradas de un replay parcial con la base nueva.
   Restaurar con `ON_ERROR_STOP`/`--exit-on-error`, sin ignorar errores.
   Mantener las FK hacia Auth y Storage:
   una estructura vacía puede tenerlas sin copiar filas. No sustituirlas por
   omisiones como en el ensayo F8 anterior. Desactivar jobs solo en esa rama.
   Conservar propietarios, grants, comentarios, RLS, triggers, constraints,
   índices, vistas, secuencias y configuración relevante.
4. Comparar la base reconstruida contra el padre **antes** de escribir su
   historial en la rama. Usar [paridad-instalacion.sql](paridad-instalacion.sql)
   mediante el envoltorio `verificar-base-instalacion.mjs --consulta-paridad`.
   Ejecutar `--paridad-rama <ref-exclusivo> padre.json rama.json`: exige los dos
   destinos correctos, 15 categorías idénticas y capturas en la misma ventana de
   60 segundos. Guarda ambos SHA del JSON como recibo. Si falla, obtener
   `--consulta-detalle` en ambos destinos y comparar categoría/clave/MD5 por
   objeto, junto a [estado-permisos.sql](../f5/estado-permisos.sql).
   Inspeccionar toda diferencia. **No hay excepciones de plataforma aceptadas
   por adelantado**: cualquier diferencia impide continuar hasta una revisión
   específica documentada con evidencia. No alterar la base esperada para pasar. El inventario F8 añade permisos por defecto
   globales y de schemas, estado de triggers (incluidos los de Auth), políticas
   PERMISSIVE/RESTRICTIVE, tipo exacto y precisión, dueños, enums/dominios,
   secuencias, extensiones/versiones, publicaciones y event triggers. La
   configuración gestionada fuera del catálogo requiere su inventario aparte.
   En esta etapa el ledger vacío ya debe estar **comprobado**, no supuesto.
   Los CHECK con diferencias de representación solo pueden aceptarse con
   equivalencia documentada de esta rama. No eliminar constraints para lograr
   coincidencia. Si no se demuestra paridad, detener la instalación.
5. Solo con la estructura equivalente, copiar en **esa rama** el conjunto exacto
   del historial del padre desde cero y comprobar versión, nombre y cada array `statements`,
   sin repararlos ni normalizarlos. No editar el ledger productivo, no alterar
   migraciones versionadas ni ejecutar un replay global sobre producción.
6. Ejecutar el seed ficticio en la rama y comprobar las precondiciones. Aplicar
   exclusivamente las dos candidatas, en orden, como migraciones separadas. Sus
   versiones remotas y arrays efectivos quedan documentados; comparar su SQL
   exacto con las huellas de este paquete. Un cambio de hash exige revisar de
   nuevo esa versión antes de instalarla.
7. Ejecutar las pruebas remotas específicas de control y demos, incluido el caso
   598/593/5/4, roles SQL y Auth/Data API. Verificar propietario, ACL/RLS, fuentes
   reales/demo, actor ajeno, revocación, carreras del control, reversa y
   reinstalación. Reversa y reinstalación se ensayan **en una base desechable
   separada de la rama que se fusionará**, sin alterar su historial aprobado.
   Ejecutar advisors antes/después y comparar los tipos expuestos F8.
8. Comprobar que el delta mergeable contiene únicamente esas dos migraciones y
   conserva todas las migraciones previas. Cotejar también **todas** las Edge del
   padre y la rama por archivos, JWT e import map, aunque F8 no cambie ninguna.
   El merge puede transportar Edge; un inventario nominal no basta. Registrar el
   modo de integración y el mecanismo real: se prevé `merge_branch` de MCP.
   Cotejar también el tercer lado si un flujo Git/CLI despliega desde el commit:
   `supabase/functions`, `_supabase_functions/functions` y `config.toml` efectivos,
   incluidos Auth/JWT. No suponer que el runtime representa ese árbol Git.

La recomendación genérica de reparar migraciones históricas en la documentación
de [Supabase](https://supabase.com/docs/guides/troubleshooting/branch-in-migrations-failed-status)
no reemplaza las reglas del repositorio. Aquí la alternativa propuesta conserva
el historial productivo. El [comportamiento de ramas](https://supabase.com/docs/guides/deployment/branching/troubleshooting)
también confirma que los datos de prueba no viajan en el merge.

## Publicación y comprobación posterior

Integrar los cambios actuales de `avancecorp/main` sin sobrescribirlos. Antes de
publicar, HEAD, Main local y Main remoto vivo deben coincidir. Construir únicamente
desde ese commit; registrar commit, hash del artefacto y de ambos SQL. Esta nota
no autoriza publicar el frontend desde `codex/f8-piloto`.

La **base del ensayo** es el JSON exacto del padre que obtuvo paridad con la
rama en el paso 4, identificado por `sha256_padre` en el recibo. Debe incluir la
captura combinada de precondiciones y catálogo; no basta una captura antigua
anterior a crear la rama. Guardar ese recibo junto a los resultados del ensayo.

Repetir obligatoriamente la consulta combinada de `verificar-base-instalacion.mjs`
en una ventana controlada, sobre el padre vivo, y ejecutar `comprobarBase` con
esa captura y la base del ensayo. Exige las 14 definiciones/ACL/propietarios,
F3 ON/F4–F7 OFF, cero instalación parcial, cero brechas reales, ninguna marca
NULL y paridad íntegra del catálogo/historial. El snapshot debe tener máximo
60 segundos al comprobarse; no se renuevan fechas de archivos viejos.
Completar primero el inventario Edge y Main remoto, y tomar la última captura
inmediatamente antes de `merge_branch`. Un cambio exige volver a comprobar los
objetos afectados. La comprobación de 60 segundos no elimina por sí sola las
carreras con un despliegue ajeno; se conserva la ventana coordinada y las
aserciones transaccionales de las candidatas. Si Main, esquema, permisos, historial
o alguna Edge cambió, detener, integrar y volver a verificar la parte afectada.
El verificador F8 devuelve `PASS_PRECONDICIONES_PADRE` con
`autoriza_merge: false`: comprueba el padre y la integridad de los dos SQL,
pero **no sustituye la paridad de la rama, Edge, artefacto, aprobaciones o pruebas
remotas ni ejecuta el merge**. La variante
F5 de `preflight-merge.mjs` fija las banderas de F5 y no debe usarse sin adaptar
su contrato para F8.

Fusionar solo la rama exclusiva validada. Comprobar después: historial anterior
conservado y delta correcto, funciones/ACL previstas, tablas con RLS cerradas,
control OFF, cero participantes, F3 ON/F4–F7 OFF, fuentes reales coherentes y
demo excluidas de los lectores operativos. Cotejar las huellas económicas y
Auth tomadas en la misma ventana; investigar las diferencias y distinguir
operaciones normales concurrentes de efectos de instalación. No restaurar una
captura para ocultar ventas nuevas.

Si la primera migración se instaló y la segunda falló, F8 debe seguir OFF y sin
miembros. Conservar el estado verificable, diagnosticar el fallo y revisar una
compensación o continuación explícita; no repetir a ciegas las dos versiones.
La [reversa demo](demos/reversa.sql) y la [reversa operativa F8](reversa-operativa.sql)
se conservan. Una reversa productiva requiere su nueva migración compensatoria
y el ciclo aprobado; nunca borrar fuentes ni forzar el ledger. Eliminar solo la
rama F8 al terminar y registrar el cierre del coste. Retirar los dumps temporales
conforme al cierre aprobado; conservar únicamente evidencia saneada y recibos.

Si avanza el historial del padre, detener y validar la secuencia remota resultante
(padre → control → exclusión). Las versiones asignadas por MCP pueden diferir del
nombre local y deben quedar registradas. No renombrar ni editar las migraciones
ya comprometidas ni reparar el ledger para forzar el orden. Si se necesita otra
migración o cambia el SQL, prepararlo y mostrarlo antes de volver a solicitar su
instalación.

## Resultado de esta preparación

| Comprobación | Estado |
|---|---|
| SQL exacto y hashes del paquete anterior | PASS, sin modificar las candidatas |
| Consulta combinada en producción | PASS, 14 definiciones/ACL coincidentes, 15 categorías de catálogo y cero brechas reales |
| Verificador de precondiciones del padre | PASS: 24 pruebas offline, acepta ventas nuevas y rechaza deriva/expiración |
| Mutaciones del catálogo en banco fijo con rollback | PASS: siete mutaciones y su contenedor (8 pruebas): permisos por defecto, triggers, políticas, precisión, dueño, enum y secuencia |
| 31 pruebas SQL locales de las candidatas | PASS previo, evidencia en [demos](demos/pruebas-sql.txt) |
| Reconstrucción equivalente de una nueva rama F8 | NOT RUN, pendiente del ciclo autorizado |
| Nuevas pruebas remotas / advisors / tipos | NOT RUN para el paquete combinado |
| Merge, instalación OFF y publicación | NOT RUN |
| Equipo, activación y casos reales G7 | PENDIENTES |

Comandos de preparación desde `CRM-Avance-Corp`:

```sh
npm run check:multiempresa:f8
npm run test:multiempresa:f8:instalacion
node supabase/scripts/multiempresa-f8/verificar-base-instalacion.mjs --consulta
node supabase/scripts/multiempresa-f8/verificar-base-instalacion.mjs --consulta-paridad
node supabase/scripts/multiempresa-f8/verificar-base-instalacion.mjs --consulta-detalle
node supabase/scripts/multiempresa-f8/verificar-base-instalacion.mjs --paridad-rama ref-de-la-rama padre.json rama.json
node supabase/scripts/multiempresa-f8/verificar-base-instalacion.mjs base-ensayo.json captura-viva.json
```

Los dos JSON del último comando son capturas del padre obtenidas por el ejecutor
con el mismo `project_id`: `proyecto` más la salida `precondiciones`/`paridad`.
La base revisada aquí todavía no es una base de ensayo remoto firmado.
El CLI solo acepta una captura actual posterior a la base, nunca el mismo
archivo. Las ACL de paridad conservan el array literal: si solo cambia su orden,
se investiga con `aclexplode` ordenado antes de documentar una equivalencia;
no se ignora la diferencia automáticamente. La prueba
offline fija un reloj histórico para ejercitar el verificador; nunca debe usarse
ese reloj en la instalación. El CLI usa el reloj real y rechaza el archivo viejo.

La revisión independiente del procedimiento y las decisiones del PRIMARY se
guardan en [instalacion/REVISION.md](instalacion/REVISION.md).

Después de instalar OFF: elegir Gerencia, supervisor y dos vendedores; preparar
su configuración exacta con vencimiento, solicitar encendido y ejecutar
[ACTA-G7.md](ACTA-G7.md). No trasladar una firma histórica de G6 al nuevo piloto.
