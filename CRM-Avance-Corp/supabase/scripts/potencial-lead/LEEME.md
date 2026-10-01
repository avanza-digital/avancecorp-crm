# 20260930213647_crm_potencial_lead — scripts de acompañamiento

Fase 1 del plan «Potencial del lead» (Frío · Tibio · Estrella), aprobado por Miguel el 30/09/2026.
Nota del vault: «Potencial del lead - Frio Tibio Estrella (2026-09-30)».

## Orden en producción (lo lanza Miguel con `!`, desde `CRM-Avance-Corp/`)

1. `supabase db query --linked --file supabase/migrations/20260930213647_crm_potencial_lead.sql`
   — aplica, en su propia transacción con `lock_timeout = 5s` (crea FK hacia `crm.leads` y
   `public.perfiles`). Preflight: objetos nuevos inexistentes, ayudantes presentes y huellas de
   `private.rol_crm` (`16960a2a…`) y `private.vendedor_ids_visibles` (`45ae492c…`) por md5 de
   cuerpo + DEFINER + volatilidad + configuración + dueño. Postflight (con `search_path` vacío):
   puerta DEFINER con EXECUTE solo authenticated, 4 privadas sin EXECUTE de la API, tablas y
   secuencia con dueño postgres y ACL solo de postgres (lista blanca) y cero permisos efectivos de
   anon/authenticated/service_role, policies exactas, 5 disparadores exactos
   (`pg_get_triggerdef`) y la bandera `potencial_lead` apagada.
2. `supabase db query --linked --file supabase/scripts/potencial-lead/registrar.sql` — fila en
   `schema_migrations` (statements = el archivo entero, md5 `f4087876…`). Idempotente.
3. `supabase db query --linked --file supabase/scripts/potencial-lead/verificar.sql` — solo
   lectura, termina en raise: marcas 0, eventos 0, bandera false, EXECUTE de la puerta
   `authenticated,postgres`, 0 EXECUTE ajenos en las privadas, 0 permisos API en las tablas,
   registro presente.
4. `supabase db advisors --type all` — ninguna clase nueva.

La bandera se enciende en la fase 3, cuando la pantalla esté publicada.

Reversa: `reversa.sql` (solo con las tablas vacías y la bandera apagada; conserva la fila de
`schema_migrations`: anotarlo en `MIGRACIONES.md`). ⚠️ Toma AccessExclusiveLock sobre `crm.leads` y
`public.perfiles` (lo exige el DROP de las FK; medido en el banco) ANTES de las tablas nuevas, con
`lock_timeout = 3s`: mientras dura nadie lee leads ni perfiles del portal. Correr en horario bajo y
reintentar si salta el timeout.

## Banco

**Repetible con un comando:** `banco/montar-banco.sh` monta el banco desde cero y `banco/ciclo-fase1.sh`
y `banco/ciclo-fase2.sh` corren todo lo de abajo (ciclo, pruebas, mutantes, concurrencia, registro y
verificación). Detalle y cómo leer la salida en `banco/LEEME.md`.

Docker propio `avancecorp-potencial-20260930` (imagen `supabase/postgres:17.6.1.105`, puerto
55470 en loopback), esquema `public,crm,private` volcado de producción el 30/09 con paridad de
huellas: 280 funciones `crm` y 540 `private` idénticas (con el mismo `search_path`; el texto de
`pg_get_functiondef` cambia con él, por eso las huellas fijadas no lo usan).

Ciclo pasado (versión final, tras Codex r1 + r2 y auditor-rls r1): migración → repetida (se niega) →
reversa → reversa repetida (se niega) → migración → registrar ×2 (idempotente) → verificar.

`prueba-sintetica.sql` (como `supabase_admin`, deshecha): **75 de 75**. Roles (analista dueño,
supervisor, sub-supervisor, parqueo solo para supervisor, gerencia, coordinador, directorio, equipo
inactivo, analista desactivado tras marcar, sin sesión), lead ajeno/inactivo/inexistente/
convertido/descartado, bandera apagada y encendida, doble clic sin evento, reconfirmar pasado el
minuto reinicia `marcado_en`, historial en orden, marcar no toca `crm.leads.actualizado_en`
(sembrado en el pasado) ni crea `crm.actividades`, sin grants la API no lee y con un grant de prueba
la RLS filtra, escrituras directas denegadas, historial inmutable (UPDATE, DELETE, TRUNCATE),
reasignación (la marca viaja) y filas de `public.audit_log` con su autor.

