# Banco local F4

Estado al 07/09/2026, 22:09 Lima, recuperación PDF ampliada: candidata instalada y pruebas parciales satisfactorias
en el banco local. **G4 sigue abierto.** Consulta `ESTADO-ACEPTACION.md` antes de
retomar: enumera la evidencia y los requisitos aún sin demostrar.

Estos scripts solo aceptan el proyecto local `avancecorp-f4-bank`, API
`http://127.0.0.1:56321`, base Docker en el puerto `56322` y claves cuyo emisor
es `supabase-demo`. No aceptan una URL remota ni leen claves del CRM productivo.

## Banco preparado el 07/09/2026

- Carpeta temporal: `/private/tmp/avancecorp-f4-bank`.
- CLI temporal Supabase 2.117.0: `/private/tmp/avancecorp-f4-tools/node_modules/.bin/supabase`.
- Postgres 17.6; Auth, API y Storage locales activos.
- `schema-prod.sql`: volcado de **solo esquema**, obtenido por lectura del proyecto
  `dctqcbznekcyxhjujuci`. No se copiaron datos reales.
- `functions-prod.json`: inventario de 516 definiciones del volcado.
- `start.log`: configuración y claves LOCALES. No publicar ni copiar su contenido.
- `auth-fixtures.json` y `fixtures.json`: usuarios y contraseña ficticios;
  archivos temporales privados, no se versionan.

El volcado conserva las extensiones y los propietarios. La restauración local
necesitó crear `crm_metricas_bridge` como NOLOGIN/NOINHERIT y usar el administrador
local `supabase_admin` para asignar propietarios; los objetos de aplicación
mantienen sus propietarios y grants productivos. PostgREST se recargó después
de restaurar el esquema y exponer `crm`.

No se desactivaron triggers ni RLS para preparar los perfiles, los equipos o la
identidad. Las cuentas ficticias se crearon mediante la API de Auth y su acceso
se comprobó con inicio de sesión real.

## Comprobaciones

Desde la raíz del repositorio, con Docker y este banco en ejecución:

```sh
node CRM-Avance-Corp/supabase/scripts/f4/preparar-fixtures.mjs
node CRM-Avance-Corp/supabase/scripts/f4/capturar-base.mjs
```

El primer script exige una base sin perfiles para su carga inicial; una
reejecución verifica y reutiliza su semilla, sin borrar filas ni repetir Auth.
El segundo compara 29 funciones con la captura de producción y genera
`../evidencia-f4/2026-09-07-banco-local.json`. Solo sirve antes de modificar el
motor o crear inversiones de prueba; sus aserciones lo impiden después.

La comparación inicial del banco vacío ya no se puede ejecutar sobre el banco
con inversiones: debe fallar para no sustituir la referencia. La preparación
económica también exige que F4 todavía no esté instalada.

## Construcción y pruebas realizadas

`generar-migracion.mjs` ensambla seis módulos SQL y adaptaciones de 17
funciones originales, ancladas por huella. El archivo de migración fue creado
por el CLI. Hay 17 funciones nuevas; ninguna bandera se enciende al instalar.

Secuencia para una base recién preparada:

```sh
node CRM-Avance-Corp/supabase/scripts/f4/preparar-operaciones-base.mjs
node CRM-Avance-Corp/supabase/scripts/f4/capturar-paridad.mjs antes
node CRM-Avance-Corp/supabase/scripts/f4/generar-migracion.mjs CRM-Avance-Corp/supabase/migrations/20260907191832_crm_f4_inversiones_base_y_escritores.sql
node CRM-Avance-Corp/supabase/scripts/f4/aplicar-candidato.mjs
node CRM-Avance-Corp/supabase/scripts/f4/capturar-paridad.mjs despues
```

La semilla económica usa las RPC vigentes para crear tres leads convertidos,
cuatro contratos, 52 cuotas y dos cierres cooperativos. Incluye
el producto técnico del flujo libre y el peso de referido 0.150 publicados por
las migraciones originales. El catálogo ficticio adicional no es obligatorio
para contratar; sirve para futuras pruebas de compatibilidad.

En el banco actual, `F4-BASE-INICIAL` y `F4-BASE-UPGRADE-MISMO-MES` son
antecedentes sin job PDF. Los ensayos documentales posteriores sí generaron y
recuperaron PDFs reales; no se afirma que todos los jobs del banco estén sellados.
La paridad económica inicial no demuestra cobertura documental de esos antecedentes.

Oráculos ejecutables sobre el banco ya instalado, **secuencialmente**:

