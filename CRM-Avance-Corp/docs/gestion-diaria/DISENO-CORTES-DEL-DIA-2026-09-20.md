# DISEÑO — Cortes de actividad del día (Gestión Diaria, Fase 4)

**Estado:** diseño revisado por Codex (SECONDARY_REVIEWER, read-only) · LEVEL 3 (permisos, RLS, política que juzga a personas) · **no se escribió ni una línea de código** · VERIFICATION: **NOT RUN** (no hay nada que verificar todavía).

---

## 0 · Lo que hay que preguntarle a Miguel ANTES de escribir código

Codex bloqueó el diseño por esto y tiene razón: siete decisiones son de negocio, no técnicas.

1. **¿La base del segundo corte son las 11:00 o las 11:30?** Confirmar con el número: «si a las 11:30 lleva 8, a las 16:00 debe llevar 20».
2. **¿Cuántas llamadas mínimas al primer corte?** Se puede medir la mediana real de los últimos 14 días (lectura de solo lectura), pero la mediana *describe* lo que hace el equipo; no *fija* lo exigible.
3. **¿Cuenta toda llamada o solo la «útil»?** (Útil = resultado ∉ `numero_errado`/`no_es_la_persona`, sellado en `…041500…sql:306`.) Recomiendo toda llamada: el corte mide actividad, la tasa ya mide calidad.
4. **¿El incumplimiento de las 11:30 desaparece si el analista se pone al día antes de las 16:00?** ¿Y el de las 16:00 queda marcado aunque llame después?
5. **Sábado sí o no.** La regla vigente del sistema es **L–S** (`app/src/lib/motor-siguiente.ts:45-66`, `slotHabil()` manda domingo a lunes). Si el sábado tiene menos volumen por naturaleza, la perilla correcta no es apagarlo sino un mínimo distinto — y eso es otra fase.
6. **¿Qué es «prestarle atención»?** ¿Basta «lo vi», o el supervisor tiene que registrar qué hizo? ¿Acepta que el aviso solo exista con el CRM abierto (hoy no hay push para esto)?
7. **¿Los cambios de configuración rigen desde la jornada siguiente** (recomendado) **o tienen que poder afectar el mismo día?**

---

## 1 · Las tres ambigüedades

| Ambigüedad | Interpretación recomendada | Por qué |
|---|---|---|
| **«150 % más»: ×2,5 o ×1,5** | **×2,5** (incremento, no proporción). Se guarda como `corte_2_incremento_pct = 150` y la pantalla imprime la frase ya calculada. | En castellano «150 % **más**» es incremento; y cuadra con la otra lectura del propio pedido («lo de la tarde debe traer 150 % de lo de la mañana» = base + 1,5·base = 2,5·base). Con la frase calculada en pantalla, un error de lectura se ve en dos segundos. |
| **«11:30» vs «las que tenía a las 11 am»** | **Un solo reloj: la base es el acumulado en el corte 1.** Pero esto **se pregunta, no se decide** (Codex F7): «una perilla menos» no resuelve una contradicción del pedido. | Dos relojes distintos (juzgar a las 11:30, comparar contra las 11:00) meten media hora de llamadas en tierra de nadie y obligan a una tercera consulta. |
| **No dijo el mínimo del primer corte** | Perilla nueva `corte_1_minimo_llamadas`, **sembrada con un número que Miguel aprueba**, informado por la mediana medida en prod sobre los mismos 14 días con que se aprobaron 45/25/5 (`…041500…sql:183-185`). | Inventar el número es fabricar una política; medirlo y presentárselo es darle la decisión con evidencia. |

---

## 2 · Modelo de datos

**Tabla nueva `crm.politica_gestion_diaria`, molde VERSIONADO CON VIGENCIA** — el de `crm.sla_politicas` (`supabase/migrations/20260807203757_crm_metas_sla_versionados.sql:386-421`), **no** el singleton de `crm.politica_abandono`.

