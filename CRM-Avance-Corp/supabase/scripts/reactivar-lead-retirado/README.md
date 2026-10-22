# Ensayo de «Registrar a una persona con lead retirado reactiva su ficha»

Verifica la migración `20261022170200_crm_alta_reactiva_lead_retirado.sql` **en el banco Docker local (el laboratorio) y sin
escribir nada**. Este ensayo **no se corre contra producción**: da de alta leads de verdad con los actores del banco por la puerta
real `crm.crear_lead_si_disponible` (y por `crm.crear_lead_documento_fn`), los retira como lo hace Gerencia por API
(`UPDATE activo = false` con su sesión) y vuelve a registrar a la misma persona, siempre dentro de una transacción que termina en
`rollback`.

## Qué prueba

La regla de Miguel (decisiones D-11/Q1, D-15, D-17 y D-21, 2026-10-06/07; plan AVANCE-BACKEND-0710-P1, bloque 2.4): si alguien
registra a mano a una persona cuyo lead fue **retirado** (`crm.leads.activo = false`, no convertido, sin veto) y ningún lead
**activo**, veto ni identidad coincide con lo tecleado **ni con lo que esa ficha conserva**, el alta **reactiva esa misma ficha** a
nombre del destino del alta (el vendedor que se autoasigna, la bandeja del supervisor, el analista que elige Gerencia, o la cola
global si Gerencia no elige) y responde `{estado:'reutilizado', lead_id}` en vez de crear un segundo lead. También cuando el
verificador dice «enfriamiento» y su único causante es un retirado (D-15: sin esperar la espera ni la carencia de 24 h). Se
conservan los datos de la ficha (un retirado de base cargada sin capital toma el capital tecleado); lo tecleado va a la actividad
de rastro (`evento = 'reactivacion_alta'`, con `id = p_id` del alta: un reintento con el mismo id no repite). Un retirado
**enlazado a persona** bloquea («ya es cliente») también cuando solo se tecleó el teléfono (D-21). Un lead activo del mismo
contacto tecleado, un convertido y «no contactar» siguen exactamente como hoy; nadie gana permisos.

**Ronda 2** (revisión de Codex C-1…C-5 y del auditor A-1…A-8, `fase-2/bloque-2.4/revision/CONCILIACION.md`): los casos marcados
«(r2)». **Ronda 3** (validación de Codex R2-1/R2-2 y del auditor AR2-1, `fase-2/bloque-2.4/revision/CONCILIACION-R2.md`): los
marcados «(r3)». **Ronda 4** (validación de Codex R3-1, `fase-2/bloque-2.4/revision/CONCILIACION-R3.md`): los marcados «(r4)»:
**un reintento con rastro previo nunca crea otra ficha.** **Ronda 5** (validación de Codex R4-1, `fase-2/bloque-2.4/revision/CONCILIACION-R4.md`):
los marcados «(r5)»: **el paso 3a del núcleo nunca devuelve nulo en un reintento** (garantía completa: un reintento con rastro previo
nunca llega al INSERT; ficha original, dato conservado, lead activo por lo tecleado y veredicto fresco nulo quedan cubiertos).

