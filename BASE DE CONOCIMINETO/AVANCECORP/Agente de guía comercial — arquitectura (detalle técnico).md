# Guía comercial de Avance Corp — arquitectura definitiva

> Síntesis del panel (3 lentes, ganador unánime: **determinista**). Incorpora injertos nombrados de `hibrido-eventos` y `llm-servidor`, y corrige las 12 afirmaciones falsas o imprecisas que el panel marcó. Fecha: 2026-07-19.

---

## 1. La arquitectura elegida y por qué ganó

**`lib/guia/` — motor de reglas determinista, puro, que corre en el navegador; recetario de mensajes segmentado por `estado_clave`, curado offline con IA y aprobado por Miguel; una sola función SQL nueva.**

El agente **no es un modelo en la ruta caliente**. Es:

1. Un motor puro `senalesDe(ambito, ahora, opts)` que extiende `lib/inteligencia.ts` a **sujeto polimórfico** (lead **o cliente o contrato**) y emite `Senal[]` rankeadas.
2. Un **recetario** indexado por `estado_clave = regla | moneda | banda_monto | categoría` — la mejor idea de `hibrido-eventos`, injertada — que convierte la capacitación de Miguel en **datos versionados y aprobados**, no en prompts.
3. **Render en dos tiempos** (injerto de `llm-servidor`): las piezas del bundle pintan a 0 ms; el override de BD las sustituye in situ cuando carga, con el origen visible.
4. Una franja `<GuiaGestion/>` en **Clientes y Contratos** — las dos únicas pantallas que la fuerza de ventas ve hoy — sin tocar `config.ts`, `router.ts` ni `App.tsx`.

### Por qué ganó los tres lentes

| Lente | Razón decisiva |
|---|---|
| **Valor** | Es el único que un vendedor real usa **esta semana**: pinta en <1 ms en la pantalla donde ya aterriza (`App.tsx` sanea a vista base `'clientes'`), y `screens/clientes.tsx:302` devuelve `stats = null` para un vendedor — hay un hueco literalmente vacío arriba de la tabla. Valor entregado = valor × P(se despliega). |
| **Entrega** | Cero migraciones para la primera fase. Verifiqué que **todos** los helpers SQL de su única migración crítica existen en prod (`private.rol_crm`, `private.es_lector_global`, `private.vendedor_ids_visibles`) y que las columnas también (`public.contratos.numero_contrato`, `public.perfiles.numero_cuenta_usd`). Es el único diseño del que se puede afirmar que su SQL compila hoy. |
| **Riesgo** | Radio de explosión **cero PII** ante un bug del motor: corre sobre datos que la RLS ya entregó. Esto importa porque —hecho verificado y omitido por los tres diseños— **todas las tablas de `crm` y `public` tienen `relforcerowsecurity = false` y `owner = postgres`**, luego **toda función `SECURITY DEFINER` lee saltándose la RLS**. En ese terreno la métrica correcta es *cuántos `WHERE` escritos a mano añades*: este diseño añade **uno**. |

### La tensión central, resuelta sin mentir

Miguel pidió *"que les recomiende mensajes según la etapa del prospecto"*. Hoy eso es **inejecutable tal cual**: `crm.leads = 0` y `FUNCIONES_LEADS_APROBADAS = false` (`lib/config.ts:99`) oculta Pipeline a vendedor/supervisor. La respuesta honesta no es fingir: es **cambiar el sujeto de la etapa sin cambiar el mecanismo** — hoy la etapa es la del **cliente en su ciclo de inversión** (§6), mañana la del lead, con el mismo motor y el mismo recetario.

---

## 2. Diagrama de componentes

```
╔═══════════ OFFLINE — una vez por versión del corpus, sin usuarios, sin producción ═══════════╗
║                                                                                              ║
║  Material de ventas de Miguel          scripts/guion/destilar.mjs           Miguel (dueño)   ║
║  (PDF/DOCX/video → .md)          ────► Batch API · claude-opus-4-8    ────► APRUEBA pieza    ║
║  docs/capacitacion/*.md                 ├ entrada: SOLO FichaAnonima        por pieza        ║
║   frontmatter:                          │  (whitelist, cero UUID)                │           ║
║   estado: vigente|corregido|retirado    ├ + pasaje 'vigente' del curso           │           ║
║   nota_conciliacion: "…"                └ + barandillas del vault                │           ║
║   ▲                                          │                                   │           ║
║   └── CONCILIACIÓN BLOQUEANTE ───────────────┤ borradores/*.md ──────────────────┘           ║
║       contra el vault (folklore purgado)     │                                               ║
║                              ┌───────────────┴───────────────┐                               ║
║                              ▼                               ▼                               ║
║             src/lib/guia/guion-base.ts            scripts/guion/seed.sql                     ║
║             GUION_BASE as const  (bundle,         → crm.fijar_guion_pieza(...)               ║
║              fallback garantizado, 0 ms)             estado='borrador'                       ║
╚══════════════════════════════╪═══════════════════════════════╪═══════════════════════════════╝
                               │                               │
═══════════════════════════════╪═══════════ RUNTIME ═══════════╪═══════════════════════════════
  DATOS (RLS ya aplicada)      │                               │
  ┌──────────────────────────┐ │                     useGuion()  TanStack, staleTime 30 min
  │ crm.clientes_basicos     │ │                     ├─ crm.guion_piezas (estado='aprobada')
  │   useClientes()   ✓ HOY  │ │                     └─ crm.guia_reglas (activa, presupuesto)
  │ crm.contratos_cartera    │ │                        FALLA → GUION_BASE + reglas del bundle
  │   useContratos()  ✓ HOY  │ │                               │
  │ crm.salud_cartera_fn ★NEW│ │                               │
  │   useSaludCartera() 5 min │ │                              │
  │ leads/actividades/tareas │ │                               │
  │   store  ── HOY VACÍO ── │ │                               │
  └───────────┬──────────────┘ │                               │
              │   useTipoCambio() ─┐  (TC vive AQUÍ, no en SQL) │
              ▼                    ▼                            │
  ┌─────────────────────────────────────────┐                   │
  │  lib/guia/motor.ts                      │                   │
  │  senalesDe(ambito, ahora, opts)         │                   │
  │  reglas/cobranza.ts  ← VIVAS            │                   │
  │  reglas/contratos.ts ← VIVAS            │                   │
  │  reglas/clientes.ts  ← VIVAS            │                   │
  │  reglas/leads.ts     ← DORMIDA          │                   │
  │  reglas/agenda.ts    ← DORMIDA          │                   │
  │        │                                │                   │
  │        ▼ ranking LEXICOGRÁFICO           │                  │
  │  banda → severidad → orden.peso → desde │                   │
  │  → clave  (orden TOTAL, sin parpadeo)   │                   │
  └────────────────┬────────────────────────┘                   │
                   │ Senal[]  (sin texto todavía)               │
                   ▼                                            │
  ┌─────────────────────────────────────────┐◄──────────────────┘
  │  lib/guia/recetario.ts                  │
  │  estadoClave(senal) → 'regla|PEN|alta|upgrade'                │  LOOKUP O(1),
  │  elegirPieza(clave, guion)  ← cascada de fallback             │  en el navegador
  │  validarPieza(pieza)        ← LISTA NEGRA EN RUNTIME ★        │
  │  renderPieza(pieza, vars)   ← interpola nombre/monto/fecha    │
  └────────────────┬────────────────────────┘
                   ▼  ResultadoGuia { visibles, ocultas, estado, frescura }
  ┌──────────────────────────────────────────────────────────────────────┐
  │  components/app/guia-gestion.tsx                                     │
  │   montado en screens/clientes.tsx:344 y screens/contratos.tsx:247    │
  │   ≤3 tarjetas + "+N más" verificable · PanelVacio · PanelError       │
  │       └─ [Enviar por WhatsApp] → mensaje-sugerido.tsx (Dialog)       │
  │            <Textarea EDITABLE> · [¿por qué?] → Cita recuperable      │
  │            [Enviar por WhatsApp]  [Copiar]  [Omitir]                 │
  │  components/app/guia-equipo.tsx  ← MISMOS motivos, ámbito supervisor │
  └───────────────────────┬──────────────────────────────────────────────┘
                          ▼  fire-and-forget, no bloquea, SIN texto renderizado
              crm.registrar_guia_evento(...) → crm.guia_eventos
                          │
                          ▼  (mensual, gerencia)
              crm.guia_atribucion_fn(p_dias) → ¿el hecho se resolvió tras la señal?
```

**Nada de este flujo sale a internet en runtime.** No hay edge `crm-guia`. No hay proveedor de LLM en la ruta caliente. El único tráfico nuevo son dos lecturas cacheadas.

---

## 3. Modelo de datos completo (SQL con RLS)

### Presupuesto de seguridad, declarado

Dado que `relforcerowsecurity = false` y `owner = postgres` en todo `crm`/`public`, **cada `SECURITY DEFINER` es un bypass de RLS cuyo único control es su `WHERE`**. Añadimos:

| Función | ¿Toca PII de clientes? | Control |
|---|---|---|
| `crm.salud_cartera_fn` | **Sí** (lee bancarias, **devuelve solo un booleano**) | `private.vendedor_ids_visibles(auth.uid())` — pasa su propio gate porque la llama el usuario |
| `crm.fijar_guion_pieza` / `aprobar` / `retirar` | No (texto de catálogo) | gate `rol_crm = 'gerencia'` |
| `crm.registrar_guia_evento` | No (solo ids internos) | escribe únicamente la fila de `auth.uid()` |
| `crm.guia_atribucion_fn` | Sí (lectura agregada) | `vendedor_ids_visibles` + gate de gerencia |

