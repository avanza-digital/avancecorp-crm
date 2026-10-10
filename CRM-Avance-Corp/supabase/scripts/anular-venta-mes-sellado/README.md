# Ensayo de «No se puede anular una venta de un mes sellado»

Verifica la migración `20261009210000_crm_anular_venta_mes_sellado.sql` **en el banco Docker local (el laboratorio) y sin
escribir nada**. Este ensayo **no se corre contra producción**: siembra ventas, sella meses de ensayo y llama a las puertas
de anulación de verdad, siempre dentro de una transacción que termina en `rollback`.

**Publicación (fase 4; la ensaya antes el Director en la branch).** Desde `CRM-Avance-Corp/`, la migración y después su registrador (`db query` no registra la versión):
`supabase db query --linked --file supabase/migrations/20261009210000_crm_anular_venta_mes_sellado.sql` y
`supabase db query --linked --file supabase/scripts/anular-venta-mes-sellado/registrar/20261009210000.sql`. Luego, el 2.3 (`20261009210100`) y su registrador.
El registrador exige el estado completo que deja la migración (puertas y detector: cuerpo, definición, ficha, ACL y comentario; y el
ledger de F4.2-bis) y se niega si el nombre ya está con otra versión; por `db query --linked` no llegan los NOTICE: sin error = registrado.

Ronda 2 (07/10/2026): incorpora las correcciones conciliadas tras las revisiones de Codex y del auditor de permisos
(`fase-2/bloque-2.6/revision/CONCILIACION.md`): mes **desconocido** (falla cerrado), varios episodios (error de integridad),
detector **INVOKER**, guarda de aislamiento **0A000**, preflight con `is_grantable` y ficha completa de los helpers, reversa
que **falla cerrada**, deuda previa conservada y fotos por contenido.

Ronda 3 (07/10/2026): cierra los tres P2 de la segunda revisión de Codex (`fase-2/bloque-2.6/revision/CONCILIACION-R2.md`):
la reversa exige también la **ficha** de las puertas y el **cuerpo y la ficha del detector** antes de tocar nada (ensayado con
`--reversa-con-grant` y `--reversa-con-detector-alterado`); un mes **nulo o no canónico** es error de integridad `P0001`, nunca
«abierto» (caso 3-N y su mutante; el preflight fija el NOT NULL y los CHECK de primer día de mes); el preflight y el postflight
fijan la **versión del ledger** (`md5(prosrc)` de `private.conversion_episodios`); y los textos dicen «política nueva», no
«mismo orden».

Ronda 4 (07/10/2026): cierra el P2 y los dos P3 de la tercera revisión de Codex (`fase-2/bloque-2.6/revision/CONCILIACION-R3.md`):
la huella del ledger cubre también **`private.conversion_cierres`** (en la que `conversion_episodios` delega los cierres desde
septiembre; preflight, postflight y 9c; deriva D20); el preflight exige además el **NOT NULL de `fecha_comercial`** (sin él el
CHECK de `periodo_comercial` daría UNKNOWN; deriva D21) y los textos dicen exactamente qué garantiza cada restricción; y la
reversa compara los **comentarios** de las dos puertas y del detector antes de tocar nada (`--reversa-con-comentario`), con un
contrato que enumera lo que exige en vez de decir «cualquier deriva».

Fase 4, F4.2 (09/10/2026): **reselle contra el código de producción** (laboratorio igual a producción: B5+B6, 32 migraciones de
`main` y `20261009120000`). La migración se negaba porque `main` cambió cuatro funciones que fija: `private.conversion_episodios`
(tope de referidos, `20261007160937`), `private.conversion_cierres` y `private.registrar_ajuste_si_mes_cerrado` (bases cargadas,
`20261006042144`) y `crm.cerrar_periodo` (tope de referidos, `20261007160937` y `20261007203000`). Se re-auditaron contra los
cuerpos de la auditoría (reconstruidos byte a byte, md5 comprobado): para la llamada del detector, las filas de cierre y su
`fecha_numerador` son las mismas (solo cambia el aporte: base cargada 1, referidos sobre el tope 0) y el cerrojo del mes de
`cerrar_periodo` es el mismo; un ensayo de equivalencia aparte (ledger auditado en pg_temp frente al vigente, detector entero
sobre cada uno, política apagada y encendida) dio 0 diferencias. Cambian solo esas huellas (preflight, postflight y 9c) y una
línea del montaje (la siembra de `crm.conversion_pesos`, ver «Trampas»); el detector, las puertas, la regla, la excepción, los
casos y sus expectativas, iguales. Cadena repetida: ROJO 26 (los mismos fallos que la ronda 4), VERDE 60, aislamiento, 27
mutantes + 2 equivalentes, 22 derivas, cinco reversas y trinquetes idénticos. Evidencia: `fase-4/F4.2-reselle/salidas/` del plan.