| Caso | Qué exige |
|---|---|
| 1 | Retirado en etapa operativa (`contactado`, de VEND1, sin enlace); VEND2 registra la misma persona por teléfono y DNI ⇒ `reutilizado` con el **mismo `lead_id`**, `activo = true`, dueño VEND2, etapa y ciclo iguales, **un solo lead** por teléfono y por DNI, actividad `reactivacion_alta` con `id = p_id`, firmada por VEND2, con `propietario_anterior` = VEND1, `etapa_anterior`, **`activo_anterior = false`** (r2, C-4) y `otro_retirado` booleano sin id ajeno (r2, A-8). |
| 4 | El ledger de asignaciones abre el episodio **`reactivado`** para el dueño nuevo (medida: en un retirado que venía de `descartado` el trigger lo abre como `reabierto`, porque reabrir tiene prioridad en `private.trg_leads_asignaciones`; el rastro contractual de D-15 es la actividad + el episodio). |
| 5 | La ficha conserva nombre, correo y capital; de lo tecleado quedan en la actividad **solo** capital, moneda, origen y tipo de documento (r2, A-7) y la nota en el detalle; **nada** de nombre, correo, teléfonos, documento, género ni fecha de nacimiento, ni en claro ni en el `metadata`. |
| 6 | Idempotencia: el mismo `p_id` con la misma huella ⇒ misma respuesta, sin segunda actividad ni segundo cambio; el mismo `p_id` con otro payload, otro vendedor u **otro supervisor con el mismo payload** ⇒ `22023`. **C-2 (r2):** el mismo `p_id` con **otro teléfono** ⇒ `22023` (nunca «reutilizado» con la ficha de otro contacto). **6e/6f (r2, A-1):** la huella **no depende del DNI** (otro DNI con el mismo `p_id` es el mismo alta y no altera nada) pero sí del **tipo de documento** (sin DNI tecleado ⇒ `22023`). **A-6 (r2):** el reintento solo confirma una ficha que **sigue activa**: si Gerencia la retiró otra vez, el mismo `p_id` la reactiva de nuevo (su rastro lleva otro id con `alta_id = p_id`) y un tercer reintento repite sin cambios. **R2-1 (r3):** con **dos retirados del mismo teléfono** (el otro, más reciente por `actualizado_en`), el reintento tras el segundo retiro reactiva **la ficha del primer rastro** (mismo `lead_id`), la otra queda intacta y sin rastro, hay un solo lead activo del número, y un tercer reintento repite sin cambios. |
| R3-1 (r4) | **Un reintento con rastro previo nunca llega al INSERT.** Si la ficha del primer rastro ya no se puede reactivar, el núcleo responde un veredicto bloqueante y **nunca nulo** (nulo dejaría que el alta insertara OTRA ficha con el mismo `p_id`): **(a)** ficha retirada y **convertida** (sembrada sin triggers, como 3d) con el verificador en `libre` ⇒ `ya_es_cliente` en el formato del verificador, a nombre del tenedor de la ficha y sin `via`; nada escrito, un solo lead por teléfono y por DNI, sin segundo rastro. **(b)** ficha **inexistente** (borrada dentro del rollback con los disparadores apagados; el rastro con `id = p_id` sigue) ⇒ `22023` «el alta original ya no existe: registra de nuevo con un identificador nuevo» y ningún lead con ese contacto. **(c)** ficha retirada y **vetada** (veto sembrado sin triggers) ⇒ `no_contactar` (lo da ya el verificador por el teléfono; el núcleo lo garantiza también si no lo viera), ficha intacta, un solo lead. Enlazada a persona ⇒ el juicio de identidad (`via = identidad`), solo alcanzable con la bandera apagada (sin caso, declarado). |
| R4-1 (r5) | **El paso 3a nunca devuelve nulo en un reintento.** Reintento con el mismo `p_id` sobre la ficha del primer rastro (retirada otra vez) cuando **otro lead activo coincide con lo tecleado** y el verificador no lo califica: un **descartado activo de 0 días (`pide_credito`) dentro de sus 24 h**, a nombre de VEND1, sembrado sin triggers (con la regla instalada la puerta real reactivaría la ficha retirada; los índices vivos no cubren descartados), con el mismo teléfono y DNI tecleados; el verificador dice `libre` (la carencia es solo para tomar) ⇒ `tomado` nombrando a VEND1 (o `en_bolsa` si el descartado no tuviera tenedor), en el formato exacto del verificador; nada escrito: la ficha retirada y el descartado activo intactos, los mismos leads con ese teléfono que antes del reintento, sin segundo rastro. (Con el núcleo de la ronda 4: `creado` y tres leads con el teléfono —el reintento llegó al INSERT con el mismo `p_id`—.) Fuera del reintento, 3a sigue devolviendo nulo (3a/3b). Convertido activo sin identidad en un reintento ⇒ `22023` «el alta original ya no se puede repetir: hay otro lead activo con ese contacto» (sin caso, declarado). |
| 2 | Retirado + `descartado` con la **espera sin vencer** (`sin_fondos`, 90 días; el verificador dice `enfriamiento`) ⇒ se reactiva igual: etapa `nuevo`, ciclo 2, sin motivo ni sello de descarte. **2b**: motivo de 0 días (`pide_credito`) dentro de las 24 h ⇒ se reactiva sin esperar. |
| 3 | **Negativos que no cambian** (ficha retirada intacta byte a byte y la respuesta de hoy): 3a lead activo operativo del mismo contacto junto a un retirado ⇒ `tomado`; 3b descartado **activo** con la espera vigente junto a un retirado ⇒ `enfriamiento`; 3c retirado **enlazado a persona** ⇒ `ya_es_cliente` con el DNI **y también con solo el teléfono** (r2, D-21: `via = identidad`, un solo lead); 3d **convertido** retirado ⇒ `creado` (lo de hoy); 3e retirado con «No contactar» ⇒ `no_contactar`; 3g el veto de **otro** lead del mismo número manda ⇒ `no_contactar`; **3h (r2)** el veto asociado **solo al DNI que conserva la ficha** (W vetado y retirado con el DNI A; retirado sin veto con otro teléfono y el DNI A; alta solo con ese teléfono) ⇒ `no_contactar`; **3i (r2)** el veto de otro lead que casa solo por el DNI **tecleado** ⇒ `no_contactar` (la rama no se salta el veredicto). 3f (medida) el par L9 del banco ⇒ `tomado`. |
| C-1 (r2) | Un lead **activo** que coincide con un dato **conservado** por la ficha retirada, no con lo tecleado: **C-1a** activo `(U, A)` en la bolsa + retirado `(T, A)`, alta `(T, B)` ⇒ `en_bolsa`; **C-1b** activo `(T, —)` de VEND1 + retirado `(T, A)`, alta `(V, A)` ⇒ `tomado` nombrando a VEND1. Siempre: un solo lead por contacto, nada escrito, ficha intacta; el veredicto en el **formato exacto del verificador** (el contrato de la app es estricto). **B1 (r3):** un **convertido activo** (sin enlace ni perfil, sembrado sin triggers) que casa solo por el DNI conservado ⇒ `ya_es_cliente` (el verificador decía `libre`). **B2 (r3):** un **descartado activo de 0 días dentro de sus 24 h** que casa solo por el DNI conservado ⇒ `tomado` nombrando a VEND1 (o `en_bolsa` si el descarte lo dejó sin tenedor; el verificador decía `libre`). |
| AR2-1 (r3) | D-21 por la letra, con la **bandera `resolver_en_puertas` apagada** (se apaga y se vuelve a encender dentro del rollback; su trigger toma el candado exclusivo, reentrante para la misma sesión): tecleado `(T, A)`; R1 `(T, sin DNI, no enlazado)` retirado; R2 `(U, A, enlazado a P)` retirado ⇒ el verificador dice `libre` (su bloque por identidad está gateado) y el núcleo responde `ya_es_cliente` con `via = identidad`; R1 y R2 intactos, un solo lead con `T`. |
| R2-2 (r3) | Solo el CHECK `leads_monto_estimado_valido` es «veredicto fresco»: un **23514 ajeno** nacido del UPDATE de la reactivación (fixture: la restricción `ens_23514_ajeno`, sembrada `NOT VALID` al **empezar** el oráculo —antes de cualquier escritura en `crm.leads`— y que solo viola una ficha «FICHA CHECK 23514» activa a nombre de VEND2) se **propaga** al llamador: `23514` con el nombre de la restricción ajena, ficha intacta, un solo lead por contacto. |
| 4b/4c/4d | SUP1 registra sin analista ⇒ la ficha va a **su bandeja** (sin episodio abierto); Gerencia elige a VEND3 ⇒ dueño VEND3 con episodio; dos retirados (uno por teléfono, otro por DNI) ⇒ manda el del **teléfono**, el otro queda retirado, la respuesta trae `aviso` y el rastro `otro_retirado = true` (sin id). **4d-replay (r2, C-3):** el replay repite el `aviso`. **4e (r2):** Gerencia **sin destino** ⇒ cola global (sin vendedor ni bandeja, sin episodio), etapa y ciclo conservados. **4f (r2):** un retirado en `reunion_agendada` conserva la etapa. |
| 8 | Coordinador, membresía inactiva y admin sin rol CRM ⇒ `42501` y ficha intacta; después VEND2 sí la reactiva. |
| 9 | Por `crm.crear_lead_documento_fn`: con **CE** ⇒ `reutilizado` y la ficha **no** recibe documento ni enlace, y no nace ninguna identidad; con DNI, igual que el alta directa. (Medida, declarado: el tipo y el número de CE no llegan al alta, por eso el rastro lleva `tipo_documento = null` y el replay con **otro** número de CE se trata como el mismo alta.) |
| C-5 (r2) | Solo `uq_leads_telefono_vivo` y `uq_leads_dni_vivo` son «carrera de contacto»: un 23505 **ajeno** nacido del UPDATE (índice único temporal del ensayo sobre dos retirados homónimos, que solo afecta a filas activas con ciclo ≥ 2) se **propaga** al llamador, la ficha queda intacta y hay un solo lead por contacto. |
| A-2 (r2) | Retirado de **base cargada** (origen y motivo `base_cargada`, descartado, **capital vacío**) ⇒ `reutilizado`, `nuevo`, ciclo 2, capital = el tecleado, origen intacto. Necesita el esquema B7 (abajo, «Fixture B7»). |
| 7 | **NO EJECUTADO** con dos conexiones (una sola sesión, sin credenciales para otra). Se mide por el cuerpo: el núcleo toma la fila del retirado con `for update;`. |
| 10 | Catálogo: el alta conserva dueño `postgres`, DEFINER, `search_path` vacío, `lock_timeout` y la ACL exacta; el núcleo `private.alta_reactivar_retirado` **y su pieza `private.alta_reactivar_bloqueo_conservado`** (r2) son DEFINER de `postgres`, `search_path` vacío y EXECUTE **solo** para `postgres`; el verificador conserva `md5(prosrc)` y la huella **compuesta** que fija la carga de bases; huellas intactas de las puertas y piezas que no se tocan; **10f (r2, A-5):** el núcleo exige `p_actor = auth.uid()` (actor ajeno ⇒ `42501`; propio con veredicto bloqueante ⇒ `null`). Huellas del alta, del núcleo y de la pieza en la medida 10e. |

