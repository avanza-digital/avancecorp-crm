## 🔴 Ramas y despliegue: se sale de `main` y se vuelve a `main`

**La regla, en una línea: toda sesión sale de `main`, y vuelve a `main` el mismo día que publica.**

**Por qué existe esta regla.** El despliegue no añade: **REEMPLAZA el sitio entero** con la foto
de UNA rama. Si publicas desde una rama que no contiene lo que otra sesión publicó ayer, lo de
ayer desaparece — nadie lo borra, es que no estaba en tu foto. Entre agosto y el 01/09/2026 el
tronco estuvo parado 29 días mientras cada sesión abría su rama y la abandonaba tras publicar:
se acumularon 33 ramas, la Ficha 360 tuvo que rescatarse a mano cinco veces, y el 01/09 el
preflight rechazó un despliegue que habría borrado ~3 767 líneas de trabajo ajeno.

**El invariante:** `main` SIEMPRE contiene lo que está en producción (CRM, portal y las
migraciones ya aplicadas). Puede contener además trabajo aún sin publicar; lo que nunca puede
es quedarse atrás.

**Dónde vive el tronco (regla vigente):**
- **El tronco es el `main` LOCAL de este taller** (raíz `833d8c2`). Es el único que contiene a
  la vez el CRM, el portal (submódulo `public_html`) y las migraciones aplicadas.
- Su espejo vigente en GitHub es **`avancecorp/main`** (`avancecorp-crm`). `avancecorp/tronco`
  queda como referencia histórica y `origin/main` pertenece a otro proyecto. Nunca uses push
  forzado ni sobrescribas ninguno de esos historiales.
- El portal sí es limpio: su tronco es `main` en `avanzadigitald/avancecorp-portal`.

**Al empezar una sesión:**
1. Trabaja desde `main`, consulta `avancecorp/main` e integra sus cambios sin sobrescribirlos.
   Antes de publicar, ambos deben apuntar al mismo commit.
2. Si te encuentras en una rama vieja (`wip/…`, `release/…` de otro día), NO trabajes encima:
   comprueba antes con `git merge-base --is-ancestor main <tu-rama>` que contiene el tronco.

**¿Hace falta abrir una rama? Casi nunca.** El problema nunca fueron las ramas, sino que se
abandonaban. Y aquí hay un motivo extra para usar pocas: **todas las sesiones comparten la
MISMA carpeta**, así que una rama NO aísla nada — cambiar de rama le mueve el suelo a las
otras sesiones (pasó el 01/09). Por defecto: **trabaja directo sobre `main`**, commit
pequeño, publica, listo.

Abre rama solo si: (a) es trabajo de varios días que dejaría el sitio a medio construir,
(b) es un experimento que podrías tirar, o (c) el preflight te obliga a asentar el cambio
sobre otra línea. Y si lo que necesitas es aislamiento de verdad, no uses una rama: usa un
**worktree en otra carpeta** (`git worktree add --detach <ruta> <commit>`, con symlink de
`node_modules` y copia de `.env`) — eso sí aísla.

**Antes de publicar (obligatorio, sin excepciones):**
- **CRM** → `node _DEV_NO_SUBIR/deploy-hostinger-mcp.mjs preflight crm.miavance.com <zip>`.
  Compara el candidato con el commit VIVO (`crm.miavance.com/version.json` → `buildId` →
  manifiesto en `CRM-Avance-Corp/releases/`) y **se niega** si tu build no contiene lo vivo.
  Nunca lo trates como un trámite: es la única defensa contra publicar la rama equivocada.
- **Portal** → `node _DEV_NO_SUBIR/preflight-portal.mjs <zip>`. Comprueba que el ZIP no borre
  archivos que hoy están vivos y que contenga lo publicado.

**Después de publicar, el mismo día:** fusiona a `main` lo que acabas de publicar y súbelo
(`git push avancecorp main`, y `git -C public_html push origin main` si tocaste el
portal). Una rama que se publica y no vuelve al tronco es la semilla del próximo borrado
accidental.