`prueba-concurrencia.sh` (dos sesiones de verdad, mundo confirmado y limpiado): **11 de 11**.
A reasignación en vuelo → P0002 sin escribir y V1 esperó ≥ 1,5 s (prueba de que se cruzaron);
B descarte en vuelo → 22023 y esperó; C reversa frente a una marca sin confirmar → espera y se
niega, la marca sobrevive; D reversa frente a una marca a medio camino (FOR SHARE del lead y luego
escribe) → sin interbloqueo, se niega; E lead aún sin confirmar → P0002 sin escribir. Mutantes:
puerta sin `potencial_bloquear_lead` → 3 fallas (escribía con permiso caducado); reversa sin
candados → borra la marca confirmada; reversa con el orden viejo (tablas nuevas antes que
leads/perfiles) → `deadlock detected` y la reversa borra todo.
El caso «FOR SHARE no encontró fila y la fila se confirma antes de autorizar» (Codex r2 R2-1) no es
reproducible de forma determinista (ventana de microsegundos): lo cubre el código (sin fila bloqueada
→ P0002) y el caso E.

Mutantes de la migración, todos rechazados por su pre/postflight: privada sin revoke, SELECT a
authenticated, secuencia abierta, policy `using (true)`, disparador inmutable solo en UPDATE, sin
disparador de TRUNCATE, puerta INVOKER, bandera encendida, `private.rol_crm` alterado.
Mutantes de la lógica cazados por la sintética: cerrado pasa (3), parqueo sin exigir supervisor
(1), token NULL en vez de «ok» (29), sin antirrebote (7), no reinicia el reloj (1), gerencia pasa
en ayudante Y puerta (7). «Gerencia pasa» solo en el ayudante sobrevive porque la puerta vuelve a
exigir el rol (doble candado, a propósito).

⚠️ La imagen del banco trae un `auth.uid()` que solo lee `request.jwt.claim.sub`; el de
producción también lee `request.jwt.claims`. La prueba fija las dos.
⚠️ En este Postgres, llamar a una función SIN EXECUTE bajo `set role` tumba el servidor: los
permisos de las privadas se leen del catálogo, nunca se llaman.
⚠️ Riesgo residual documentado: una baja o un cambio de jerarquía en `crm.equipo` confirmado en el
mismo instante que una marca no se serializa con ella (la marca queda; el actor ya no la usa ni la ve).
⚠️ Fase 2 (caducidad): debe tomar el MISMO candado consultivo que `private.potencial_bloquear_lead`
antes de escribir, o el `nivel_anterior` de sus eventos puede salir falso.

---

# Fase 2 · 20260930235917_crm_potencial_lead_caducidad — la marca baja sola

Reglas de Miguel (30/09): Estrella → Tibio con 5 días sin gestión, Tibio → Frío con 10; cuentan de
lunes a sábado; cada contacto o marca reinicia el reloj. Feriados: día normal (supuesto comunicado).

- **Días completos:** `private.dias_lunes_a_sabado(desde, hasta)` cuenta los días ESTRICTAMENTE entre
  las dos fechas (la tarea corre de madrugada: hoy aún no pasó).
- **Corre todos los días** a las 05:10 y 05:40 Lima (`10,40 10 * * *`, pg_cron en GMT): el domingo no
  cuenta como día, pero lo cumplido el sábado se aplica el domingo de madrugada (Codex f2 r1 F2).
  Marcada un lunes y sin contacto, la Estrella baja el domingo de madrugada.
- **Lote acotado** (Codex f2 r2 P2): como mucho 200 leads por pasada, de la marca más antigua a la más
  nueva; la segunda pasada y los días siguientes recogen el resto. Los candados de una pasada se
  sostienen hasta que termina: medido en el banco con 2 000 marcas vencidas, **200 leads = 34 ms**
  (1 600 sin acotar = 162 ms). Ese es el máximo que puede esperar un usuario que toque uno de esos leads
  a esa hora.
- **Gestión = contacto:** los 5 tipos del índice `actividades_contacto_episodio_idx` (llamada realizada
  o no contestada, WhatsApp enviado o recibido, reunión realizada). Las notas no cuentan. Cuentan los
  contactos hasta el INSTANTE de la corrida (`p_corte`, Codex f2 r2 P1: un WhatsApp de la 01:00 salva
  la marca en la corrida de las 05:10); uno con fecha futura no cuenta hasta su hora.