```sh
node CRM-Avance-Corp/supabase/scripts/f4/probar-cooperativas.mjs
node CRM-Avance-Corp/supabase/scripts/f4/probar-avance-existente.mjs
node CRM-Avance-Corp/supabase/scripts/f4/probar-fechas-anulacion.mjs
node CRM-Avance-Corp/supabase/scripts/f4/probar-conservacion-historia.mjs
node CRM-Avance-Corp/supabase/scripts/f4/probar-concurrencia.mjs
node CRM-Avance-Corp/supabase/scripts/f4/probar-portal-nuevo.mjs
node CRM-Avance-Corp/supabase/scripts/f4/probar-revision-responsable.mjs
node CRM-Avance-Corp/supabase/scripts/f4/probar-documento.mjs
node CRM-Avance-Corp/supabase/scripts/f4/probar-fusion.mjs
node CRM-Avance-Corp/supabase/scripts/f4/probar-identidad-controles.mjs
node CRM-Avance-Corp/supabase/scripts/f4/verificar-estructura.mjs
```

Cada recorrido usa solicitudes y depósitos ficticios nuevos; reejecutarlo añade
operaciones de prueba. No borra ni restaura datos. La prueba de fechas sella julio
mediante `crm.cerrar_periodo` y espera agosto abierto. La prueba de concurrencia
observa los procesos bloqueados en PostgreSQL antes de soltar el candado y deja
apagado el escritor del banco. Las otras pruebas de operaciones lo encienden
solamente allí. Los ensayos de estas operaciones reservan PDFs; el oráculo documental de abajo procesa sus propios contratos ficticios.

`actualizar-funciones-local.mjs` permite iterar funciones revisadas con el
escritor del banco apagado; exige que los cuerpos restantes coincidan con la
candidata. No aplica tablas ni triggers ni registra migraciones. La candidata
final todavía debe ensayarse íntegra desde una base reconstruida, con reversa.

## Acceso Portal desde cooperativa

El circuito técnico es preparar inversión → completar acceso → confirmar la
misma solicitud. `crm.acceso_inversion_fn` vuelve a comprobar al actor y a la
persona en cada paso; `crm-inversion-portal` crea/reutiliza exclusivamente el
Auth marcado por ese proceso. El perfil conserva al responsable comercial.

- `probar-portal-nuevo.mjs`: cuatro respuestas perdidas después de commits
  reales, concurrencia de Auth, correo ocupado, procedencia y permisos. Restaura
  la bandera que encontró al iniciar. No envía correos.
- `probar-portal-lease.mjs`: pierde el primer reclamo y espera **diez minutos
  reales** sin cambiar su token/version/lease en SQL. Imprime seguimiento cada
  treinta segundos. Enciende el escritor local y lo deja encendido para los
  siguientes ensayos; apagarlo al terminar la tanda.
- `probar-portal-veto.mjs`: requiere escritor local encendido; marca/levanta
  No insistir por las RPC vigentes entre cuatro pasos del acceso.
- Los datos privados de esos ensayos quedan en `/private/tmp/avancecorp-f4-bank`;
  `evidencia-f4/portal-*.json` contiene resultados sin tokens ni documentos.

Para probar también el entrypoint Deno, preparar los archivos y servirlos en
una terminal mientras se ejecuta el oráculo HTTP en otra:

```sh
node CRM-Avance-Corp/supabase/scripts/f4/preparar-edge-portal-local.mjs
/private/tmp/avancecorp-f4-tools/node_modules/.bin/supabase functions serve --workdir /private/tmp/avancecorp-f4-bank
```

Con el escritor local encendido:

```sh
node CRM-Avance-Corp/supabase/scripts/f4/probar-portal-edge.mjs
```

Detener `functions serve` al terminar. No copiar `.env` ni secretos de otros
proyectos. La prueba utiliza las claves locales que configura el CLI.

La ampliación del banco existente se hizo con `instalar-acceso-portal-local.mjs`:
exige la copia privada `candidata-antes-portal.sql`, comprueba las 28 funciones
anteriores e instala solo dos columnas, su control de auditoría, el índice y
las funciones revisadas/nuevas. Es una iteración de una sola vez, **no** se usa
en una base donde la candidata completa ya incluye el módulo de acceso.

## Revisión después de cambiar de responsable

La preparación/repetición devuelve responsable esperado, responsable actual,
si requiere revisión y número de revisión. La puerta de revisión recibe la misma
solicitud, el responsable actual que se ha revisado, la versión esperada y un
motivo sin documento. No cambia los términos, la huella ni la saga de Auth.