**Una sola función lee PII de clientes.** Ese es el presupuesto y no se amplía.

---

### 3.1 `crm.salud_cartera_fn` — la única lectura nueva

`CRM-Avance-Corp/supabase/migrations/20260720000001_crm_salud_cartera_fn.sql`

```sql
set local lock_timeout = '10s';

-- Salud operativa de la cartera propia: qué se cobra pronto y a quién NO se le
-- puede depositar.
--
-- DECISIÓN DELIBERADA: la RLS PERMITIRÍA leer en bloque las 14 columnas
-- bancarias de public.perfiles (verificado: 13 filas legibles bajo el JWT de un
-- vendedor real). Esta función se NIEGA a hacerlo y devuelve solo el veredicto
-- booleano. Un SELECT masivo de bancarias hacia el navegador sería una
-- regresión de superficie, no una feature.
--
-- La moneda del CONTRATO manda: PEN mira numero_cuenta, USD mira
-- numero_cuenta_usd. Son cuentas independientes (regla del portal 2026-06-09).
-- El conteo ingenuo "clientes sin cuenta PEN" produce falsos positivos
-- (CUYA GONZALES: único contrato en USD, con su cuenta USD lista).
--
-- ⚠️ LANDMINE DOCUMENTADA (hallazgo de `hibrido-eventos`, verificado):
--    private.vendedor_ids_visibles(p) devuelve VACÍO si auth.uid() es NULL,
--    porque su primera guarda es
--      `if p_perfil_id is distinct from (select auth.uid())
--          and not private.es_lector_global() then return; end if;`
--    Por tanto esta función SOLO es válida invocada dentro de una sesión de
--    usuario. Cualquier job de pg_cron que la use materializará 0 filas EN
--    SILENCIO. Si algún día hace falta calcular "en nombre de" otro perfil,
--    hay que extraer private.equipo_subarbol (árbol sin política) y dejar el
--    gate en el wrapper. NO se hace ahora porque este diseño no usa cron.
create function crm.salud_cartera_fn(p_dias int default 30)
returns table (
  contrato_id         uuid,
  numero_contrato     text,     -- ⚠️ la columna es numero_contrato, NO `numero`
  cliente_id          uuid,
  cliente_nombre      text,
  moneda              text,
  categoria           text,
  capital             numeric,
  fecha_vencimiento   date,
  proxima_cuota_en    date,
  proxima_cuota_monto numeric,
  tipo_cuota          text,
  falta_cuenta        boolean,  -- veredicto, JAMÁS el número de cuenta
  cuotas_tarde        int,
  cuotas_vencidas     int
)
language sql
stable
security definer
set search_path to ''
as $$
  with visibles as (
    select v as perfil_id
    from private.vendedor_ids_visibles((select auth.uid())) v
  ),
  cart as (
    select c.id, c.numero_contrato, c.cliente_id, c.moneda, c.categoria,
           c.capital, c.fecha_vencimiento,
           p.nombre_completo as cliente_nombre,
           case when c.moneda = 'USD'
                then nullif(btrim(coalesce(p.numero_cuenta_usd, '')), '') is null
                else nullif(btrim(coalesce(p.numero_cuenta,     '')), '') is null
           end as falta_cuenta
    from public.contratos c
    join public.perfiles  p on p.id = c.cliente_id
    where c.estado = 'activo'
      -- ASIMETRÍA REAL: contratos_cartera_fn añade este fallback y
      -- clientes_basicos_fn no. Se replica para no perder contratos cuyo
      -- cliente no aparece en la lista del vendedor.
      and ( p.asesor_perfil_id in (select perfil_id from visibles)
         or (p.asesor_perfil_id is null
             and p.creado_por in (select perfil_id from visibles)) )
  ),
  prox as (
    select distinct on (cp.contrato_id)
           cp.contrato_id, cp.fecha_programada, cp.monto_programado, cp.tipo
    from public.cronograma_pagos cp
    join cart on cart.id = cp.contrato_id
    where cp.estado = 'pendiente'
      and cp.fecha_programada >= (now() at time zone 'America/Lima')::date
      and cp.fecha_programada <  (now() at time zone 'America/Lima')::date
                                 + least(greatest(coalesce(p_dias, 30), 1), 366)
    order by cp.contrato_id, cp.fecha_programada asc
  ),
  tarde as (
    -- cronograma_pagos.estado='vencido' = 0 en TODA la base: el estado no se
    -- usa. El atraso se DERIVA de fechas, nunca se lee del estado.
    select cp.contrato_id,
           count(*) filter (where cp.estado = 'pagado'
                              and cp.fecha_pago_real > cp.fecha_programada)::int as n_tarde,
           count(*) filter (where cp.estado = 'pendiente'
                              and cp.fecha_programada
                                  < (now() at time zone 'America/Lima')::date)::int as n_venc
    from public.cronograma_pagos cp
    join cart on cart.id = cp.contrato_id
    group by cp.contrato_id
  )
  select ct.id, ct.numero_contrato, ct.cliente_id, ct.cliente_nombre,
         ct.moneda, ct.categoria, ct.capital, ct.fecha_vencimiento,
         prox.fecha_programada, prox.monto_programado, prox.tipo,
         ct.falta_cuenta,
         coalesce(tarde.n_tarde, 0), coalesce(tarde.n_venc, 0)
  from cart ct
  left join prox  on prox.contrato_id  = ct.id
  left join tarde on tarde.contrato_id = ct.id;
$$;

comment on function crm.salud_cartera_fn is
  'Cobranza proxima + veredicto de cuenta bancaria faltante (por moneda del contrato) sobre la cartera visible. NUNCA devuelve numeros de cuenta ni CCI. Solo valida dentro de una sesion de usuario: vendedor_ids_visibles devuelve vacio si auth.uid() es NULL.';

revoke all on function crm.salud_cartera_fn(int) from public, anon;
grant execute on function crm.salud_cartera_fn(int) to authenticated;
```

---

### 3.2 `crm.guia_reglas` — kill-switch por fila

> **Injerto de `hibrido-eventos`** (`senal_reglas.activa` + `presupuesto_por_dueno`). Corrige el hueco real del diseño ganador: con `FAMILIAS_ACTIVAS` en el bundle, apagar una regla que molesta a 17 vendedores exige un redeploy — inaceptable en un repo con carreras de deploy documentadas (2026-07-17) y un rollback que eligió el artefacto equivocado (2026-07-18).

`20260720000002_crm_guia_reglas.sql`

```sql
create table crm.guia_reglas (
  clave        text primary key,          -- 'cobranza.sin_cuenta'
  familia      text not null
               constraint guia_familia_valida
               check (familia in ('cobranza','contratos','clientes','leads','agenda','meta','equipo')),
  banda        smallint not null check (banda between 0 and 3),
  -- 0 irreversible · 1 ingreso en riesgo · 2 higiene · 3 informativa
  audiencia    text not null default 'vendedor'
               constraint guia_audiencia_valida
               check (audiencia in ('vendedor','supervisor','ambos')),
  activa       boolean not null default false,   -- nace APAGADA: 0 filas, 0 riesgo
  presupuesto  smallint not null default 3 check (presupuesto between 1 and 20),
  nota         text not null default '',
  actualizado_en timestamptz not null default now()
);

comment on table crm.guia_reglas is
  'Interruptor por fila del motor de guia. Apagar una regla ruidosa o peligrosa es un UPDATE, no un redeploy. Si la tabla no carga, el bundle usa REGLAS_BASE (fail-safe hacia lo conocido).';

alter table crm.guia_reglas enable row level security;

create policy guia_reglas_select on crm.guia_reglas
  for select to authenticated
  using ( (select private.rol_crm((select auth.uid()))) is not null
          or (select private.es_lector_global()) );
-- Sin policies de escritura: solo gerencia, por RPC.

grant select on crm.guia_reglas to authenticated;
grant select, insert, update on crm.guia_reglas to service_role;
```

---

### 3.3 `crm.guion_piezas` — el recetario segmentado

> **Injerto doble.** De `hibrido-eventos`: la clave es `estado_clave = regla|moneda|banda_monto|categoría`, **no** una rotación por `hash(sujeto.id) % n`. Rotar da variedad; segmentar da **criterio** — el mensaje de una renovación de S/ 170,000 a un cliente que pagó puntual no es el de una de S/ 5,000, y el de un candidato a **upgrade** no es el de una renovación plana (dato duro: upgrade 36 vs renovación 6, 6×).
> De `llm-servidor`: el ciclo `borrador | aprobada | retirada` con `aprobada_por/aprobada_en`, y la **cita recuperable** (documento + sección + ancla) que alimenta el botón "¿por qué?".

`20260720000003_crm_guion_piezas.sql`

