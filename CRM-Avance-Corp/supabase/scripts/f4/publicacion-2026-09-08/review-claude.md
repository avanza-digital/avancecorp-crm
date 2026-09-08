VERDICT:
CHANGES_REQUESTED

SUMMARY:
El delta de publicación está bien construido: la candidata original queda intacta, el generador prueba mecánicamente que 47/48 cuerpos son idénticos byte a byte (`generar-publicacion.mjs:49-50`), las dos anclas de inyección son únicas por assert (`generar-publicacion.mjs:26`) y el guard de hashes aborta dentro de `begin;` si producción difiere, por lo que un error de captura no deja producción a medias. El ensayo de 9 grupos cubre instalación íntegra, idempotencia, doble instalación y el camino feliz del upgrade R4.

Los hallazgos accionables no están en la construcción del artefacto sino en tres puntos: (1) la premisa de release "todas las banderas OFF ⇒ sin cambio de comportamiento" no se sostiene, porque el camino caliente de creación de contratos gana una llamada incondicional y `private.backfill_multiempresa_ejecutar()` queda retirado de forma no reversible por bandera; (2) faltan aserciones negativas sobre el control financiero que este delta atraviesa (origen de tasa R4) y sobre el ACL de la tabla de banderas, que es el kill-switch de todo F4; (3) el plan F5 no nombra la fuente de datos de cooperativas ni exige auditoría/alcance de la búsqueda por documento. El plan F5 es sólido en secuencia y en el resto de reglas.

FINDINGS:

**[P1] "Banderas OFF" no equivale a "sin cambio en producción"; no hay artefacto de reversa preparado**

File:
`CRM-Avance-Corp/supabase/migrations/20260908211349_crm_f4_publicacion_compatible_rentabilidad.sql` (delta, hunk `@@ -3788,11 +3790,25 @@`), `CRM-Avance-Corp/supabase/scripts/f4/generar-publicacion.mjs:29-36`

Problem:
La instalación modifica `crm.crear_contrato_con_cuenta_pdf_v2`, que es la función viva de alta de contratos, y le añade `perform private.inversiones_escritura_bajo_candado();` como primera sentencia ejecutada **siempre**, independientemente de la bandera. La estrategia de reversa declarada es "Recovery OFF, never destructively DOWN", es decir, apagar banderas. Apagar banderas no revierte esta sentencia.

Evidence:
- Producción hoy tiene el cuerpo `f1a9655a75261d6ba2bb16744c77a8d9`, que **no** contiene esa llamada (el generador la inyecta en `generar-publicacion.mjs:29-30` sobre `pdf-antes.sql`).
- La inyección va después de `\nbegin\n`, o sea antes de cualquier condicional de bandera y antes de `if v_actor_id is null then raise insufficient_privilege` (contexto del diff).
- El nombre `..._bajo_candado` y su comentario "bandera antes de persona/cuenta/PDF" sugieren adquisición de candado además de lectura de bandera. *No dispongo del cuerpo de esa función; la parte de semántica de bloqueo es hipótesis, no hecho.*
- `probar-publicacion.mjs` no ejecuta ningún caso concurrente: las 9 pruebas son secuenciales de una sola sesión.

Impact:
Toda alta de contrato en producción pasa a ejecutar una lectura/candado adicional desde el minuto uno del despliegue. Si esa función serializa altas concurrentes o toma un lock sobre `crm.multiempresa_flags`, la degradación aparece en el camino comercial más caliente y **no se puede quitar apagando banderas**; el único remedio sería un fix hacia adelante redactado bajo presión.

Recommendation:
Antes de instalar, dejar preparado y ensayado en la copia sintética un artefacto de reversa hacia adelante que restaure `crm.crear_contrato_con_cuenta_pdf_v2` exactamente al cuerpo `f1a9655a75261d6ba2bb16744c77a8d9` (ya está capturado en `publicacion-2026-09-08/pdf-antes.sql`) y reponga `private.backfill_multiempresa_ejecutar` (ver hallazgo siguiente), con su propio guard de hash. Añadir además un caso de dos altas concurrentes en el ensayo, o documentar explícitamente el comportamiento de bloqueo de `inversiones_escritura_bajo_candado` como evidencia de que no serializa.

---

**[P1] `private.backfill_multiempresa_ejecutar` se retira incondicionalmente sin inventario de llamadores adjunto**

File:
`CRM-Avance-Corp/supabase/scripts/f4/probar-publicacion.mjs:74-78`

