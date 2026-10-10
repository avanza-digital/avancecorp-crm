# Ensayo de «El servidor exige el número de contrato»

Verifica la migración `20261009210100_crm_numero_contrato_servidor.sql` **en el banco Docker local (el laboratorio) y sin
escribir nada**. Este ensayo **no se corre contra producción**: da de alta contratos de verdad con los actores del banco, por la
llamada directa a `public.crear_contrato` y por la puerta `crm.crear_contrato_con_cuenta_pdf_v2`, siempre dentro de una transacción
que termina en `rollback`.

**Publicación (fase 4; la ensaya antes el Director en la branch), tras el 2.6 y su registrador.** Antes de aplicar, `candidatos-sonda.sql` (solo lectura) dice qué pares vendedor–cliente probaría la sonda y si concluirían. Desde `CRM-Avance-Corp/`, la migración (solo confirma si su sonda rechaza «ABC» con 22023; **por `db query --linked` el NOTICE no llega: sin error = la sonda rechazó**, y qué candidato concluyó solo se ve en la branch, por psql) y después su registrador (`db query` no registra la versión; el registrador exige el estado completo de `public.crear_contrato` y se niega si el nombre ya está con otra versión):
`supabase db query --linked --file supabase/migrations/20261009210100_crm_numero_contrato_servidor.sql` y
`supabase db query --linked --file supabase/scripts/numero-contrato-servidor/registrar/20261009210100.sql`.

## Qué prueba

La regla de Miguel (decisiones D-11/Q3, D-12/Q3b, D-16 y D-17, 2026-10-06/07): `public.crear_contrato` rechaza cualquier número
de contrato que no sea `2024-01-NNNNNN`, `2025-01-NNNNNN` o `2026-01-NNNNNN` (seis dígitos ASCII), incluido el vacío, un espacio o
la ausencia de la clave, con SQLSTATE `22023` y el mensaje «Formato de número de contrato inválido: serie 2024-01-, 2025-01- o
2026-01- seguida de exactamente 6 dígitos», en vez de inventar `AC-AAAA-NNNN`; por **cualquier** entrada (la llamada directa a la
API como `authenticated` y las puertas `crm.*` que la envuelven). La única excepción es quien es a la vez admin o superadmin del
Portal **y** Gerencia del CRM (`public.es_admin()` y `private.es_gerencia_crm_activa()`): conserva el comportamiento de hoy
(autogenera si va vacío; acepta cualquier número no duplicado). El duplicado conserva su error de siempre (`P0001`).