- **La regla y el reloj en un solo lugar:** `private.potencial_nivel_tras` y `private.potencial_reloj`.
- **Nunca espera** (Codex f2 r1 F1, auditor P3-1/P3-2): por candidato, `pg_try_advisory_xact_lock` (el
  consultivo de la marca) y la fila del lead en `FOR SHARE SKIP LOCKED`; si algo está ocupado, el lead
  queda para la próxima corrida. Bajo los candados revalida el lead (activo y abierto) y la marca, y
  solo BAJA. `lock_timeout = 10s` como red. Un error real aborta la corrida del día (queda en
  `cron.job_run_details`) y se pone al día al siguiente: la regla es acumulativa.
- **Supuestos a confirmar con Miguel antes de encender la bandera** (auditor P3-5): Estrella llega a
  Frío a los 10 días en total; el tiempo cerrado o inactivo cuenta como sin gestión; agendar o reasignar
  no reinicia el reloj. Riesgo residual: un contacto confirmado entre la relectura y el UPDATE no se ve.

## Orden en producción (Miguel con `!`, desde `CRM-Avance-Corp/`)

1. `supabase db query --linked --file supabase/migrations/20260930235917_crm_potencial_lead_caducidad.sql`
   — preflight: fase 1 con su candado, CHECK de tipos de `crm.actividades` igual al ensayado, contexto
   del job (current_user postgres con BYPASSRLS, `cron.timezone` GMT, sin job previo con ese nombre);
   postflight: 4 funciones INVOKER sin EXECUTE de la API (la tarea con `lock_timeout`), reloj y regla a
   mano, y UN solo job con horario, comando, usuario y base exactos.
2. `supabase db query --linked --file supabase/scripts/potencial-lead/registrar-caducidad.sql`.
3. `supabase db query --linked --file supabase/scripts/potencial-lead/verificar-caducidad.sql` — solo
   lectura: job, última corrida, permisos, marcas vivas y cuántas bajarían hoy.
4. `supabase db advisors --linked --type all` — ninguna clase nueva.
5. A la mañana siguiente, `verificar-caducidad.sql` otra vez: «última corrida» debe decir `succeeded`
   (prueba de que el planificador ejecuta el job en producción).

Reversa: `reversa-caducidad.sql` (desprograma el job y quita las funciones; el historial se queda;
funciona con y sin pg_cron). La reversa de la fase 1 se niega mientras la fase 2 esté puesta.

## Banco (mismo contenedor; pg_cron activado como en producción)

- SIN pg_cron: migración → reversa → migración → reversa, todo en verde.
- CON pg_cron: migración (job `10,40 10 * * *` postgres@postgres) → repetida (se niega) → reversa de la
  fase 1 con la 2 puesta (se niega) → reversa f2 (sin job) → repetida (se niega) → migración.
- **Corrida real de pg_cron** con la misma orden como `postgres`: `succeeded`.
- `prueba-caducidad.sql` (la tarea llamada como postgres, corte a las 05:10): **51 de 51** con
  calendario simulado de octubre (reloj, regla, contacto que reinicia, nota que no, contacto de 2099,
  contacto viernes 21:00 Lima, contactos del domingo a las 00:00, 00:30 y 06:00 alrededor de la
  corrida, lote con límite 2 y segunda pasada, bajada en domingo, convertido e inactivo intactos, idempotencia, re-marca, apagón de 11 días
  directo a frío con un solo evento, auditoría con autor nulo). Fase 1 sin regresión: 75/75.
- `prueba-concurrencia-caducidad.sh`: **10 de 10** (re-marca en vuelo y descarte en vuelo: salta sin
  esperar; la corrida siguiente baja lo vencido).
- Mutantes cazados: domingo cuenta, hoy incluido, nota es gestión, reloj sin contacto, contacto futuro
  cuenta, sin zona Lima, umbral 4, tibio a los 5, sin límite, cerrados en filtro y relectura, corte al
  inicio del día en filtro y relectura; esperar el consultivo y quitar SKIP LOCKED (concurrencia).
  «Cerrados» y «corte» rotos SOLO en el filtro sobreviven: los cubre la relectura bajo candado (doble
  cálculo, a propósito). Mutantes de la migración rechazados: EXECUTE abierto, una sola pasada, sin
  `lock_timeout`, regla distinta.
- Riesgos aceptados y escritos: un lead ocupado en cada corrida podría saltarse varios días (la regla
  es acumulativa: baja cuando se procese); el preflight del contexto del job es conservador (otro alias
  de UTC o rol equivalente daría rojo).

# Fase 3, entrega A · 20261001151704_crm_potencial_lead_lectura — la puerta de lectura

Plan aprobado por Miguel el 01/10/2026 («vamos dale»): la pantalla en dos entregas, A marcar y ver, B
filtrar. Esta migración es el servidor de la A y **no toca nada de lo que existe**.

