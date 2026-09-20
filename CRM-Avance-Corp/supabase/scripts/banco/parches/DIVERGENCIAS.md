# Lo que el banco NO reproduce igual que producción

## ✅ RESULTADO FINAL — 196/196 versiones · paridad 9 de 9

Comprobado corriendo **la misma consulta en los dos lados** y comparando las huellas:

| Categoría | Nº | Banco | Producción | |
|---|---:|---|---|---|
| columnas | 743 | `7e95c5ce…` | `7e95c5ce…` | ✅ |
| funciones | 383 | `e0ca92f9…` | `e0ca92f9…` | ✅ |
| disparadores | 166 | `ff5f9a5c…` | `ff5f9a5c…` | ✅ |
| políticas RLS | 81 | `cb500f63…` | `cb500f63…` | ✅ |
| RLS por tabla | 71 | `c6ae27d2…` | `c6ae27d2…` | ✅ |
| índices | 286 | `dc49a4c2…` | `dc49a4c2…` | ✅ |
| restricciones | 515 | `f87693e8…` | `f87693e8…` | ✅ |
| registro | 196 | `346e3122…` | `346e3122…` | ✅ |
| vistas | 3 | `d2ea52eb…` | `d2ea52eb…` | ✅ |

La huella de cada categoría es el md5 del **contenido completo** ordenado, no un conteo: las
383 funciones incluyen cuerpo, dueño, comentario y permisos efectivos; los disparadores, su
definición entera (con el `WHEN`); las políticas, sus expresiones `USING` y `WITH CHECK`.

⚠️ **Lo que esta comprobación NO dice:** solo mira **estructura**. Los **datos** del banco son
su siembra, no los de producción — y así debe ser.

---


El banco replaya el SQL del REGISTRO de producción tal cual. Aquí está **todo** lo que
se apartó de esa regla, en tres categorías que no hay que confundir:

| Categoría | Qué es | ¿Debilita una prueba? |
|---|---|---|
| **1. Parches de banco** | Una aserción concreta neutralizada | **SÍ** — se declara una por una |
| **2. Siembra** | El DATO que la prueba necesita para ejecutarse | **NO** — la aserción corre entera |
| **3. Entorno** | El reloj del que ejecuta | **NO** — no toca ninguna lógica |

🔴 **Regla:** una divergencia sin fila aquí es un banco que miente. Si hay que apartarse
de nuevo, se anota con las tres columnas — qué, por qué y qué queda vivo.

---

## 1. Parches de banco (aserciones neutralizadas)

| Versión | Qué se neutralizó | Por qué | Qué sigue vivo |
|---|---|---|---|
| `20260824231133` `crm_gestion_clientes_renovaciones_conversion` | El censo `v_ops >= 48 and v_conversiones = 29` del backfill de agosto/2026 | Cuenta filas de PRODUCCIÓN; un banco recién nacido tiene 0. Se tolera **solo** el caso exactamente vacío (0/0): con datos parciales vuelve a abortar | Las otras dos aserciones del mismo postflight: que el backfill **no inventó capital** (`sum(capital_adicional) = 0`) y que el ledger **no acepta INSERT directo de `authenticated`** |
| `20260829191000` `crm_f4_a_pantallas_gerencia` | La guarda «la foto del vendedor está vacía — elegir otro actor» | Sin un solo contrato, las tres fotos son `[]` y el oráculo compararía `[]` con `[]`: no probaría nada. Se tolera **solo** con **cero contratos no-demo** en toda la base; con datos parciales vuelve a abortar | El reemplazo entero de las dos funciones y la **comparación antes/después** de las 5 huellas (gerencia, vendedor y supervisor). El oráculo hizo su trabajo **en producción**, que es donde tenía algo que decir |
| `20260831010000` `crm_atr_3a_lentes_y_ficha_al_analista` | El censo `13 contratos sin analista` | Es un recuento de filas de PRODUCCIÓN. Un banco nuevo tiene 0 contratos, luego 0 sin analista — y eso no contradice nada. Se tolera **solo** con 0 sin analista **y** 0 contratos no-demo | Los tres pines de huella del preflight, el pin ambiental bivalente de `capital_episodios`, los cuerpos generados y todo el postflight |
| `20260901180000` `crm_atr_4_sancion_de_anular_solo_conversion` | El censo `1 coop anulada` **y** su mitad gemela, «la coop anulada es la demo `a112aead…` con motivo DEMO» | Ambas describen **una fila concreta de producción**. Con `cierres_externos` vacío no hay ninguna fila que contar ni que identificar. Se tolera **solo** con 0 anuladas **y** 0 cierres externos en total | Los otros dos censos del mismo preflight (0 anulaciones de Avance, 0 deudas en `ajustes_mes_cerrado`), los 5 bisturís y las 4 lentes del dinero |
| `20260901200000` `crm_f7_2_cerrar_el_interruptor_legacy` | El suelo `producto_condiciones >= 568` | Otro recuento de producción. Lo que la aserción quiere decir es «esta migración no borró condiciones»; en un banco nunca hubo ninguna. Se tolera **solo** con 0 condiciones **y** 0 contratos no-demo | El cierre del interruptor, el acta en el libro de observación y el resto del postflight |