```sql
create table crm.guion_piezas (
  id             uuid primary key default gen_random_uuid(),

  -- Lookup: 'cobranza.sin_cuenta|PEN|alta|upgrade'. El motor consulta con
  -- cascada de fallback (§4.4), así que el catalogo puede ser esparso.
  estado_clave   text not null,
  canal          text not null default 'whatsapp'
                 constraint guion_canal_valido
                 check (canal in ('whatsapp','llamada','reunion','correo')),

  -- Placeholders: lista CERRADA {{nombre}} {{capital}} {{fecha}} {{dias}} {{contrato}}
  texto          text not null
                 constraint guion_texto_cuerdo check (length(texto) between 10 and 1200),
  fundamento     text not null default ''
                 constraint guion_fundamento_cuerdo check (length(fundamento) <= 800),

  -- CITA RECUPERABLE: lo que convierte una plantilla en asesoría.
  fuente_doc     text not null default '',   -- 'modulo-3-renovaciones'
  fuente_seccion text not null default '',   -- 'Abrir la conversación 60 días antes'
  fuente_ancla   text not null default '',   -- '#p12'
  fuente_extracto text not null default ''   -- el párrafo literal del curso
                 constraint guion_extracto_cuerdo check (length(fuente_extracto) <= 2000),

  estado         text not null default 'borrador'
                 constraint guion_estado_valido
                 check (estado in ('borrador','aprobada','retirada')),
  origen         text not null default 'llm'
                 constraint guion_origen_valido
                 check (origen in ('miguel','llm','reglas')),

  version        int not null default 1,
  aprobada_por   uuid references public.perfiles(id) on delete set null,
  aprobada_en    timestamptz,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

comment on table crm.guion_piezas is
  'Recetario de mensajes por (estado_clave, canal). SOBRESCRIBE a GUION_BASE del bundle cuando estado=aprobada. Ningun vendedor ve un texto que gerencia no firmo.';

-- Una sola pieza VIVA por (estado_clave, canal).
create unique index guion_piezas_aprobada
  on crm.guion_piezas (estado_clave, canal) where estado = 'aprobada';
create index guion_piezas_borradores
  on crm.guion_piezas (estado, creado_en desc) where estado = 'borrador';

alter table crm.guion_piezas enable row level security;

create policy guion_piezas_select on crm.guion_piezas
  for select to authenticated
  using (
    ( estado = 'aprobada'
      and (select private.rol_crm((select auth.uid()))) is not null )
    or (select private.rol_crm((select auth.uid()))) = 'gerencia'
    or (select private.es_lector_global())
  );
-- Sin INSERT/UPDATE/DELETE para authenticated: todo por RPC.

grant select on crm.guion_piezas to authenticated;
grant select, insert, update on crm.guion_piezas to service_role;

-- ── Historial dentro de crm, NO trigger a public.audit_log ───────────────────
-- DECISIÓN CONSCIENTE: private.log_audit_crm vuelca la fila completa a
-- public.audit_log, que tiene grants ALL para anon Y authenticated (salvada
-- solo por RLS). El texto del guion no es PII, pero heredar ese patrón frágil
-- por comodidad no se hace. El historial vive en crm, con su propia RLS.
create table crm.guion_historial (
  id           bigint generated always as identity primary key,
  pieza_id     uuid not null references crm.guion_piezas(id) on delete cascade,
  estado_clave text not null,
  version      int not null,
  estado       text not null,
  texto        text not null,
  actor        uuid,
  ts           timestamptz not null default now()
);
alter table crm.guion_historial enable row level security;
create policy guion_historial_select on crm.guion_historial
  for select to authenticated
  using ( (select private.rol_crm((select auth.uid()))) = 'gerencia'
          or (select private.es_lector_global()) );
grant select on crm.guion_historial to authenticated;

-- ── RPCs de escritura (gerencia) ─────────────────────────────────────────────
create function private.guia_es_gerencia() returns boolean
language sql stable security definer set search_path to '' as $$
  select exists (
    select 1 from crm.equipo e join public.perfiles p on p.id = e.perfil_id
    where e.perfil_id = (select auth.uid())
      and e.rol_crm = 'gerencia' and e.activo and p.activo
  );
$$;

create function crm.fijar_guion_pieza(
  p_estado_clave text, p_canal text, p_texto text, p_fundamento text,
  p_fuente_doc text, p_fuente_seccion text, p_fuente_ancla text,
  p_fuente_extracto text, p_origen text default 'llm'
) returns crm.guion_piezas
language plpgsql security definer set search_path to ''
as $$
declare v_actor uuid := (select auth.uid()); v_fila crm.guion_piezas;
begin
  if v_actor is null or not private.guia_es_gerencia() then
    raise exception 'Solo Gerencia puede editar el guion comercial' using errcode = '42501';
  end if;

  -- LISTA NEGRA REGULATORIA como CHECK de escritura, no solo como test de CI.
  -- (Injerto de llm-servidor: el validador debe correr donde el texto ENTRA,
  --  porque crm.guion_piezas SOBRESCRIBE al bundle en runtime.)
  if (p_texto || ' ' || coalesce(p_fundamento,'')) ~*
     '(garantiz|sin riesgo|libre de riesgo|asegurad|respaldad|rentabilidad fija|dep[óo]sito a plazo|\ySBS\y|\ySMV\y|\yFSD\y|fondo de seguro)'
  then
    raise exception 'El texto contiene lenguaje regulatoriamente prohibido' using errcode = '22023';
  end if;

  insert into crm.guion_piezas
    (estado_clave, canal, texto, fundamento,
     fuente_doc, fuente_seccion, fuente_ancla, fuente_extracto, origen, estado)
  values
    (p_estado_clave, coalesce(p_canal,'whatsapp'), p_texto, coalesce(p_fundamento,''),
     coalesce(p_fuente_doc,''), coalesce(p_fuente_seccion,''), coalesce(p_fuente_ancla,''),
     coalesce(p_fuente_extracto,''), coalesce(p_origen,'llm'), 'borrador')
  returning * into v_fila;

  insert into crm.guion_historial (pieza_id, estado_clave, version, estado, texto, actor)
  values (v_fila.id, v_fila.estado_clave, v_fila.version, 'borrador', v_fila.texto, v_actor);
  return v_fila;
end;
$$;

create function crm.aprobar_guion_pieza(p_id uuid) returns crm.guion_piezas
language plpgsql security definer set search_path to ''
as $$
declare v_actor uuid := (select auth.uid()); v_fila crm.guion_piezas;
begin
  if v_actor is null or not private.guia_es_gerencia() then
    raise exception 'Solo Gerencia puede aprobar el guion comercial' using errcode = '42501';
  end if;
  -- Retira la vigente de esa (estado_clave, canal) antes de promover.
  update crm.guion_piezas p set estado = 'retirada', actualizado_en = now()
   where p.estado = 'aprobada'
     and (p.estado_clave, p.canal) = (select g.estado_clave, g.canal
                                        from crm.guion_piezas g where g.id = p_id);
  update crm.guion_piezas set estado = 'aprobada', aprobada_por = v_actor,
         aprobada_en = now(), actualizado_en = now(), version = version + 1
   where id = p_id and estado = 'borrador'
  returning * into v_fila;
  if v_fila.id is null then raise exception 'Pieza no encontrada o ya procesada'; end if;

  insert into crm.guion_historial (pieza_id, estado_clave, version, estado, texto, actor)
  values (v_fila.id, v_fila.estado_clave, v_fila.version, 'aprobada', v_fila.texto, v_actor);
  return v_fila;
end;
$$;

create function crm.retirar_guion_pieza(p_id uuid) returns void
language plpgsql security definer set search_path to ''
as $$
declare v_actor uuid := (select auth.uid());
begin
  if v_actor is null or not private.guia_es_gerencia() then
    raise exception 'Solo Gerencia puede retirar piezas' using errcode = '42501';
  end if;
  update crm.guion_piezas set estado = 'retirada', actualizado_en = now() where id = p_id;
  insert into crm.guion_historial (pieza_id, estado_clave, version, estado, texto, actor)
  select id, estado_clave, version, 'retirada', texto, v_actor
    from crm.guion_piezas where id = p_id;
end;
$$;

revoke all on function crm.fijar_guion_pieza(text,text,text,text,text,text,text,text,text) from public, anon;
revoke all on function crm.aprobar_guion_pieza(uuid) from public, anon;
revoke all on function crm.retirar_guion_pieza(uuid)  from public, anon;
grant execute on function crm.fijar_guion_pieza(text,text,text,text,text,text,text,text,text) to authenticated;
grant execute on function crm.aprobar_guion_pieza(uuid) to authenticated;
grant execute on function crm.retirar_guion_pieza(uuid)  to authenticated;
```

---

### 3.4 `crm.guia_eventos` — telemetría + atribución de resultado

> **Injerto de `hibrido-eventos`**: no basta medir clics (`mostrada`/`copiada`), hay que medir **outcome**. Es lo único que permite responderle a Miguel *"¿sirvió?"* con evidencia y lo único que puede alimentar el gate anti-oráculo del vault (backtest contra resultados posteriores).
> **Corrección aplicada**: el bloque de `hibrido-eventos` que insertaba los eventos `emitida` **nunca dispara** (`v_t0 := clock_timestamp()` es posterior a `now() = transaction_timestamp()`, la condición es siempre falsa) — el patrón no se replica: aquí el evento lo escribe el cliente, explícitamente.

`20260720000004_crm_guia_eventos.sql`