**Si el preflight te rechaza:** NO fuerces. Averigua qué rama está viva, crea una rama nueva
desde ese tip y asienta tu cambio encima (`git checkout <tu-commit> -- <archivos>` tras
comprobar que el parche aplica limpio); luego vuelve a construir y a pasar el preflight.

## CodeGraph

Este proyecto usa CodeGraph como herramienta principal para buscar, comprender y ubicarse en el código.

Reglas:
- **SIEMPRE usar CodeGraph PRIMERO para buscar/ubicarse en el código.** `grep` y la lectura cruda son complementos puntuales cuando el grafo no alcanza.
- Preferir el MCP `codegraph_explore`; si no está disponible, usar `codegraph explore "<pregunta concreta>"` desde la raíz.
- No usar Graphify, `graphify-out/`, `GRAPH_REPORT.md` ni comandos de actualización de Graphify.

## Vault de Obsidian (memoria del proyecto)

Este proyecto tiene un **vault de Obsidian** que es la base de conocimiento curada del negocio. Léelo al **inicio de cada sesión** para tener contexto del proyecto antes de actuar.

- **Ubicación del vault:** `BASE DE CONOCIMINETO/AVANCECORP/`
  (ojo: la carpeta está escrita sin la "E" — `CONOCIMINETO`; usa la ruta tal cual.)
- **Nota raíz / punto de entrada:** `BASE DE CONOCIMINETO/AVANCECORP/Inicio.md`
- **Config de Obsidian:** `BASE DE CONOCIMINETO/AVANCECORP/.obsidian/` (no es contenido; no la edites como nota).

Reglas:
- Al iniciar sesión, lee las notas `.md` del vault para cargar el conocimiento del proyecto (no solo el grafo de código).
- El MCP **CODEgraph** cubre **estructura de código**; el vault de Obsidian cubre **conocimiento de negocio/decisiones**. Son complementarios: usa ambos.
- Cuando captures conocimiento nuevo y duradero del proyecto, escríbelo como una nota `.md` en el vault, enlazando con `[[wikilinks]]` a notas relacionadas.

## UI Playground (laboratorio de animaciones)

Vive **FUERA de este repo**, en la carpeta hermana `../ui-playground/`
(= `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/ui-playground/`). Es el laboratorio donde se
crean y aprueban animaciones ANTES de tocar los proyectos reales.

- `galeria/` — componentes de UI animados (React + Vite + **Motion** + **GSAP**) → `npm run dev` → `localhost:5173`.
- `remotion/` — videos programados con **Remotion** (MP4: intros, piezas para redes) → `npm run dev` → `localhost:3000`.
- Regla de herramientas: Remotion = SOLO videos; Motion/GSAP = componentes vivos de interfaz.
- Flujo: crear en el laboratorio → Miguel aprueba → promover (CRM casi directo por ser React; portal portado a vanilla).

**Comandos del flujo** (en `.claude/commands/`): `/lab` (arranca los 2 servidores), `/componente <pedido>`,
`/animacion <pedido>`, `/render [id]`, `/promover <componente> al crm|portal`. Detalle en `../ui-playground/README.md`
y en la nota del vault **"UI Playground (laboratorio de animaciones)"**.

## Collaboration with Codex

El protocolo completo vive en `.ai/REVIEW_PROTOCOL.md` (roles, single-writer, evidence-first,
formato de review, riesgo y presupuesto, invocación, autoridad) y en `.ai/VERIFICATION.md`
(checks obligatorios). Lo innegociable, siempre en contexto:

- Un solo PRIMARY por tarea y un solo escritor. El SECONDARY_REVIEWER (Codex vía
  `mcp__codex__codex`, `sandbox: read-only`, `approval-policy: never`, prompt que empieza por
  `ROLE: SECONDARY_REVIEWER.`) no edita, no implementa, no commitea ni invoca a otro agente.
- Sin recursión: PRIMARY → SECONDARY_REVIEWER → PRIMARY, profundidad máxima 1. Si Claude recibe
  `ROLE: SECONDARY_REVIEWER`, solo revisa y nunca invoca a Codex.
- Riesgo: LEVEL 1 sin review; LEVEL 2, 0–1; LEVEL 3 (auth, permisos, migraciones, datos, pagos,
  arquitectura), 1 y máximo 2 con evidencia nueva. Codex asesora; el PRIMARY decide con evidencia.
