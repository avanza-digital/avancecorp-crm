# Pipeline «Gestionado»: filtro `p_gestion` en `crm.cartera_filtrada_fn`

Migración `20261001154153_crm_cartera_filtro_gestion.sql`. **Ensayada en banco Docker propio y APLICADA en
producción el 01/10/2026 (~15:20 Lima) por `!` de Miguel**; acreditada después en solo lectura (15 anclas `[OK]`)
y con la sonda HTTP. El frente que envía `p_gestion` se publica aparte. Acta en `../../migrations/MIGRACIONES.md`.

> **Desde `20261001212341_crm_cartera_filtro_potencial` la firma viva es la de 14** (se añadió `p_potencial`
> al final; `p_gestion` sigue siendo el 13.º y su regla no cambió). Este kit queda como acta de SU migración:
> `ensayar.mjs`, `acreditar.sql` y `reversa.sql` exigen la firma de 13. Para revertir esta migración hay que
> revertir antes la del potencial (`../potencial-lead/reversa-filtro.sql`). El oráculo de la regla se corre
> contra la firma de 14 desde `../potencial-lead/banco/ciclo-fase3b.sh` (paso 13).

## Qué hace

Los analistas piden en el Pipeline una columna «Gestionado» entre «Nuevo» y «Contactado»: leads que
ya se intentaron contactar y aún no responden. No es una etapa guardada (el lead sigue en
`etapa = 'nuevo'`): la columna se calcula con un filtro opcional, 13.º argumento de la función.

| `p_gestion` | Devuelve |
|---|---|
| `null` (o ausente) | Lo mismo que antes: no recorta. |
| `'con_gestion'` | Leads con titular, con `tenencia_desde`, y al menos un contacto (llamada realizada o no contestada, WhatsApp enviado o recibido, reunión realizada) con `creado_en >= tenencia_desde` y NO deshecho (`metadata.deshecho_en`). |
| `'sin_gestion'` | Todos los demás. Sin titular o sin `tenencia_desde` ⇒ sin gestión. |
| otro valor | `22023` «Filtros de cartera inválidos». |

- **Regla de Miguel (01/10):** lo que intentó un analista ANTERIOR no cuenta para el actual. El reloj
  es `crm.leads.tenencia_desde`, que sella el trigger `trg_leads_zzz_tenencia_desde` y se renueva al
  reasignar y al reabrir. Consecuencias, todas fijadas en el oráculo: reabrir un descartado también
  devuelve el lead a «Nuevo», incluso con el mismo titular; cuenta la FECHA del contacto, no su autor
  (un intento del supervisor dentro de la tenencia cuenta); en etapas terminales (`tenencia_desde`
  nula) todo es «sin gestión».
- **Lo deshecho no cuenta (decisión del 01/10):** un resultado de llamada deshecho por su puerta
  (`crm.deshacer_resultado_llamada`) conserva la fila con `deshecho_en`; para el filtro no ocurrió,
  como en los núcleos de Gestión Diaria. Solo un intento deshecho ⇒ «Nuevo»; deshecho + otro vigente
  ⇒ «Gestionado». `ultimo_contacto_en` y `sin_tocar` no se tocan: siguen viendo esa llamada.
- **La forma del payload no cambia**: sin eco y sin campos nuevos por fila (hay bundles viejos). La
  fila ya trae con qué comprobarlo en UN sentido: con gestión ⇒ `vendedor_id` y
  `ultimo_contacto_en >= tenencia_desde`. El recíproco no vale (por lo deshecho).
- Recorta la MISMA base que los demás filtros (filas, totales, capital, embudo) e ignora la etapa: la
  pantalla lo usa con `p_etapa = 'nuevo'`.
- Igual que antes: INVOKER bajo RLS, `stable`, `search_path` vacío, solo `authenticated` ejecuta, una
  sola firma (se retira la de 12) y la exención analítica se mueve y resella.

## De qué depende la regla (y qué vigila la migración)

La regla compara dos relojes que sella el SERVIDOR; el cliente no puede fabricar una gestión ni
borrarla. La migración se niega a instalarse (preflight, y lo repite en el postflight) si algo de
esto deja de ser lo auditado:

| Guarda | Qué ancla |
|---|---|
| 4 · reloj del LEAD | Trigger `trg_leads_zzz_tenencia_desde` activo, con su definición y su función: `tenencia_desde` se renueva al reasignar y el cliente no puede escribirla. |
| 5 · reloj e integridad de la ACTIVIDAD | Triggers `trg_01_gestion_lead_serializada` (re-sella `creado_en` y revalida el ámbito) y `trg_00_actividades_resultado_solo_nucleo` (reserva el resultado de llamada y `deshecho_en`), activos y con definición y función auditadas · RLS encendida · una sola policy de INSERT (`actividades_insert`, su `with check`) · ninguna permisiva ALL ni policies de UPDATE/DELETE · restrictivas de `crm.actividades` y `crm.leads`: exactamente `crm_actor_activo_gate`, con su expresión · `authenticated` y `anon` sin UPDATE ni DELETE. |