Absorbe **también** los tres umbrales que hoy están a fuego, para que la fuente siga siendo una sola:

```
id uuid pk
version integer not null unique
version_anterior_id uuid references crm.politica_gestion_diaria(id)
vigente_desde timestamptz not null            -- SIN unique (ver §3, corrección Codex F11)
-- lo que hoy vive en el cuerpo de la función (…041500…sql:186-197)
bien_min_pct / atencion_min_pct / minimo_llamadas_utiles integer not null
-- lo nuevo
cortes_activos boolean not null default false
corte_1_hora time                             -- 11:30
corte_1_minimo_llamadas integer
corte_2_hora time                             -- 16:00
corte_2_incremento_pct integer                -- 150
corte_2_minimo_llamadas integer               -- piso absoluto
corte_2_techo_llamadas integer                -- techo absoluto (ver §7)
aplica_sabado boolean not null default true   -- la regla vigente es L–S
aviso_persistente boolean not null default false
publicada_por uuid / publicada_en timestamptz
check (not cortes_activos or (corte_1_hora is not null and … ))
```

- **Inmutable** por `private.trg_config_versionada_inmutable()` (el mismo trigger de SLA, `:299-313`), que lanza `55000` «publica una nueva revisión».
- **Versión 1 sembrada con `vigente_desde = '-infinity'` lleva SOLO 45/25/5 y `cortes_activos = false`.** Corrección de Codex (F1): sembrar los cortes desde `-infinity` haría parecer que la obligación existía antes de inventarla. Los cortes nacen en la **versión 2**, con la jornada en que Miguel los enciende.
- **RLS ON.** Policy de SELECT calcando `politica_abandono_select` (`20260816221500…:77-83`): `es_lector_global()` **o** `rol_crm(auth.uid()) is not null`. **Sin policy de INSERT/UPDATE/DELETE**: la única puerta de escritura es la función definer (igual que `sla_politicas`, `:447-461`).
- **Grants:** `revoke all … from public, anon` + `grant select … to authenticated`. Nada más. Gerencia **no** escribe por PostgREST (a diferencia de `politica_abandono`, `:117-118`): una política que juzga personas necesita `expected_version` y validación de forma.
- Trigger de auditoría `private.log_audit_crm()`.

**Por qué versionada y no singleton (y dónde Codex me corrigió el argumento).** El motivo válido es uno solo: **la puerta F3 ya admite consultar días pasados** (`p_dia` hasta un año atrás, `…041500…sql:534-535`) y con una fila que se pisa, el martes pasado se re-juzgaría con la perilla de hoy. El argumento que yo daba de que `dias_auto_bolsa` lleva un mes sin consumidor **no prueba nada** sobre singleton vs versionado (Codex, aceptado): prueba otra cosa, que una perilla sin pantalla se muere.

**Dónde vive la tabla (desacuerdo registrado con Codex, F8).** Codex propone bajarla a `private` con cero grants (precedente real: `crm.conversion_pesos`, `20260811154434:409-412`). **No lo hago**, y la evidencia es literal: estos valores **ya viajan hoy a cualquier analista autenticado** dentro de su propio día, en la clave `'umbrales'` (`…041500…sql:460`). Esconder la tabla no compra confidencialidad y en cambio obligaría a convertir `private.gestion_diaria_umbrales()` de `invoker` a `definer`, tocando una propiedad que el gate sella. Sí acepto la otra mitad de F8: **la lógica de evaluación baja al núcleo** (§4).

---

## 3 · La puerta

**Lectura del editor** — `crm.configuracion_gestion_diaria_fn()`, DEFINER con `search_path = ''`, calco de `crm.configuracion_sla_fn` (`20260807203757…:571-607`). Devuelve `expected_version`, `puede_editar` (= `rol_crm = 'gerencia'`, **calculado en servidor**), la política vigente con autor, la frase de ejemplo ya calculada, y —corrección de Codex F11— **`revisiones_pendientes[]`**: las versiones con `vigente_desde` futuro. Sin eso, gerencia edita a ciegas sobre valores antiguos y pisa lo que ya estaba programado.