| Caso | Qué exige |
|---|---|
| 1 | Llamada **directa** a `public.crear_contrato` como vendedor (`VEND1`) y como la `gerencia` histórica del banco (`comercial+gerencia`, **no exenta**) con **24** números malos (`b01`…`b18`, con las variantes `b03b`, `b03c`, `b09b`, `b11b`, `b11c`, `b12b`; los 11 que pedía el encargo están todos): sin clave, `''`, `' '`, solo tabulador, JSON `null`, `ABC`, `2026-01-12`, `2027-01-000009`, 5 y 7 dígitos, dígitos arábigo-índicos (y mezcla), `AC-2026-0001`, válido con salto de línea final/inicial o tabulador final, basura delante/detrás (y un dígito delante), serie 2023, `-02-`, mes de un dígito, una letra, dos números ⇒ `22023`, mensaje exacto, sin pista. Si el literal del banco ya existe en el laboratorio se usa una variante de la misma forma (lo dice la `medida 0`). |
| 2 | Lo mismo por `crm.crear_contrato_con_cuenta_pdf_v2` (vendedor: los 24; Gerencia histórica: sin clave, vacío, `ABC`). |
| 3 | Tras cada rechazo, la **foto** (contratos por id y número, cronograma, titulares, operaciones de cartera, cuentas bancarias, vínculos cuenta-contrato, inversiones, libro de rentabilidad, jobs de PDF, altas idempotentes) es idéntica; y lo que la llamada hubiera dejado se deshace para que el caso siguiente no choque con un duplicado. |
| 4 | Positivos: `2024-01-000000`, `2025-01-123456`, `2026-01-000009`, `2026-01-999999`, un valor con espacios alrededor (se recorta), la Gerencia histórica y un admin sin ficha con número válido; por la puerta `crm` las tres series y el recortado (con cuenta vinculada). Lo diferido sobrevive al `COMMIT` (`set constraints all immediate`). Duplicado de un número válido ⇒ `P0001` «El N de contrato … ya existe» (directa y `crm`). |
| 4b | **Renovación y upgrade** sobre contratos históricos `AC-2025-0777`/`AC-2025-0778` (sembrados con los triggers apagados): el contrato NUEVO sin número o con `ABC-R1` se rechaza (directa y `crm`, vendedor de la cartera); con número válido entra y el histórico **conserva su número `AC-…`** (y queda `renovado` con su operación de cartera). |
| 5 | **Exento (D-17):** `ger_admin` (admin+gerencia) y `ger_super` (superadmin+gerencia): sin clave, vacío y espacio ⇒ autogenera exactamente el `AC-AAAA-NNNN` que toca (calculado aparte, como GCAR-C18); `ABC-X1`/`ABC-X2` ⇒ aceptados; también por la puerta `crm`. La exención **no** salta el duplicado (`P0001`). Negativos: la `gerencia` histórica, `admin` sin ficha, `superadmin` puro, vendedor y supervisor ⇒ rechazados con la regla; sin sesión de usuario ⇒ `42501` de siempre (muere antes de la guarda). Inválido y además duplicado (`ABC-DUP`, sembrado por el exento) ⇒ gana la **forma**. Las dos mitades de la excepción medidas por sesión (`medida 5-pares`). |
| 6 | **Idempotencia:** repetir por `pdf_v2` con la misma clave devuelve lo guardado (`idempotente: true`, mismo id y número) sin cambiar la foto; y si el exento pierde la exención entre el alta y la repetición (se degrada a `comercial` dentro de un bloque que se deshace) la repetición sigue devolviendo lo guardado aunque su número autogenerado ya no pasaría, mientras un alta NUEVA con `ABC-ID` se rechaza. |
| 7 | Mediciones del banco: con qué usuario corren N1, N1b-1…4, N2, N3, N4–N8 (`VEND1`, no exento); `K.numero()` reproducida con `P8_BLOCK` de un carácter (`1`, `9`) y de dos (`10`) y con `n` = 1, 99999 y 100000; y que en este Postgres `\d` casa un dígito arábigo-índico y `[0-9]` no (por eso la regla usa `[0-9]`). |
| 9 | Catálogo: `public.crear_contrato` conserva dueño `postgres`, `security definer`, `search_path` vacío y la ACL exacta (`postgres`, `authenticated`, `service_role` con EXECUTE **sin opción de concesión**; `anon` sin EXECUTE); huellas intactas de `private.siguiente_numero_contrato`, `public.actualizar_numero_contrato`, `crm.actualizar_numero_contrato_pdf_v3`, `crm.crear_contrato_con_cuenta[_pdf_v2]`, `public.es_admin`, `private.es_gerencia_crm_activa`, `private.rol_crm` y `private.puede_registrar_ventas`; y las dos huellas de la función (`medida 9c`). |

## Por qué así

El ensayo no prueba una copia de la función: pega la **migración real** (preflight, postflight y comentario incluidos) dentro de
la transacción. Si alguien toca la migración, el oráculo prueba lo tocado.

Para montar un alta válida se usa lo mismo que `supabase/scripts/test-crear-contrato-cartera.sql` (capital 500, PEN, tasa 15,
mensual, simple, hoy / hoy+365, una cuota) con los actores reales del banco (`PASO08 …`), **obligatorios**: si falta uno o no es el
par declarado (rol del Portal + rol del CRM), el ensayo aborta (`ENSAYO ABORTADO`), no pasa en verde. La identidad se fija en las
DOS formas de los claims (`request.jwt.claim.sub` y `request.jwt.claims`); no se usa `set role` (llamar bajo `set role` a una
función sin EXECUTE tumba el Postgres del banco): los permisos se leen del catálogo (caso 9).

## Cómo se corre

Desde `CRM-Avance-Corp/`. `EJECUTAR_SQL` es el comando que manda un archivo `.sql` al banco local (la herramienta del laboratorio
`fase-2/bloque-2.1/herramientas/lab_sql.py`, que compara una huella de la base antes y después y sale con 9 si algo quedó
escrito). Los SQL generados van a una carpeta de trabajo, no al repo.