---

## 2. Siembra (datos, no parches)

Ninguna de estas toca una aserción: le dan a la prueba el dato que le falta para
**ejecutarse de verdad** en vez de neutralizarse.

| Fichero | Qué siembra | Quién lo pide |
|---|---|---|
| `siembra-banco.sql` | Un supervisor y un vendedor con perfil de Portal activo | `20260812000259_crm_cierres_externos`, que **muere por diseño** en todo banco nuevo |
| `siembra-gerencia.sql` | Una gerencia activa (`b0000000-…-0003`) | `20260827090000` (F2.3b): «postflight vacuo: sin gerencia activa no se puede probar la cadena» |
| `siembra-actor-oraculos.sql` | El **par completo** del actor que los oráculos suplantan por su UUID literal de producción `bf1c562e-ed08-4cc3-92a8-34f1fa3e9127`: `admin` en el Portal **y** `gerencia` en el CRM | Los oráculos de la F4.b/c/d. Sin el perfil, `es_admin()` es falso → «No autorizado»; sin el asiento de CRM, `private.rol_crm()` es NULL → «No autorizado» otra vez. Sembrar el **par** es fiel a producción, donde gerencia real = admin en el Portal |

---

## 3. Entorno: la zona horaria de quien ejecuta

El replay corre cada migración con `set timezone='America/Lima'`.

**Por qué.** Banco y producción corren con `TimeZone=UTC`, pero los gates del sistema
comparan contra el «hoy» de **Lima** (`(now() at time zone 'America/Lima')::date`).
`current_date` en una sesión UTC devuelve el día de **UTC**. Entre las **19:00 y las 24:00
de Lima** los dos NO coinciden, y un oráculo que pasa `current_date` como `p_hasta` se come
un «Periodo invalido» — **también en producción**. Medido el 01/09 a las 19:54 de Lima:

```
banco       TimeZone=UTC   current_date=2026-09-02   hoy_lima=2026-09-01   desfase
producción  TimeZone=UTC   current_date=2026-09-02   hoy_lima=2026-09-01   desfase
```

Poner la sesión en Lima reproduce las condiciones en que producción aplicó estas
migraciones. No toca la lógica de nadie: solo alinea el reloj.

⚠️ **`PGOPTIONS` no sirve** — el pooler de Supabase se come las opciones de arranque
(medido: sigue diciendo UTC). Hay que mandar un `SET` explícito por invocación.

🟢 **Y se comprobó que esto NO es un incidente de producción:** cero funciones, cero
tareas del cron y cero defaults de columna pasan `current_date` a esas puertas. El desfase
solo hace la migración no replayable en esa franja diaria.

---

## ✅ RESUELTO — la parada del 145/196 no era una divergencia

`20260827090000_crm_f2_3b_distribucion_v3` detuvo el replay con:

> `private.metricas_distribucion_leads_autorizada viva NO es la esperada`

**Primera explicación, ESCRITA Y DESPUÉS REFUTADA.** Llegué a anotar aquí que la causa era
el backfill del registro del 15/08 —«replayar reproduce el estado final, no los
intermedios»—. Suena razonable y es **falso**: se midió el texto guardado de la migración
anterior (`20260808160137`) y **no** contiene la rama `p_version=3`; el registro sí guarda
el texto histórico. Queda escrito el error porque la explicación bonita casi sustituye a
la medición.

**Lo que de verdad pasó,** reconstruido midiendo:

| # | Hecho medido |
|---|---|
| 1 | El fichero de 3b **no abre transacción propia**: `psql` lo corre sentencia a sentencia, en autocommit |
| 2 | En el **primer intento** el preflight pasó, las secciones 1–4 **commitearon**, y murió el postflight — le faltaba una gerencia activa (por eso existe `siembra-gerencia.sql`) |
| 3 | `replay.py` registra la versión **solo si `psql` termina bien** ⇒ los objetos quedaron dentro y la versión **sin registrar** |
| 4 | En el **segundo intento** el preflight ancla el estado ANTERIOR a 3b, que 3b ya se había comido ⇒ el rojo que se leyó como «el banco está corrupto» |