Fase 4, F4.2-bis (09/10/2026, tarde): **producción aplicó `20261009200000`** (baja de analista: lo que produjo un analista dado de
baja pasa a su responsable actual activo), que reescribe `private.conversion_episodios` (`e3d278a1…` → `125b4046…`), y la migración
volvía a negarse en el preflight. El cambio son dos líneas de la pierna de **operaciones** de cartera (su analista y su filtro de ámbito
pasan por `private.analista_efectivo_contrato`); las piernas de llegadas y de cierres, el tope y `conversion_cierres`, iguales. El
detector no lee ni el analista ni las operaciones: mismo mes para la misma venta, con la política de septiembre apagada o encendida
(en producción, encendida) y con un analista dado de baja y su heredero. Re-auditado por lectura y con un ensayo de equivalencia
aparte (ledger de F4.2 en pg_temp frente al vigente, detector entero sobre cada uno, 61 leads, cuatro estados: política apagada o
encendida × sin o con dos analistas de baja): 0 filas de cierre o llegada distintas, 0 respuestas del detector distintas, 0 errores,
las 20 siembras con su resultado esperado; no vacío: con la baja, 2 operaciones pasan al heredero. Cambian esa huella (preflight,
postflight y 9c) y un caso nuevo, **3-B** (ver la tabla); el detector, las puertas, la regla y la excepción, iguales. Cadena: ROJO 28
(los 26 de siempre y los dos de 3-B, todos «el servidor ACEPTÓ…»), VERDE 63, aislamiento con y sin migración, 27 mutantes + 2
equivalentes, 22 derivas, cinco reversas y trinquetes idénticos. Evidencia: `fase-4/F4.2b-reselle/salidas/` del plan.

## Qué prueba

La regla de Miguel (decisiones D-09, D-14 y D-17, 2026-10-06): anular la **conversión** (el cierre inicial) de una venta
cuyo mes tiene fila en `crm.periodos_cerrados` se rechaza con SQLSTATE `P0409`, el mensaje «No se puede anular: el mes de esta
venta (AAAA-MM) ya está sellado» y la pista «Un mes sellado no se reescribe. La corrección se hace por otra vía, fuera del
sistema.», por `crm.anular_cierre_avance` y por `crm.anular_cierre_externo` (solo si el cierre es inicial), y no escribe
nada. Si el mes de la venta **no se puede determinar** (sin acreditación, sin episodio de cierre y sin fecha de conversión) se
rechaza igual, con el mensaje «No se puede anular: no se puede determinar el mes de esta venta» y la misma pista. La única
excepción es quien es a la vez admin o superadmin del Portal y Gerencia del CRM: anula **sin ajuste** y deja rastro en los
metadatos de la actividad (`excepcion_mes_sellado` = `AAAA-MM` o `'desconocido'`, `excepcion_por`, `excepcion_en`).