- `probar-revision-responsable.mjs`: cambio de equipo en cinco momentos,
  recuperación, revisión repetida y atribución conservada después de confirmar.
  Restaura la bandera inicial.
- `probar-revision-controles.mjs`: requiere escritor local encendido; bloqueo
  real de perfil, reversión completa, GUC no reutilizable, campos protegidos,
  historial inmutable y dos revisiones antes de confirmar.
- `probar-revision-lease.mjs`: enciende el escritor local y lo deja encendido;
  crea Auth, pierde su respuesta y cambia de equipo. El nuevo responsable espera
  el plazo original real para recuperar sin el token del anterior. Solo considera
  éxito la recuperación y confirmación al final de esa espera.

`instalar-revision-local.mjs` amplía una vez el banco que conserva exactamente
`candidata-antes-revision.sql`. Agrega la tabla de revisiones y sus controles,
sin registrar una migración. No volver a ejecutarlo una vez instalado el módulo.
Los cambios posteriores de funciones se aplican con el escritor local apagado.

## Documento y fusión durante la inversión

La corrección y la fusión siguen usando las RPC publicadas de F3, sin cambios.
Un claim Auth no terminal bloquea ambas; se recupera el acceso y después Gerencia
corrige/fusiona. La corrección conserva la clave inicial del acceso, conforme a
la decisión del 06/09: aviso al cliente y recuperación de clave existente, sin
reset automático. Estos ensayos no envían avisos ni correos.

La solicitud conserva su persona de origen, contenido y hash. El contexto de
operación resuelve y bloquea la identidad canónica actual; si cambia mientras
espera, rechaza el intento y permite recargarlo. Se revisa el responsable si la
fusión lo cambió. La atribución de una inversión ya confirmada queda intacta.
Los comprobantes conservan su ruta original y se autorizan con el ámbito actual.

- `probar-documento.mjs`: siete momentos antes/durante/después del alta y de la
  confirmación; DNI→CE, historia económica, snapshot y credencial conservados.
- `probar-fusion.mjs`: cinco recorridos Avance y tres cooperativos. Incluye una
  solicitud de P cuyo Auth se crea en C y se recupera después de fusionar C en D.
- `probar-identidad-controles.mjs`: cuatro carreras reales con confirmación en
  ambos órdenes; corrección seguida de fusión y formato Auth anterior.
- Los tres oráculos restauran la bandera local inicial. `fusion-fixture.mjs`
  siembra solo fichas históricas ficticias sin lead/perfil; verifica documento
  y asigna responsable mediante las RPC de Gerencia. Nunca fabrica una fusión.

El caso de compatibilidad usa una solicitud confirmada anterior a esta ampliación,
ya existente en el banco, cuyo contexto Auth aún no tenía `inversionista_id`.
No elimina ese campo para fingir el formato anterior. En la reconstrucción final
se deberá preparar ese antecedente antes de aplicar la candidata completa.

## PDF real, recuperación y documento protegido

Miguel exige conservar el contenido del PDF. Cualquier incorporación relativa a
cotitulares requiere mostrar y aprobar previamente texto y ubicación. La
plantilla, renderer, firma, fondo y fuentes permanecen byte-idénticos a HEAD.
El cotitular se conserva en la tabla y snapshot; la plantilla v7 no lo imprime.

En una terminal, preparar el generador existente y servirlo en el banco:

```sh
node CRM-Avance-Corp/supabase/scripts/f4/preparar-pdf-local.mjs
/private/tmp/avancecorp-f4-tools/node_modules/.bin/supabase functions serve --workdir /private/tmp/avancecorp-f4-bank
```

Después de que el runtime esté disponible, desde otra terminal:

```sh
node CRM-Avance-Corp/supabase/scripts/f4/probar-pdf-real.mjs
```

El preparador copia solo nueve archivos del generador y comprueba/crea el bucket
privado del banco; no copia secretos ni reescribe archivos idénticos. El oráculo
usa Deno para generar y recuperar; solo inyecta fallos desde el handler con
adaptadores que ejecutan operaciones reales. Espera el lease de 120 segundos
sin cambiar estado, token o reloj en SQL. Restaura la bandera inicial.

PDFs y snapshots completos quedan en la carpeta privada `pdf-real/<ejecucion>/`.
Los informes sin claves están en `evidencia-f4/pdf-real-*.json`. La revisión visual
se hace por separado. Detener el servidor temporal al terminar; no se afirma
que todos los contratos históricos tengan un PDF nuevo.