**Verificado antes de registrarla** — las cuatro piezas que instala 3b, contra producción:

| Objeto | cuerpo | comentario | ACL | dueño |
|---|---|---|---|---|
| `private.conversion_punteria(int,int)` | ✅ | ✅ | ✅ | ✅ |
| `private.metricas_distribucion_leads_v3_core(date,date,timestamptz)` | ✅ | ✅ | ✅ | ✅ |
| `private.metricas_distribucion_leads_autorizada(date,date,smallint)` | ✅ | ✅ | ✅ | ✅ |
| `crm.metricas_distribucion_leads_v3_fn(date,date)` | ✅ | ✅ | ✅ | ✅ |

**4 de 4 idénticas**, y el postflight de la propia 3b —el juez de contrato, no una
huella— vuelve a pasar en verde: `v3 = v2 + sondas · cadena real probada`. Por eso 3b
**se registró sin neutralizar nada**: no había nada que neutralizar.

### El arreglo, que es del arnés y no de la migración

`replay.py` ahora envuelve en transacción (`psql -1`) **todo fichero que no traiga la
suya**. De 51 pendientes, 39 abrían transacción propia y **12 no**: cualquiera de esas 12
podía repetir el mismo medio-aplicado. Ahora entra entera o no entra.

🔑 **La lección, que vale para cualquier replay:** una migración sin transacción que muere
en su postflight deja el banco **con el trabajo hecho y sin acta**. El siguiente intento
falla en el preflight —diciendo la verdad— y parece corrupción. Antes de neutralizar un
ancla, **comprobar si la migración ya se aplicó**: correr su propio postflight y comparar
sus objetos con producción.

### La forma del registro: dos arreglos, y el segundo lo cazó la Ola R

**(1) Los dos caracteres de más.** `volcar.py` guardaba el texto con un `;\n` final de
cortesía. Se le quita al registrar, y las 60 versiones ya registradas se repararon —
comprobando antes, una a una, que sin esos 2 caracteres su huella **ya coincidía** con la
de producción. No se adivinó nada.

**(2) Las fronteras entre sentencias.** El arreglo (1) no bastó, y quien lo cazó fue la
propia **Ola R**: se negó a aplicarse diciendo que la versión `20260819162752` «no tiene el
cuerpo objetivo».

`statements` no es un texto: es un **array de sentencias**. El replay lo guardaba como
**un solo elemento** con todo el texto unido — mismo texto, fronteras distintas (1 elemento
donde producción tiene 17). La Ola R comprueba la identidad **por elemento**
(`md5(string_agg(md5(elemento) order by ord))`) **y** el número de sentencias, precisamente
porque —está escrito en su cabecera— *el md5 del texto unido NO ve fronteras desplazadas*.

Se arregló re-registrando desde producción con `to_jsonb(statements)`, respetando el array
(`reregistrar.py`).

🔑 **La lección:** un banco que replaya el registro tiene que reproducir el registro
**entero — texto Y fronteras**. Y el que la haya cazado una guarda ajena, escrita para otra
cosa, es el mejor argumento para no desmontarlas: la alternativa era neutralizar la Ola R y
quedarse con un registro sutilmente falso.

**(3) Las 34 de julio.** Las versiones que **Supabase replayó por su cuenta** al crear el
banco guardaron el texto de los ficheros del repo, que no es letra por letra el que guarda
producción. La estructura que producen es **idéntica** (lo prueban las 8 categorías de la
comprobación final), pero el texto no. Se copió también el de producción, para que el
registro entero compare al byte.

---

## 4. Cómo se aplica: el fichero entero en UN mensaje

`replay.py` manda cada migración con `psql -c "<fichero>"`, **no** con `psql -f`.

**Por qué, y quién lo cazó.** El oráculo de la **F7.1** fotografía el payload de la pantalla
de distribución y lo vuelve a pedir después, exigiendo que no haya cambiado. En el banco
cambiaba — y la clave que se movía era `generado_en`.

Medido en producción, con el mismo código y dentro de un bloque que termina en `raise`:

```
filas distintas = 0 · generado_en A=2026-09-01T20:08:22.388918-05:00
                                  B=2026-09-01T20:08:22.388918-05:00
```

Idénticas. La razón es del **transporte**, no del SQL: `statement_timestamp()` es «la hora
del último **mensaje** recibido del cliente». Producción aplica con
`supabase db query --linked --file`, que manda el fichero entero **como un solo mensaje**,
así que el reloj no avanza en toda la migración. `psql -f` manda **una sentencia por
mensaje** y el reloj corre entre ellas.