**Escritura** — `crm.publicar_politica_gestion_diaria(p_expected_version integer, p_vigente_desde timestamptz, p_config jsonb)`, DEFINER, calcando `crm.publicar_politica_sla` (`:470-560`):

- `rol_crm(auth.uid()) = 'gerencia'` o **42501**.
- Forma exacta del jsonb: `?&` con todas las claves **y** `p_config - array[...] <> '{}'` para rechazar claves de más.
- Rangos: porcentajes 0–100 con `atencion_min_pct <= bien_min_pct`; `minimo_llamadas_utiles` 1–100; mínimos y piso 1–200; incremento 0–900; `corte_2_hora >= corte_1_hora + 60 min`; ambas horas dentro de 06:00–22:00 Lima.
- **Vigencia**: `p_vigente_desde` debe ser el **inicio de una jornada Lima futura** (no una hora cualquiera). Ver §4.
- `pg_advisory_xact_lock(hashtext('crm.politica_gestion_diaria'), 1)` + `p_expected_version <> v_actual` → **40001**.
- **Sin `unique` en `vigente_desde`, y el resolutor ordena `(vigente_desde desc, version desc)`.** Es la única desviación deliberada del molde SLA y la razón es la que levantó Codex (F11): con `unique`, una revisión ya programada para mañana **no se puede corregir** sin romper la inmutabilidad. Sin `unique`, la corrección es simplemente una versión mayor para la misma jornada, y gana. `private.sla_politica_vigente` ya desempata así (`:562-569`), o sea que el patrón de lectura no se inventa.

**Resolución** — `private.politica_gestion_diaria_vigente(p_instante timestamptz)`.

**Encaje con `private.gestion_diaria_umbrales()` (hoy a fuego, `…041500…sql:186-202`) — corregido por Codex (F2).** Mi plan original («le pongo un parámetro con default») **no funciona**: en Postgres una función de cero argumentos y otra de un argumento con default son firmas distintas, y `create or replace` no puede añadir un parámetro. Diseño corregido:

- Se **añade** `private.gestion_diaria_umbrales(p_instante timestamptz)` — sin default — que lee la vigente.
- La de cero argumentos **se conserva** como envoltorio (`select private.gestion_diaria_umbrales(now())`), para no hacer un `drop` en producción ni reemitir grants. Su cuerpo cambia → **hay que re-sellar el md5 `6ab633af9f5356f3fa11cf309ff4b25c` en `private.assert_gestion_diaria_analista()` (`:801`)**.
- **`private.gestion_diaria_analista_core` deja de llamarla sin argumento** (`:331`) y pasa `p_ini` explícito. Su cuerpo cambia → **re-medir y re-sellar su md5 (`:800`)**.
- **Mutantes obligatorios** (`:907`, `:912`; `npm run test:mutantes`): uno por cada defensa nueva — la policy de UPDATE ausente, el 42501 de la publicación, el 40001 de `expected_version`, el rechazo de claves extra, el techo/piso del corte 2.
- La migración `20260920041500` **está en producción y registrada** (acta en `supabase/migrations/MIGRACIONES.md`, sección «20260920041500 — Gestión Diaria (F3)», 20/09 ~06:19 UTC): **no se edita**. Todo esto va en migración nueva.

**Autorización, explícita y no «por calco»** (Codex F6, aceptado como vacío de diseño): por cada RPC hay que escribir quién tiene `execute`, qué comprueba dentro cada DEFINER, cómo se acota `p_supervisor_id` a la jerarquía del actor (`private.vendedor_ids_visibles`), y qué ven gerencia, directorio y lector global. Se prueba identidad por identidad en el postflight con `set_config('request.jwt.claims')`, patrón `20260916205617:240-379`.

---

## 4 · El cálculo de los cortes