```bash
# 1. ROJO: el oráculo SIN la migración. Es la medición del defecto.
node supabase/scripts/numero-contrato-servidor/armar-ensayo.mjs --sin-migracion > "$SALIDAS/rojo.sql"
$EJECUTAR_SQL "$SALIDAS/rojo.sql"
#    → ENSAYO ROJO — 95 fallo(s): 93 «el servidor ACEPTÓ el número (guardó o autogeneró «…»)» más «inválido y además duplicado»
#      (hoy gana el duplicado) y «exento degradado: un alta nueva con ABC-ID no se rechazó». Nunca un error de montaje.

# 2. VERDE: la migración real + el oráculo. Termina SIEMPRE en excepción: eso es el veredicto.
node supabase/scripts/numero-contrato-servidor/armar-ensayo.mjs > "$SALIDAS/verde.sql"
$EJECUTAR_SQL "$SALIDAS/verde.sql"
#    → ENSAYO VERDE — 0 fallos (129 comprobaciones «ok» y las medidas 5-pares, 0, 7a, 7b, 7c y 9c)

# 3. Los mutantes: rompen una defensa DESPUÉS de la migración y exigen que el oráculo lo grite nombrando su fallo.
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/mutantes" bash supabase/scripts/numero-contrato-servidor/mutantes.sh
#    → MUTANTES: los 22 mutantes de verdad murieron, cada uno por su fallo; 1 equivalente confirmado.

# 4. Las derivas previas: rompen el catálogo (o dejan la base sin candidatos para la sonda) ANTES de la migración y exigen que
#    se niegue sin dejar rastro (en el preflight; las de la sonda, en el postflight). Una deriva (D22) tiene que dejarla ENTRAR:
#    solo el primer candidato de la sonda no es concluyente, y la sonda concluye con el segundo.
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/derivas" bash supabase/scripts/numero-contrato-servidor/derivas.sh
#    → DERIVAS: las 21 abortan (preflight, o postflight las dos de la sonda) y no dejan rastro; la deriva 22 (primer candidato
#      no concluyente) ENTRA y su NOTICE nombra al candidato 2; el control entra; los tres mutantes (dos del preflight, uno
#      del postflight) mueren.

# 5. La reversa: aplicar → revertir → la función vuelve a ser la de antes.
node supabase/scripts/numero-contrato-servidor/armar-ensayo.mjs --reversa > "$SALIDAS/reversa.sql"
$EJECUTAR_SQL "$SALIDAS/reversa.sql"
#    → REVERSA VERDE: prosrc 1adfbe1a…, definición dce8f0dd…, ficha idéntica (definición, dueño, ACL, configuración y comentario).

# 6. La reversa con un SET añadido después de migrar: tiene que ABORTAR y no dejar rastro (falla cerrada).
node supabase/scripts/numero-contrato-servidor/armar-ensayo.mjs --reversa-con-set > "$SALIDAS/reversa-con-set.sql"
$EJECUTAR_SQL "$SALIDAS/reversa-con-set.sql"
#    → REVERSA CON SET VERDE: la reversa ABORTÓ («no tiene exactamente la definición que dejó la migración»); foto IGUAL, SET conservado.

# 7. Los trinquetes: la foto de los 36 private.assert_*() y del censo analítico, con la migración puesta, para compararla con la de antes.
node supabase/scripts/numero-contrato-servidor/armar-ensayo.mjs --trinquetes > "$SALIDAS/trinquetes.sql"
$EJECUTAR_SQL "$SALIDAS/trinquetes.sql"
```

El ensayo se arma para una base que **todavía no tiene** la migración: su preflight exige las huellas anteriores de la función
(`md5(prosrc)` `1adfbe1a…`, `md5(pg_get_functiondef)` `dce8f0dd…`). En una base que ya la tiene, el oráculo se corre solo
(`--sin-migracion`) y entonces tiene que salir VERDE.

## Qué hay aquí