| Caso | Qué exige |
|---|---|
| 1 y 2 | Gerencia **no exenta** (la `gerencia` histórica del banco, comercial+gerencia) anula una conversión de junio (sellado) por las dos puertas: `P0409`, mensaje y pista exactos; después, la foto del lead, sus anulaciones, sus cierres externos, sus actividades y **todos** los ajustes (por contenido, md5 de las filas), idéntica. |
| 3 | Mes sellado con una venta que **hoy no habría generado ajuste**: fuera de plazo, origen que no pesa, sin acreditación, sin episodio de cierre (por las dos puertas); y los dos relojes de la venta: el **episodio del ledger** manda sobre `convertido_en`, y la **fecha comercial** de la acreditación manda sobre ambos (septiembre). |
| 3-D | **Fecha de conversión ausente** (por la puerta externa; la de Avance ya rechaza esa ausencia con su `22023` de siempre, caso 3-D5): con acreditación de septiembre manda la acreditación (`P0409` 2026-09, no «desconocido»); con episodio de junio manda el episodio (`P0409` 2026-06); sin nada ⇒ **desconocido**: no exento `P0409` «no se puede determinar» y nada escrito; exento anula sin ajuste con `excepcion_mes_sellado = 'desconocido'`. |
| 3-M | **Dos episodios de cierre** en el ledger ⇒ el mismo error de integridad que `registrar_ajuste_si_mes_cerrado` (`P0001` «Integridad: el lead … tiene 2 episodios de cierre en el ledger») por las dos puertas, y nada escrito. Ver «Límites» 3: ese estado es imposible con el índice único puesto. |
| 3-B | **Analista dado de baja con heredero** (F4.2-bis, `20261009200000`): una venta de junio por la puerta externa cuya persona queda a cargo de SUP1 (activo) y otra por la de Avance; su vendedor (VEND1) se da de baja solo durante el caso. La regla de baja de producción tiene que ACTUAR (el analista efectivo del cierre externo es SUP1; si no, `FALLO 3-B-heredero`: el caso no probaría nada) y el rechazo es el de siempre (`P0409` 2026-06, nada escrito), por las dos puertas: el mes de la venta no depende del analista. |
| 3-N | **Mes no canónico o nulo** (ronda 3): una acreditación de septiembre con `periodo_comercial = 2026-09-10` (3-N1) o `NULL` (3-N2) ⇒ `P0001` «Integridad: el mes de la venta 2026-09-10 (lead …) no es un primer día de mes» (o `NULL`) y nada escrito; **nunca** «abierto» (el día 10 o un nulo no casan con el sello del día 1). Ver «Límites» 10: ese estado es imposible con el esquema puesto. |
| 4 | Lo que sigue entrando igual: mes abierto (las dos puertas), mes terminado sin sellar (agosto), cierre externo **no inicial** colgado de una venta de un mes sellado, «ya estaba anulado» con su mensaje de siempre, y los dos relojes al revés (episodio en mes abierto; acreditación en mes abierto). Con las claves de la respuesta, `mes_cerrado:false`, `ajuste_id:null`, la anulación registrada y la actividad **sin** marca de excepción. |
| 4g | **Deuda previa conservada**: una venta de junio anulada antes de la regla con su ajuste pendiente sembrado; tras anulaciones en mes abierto y terminado, rechazos en mes sellado y las del exento, la fila y su saldo (`pendiente_numerador = 1`, sin `saldado_en`) están byte a byte como se sembraron. |
| 5 | **Exento**: `ger_admin` (admin+gerencia) y `ger_super` (superadmin+gerencia) anulan en mes sellado por las dos puertas **sin ajuste**, con las mismas claves de respuesta, la anulación registrada y la actividad con `excepcion_mes_sellado` (AAAA-MM), `excepcion_por` y `excepcion_en`; también sobre una venta de septiembre que SÍ habría generado ajuste. Negativos: la `gerencia` histórica (rechazo del sello), `admin` sin ficha, `superadmin` puro, vendedor, supervisor y la llamada **sin sesión de usuario** (42501 «Solo gerencia…»). Y las dos mitades de la excepción medidas por sesión (`es_admin()` y `es_gerencia_crm_activa()`). |
| 6 | Frontera: una venta de julio se anula **antes** de sellar julio (entra) y otra **después** (se rechaza); la ya anulada sigue «ya estaba anulado». La carrera con `crm.cerrar_periodo` **no se puede probar con una conexión**: se mide que cada anulación que entra deja **tomado el cerrojo del mes** (`pg_locks`). Ver «Límites». |
| 7 | `crm.eliminar_inversion_fn`: en el corte `20261003162500` el laboratorio **no la tenía** y el oráculo lo anotaba como NO EJECUTADO; desde F4.2 el laboratorio igual a producción **sí la tiene** y el oráculo avisa de que hay que correr `eliminar-inversion/test-eliminar-inversion.sql` (no la ejerce: es la tarea F4.3 del plan). |
| 8 | Fechas de ensayo fijas (junio, julio, agosto y septiembre de 2026) y el mes en curso; no se mueve el reloj. |
| 9 | Catálogo: las dos puertas conservan dueño, DEFINER, `search_path` vacío y EXECUTE solo para el dueño y `authenticated` **sin opción de concesión**; el detector (si existe) es **SECURITY INVOKER**, dueño `postgres`, `search_path` vacío, volátil, devuelve `record` y **ningún** rol salvo el dueño tiene EXECUTE (`has_function_privilege` para `authenticated`, `anon`, `service_role`, `authenticator`); el detector llamado directamente da las tres respuestas (lead inexistente → desconocido; junio → sellado; mes en curso → no sellado); las huellas de `conversion_episodios` y `conversion_cierres` (la versión auditada del ledger, en sus dos funciones), `registrar_ajuste_si_mes_cerrado`, `saldar_ajustes`, `cerrar_periodo`, `es_admin`, `es_gerencia_crm_activa` y `rol_crm` no cambian; el **censo analítico** (`private.contadores_crudos_leads_citas()`) queda como estaba. |
| aislamiento | (`aislamiento.sql`, transacción aparte en **REPEATABLE READ**) las dos puertas responden `0A000` «La anulación de una venta no admite este modo de transacción» y nada queda escrito. Sin la migración, aceptan. |

## Por qué así

El ensayo no prueba una copia de las funciones: pega la **migración real** (preflight, postflight y comentarios incluidos)
dentro de la transacción. Si alguien toca la migración, el oráculo prueba lo tocado.

Para **sellar** un mes se sigue `supabase/scripts/test-cierre-mes.sql` (bloques 4–7): junio y julio de 2026 se sellan con
`crm.cerrar_periodo` real (su ventana ya pasó; no se mueve el reloj). **Septiembre de 2026 no se puede pedir a
`cerrar_periodo`** (su ventana abre el 10/10), así que su fila en `crm.periodos_cerrados` se inserta con los triggers apagados,
como hace `eliminar-inversion/test-eliminar-inversion.sql`; con ella y la política de septiembre activada se prueba la rama de
acreditaciones. La siembra de ventas, ledger, cierres, acreditaciones y la deuda previa también va con los triggers apagados
(`set local session_replication_role = replica`, solo durante la siembra; las puertas se llaman con los triggers encendidos).
Todo se deshace con el `rollback`.