## Por qué así

El ensayo no prueba una copia de la función: pega la **migración real** (preflight, postflight y comentario incluidos) dentro de
la transacción. Si alguien toca la migración, el oráculo prueba lo tocado.

Los fixtures nacen por la **puerta real** como VEND1 y se retiran con la sesión de Gerencia; los actores del banco (`PASO08 …`)
son **obligatorios** con su rol exacto (si falta uno, `ENSAYO ABORTADO`, nunca verde). Algunos fixtures se siembran con los
triggers apagados (`set local session_replication_role = replica`, como los contratos históricos del ensayo 2.3): el **retirado
junto a un lead activo del mismo contacto** (la puerta real ya no permite montarlo una vez instalada la regla: reactivaría), el
**convertido retirado sin persona** (convertir exige una inversión confirmada), el **retirado de base cargada sin capital** (nace
por la carga, no por el alta) y el **descartado activo de 0 días junto a la ficha retirada del mismo contacto** (r5: la puerta real
reactivaría la ficha en vez de crearlo). La identidad se fija en las DOS formas de los claims; no se usa `set role` (llamar bajo `set role` a
una función sin EXECUTE tumba el Postgres del banco): los permisos se leen del catálogo.

**Fixture B7 (ronda 2).** El laboratorio está en el corte B6 (`20261003162500`) y producción tiene B7 (`20261004160034`, aplicada
el 04/10/2026): `monto_estimado` admite nulo solo en un contacto de base cargada dormido, existen el origen y el motivo
`base_cargada` y el trigger `trg_leads_000_base_cargada_solo_puerta` los reserva a la carga. El caso A-2 solo existe con ese
esquema, así que `armar-ensayo.mjs` lo instala como fixture **extraído textualmente de la migración B7** (función del trigger,
trigger y el `ALTER TABLE crm.leads` de capital/origen/motivo), después de la migración y antes del oráculo, dentro de la misma
transacción con `rollback`. Si el laboratorio ya tuviera B7, el ensayo **aborta** (habría que quitar el fixture). En producción
están además B8–B10; sus versiones de `trg_leads_disponibilidad_atomica` y `trg_leads_sla_versionado` no se ensayan aquí (ver
límites).