| Archivo | Qué es |
|---|---|
| `armar-ensayo.mjs` | Pega migración + oráculo en una transacción con `rollback`. Modos: `--sin-migracion`, `--mutante <archivo>`, `--reversa`, `--reversa-con-set`, `--deriva <archivo> [--espera "<texto>"]` (la línea `-- @@MIGRACION@@` del archivo se sustituye por la migración: deriva «ya aplicada»), `--trinquetes [--sin-migracion]`; modificador `--migracion <ruta>` (otra migración, para mutar el preflight). Se niega si queda un `commit` suelto. |
| `pruebas.sql` | El oráculo (casos de arriba). Actores del banco **obligatorios**; cada rechazo fotografía antes y después y deshace lo que la llamada hubiera dejado. |
| `mutantes.sh` | 23 mutantes: 22 de verdad (17 de cuerpo y 5 de catálogo; la lista está en el propio guion) y 1 **equivalente** («la excepción no exige sesión»: sin sesión la función ya murió con `42501` en `puede_registrar_ventas()`; la guarda nunca ve una sesión nula). Cada uno solo cuenta como muerto si el ensayo sale ROJO **y nombra los fallos que le corresponden**; «guarda solo en la puerta crm» exige además que los fallos de la puerta `crm` NO aparezcan. |
| `derivas.sh` | Veintidós derivas instaladas ANTES de la migración: 12 de la ronda 1 (cuerpo, `SET`, INVOKER, `anon`, `WITH GRANT OPTION`, `service_role` sin EXECUTE, comentario, cuerpo de los cuatro helpers, migración ya aplicada), 9 de la ronda 2 (la **ficha** de un helper sin tocar su cuerpo: `private.rol_crm` IMMUTABLE, otro `search_path`, `WITH GRANT OPTION` sobre un helper de `private`, otro dueño, `public.es_admin()` INVOKER, PARALLEL SAFE; `assert_f7_piezas_cerradas` ausente; base sin ningún candidato vendedor–cliente para la sonda; **ningún candidato concluyente**: todos los clientes sin documento, cada candidato muere antes de la guarda con `P0409` y el mensaje los enumera) y 1 de la ronda 3 que tiene que dejar **entrar** a la migración (solo el **primer** candidato de la ordenación pierde el documento: la sonda lo descarta, concluye con el segundo y el `NOTICE` dice «candidato 2 de 2» y la causa del descartado), un control sin deriva y **tres mutantes**: dos del preflight (sin comparar `is_grantable`, la deriva `WITH GRANT OPTION` tiene que colarse; sin comparar la ficha de los helpers, la deriva IMMUTABLE tiene que colarse) y uno del postflight (una sonda que **no itera**, `limit 1`, tiene que abortar con la deriva «primer candidato no concluyente»). El cambio de dueño de `public.es_admin` no es ensayable en el laboratorio (`postgres` no es dueño de `public`): se ensaya sobre un helper de `private`, con la misma comparación. |
| `candidatos-sonda.sql` | **Solo lectura** (una SELECT; F4.1-A ronda 5). Los 5 primeros pares vendedor–cliente que probaría la sonda del postflight (misma selección y orden) y si cada uno concluiría o moriría antes de la guarda (identidad unificada: sin documento, documento inválido, documento de otra persona); la última fila dice con cuál concluiría o que la migración se negaría. Para la branch antes de aplicar y para producción en F4.7. |
| `generar_registrador.py` · `registrar/20261009210100.sql` | El registrador (`db query --file` no registra la versión): exige el estado completo de `public.crear_contrato` (cuerpo, definición, ficha, ACL, EXECUTE efectivo y comentario), se niega si el nombre ya está con otra versión o la versión con otro contenido; idempotente; la migración incrustada una vez. Regenerarlo si cambia la migración. |
| `reversa.sql` | Quita el bloque de la guarda del cuerpo vivo (ancla única) y repone el comentario. **Falla cerrada:** exige `md5(prosrc)` `dee13ad8…` y `md5(pg_get_functiondef)` `6e5a0154…` (los que deja la migración). No deshace datos. |

## Preflight y postflight fail-closed (rondas 2 y 3) y runbook del branch

- **Preflight:** además de `public.crear_contrato` (huellas, ficha con `is_grantable`, comentario), fija los cinco helpers de la
  excepción y del autogenerado (`public.es_admin`, `private.es_gerencia_crm_activa`, `private.rol_crm`,
  `private.puede_registrar_ventas`, `private.siguiente_numero_contrato`) por `md5(prosrc)` **y por su ficha completa** (dueño,
  DEFINER, volatilidad, modo paralelo, `proconfig`, ACL con opción de concesión; valores medidos en el laboratorio el 07/10/2026),
  y exige que **existan** `private.assert_analista_vigencia()` y `private.assert_f7_piezas_cerradas()`.