Problem:
El propio ensayo confirma que, con las banderas apagadas, instalar F4 hace que una función existente en producción falle con 55000. Es un cambio de comportamiento no condicionado por bandera sobre una función que hoy es invocable.

Evidence:
```js
caso('Escritores nuevos apagados y F2 global retirado al instalar', () => {
  assert.equal(sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'"), 'f');
  assert.throws(() => rpc('preparar_inversion_fn', [...]), /P0409/);
  assert.throws(() => sql('...select private.backfill_multiempresa_ejecutar()'), /55000/);
});
```
`private.backfill_multiempresa_ejecutar()` figura en el inventario de consumidores con md5 `930acfc792eb4db91df599f26e283f12`, es decir, existe y está capturada en producción. La evidencia adjunta no incluye ninguna búsqueda de llamadores (frontend, edge functions, cron/pg_cron, runbooks de psql, jobs de Administración).

Impact:
Si algún runbook operativo, job programado o acción de administración la invoca, el despliegue rompe ese flujo el mismo día, con banderas apagadas y sin ruta de vuelta por bandera. La descripción "F2 global retires even OFF: censo/admin bounded batches replace it in eventual activation" describe el reemplazo *futuro*, no cubre la ventana entre instalación y activación.

Recommendation:
Adjuntar el inventario de llamadores (grep en `app/src`, `supabase/functions`, `supabase/migrations`, `pg_cron.job`, documentación operativa) y confirmar cero llamadores vivos; o condicionar el retiro a una bandera para que sea reversible sin DOWN. Como mínimo, registrar la decisión en el acta de despliegue con el resultado de la búsqueda.

---

**[P1] El ensayo no verifica el ACL/RLS de `crm.multiempresa_flags`, que es el kill-switch de F4**

File:
`CRM-Avance-Corp/supabase/scripts/f4/probar-publicacion.mjs:62-68`

Problem:
El bucle de aserciones de seguridad enumera 7 tablas nuevas y comprueba `relrowsecurity` y ausencia de privilegios para `anon`/`authenticated`/`service_role`. `crm.multiempresa_flags` no está en esa lista, pese a ser la tabla de la que depende cada guard de escritura de F4.

Evidence:
```js
for (const t of ['inversion_solicitudes','inversion_solicitud_revisiones','inversion_ajustes_mes_cerrado',
  'inversion_eventos','inversion_backfill_lotes','inversion_cotitular_origenes','inversion_solicitud_correcciones']) {
```
Además, los flips de bandera del ensayo (`:79` y `:112`) se hacen con `sql(...)` sin `como(...)`, es decir fuera del rol `authenticated`, por lo que ninguna prueba establece qué puede hacer un usuario autenticado con esa tabla.

Impact:
Si `authenticated` tuviera UPDATE sobre `crm.multiempresa_flags`, cualquier usuario logueado podría encender F4 en producción y saltarse todo el gating de F7/G6. La suite actual pasaría igual.

Recommendation:
Añadir `multiempresa_flags` (y `crm.ledger_rentabilidad`, `crm.politica_rentabilidad`) al bucle de ACL, y un caso negativo explícito ejecutado con `como(..., vendedor)` que confirme que un `authenticated` no puede leer ni escribir la bandera.

---

**[P1] El control de "origen de tasa por cliente" que atraviesa este delta no tiene prueba negativa, y F4 razona sobre `inversionista_id` mientras R4 razona sobre `cliente_id`**

File:
Delta `crear_contrato_con_cuenta_pdf_v2` (hunk `@@ -3788,11 +3790,25 @@`); `CRM-Avance-Corp/supabase/scripts/f4/probar-publicacion.mjs:89-107`

Problem:
El código afirma en comentario un control de seguridad financiera:
```sql
-- Va con el cliente delante para que no pueda aplicarse al contrato de otro
perform set_config('crm.rentabilidad_origen_upgrade',
  case when p_contrato->>'categoria' = 'upgrade' and v_origen_upgrade is not null
       then coalesce(p_contrato->>'cliente_id','') || '|' || v_origen_upgrade else '' end, true);
```
El ensayo solo ejercita el caso positivo. No hay ningún caso en el que `contrato_origen_id` apunte a un contrato de **otro** cliente, que es exactamente lo que el comentario dice prevenir.