- `crm.potencial_leads_fn(uuid[])` (DEFINER, STABLE, EXECUTE solo authenticated): sesión, el gate
  restrictivo del CRM (`private.puede_acceder_crm`, invocado), tope de 200 ids (cuenta todos los
  elementos, también de una matriz) y la bandera. Con la bandera `potencial_lead` apagada devuelve
  `{version:1, habilitada:false, items:[]}` sin leer nada.
- `private.potencial_lectura(actor, ids, hoy, corte, próxima corrida)` (INVOKER, sin EXECUTE de la
  API; el actor debe ser el de la sesión, si no 42501): un ítem por cada lead pedido que el actor puede
  VER (espejo de la policy `leads_select`):
  `{lead_id, nivel, origen, nivel_marcado, marcado_en, dias_sin_gestion, baja_a, baja_el, puede_marcar}`.
  Un lead visible sin marca viaja con `nivel` null. Una sola regla: días con `potencial_reloj` y
  `dias_lunes_a_sabado`, nivel siguiente con `potencial_nivel_tras` (fase 2); permiso con
  `potencial_rechazo` (fase 1).
- `private.potencial_proxima_corrida(instante)`: la fecha de la próxima pasada de la tarea según su
  horario NOMINAL (hoy hasta las 05:45 Lima: la última pasada se programa a las 05:40 y se dejan cinco
  minutos de margen; después, mañana). No mira si la pasada ya corrió. `private.potencial_proxima_baja(nivel, día del reloj, desde)`: la
  primera fecha, desde esa pasada, en que la regla da un nivel menor, y ese nivel.
- **Qué significa `baja_el`:** la primera madrugada, desde el siguiente horario nominal de la tarea, en
  que la regla la bajaría con lo que se sabe ahora. No es una promesa ni acredita ejecución: un contacto o
  una marca nuevos la aplazan, un lead ocupado o el límite del lote la dejan para la pasada siguiente, y
  si pg_cron se retrasa más allá de las 05:45 una pasada de hoy todavía puede bajarla hoy. La pantalla lo
  dice con «si no se gestiona».
- Sin agregados de conteo: el censo `private.contadores_crudos_leads_citas` vigila toda función que
  nombre `crm.leads` y cuente.
- 🔴 El núcleo COPIA la policy `leads_select`. Si esa policy o `crm_actor_activo_gate` cambian, hay que
  re-auditar `private.potencial_lectura`. El preflight las fija por md5 al aplicar; después, lo vigila el
  bloque `testPotencialLectura` del gate, que enciende la bandera fuera de banda y compara, rol por rol,
  lo que entrega la puerta con lo que la RLS deja ver.

## Orden en producción (Miguel con `!`, desde `CRM-Avance-Corp/`)

Exige las fases 1 y 2 aplicadas. Con la bandera apagada, publicar esta migración no cambia nada visible.

1. `supabase db query --linked --file supabase/migrations/20261001151704_crm_potencial_lead_lectura.sql`
   — preflight: fases 1 y 2 presentes, sin objetos previos, huellas de seis ayudantes
   (`rol_crm`, `vendedor_ids_visibles`, `es_lector_global`, `puede_acceder_crm`, `bandera_activa`,
   `potencial_rechazo`) y de las DOS policies de lectura de `crm.leads` (`leads_select` y
   `crm_actor_activo_gate`): si algo cambió desde el ensayo, se niega sin tocar nada. Postflight: puerta
   DEFINER/STABLE con configuración y ACL exactas (EXECUTE solo authenticated, sin opción de concederlo;
   anon y service_role sin permiso efectivo), tres ayudantes INVOKER sin EXECUTE de la API, sin conteos,
   contrato de la próxima corrida y la próxima bajada, la tarea de la fase 2 entera (un solo job, horario
   `10,40 10 * * *`, comando, usuario, base, activa, zona GMT) y el núcleo rechazando un actor que no es el
   de la sesión. El aviso final debe decir «tarea de caducidad comprobada»; «NO COMPROBADA» solo sale en
   un banco sin pg_cron.
2. `supabase db query --linked --file supabase/scripts/potencial-lead/registrar-lectura.sql` —
   idempotente; lleva el md5 de la migración (se regenera con `banco/generar-registrador.py`).
3. `supabase db query --linked --file supabase/scripts/potencial-lead/verificar-lectura.sql` — solo
   lectura, termina en raise: ejecutan la puerta `authenticated`, 0 EXECUTE de la API en los tres
   ayudantes, 0 funciones con ACL nula, forma `DEFINER/s/search_path=""`, job, bandera, marcas y registro.