**Dónde vive: en el núcleo, no en la puerta y desde luego no en la pantalla.** `private.gestion_diaria_cortes(p_dia, p_ini, p_vendedor_ids, p_politica jsonb)`; `crm.gestion_diaria_equipo_fn` (Fase 4, aún sin escribir) **solo autoriza y compone**. Corrección de Codex (F8): yo lo tenía en la puerta, y la regla de la casa es que la puerta no lleva lógica de negocio.

**Cómo se mide.** Componiendo el núcleo que **ya está en producción**, `private.gestion_diaria_llamadas(p_ini, p_fin, p_vendedor_ids)` (`…041500…sql:206-307`), con tres ventanas: `[día, corte_1)`, `[día, corte_2)`, `[día, min(ahora, fin_día))`. Composición, no duplicación: sigue habiendo **una sola** definición de llamada. **No se usa `por_hora`**: es un array disperso de **hora entera** (`:235`, `extract(hour from … at time zone 'America/Lima')`) y no puede expresar las 11:30.

**Zona horaria.** Todo con `at time zone 'America/Lima'`, como `…041500…sql:578-580`; nunca `-05:00` a mano. Perú no observa horario de verano desde 1994, pero da igual: al usar el nombre de zona, el cálculo es correcto aunque cambiara. Codex no pudo confirmarlo con la evidencia pegada y lo dejó como pregunta abierta; queda anotado.

**El instante que resuelve la política — lo que Codex bloqueó (F1).** La política se resuelve **al inicio de la jornada Lima evaluada** (`v_ini`), no con `now()` ni con `least(v_fin, now())`. Tres razones, las tres suyas:
- con `now()` por defecto, un día pasado se juzgaría con la perilla de hoy;
- `least(v_fin, now())` devuelve la **medianoche del día siguiente**, así que una revisión que entre en vigor justo entonces contaminaría el día anterior;
- publicar al mediodía cambiaría las reglas de un corte que **ya ocurrió** esa mañana.

Resolviendo en `v_ini` y exigiendo que `vigente_desde` sea el inicio de una jornada futura, **las reglas del día se fijan al amanecer y no se mueven**. Eso es lo que hay que confirmarle a Miguel (pregunta 7).

**Las reglas.**
- **Corte 1 (11:30):** falla si `llamadas_acumuladas < corte_1_minimo_llamadas`.
- **Corte 2 (16:00):** objetivo = `max(ceil(base × (100 + incremento)/100), corte_2_minimo_llamadas)`, acotado por `corte_2_techo_llamadas`. **`ceil`, no `round`** (Codex F9): con base 8 e incremento 30 %, el objetivo es 10,4 y «al menos» significa **11**; `round` daría 10. Con 150 % el defecto queda oculto porque salen enteros.
- **Base cero:** si el acumulado del corte 1 es 0, la razón siempre pasa (0 × 2,5 = 0) y con base 1 pide 3 — por eso el **piso absoluto** manda en ese caso.
- **Sábado:** se evalúa si `aplica_sabado` (default **true**, porque la regla vigente del sistema es L–S). Domingo nunca.
- **Feriados: no existe calendario laboral en el repo** (`grep feriado|festivo|dias_no_laborables|calendario_laboral` sobre `supabase/migrations/` y `app/src/` → **0 resultados**) y **no propongo crearlo**. Mi heurística de «día atípico» (silenciar si menos de un tercio del roster registró llamadas) **la retiro**: Codex (F3) demostró que apaga la alarma exactamente el día en que nadie llamó, que es el día que más importa. En su lugar: la alerta **se emite siempre**, y cuando la participación del equipo entero está por los suelos lleva una marca de contexto («actividad excepcionalmente baja en todo el equipo — revisa si hoy es feriado o hubo una incidencia») y se presenta como **una** alerta de equipo, no como N individuales. Silenciar un día requiere una decisión explícita, no una inferencia.
- **Analista que entró a media mañana:** no se prorratea. La alerta incluye `primera_llamada_en` (ya lo devuelve el núcleo, `:483-484`) para que el supervisor lea el contexto. **Quien tiene cero llamadas SÍ entra en el grupo del corte** — corrección de Codex (F4): mi deduplicación original lo dejaba solo en `sin_llamadas_hoy` y fuera del aviso fuerte, o sea que el que peor está recibía el aviso más débil. `sin_llamadas_hoy` se suprime **en la presentación** para quien ya está dentro del grupo del corte, no en el cálculo.
- **A quién se evalúa:** roster activo (`crm.equipo.activo = true` y `rol_crm` = vendedor, definición fijada en `PLAN-POR-FASES-2026-09-19.md`), **menos** quien no tiene cartera abierta — decisión de negocio, pregunta 3 de Miguel.