Evidence:
- `probar-publicacion.mjs:90` `up.contrato.contrato_origen_id = alta.id;` — mismo cliente, siempre.
- El dato viaja desde el cliente: `preparar_inversion_fn(...{inversionista_id, empresa, ...up})` en `:94` recibe `up.contrato.contrato_origen_id` sin que la evidencia muestre validación de pertenencia en F4.
- El guard de R4 compara por `cliente_id`, pero F4 introduce identidad canónica y fusión (`crm.fusionar_inversionistas_fn`, md5 `6919e7ce...`, en el inventario). Ninguna prueba cubre "upgrade sobre un contrato originado bajo un `cliente_id` fusionado".

Impact:
Dos escenarios, ambos financieros: heredar una tasa de un contrato ajeno (si el guard no cierra el caso que F4 abre), o romper upgrades legítimos de personas fusionadas al no coincidir `cliente_id` con el del contrato origen. *La conducta exacta del guard es hipótesis: no dispongo del cuerpo de `private.trg_contratos_observar_rentabilidad`.*

Recommendation:
Añadir dos casos al ensayo: (a) `contrato_origen_id` de un contrato de otra persona ⇒ rechazo o no herencia, verificado en `crm.ledger_rentabilidad`; (b) upgrade posterior a una fusión ⇒ herencia correcta. Si el guard compara `cliente_id`, documentar cómo se resuelve tras fusión.

---

**[P2] La aserción del origen R4 es un `includes` sobre el JSON completo del ledger, no sobre el campo**

File:
`CRM-Avance-Corp/supabase/scripts/f4/probar-publicacion.mjs:104-106`

Problem:
```js
const ev = JSON.parse(sql(`select coalesce(jsonb_agg(to_jsonb(l)),'[]') from crm.ledger_rentabilidad l where l.contrato_id=${q(id)}`));
assert(ev.length > 0, 'R4 debe registrar la observación de la operación');
assert(JSON.stringify(ev).includes(alta.id), 'El libro debe conservar el origen del upgrade');
```
`includes` sobre el serializado completo pasa si `alta.id` aparece en *cualquier* campo (un eco del payload, un blob de diagnóstico, un `contrato_anterior` no relacionado), aunque el campo de origen esté vacío. Y `ev.length > 0` no comprueba ni el tipo de observación ni la tasa resultante.

Impact:
La prueba que sostiene la afirmación "Upgrade por F4 conserva origen de R4" puede pasar con la herencia de tasa rota. Es la única prueba del delta sobre la lógica financiera que este cambio toca.

Recommendation:
Aserción sobre la columna/ruta JSON concreta del origen, y aserción sobre el valor de tasa resultante del contrato nuevo comparado con el del contrato origen bajo la política en enforcement (15/tope 19).

---

**[P2] El subquery inyectado de cotitulares no está protegido contra 0 ni contra >1 fila**

File:
`CRM-Avance-Corp/supabase/scripts/f4/generar-publicacion.mjs:31-36`

Problem:
```sql
if private.inversiones_escritura_bajo_candado() then
  perform private.inversion_cotitulares_vincular(
    (select id from crm.inversiones where contrato_id=v_contrato_id),'alta');
end if;
```
Sin `strict` ni guard: si no hay fila en `crm.inversiones` para ese contrato, se pasa NULL a `inversion_cotitulares_vincular`; si hubiera más de una, PostgreSQL lanza "more than one row returned by a subquery" desde el camino caliente de alta.

Evidence:
El ensayo solo cubre el caso de exactamente una fila (`probar-publicacion.mjs:84` `count(*) = 1`). La evidencia adjunta no muestra un índice único sobre `crm.inversiones(contrato_id)`.

Impact:
Con NULL, la vinculación de cotitulares se salta en silencio (datos incompletos sin error); con duplicado, la creación del contrato falla con un error opaco de PostgreSQL en producción.

Recommendation:
Confirmar y adjuntar la restricción única sobre `crm.inversiones(contrato_id)`, o convertir a `select ... into strict` / añadir guard explícito con mensaje de dominio.

---

**[P2] El GUC de origen es una única ranura por transacción; un trigger diferido no puede atribuirla por fila**

File:
Delta `crear_contrato_con_cuenta_pdf_v2` (hunk `@@ -3788,11 +3790,25 @@`)

Problem:
El comentario del propio código describe la mitigación elegida:
> "se REESCRIBE en cada alta (también vacío) para que un alta posterior de la misma transacción no herede la declaración de la anterior."

Reescribir funciona si el lector corre inmediatamente después de cada alta. Si el lector es un constraint trigger que dispara **al commit** —como describe el propio comentario ("el candado del servidor ... al commit")— y una transacción crea dos contratos, al commit el GUC solo contiene el valor de la última llamada: el upgrade que iba primero pierde su declaración de origen, o la del segundo se evalúa contra el primero.