## Cómo se corre

Desde `CRM-Avance-Corp/`. `EJECUTAR_SQL` es el comando que manda un archivo `.sql` al banco local (la herramienta del laboratorio
`fase-2/bloque-2.1/herramientas/lab_sql.py`, que compara una huella de la base antes y después y sale con 9 si algo quedó
escrito). Los SQL generados van a una carpeta de trabajo, no al repo.

```bash
# 1. ROJO: el oráculo SIN la migración. Es la medición del defecto.
node supabase/scripts/reactivar-lead-retirado/armar-ensayo.mjs --sin-migracion > "$SALIDAS/rojo.sql"
$EJECUTAR_SQL "$SALIDAS/rojo.sql"
#    → ENSAYO ROJO — 45 fallo(s): «1-reactiva: … estado=creado → creó un SEGUNDO lead de la misma persona; 2 lead(s) con el
#      teléfono … y 2 con el DNI», C-1a/C-1b (segundo lead por dato conservado), 3c (segundo lead de un enlazado), A-2, C-5,
#      R2-1, R2-2, AR2-1, R3-1a/b/c, R4-1… y los demás positivos; los negativos (3a–3i, 8, 10a/c/d) ya pasan. Nunca un error de montaje.

# 2. VERDE: la migración real + el oráculo. Termina SIEMPRE en excepción: eso es el veredicto.
node supabase/scripts/reactivar-lead-retirado/armar-ensayo.mjs > "$SALIDAS/verde.sql"
$EJECUTAR_SQL "$SALIDAS/verde.sql"
#    → ENSAYO VERDE — 0 fallos (66 comprobaciones «ok» y las medidas 0, 2, 2b, 3c, 3d, 3f, 4, 4d, 7, 9, A-2, C-1a/b, B1, B2,
#      AR2-1, R2-1, R2-2, R3-1a/b/c, R4-1 y 10e)

# 3. Los mutantes: rompen una defensa DESPUÉS de la migración y exigen que el oráculo lo grite nombrando su fallo.
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/mutantes" bash supabase/scripts/reactivar-lead-retirado/mutantes.sh

# 4. Las derivas previas: rompen el catálogo ANTES de la migración y exigen que su preflight se niegue sin dejar rastro.
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/derivas" bash supabase/scripts/reactivar-lead-retirado/derivas.sh

# 5. La reversa: aplicar → revertir → el alta vuelve a ser la de antes y el núcleo y su pieza desaparecen.
node supabase/scripts/reactivar-lead-retirado/armar-ensayo.mjs --reversa > "$SALIDAS/reversa.sql"
$EJECUTAR_SQL "$SALIDAS/reversa.sql"
#    → REVERSA VERDE: prosrc 54fc34f7…, definición d1daa1c6…, núcleo BORRADO, pieza BORRADA, ficha idéntica.

# 6. La reversa con un SET añadido después de migrar: tiene que ABORTAR y no dejar rastro (falla cerrada).
node supabase/scripts/reactivar-lead-retirado/armar-ensayo.mjs --reversa-con-set > "$SALIDAS/reversa-con-set.sql"
$EJECUTAR_SQL "$SALIDAS/reversa-con-set.sql"
#    → REVERSA CON SET VERDE: la reversa ABORTÓ («no tiene exactamente la definición que dejó la migración»); foto IGUAL.

# 7. Los trinquetes: la foto de los private.assert_*() y del censo analítico, con la migración puesta, para compararla con la de antes.
node supabase/scripts/reactivar-lead-retirado/armar-ensayo.mjs --trinquetes > "$SALIDAS/trinquetes.sql"
$EJECUTAR_SQL "$SALIDAS/trinquetes.sql"
```