La 3 (`assert_actividades_de_lead_base`) sella las permisivas de lectura; solo comprobaba que el gate
restrictivo estuviera. Por eso la 5 fija el conjunto de restrictivas: una restrictiva de SELECT añadida
(p. ej. `creado_por = auth.uid()`) daría a titular y supervisor veredictos distintos sobre el mismo lead.

**Límite conocido (carrera de relojes; no se toca aquí).** La tenencia se sella con
`statement_timestamp()` y el contacto con `clock_timestamp()` tras tomar el candado del lead. En una
reasignación en lote, o en una que espera a una gestión en vuelo, el intento del titular SALIENTE puede
quedar fechado después de la tenencia nueva y contar para el entrante. Ventana estrecha; el efecto es
un lead mal rotulado («Gestionado» en vez de «Nuevo»), sin exposición de datos. Arreglarlo es cambiar
el trigger de tenencia, que es otra tarea.

## Archivos

| Archivo | Para qué |
|---|---|
| `ensayar.mjs` | El ensayo entero, repetible. Escribe `reversa.sql`, `registrar.sql` y `verificacion.json`. |
| `test-cartera-gestion.sql` | Oráculo de negocio (128 aserciones): regla caso por caso, partición, validación, cursor, roles bajo RLS, negativas de falsificación (contacto en lead ajeno, `deshecho_en` a mano, UPDATE y DELETE de actividades, `creado_en` futuro) y la cadena REAL de triggers y puertas (entrega, llamada por `crm.registrar_llamada_v4`, deshacer por `crm.deshacer_resultado_llamada`, nuevo intento, reasignación, descarte y reapertura). Se puede correr solo. |
| `volumen.sql` · `igualdad.sql` · `particion-volumen.sql` · `rendimiento.sql` | Fragmentos que compone `ensayar.mjs`: 5 000 leads y ~31 600 actividades sintéticas; igualdad vieja/nueva; el Pipeline recorrido por cursor contra un oráculo independiente; tiempos con planes. |
| `siembra-control-banco.sql` | Solo para un banco recién montado: declara y sella el trinquete analítico, que un volcado de solo esquema deja vacío. |
| `acreditar.sql` | **Solo lectura** (termina siempre en `raise`): anclas y conteos de realidad. Antes y después de publicar. |
| `reversa.sql` · `registrar.sql` | Generados por el ensayo con las huellas medidas. No editar a mano. |
| `banco.mjs` · `generar-*.mjs` | Acceso al banco (solo `docker exec` a `avancecorp-gestionado-AAAAMMDD`) y generadores. |

## Ensayo

Banco: `supabase/scripts/potencial-lead/banco/montar-banco.sh` con el volcado de esquema de
producción, contenedor `avancecorp-gestionado-AAAAMMDD` (aquí `…-20261001`, puerto 55481).

```bash
node supabase/scripts/cartera-gestion/ensayar.mjs          # ~2 min; BANCO_CONTENEDOR=… para otro
docker exec -i -e PGPASSWORD=postgres avancecorp-gestionado-20261001 \
  psql -X -qAt -U postgres -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 \
  < supabase/scripts/cartera-gestion/test-cartera-gestion.sql   # solo el oráculo
```

Qué prueba, en orden (77 pasos):

1. ANTES: gate analítico, sello, declaración y anclas (`acreditar.sql`).
2. Control: migración + oráculo en una transacción deshecha.
3. Igualdad vieja/nueva sin `p_gestion` y `resumen_cartera_fn` antes/después en la misma sesión.
4. Instalación con un rojo ajeno en el censo: lo conserva.
5. 26 mutantes del preflight: 8 de las guardas 1 a 4; 16 de la guarda 5, uno por cláusula (`trg_01`
   apagado o recreado con un `WHEN` que lo neutraliza, `trg_00` con otro cuerpo, RLS apagada, policy
   de INSERT con otro `with check` o abierta a otro rol, segunda policy de INSERT, policies ALL, UPDATE
   y DELETE, restrictiva de SELECT añadida, gate alterado, UPDATE o DELETE concedidos a `authenticated`
   o a `anon`); a la policy ALL la rechaza antes la guarda 3, así que un gemelo sin la 3 prueba que la
   cláusula de la 5 no es código muerto; y uno quita el `search_path` fijado. 6 del postflight (uno
   prueba que la repetición de la guarda 5 tampoco es código muerto). Todos rechazados.
6. 16 mutantes de la lógica (el oráculo se pone rojo con cada uno, entre ellos «lo deshecho
   cuenta»; 1 equivalente declarado), 3 de ESTADO (el servidor deja de sellar o de reservar, o la API
   puede reescribir: las negativas de falsificación del oráculo se ponen rojas), 2 contra la
   igualdad y 2 contra el oráculo de volumen.