```sql
create table crm.guia_eventos (
  id            bigint generated always as identity primary key,
  perfil_id     uuid not null references public.perfiles(id) on delete cascade,
  rol_crm       text not null,          -- congelado: el rol cambia con el tiempo
  regla         text not null,
  estado_clave  text not null,
  banda         smallint not null,
  severidad     text not null,
  sujeto_tipo   text not null
                constraint guia_sujeto_valido
                check (sujeto_tipo in ('lead','tarea','cliente','contrato','miembro','ambito')),
  sujeto_id     uuid,                   -- id INTERNO, para atribución. Nunca sale a terceros.
  accion        text not null
                constraint guia_accion_valida
                check (accion in ('mostrada','abierta','copiada','whatsapp','descartada','omitida')),
  guion_origen  text,                   -- 'bundle' | 'bd' | 'sin_pieza'
  guion_version int,
  creado_en     timestamptz not null default now()
);

comment on table crm.guia_eventos is
  'Bitacora de la guia comercial. SIN PII: ni nombre, ni telefono, ni DNI, ni el TEXTO RENDERIZADO del mensaje (solo regla + estado_clave + ids internos). El log de una funcion de gobierno no puede ser el mismo un deposito de PII.';

create index guia_eventos_perfil_idx  on crm.guia_eventos (perfil_id, creado_en desc);
create index guia_eventos_regla_idx   on crm.guia_eventos (regla, accion, creado_en desc);
create index guia_eventos_sujeto_idx  on crm.guia_eventos (sujeto_tipo, sujeto_id, creado_en desc);

alter table crm.guia_eventos enable row level security;

create policy guia_eventos_select on crm.guia_eventos
  for select to authenticated
  using ( perfil_id in (select v from private.vendedor_ids_visibles((select auth.uid())) v)
          or (select private.es_lector_global()) );
-- Inmutable: sin UPDATE ni DELETE para nadie. Mismo criterio que crm.actividades.

grant select on crm.guia_eventos to authenticated;
grant select, insert on crm.guia_eventos to service_role;

create function crm.registrar_guia_evento(
  p_regla text, p_estado_clave text, p_banda smallint, p_severidad text,
  p_sujeto_tipo text, p_sujeto_id uuid, p_accion text,
  p_guion_origen text default null, p_guion_version int default null
) returns void
language plpgsql security definer set search_path to ''
as $$
declare v_actor uuid := (select auth.uid()); v_rol text;
begin
  if v_actor is null then return; end if;            -- silencioso: es telemetría
  select e.rol_crm into v_rol from crm.equipo e
   where e.perfil_id = v_actor and e.activo = true;
  if v_rol is null then return; end if;
  insert into crm.guia_eventos
    (perfil_id, rol_crm, regla, estado_clave, banda, severidad,
     sujeto_tipo, sujeto_id, accion, guion_origen, guion_version)
  values
    (v_actor, v_rol, p_regla, p_estado_clave, p_banda, p_severidad,
     p_sujeto_tipo, p_sujeto_id, p_accion, p_guion_origen, p_guion_version);
end;
$$;
revoke all on function crm.registrar_guia_evento(text,text,smallint,text,text,uuid,text,text,int)
  from public, anon;
grant execute on function crm.registrar_guia_evento(text,text,smallint,text,text,uuid,text,text,int)
  to authenticated;

-- ── ATRIBUCIÓN DE RESULTADO (gerencia) ───────────────────────────────────────
-- Responde: de las señales mostradas, ¿cuántas terminaron con el hecho resuelto
-- dentro de la ventana? Es evidencia OBSERVACIONAL, no causal, y la UI debe
-- rotularla así: el vault prohibe la voz de oraculo hasta pasar su gate de
-- suficiencia (IC, backtest, estabilidad semanal).
create function crm.guia_atribucion_fn(p_dias int default 30)
returns table (regla text, estado_clave text, mostradas int, actuadas int,
               descartadas int, resueltas int)
language sql stable security definer set search_path to ''
as $$
  with venta as (
    select distinct on (e.regla, e.estado_clave, e.sujeto_id)
           e.regla, e.estado_clave, e.sujeto_tipo, e.sujeto_id, e.creado_en, e.perfil_id
    from crm.guia_eventos e
    where e.accion = 'mostrada'
      and e.creado_en >= now() - make_interval(days => least(greatest(p_dias,1), 366))
      and ( e.perfil_id in (select v from private.vendedor_ids_visibles((select auth.uid())) v)
            or private.es_lector_global() )
    order by e.regla, e.estado_clave, e.sujeto_id, e.creado_en asc
  ),
  actos as (
    select v.regla, v.estado_clave, v.sujeto_id,
           bool_or(e2.accion in ('copiada','whatsapp')) as actuada,
           bool_or(e2.accion in ('descartada','omitida')) as descartada
    from venta v
    left join crm.guia_eventos e2
           on e2.regla = v.regla and e2.sujeto_id = v.sujeto_id
          and e2.creado_en between v.creado_en and v.creado_en + interval '7 days'
    group by 1,2,3
  ),
  resuelto as (
    -- Hoy solo se atribuye la regla de mayor valor. Las demás se añaden cuando
    -- tengan un criterio de cierre igual de duro. NUNCA se infiere causalidad.
    select v.regla, v.estado_clave, v.sujeto_id,
           case when v.regla = 'cobranza.sin_cuenta' then exists (
                  select 1 from public.contratos c join public.perfiles p on p.id = c.cliente_id
                  where c.id = v.sujeto_id
                    and case when c.moneda = 'USD'
                             then nullif(btrim(coalesce(p.numero_cuenta_usd,'')),'') is not null
                             else nullif(btrim(coalesce(p.numero_cuenta,'')),'')     is not null end)
                else null end as ok
    from venta v
  )
  select v.regla, v.estado_clave,
         count(*)::int,
         count(*) filter (where a.actuada)::int,
         count(*) filter (where a.descartada)::int,
         count(*) filter (where r.ok)::int
  from venta v
  left join actos a on (a.regla,a.estado_clave,a.sujeto_id)=(v.regla,v.estado_clave,v.sujeto_id)
  left join resuelto r on (r.regla,r.estado_clave,r.sujeto_id)=(v.regla,v.estado_clave,v.sujeto_id)
  group by 1,2;
$$;
revoke all on function crm.guia_atribucion_fn(int) from public, anon;
grant execute on function crm.guia_atribucion_fn(int) to authenticated;
```

> **Las 4 tablas y las 7 funciones nuevas se añaden al gate RLS (hoy 232/232) ANTES del merge.** `crm.guia_eventos` es la crítica: un vendedor no puede ver la bitácora de otro.

---

## 4. Contratos TS

### 4.1 `src/lib/guia/tipos.ts`

```ts
// lib/guia/tipos.ts — Contrato del motor de guía. Puro: sin React, sin red.
import type { Actividad, Lead, Miembro, Tarea, TipoTarea } from '../tipos'
import type { ClienteBasico, ContratoRow } from '../clientes-tipos'
import type { Moneda } from '../format'

/** El sujeto es polimórfico: es lo que permite hablarle HOY a un vendedor real
 *  (12 clientes / 13 contratos) mientras crm.leads sigue en 0 y oculto. */
export type Sujeto =
  | { t: 'cliente';  id: string; cliente: ClienteBasico }
  | { t: 'contrato'; id: string; contrato: ContratoRow; cliente: ClienteBasico | null }
  | { t: 'lead';     id: string; lead: Lead }
  | { t: 'tarea';    id: string; tarea: Tarea; lead: Lead | null }
  | { t: 'miembro';  id: string; miembro: Miembro }
  | { t: 'ambito';   id: 'yo' }

export type Familia =
  | 'cobranza' | 'contratos' | 'clientes' | 'leads' | 'agenda' | 'meta' | 'equipo'

/** Banda comercial. AQUÍ y solo aquí vive "lo que genera ingreso, primero". */
export type Banda = 0 | 1 | 2 | 3
//  0 irreversible · 1 ingreso en riesgo · 2 higiene · 3 informativa

export type Severidad = 'critica' | 'media' | 'baja'   // misma escala que ItemCola

/** Acciones como DATOS, nunca closures: el motor sigue puro y testeable sin React. */
export type Accion =
  | { k: 'abrir_cliente';   clienteId: string }
  | { k: 'abrir_contrato';  contratoId: string }
  | { k: 'filtrar_tabla';   q: string }
  | { k: 'nuevo_contrato';  clienteId: string }
  | { k: 'corregir';        tipo: 'cliente' | 'contrato'; id: string }
  | { k: 'ir_a';            vista: 'clientes' | 'contratos' }
  | { k: 'whatsapp';        telefono: string }
  | { k: 'abrir_lead';      leadId: string }                                   // dormida
  | { k: 'agendar';         leadId: string; tipo: TipoTarea; venceEn: string } // dormida

/** Cita RECUPERABLE al material de Miguel (injerto de llm-servidor).
 *  Es lo que convierte una plantilla en asesoría y lo que hace auditable el
 *  curso: cuando Miguel diga "ese no es el mensaje que enseño", se ubica. */
export interface Cita {
  documento: string      // 'modulo-3-renovaciones'
  seccion: string        // 'Abrir la conversación 60 días antes'
  ancla: string          // '#p12'
  extracto: string       // el párrafo literal, para el botón "¿por qué?"
}

export interface Consejo {
  texto: string          // YA interpolado con nombre, capital y fecha reales
  fundamento: string     // por qué el material recomienda esto AQUÍ
  cita: Cita | null
  canal: 'whatsapp' | 'llamada' | 'reunion' | 'correo'
  /** Honestidad de origen, VISIBLE en la UI (injerto de llm-servidor).
   *  'bundle' = pieza compilada y testeada · 'bd' = override aprobado por gerencia. */
  origen: 'bundle' | 'bd'
  version: number
  /** Enlace wa.me PRELLENADO. El repo ya lo soporta (lib/recordatorio.ts:41). */
  enlaceWa: string | null
}

export interface Senal {
  /** Dedupe + estabilidad de render: `${regla}:${sujeto.t}:${sujeto.id}`. */
  clave: string
  regla: string
  familia: Familia
  /** 'regla|moneda|banda_monto|categoria' — la clave del recetario. */
  estadoClave: string
  sujeto: Sujeto
  banda: Banda
  severidad: Severidad
  /** Titular corto es-PE. */
  titulo: string
  /** Hecho observable — guion largo — qué toca. Lo genera el MOTOR, no el JSX. */
  motivo: string
  /** Capital en juego, en su moneda ORIGINAL. Es lo que SE MUESTRA. */
  capital: { monto: number; moneda: Moneda } | null
  /** Solo para ORDENAR. peso = equivalente PEN.
   *  INVARIANTE TESTEADA: jamás pasa por money() ni moneyK(). */
  orden: { peso: number; convertido: boolean }
  desde: number          // epoch ms — la severidad escala sobre esto
  hasta: number | null   // muerte por reloj; null = vive mientras el hecho exista
  acciones: readonly Accion[]
  consejo: Consejo | null
}

/** Snapshot de solo lectura. Lo arma useGuia(); el motor NUNCA pide datos. */
export interface AmbitoGuia {
  rol: string
  yoId: string | null
  /** 'vendedor' = mi cartera · 'equipo' = el árbol que superviso. */
  alcance: 'vendedor' | 'equipo'
  clientes: readonly ClienteBasico[]
  contratos: readonly ContratoRow[]
  salud: readonly FilaSalud[]
  leads: readonly Lead[]             // hoy []
  actividades: readonly Actividad[]  // hoy []
  tareas: readonly Tarea[]           // hoy []
  equipo: readonly Miembro[]
  /** TC USD→PEN de useTipoCambio(). null ⇒ ranking SEGREGADO (PEN antes que
   *  USD, cada uno por monto desc). JAMÁS una tasa inventada.
   *  Precedente exacto y ya testeado: sinProximaAccion (inteligencia.ts:204). */
  tcUsdPen: number | null
  reglas: ReglasResueltas
  guion: GuionResuelto
}

export interface OpcionesGuia {
  presupuesto?: number    // techo de `visibles`; el resto va a `ocultas`. Default 3
  maxPorSujeto?: number   // dedupe transversal. Default 1
}

/** `estado` distingue AL DÍA de NO SÉ. Injerto de hibrido-eventos:
 *  un falso "todo bien" es peor que un error visible. */
export interface ResultadoGuia {
  visibles: readonly Senal[]
  ocultas: readonly Senal[]
  estado: 'al_dia' | 'con_senales' | 'sin_cartera' | 'sin_calcular'
  /** Frescura de primera clase: qué fuentes cargaron y cuándo. */
  frescura: {
    saludOk: boolean
    guionOk: boolean
    reglasOk: boolean
    calculadoEn: number
  }
  diagnostico: ReadonlyArray<{ regla: string; emitidas: number; motivoCero?: string }>
}

/** Firma única. `ahora` es OBLIGATORIO — nada de Date.now() adentro
 *  (el default de colaDe/estancados es una trampa de congelamiento en render). */
export declare function senalesDe(
  ambito: AmbitoGuia, ahora: number, opts?: OpcionesGuia,
): ResultadoGuia
```

