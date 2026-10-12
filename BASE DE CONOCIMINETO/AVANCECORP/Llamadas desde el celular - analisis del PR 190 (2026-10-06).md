# Llamadas desde el celular — análisis del PR #190 (06/10/2026)

Sigue a [[Llamadas desde el celular - decisiones de Miguel y plan v2 (2026-10-03)]] y a
[[Llamadas desde el celular - revision antes de publicar (2026-10-02)]]. Pedido de Miguel: «analiza el pr 190».
**Nada aplicado en producción ni fusionado.** El comentario ya está en el PR (su texto quedó en
`AVANCECORP-desktop-worktrees/bancos-20261006-NO-VERSIONAR/pr190/comentario-pr190-borrador.md`).

## Qué trae hoy el #190

Rama `crm/llamadas-quinta-migracion-20261005`, cabeza **`ae2435e2`**. Ya no son siete migraciones: el **#198 (F4-b) se
fusionó DENTRO de esta rama** el 06/10 04:51 UTC (era una PR apilada: «MERGED» no es «llegó a `main`»). Hoy trae las
**nueve** (`20261001145242` … `20261005224330`: datos, núcleo, ingesta, elegibilidad, quinta, F4-a, séptima, octava y
novena), la Edge, el gate, las guías y la pantalla de F4-b (id de la llamada hasta la encuesta + pestaña «Celular», que
solo se ve en la demo).

## Resultado en una línea

**La base está sana y se puede instalar; no se fusiona todavía** por un conflicto con `main` y por cinco P2 de regla
(dos del auditor, tres de Codex) que piden una **décima migración** de Jhosep.

## Lo que se midió (banco Docker a paridad con producción)

Banco `avancecorp-pr190-20261006` (puertos 5842x), clon del de B11 con B11 revertida: `933 | 2c2f2612…` funciones
`crm`+`private` = producción con «eliminar inversión». Configuración, guiones y evidencia:
`AVANCECORP-desktop-worktrees/bancos-20261006-NO-VERSIONAR/pr190/`. Worktree de lectura: `pr190-analisis-20261006`.

| Check | Resultado |
| --- | --- |
| Update branch | **FAIL**: `CONFLICTING` con `main` (`33694da6`) en `app/src/lib/router.ts` |
| Nueve + registradores (como `postgres`, `psql -f`) | PASS; huella `988 \| 2cd5beab…` |
| V1–V5 | PASS (V1 9/9 `t`; V2 todo `t`; V3 todo 0; V4 `f f t t f`; V5 `23 6 * * *, t, f, f, 30, 600`) |
| Catálogo | 17 puertas DEFINER de `postgres` con `search_path` vacío (15 solo `authenticated`, 2 solo `service_role`); núcleo sin EXECUTE para la API; 7 tablas con RLS, sin policies ni grants |
| Reversas | PASS: fuera de orden se niega; las nueve en orden devuelven la huella EXACTA de producción y el censo analítico; también después del gate + limpieza |
| Gate `test-rls.mjs` con `CRM_RLS_EXIGE_LLAMADAS=1` y `…_F4B=1` | PASS: **8 de 2817 → 8 de 3005**, los mismos 8 rojos de fondo; bloque de llamadas **188 ✓ / 0 ✗ / 0 saltadas** |
| Advisors (locales) | sin alertas nuevas de nivel aviso; informativas por diseño (7 «RLS sin policies», 11 índices sin uso en tablas vacías) y una FK sin índice (`llamadas_celular_eventos_asignacion_id_fkey`) |
| Tipos desde el banco | solo añaden (0 retiradas de esquema): 21 objetos de llamadas **y 8 puertas de Bases cargadas B9/B10 que ya están en producción y faltan en el archivo de `main`**. No subidos |
| `npm run check` (cabeza del PR) | PASS, 6141 tests |