Evidence:
`set_config(..., true)` es transaccional (correcto para pooling), y el comentario sitúa a `private.trg_contratos_observar_rentabilidad` en el commit. No hay ninguna prueba con dos altas en la misma transacción. *La cadencia exacta del trigger es hipótesis: no tengo su cuerpo.*

Impact:
Pérdida silenciosa de herencia de tasa (o aplicación al contrato equivocado del mismo cliente) en cualquier flujo que cree más de un contrato por transacción. F5.5 ("Nueva inversión ... Avance reutiliza contrato/cuenta/PDF") aumenta la probabilidad de que ese flujo aparezca.

Recommendation:
Es cuerpo heredado de R4 y no es delta de esta tarea, así que no bloquea la publicación; sí conviene registrarlo como deuda con dueño. Si se confirma el disparo diferido, la corrección estructural es indexar la declaración por `contrato_id` (tabla temporal o columna transitoria) en vez de una ranura única.

---

**[P2] El caso "Base actual conserva..." verifica el estado que el propio script acaba de construir, no producción**

File:
`CRM-Avance-Corp/supabase/scripts/f4/probar-publicacion.mjs:36-45`

Problem:
Las líneas 36 y 40 instalan incondicionalmente `documento-antes.sql` y la migración de PDF v8 sobre la copia; el caso de la línea 42 después asserta los md5 `f1a9655...` y `45077ddc...`. El nombre del caso ("Base actual conserva el contrato PDF de Rentabilidad R4 y la corrección administrativa") y el comentario de la línea 41 ("La captura leída en producción prueba que la deriva PDF es exactamente R4") invitan a leerlo como evidencia sobre producción; no lo es.

Impact:
El eslabón que sostiene los dos hashes nuevos del guard es la captura de solo lectura de producción, que **no viene adjunta** en esta evidencia. Riesgo contenido: el guard aborta la transacción si el hash no coincide, así que un error de captura no deja producción a medias — por eso esto es P2 y no BLOCK.

Recommendation:
Renombrar el caso para que refleje lo que prueba (coherencia de la copia sintética con la captura), y adjuntar/archivar la salida cruda del preflight de solo lectura junto a `ensayo.json` como evidencia de la deriva.

---

**[P2] El plan F5 no nombra la fuente de datos de cooperativas**

File:
`BASE DE CONOCIMINETO/AVANCECORP/Plan de implementacion F5 - cartera y ficha multiempresa (2026-09-08).md:21-36, 41-46`

Problem:
La sección "Punto de partida que se reutiliza" nombra con precisión cada archivo del lado Avance (`mi-cartera.tsx`, `cliente-ficha.tsx`, `cliente-ficha-modelo.ts`, `crm-api.ts`...), pero para cooperativas solo dice "las cooperativas aparecen aparte" (línea 24). F5.2 promete devolver "empresa, moneda" y F5.4 "inversiones por empresa/moneda" para Qorilazo y Prodelco sin nombrar ni una tabla, RPC o vista de origen.

Impact:
F5.3 y F5.4 no son estimables ni implementables si resulta que el capital/depósito de cooperativas aún no tiene fuente consultable; el descubrimiento llegaría en mitad de la implementación, no en el paso de contrato.

Recommendation:
Añadir a F5.1 un entregable explícito: inventario nombrado de tablas/RPC de origen por empresa (Avance, Qorilazo, Prodelco), con moneda, estado y responsable, y marcar como bloqueante cualquier empresa sin fuente.

---

**[P2] El plan F5 no exige auditoría de lectura ni acota la búsqueda por documento**

File:
`BASE DE CONOCIMINETO/AVANCECORP/Plan de implementacion F5 - cartera y ficha multiempresa (2026-09-08).md:43, 55-80`

Problem:
F5.3 introduce "búsqueda por nombre/documento/contacto" sobre las tres empresas. La regla 4 acota la *visualización* por responsable y la regla 5 la caché, pero ninguna regla acota el **buscador**: buscar por DNI permite enumerar si una persona es inversionista y con quién, aunque no esté en el ámbito del actor. Tampoco hay ninguna regla de auditoría de lectura, pese a que F4 ya deja disponible un sumidero de eventos (`crm.inversion_eventos`, visible en `probar-publicacion.mjs:62`).

Impact:
Fuga por enumeración de PII (documentos de identidad y relación comercial) entre equipos, y ausencia de rastro de quién consultó la ficha de quién en un módulo que concentra datos financieros de tres empresas.