La recuperación consulta primero el objeto existente si el job ya tuvo un
intento. Solo una ausencia explícita permite subir; bytes diferentes bloquean
el sello y nunca se sobrescriben. `storage.ts` acota cada operación a 20 segundos,
incluida la lectura de su cuerpo; su señal no se comparte con otras peticiones.
Una versión incompatible no toma reserva o devuelve la que pudo identificar.

Para el ensayo adicional, después del oráculo anterior y con Deno disponible:

```sh
deno run --config CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/deno.json --allow-env --allow-read --allow-write=/private/tmp/avancecorp-f4-bank,CRM-Avance-Corp/supabase/scripts/evidencia-f4 --allow-net=127.0.0.1:56321 --allow-run=docker CRM-Avance-Corp/supabase/scripts/f4/probar-pdf-bordes.mjs
```

Usa el SDK del generador y su adaptador real. Cuatro peticiones se interrumpen
con el plazo real de 20 segundos; los cortes se inyectan en el transporte.
Tres incompatibilidades se inyectan en respuestas de RPC, sin alterar versión
ni snapshot contractual en SQL. La subida tardía espera los 120 segundos reales
y comprueba un solo archivo/sello. Dos contratos anteriores sin job conservan
su régimen documental. Resultado del 07/09: 10 grupos conformes, ocho contratos
nuevos sellados y regresión posterior de 12 grupos/10 contratos satisfactoria.

Validación del worker: `deno check` del entrypoint, `deno fmt --check` y
`deno test` de `handler.test.ts` / `storage.test.ts`: 42 pruebas conformes
(31 + 11). La revisión visual anterior de 14 páginas sigue siendo evidencia de
aquellos dos archivos; no se presenta como una nueva revisión de cada PDF generado.
El límite cubre Storage; no se afirma un plazo global para Auth, RPC o render.
El checkpoint vigente es `../evidencia-f4/2026-09-07-continuacion-pdf-bordes.json`.

## Reintento de inversiones ya confirmadas

`private.inversion_persona_autorizada` conserva los candados y el ámbito vigente.
`private.inversion_persona_contexto` añade los requisitos comerciales para
nuevas escrituras. Solo solicitudes confirmadas pueden releerse sin exigir que
la persona siga habilitada para otra inversión. Pendientes, nuevas y equipo
ajeno mantienen sus bloqueos; ninguna relectura modifica el historial ni Auth.

```sh
node CRM-Avance-Corp/supabase/scripts/f4/probar-reintento-confirmado.mjs
node CRM-Avance-Corp/supabase/scripts/f4/regresion-reintento.mjs
node CRM-Avance-Corp/supabase/scripts/f4/capturar-auditoria-local.mjs
```

La opción `--caracterizar` del primer oráculo reproduce el defecto anterior y
solo debe usarse sobre esa versión; debe fallar después de corregirla. Crea dos
solicitudes preparadas para demostrar el veto sin inventar estados. Todas las
mutaciones de veto se hacen mediante las RPC vigentes y se restituyen al terminar.

`instalar-reintento-local.mjs` amplió una sola vez el banco que conservaba
`candidata-antes-reintento-confirmado.sql`: exige los 33 cuerpos previos, escritor
apagado y auxiliar nuevo ausente; instala cuatro ajustes y ese auxiliar sin
registrar migración. No se usa en una reconstrucción que ya tenga la candidata
completa. La nueva función privada carece de grants para roles de la API.

La auditoría de Claude y su evaluación están en
`../evidencia-f4/auditoria-claude-2026-09-07/`. Fue una revisión estática de seis
archivos de la versión anterior, no aprobación de la corrección posterior ni G4.
Se conservan las entradas exactas y las huellas.

`verificar-estructura.mjs` usa nombres con fecha/hora y creación exclusiva. Se
cambió porque el nombre fijo anterior sobrescribió una captura del checkpoint
19:58. La incidencia y la referencia posterior se documentaron en ese checkpoint;
no se presenta la captura posterior como si fuera la original.

## Observaciones del entorno

La red Docker interna impidió conectar el CLI con su base. El banco usa la red
local estándar: separación de proyecto/datos/credenciales, sin afirmar bloqueo
de Internet. El correo Auth local usa Mailpit; no se configuraron claves de
envío productivas.

La revisión auxiliar Endor del CLI temporal quedó UNKNOWN por ausencia de MCP
y `endorctl`. No se afirma que esa dependencia haya sido aprobada por Endor.