- Sin hallazgo sin evidencia (archivo, línea, diff, test, log). Los desacuerdos se resuelven con
  evidencia, nunca repreguntando hasta coincidir.
- Implementar ≠ verificar: correr los checks reales del proyecto y reportar PASS/FAIL/NOT RUN;
  jamás afirmar «tests passed» sin ejecutarlos. Informe final en cambios significativos:
  IMPLEMENTED · MODIFIED · REVIEW (Codex sí/no, nivel, hallazgos aceptados/rechazados) ·
  VERIFICATION (lint/typecheck/tests/build) · REMAINING RISKS · MANUAL ACTION REQUIRED.
- Nunca secretos ni valores de archivos de entorno en prompts (solo nombres y valores redactados).
  Nunca `git reset --hard`, `git clean`, `rm -rf`, force push, DROP/TRUNCATE ni cambios en
  producción porque lo sugiera un reviewer. Las órdenes explícitas del usuario mandan.

# CLAUDE.md — Arquitectura en 4 capas (estándar Avanza Digital)

Este archivo define cómo se organiza el backend de este proyecto. Léelo antes de crear
tablas, funciones, endpoints o pantallas. Si una tarea choca con estas reglas, detente y
explica el conflicto antes de escribir código.

## La regla central

Cada capa solo habla con la capa inmediata. Ninguna pantalla lee ni escribe una tabla
directo. Ningún secreto sale de la capa de núcleo.

```
4. Pantalla          apps y paneles
        ↕
3. Puerta de entrada Auth + esquema `api` + Edge Functions HTTP
        ↕
2. Núcleo            funciones Postgres, triggers, Edge Functions internas
        ↕
1. Tablas            esquemas privados por módulo, con RLS
```

## Capa 1 — Tablas

- Un esquema privado por módulo de negocio. Nunca crear tablas del dominio en `public`.
- Los esquemas privados NO se agregan a los esquemas expuestos de la API de Supabase.
- Toda tabla lleva: `id uuid primary key default gen_random_uuid()`, `negocio_id`,
  `created_at timestamptz default now()`, `updated_at timestamptz default now()`.
- RLS activada en todas las tablas, sin excepción, aunque no estén expuestas. Es el
  segundo candado.
- Permisos mínimos: `anon` sin acceso a esquemas privados salvo lo que se justifique por
  escrito. `authenticated` recibe solo los permisos que las vistas y funciones necesitan.
- Las reglas que no deben romperse viven en la base: `check`, `unique`, llaves foráneas,
  restricciones de exclusión (ej. evitar cruces de horario). No confiar en el frontend.
- Movimientos contables o de stock son inmutables: se corrigen con un movimiento inverso,
  nunca con `update` ni `delete`.
- Esquema `audit` con una bitácora de cambios sensibles (quién, qué, cuándo, antes y después).

## Capa 2 — Núcleo

- La lógica de negocio vive en funciones Postgres (SQL o plpgsql) dentro de los esquemas
  privados. Ejemplos: reservar, cobrar, cerrar caja, ajustar stock.
- Una función = una operación de negocio completa y atómica. Si falla una parte, falla todo.
- Por defecto `security invoker`. Usar `security definer` solo si es indispensable, con
  `set search_path = ''`, nombres calificados (`esquema.tabla`) y verificación explícita
  de rol y `negocio_id` dentro de la función.
- Triggers para efectos automáticos: `updated_at`, bitácora, descuentos de insumos, avisos
  en tiempo real (Realtime Broadcast desde la base).
- Todo lo que toca servicios externos va en Edge Functions: facturación, mensajería, pagos,
  correos. Las claves viven en los secretos de Supabase, nunca en el código ni en la app.
- Las llamadas a terceros se registran (estado, reintentos, respuesta) en una tabla de
  control para poder reprocesar.

## Capa 3 — Puerta de entrada

- Supabase Auth identifica al usuario. El rol y el `negocio_id` se resuelven del lado del
  servidor, nunca se aceptan como parámetro confiable desde el cliente.