**Historia.** Todo se deriva del log de actividades; **no hay tabla de «evaluaciones de corte»**. Limitación que hay que decir en pantalla (Codex F10, aceptado): un día pasado se recalcula con **el equipo y la jerarquía de hoy**, no con los de entonces. Reproducir «lo que el supervisor vio aquel día» es un contrato distinto y más caro; si Miguel lo quiere para evaluaciones de desempeño, entonces —y solo entonces— hace falta un registro derivado, que **no** es automáticamente «otro origen de verdad». Pendiente de verificar: que ningún escritor fije `creado_en` a mano en `crm.actividades` (inserciones tardías romperían el recálculo).

---

## 5 · El aviso «que le tenga que prestar atención»

En esta app, hoy, **no existe nada bloqueante**: `components/ui/dialog.tsx:19-27` solo expone `{open, onClose}` (sin modo no-cerrable), `grep alertdialog` → 0 resultados, y la campana (`topbar.tsx:456-482`) es un badge que se puede ignorar para siempre. Opciones de menos a más intrusiva:

| # | Qué | Coste | Veredicto |
|---|---|---|---|
| 1 | Fila roja en `components/gestion-diaria/alertas-del-dia.tsx` (ya planeado en F4) | ~0 | Necesario, insuficiente |
| 2 | Campana + contador vía el adaptador `alertaDiariaAAlertaCRM()` → `topbar.tsx:456` | bajo | **Sí, en v1** |
| 3 | **Barra persistente sin botón de cerrar**, portal fijo `z-[60]`, calcando `components/app/guardados-sla-pendientes.tsx` + `App.tsx:697-704` | medio | **Recomendada para v1** |
| 4 | **Reconocimiento con rastro en servidor** en `crm.alertas_reconocimientos` | medio | **Recomendada, misma fase** |
| 5 | Notificación de escritorio + sonido reusando `respuestas-tasa-provider.tsx:126-142` y `lib/respuestas-tasa.ts:89-115`, solo si la pestaña no tiene foco | medio | Opcional, decide Miguel |
| 6 | Web Push con la app cerrada | alto | **No en v1** |
| 7 | Modal bloqueante | alto + daño | **No** |

**Por qué 3 + 4 juntos y no 3 solo.** El patrón de `guardados-sla-pendientes` funciona porque **se autoapaga cuando la condición cesa** (`:54`). El corte de las 16:00 **no cesa**: es un hecho del pasado. Sin una forma de cerrarlo, la barra sería papel pintado a las 16:05 — y una alerta que no se puede apagar deja de ser una alerta. El corte de las 11:30 sí puede autoapagarse (si el analista se pone al día), lo cual encaja con el «se retira sola al resolverse» que el plan ya usa.

**Lo que 4 exige, y la corrección de Codex (F5).** `crm.alertas_reconocimientos` tiene el `alerta_id` cerrado por CHECK a cuatro tipos (`20260823204930…:44-46`), y el comentario de la tabla dice que ampliarlo exige migración **a propósito**. Hasta ahí, previsto. Lo que yo tenía mal: pensaba caducar el asiento de corte por `creado_en` al cambiar el día. **No sirve**: con `grupo:<tipo>:<uuid supervisor>` el id **se reutiliza cada día**, así que un reconocimiento reintentado hoy (el servidor le sella `creado_en` de hoy) podría ocultar el corte **de hoy**. La identidad persistida tiene que llevar **supervisor + jornada Lima + corte**:

- regex nueva con una rama propia: `^grupo:(corte_manana|corte_tarde):<uuid>:\d{4}-\d{2}-\d{2}$`, manteniendo intacta la rama de los cuatro tipos vigentes (que **no** llevan fecha);
- **`posponer` prohibido** para los tipos de corte: posponer a «mañana» no tiene sentido cuando mañana el id es otro. El trigger lo rechaza;
- `miembros[]` = los analistas del grupo, así el «reaparece si empeora» de `lib/reconocimientos-alertas.ts:111-113` sigue funcionando: un analista nuevo que cae en el corte 2 revive la alerta;
- `ultimoAsientoPorAlerta` (`:60-75`, orden por `secuencia`) y la caducidad de 7 días (`:17`) siguen igual y ya no estorban: el id muere con la jornada;
- barra, campana y pantalla de alertas tienen que aplicar **el mismo** reconocimiento.

`SeveridadAlerta` **no gana un tercer valor**: la barra persistente es una decisión de presentación, no una severidad nueva. `TipoAlerta` (`lib/alertas.ts:19-29`) sí gana `corte_manana` y `corte_tarde`.

**Honestidad sobre el alcance:** con esto el supervisor se entera **solo si tiene el CRM abierto**, y con hasta 60 s de retraso (`refetchInterval: 60_000`, `crm-queries.ts:1216-1229`). Si Miguel quiere que le llegue con la app cerrada, eso es la opción 6: el molde completo existe y está en producción (`supabase/functions/crm-notificaciones-tasa/`, `20260910225540_crm_notificaciones_push_tasa.sql`) pero dispara **por INSERT en una tabla** (`trg_encolar_push_tasa`, `:163`); los cortes necesitan disparo **por reloj** (pg_cron 11:30/16:00 Lima) más cola y dedupe por (día, corte, supervisor). Es una fase entera.

---

## 6 · La pantalla de gerencia

**Sección propia `config-gestion-diaria`.** No dentro de `config-sla`: son dos contratos versionados distintos y «Tiempos de atención» significa otra cosa.

Los siete archivos con `Record<Vista,…>` exhaustivo (si falta uno, el typecheck se cae): `lib/router.ts:11-41` (VISTAS) y `:53-60` (VISTAS_CONFIGURACION), `lib/vistas.ts:21-50`, `App.tsx:65-71` y `:74-102`, `components/app/topbar.tsx:48,73-74`, `components/app/ayuda-vendedor-panel.tsx:20,45-46`, `screens/config.tsx:39-46`. El sidebar no se toca (`sidebar.tsx:66-70` excluye `esVistaConfiguracion`). Más: `lib/politica-gestion-diaria.ts` (Valibot `strictObject`, calco de `lib/control-citas.ts:1-21`), `data/crm-config-api.ts` con `parsear()` y **eco campo a campo** tras el RPC calcando `:455-491`, `data/crm-config-queries.ts` con `mutacionSoloReal` (`:42-55`) e invalidación **también** de la clave de Gestión Diaria, y clave nueva en `crm-queries.ts:90-97`.

**No entra en el riel de estado** de `config.tsx:155-206` — eso exigiría un doble demo en `lib/demo-config.ts`, y por eso mismo `config-rentabilidad` y `config-citas` tampoco están.

**Qué valida el cliente** (espejo de §3; la que manda es la del servidor): horas dentro de 06:00–22:00 Lima, `corte_2 ≥ corte_1 + 60 min`, enteros y rangos, `atencion_min_pct ≤ bien_min_pct`, y **la frase calculada visible mientras se edita**: «si a las 11:30 lleva 8 llamadas, a las 16:00 deberá llevar al menos 20».