El ensayo se arma para una base que **todavía no tiene** la migración: su preflight exige las huellas anteriores del alta
(`md5(prosrc)` `54fc34f7…`, `md5(pg_get_functiondef)` `d1daa1c6…`). En una base que ya la tiene, el oráculo se corre solo
(`--sin-migracion`) y entonces tiene que salir VERDE.
Si la base ya tiene además el bloque 2.7 (`20261022170300`), este armador no fija el modo del caso 3d (`ensayo.modo_2_7`, por defecto `sin`) y 3d cae a propósito: ese oráculo se arma con `node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --oraculo-24 --sin-migracion --modo-2-7 con` (README del 2.7, límite 1).

**Reselle C2** (22/10/2026; plan AVANCE-BACKEND-1310-C2, encargo C2-a): producción cambió el alta dos veces después de la auditoría (`20261015171407` Formulario 3: origen `formulario_3`; `20261016183308`: Supervisión registra sus propios referidos y se autoasigna) y le añadió al comentario la frase «F3 (15/10/2026)…». Las dos anclas del parche siguen apareciendo exactamente una vez y el cuerpo parcheado conserva esos cambios (el diff entre el cuerpo parcheado de antes y el de ahora es exactamente el diff de producción). Huellas nuevas: antes de la migración `145b30a3…`/`068d4d88…` (eran `54fc34f7…`/`d1daa1c6…`); después `30109c53…`/`e06eca23…` (eran `01ebf089…`/`94ec2bd7…`); el comentario que exige el preflight, el que deja la migración y el que repone la reversa conservan la frase F3. Las cifras de arriba que nombran las huellas viejas se leen con estas. En un laboratorio igual a producción (que ya tiene B7) el fixture B7 de este armador abortaba a propósito; desde la ronda 2 de C2-a (22/10) el armador ya no lo instala: exige que B7 esté (la guarda inversa, como el armador del 2.13). El oráculo no cambia.