7. Aplicación real como `postgres` y en un mensaje; repetida, se niega.
8. DESPUÉS: oráculo, igualdad, Pipeline con volumen contra un oráculo independiente y rendimiento.
   Además extrae de `../test-rls.mjs` el código de su oráculo de gestión y lo ejecuta, actor por actor
   bajo RLS, contra las tablas y la función (con tres controles negativos). No es una ejecución de esa
   matriz —no hay PostgREST ni sesiones—: solo prueba que su lógica coincide con la función.
9. Guardas de la reversa, reversa real (todo EXACTAMENTE como antes, huella `7169d942…`) y repetida.
10. Reaplicación, registrador (idempotente) y acreditación final.

El banco queda CON la migración y sin datos. Resultado del 01/10 en `verificacion.json`.

## Publicación (Miguel, desde `CRM-Avance-Corp/`; servidor primero, pantalla después)

1. **Antes de producción: correr la matriz de `supabase/scripts/test-rls.mjs` donde haya credenciales**
   (rama de Supabase con el seed y esta migración aplicada; nunca contra producción: crea filas
   transitorias). Su bloque de cartera cubre este filtro: partición, oráculo propio por rol leyendo las
   tablas, caso permitido determinista, admisión (`vendInactive`, `clientBank`), catálogo de la firma
   de 13 (con `CRM_BANCO_PSQL_URL`), dominio y negativa cruzada. En el ensayo de este kit NO se pudo
   ejecutar (NOT RUN: exige credenciales); si se publica sin correrla, dejar esa excepción a la vista
   en el acta.
2. `supabase db query --linked --file supabase/scripts/cartera-gestion/acreditar.sql` — solo lectura.
   Debe decir «ANTES de publicar» y «todas las anclas coinciden: la migración pasaría su preflight».
3. `supabase db query --linked --file supabase/migrations/20261001154153_crm_cartera_filtro_gestion.sql`
4. `supabase db query --linked --file supabase/scripts/cartera-gestion/registrar.sql`
5. `acreditar.sql` otra vez: «DESPUES de publicar» y «quedó instalado lo ensayado». Advisors sin clases nuevas.
6. **Comprobar por HTTP que la API ya acepta `p_gestion`, ANTES de publicar la pantalla.** El
   `notify pgrst` de la migración no espera a que PostgREST recargue su caché de esquema. Con la sesión
   de cualquier usuario del CRM: `POST /rest/v1/rpc/cartera_filtrada_fn`, cabecera `Content-Profile: crm`,
   cuerpo `{"p_limite":1,"p_gestion":"con_gestion"}` → debe responder 200 con el payload. Si responde
   `PGRST202` (no encuentra la función en la caché), aún no recargó: esperar y repetir, o mandar otro
   `notify pgrst, 'reload schema'`. Sin sesión de persona vale la sonda anónima de la casa (acta de
   `20260920014500`): el mismo POST con la clave publicable del bundle vivo debe dar 401/`42501` y no
   404/`PGRST202`. Esa sonda anónima es para la API; no se imita con `set role anon` contra un banco
   Docker local (allí llamar sin `EXECUTE` tumba Postgres).
7. Publicar el frente que envía `p_gestion`.

Reversa: retirar primero ese frente; luego `reversa.sql` (reinstala la firma de 12 byte a byte y su
declaración; conserva la fila de `schema_migrations`: anotarlo en el acta). La reversa no detecta un
consumidor de SERVIDOR que ya pase `p_gestion` (plpgsql enlaza tarde: fallaría al ejecutarse); hoy no
hay ninguno y su cabecera trae la consulta para buscarlo antes de revertir.

## Trampas

- En esta imagen de Postgres, llamar a una función SIN `EXECUTE` bajo `set role` tumba el servidor:
  `anon` y `service_role` se comprueban en el catálogo, nunca llamando.
- `auth.uid()` de la imagen solo lee `request.jwt.claim.sub`; el de producción también
  `request.jwt.claims`. Las pruebas fijan las dos.
- La cadena real va en sentencias sueltas: dentro de un solo `DO`, `statement_timestamp()` no avanza y
  un intento anterior a la reasignación quedaría fechado después de la tenencia nueva.
- El `exists` del filtro es un `Index Scan` (no «solo índice»): `metadata` no está en
  `actividades_contacto_episodio_idx`. Medido: +0,08 ms por 2 222 sondeos con páginas todo-visibles;
  dentro del ruido a través de la función.
- Las huellas se miden con `search_path` vacío; la migración lo fija para su transacción. No es
  teoría: con `private` en el camino de la sesión, `pg_get_triggerdef` escribe la función del trigger
  sin esquema y su md5 pasa de `f5849e26…` a `4485fef7…`. Para acreditar en producción, `acreditar.sql`.
- El oráculo, la siembra de control y la de volumen (`volumen.sql`) exigen un banco sin datos; se
  niegan si los hay.