🔑 **Por qué el gate del 05/10 dio FAIL:** no era el PR. Al banco le faltaban las filas únicas de
`crm.sla_operacion_control` y `crm.piloto_f8_control` (las siembran sus migraciones; un volcado solo-esquema no las
trae) y todo «registrar llamada» moría con `P0002`. Con las dos filas, los rojos de fondo bajan de 71 a 8.

## Lo que impide fusionar

1. **Conflicto con `main`** en `router.ts`: `main` añadió `consultaCitas` (#201–#203) en la misma posición donde el PR
   añadió `llamadaOrigenId`. Resolver conservando el orden de `main` y el id al final; `router.test.ts` se mezcla solo
   pero queda roto (hay que insertar un `undefined`). Si se resuelve al revés, se rompen los enlaces «Citas por equipo».
2. **[P2] Candidatos más anchos que la regla real** (`private.llamada_celular_candidatos_dueno`, quinta 423–434).
   Reproducido: con un lead ABIERTO de otro analista, 0 candidatos (bien); si además existe un descartado viejo con ese
   número, ese descartado sale como candidato y la llamada se guarda «por revisar» sobre un contacto que «Nuevo lead»
   da por tomado. Tampoco mira «no contactar» ni cliente. Lo vieron el auditor y Codex por separado.
3. **[P2] El antiguo dueño de un reutilizable** ve la llamada de otro analista (reproducido: la ve él, no quien llamó)
   y además puede **descartarla y reasociarla** (`llamada_celular_visible` es la autorización de las ocho puertas).
   Jhosep declaró el «ve»; el «descarta» no. **Decide Miguel.**
4. **[P2] Codex r2** (BLOCK), estático: (F1) la ingesta no revalida al candidato después de esperar el candado del lead;
   (F2) repetir una operación con otro id puede dejar un resultado enlazado a una llamada y con una intención pendiente
   para otra; (F3) un JSON con `\u0000` lo rechaza Postgres antes de entrar a la puerta (comprobado: `unsupported Unicode
   escape sequence`), así que no gasta cupo y sale 503 en vez de 400.
5. **Pantalla (no bloquea publicar: solo vive en la demo):** la bandeja no devuelve `evento_origen_id` (comprobado en el
   banco), así que unir «desde la pestaña» es inalcanzable aunque el test lo dé por bueno con el fixture; el id se pierde
   si el analista tocó «Llamar» en el CRM antes del enlace de la macro; faltan estados de carga/error y «hay más»; tres
   P2 de accesibilidad (foco perdido tras descartar/elegir, contraste de las etiquetas, la búsqueda no anuncia su
   resultado).

## Sin verificar

- El modo real de `crm.sla_operacion_control` en producción (el banco quedó en `legado`). Lectura para Miguel:
  `select modo, revision from crm.sla_operacion_control;`
- F1 y F2 de Codex no se reprodujeron con dos sesiones (Jhosep tiene el banco de carreras).
- Edge desplegada, macro y alta de celulares: fuera de este análisis («instalar no es activar»).

## Decisiones de Miguel (06/10) y comentario publicado

- **Antiguo dueño de un reutilizable: ni verla ni tocarla.** Mientras nadie tome el lead, la llamada de otro analista
  queda oculta para el antiguo dueño y su cadena; gerencia sí la ve; le aparece a quien lo tome.
- **Números tomados o vetados: no se guarda.** Si el número tiene un lead abierto de otro analista, está en «no
  contactar» o ya es cliente, se trata como número sin lead (la misma regla que «Nuevo lead»).
- Comentario publicado en el #190 con todo lo anterior y turno para Jhosep:
  `https://github.com/avanza-digital/avancecorp-crm/pull/190#issuecomment-6020430364`.

## Siguiente paso

Turno para **Jhosep**: resolver el conflicto y escribir la décima migración (candidatos, revalidación bajo candado,
reserva única del resultado, U+0000) con sus pruebas. Con la décima, repetir aquí: nueve + décima, gate (banco ya arreglado) y fusionar.

**06/10 — SLA de producción medido (Miguel con `!`):** `crm.sla_operacion_control` está en **`activo`** (revisión 1, activado el
07/09 04:03 UTC, con política de adopción). El ensayo del #190 se hizo con el banco en **`legado`** (fila sembrada con los
valores por defecto) ⇒ su PASS no cubre el modo real: repetirlo en `activo`, sembrando la política como en producción
(la activación y las políticas vienen de `20260907024903_crm_sla_nucleo_operativo_escritura.sql`).