## Qué hay aquí

| Archivo | Qué es |
|---|---|
| `armar-ensayo.mjs` | Pega migración + fixture B7 + oráculo en una transacción con `rollback`. Modos: `--sin-migracion`, `--mutante <archivo>`, `--reversa`, `--reversa-con-set`, `--deriva <archivo> [--espera "<texto>"]` (la línea `-- @@MIGRACION@@` del archivo se sustituye por la migración: deriva «ya aplicada»), `--trinquetes [--sin-migracion]` (sin fixture B7); modificador `--migracion <ruta>`. Se niega si queda un `commit` suelto. |
| `pruebas.sql` | El oráculo (casos de arriba). Actores del banco **obligatorios**; cada caso negativo compara la ficha retirada antes y después. |
| `mutantes.sh` | 36 mutantes: 28 de cuerpo (rama quitada; sin excluir activos tecleados ni conservados; ignorar el enfriamiento de un descartado activo; reactivar convertidos; dueño no cambiado; sin FOR UPDATE; sin rastro; sin idempotencia; reintento sin exigir actor / payload; ficha pisada; etapa siempre nuevo; el descartado no renace; la rama no filtra el veredicto; **C-1** la coincidencia conservada vuelve a devolver null; **C-2** huella sin teléfono; **C-5** captura cualquier 23505; **D-21** el enlazado por teléfono vuelve a crear; **A-5** sin gate interno; **A-6** el reintento no exige ficha activa; **A-2** sin el capital tecleado; **C-3** el replay pierde el aviso; la pieza conservada ignora el veto; **R2-1** el reintento vuelve a elegir por contacto; **R2-2** captura cualquier 23514; **AR2-1** el otro enlazado por el DNI tecleado no bloquea; **R3-1** el reintento con rastro previo cae al veredicto fresco y llega al INSERT; **R4-1** el paso 3a devuelve nulo en un reintento y llega al INSERT) y 8 de catálogo (verificador modificado; núcleo y pieza INVOKER o con EXECUTE para `authenticated`; núcleo sin `search_path` vacío; alta sin `search_path` vacío, con EXECUTE para `anon`). Cada uno solo cuenta como muerto si el ensayo sale ROJO **y nombra los fallos que le corresponden**. |
| `derivas.sh` | Trece derivas de catálogo instaladas ANTES de la migración (cuerpo, `SET`, INVOKER, `anon`, `WITH GRANT OPTION`, `authenticated` sin EXECUTE, comentario, verificador de 3 y de 2 argumentos, guard de tenencia, reapertura solo por RPC, disparador deshabilitado, migración ya aplicada), un control sin deriva y un **mutante del preflight** (sin comparar `is_grantable`, la deriva `WITH GRANT OPTION` tiene que colarse). |
| `reversa.sql` | Quita los dos bloques insertados del cuerpo vivo (ancla única), repone el comentario y borra el núcleo y su pieza. **Falla cerrada:** exige `md5(prosrc)` `01ebf089…` y `md5(pg_get_functiondef)` `94ec2bd7…` (los que deja la migración). No deshace datos. |