**Cómo se publica:** diálogo de confirmación «Publicar política de Gestión Diaria v{expected_version + 1} — rige desde la jornada del DD/MM; las versiones publicadas no se editan», con las **revisiones pendientes** a la vista. Mapeo de errores ya existente (`crm-config-api.ts:102-124`): `40001 → CONFLICTO_CONFIG`, `42501 → SIN_PERMISO`, `22023/23514 → REGLA_SERVIDOR`. Gate de acceso: `lib/vistas.ts:89-92` (gerencia y directorio; directorio en solo lectura por `puede_editar` del servidor).

---

## 7 · Riesgos

1. **El ruido.** Es el riesgo mayor y el que mata la funcionalidad. Mitigaciones: **una** alerta por corte por supervisor con `miembros[]` (no N alertas — regla «una alerta por DECISIÓN», `lib/alertas.ts:405-411`); el corte 1 se retira solo si el analista se pone al día; techo «1 rojo por decisión, máx. 2 ámbar» del playbook; excluir a quien no tiene cartera; y `aviso_persistente` **apagado en la versión inicial**, para que gerencia encienda la barra desde su propia pantalla cuando los números se vean sanos. Codex (F12) tiene razón en dos cosas: ese «modo observación» es **parcial por construcción** (sin ejecución programada y sin CRM abierto no hay muestra completa) y **no se puede dar por hecho que Miguel acepte esperar** para tener lo que pidió. Por eso es una perilla, no un calendario.
2. **La injusticia del objetivo relativo** (la levanta Codex y es de negocio, no técnica): con ×2,5, quien llevaba 20 necesita 50 y quien llevaba 8 necesita 20. El primero puede acabar con 30 llamadas y **fallar**, mientras el segundo cumple con 20. Por eso propongo `corte_2_techo_llamadas`: quien ya superó un volumen absoluto no falla la regla relativa. El piso solo no lo arregla.
3. **Re-sellado de md5 y mutantes** (`…041500…sql:800-801`, `:907`, `:912`): si se re-sella sin re-medir en producción, el gate deja de proteger y nadie se entera.
4. **Deriva del duplicado del front**: `app/src/lib/gestion-diaria-analista.ts:300` repite 45/25/5 a mano para el modo demo y `analista.test.tsx:46` los fija en el fixture. Al hacer configurables los umbrales, ese duplicado se convierte en mentira. Hay que anotarlo como demo explícita.
5. **`database.types.ts` a mano**: `gen:types` está roto (riesgo ya declarado en el plan); dos RPC nuevas se escriben a mano.
6. **Reproducibilidad histórica incompleta**: se versiona la política, no el roster ni la jerarquía (§4).
7. **Alcance del aviso**: hasta 60 s de retraso y cero aviso con el CRM cerrado.
8. **Doble alerta** con `sin_llamadas_hoy` y `parado_2h`: resuelto por presentación, pero es donde más fácil se cuela el ruido.
9. **Banco compartido entre sesiones** y sesión paralela de «historial por lead»: pedir turno antes del ciclo de pruebas.

---

## 8 · Qué NO haría

- **Modal bloqueante.** No existe `alertdialog` en el repo y `Dialog` no tiene modo no-cerrable (`ui/dialog.tsx:19-27`). Construirlo es pelearse con la arquitectura de la app para conseguir que el supervisor odie la funcionalidad en dos días.
- **Tabla de feriados.** No existe calendario laboral (0 resultados) y crearlo es asumir un mantenimiento anual para un beneficio que se resuelve con contexto en la alerta.
- **Heurística de «día atípico» que silencia.** Retirada por la refutación de Codex (F3).
- **Push, correo o WhatsApp en v1.** El molde de push existe pero dispara por INSERT, no por reloj.
- **Cuota diaria por analista.** Está **fuera de v1 por decisión escrita** (`PLAN-POR-FASES-2026-09-19.md`, «Fuera de v1»; `PLAN.md:256-258`). Los cortes no son la cuota: miden ritmo, no volumen objetivo.
- **Perilla por analista** (molde `crm.equipo.capacidad_leads_objetivo`). Empieza global; si hace falta individualizar, es otra fase.
- **Meter los cortes en `config-sla`** ni escribirlos por PostgREST al estilo `politica_abandono`.
- **Tabla de snapshots de corte en v1** — pero **sin descartarla por principio**: si Miguel quiere «lo que el supervisor vio aquel día» como evidencia, un registro derivado es legítimo (corrección de Codex, F10).
- **Tocar la migración `20260920041500`**, que está en producción y registrada.