- **Postflight:** las mismas fichas intactas; los dos `assert_*` existen y dan exactamente lo mismo que antes; y la **sonda es
  gate** y prueba **hasta 5 candidatos** (vendedor activo —`comercial` en el Portal, `vendedor` activo en `crm.equipo`— × cliente
  activo de su cartera, en orden determinista vendedor, cliente): cada uno manda `ABC` por `public.crear_contrato` dentro de su
  propia subtransacción, que siempre se deshace, y la sonda se detiene en el primer resultado concluyente. «RECHAZADO con 22023 y
  el mensaje fijado» ⇒ pasa; «ACEPTÓ» ⇒ la migración aborta; «no concluyente» (la llamada murió antes de la guarda, p. ej. cliente
  sin documento) ⇒ siguiente candidato. Si **ningún** candidato es concluyente, o no hay candidatos, la migración **se niega** y el
  mensaje enumera cada candidato probado con su causa y dice exactamente qué preparar. El `NOTICE` final dice qué candidato
  concluyó, cuántos se probaron y cuáles se descartaron (por psql; por `supabase db query --linked` no llega). La sonda ejecuta código de negocio real sobre filas reales, pero nada
  queda escrito.
- **Runbook del branch:** la migración solo confirma si la sonda dice «RECHAZADO con 22023 y el mensaje fijado». Por psql se lee
  en el `NOTICE`; **por `supabase db query --linked` el `NOTICE` no llega: sin error = la sonda rechazó** (si acepta o no concluye,
  la migración aborta con un error que lo dice); el detalle del candidato solo se ve en la branch. Antes de aplicar,
  `candidatos-sonda.sql` (solo lectura) lista los 5 pares y si concluirían. Si se niega, leer la lista de candidatos y causas del mensaje: **la única salida es preparar en el branch un vendedor
  activo con un cliente activo con documento en su cartera y volver a aplicar la migración.** Este oráculo con `--sin-migracion`
  y la prueba HTTP N1/N1b del banco son **diagnósticos**: miden la función que haya en la base (tras un aborto, la **anterior**) y
  **no sustituyen una migración abortada ni desbloquean el gate**. Y **antes de adaptar nada**, correr
  `npm run test:rls:preflight` tal como está para medir el ROJO real del gate.

## Para quien integre (hallazgos del auditor de permisos, ronda 2)

- **El gate `supabase/scripts/test-rls.mjs` queda ROTO tras la migración** (no se toca aquí; adaptación en la fase 4): `payloadIdem`
  (`:5507-5543`) arma `numero_contrato` libre `RLS-IDEM-…` y lo usan altas positivas de `vend1` (no exento) en `:5543, 5564, 5602,
  5612, 5619, 5637, 5664-5665, 5695`, con negativos que dependen de ellas en `:5558, 5576, 5590, 5631`; el caso `:5119-5137`
  (directorio-como-analista, sin número) espera `23514` y recibirá `22023`. Adaptación: `payloadIdem` con `2026-01-` + 6 dígitos
  aleatorios sin colisionar con `990001`/`990002` (`BANK_CONTRACT.number` SÍ es válido) y el caso 5119 con un número válido; más
  los 8 casos nuevos de la regla (en el informe del bloque).
- **El exento sigue generando `AC-AAAA-NNNN`** (deuda de datos de D-17, no de seguridad): la pantalla del CRM no admite ese
  formato (`app/src/lib/contratos-catalogo.ts`) hasta el paso aparte de `public.actualizar_numero_contrato` (D-16). El duplicado
  explícito que mete el exento lo detecta el `if exists` sin serializar, respaldado por el UNIQUE `contratos_numero_contrato_key`
  de `public.contratos.numero_contrato` (del portal; comprobado en el laboratorio).

## Límites conocidos (lo que este ensayo NO garantiza)