### 4.2 `estado_clave` y bandas de monto — con la corrección del panel

> `private.banda_monto()` **no existe** en producción (verificado). Como el ranking y el lookup ocurren en el navegador —donde `useTipoCambio` sí existe—, la banda se calcula en TS. **Los rangos aprobados del vault son SOLO PEN**; USD no tiene rangos aprobados, así que USD usa una banda única y explícita hasta que Miguel los apruebe.

```ts
// lib/guia/estado-clave.ts
import type { Moneda } from '../format'

/** Rangos PEN del vault (Distribución…md:221-230), colapsados a 3 bandas para
 *  el recetario. El mapeo se declara aquí y no se reinventa por regla:
 *    baja  = (0, 10k]      ← (0,1k] ∪ (1k,5k] ∪ (5k,10k]
 *    media = (10k, 50k]    ← (10k,20k] ∪ (20k,50k]
 *    alta  = > 50k         ← (50k,100k] ∪ >100k
 *  USD NO tiene rangos aprobados en el vault: banda única 'usd' hasta que
 *  Miguel los apruebe. Inventar cortes en USD sería fabricar una regla de
 *  negocio que nadie firmó. */
export type BandaMonto = 'baja' | 'media' | 'alta' | 'usd' | 'sin_monto'

export function bandaMonto(monto: number | null, moneda: Moneda): BandaMonto {
  if (monto == null || monto <= 0) return 'sin_monto'
  if (moneda === 'USD') return 'usd'
  if (monto <= 10_000) return 'baja'
  if (monto <= 50_000) return 'media'
  return 'alta'
}

/** 62% de los contratos de una cartera real tienen categoria NULL. No se
 *  inventa: 'sin_cat' es una variante legítima del recetario. */
export function estadoClave(
  regla: string, moneda: Moneda, monto: number | null, categoria: string | null,
): string {
  return `${regla}|${moneda}|${bandaMonto(monto, moneda)}|${categoria ?? 'sin_cat'}`
}

/** Cascada de fallback: el catálogo puede ser esparso y crecer sin romper nada. */
export function clavesDeBusqueda(regla: string, moneda: Moneda,
                                 monto: number | null, categoria: string | null): string[] {
  const b = bandaMonto(monto, monto == null ? moneda : moneda)
  return [
    `${regla}|${moneda}|${b}|${categoria ?? 'sin_cat'}`,
    `${regla}|${moneda}|${b}|*`,
    `${regla}|${moneda}|*|*`,
    `${regla}|*|*|*`,
  ]
}
```

### 4.3 Recetario, validador de runtime y render

```ts
// lib/guia/recetario.ts
import { CLAVES_SENSIBLES } from '../observabilidad'

export interface Pieza {
  estadoClave: string
  canal: Consejo['canal']
  /** Placeholders permitidos, lista CERRADA. Cualquier otro FALLA el test. */
  texto: string          // '{{nombre}} {{capital}} {{fecha}} {{dias}} {{contrato}}'
  fundamento: string
  cita: Cita | null
  origen: 'bundle' | 'bd'
  version: number
}
export type GuionResuelto = ReadonlyMap<string, Pieza>  // clave: `${estadoClave}:${canal}`

/** LISTA NEGRA EN RUNTIME, no solo en CI (injerto de llm-servidor).
 *  guion.test.ts solo cubre GUION_BASE; crm.guion_piezas lo SOBRESCRIBE en
 *  runtime y gerencia puede escribir cualquier cosa. La misma regex corre en
 *  la RPC (CHECK de escritura) y aquí (última defensa antes de la pantalla). */
const PROHIBIDO =
  /(garantiz|sin riesgo|libre de riesgo|asegurad|respaldad|rentabilidad fija|dep[óo]sito a plazo|\bSBS\b|\bSMV\b|\bFSD\b|fondo de seguro)/i

const PLACEHOLDER = /\{\{(\w+)\}\}/g
const PERMITIDOS = new Set(['nombre', 'capital', 'fecha', 'dias', 'contrato'])

export function piezaValida(p: Pieza): boolean {
  if (PROHIBIDO.test(`${p.texto} ${p.fundamento}`)) return false
  for (const m of p.texto.matchAll(PLACEHOLDER)) {
    if (!PERMITIDOS.has(m[1] ?? '')) return false
  }
  return true
}

/** BD (aprobada) sobrescribe bundle. Un override inválido se DESCARTA y manda
 *  la pieza del bundle: nunca se degrada a "sin consejo" por un mal override. */
export function resolverGuion(
  base: readonly Pieza[], overrides: readonly Pieza[] | undefined,
): GuionResuelto {
  const m = new Map<string, Pieza>()
  for (const p of base) if (piezaValida(p)) m.set(`${p.estadoClave}:${p.canal}`, p)
  for (const p of overrides ?? []) if (piezaValida(p)) m.set(`${p.estadoClave}:${p.canal}`, p)
  return m
}
```

```ts
// lib/guia/render.ts — el ÚNICO lugar donde nombre y capital tocan el texto.
// INVARIANTE: el texto interpolado NUNCA se persiste ni se transmite.
//   crm.guia_eventos registra regla + estado_clave + ids internos, jamás el texto.
//   (Injerto de llm-servidor, elevado a invariante testeada.)
import { money, primerNombre } from '../format'
import { fechaLima } from '../agenda-derivada'

export function renderPieza(p: Pieza, v: {
  nombre: string; capital: { monto: number; moneda: Moneda } | null
  fecha?: string; dias?: number; contrato?: string
}): string {
  // primerNombre() ya capitaliza: 'TISNADO GABRIELA' → 'Gabriela'. Los nombres
  // viven en MAYÚSCULA por trigger de BD; pegarlos crudos se lee como grito.
  return p.texto
    .replaceAll('{{nombre}}',   primerNombre(v.nombre))
    .replaceAll('{{capital}}',  v.capital ? money(v.capital.monto, v.capital.moneda) : '')
    .replaceAll('{{fecha}}',    v.fecha ? fechaLima(v.fecha) : '')
    .replaceAll('{{dias}}',     String(v.dias ?? ''))
    .replaceAll('{{contrato}}', v.contrato ?? '')
}

/** UN SOLO BOTÓN. Corrección propia del panel: los tres diseños asumían que
 *  wa.me no admite ?text=. FALSO — lib/recordatorio.ts:41 ya construye
 *  `https://wa.me/${tel}?text=${encodeURIComponent(...)}` y está testeado
 *  (recordatorio.test.ts:47). Lo que no lo prellena es UN call-site:
 *  components/app/contacto.tsx:133. Para alguien que hace esto 15 veces al día,
 *  3 pasos vs 1 tap es la diferencia entre usar la guía y no usarla. */