---

## REVIEW · Codex (SECONDARY_REVIEWER, `sandbox: read-only`, `approval-policy: never`)

**Veredicto de Codex: REQUEST CHANGES.** Sin P0. Doce hallazgos P1–P2.

**Aceptados e incorporados (11):** F1 resolución temporal por jornada y semilla `-infinity` sin cortes · F2 el parámetro con default no reemplaza la firma (envoltorio + función parametrizada, y el llamador pasa el instante) · F3 retirar la supresión por «día atípico» · F4 el de cero llamadas entra en el grupo del corte · F5 la identidad del reconocimiento lleva jornada y corte, y `posponer` se prohíbe · F6 escribir la autorización explícita de cada RPC · F7 devolver a Miguel las decisiones de negocio (hora base, sábado, mínimo, piso, sin-cartera) · F9 `ceil` en vez de `round` · F10 declarar la limitación de reproducibilidad y no descartar el registro derivado · F11 revisiones pendientes visibles y `vigente_desde` **sin unique** · F12 el modo observación es parcial y es una perilla, no un calendario. Más su observación de negocio sobre la injusticia del objetivo relativo → `corte_2_techo_llamadas`.

**Aceptado a medias (1):** F8. Acepto bajar el cálculo al núcleo. **Rechazo** mover la tabla a `private`, con evidencia: los valores ya viajan hoy a cualquier analista autenticado en `…041500…sql:460`, así que esconderla no compra confidencialidad y obligaría a convertir `gestion_diaria_umbrales` de invoker a definer.

**Confirmado por Codex tal cual (no tocar):** D1 (×2,5 con ejemplo numérico), la elección de configuración versionada e inmutable, el control de gerencia en servidor con bloqueo y `expected_version`, la reutilización de `gestion_diaria_llamadas` con ventanas exactas evitando `por_hora`, descartar el modal bloqueante, y la estructura completa de la pantalla de §6.

**Abierto:** Codex no pudo confirmar con la evidencia pegada que `America/Lima` no tenga DST (es un hecho —Perú no lo observa desde 1994— y el código usa el nombre de zona, así que es indiferente); y pide verificar que el índice `actividades_llamadas_autor_dia_idx` exista de verdad y no solo en el plan.

**VERIFICATION: NOT RUN** — es un diseño; no hay lint, typecheck, tests ni build que correr todavía.

**Archivos citados (rutas absolutas):**
`/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp/supabase/migrations/20260920041500_crm_gestion_diaria_analista.sql` · `.../20260807203757_crm_metas_sla_versionados.sql` · `.../20260816221500_crm_lead_libre_f1_verificacion.sql` · `.../20260823204930_crm_alertas_reconocimientos.sql` · `.../20260910225540_crm_notificaciones_push_tasa.sql` · `.../supabase/migrations/MIGRACIONES.md` · `.../docs/gestion-diaria/PLAN-POR-FASES-2026-09-19.md` · `.../docs/gestion-diaria/PLAN.md` · `.../app/src/lib/alertas.ts` · `.../app/src/lib/reconocimientos-alertas.ts` · `.../app/src/lib/motor-siguiente.ts` · `.../app/src/lib/vistas.ts` · `.../app/src/screens/config.tsx` · `.../app/src/screens/config-sla.tsx` · `.../app/src/components/app/guardados-sla-pendientes.tsx` · `.../app/src/App.tsx` · `.../app/src/data/crm-config-api.ts` · `.../app/src/data/crm-config-queries.ts` · `.../app/src/data/crm-queries.ts`