El detector es **SECURITY INVOKER**: lo invocan solo dos puertas DEFINER, así que corre como su dueño (`postgres`) y nadie más
tiene EXECUTE (patrón del núcleo del ledger, `20261001160219`). En el laboratorio todas las llamadas son como `postgres`, de
modo que «funciona llamado desde las puertas» lo prueba todo el oráculo y «nadie más puede ejecutarlo» se prueba por
**catálogo** (9b), nunca llamando bajo `set role` (tumba el Postgres del banco).

## Cómo se corre

Desde `CRM-Avance-Corp/`. `EJECUTAR_SQL` es el comando que manda un archivo `.sql` al banco local (la herramienta del laboratorio
`fase-2/bloque-2.1/herramientas/lab_sql.py`, que compara una huella de la base antes y después y sale con 9 si algo quedó
escrito). Los SQL generados van a una carpeta de trabajo, no al repo.

```bash
# 1. ROJO: el oráculo SIN la migración. Es la medición del defecto.
node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --sin-migracion > "$SALIDAS/rojo.sql"
$EJECUTAR_SQL "$SALIDAS/rojo.sql"
#    → ENSAYO ROJO — 28 fallo(s) (26 hasta F4.2 + los dos de 3-B), todos «el servidor ACEPTÓ anular en un mes sellado / cuyo mes no se puede determinar / la
#      anulación» (casos 1, 2, 3-*, 3-D1..D3, 3-N1..N2, 5n-gerencia-historica, 6-despues*) o «al exento le nació un ajuste / sin
#      rastro» (casos 5-*, 3-D4): nunca un error de montaje. Los casos 3-M pasan en ROJO: hoy registrar_ajuste… lanza el mismo
#      error de integridad.

# 2. VERDE: la migración real + el oráculo. Termina SIEMPRE en excepción: eso es el veredicto.
node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs > "$SALIDAS/verde.sql"
$EJECUTAR_SQL "$SALIDAS/verde.sql"
#    → ENSAYO VERDE — 0 fallos (63 comprobaciones «ok» y las medidas 5-pares, 6, 7 y 8)

# 3. AISLAMIENTO: transacción REPEATABLE READ + migración + aislamiento.sql. Con --sin-migracion tiene que salir ROJO.
node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --aislamiento > "$SALIDAS/aislamiento.sql"
$EJECUTAR_SQL "$SALIDAS/aislamiento.sql"
#    → ENSAYO VERDE — 0 fallos (aislamiento): las dos puertas responden 0A000 y la foto queda intacta

# 4. Los mutantes: rompen una defensa DESPUÉS de la migración y exigen que el oráculo lo grite nombrando su fallo.
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/mutantes" bash supabase/scripts/anular-venta-mes-sellado/mutantes.sh
#    → MUTANTES: los 27 mutantes de verdad murieron, cada uno por su fallo; 2 equivalentes secuenciales confirmados.

# 5. Las derivas previas: rompen el catálogo ANTES de la migración y exigen que su preflight se niegue sin dejar rastro.
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/derivas" bash supabase/scripts/anular-venta-mes-sellado/derivas.sh
#    → DERIVAS: las 22 abortan en el preflight y no dejan rastro; el control entra; el mutante del preflight muere.

# 6. La reversa: aplicar → revertir → las puertas vuelven a ser las de antes.
node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --reversa > "$SALIDAS/reversa.sql"
$EJECUTAR_SQL "$SALIDAS/reversa.sql"
#    → REVERSA VERDE: prosrc 8556d0bd…/09a47896…, definición 23e3be19…/f568b78f…, sin detector y ficha idéntica.

# 7. La reversa con un SET añadido después de migrar: tiene que ABORTAR y no dejar rastro (falla cerrada).
node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --reversa-con-set > "$SALIDAS/reversa-con-set.sql"
$EJECUTAR_SQL "$SALIDAS/reversa-con-set.sql"
#    → REVERSA CON SET VERDE: la reversa ABORTÓ («no tiene exactamente la definición que dejó la migración»); foto IGUAL, SET conservado.

# 7b. La reversa con un GRANT añadido después de migrar (service_role sobre una puerta): tiene que ABORTAR por la FICHA.
node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --reversa-con-grant > "$SALIDAS/reversa-con-grant.sql"
$EJECUTAR_SQL "$SALIDAS/reversa-con-grant.sql"
#    → REVERSA CON GRANT VERDE: la reversa ABORTÓ («la ficha de crm.anular_cierre_externo(uuid,text) no es la que dejó la migración»);
#      foto IGUAL, GRANT conservado (service_role=X sigue en la ACL).

# 7c. La reversa con el detector REEMPLAZADO después de migrar (otro cuerpo, misma firma y ficha): tiene que ABORTAR y NO borrarlo.
node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --reversa-con-detector-alterado > "$SALIDAS/reversa-con-detector-alterado.sql"
$EJECUTAR_SQL "$SALIDAS/reversa-con-detector-alterado.sql"
#    → REVERSA CON DETECTOR ALTERADO VERDE: la reversa ABORTÓ («el detector private.mes_sellado_de_venta(uuid) no es el que dejó la
#      migración»); foto IGUAL, detector alterado conservado.

# 7d. La reversa con el COMENTARIO de una puerta cambiado después de migrar (COMMENT ON FUNCTION … IS 'otro'): tiene que ABORTAR y NO
#     sobrescribirlo con el comentario anterior.
node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --reversa-con-comentario > "$SALIDAS/reversa-con-comentario.sql"
$EJECUTAR_SQL "$SALIDAS/reversa-con-comentario.sql"
#    → REVERSA CON COMENTARIO VERDE: la reversa ABORTÓ («el comentario de crm.anular_cierre_avance(uuid,text) no es el que dejó la
#      migración»); foto IGUAL, comentario «otro» conservado.

# 8. Los trinquetes: la foto de los 36 private.assert_*() y del censo analítico, con la migración puesta, para compararla con la de antes.
node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --trinquetes > "$SALIDAS/trinquetes.sql"
$EJECUTAR_SQL "$SALIDAS/trinquetes.sql"
```