4. `supabase db advisors --linked --type all` — ninguna clase nueva (la puerta suma un
   `authenticated_security_definer_function_executable`, clase ya existente).
5. En `app/`: `npm run gen:types`. Debe dejar los mismos bloques del potencial que ya lleva
   `database.types.ts` (se trasplantaron de los tipos generados desde el banco).

## Encender y apagar la marca (Miguel con `!`)

- `encender-bandera.sql`: SOLO cuando la pantalla ya está publicada. Se niega si falta la fase 1, la fase
  2, la puerta de lectura o la tarea diaria con su horario. Después, `verificar-lectura.sql` debe decir
  «bandera true». Anotar en `MIGRACIONES.md` quién la encendió y cuándo (desde `db query` la bitácora no
  guarda el actor).
- `apagar-bandera.sql`: el interruptor de emergencia. La puerta de marcar se niega (55000) y la de
  lectura devuelve `habilitada: false`: la pantalla deja de pintar el potencial en su siguiente lectura.
  Las marcas y su historial se quedan y la tarea diaria sigue bajando las que existan.
- Ensayados en el banco: encender, repetir (idempotente), apagar, repetir, y encender sin la puerta de
  lectura (se niega).

Reversa: `reversa-lectura.sql` (quita las cuatro funciones; la pantalla trata «función inexistente» como
potencial apagado). Va ANTES que las reversas de las fases 2 y 1: `reversa-caducidad.sql` se niega si la
puerta de lectura sigue puesta.

## Banco

`banco/ciclo-fase3a.sh` corre todo: ciclo, foto de los trinquetes sin y con la migración
(`banco/trinquetes.sql`), `prueba-lectura.sql`, fases 1 y 2 sin regresión, mutantes de lógica, de la
migración y del preflight, `banco/medir-lectura.sql`, registro, verificación y el verificador frente a un
ayudante abierto a PUBLIC. Los ciclos de las fases 1 y 2 retiran la lectura al empezar y la reponen al final.

`prueba-lectura.sql` (como `supabase_admin`, deshecha): **94 de 94**. Permisos del catálogo (API y roles
de puente); bandera apagada y encendida; sin sesión, usuario dado de baja, perfil inactivo, usuario solo
del portal y pareja desalineada (42501); 200 ids pasa, 201 y una matriz de 3 × 67 dan 22023; forma del
sobre y del ítem, sin repetidos; lo que ve cada actor (analista, sub-supervisor, supervisor con su
parqueo, gerencia y los dos directorios con lo sin asignar, coordinación sin leads); **equivalencia, actor
por actor, con la RLS real de `crm.leads`**; `puede_marcar` contra intentar marcar de verdad por la puerta
de la fase 1 (deshecho); el núcleo con un actor que no es el de la sesión (42501); y el calendario
simulado: recién marcada, 4 y 5 días, bajada pendiente antes y después de la corrida, 9 días tras la
corrida (va a frío mañana, no a tibio hoy), 11 días sin corrida, tibio a 10 días, contacto que reinicia,
contacto futuro que aún no cuenta, zona de Lima, marca que bajó sola, leads cerrados y frío.

Mutantes de lógica: 30; caen 29 y `sin-sesion` sobrevive a propósito (sin sesión el gate ya rechaza con
el mismo 42501; su doble `sin-sesion-ni-gate` cae). `baja-no-para` cae con un error de la propia prueba
(«more than one row»), no con una lista de fallas. 🔑 El primer pase dejó vivo `sin-gerencia`: la rama
«rol = gerencia» de la policy solo importa para leads SIN ASIGNAR (gerencia ve todo lo demás por
`vendedor_ids_visibles`); se añadió el lead `LS` y ahora cae. Mutantes de la migración y del preflight:
28 rechazados (incluidos el job con otro horario, otro comando, inactivo o ausente). Sin pg_cron la
migración se instala y avisa «NO COMPROBADA». Trinquetes: los 36 `private.assert_*()` y el censo, idénticos sin y con la migración.
Medición (supervisor con un equipo de 67 en tres niveles): 50 ids ≈ 8 ms, 200 ids ≈ 25 ms; 200 marcas de
hace 400 días con 20 contactos cada una ≈ 40 ms; un analista que pide 200 ≈ 2 ms. Con la máquina
cargada (otras pruebas corriendo a la vez) las cifras suben hasta cuatro veces.

🔑 Trampa de la prueba: dentro de un `DO` con una variable `r record`, un alias SQL `r` choca con ella
(«record "r" is not assigned yet»). Los alias de las consultas del bloque no pueden llamarse como sus
variables.