**06/10 — la sesión a2 se CERRÓ (orden de Miguel).** El #190 queda SIN sesión: cuando Jhosep suba la décima, abrir una nueva y empezar por la nota del vault «Llamadas desde el celular - analisis del PR 190 (2026-10-06)». Se CONSERVA todo lo del #190: banco `avancecorp-pr190-20261006` (parado), worktree `pr190-analisis-20261006`, `bancos-20261006-NO-VERSIONAR/pr190/`; y lo del 02/10: worktree `llamadas-f2-20261002` (commits `897f9553` y `60a926f8` SOLO en la rama local `feat/llamadas-f2`), `llamadas-banco-20261002-NO-VERSIONAR/` y el stack `avancecorp-llamadas-20261002` APAGADO (volúmenes intactos).

**06/10 ~12:00 — para quien retome el #190:** producción confirma la huella del banco (933 funciones crm+private = `2c2f2612…`). Con el control en `activo`, repetir «registrar llamada» v4/v5 y Deshacer antes del visto bueno (el 188/188 se midió en `legado`). El VIVO pasó a `afae7b59` (B11) = `avancecorp/main`: el #190 también tiene que ponerse al día con eso.

## Novedades del 06/10 ~12:10 Lima (traspaso a la sesión `avancecorp-pr190-correcciones-20261006-b1`)

- **Jhosep respondió (17:00 UTC):** dejó la rama `crm/llamadas-190-integrar-jhosep-20261006` sobre `ae2435e2` (se adopta
  con `--ff-only`): fusión con `main` `33694da6` y `router.ts` resuelto; migraciones `20261006150154` (bandeja y detalle
  devuelven `evento_origen_id`) y `20261006150254` (salud sin la hora exacta); planes F4C/F4D/F4E. **La migración de los
  cinco P2 la escribe el lado de Miguel**, numerada después de `20261006150254`. No suben nada más al #190.
- **`main` ya es `afae7b59`** (Bases cargadas B11, #204) y está abierta la #205 (solo ledger): hay que integrarlos
  (`test-rls.mjs` y `MIGRACIONES.md` chocan con lo de llamadas).
- **Producción hoy:** crm+private `934 | 2f359f3e…` (B11 aplicada), `crm.sla_operacion_control` = **activo / rev 1**. El
  banco `avancecorp-pr190-20261006` está en `933` + las nueve y con el control en `legado`: para el visto bueno hay que
  aplicarle B11 y repetir v4/v5 y Deshacer con el control en activo.
- La sesión de bases cargadas le pasó TODO a la sesión nueva por mensaje (hallazgos, decisiones, banco, guiones y evidencia).

## Aviso del 06/10 ~12:30 Lima (la sesión del #190 ya no estaba abierta para recibirlo)

- Por orden de Miguel se borraron los bancos y worktrees de BASES: ya **no existen** el banco `avancecorp-b10-20261004` ni
  `bancos-20261006-NO-VERSIONAR/b11/` (se habían dado «como referencia» en el traspaso). **Lo de llamadas está intacto:**
  banco `avancecorp-pr190-20261006`, worktree `pr190-analisis-20261006` y `bancos-20261006-NO-VERSIONAR/pr190/`.
- La PR #205 (ledger de B11) está fusionada: `avancecorp/main` = `4e7c55bb`. Para llevar el banco del #190 a la paridad de
  hoy, la migración de B11 está en `main`: `supabase/migrations/20261006042144_crm_bases_cargadas_conversion.sql` (como
  `postgres`, en un mensaje).