const soloDigitos = (t: string) => t.replace(/\D/g, '')
export function enlaceGuia(telefono: string | null, texto: string): string | null {
  const tel = soloDigitos(telefono ?? '')
  if (tel.length < 9) return null
  return `https://wa.me/${tel}?text=${encodeURIComponent(texto)}`
}
```

### 4.4 Frontera Valibot (`data/crm-api.ts`)

```ts
// numeric de PostgREST puede llegar como string — mismo criterio que ContratoRowSchema
const Num = v.pipe(v.union([v.number(), v.string()]), v.transform(aNumero))

export const FilaSaludSchema = v.object({
  contrato_id: v.pipe(v.string(), v.uuid()),
  numero_contrato: v.string(),                 // ⚠️ NO `numero`
  cliente_id: v.pipe(v.string(), v.uuid()),
  cliente_nombre: v.nullable(v.string()),
  moneda: v.picklist(['PEN', 'USD'] as const),
  categoria: v.nullable(v.picklist(['nuevo', 'renovacion', 'upgrade'] as const)),
  capital: Num,
  fecha_vencimiento: v.nullable(v.string()),
  proxima_cuota_en: v.nullable(v.string()),    // 'YYYY-MM-DD' → parseDateLocal, UTC-5
  proxima_cuota_monto: v.nullable(Num),
  tipo_cuota: v.nullable(v.string()),
  falta_cuenta: v.boolean(),
  cuotas_tarde: v.number(),
  cuotas_vencidas: v.number(),
})

export const PiezaBdSchema = v.object({
  estado_clave: v.string(),
  canal: v.picklist(['whatsapp', 'llamada', 'reunion', 'correo'] as const),
  texto: v.pipe(v.string(), v.minLength(10), v.maxLength(1200)),
  fundamento: v.string(),
  fuente_doc: v.string(), fuente_seccion: v.string(),
  fuente_ancla: v.string(), fuente_extracto: v.string(),
  version: v.number(),
})

export const ReglaBdSchema = v.object({
  clave: v.string(),
  familia: v.picklist(FAMILIAS),
  banda: v.picklist([0, 1, 2, 3] as const),
  audiencia: v.picklist(['vendedor', 'supervisor', 'ambos'] as const),
  activa: v.boolean(),
  presupuesto: v.number(),
})
```

### 4.5 Ranking — lexicográfico, con orden total

```ts
// lib/guia/orden.ts
// NO es una suma ponderada (α·sev + β·capital): eso es inexplicable a un
// vendedor e imposible de fijar en un test. Es una cascada:
//   1. banda        ← "lo que genera ingreso, primero", codificado
//   2. severidad    ← PESO_SEV de inteligencia.ts:85
//   3. orden.peso   ← capital PEN-equivalente, desc
//   4. desde        ← antigüedad/proximidad, desc
//   5. clave        ← ORDEN TOTAL. Sin esto, dos ítems empatados se
//                     intercambian entre ticks de useAhora (60 s) = parpadeo.
//
// Sin TC (tcUsdPen === null) NO se inventa tasa ni se mezcla: ranking
// SEGREGADO — dentro de cada (banda, severidad), PEN por monto desc y luego
// USD por monto desc. Precedente exacto ya en prod y testeado:
// sinProximaAccion (inteligencia.ts:204-207, inteligencia.test.ts:304).
```

---

## 5. Pipeline de la capacitación de Miguel — de documento crudo a consejo mostrado

```
[1] INGESTA                     [2] CONCILIACIÓN         [3] DESTILACIÓN
PDF/DOCX/video de Miguel   →    contra el vault      →   scripts/guion/destilar.mjs
  ↓ normalizar                    (BLOQUEANTE)             Batch API · opus-4-8