## Límites conocidos (lo que este ensayo NO garantiza)

1. **Dos altas simultáneas (caso 7) NO se ejecutaron:** el ensayo corre en una conexión y no tiene credenciales para abrir otra.
   El alta serializa por `private.bloquear_contactos_lead` (candados de teléfono y DNI) y el núcleo toma la fila `for update` y
   recomprueba `activo = false`; la segunda alta ve la ficha viva y recibe `tomado`. Lo que se mide es el cuerpo, no la conducta.
2. **Interbloqueo (A-3):** el alta toma documento (tecleado) → persona → contactos; el núcleo, después, toma el documento del
   retirado (`bloquear_personas_de_leads`). Dos altas de la misma persona con datos cruzados pueden abrazarse; Postgres lo detecta
   (40P01), una de las dos aborta sin dejar nada a medias y la app lo traduce («otro usuario está procesando este contacto»). Es el
   resultado esperado; se ensaya con dos sesiones en la fase 4 (`test-rls.mjs`).
3. **El episodio de un retirado que venía de `descartado` se abre como `reabierto`**, no como `reactivado`: en
   `private.trg_leads_asignaciones` reabrir tiene prioridad (medida 2). Un retirado en etapa operativa sí abre `reactivado`. El
   rastro inequívoco de D-15 es la actividad `reactivacion_alta` (`etapa_anterior`, `activo_anterior = false`) + el episodio.
4. **El documento CE/pasaporte tecleado no se persiste ni entra en la huella** cuando el alta reactiva una ficha:
   `crm.crear_lead_documento_fn` responde `reutilizado` antes de fijarlo y el alta no recibe ni el tipo ni el número (la rama no
   puede saberlo). Un replay con otro número de CE se trata como el mismo alta. Cambio mínimo para la fase 4 en el informe.
5. **El veredicto bloqueante por dato conservado (C-1) no lleva `lead_id` ni `causa`:** el contrato de la app
   (`app/src/lib/disponibilidad-lead.ts`, `strictObject`) rechazaría la respuesta entera con una clave extra. Va en el formato
   exacto del verificador.