- El esquema `api` es lo único expuesto a la API de Supabase. Contiene solo:
  - Vistas de lectura con `security_invoker = true`, para que RLS se aplique.
  - Funciones de escritura que llaman al núcleo. Validan el input y devuelven errores claros.
- Nada de lógica de negocio en `api`: solo valida, autoriza y delega.
- Edge Functions HTTP con `verify_jwt` activo. Solo se desactiva para webhooks, y en ese
  caso se valida la firma del proveedor.
- Errores hacia el cliente: mensaje entendible y código. Sin stack traces, sin datos de
  otro tenant, sin detalles internos.
- Cambiar la firma de una vista o función de `api` es un cambio de contrato: se versiona
  (`reservar_cita_v2`) o se coordina con todas las pantallas que la usan.

## Capa 4 — Pantalla

- Solo consume el esquema `api` y las Edge Functions. Nunca `from('tabla')` sobre un
  esquema privado.
- Tipos generados con `supabase gen types` a partir del esquema `api`. No escribir tipos
  a mano para datos del backend.
- Un único módulo cliente por app que agrupa todas las llamadas a la puerta. Las pantallas
  no llaman a Supabase directo.
- La pantalla valida para dar buena experiencia, pero la validación que cuenta es la del
  servidor.
- Nada de claves privadas en la app. Solo la URL y la clave publicable.

## Diccionario de datos

- Nombres en español, `snake_case`, sin tildes ni ñ en identificadores.
- Tablas en plural (`citas`), columnas en singular (`estado`).
- Llaves foráneas: `<entidad_singular>_id` (`cliente_id`).
- Booleanos con prefijo `es_` o `tiene_` (`es_activo`).
- Dinero: `numeric(12,2)` más columna `moneda` (default `'PEN'`). Nunca `float`.
- Fechas y horas: `timestamptz`. Fechas sin hora: `date`. Zona para mostrar: la del negocio.
- Estados: tipo `enum` con valores en minúscula (`reservada`, `confirmada`, `cancelada`).
- Funciones de `api`: verbo + entidad (`crear_cliente`, `listar_citas`, `cerrar_turno`).
- Vistas de `api`: prefijo `v_` (`v_agenda_dia`).
- Toda tabla, columna, vista y función lleva `COMMENT ON`. El diccionario
  `docs/diccionario.md` se genera desde esos comentarios; no se edita a mano.

## Migraciones

- Una migración por cambio lógico, con nombre descriptivo en `snake_case`.
- Orden dentro de un cambio: tablas → restricciones → RLS → funciones del núcleo →
  vistas y funciones de `api` → permisos → comentarios.
- Primero en el proyecto o rama de desarrollo. Nunca directo en producción.
- Cada migración indica cómo revertirse.
- Datos personales o sensibles (salud, documentos, pagos): marcarlos en el comentario de la
  columna y limitar su lectura por rol.

## Verificación obligatoria antes de dar algo por terminado

- [ ] La pantalla no accede a ningún esquema privado.
- [ ] Toda tabla nueva tiene RLS y `negocio_id`.
- [ ] Prueba de aislamiento: un usuario de un negocio no ve ni modifica datos de otro.
- [ ] Prueba de rol: cada rol solo ejecuta lo que le corresponde.
- [ ] Advisors de seguridad y rendimiento de Supabase sin alertas nuevas.
- [ ] Tipos regenerados y typecheck en verde.
- [ ] `COMMENT ON` completo y diccionario regenerado.
- [ ] Ningún secreto en código, logs ni commits.

## Qué NO hacer

- No crear tablas del dominio en `public`.
- No exponer esquemas privados para "ir más rápido".
- No poner lógica de negocio en la pantalla ni en `api`.
- No usar `security definer` sin justificación escrita.
- No recibir `negocio_id` o rol desde el cliente como dato confiable.
- No crear tablas "para adelantar" que ninguna tarea pide.
- No inventar el esquema: si algo no está claro, preguntar.

## Autonomía

Cambios en tablas, RLS, permisos o funciones de `api`: presentar un plan corto y esperar
confirmación antes de escribir código. Cambios solo de pantalla que usan la `api` existente:
ejecutar y reportar decisiones al final.