Recommendation:
Añadir dos reglas: (a) el buscador aplica exactamente la misma autorización que el listado y no revela existencia fuera del ámbito (sin distinguir "sin resultados" de "sin permiso"); (b) las lecturas de ficha y las búsquedas por documento se registran en `crm.inversion_eventos` con actor, identidad y filtro. Y añadir el caso negativo correspondiente a la matriz de F5.6.

---

**[P3] Asimetría en el generador: un hash se reemplaza sin verificar ocurrencias**

File:
`CRM-Avance-Corp/supabase/scripts/f4/generar-publicacion.mjs:40-41`

Problem:
```js
salida = salida.replaceAll('9833ed526e733dc8af6ca78e5c85c7ca', 'f1a9655a75261d6ba2bb16744c77a8d9');
salida = reemplazar(salida, '49d73e13f8969161060e2ce2b669a85a', '45077ddc61bd59ab5f435116de292b05');
```
La línea 41 usa `reemplazar`, que asserta exactamente una ocurrencia (`:26`); la 40 usa `replaceAll`, que tiene éxito silencioso con cero ocurrencias.

Impact:
Si un refactor futuro cambia el número de apariciones del hash antiguo, el generador emite un artefacto cuyo guard sigue comprobando el hash obsoleto y la migración aborta en producción con el mensaje engañoso "cambió la función". No es un bug vivo: el delta muestra las dos apariciones correctamente sustituidas.

Recommendation:
Antes del `replaceAll`, `assert.equal(salida.split('9833ed...').length - 1, 2)`.

---

**[P3] Higiene del manifiesto: campos declarados por asignación y `conforme` siempre verdadero**

File:
`CRM-Avance-Corp/supabase/scripts/f4/generar-publicacion.mjs:57-58`, `probar-publicacion.mjs:22`

Problem:
`cuerposSinCambio: 47`, `conservaRentabilidadR4: true` y `conservaAdministracion: true` son literales, no valores derivados de las comprobaciones. `caso()` empuja `{conforme:true}` incondicionalmente tras ejecutar `fn()`, sin try/catch, por lo que `ensayo.json` nunca puede registrar un fallo.

Impact:
Cosmético en cuanto a corrección (los `assert` previos abortan el proceso y `ensayo.json` no se escribe), pero en una cultura de gates basada en evidencia, un manifiesto cuyos campos no pueden ser falsos vale menos como evidencia de lo que aparenta.

Recommendation:
Derivar `cuerposSinCambio` del `deepEqual` real y documentar en el propio manifiesto que su existencia implica que todos los casos pasaron.

---

**[P3] `readFileSync(destino)` obliga a pre-crear el archivo destino**

File:
`CRM-Avance-Corp/supabase/scripts/f4/generar-publicacion.mjs:54-55`

Problem:
`const existente = readFileSync(destino, 'utf8');` lanza ENOENT si el destino no existe, así que reproducir el artefacto desde cero exige un `touch` previo con el nombre exacto — paso manual no documentado en el encabezado del script.

Impact:
Merma la reproducibilidad que el script busca garantizar; un tercero que intente reproducir el sha256 `f0f28b03...` falla en el primer intento.

Recommendation:
Documentar el paso o usar lectura tolerante (`existsSync ? readFileSync : ''`) conservando el assert anti-sobrescritura.

---

**[P3] Reordenamiento respecto a la verificación de sesión (heredado de la candidata, no de este delta)**

File:
Delta `crear_contrato_con_cuenta_pdf_v2`, contexto del hunk `@@ -3788,11 +3790,25 @@`

Problem:
`perform private.inversiones_escritura_bajo_candado();` queda **antes** de `if v_actor_id is null then raise insufficient_privilege`. Una sesión inválida ejecuta la lectura de bandera (y el posible candado) antes de ser rechazada.

Impact:
Superficie mínima de contención/coste para llamadas no autenticadas. Ya estaba en la candidata aceptada en G4, así que queda fuera del alcance de este delta; se registra para no darlo por revisado.

Recommendation:
En un cambio posterior, mover la inyección después del chequeo de sesión.