6. **El laboratorio está en el corte B6:** B7 se instala como fixture (arriba), pero B8–B10 no. En producción
   `trg_leads_disponibilidad_atomica` (B8) solo juzga el UPDATE cuando cambian teléfono o DNI (la reactivación no los cambia) y
   `trg_leads_000_base_cargada_solo_puerta` (B7) deja salir del descarte con capital: leído, no ensayado con esas versiones. Por
   eso el preflight de la migración **no fija** las huellas de `private.trg_leads_disponibilidad_atomica()` (aquí vive su versión
   anterior, `md5(prosrc)` `ba0fd3ef…`) ni de `private.trg_leads_base_cargada_solo_puerta()` (no existe aquí): antes del branch
   hay que medirlas en la branch y añadirlas al preflight, o declarar que el gate del branch (`test-rls.mjs`) lo cubre (AR2-3).
7. **Los mutantes de catálogo mueren solo por el caso 10**, no por un cambio de conducta: en el laboratorio todo corre como
   `postgres`, dueño de las funciones.
8. **Los gates del banco no están todos verdes:** de los `private.assert_*()`, varios caen desde antes por trabajos ajenos. Lo que
   se exige es que la foto NO cambie con la migración puesta (`--trinquetes`), y el postflight de la migración exige que cuatro de
   ellos den exactamente lo mismo que antes.

## Trampas encontradas al escribirlo

- **`now()` es la hora de la transacción**, no la del instante: el ledger exige `finalizado_en >= asignado_en` y el alta sella con
  `statement_timestamp`; los fixtures sembrados sin triggers usan `clock_timestamp()` y un ÚNICO valor para `finalizado_en` y
  `resultado_en` (el CHECK exige que sean iguales).
- **`text[] || 'literal'`** lo toma Postgres como literal de array («malformed array literal»): los motivos se acumulan con
  `array_append`.
- **Un vendedor cambia el payload al autoasignarse** (`vendedor_id` tecleado = él mismo): para probar que el reintento exige el
  mismo ACTOR hace falta el caso de dos supervisores que parquean (payload idéntico).
- **«Devolver null» no siempre reactiva:** cuando el núcleo devuelve nulo el alta responde su veredicto original; con
  `enfriamiento` eso bloquea. Por eso el mutante «no excluye activos» quita los bloques enteros y el de C-1 convierte el bloqueo
  conservado en nulo (son defectos distintos).
- **`exit <etiqueta>` sale de un bloque etiquetado también desde un manejador de excepción** (sonda en
  `fase-2/bloque-2.4/salidas/ronda2/previo/sonda-exit-bloque.sql`): así el núcleo tiene un único sitio de «veredicto fresco».
- **Un `ALTER TABLE crm.leads` a mitad del oráculo puede chocar con eventos diferidos pendientes** (`trg_leads_zzzz_conversion_responsable`
  y la FK de `sla_operacion_recibos` son `initially deferred`): el CHECK ajeno de R2-2 se siembra al **empezar** el oráculo, antes de
  cualquier escritura en la tabla, con `NOT VALID` (no revisa lo que ya hay) y una condición que solo cumple su propia ficha.
- **La bandera se puede apagar y encender dentro del rollback:** su trigger toma `pg_advisory_xact_lock('crm_flag_resolver_en_puertas')`
  exclusivo, compatible con el compartido que esta misma sesión ya tiene por las puertas (los candados consultivos no chocan
  consigo mismos); el prólogo exige la bandera encendida y el caso AR2-1 la deja como estaba (aborta si no).
- **Al reindentar una consulta, un fragmento de `mutantes.sh` puede empezar a coincidir con otra** (la del «otro retirado» y la del
  candidato por DNI comparten dos líneas a 10 espacios): el fragmento se hace más largo hasta que sea único; el guion se niega si
  aparece más veces de las declaradas.