1. **La llamada «como `authenticated`» se hace con la identidad en los claims, no con `set role authenticated`.** Que `anon` no
   tenga EXECUTE y que `authenticated`/`service_role` sí lo tengan se lee del catálogo (caso 9a), nunca llamando bajo `set role`.
   La prueba por PostgREST con sesiones reales es la del banco (`laboratorio/paquete-paso08/42_fila2_inversion.py`, casos N1 y N1b).
2. **Un mutante es EQUIVALENTE y no se puede matar:** «la excepción no exige sesión de usuario». `private.puede_registrar_ventas()`
   exige `auth.uid()` (la función rechaza con `42501` antes de la guarda) y `public.es_admin()` da falso sin uid: no hay camino por el
   que la guarda vea una sesión nula. El ensayo lo confirma (sigue VERDE) y lo mide (`5n-sin-sesion`, directa y `crm`).
3. **Los mutantes de catálogo (INVOKER, `search_path`, ACL) mueren solo por el caso 9a**, no por un cambio de comportamiento: en
   el laboratorio todo corre como `postgres`, dueño de la función, así que INVOKER y DEFINER se comportan igual.
4. **La exención deja un hueco permanente para el par admin/superadmin + Gerencia** (riesgo señalado en D-17): el ensayo lo prueba
   por los dos lados, pero no lo cierra.
5. **Los literales del banco (`ABC`, `2026-01-12`, `2027-01-000009`, `AC-2026-0001`) ya existen en este laboratorio** como restos de
   la fila 2 del banco: el oráculo usa variantes de la misma forma (`medida 0`) para que el rechazo medido sea el de la forma y no
   el de «ya existe». El caso «inválido y además duplicado» se mide aparte.
6. **La serie 2027 no está** (D-12): en enero de 2027 el servidor bloquea las altas hasta que Miguel la pida (tope 15/12/2026).

## La reversa, con exactitud

- **Falla cerrada.** Exige que `public.crear_contrato` tenga EXACTAMENTE la definición que dejó la migración (`md5(prosrc)` y
  `md5(pg_get_functiondef)`). Si alguien cambió el cuerpo **o un atributo** después (p. ej. `ALTER FUNCTION … SET lock_timeout`),
  **se niega** y no toca nada. Ensayado con `--reversa-con-set`.
- **Qué restaura:** el cuerpo anterior (`1adfbe1a…` / `dce8f0dd…`), quitando el bloque de la guarda (comentario + `if … end if;`)
  que la migración insertó delante de la rama de autogeneración, y el comentario anterior. El postflight lo exige.
- **Qué conserva:** firma, dueño, `security definer`, `search_path` vacío y ACL.
- **No deshace datos:** la guarda solo rechazaba. Tras revertir, el servidor vuelve a autogenerar y a aceptar cualquier número no
  duplicado: es el defecto que la migración cerraba.
- **La fila de `supabase_migrations.schema_migrations` se conserva** (regla de la casa, como en `scripts/categoria-sin-operacion/LEEME.md`): la reversa no la toca; se anota en `MIGRACIONES.md` con fecha, motivo y su salida (F4.1-A ronda 5, auditor r2 P3-7).

## Trampas encontradas al escribirlo

- **`btrim` solo recorta espacios:** un tabulador o un salto de línea sobreviven al recorte y llegan a la guarda (que los rechaza).
  En ARE, `$` no casa antes de un salto de línea final: «válido + `\n`» se rechaza.
- **`\d` casa dígitos no ASCII en este Postgres** (`medida 7c`): la regla usa `[0-9]`. El mutante M8 lo demuestra.
- **El exento autogenera `AC-2026-NNNN`, y el laboratorio ya tiene `AC-2026-…`:** el número esperado se calcula aparte con la misma
  regla que `private.siguiente_numero_contrato` (como hace GCAR-C18).
- **`set_config('session_replication_role', …)` está denegado y `SET LOCAL session_replication_role = replica` no** (rol
  `postgres` del laboratorio): la siembra de los históricos usa la sentencia.
- **Los gates del banco no están todos verdes:** de los 36 `private.assert_*()`, 7 caen desde antes por trabajos ajenos (entre
  ellos `assert_analista_vigencia`). Lo que se exige es que la foto de los 36 y el censo NO cambien con la migración puesta
  (`--trinquetes`), y el postflight de la migración exige que `assert_analista_vigencia()` y `assert_f7_piezas_cerradas()` den
  exactamente lo mismo que antes.