TEST GAPS:
- Sin prueba negativa de `contrato_origen_id` perteneciente a otro cliente (el control que el comentario del código declara).
- Sin prueba de upgrade posterior a `fusionar_inversionistas_fn` (choque `inversionista_id` canónico vs `cliente_id` del guard R4).
- Sin aserciones de ACL/RLS sobre `crm.multiempresa_flags`, `crm.ledger_rentabilidad` y `crm.politica_rentabilidad`.
- Sin caso concurrente (dos altas simultáneas) que caracterice `inversiones_escritura_bajo_candado` en el camino caliente.
- Sin caso de dos altas en la misma transacción para el GUC de origen.
- Sin caso de `crm.inversiones` ausente o duplicado para el contrato en la inyección de cotitulares.
- La aserción de origen R4 es `includes` sobre el JSON completo, no sobre el campo ni sobre la tasa resultante.
- El estado inicial del ensayo es condicional (`probar-publicacion.mjs:24-39`) y `ensayo.json` no registra qué rama de preparación se ejecutó.

ARCHITECTURE RISKS:
- Ranura única de GUC (`crm.rentabilidad_origen_upgrade`) como canal entre la RPC y un trigger diferido: no es direccionable por fila y no escala a más de un contrato por transacción.
- Dos modelos de identidad conviviendo: R4 razona sobre `cliente_id`, F4 sobre `inversionista_id` canónico con fusión. F5 construye toda su navegación sobre el segundo (regla 1 del plan) mientras el control de tasa sigue en el primero.
- El guard de inventario se puebla dinámicamente por `prosrc ilike '%cierres_externos%'`: cualquier función nueva que solo mencione la cadena invalida el preflight. Correcto como detector, frágil frente a trabajo concurrente en la rama.

SECURITY RISKS:
- Kill-switch (`crm.multiempresa_flags`) sin cobertura de permisos en la suite.
- Herencia de tasa declarada por el cliente en el payload, con validación no evidenciada en el nuevo camino F4.
- F5: búsqueda por documento sin alcance definido (enumeración de PII) y sin auditoría de lectura.

REGRESSION RISKS:
- Camino caliente de alta de contratos modificado en producción con banderas apagadas, sin reversa por bandera.
- `private.backfill_multiempresa_ejecutar` inutilizable tras la instalación, sin inventario de llamadores adjunto.
- Orden de despliegue frontend → SQL → edge functions con estados intermedios no descritos: `crm-contrato-pdf-v2` mapea razones de error de F4 (P0409) que solo existen tras el SQL, y `crm-inversion-portal` depende de objetos que solo existen tras el SQL. Conviene fijar y publicar el orden exacto y qué se ve en cada estado intermedio.
- 13 fallos de Playwright atribuidos a fixtures obsoletos se corrigieron y la suite completa "se está repitiendo": el resultado completo aún no existe al momento de esta revisión.

RECOMMENDED NEXT ACTIONS:
1. Preparar y ensayar en la copia sintética el artefacto de reversa hacia adelante (restaurar `f1a9655...` + reponer `backfill_multiempresa_ejecutar`, con guard de hash propio) antes de tocar producción, y adjuntar el inventario de llamadores de `backfill_multiempresa_ejecutar`.
2. Ampliar `probar-publicacion.mjs` con: ACL de `multiempresa_flags`, caso negativo de origen cross-cliente, aserción del campo/tasa en lugar de `includes`, y guard de 0/>1 filas en la inyección de cotitulares. Volver a generar `ensayo.json`.
3. Re-ejecutar el preflight de solo lectura **inmediatamente antes** de `apply_migration`, archivar su salida cruda junto a `ensayo.json`, y verificar que los bytes aplicados hashean a `f0f28b032cfa7c4b65dc6734fb359e263f0feebaf174bf25537a215628a434ae`.
4. Publicar el orden exacto de despliegue (frontend / SQL / edge functions) con el comportamiento esperado en cada estado intermedio, y confirmar que la suite Playwright completa terminó en verde antes de declarar DONE.
5. Antes de arrancar F5, añadir al plan: inventario nombrado de fuentes por empresa (F5.1), alcance de autorización del buscador y auditoría de lectura (reglas nuevas + casos en F5.6).

CONFIDENCE:
MEDIUM — Alta sobre lo verificable en los artefactos adjuntos (generador, ensayo, delta, plan F5). Media sobre los hallazgos que dependen de cuerpos no adjuntados: `private.inversiones_escritura_bajo_candado`, `private.trg_contratos_observar_rentabilidad`, `private.inversion_cotitulares_vincular` y las validaciones internas de `preparar_inversion_fn`/`confirmar_inversion_revisada_fn`. Esos puntos están marcados como hipótesis en su hallazgo. No emito BLOCK porque el guard de hashes dentro de la transacción contiene el riesgo de una captura errónea de producción.