docs/capacitacion/*.md            ↓                        entrada = FichaAnonima
  frontmatter:                  marca cada pasaje:           + pasaje 'vigente'
    estado: vigente|corregido|    vigente | corregido        + barandillas del vault
            retirado              | retirado                 salida = {texto, fundamento,
    nota_conciliacion: "..."      + nota                             cita}
    anclas: p1, p2, …             (folklore purgado →      ~200 estado_clave × 1 llamada
  (NO entra al bundle:            versión corregida)
   es confidencial)                                              ↓
                                                          [4] APROBACIÓN DE MIGUEL
[6] DERIVA CONTROLADA      ←    [5] COMPILACIÓN      ←    borradores/*.md, pieza a pieza
guion.test.ts falla si:           npm run guion:build      → crm.fijar_guion_pieza()
 · una regla activa no tiene       ├ src/lib/guia/            estado='borrador'
   pieza en su cascada             │  guion-base.ts        → pantalla Gerencia
 · un texto usa placeholder        │  (bundle, 0 ms)         "Aprobar mensajes"
   fuera de la lista cerrada       └ scripts/guion/         → crm.aprobar_guion_pieza()
 · un texto matchea la lista          seed.sql                estado='aprobada'
   negra regulatoria
 · el payload saliente del
   destilador matchea
   CLAVES_SENSIBLES
```

### Detalle de cada paso

**[1] Ingesta.** El material de Miguel se normaliza a `docs/capacitacion/*.md` con anclas estables (`modulo-3-renovaciones.md#p12`). **No entra al bundle** (fuera de `src/`): `app/src` se sirve público en crm.miavance.com, y el curso es IP de la empresa. Lo que sí viaja al bundle son las **plantillas** (texto que de todos modos se envía por WhatsApp) y el `fundamento`; el **extracto literal** del curso viaja solo desde BD, bajo RLS, y se muestra únicamente al pulsar "¿por qué?".

**[2] Conciliación con el vault — BLOQUEANTE.** *(Injerto de `llm-servidor`: modelo `estado ∈ vigente|corregido|retirado` + `nota_conciliacion`.)* El vault ya ganó una verificación adversarial contra el folklore de ventas: *"80 % de las ventas tras el 5.º follow-up"* y *"44 % abandona tras 1 intento"* están **purgados**; *"5–8 toques"* es para **conseguir contacto**, no para cerrar; la cifra vigente de tiempo no vendiendo es **72/28**, no 60 %; *"mañana protegida"* son **dos picos** (10:00–11:30 y 16:00–18:00), no la mañana. Si un pasaje repite folklore purgado: `estado: corregido` + nota + se ingiere la versión corregida. Un pasaje `retirado` **el destilador se niega a usarlo**.

> **Reparto de autoridad, explícito**: el **vault** manda sobre *cuándo y con qué frecuencia* (SLA 24 h, umbrales 1/3/5 días, cadencia D0→D14, tope ~6 llamadas/8 toques, ventana L–S 07:00–20:00, ritmo mar–jue). El **curso de Miguel** aporta *qué decir*: guiones, manejo de objeciones, tono.

**[3] Destilación offline.** *(Injerto de `llm-servidor`: `FichaAnonima` como whitelist aplicada al script offline.)* El destilador recorre el catálogo cerrado de `estado_clave` y por cada uno manda **una** petición batch. **Entrada estructuralmente incapaz de llevar PII**: `{regla, familia, banda, moneda, banda_monto, categoria, dias, canal}` — enums y enteros, **sin ids, sin UUIDs** (un UUID es reidentificable si el proveedor correlaciona peticiones), sin nombres, sin montos exactos, sin texto libre del CRM. Un test de CI falla si el payload saliente matchea la regex `CLAVES_SENSIBLES` de `lib/observabilidad.ts:7`.

**[4] Aprobación de Miguel, pieza por pieza.** Nada llega a un vendedor sin `estado='aprobada'` y `aprobada_por` de gerencia. En un negocio que vende renta fija de 12–25 % anual a personas naturales en Perú, que el dueño firme cada frase que 17 vendedores enviarán a 188 inversionistas reales **es una ventaja regulatoria, no fricción**.

**[5] Compilación a dos destinos.** `guion-base.ts` (bundle: latencia 0, funciona sin red y sin BD) y `seed.sql` (BD: gerencia retoca copy sin redeploy). El **render en dos tiempos** *(injerto de `llm-servidor`)*: la franja pinta con el bundle al instante y sustituye in situ cuando `useGuion()` resuelve, con el origen (`bundle` / `bd`) visible en el diálogo.

**[6] Deriva controlada.** El test de compilación es el guardián. Y en runtime, la misma lista negra corre en `resolverGuion()` **y** como `CHECK` dentro de `crm.fijar_guion_pieza` — porque la BD sobrescribe al bundle y un test de CI no protege lo que gerencia escribe después.

### Si el material aún no llega

`GUION_BASE` admite **piezas escritas a mano**. La fase F0 se lanza con ~8 plantillas redactadas por Miguel en una tarde, y el destilador entra cuando el corpus exista. **El agente nunca depende del LLM para existir**: sin pieza, la señal se muestra igual con su `motivo` determinista y sin consejo.

---

## 6. "Mensajes según etapa" — hoy y mañana

### Hoy: la etapa es la del **cliente en su ciclo de inversión**

| Etapa real del cliente | Regla que la detecta | Qué recomienda | Vale hoy (1 vendedor real) |
|---|---|---|---|
| **Cobra y no hay dónde depositarle** | `cobranza.sin_cuenta` (banda 0) | pedir la cuenta, un paso, sin culpar | **4 casos**, uno a **3 días** |
| **Le llega su interés esta semana** | `cobranza.cobro_proximo` (banda 1) | el día del depósito es el de máxima confianza: aporte adicional o referido | **5 cuotas en 7 d**; 11 en 30 d (S/ 5.973,76 + US$ 127,50) |
| **Próximo a vencer** | `contratos.vence_pronto` (banda 1) | abrir renovación **o upgrade** 60 d antes | S/ 140.000 en dic-2026 |
| **Registrado, sin invertir** | `clientes.sin_contrato` (banda 2) | reactivación con propuesta concreta | **2 de 12** (una con cuenta lista y 30 d sin invertir) |
| **Le pagamos tarde** | `cobranza.pago_tardio` (banda 2) | adelantarse antes de que pregunte | 3 de 11 cuotas pagadas |
| **Alta reciente, ventana viva** | `contratos.ventana_5h` (banda 0) | corrige capital/tasa/fechas antes de las 5 h | 0 hoy; se enciende al registrar |
| **Concentración** | `contratos.concentracion` (banda 3) | pedir referidos a quien ya confía | **38,4 %** del capital PEN en una persona |

Las categorías del contrato (`nuevo`/`renovacion`/`upgrade`) entran en `estado_clave`, así que la renovación de S/ 170.000 de un cliente puntual **no recibe el mismo texto** que una de S/ 5.000 — que es la diferencia entre un recetario y un asesor.

### Mañana: la etapa del **lead**, sin tocar el motor

Las claves ya están reservadas en el recetario: `leads.sin_responder`, `leads.propuesta_sin_respuesta`, `leads.seguimiento`, `leads.por_repartir`, `agenda.recordatorio_cita`, `agenda.no_show`. Mapean 1:1 a los buckets que `colaDe()` **ya emite**. `reglas/leads.ts` es una **envoltura** de `colaDe`/`estancados`/`sinProximaAccion`/`colaHigiene`, no una reimplementación.

Encender la familia = `UPDATE crm.guia_reglas SET activa = true WHERE familia = 'leads'` + que `funcionesLeadsVisibles()` lo permita. **Cero cambios al motor, a la tarjeta o al diálogo.**

**Prerequisito legal, no opcional:** `no_contactar` end-to-end antes de la primera regla de leads. Corrección del panel: **`crm.leads` NO tiene GRANT por columna** — `authenticated` tiene `SELECT` sobre las 30 columnas, incluida `no_contactar`. Por tanto es **puro frontend**: añadirla a `COLUMNAS_LEAD` (`data/crm-api.ts:58`), al tipo `Lead` (`lib/tipos.ts:199`) y a los dos call-sites de `components/app/cerrar-tarea.tsx:114,128`. ~30 líneas, cero trabajo de grants. Mientras no esté cerrada, la familia `leads` emite `consejo: null`.

### El flujo en pantalla

```
Franja "Tu gestión hoy"  ·  Card + SectionHead + Badge(n)  ·  ≤3 tarjetas + "+N más"
 └─ FilaSenal: dot SEV_COLOR · Badge etiqueta · nombre · motivo · money(capital, moneda)
     └─ [Enviar por WhatsApp] ──► Dialog "Mensaje sugerido — Falta cuenta bancaria"
          <Textarea EDITABLE, prellenado e interpolado>
             Hola Carlos, el martes 21 te depositamos tu interés del contrato
             2026-01-000453. ¿Me confirmas a qué cuenta en soles te llega?
          de tu capacitación · «Cobranza» § Pedir datos sin fricción   [¿por qué?]
          origen: aprobado por gerencia · v3
          [Enviar por WhatsApp]   [Copiar]   [Omitir]
```

- **Editable**, no de solo lectura: un mensaje que no se puede tocar no se manda.
- **Un botón principal**, no dos. `wa.me?text=` funciona (corregido). "Copiar" queda como respaldo real (sin HTTPS o sin permiso de portapapeles el `Textarea` sigue siendo copiable a mano).
- **Ventana legal L–S 07:00–20:00** (Ley 29571): fuera de ella el botón propone el próximo slot válido en vez de disparar. Se reutiliza `slotHabil`/`proximoSlotSugerido` de `lib/motor-siguiente.ts`, que ya salta el domingo.
- **v1 NO registra actividad.** `crm.actividades.lead_id` es `NOT NULL` y no hay tipo `mensaje_enviado`: no se puede registrar un toque contra un cliente del portal sin migración. El botón no promete un registro que no ocurre. `crm.guia_eventos` registra que se envió — **telemetría del producto, no timeline del cliente**.
- **No es un chat.** No hay caja de entrada libre, ni turnos, ni historial conversacional. El vault ya lo había anticipado: *"si el timeline parece un chat, el vendedor esperará que escribir ENVÍE el WhatsApp"*.

### El panel del supervisor

> **Injerto de `hibrido-eventos`, sin materializar.** Lo que compra adopción no es la fila en Postgres: es que el ítem **no sea privado**. El vault ya dictaminó por qué funciona el bucket amarillo — *"el mecanismo real de la industria no es el candado, es esta lista inocultable"*.

`components/app/guia-equipo.tsx` corre **el mismo `senalesDe`** con `alcance: 'equipo'` y renderiza **los mismos strings de `motivo`**. La consistencia se garantiza porque es **la misma función pura**, no dos motores que puedan divergir. Coste: un ámbito distinto, cero infraestructura.

---

## 7. Mapa de fases

| Fase | Qué se entrega | Migración | Bloqueado por |
|---|---|---|---|
| **F0 · Motor + franja** | `lib/guia/{tipos,motor,orden,estado-clave,recetario,render}.ts` + `reglas/{contratos,clientes}.ts` + `guion-base.ts` con ~5 piezas de Miguel + `<GuiaGestion/>` en Clientes y Contratos + `mensaje-sugerido.tsx` + tests vitest. Señales vivas: `clientes.sin_contrato`, `contratos.vence_pronto`, `contratos.concentracion`, `contratos.ventana_5h`. | **ninguna** | — |
| **F1 · Cobranza** | `crm.salud_cartera_fn` + `useSaludCartera` + schema Valibot + `reglas/cobranza.ts`. Enciende las 3 señales de mayor valor (`sin_cuenta`, `cobro_proximo`, `pago_tardio`). | 1 fn | F0 |
| **F2 · Gobierno** | `crm.guia_reglas` (kill-switch), `crm.guion_piezas` + historial + 3 RPC, `crm.guia_eventos` + RPC. `useGuion()`. Origen visible. Casos nuevos en el gate RLS (232 → ~248). Advisors limpios. | 3 tablas + 6 fn | F1 |
| **F3 · Capacitación** | `docs/capacitacion/` + conciliación con el vault + `destilar.mjs` + pantalla Gerencia "Aprobar mensajes" + `guion.test.ts` (lista negra + placeholders + cobertura de reglas). Catálogo pasa de ~5 a ~200 piezas. | — | **Miguel entrega el material** |
| **F4 · Equipo y evidencia** | `guia-equipo.tsx` (mismo motor, ámbito supervisor) + `crm.guia_atribucion_fn` + panel de gerencia con la atribución **rotulada como observacional**. | 1 fn | F2 |
| **F5 · Leads** | `no_contactar` end-to-end (~30 líneas, puro frontend) → `reglas/leads.ts` como envoltura de `colaDe`/`estancados`/`sinProximaAccion`/`colaHigiene` + `reglas/agenda.ts`. Migración de la deuda D1/D3/D4/D5/D7 al motor. | — | leads cargados + aprobación de Miguel |

**Rollback en cada fase:** F0–F1 se revierten con un deploy. Desde F2, apagar una regla ruidosa o retirar un mensaje malo es **un `UPDATE` de una fila**, con efecto inmediato y sin deploy.

### Prerrequisito de Miguel (fase 0, no técnico)

1. **Estatus regulatorio de Avance Corp S.A.C., por escrito.** No hay una sola nota en el vault que mencione SBS, SMV o Fondo de Seguro de Depósitos. Hasta tener respuesta, **el guion v1 no menciona tasas ni rendimientos**: habla de fechas de cobro, cuentas faltantes, vencimientos y clientes sin invertir. Los ocho casos con datos reales de hoy no necesitan prometer rentabilidad para ser útiles.
2. El material de capacitación (desbloquea F3).
3. Retención de `crm.guia_eventos` — sugiero 12 meses con purga.
4. Ratificar "Analista" vs "Vendedor" en la copia (manda la decisión del 2026-07-16: **"analista"** al equipo, **"tu asesor"** al cliente).

---

## 8. Presupuesto de costo y latencia

### Runtime — el punto entero del diseño

| Métrica | Valor |
|---|---|
| **Costo por invocación** | **US$ 0,00** — no hay proveedor en la ruta caliente |
| **Costo mensual, 17 vendedores** | **US$ 0,00** |
| Motor `senalesDe` | **< 1 ms** — O(n) sobre ≤ 60 filas (el vendedor con más carga tiene 13 contratos) |
| Lookup del recetario | **O(1)** — `Map` en memoria |
| Red en frío (adicional) | ~120–250 ms: `salud_cartera_fn` + `guion_piezas` + `guia_reglas`, en paralelo con queries ya montadas |
| Red en caliente | **0** — `staleTime` 5 min (salud) / 30 min (guion+reglas) |
| Sin conexión / BD caída | **funciona degradado**: `GUION_BASE` y `REGLAS_BASE` van en el bundle |
| Peso añadido al bundle | ~14 KB min+gzip (motor + ~40 piezas); ~28 KB con las ~200 de F3 |
| Alucinación en runtime | **estructuralmente imposible** — todo texto salió de una pieza aprobada |

### Offline — costo real de autoría, una sola vez

Modelo: **`claude-opus-4-8`** ($5 / $25 por MTok) vía **Batch API (−50 %)**, con `cache_control` sobre el prefijo compartido (barandillas + tono + few-shot, idéntico en las ~200 llamadas).

| Escenario | Llamadas | Costo con Batch |
|---|---:|---:|
| Guion v1 (piezas de Miguel a mano) | 0 | **US$ 0** |
| Catálogo F3 completo, ~200 `estado_clave` | 200 | **≈ US$ 2,00** (≈ **US$ 1,20** con caché de prefijo) |
| Refresco tras una revisión del curso | ~20 | ≈ US$ 0,20 |

**El guion completo cuesta menos de dos dólares y se paga una vez.**

### La comparación honesta con el LLM en runtime

> **Corrección al diseño ganador.** Su §8 comparaba contra *"7.500 llamadas/mes → US$ 75–150/mes"*. Eso es un **hombre de paja**: `llm-servidor` cachea por `unique(perfil_id, dia_lima, huella)` y proyecta **374 briefings/mes ≈ US$ 18**. El costo **no** es el argumento — es despreciable en ambos casos.

El argumento real contra generar en runtime es **el propio argumento de `llm-servidor`**: si el espacio de estados son 30–60 combinaciones (200 con nuestra segmentación), entonces son 200 **textos**, y eso es un lote offline por definición. La arquitectura de pgvector + edge en la ruta caliente **no está justificada por su propia aritmética**. Lo que sí aporta el LLM —RAG sobre el corpus **con cita**— se obtiene igual generando offline, y encima con revisión humana. Lo que cuesta la ruta caliente no es dinero: son **5–12 s de latencia por consejo**, una dependencia externa que puede caerse en mitad de una llamada con un inversionista, un segundo proveedor de embeddings, pgvector instalado en la BD financiera de producción, y texto que Miguel nunca leyó.

---

## 9. Qué se decidió NO hacer, y por qué

| Descartado | Por qué |
|---|---|
| **LLM en runtime (edge `crm-guia`)** | Su propio argumento de 30–60 estados demuestra que la llamada en vivo es innecesaria. Añade 5–12 s de latencia, un proveedor externo en la ruta crítica, PII cruzando la red y texto no revisado — para producir el mismo resultado que un lote offline de US$ 2. |
| **pgvector + RAG en la ruta caliente** | `vector` está **disponible pero NO instalado** (`installed_version = null`, verificado). Instalar una extensión en la BD financiera de producción como prerrequisito, más un segundo proveedor de embeddings sin cuenta ni acuerdo de retención, para un corpus que se puede recorrer en lote. La **cita recuperable** —lo valioso— se conserva sin nada de eso. |
| **Materialización en `crm.senales` + `pg_cron`** | 6 tablas, un reconciliador, 4 crons, un watchdog, un job de atribución **y** un refactor previo de `private.vendedor_ids_visibles` (la función de seguridad más delicada del sistema, con 3 policies colgando) — para comprar consistencia y telemetría que se obtienen con el mismo motor puro sobre otro ámbito y una tabla de eventos. Añade dos fallos que el motor puro no tiene: desfase (la señal equivocada también sería pública) y falla silenciosa ("al día" mientras 4 clientes no pueden cobrar). |
| **Triggers sobre `public.contratos` / `perfiles` / `cronograma_pagos`** | Un bug ahí rompe el alta de clientes en producción, sobre la ruta de ingreso, y viola la regla vigente de separar CRM y portal. |
| **Segundo motor de reglas en SQL** | Habría que mantenerlo en lockstep con `lib/inteligencia.ts` — dos implementaciones que pueden divergir. Y el SQL propuesto por `hibrido-eventos` no compila: invoca `crm.tipo_cambio_vigente()` y `private.banda_monto()`, que **no existen** (el TC vive solo en la edge `crm-tipo-cambio`), y selecciona `c.numero` cuando la columna es `numero_contrato`. |
| **Apoyarse en `crm.metricas_vencimientos_fn`** | **Existe en prod pero NO tiene migración en el repo** (drift verificado), contra la regla explícita de `supabase/functions/LEEME.md`. Además con su default `p_dias=90` devuelve **cero** para un vendedor cuyo primer vencimiento está a 110 días — un panel vacío que parecería un bug. Los vencimientos se derivan de `useContratos()`, que ya está montada. |
| **Lectura masiva de las 14 columnas bancarias** | La RLS lo permitiría, pero enviar DNI/CCI/cuentas al navegador para calcular un booleano es una regresión de superficie. `salud_cartera_fn` devuelve el veredicto. Contexto: `public.perfiles` concede `SELECT` sobre sus 33 columnas a `authenticated` **y a `anon`**; la RLS es el único control sobre los datos bancarios de 188 clientes. |
| **Trigger `private.log_audit_crm` sobre `guion_piezas`** | Volcaría el texto completo a `public.audit_log`, que tiene grants `ALL` para `anon` y `authenticated` (salvada solo por RLS). No es PII, pero heredar ese patrón frágil por comodidad se descarta: el historial vive en `crm.guion_historial` con su propia RLS. |
| **Persistir las señales o el texto renderizado** | La caducidad derivada es gratis y es la mejor defensa contra la fatiga: cuando el cliente da su cuenta, la señal desaparece sola. Y `guia_eventos` registra regla + ids, **nunca** el texto interpolado — así un bug de log degrada a "consejo genérico", no a fuga. |
| **Snooze en v1** | En `localStorage` es un mute que el supervisor no ve — destruye la propiedad que justifica el bucket amarillo inocultable. Con tabla y RLS es correcto pero prematuro. Se cubre con escalado (`severidad = f(ahora − desde)`) + caducidad (`hasta`). |
| **Registrar actividad desde la guía** | `crm.actividades.lead_id` es `NOT NULL` y no hay tipo `mensaje_enviado`. Prometer un registro que no ocurre es exactamente la mentira que el vault prohíbe. |
| **`sin_altas_este_mes` en el panel del vendedor** | *"Llevas 19 días de julio con 0 clientes nuevos, junio cerró en 7"* es un robot regañando a un comisionista, sin acción de un paso asociada, con una herramienta que aún se le está pidiendo que adopte — el vault cita Speier & Venkatesh 2002: *un CRM percibido como control sube la rotación*. **Existe, pero con `audiencia = 'supervisor'`.** |
| **`sin_categoria` con severidad** | Es higiene de datos, no ingreso. Banda 3, al pie, sin dot de severidad, con la muestra rotulada ("5 de 13 clasificados"), nunca una torta que finja un mix que no se midió (62 % `NULL` en una cartera real). |
| **Verbos de priorización estadística** | `Priorizar`, `Pausar`, ranking predictivo y Wilson están **prohibidos por el vault** hasta pasar el gate de suficiencia (IC, backtest, estabilidad semanal). La guía recomienda sobre **proceso** —a quién le toca, qué decir, cuándo, qué falta— que es regla determinista explicable; nunca sobre **ruteo estadístico**. `guia_atribucion_fn` empieza a construir la evidencia; hasta que pase el gate, **el sistema presenta evidencia y el gerente decide**. |
| **% de renovación, mora, conversión, embudo, tendencia por origen** | `renovado_a_id` no nulo = **0** y `cerrado_en` = **0** en los 197 contratos: cualquier "% de renovación" es una división por cero disfrazada. `cronograma_pagos.estado='vencido'` = 0 en toda la base. `crm.leads` y `crm.actividades` = 0. `crm.objetivos` = 0, así que `pctMeta` no tiene denominador. Con 3 meses de historia no se proyecta tendencia — `tendenciaDe` ya devuelve `undefined` sin muestra y ese criterio se respeta. |
| **Dos botones "Copiar" + "Abrir WhatsApp"** | Los tres diseños lo asumían por una premisa **falsa**. `lib/recordatorio.ts:41` ya construye `wa.me/${tel}?text=…` con test (`recordatorio.test.ts:47`). Un botón principal; "Copiar" como respaldo. |

### Dos correcciones de copy, no de arquitectura

1. **El primer vencimiento activo es 2026-08-06** (no 2026-09-23 como dice `Ciclo de vida de contratos.md:24`, stale) y **29 contratos vencen en 2026** (no 20). Con fecha de hoy, el aviso automático de 30 días para ese contrato **ya se disparó** (~07-07): la primera señal de renovación del sistema nace **tarde**, y el copy **no debe presentarla como anticipación**. Se redacta como recuperación: *"El aviso de 30 días salió el 7 de julio. Si aún no hablaste con él, llámalo hoy."*
2. **"494 tests"** es el conteo unitario de **todo el proyecto**, no de `lib/inteligencia.ts`. La madurez del módulo es defendible; el número no se cita.

---

**Archivos nuevos:**
`/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp/app/src/lib/guia/{tipos.ts,motor.ts,orden.ts,estado-clave.ts,recetario.ts,render.ts,guion-base.ts,reglas-base.ts,reglas/{cobranza,contratos,clientes,leads,agenda}.ts}` · `.../app/src/components/app/{guia-gestion.tsx,mensaje-sugerido.tsx,guia-equipo.tsx}` · `.../app/src/data/guia-api.ts` · `.../app/src/data/guia-queries.ts` · `.../CRM-Avance-Corp/supabase/migrations/{20260720000001_crm_salud_cartera_fn.sql,20260720000002_crm_guia_reglas.sql,20260720000003_crm_guion_piezas.sql,20260720000004_crm_guia_eventos.sql}` · `.../CRM-Avance-Corp/scripts/guion/{destilar.mjs,seed.sql}` · `.../docs/capacitacion/*.md`

**Archivos que este plan NO toca:** `lib/config.ts` · `lib/router.ts` · `App.tsx` · `components/app/sidebar.tsx` · `components/app/topbar.tsx`. El agente nace del lado correcto del gate y no lo cruza nunca.