🔑 **La lección:** dos arneses que ejecutan el mismo SQL pueden dar resultados distintos por
**cómo lo mandan**. Y otra vez fue una guarda ajena la que lo destapó — el arreglo correcto
era imitar a producción, no relajar el oráculo.

Efecto secundario bienvenido: `-c` con varias sentencias las corre en **una transacción**
salvo que el fichero traiga sus propios `BEGIN`/`COMMIT` — la misma atomicidad que buscaba
el `-1`, y la misma que tiene producción.

## 19/09/2026 — ensayo de `20260919185718_crm_actividades_de_lead.sql` (historial por lead)

El banco está en la versión `20260910234453` y **no tiene el mundo SLA del 07/09** (ni
`private.assert_sla_nucleo/operacion/comandos/avisos`). La migración se aplicó desde una copia en
el scratchpad con UNA diferencia respecto al archivo versionado:

| Qué se neutralizó | Por qué | Qué sigue vivo |
|---|---|---|
| Los cuatro `perform private.assert_sla_*()` del postflight (comentados) | Esas funciones no existen en el banco; no son objetos de esta migración y en producción están verdes (`20260918213000` las corre igual) | Todo lo demás al byte: preflight con `assert_actividades_de_lead_base()` (huellas y conjunto de policies, grants, USAGE), las 4 funciones, el gate propio `assert_actividades_de_lead()` y los 5 mutantes |

Lo que el banco NO puede reproducir de este ensayo: la matriz `test-rls.mjs` por PostgREST
(la sesión no dispone de la clave de servicio ni de `CRM_DEMO_PASSWORD`); se sustituyó por la misma
matriz ejecutada por SQL bajo `set role authenticated` + `request.jwt.claims` de cada usuario
fixture, que aplica exactamente la misma RLS. El gate por PostgREST queda NOT RUN hasta que se corra
con las claves.

**Resultado (19/09 ~15:00 Lima): PASS.** Gate OK, 5/5 mutantes detectados, esquema intacto después; matriz
11 usuarios × 4 leads exacta por SQL bajo la RLS real; keyset y validaciones correctas; `EXPLAIN` por
`idx_actividades_lead`. Detalle en `supabase/migrations/MIGRACIONES.md` (entrada 20260919185718). El banco
queda con las funciones instaladas y sin fila en `schema_migrations` (la pone `reregistrar.py`).

## 19/09/2026 — ensayo de `20260919235100_crm_tareas_pendientes_keyset.sql` (tareas por cursor)

**Sin divergencias.** No se usó `banco-f7` (sigue en `20260910234453`, sin el mundo SLA ni la
restrictiva `tareas_postventa_lectura`): el ensayo corrió en el **contenedor local**
`supabase_db_avancecorp-f5-bank` (puerto 58322) sobre la copia `tareas_cursor_20260919`, creada
como `supabase_admin` desde `conversion_inversion_base_20260919` (paridad `20260917235656`, CON los
cuatro `assert_sla_*` y CON la policy de postventa), así que la migración se aplicó **tal cual** y en
un solo mensaje (`psql -c`), como producción. Guion reproducible:
`supabase/scripts/tareas-pendientes/ensayar-local.sh`; resultado en
`supabase/scripts/tareas-pendientes/verificacion.json`.

Lo que la copia NO reproduce: la matriz `test-rls.mjs` por PostgREST (sin clave de servicio ni
`CRM_DEMO_PASSWORD`); se sustituyó por la misma matriz por SQL bajo `set role authenticated` +
`request.jwt.claims` de los 11 actores fixture. El caso `testTareasPendientes` queda escrito para el
próximo ciclo del banco. Los md5 del registrador se miden en producción tras instalar (los de la
copia son solo referencia).

**Resultado (19/09, tres corridas; la última ~20:10 Lima tras auditor-rls y Codex): PASS.** Gate OK, 17/17
mutantes detectados y esquema intacto; 11 actores con puerta = tabla en orden `(vence_en, id)`; keyset de 2 (+1)
con empate de `vence_en` sin repetidos ni huecos; volumen > 1 000 (1 200 tareas de vend1 en lotes de 500+1 =
tabla); 22023/42501/anon correctos; `EXPLAIN` con planificador normal y cursor profundo por
`tareas_pendientes_keyset_idx` (`Bitmap Index Scan`, `ROW(vence_en, id) > ROW(cursor)`).
La copia queda con la migración instalada y las tareas sembradas canceladas.