El ensayo se arma para una base que **todavía no tiene** la migración: su preflight exige las huellas anteriores de las dos
puertas. En una base que ya la tiene, el oráculo se corre solo (`--sin-migracion`) y entonces tiene que salir VERDE.

## Qué hay aquí

| Archivo | Qué es |
|---|---|
| `armar-ensayo.mjs` | Pega migración + oráculo en una transacción con `rollback`. Modos: `--sin-migracion`, `--mutante <archivo>`, `--reversa`, `--reversa-con-set`, `--reversa-con-grant`, `--reversa-con-detector-alterado`, `--reversa-con-comentario` (aplicar → deriva POSTERIOR → la reversa tiene que abortar sin dejar rastro; la foto incluye los comentarios de las puertas y del detector), `--deriva <archivo> [--espera "<texto>"]` (la línea `-- @@MIGRACION@@` del archivo se sustituye por la migración: deriva «ya aplicada»), `--trinquetes [--sin-migracion]`, `--aislamiento [--mutante <archivo>] [--sin-migracion]` (la transacción va en `repeatable read`); modificador `--migracion <ruta>` (otra migración, para mutar el preflight). Se niega si queda un `commit` suelto. |
| `pruebas.sql` | El oráculo (casos de arriba). Los actores son los del banco y **obligatorios**: si falta uno o no es el par esperado, el ensayo aborta (`ENSAYO ABORTADO`), no pasa en verde. Comprueba al empezar que va en `read committed`. |
| `aislamiento.sql` | El ensayo de la guarda `0A000`: siembra una venta por puerta y exige el rechazo en `repeatable read`. |
| `mutantes.sh` | 29 mutantes: 27 de verdad (21 de cuerpo —uno de ellos de aislamiento y uno, el del mes no canónico, de la ronda 3— y 5 de catálogo, más el del detector que usa `registrar_ajuste…`) y 2 **equivalentes secuenciales**. Cada uno solo cuenta como muerto si el ensayo sale ROJO **y nombra los fallos que le corresponden**. |
| `derivas.sh` | Veintidós derivas instaladas ANTES de la migración (dieciséis de catálogo de funciones; cuatro de lo que hace canónico el mes —CHECK y NOT NULL de `periodo_comercial`, NOT NULL de `fecha_comercial`, CHECK de `periodos_cerrados.periodo`— y dos de otra versión del ledger —`private.conversion_episodios` y `private.conversion_cierres`—), un control sin deriva y un **mutante del preflight** (sin comparar `is_grantable`, la deriva `WITH GRANT OPTION` tiene que colarse). |
| `generar_registrador.py` · `registrar/20261009210000.sql` | El registrador (`db query --file` no registra la versión; F4.1-A rondas 4 y 5): exige el estado completo que deja la migración —de las puertas y del detector, cuerpo, definición, ficha, ACL efectiva y comentario— y el ledger de F4.2-bis (`conversion_episodios` `125b4046…`, `conversion_cierres` `155ce2b1…`); se niega si el nombre ya está con otra versión o la versión con otro contenido; idempotente; la migración incrustada una vez. Regenerarlo si cambia la migración. |
| `reversa.sql` | Deshace una a una las cuatro sustituciones de cada puerta y borra el detector. **Falla cerrada** si difiere algo de lo que exige, y exige exactamente esto: de las puertas, cuerpo, definición, dueño, atributos, ACL con `is_grantable` y comentario; del detector, existencia, cuerpo, definición, ficha INVOKER y comentario. Ver «La reversa, con exactitud». |

## Límites conocidos (lo que este ensayo NO garantiza)

1. **La carrera con `crm.cerrar_periodo` no está probada.** La herramienta del laboratorio es de una sola conexión. Lo medido:
   cada anulación que entra deja tomado el cerrojo del mes (clave `hashtext('crm.periodos_cerrados')` + días desde 2000-01-01),
   que es el mismo que toma `cerrar_periodo` (`20260923172517…:279-285`, segunda clave). **Los cerrojos son de la transacción**:
   un mes ya cerrojeado antes por una anulación que entró (o por el propio sellado) ya no discrimina, así que cada comprobación
   se hace la **primera** vez que ese mes se cerrojea con éxito (julio en `6-antes`, septiembre en `5-ger_admin-fecha-comercial`,
   agosto en `4d`). Para la carrera de verdad hacen falta dos conexiones (una dentro de `cerrar_periodo`, otra anulando), en
   ambos órdenes y con `acreditar`: fase 4.
2. **Dos mutantes son equivalentes SECUENCIALES y no se pueden matar con una conexión:** «la excepción solo exige admin (sin
   Gerencia)» y «la excepción no exige sesión de usuario». La puerta ya exige `v_uid is not null` y `rol_crm = 'gerencia'`
   (42501) **antes** de preguntar por la excepción. El ensayo lo confirma (siguen VERDE) y mide las dos mitades por sesión
   (`medida 5-pares`). La conjunción **se conserva** porque bajo concurrencia (revocar Gerencia mientras la puerta espera el
   cerrojo del mes, en `READ COMMITTED`) la segunda comprobación sí defiende; esa prueba necesita dos conexiones (fase 4).
3. **Dos episodios de cierre son imposibles con el esquema puesto** (`crm.lead_asignaciones_una_conversion_por_lead_idx`, único
   parcial). Para ejercer la rama de integridad del detector el caso 3-M **quita ese índice dentro de la transacción del ensayo**
   (se deshace con el rollback) justo antes de sembrar y va al final de los casos de comportamiento. Lo que prueba es que, si el
   estado se diera, el detector falla cerrado con el mismo error que `registrar_ajuste…`; no prueba que el estado sea alcanzable.
4. **Septiembre se sella insertando la fila**, no con `cerrar_periodo`. Lo que prueba es la resolución del mes por la
   acreditación, no el sello de septiembre.
5. **El detector rechaza «sin fila de acreditación» resolviendo el mes como antes de septiembre** (episodio o `convertido_en`);
   es una interpretación del encargo (caso 3: «sin acreditación: igualmente rechazada»), aceptada en la conciliación (#18a).
6. **El rastro del exento vive en `crm.actividades.metadata`** (claves `excepcion_*`), más la fila de la anulación y su auditoría
   de siempre. `mes_cerrado` queda en `false` por compatibilidad con la pantalla y **no es el rastro**. Este ensayo no mira si
   alguna pantalla lo enseña (la app no se tocó).
7. `crm.eliminar_inversion_fn` (existe en el laboratorio desde F4.2) hereda el rechazo y la excepción **por lectura**, no medido:
   ejercerla es la tarea F4.3 (`eliminar-inversion/test-eliminar-inversion.sql`, caso 24).
8. **La guarda de aislamiento se ensaya en una transacción aparte** (`--aislamiento`): dentro del oráculo principal no se puede
   cambiar el modo de transacción una vez empezada. La migración no lleva guarda de aislamiento propia (solo el detector):
   por eso se puede aplicar dentro de esa transacción `repeatable read`.
9. **Permisos del detector por catálogo, no por llamada.** Como todo corre como `postgres` (su dueño), que `authenticated`,
   `anon`, `service_role` o `authenticator` no puedan ejecutarlo se lee con `has_function_privilege`; la prueba por PostgREST
   con sesiones reales va en `test-rls.mjs` (fase 4).
10. **Un `periodo_comercial` nulo o que no sea primer día de mes es imposible con el esquema puesto.** Lo garantizan, exactamente:
    el NOT NULL de `fecha_comercial` **más** el NOT NULL de `periodo_comercial` **más** el CHECK
    `periodo_comercial = date_trunc('month', fecha_comercial)::date` (con `fecha_comercial` nula el CHECK daría UNKNOWN y pasaría:
    ese NOT NULL es parte de la garantía); y, de propina, el CHECK de `plazo_hasta`, que llama a
    `private.conversion_plazo_hasta(periodo_comercial)`, STRICT y que rechaza con `22023` cualquier otro día. El preflight exige los
    dos NOT NULL y el primer CHECK (el de `plazo_hasta` no se fija: no hace falta para la garantía). Para ejercer la defensa en
    profundidad del detector, el caso 3-N **quita esos dos CHECK y el NOT NULL de `periodo_comercial` dentro de la transacción del
    ensayo** (se deshacen con el rollback), al final de los casos de comportamiento y después de 3-M. Lo que prueba es que, si el
    estado se diera, el detector falla cerrado con `P0001`; no prueba que el estado sea alcanzable.
11. **La versión del ledger está fijada, en sus dos funciones.** El preflight, el postflight y 9c exigen `md5(prosrc)` de
    `private.conversion_episodios` = `125b4046…` **y** de `private.conversion_cierres` = `155ce2b1…` (las de producción, re-auditadas
    en F4.2 y en F4.2-bis; antes `e3d278a1…` y, en la fase 2, `9c606dd4…` y `b1d6c336…`; `conversion_episodios` delega los cierres en `conversion_cierres`, y
    de ahí sale la `fecha_numerador` de la que el detector saca el mes: otra versión de una puede resolver otro mes conservando la
    huella de la otra). Lo que `conversion_cierres` llama —`private.cierre_externo_anulado`, `private.conversion_exclusion_fuente`,
    `private.peso_referido_conversion`, `private.conversion_origen_con_cierre`— y lo que `conversion_episodios` llama para el tope
    —`private.conversion_origen_base_tope`, `private.tope_referidos_conversion`— y, desde `20261009200000`, en su pierna de operaciones
    —`private.analista_efectivo_contrato`— decide qué cierres entran y con qué peso o tope, o a quién se atribuye una operación, no
    la fecha: son **dependencias declaradas, no fijadas**; el corte de la auditoría se cierra en las dos funciones del ledger y,
    si cambian, se re-auditan. Si el `main`
    del día de integrar tiene otra versión de cualquiera de las dos, o difiere el texto de un CHECK o falta un NOT NULL de los
    fijados, la migración se niega: releer con la misma consulta y re-auditar el detector **antes** de adaptar la migración
    (fase 4). Este ensayo solo acredita la versión del laboratorio.

## La reversa, con exactitud

- **Falla cerrada. Contrato:** antes de tocar nada exige, y si algo difiere se niega sin dejar rastro:
  (a) de las dos puertas, `md5(prosrc)` (`1bb2bfd1…` avance, `4b01f805…` externo) **y** `md5(pg_get_functiondef)` (`03b67308…` y
  `906372fe…`) exactamente los que dejó la migración, **y** su ficha auditada (dueño `postgres`, `security definer`, `search_path`
  vacío, ACL exacta con opción de concesión: EXECUTE solo para el dueño y `authenticated`, sin `GRANT OPTION`; la misma que fija el
  preflight de la migración); (b) del detector `private.mes_sellado_de_venta(uuid)`, que exista, `md5(prosrc)` (`8e22b2d6…`) **y**
  `md5(pg_get_functiondef)` (`ba2cfaaa…`) exactamente los que dejó la migración, **y** su ficha INVOKER (dueño `postgres`,
  `security invoker`, `search_path` vacío, sin EXECUTE para nadie salvo el dueño); (c) los **comentarios** (`obj_description`) de
  las dos puertas y del detector, exactamente los que dejó la migración (la reversa repone los dos primeros y borra el tercero:
  un `COMMENT ON FUNCTION … IS 'otro'` posterior se perdería sin verse). **Esa lista es todo lo que exige** —cuerpos, definiciones,
  ficha, ACL con `is_grantable`, comentarios, y existencia y huellas del detector— y no promete detectar nada fuera de ella. Si
  alguien cambió un cuerpo, un atributo (p. ej. `ALTER FUNCTION … SET lock_timeout`), el dueño o la ACL de una puerta, el cuerpo o
  la ficha del detector, o un comentario, **se niega** y no toca nada: se revisa a mano. Ensayado con `--reversa-con-set`,
  `--reversa-con-grant`, `--reversa-con-detector-alterado` y `--reversa-con-comentario`: aborta con el mensaje que le corresponde
  y la foto (cuerpos, dueño, ACL, comentarios y detector) queda idéntica, deriva incluida.
- **Qué restaura:** los dos cuerpos de antes (`md5(prosrc)` `8556d0bd…` y `09a47896…`; `md5(pg_get_functiondef)` `23e3be19…` y
  `f568b78f…`), sus comentarios, y borra `private.mes_sellado_de_venta(uuid)`. El postflight lo exige.
- **Qué conserva:** firma, dueño y ACL de las puertas (`create or replace` no los toca), que con el preflight de arriba son
  exactamente los auditados.
- **No des-anula nada.** Lo que el exento anuló queda anulado, sin ajuste y con su rastro; los ajustes que existieran siguen su
  curso. Tras revertir, el servidor vuelve a dejar anular en un mes sellado creando ajuste.
- **La fila de `supabase_migrations.schema_migrations` se conserva** (regla de la casa, como en `scripts/categoria-sin-operacion/LEEME.md`): la reversa no la toca; se anota en `MIGRACIONES.md` con fecha, motivo y su salida (F4.1-A ronda 5, auditor r2 P3-7).

## Trampas encontradas al escribirlo

- **`set_config('session_replication_role', …)` está denegado y `SET LOCAL session_replication_role = replica` no** (rol
  `postgres` del laboratorio, Postgres 17.6): la siembra usa la sentencia, no la función.
- **Un cierre no inicial sembrado con los triggers apagados falla al anularlo** si su `comprobante_objeto_id` no existe en
  `storage.objects`: Postgres vuelve a comprobar la FK al actualizar una fila nacida en la misma transacción. El oráculo usa un
  objeto que ya está en el laboratorio (no escribe en storage).
- **La siembra de `crm.conversion_pesos` (F4.2):** el oráculo sembraba una versión del peso `2026-01-01` con referido 0,5 «por si
  el banco no trae ninguna». Desde `20261007160937` el CHECK `conversion_pesos_referido_con_tope` exige tope a todo peso de
  referido mayor que 0,150, y el ensayo abortaba en el montaje (medido el 09/10/2026, antes de tocar nada). Ahora solo siembra si la
  tabla está vacía, y con 0,150; el laboratorio igual a producción ya trae `2026-07-01` y `2026-10-01`. Ningún caso es un referido:
  el peso no decide nada de lo que se mide.
- **`registrar_ajuste_si_mes_cerrado` no sirve de detector:** devuelve nada con acreditación fuera de plazo, origen que no pesa,
  sin acreditación, sin episodio y —hallazgo lateral— cuando `convertido_en` cae en un mes abierto pero el episodio de cierre
  está en un mes sellado (mira primero el mes de `convertido_en`). Los casos `3-*` los miden.
- **`boolean::text` es `true`/`false`, no `t`/`f`:** las fichas esperadas de los helpers en el preflight se escriben así.
- **`private.conversion_plazo_hasta(date)` es STRICT y rechaza (`22023`) un día que no sea el primero del mes**, y el CHECK de
  `plazo_hasta` la llama: sembrar un `periodo_comercial` no canónico (3-N1) obliga a quitar también ese CHECK, y el plazo se
  calcula sobre el primer día del mes; con `periodo_comercial` nulo (3-N2) el CHECK pasa (nulo) y basta quitar el NOT NULL.
- **Las restricciones se fijan por su texto, no por su nombre:** `conversion_acreditaciones_check1` es un nombre generado; el
  preflight, el oráculo y las derivas localizan el CHECK por `pg_get_constraintdef`.
- **Un comentario no entra en `pg_get_functiondef` ni en la ficha:** antes de la ronda 4, `--reversa-con-comentario` revertía y
  sobrescribía el `COMMENT ON FUNCTION … IS 'otro'` con el comentario anterior a la migración (medido: la foto salía DISTINTA). La
  reversa compara `obj_description` aparte, y la `FOTO` del armador incluye también el comentario del detector.
- **La huella de `conversion_episodios` no cubre `conversion_cierres`:** antes de la ronda 4, otro cuerpo de `conversion_cierres`
  entraba con la migración (medido: «la migración NO abortó») porque `conversion_episodios` solo la llama. Las dos se fijan.
- **El censo analítico censa toda función que nombre `crm.leads` y use `count(` o `sum(1)`:** el detector nombra `crm.leads`, así
  que cuenta episodios con `array_agg` + `cardinality` (y el censo queda idéntico: 9d y `--trinquetes`).
- **`postgres` no es superusuario en el laboratorio:** la deriva de «otro propietario» solo es posible cediendo a `service_role`
  (del que es miembro) tras concederle `CREATE` sobre `private`; sobre `public.es_admin` no se puede (el esquema no es suyo).
- **Un mutante que se instala dentro de un `for … in $@` con `«… $debe»` revienta con `set -u`:** bash toma `»` como parte del
  nombre de la variable. Se escribe `${debe}`.
- **Los cerrojos de transacción contaminan las comprobaciones de cerrojo** (ver «Límites», 1).
- **La baja de analista (F4.2-bis):** «dado de baja» es `crm.equipo.activo = false`, y `private.rol_crm` también exige `activo`: dar
  de baja a VEND1 (el vendedor de todas las ventas del ensayo) no afecta a quien anula (Gerencia), pero tiene que volver a estar activo
  enseguida (los casos 5n necesitan su rol de vendedor). Por eso 3-B lo da de baja y lo reactiva dentro del propio caso.
- **Los gates del banco no están todos verdes:** de los 36 `private.assert_*()`, 7 caen desde antes por trabajos ajenos. Lo
  que se exige es que la foto de los 36 y el censo NO cambien con la migración puesta (`--trinquetes`).
