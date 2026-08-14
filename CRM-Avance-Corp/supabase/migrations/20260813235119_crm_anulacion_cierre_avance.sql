-- ---------------------------------------------------------------------------
-- Anulacion de cierres de AVANCE — el merito se corrige, el dinero real no
-- ---------------------------------------------------------------------------
-- Regla de negocio (Miguel, 2026-08-13): «si gerencia anula un cierre tiene que
-- afectar en la conversion si o si, porque gerencia hara eso cuando haya errores
-- de gestion o malas practicas». Y la aclaracion que fija el alcance: lo que baja
-- «no significa dinero real, solo baja para el vendedor».
--
-- QUE ARREGLA. Hasta hoy no existia NINGUNA forma de que un cierre de Avance
-- dejara de contarle a un vendedor. La practica era borrar al cliente, y eso
-- arregla solo la mitad: el capital sale de `public.contratos` (y se va con el
-- contrato) pero la conversion sale del LEDGER, donde el episodio quedo sellado
-- como 'convertido' y es inmutable por diseno. Resultado: el vendedor perdia el
-- dinero y CONSERVABA el cierre, con su porcentaje inflado para siempre. Es el
-- mismo defecto que se cerro en cooperativas el 2026-08-12.
--
-- QUE NO TOCA. Ni una fila de `public`. El contrato, el cliente y la caja siguen
-- igual. Esto solo cambia a quien se le acredita el merito.
--
-- LA PREGUNTA, ESCRITA UNA VEZ. `private.cierre_anulado(uuid)` responde por los
-- DOS canales (cooperativa y Avance). `private.cierre_externo_anulado` se
-- conserva como DELEGADO de una linea porque
-- `private.conversion_mensual_por_vendedor` (11.761 caracteres) la llama por ese
-- nombre: renombrarla obligaria a reemplazar ese cuerpo entero, que es
-- exactamente la deuda que la ultima revision senalo. Asi la CONVERSION queda
-- arreglada SIN tocar el nucleo — su unica llamada viva es esa.
--
-- LA CUOTA si obliga a reemplazar `crm.cumplimiento_metas_fn`: el capital de
-- Avance se atribuye dentro de su cuerpo y no pasa por ningun helper. Se parte
-- del cuerpo post-B (md5(prosrc) == produccion == 0210e0daa1ee83896ec30d2948bb490f)
-- y se le anaden DOS CTE (`anulados`, `neutralizados`), se parte
-- `contratos_confirmados` en `atribuidos` + neutralizacion, y `contratos_base`
-- arrastra dos columnas mas. El resto queda intacto.
--
-- ⚠️ LA ANULACION SE APLICA DESPUES DE ATRIBUIR, no filtrando contratos antes.
-- El contrato sigue entrando en `contratos_base`; lo que se pone a NULL es su
-- VENDEDOR en `contratos_confirmados`, y solo si ese vendedor es la persona a la
-- que se acredito el cierre anulado. Dos razones, las dos medidas:
--   · filtrar el contrato dentro del lateral `enlaces` le hacia perder su
--     «vendedor explicito» y caia al AUTOR por el `else meta_autor.vendedor_id`:
--     anular REGALABA el cierre en vez de quitarlo;
--   · excluir el contrato entero por CLIENTE castigaba a terceros: si ese mismo
--     cliente renovaba con otro vendedor, anular el cierre viejo le borraba a ese
--     otro su venta legitima, en un mes ya cerrado.
-- Neutralizar el vendedor conserva las dos garantias a la vez, porque `reales`
-- ya descarta las filas con `vendedor_id is null`.
--
-- VUELTA ATRAS: `supabase/scripts/rollback-anulacion-avance.sql`.
-- ---------------------------------------------------------------------------

begin;

set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 0. Preflight — anclas md5
-- ---------------------------------------------------------------------------
-- Se reemplaza `crm.cumplimiento_metas_fn` y se redefine
-- `private.cierre_externo_anulado`; ademas se DEPENDE de que
-- `private.conversion_mensual_por_vendedor` siga llamando a esa segunda por su
-- nombre (si dejara de hacerlo, la conversion no se enteraria de las
-- anulaciones de Avance y este fichero mentiria en silencio).
--
-- `pg_get_functiondef` FORMATEA segun la version mayor de Postgres: si el
-- cluster cambia de mayor, estos preflights abortaran diciendo «cambio» cuando
-- lo que cambio es el formateador. Entonces hay que regenerar anclas, no
-- «arreglar» funciones.
do $preflight$
begin
  if md5(pg_get_functiondef('crm.cumplimiento_metas_fn(date)'::regprocedure))
     <> '41936789782ccfac6585d4e9ce4c49c5' then
    raise exception 'crm.cumplimiento_metas_fn no es el cuerpo post-B que este fichero copio (2026-08-13). Regenerar antes de aplicar.';
  end if;

  if md5(pg_get_functiondef('private.cierre_externo_anulado(uuid)'::regprocedure))
     <> '5f9dfd3d17e11364b2d6bb14a58e758f' then
    raise exception 'private.cierre_externo_anulado cambio despues de la copia (2026-08-13): este fichero la redefine.';
  end if;

  if md5(pg_get_functiondef('private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)'::regprocedure))
     <> '65d3438a9b236071ebadbeebcb5117cd' then
    raise exception 'private.conversion_mensual_por_vendedor cambio: hay que comprobar que sigue llamando a private.cierre_externo_anulado, que es lo unico que hace llegar la anulacion a la conversion.';
  end if;

  -- Redefinir un nombre le cambia el significado a TODOS sus consumidores. Las
  -- anclas de arriba prueban que los cuerpos del repo son los conocidos, pero no
  -- que la BASE no tenga un consumidor nuevo que el repo no ve. Esto si lo
  -- comprueba: se espera EXACTAMENTE uno (el nucleo de conversion).
  --
  -- ⚠️ `strpos` y NO `like`: en LIKE el guion bajo es COMODIN de un caracter, asi
  -- que '%cierre_externo_anulado%' tambien casaba con la frase en castellano
  -- «cierre externo anulado» que `private.trg_cierres_externos_inmutables` lleva
  -- en su mensaje de error. Contaba 2 consumidores donde hay 1 y abortaba una
  -- migracion correcta (2026-08-14). Un guard que dice que no por una razon
  -- falsa entrena a saltarselo, que es peor que no tenerlo.
  if (select count(*)
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where strpos(p.prosrc, 'cierre_externo_anulado') > 0
         and not (n.nspname = 'private' and p.proname = 'cierre_externo_anulado')) <> 1 then
    raise exception 'El delegado private.cierre_externo_anulado tiene consumidores inesperados en esta base: revisar antes de cambiarle el significado.';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Donde se guarda la anulacion de un cierre de Avance
-- ---------------------------------------------------------------------------
-- Tabla propia y no una columna en `crm.cierres_externos`: esa tabla es la FOTO
-- de un cierre en cooperativa (monto, documento, numero de operacion). Un cierre
-- de Avance no tiene esa foto — vive en `public.contratos` — y meterlo ahi
-- obligaria a inventar columnas vacias.
--
-- ⚠️ Lleva `id` propio aunque `lead_id` ya sea unico: `private.log_audit_crm`
-- resuelve `fila_id` con `coalesce(id, perfil_id)`, asi que sin `id` cada
-- anulacion quedaria en `audit_log` SIN fila identificable. Es el defecto (2)
-- que la segunda mirada encontro en cooperativas; no se repite.
create table crm.cierres_avance_anulados (
  id          uuid primary key default gen_random_uuid(),
  /** Un lead solo se anula una vez: la anulacion es de una sola direccion. */
  lead_id     uuid not null unique references crm.leads(id) on delete restrict,
  /**
   * FOTO de a quien se le habia acreditado el cierre, sellada al anular.
   * Sin ella la neutralizacion se RECALCULABA en cada consulta, y para el legado
   * sin episodio en el ledger eso depende de `crm.leads.vendedor_id`, que
   * gerencia puede cambiar: reasignar un lead ya anulado devolvia sus contratos
   * al primero y podia borrarle los suyos al segundo. Una anulacion es un hecho
   * historico; se fotografia, igual que la de cooperativas fotografia el cierre.
   */
  acreditado_a uuid references public.perfiles(id) on delete restrict,
  motivo      text not null,
  anulado_por uuid not null references public.perfiles(id) on delete restrict,
  anulado_en  timestamptz not null default now(),
  -- `is not null` explicito a proposito: `btrim(null) <> ''` da NULL y un CHECK
  -- solo rechaza en FALSE, asi que sin esto entraria una anulacion SIN MOTIVO.
  -- Misma trampa trivaluada que ya mordio en la anulacion de cooperativas.
  constraint cierres_avance_anulados_motivo_check
    check (motivo is not null and btrim(motivo) <> '' and length(btrim(motivo)) <= 300)
);

comment on table crm.cierres_avance_anulados is
  'Cierres de Avance que gerencia anulo por error de gestion o mala practica. NO mueve dinero real: el contrato y el cliente siguen en public intactos. Lo unico que cambia es que ese cierre deja de acreditarle al vendedor en su cuota y en su conversion. Deny-by-default absoluto: RLS ON, cero policies, cero grants; se escribe SOLO via crm.anular_cierre_avance.';
comment on column crm.cierres_avance_anulados.lead_id is
  'El lead cuyo cierre deja de contar. UNIQUE: una anulacion por lead, sin des-anular.';
comment on column crm.cierres_avance_anulados.motivo is
  'Obligatorio: esto le quita merito a una persona y esa persona merece una razon escrita, no un registro mudo.';

alter table crm.cierres_avance_anulados enable row level security;
revoke all privileges on table crm.cierres_avance_anulados
  from public, anon, authenticated, service_role;

create index idx_cierres_avance_anulados_por on crm.cierres_avance_anulados (anulado_por);
create index idx_cierres_avance_anulados_en on crm.cierres_avance_anulados (anulado_en);

create trigger trg_audit_cierres_avance_anulados
after insert or delete or update on crm.cierres_avance_anulados
for each row execute function private.log_audit_crm();

-- Append-only: una anulacion no se edita ni se borra. Si se pudiera borrar, un
-- cierre anulado volveria a contar y nadie lo veria.
create or replace function private.trg_cierres_avance_anulados_append_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  raise exception using
    errcode = 'P0409',
    message = 'Una anulacion de cierre no se edita ni se borra',
    hint    = 'Es de una sola direccion por diseno: si se pudiera deshacer, el cierre anulado volveria a acreditar sin rastro.';
end;
$function$;

create trigger trg_cierres_avance_anulados_00_append_only
before update or delete on crm.cierres_avance_anulados
for each row execute function private.trg_cierres_avance_anulados_append_only();

-- ---------------------------------------------------------------------------
-- 2. «¿Este cierre fue anulado?» — UNA sola definicion, los DOS canales
-- ---------------------------------------------------------------------------
-- INVOKER a proposito (no DEFINER), igual que su predecesora: quienes la llaman
-- ya son DEFINER y ven las tablas; llamada por su cuenta desde la Data API muere
-- en el permiso de la tabla, que es lo correcto.
create or replace function private.cierre_anulado(p_lead_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from crm.cierres_externos ce
    where ce.lead_id = p_lead_id
      and ce.anulado_en is not null
  ) or exists (
    select 1
    from crm.cierres_avance_anulados ca
    where ca.lead_id = p_lead_id
  )
$$;

comment on function private.cierre_anulado(uuid) is
  'TRUE si el cierre de ese lead fue anulado por gerencia, en CUALQUIERA de los dos canales: cooperativa (crm.cierres_externos.anulado_en) o Avance (crm.cierres_avance_anulados). Es la definicion UNICA de «anulado»; escrita dos veces, las dos divergen — ya paso.';

revoke all on function private.cierre_anulado(uuid)
  from public, anon, authenticated, service_role;

-- El nombre viejo se conserva como DELEGADO de una linea porque
-- `private.conversion_mensual_por_vendedor` la llama asi. Renombrarla obligaria
-- a reemplazar ese cuerpo de 11.761 caracteres solo para cambiar una palabra.
-- Con esto la conversion aprende las anulaciones de Avance sin tocar el nucleo.
create or replace function private.cierre_externo_anulado(p_lead_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select private.cierre_anulado(p_lead_id)
$$;

comment on function private.cierre_externo_anulado(uuid) is
  'DELEGADO. La definicion real vive en private.cierre_anulado, que responde por los dos canales. El nombre se conserva porque private.conversion_mensual_por_vendedor la invoca asi; renombrarla exigiria reemplazar ese cuerpo entero. Cuando ese nucleo se toque por otra razon, cambiar la llamada y borrar este delegado.';

revoke all on function private.cierre_externo_anulado(uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2bis. A QUIEN se le acredito un cierre — escrito UNA vez
-- ---------------------------------------------------------------------------
-- ⚠️ EL LEDGER MANDA, y `crm.leads.vendedor_id` es solo el respaldo. El orden
-- importa y no es cosmetico: la CONVERSION descuenta al `analista_id` del
-- ledger, que es INMUTABLE. `vendedor_id` no lo es — la policy `leads_update`
-- deja a gerencia reasignar un lead aunque este convertido. Si la cuota mirara
-- primero esa columna, bastaria una reasignacion para que las dos mitades
-- castigaran a personas DISTINTAS: la conversion bajaria a quien cerro y la
-- cuota, o no bajaria a nadie, o —peor— se la quitaria al nuevo si ese cliente
-- le habia comprado algo. Con el ledger delante, las dos castigan a la misma
-- persona POR CONSTRUCCION y no por coincidencia.
--
-- El ledger da una respuesta unica: `lead_asignaciones_una_conversion_por_lead_idx`
-- garantiza un solo episodio convertido por lead.
--
-- El respaldo por `vendedor_id` existe para el LEGADO: leads marcados como
-- convertidos sin episodio en el ledger (sembrados antes de que existiera).
create or replace function private.vendedor_acreditado_del_cierre(p_lead_id uuid)
returns uuid
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (select la.analista_id
       from crm.lead_asignaciones la
      where la.lead_id = p_lead_id
        and la.resultado = 'convertido'
      order by coalesce(la.resultado_en, la.finalizado_en) desc
      limit 1),
    (select l.vendedor_id from crm.leads l where l.id = p_lead_id)
  )
$$;

comment on function private.vendedor_acreditado_del_cierre(uuid) is
  'A quien se le acredito el cierre de ese lead. El LEDGER manda (inmutable, y es la misma fuente que descuenta la conversion); crm.leads.vendedor_id es solo respaldo para el legado sin episodio, porque esa columna es mutable y una reasignacion haria que cuota y conversion castigaran a personas distintas.';

revoke all on function private.vendedor_acreditado_del_cierre(uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2ter. Que contratos deja de acreditar una anulacion — escrito UNA vez
-- ---------------------------------------------------------------------------
-- Lo consultan DOS sitios: la cuota (para neutralizar) y la RPC (para decirle a
-- gerencia si de verdad va a bajar dinero). Escrito dos veces, divergirian — y
-- la primera version ya mintio: `afecta_cuota` miraba `contrato_id`, columna que
-- nadie rellena, asi que decia «no baja» exactamente cuando bajaba.
--
-- Devuelve los contratos que ese lead acreditaba Y que le pertenecen a la misma
-- persona a la que se le acredito el cierre: no se le puede quitar el merito a
-- quien no lo tiene.
create or replace function private.contratos_afectados_por_anulacion(p_lead_id uuid)
returns setof uuid
language sql
stable
set search_path = ''
as $$
  select c.id
  from crm.leads l
  cross join lateral (
    -- La FOTO manda. El calculo vivo solo sirve de respaldo: para cierres en
    -- cooperativa (que no pasan por esta tabla) y para responder ANTES de anular.
    select coalesce(
      (select ca.acreditado_a from crm.cierres_avance_anulados ca where ca.lead_id = l.id),
      private.vendedor_acreditado_del_cierre(l.id)
    ) as acreditado_a
  ) q
  join public.contratos c
    on (
      -- (a) enlace directo, cuando alguien lo rellena (legado o manual)
      c.id = l.contrato_id
      -- (b) el enlace del flujo REAL: el lead apunta al CLIENTE.
      or (l.perfil_id is not null
          and l.perfil_id = c.cliente_id
          and l.convertido_en is not null
          -- SUELO: un contrato ANTERIOR a la conversion no lo produjo este
          -- cierre. `crm.convertir_lead` admite un cliente que YA existia, asi
          -- que su cartera previa es de otra historia comercial y no se toca.
          and c.creado_en >= l.convertido_en
          -- TECHO: y deja de reclamar en cuanto ese mismo cliente vuelve a
          -- cerrarse. Sin esto un cierre anulado se quedaba con TODO el futuro
          -- del cliente para siempre — incluida la venta legitima que ese mismo
          -- vendedor le hiciera un ano despues.
          and not exists (
            select 1
            from crm.leads l_post
            where l_post.perfil_id = l.perfil_id
              and l_post.id <> l.id
              and l_post.convertido_en is not null
              -- Orden TOTAL, no parcial: `now()` es constante dentro de una
              -- transaccion, asi que dos conversiones del mismo cliente pueden
              -- empatar al microsegundo. Con `>` a secas ninguna cerraria el
              -- techo de la otra y AMBAS reclamarian los mismos contratos.
              and (l_post.convertido_en, l_post.id) > (l.convertido_en, l.id)
              and l_post.convertido_en <= c.creado_en
          ))
    )
   -- Y solo se le quita a quien lo tiene: el contrato debe estar acreditado a la
   -- misma persona a la que se le acredito el cierre anulado.
   and c.creado_por = q.acreditado_a
   -- Lo que la cuota NO mira, esto tampoco puede prometerlo: sin estos dos
   -- filtros, un contrato en otra moneda o de categoria no contable entraba en
   -- `contratos_afectados` y ponia `afecta_cuota` en true sin que bajara un sol.
   and c.categoria in ('nuevo','renovacion','upgrade')
   and c.moneda in ('PEN','USD')
   -- Y la MISMA regla de ambiguedad que aplica la cuota: un contrato enlazado a
   -- leads de vendedores DISTINTOS ya queda sin atribuir alli, asi que anular no
   -- movera un sol. Sin esto, `afecta_cuota` decia true y no bajaba nada.
   and not exists (
     select 1
     from crm.leads le
     where le.contrato_id = c.id
       and le.vendedor_id is not null
     having count(distinct le.vendedor_id) > 1
   )
  where l.id = p_lead_id
$$;

comment on function private.contratos_afectados_por_anulacion(uuid) is
  'Contratos que dejarian de acreditar si se anula el cierre de ese lead: los que ese lead trajo (por enlace directo o por CLIENTE, que es el unico que el flujo real crea) Y cuyo autor es la misma persona a la que se acredito el cierre. La cuota neutraliza con esta misma regla; escrita dos veces, divergen.';

revoke all on function private.contratos_afectados_por_anulacion(uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. La accion: gerencia anula un cierre de Avance
-- ---------------------------------------------------------------------------
create or replace function crm.anular_cierre_avance(
  p_lead_id uuid,
  p_motivo text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_rol    text := private.rol_crm((select auth.uid()));
  v_lead   crm.leads%rowtype;
  v_motivo text := btrim(p_motivo);
  v_contratos uuid[];
begin
  if v_uid is null or v_rol is distinct from 'gerencia' then
    raise exception 'Solo gerencia anula cierres'
      using errcode = '42501';
  end if;

  -- El motivo es obligatorio a proposito: esto le quita merito a una persona y
  -- esa persona merece una razon escrita, no un registro de auditoria mudo.
  if v_motivo is null or v_motivo = '' then
    raise exception 'Escribe el motivo de la anulacion'
      using errcode = '22023';
  end if;
  if length(v_motivo) > 300 then
    raise exception 'El motivo admite como maximo 300 caracteres'
      using errcode = '22023';
  end if;

  -- Orden del lock: primero el LEAD, igual que `crm.convertir_lead_externo`.
  -- (`crm.anular_cierre_externo` NO bloquea el lead: bloquea la fila del cierre.
  -- Replicar el orden de convertir_lead_externo es lo correcto porque esa RPC
  -- toma el lead ANTES de insertar el cierre, asi que el `exists` de abajo no
  -- puede perderse un cierre en cooperativa que este naciendo en paralelo.)
  select * into v_lead
  from crm.leads
  where id = p_lead_id
  for update;
  if not found then
    raise exception 'Lead no encontrado';
  end if;

  -- Un cierre en cooperativa se anula con su propia RPC, que ademas guarda la
  -- foto de lo anulado (monto, deposito). Mandarlo por aqui perderia ese rastro.
  if exists (select 1 from crm.cierres_externos ce where ce.lead_id = p_lead_id) then
    raise exception 'Ese lead cerro en cooperativa: usa crm.anular_cierre_externo'
      using errcode = '22023';
  end if;

  -- Tiene que HABER un cierre que anular, y se pregunta por la ETAPA del lead,
  -- no por el ledger. Dos razones:
  --   · es lo que gerencia VE cuando decide anular;
  --   · la anulacion tambien quita CUOTA, y la cuota va por contrato, no por
  --     episodio: un lead con contrato pero sin episodio de cierre (legado)
  --     esta acreditando dinero y tiene que poder corregirse.
  -- El ledger sigue siendo la verdad de la CONVERSION; simplemente no es la
  -- precondicion para poder anular.
  if v_lead.etapa is distinct from 'convertido' then
    raise exception 'Ese lead no tiene ningun cierre que anular'
      using errcode = '22023';
  end if;

  -- Sin sello de conversion la correlacion por CLIENTE queda muerta y la
  -- anulacion bajaria la conversion sin tocar un sol, en silencio. La RPC normal
  -- siempre lo escribe; esto solo alcanza a filas sembradas a mano en etapa
  -- terminal, y ahi es mejor un error claro que una anulacion a medias.
  if v_lead.convertido_en is null then
    raise exception 'Ese lead esta convertido pero sin fecha de conversion: no se puede saber que contratos trajo'
      using errcode = '22023';
  end if;

  if exists (select 1 from crm.cierres_avance_anulados ca where ca.lead_id = p_lead_id) then
    raise exception using
      errcode = 'P0409',
      message = 'Ese cierre ya estaba anulado';
  end if;

  insert into crm.cierres_avance_anulados (lead_id, motivo, anulado_por, acreditado_a)
  values (p_lead_id, v_motivo, v_uid,
          private.vendedor_acreditado_del_cierre(p_lead_id));

  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    p_lead_id,
    'nota',
    'Gerencia anulo el cierre',
    jsonb_build_object(
      'accion', 'anulacion_cierre_avance',
      'motivo', v_motivo,
      'anulado', jsonb_build_object(
        'vendedor_id', v_lead.vendedor_id,
        'contrato_id', v_lead.contrato_id)
    ),
    v_uid
  );

  -- `afecta_cuota` se calcula con el MISMO predicado que usa la cuota, no
  -- adivinando por `contrato_id` (que nadie rellena, asi que decia «no baja»
  -- justo cuando bajaba). Y se devuelven los contratos afectados: la primera
  -- anulacion real sera la primera prueba real de esta cadena, y conviene que
  -- gerencia pueda VER lo que se movio en vez de dar un salto de fe.
  select coalesce(array_agg(x), '{}'::uuid[]) into v_contratos
  from private.contratos_afectados_por_anulacion(p_lead_id) x;

  return jsonb_build_object(
    'ok', true,
    'lead_id', p_lead_id,
    'contratos_afectados', to_jsonb(v_contratos),
    'afecta_cuota', array_length(v_contratos, 1) is not null);
end;
$$;

comment on function crm.anular_cierre_avance(uuid, text) is
  'Anula un cierre de Avance (error de gestion o mala practica), SOLO gerencia y con motivo obligatorio. El cierre deja de acreditarle al vendedor en la CUOTA y en la CONVERSION a la vez. NO mueve dinero real: el contrato y el cliente siguen intactos en public. El lead NO se reabre (un convertido es terminal por diseno) y el episodio del ledger no se toca (es inmutable). De una sola direccion: no se des-anula. Deja actividad tipo nota con el motivo.';

revoke all on function crm.anular_cierre_avance(uuid, text)
  from public, anon, service_role;
grant execute on function crm.anular_cierre_avance(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. La cuota deja de pagar un cierre anulado
-- ---------------------------------------------------------------------------
-- Cuerpo copiado BYTE A BYTE del post-B con un unico predicado anadido en
-- `contratos_base`. Ver la advertencia de la cabecera sobre por que excluye el
-- contrato entero y no el enlace del lead.
create or replace function crm.cumplimiento_metas_fn(p_periodo date)
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_periodo_id uuid;
  v_revision integer := 0;
  v_publicada_en timestamptz;
  v_ini timestamptz;
  v_fin timestamptz;
  v_payload jsonb;
  v_factor numeric;
begin
  if v_uid is null
    or (private.rol_crm(v_uid) is null and not private.es_lector_global()) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  if p_periodo is null or p_periodo<>date_trunc('month',p_periodo)::date then
    raise exception 'El periodo debe ser el primer dia del mes' using errcode='22023';
  end if;
  v_ini:=p_periodo::timestamp at time zone 'America/Lima';
  v_fin:=(p_periodo+interval '1 month')::timestamp at time zone 'America/Lima';

  select mp.id,mp.revision,mp.publicada_en
    into v_periodo_id,v_revision,v_publicada_en
  from crm.meta_periodos mp where mp.periodo=p_periodo
  order by mp.revision desc limit 1;
  v_revision:=coalesce(v_revision,0);
  v_factor:=private.peso_referido_conversion(p_periodo);

  with anulados as materialized (
    -- Los cierres anulados y, sobre todo, A QUIEN se le habia acreditado cada
    -- uno. Conjunto diminuto por definicion, asi que conduce el `exists` de
    -- abajo en vez de recorrer leads por cada contrato.
    --
    -- `acreditado_a` cae al ANALISTA DEL LEDGER cuando el lead ya no declara
    -- vendedor. Es deliberado: `crm.leads.vendedor_id` es MUTABLE (gerencia
    -- puede devolver un lead a la cola global) y usarlo solo dejaria la
    -- anulacion inerte justo cuando mas falta hace. El ledger es inmutable y es
    -- ademas la MISMA fuente de la que sale el numerador de la conversion, asi
    -- que las dos mitades castigan a la misma persona por construccion.
    -- Conducida por las tablas de ANULACION, no por `crm.leads`: preguntar
    -- `cierre_anulado` fila a fila era un recorrido de toda la tabla de leads en
    -- CADA carga de la pantalla de Metas. El conjunto de anulaciones es diminuto
    -- por definicion y es el que debe conducir.
    select
      l.id,
      coalesce(
        (select ca.acreditado_a from crm.cierres_avance_anulados ca where ca.lead_id = l.id),
        private.vendedor_acreditado_del_cierre(l.id)
      ) as acreditado_a
    from crm.leads l
    where l.id in (
      select ca.lead_id from crm.cierres_avance_anulados ca
      union all
      select ce.lead_id from crm.cierres_externos ce where ce.anulado_en is not null
    )
  ), contratos_base as materialized (
    -- public.contratos es la confirmación canónica. El lateral resume todos los
    -- enlaces explícitos sin duplicar el contrato y detecta los legacy ambiguos
    -- que apuntan a vendedores distintos: esos quedan sin atribuir.
    select
      c.id,
      c.categoria,
      c.moneda,
      c.capital,
      c.creado_por,
      coalesce(enlaces.tiene_vendedor_explicito,false)
        as tiene_vendedor_explicito,
      coalesce(enlaces.vendedores_distintos,0) as vendedores_distintos,
      enlaces.vendedor_unico
    from public.contratos c
    left join lateral (
      select
        count(*) filter(where lead.vendedor_id is not null)>0
          as tiene_vendedor_explicito,
        count(distinct lead.vendedor_id)
          filter(where lead.vendedor_id is not null)::integer
          as vendedores_distintos,
        case
          when count(distinct lead.vendedor_id)
            filter(where lead.vendedor_id is not null)=1
          then min(lead.vendedor_id::text)
            filter(where lead.vendedor_id is not null)::uuid
        end as vendedor_unico
      from crm.leads lead
      where lead.contrato_id=c.id
    ) enlaces on true
    where c.creado_en>=v_ini and c.creado_en<v_fin
      and c.categoria in ('nuevo','renovacion','upgrade')
      and c.moneda in ('PEN','USD')
  ), atribuidos as materialized (
    -- La atribución explícita es autoritativa: si existe pero no pertenece al
    -- snapshot del mes, no cae silenciosamente al autor. El autor inmutable se
    -- usa solo cuando el contrato no tiene vendedor explícito. metas_vendedor
    -- impide que supervisores u otros actores se apropien de la producción.
    select
      base.id,
      case
        when base.vendedores_distintos>1 then null
        when base.tiene_vendedor_explicito then meta_lead.vendedor_id
        else meta_autor.vendedor_id
      end as vendedor_id,
      base.categoria,
      base.moneda,
      base.capital
    from contratos_base base
    left join crm.metas_vendedor meta_lead
      on meta_lead.meta_periodo_id=v_periodo_id
     and meta_lead.vendedor_id=base.vendedor_unico
    left join crm.metas_vendedor meta_autor
      on meta_autor.meta_periodo_id=v_periodo_id
     and meta_autor.vendedor_id=base.creado_por
  ), neutralizados as materialized (
    -- Los pares (contrato, vendedor) que dejan de acreditar. La REGLA vive en
    -- `private.contratos_afectados_por_anulacion` y NO se reescribe aqui: la
    -- misma funcion la usa la RPC para decir `afecta_cuota`, y escrita dos veces
    -- las dos divergen — es la leccion que ya costo dos rondas esta semana.
    select ca as contrato_id, an.acreditado_a as vendedor_id
    from anulados an
    cross join lateral private.contratos_afectados_por_anulacion(an.id) ca
  ), contratos_confirmados as materialized (
    -- 2026-08-13 · SOLO SE LE PUEDE QUITAR EL MERITO A QUIEN LO TIENE.
    --
    -- La anulacion se aplica DESPUES de atribuir, y solo cuando el vendedor
    -- atribuido ES la persona a la que se le habia acreditado el cierre
    -- anulado. Las dos claves no son la misma: la exclusion se decide por
    -- CLIENTE (el unico enlace que el flujo real crea) pero el merito se paga
    -- por AUTOR del contrato. Comparar solo por cliente castigaba a quien no
    -- habia hecho nada: si ese cliente RENUEVA meses despues con otro vendedor,
    -- anular el cierre viejo le borraba a ese otro su venta legitima, en un mes
    -- ya cerrado y sin dejar rastro. Con flujos normales, sin nada raro.
    --
    -- Neutralizar aqui (y no excluir el contrato en `contratos_base`) conserva
    -- ademas la garantia original: `reales` filtra `vendedor_id is not null`,
    -- asi que el contrato desaparece en vez de CAER AL AUTOR — que era el
    -- «regalo» que se midio y se descarto al disenar esto.
    select
      a.id,
      case
        when a.vendedor_id is not null and exists (
          select 1 from neutralizados n
          where n.contrato_id = a.id
            and n.vendedor_id = a.vendedor_id
        ) then null
        else a.vendedor_id
      end as vendedor_id,
      a.categoria,
      a.moneda,
      a.capital
    from atribuidos a
  ), externos_confirmados as materialized (
    -- Cierres en cooperativas (Qorilazo/Prodelco): suman a la cuota del mes
    -- como categoría 'nuevo', en SU moneda (PEN/USD jamás se suman), atribuidos
    -- al vendedor_id FOTO del cierre y validados contra el snapshot de metas
    -- del mes — el MISMO contrato que un contrato Avance: fuera del snapshot ⇒
    -- sin atribución, nunca cae a otro actor (el JOIN hace ambas cosas).
    -- Ventana por creado_en: la fecha del cierre es automática y no se
    -- retro-data, así que el mes del cierre es el mes real.
    select
      mv.vendedor_id,
      'nuevo'::text as categoria,
      ce.moneda,
      ce.monto as capital
    from crm.cierres_externos ce
    join crm.metas_vendedor mv
      on mv.meta_periodo_id=v_periodo_id
     and mv.vendedor_id=ce.vendedor_id
    where ce.creado_en>=v_ini and ce.creado_en<v_fin
      -- Un cierre anulado por gerencia (fraude o error) deja de pagar. La fila
      -- sigue ahi porque es el ancla de legalidad del lead convertido, pero no
      -- es dinero. Su gemelo en la conversion vive en
      -- private.conversion_mensual_por_vendedor.
      and ce.anulado_en is null
  ), reales as (
    select vendedor_id,categoria,moneda,
      count(*)::integer as contratos_real,
      coalesce(sum(capital),0) as capital_real
    from (
      select vendedor_id,categoria,moneda,capital
      from contratos_confirmados
      where vendedor_id is not null
      union all
      select vendedor_id,categoria,moneda,capital
      from externos_confirmados
    ) confirmados
    group by vendedor_id,categoria,moneda
  ), conversiones as (
    -- MIGRACION B: la conversion de las METAS deja de tener formula propia y
    -- CONSUME la misma funcion que pinta la pantalla. Antes esta CTE calculaba
    -- convertidos/RESUELTOS sin ponderar, asi que el mismo asesor tenia dos
    -- porcentajes distintos a 300 px de distancia: el titular ponderado y la
    -- barra de su propia meta. Reimplementar una regla de negocio dos veces es
    -- la deuda; esto la borra.
    --
    -- El filtro de cierres ANULADOS ya no se escribe aqui: viaja dentro de
    -- private.conversion_mensual_por_vendedor, que es ahora la unica definicion.
    --
    -- p_global => true A PROPOSITO, y la razon NO es la que parece. Recortar
    -- aqui ademas de en `visibles` daria EL MISMO conjunto de filas (medido:
    -- p_global=true/p_visibles={} y p_global=false/p_visibles={A} devuelven
    -- filas identicas para A), asi que no se hace por no perder a nadie.
    --
    -- Se hace porque para el LECTOR GLOBAL `private.vendedor_ids_visibles`
    -- devuelve VACIO (su rol_crm es NULL y la funcion retorna sin filas): un
    -- p_visibles construido con ella le dejaria todos los numeros en blanco.
    -- `crm.conversion_mensual_fn` resuelve lo mismo con su propio v_global.
    --
    -- Es seguro porque este nucleo no tiene ni un agregado transversal: todas
    -- sus CTE agrupan por analista_id y devuelve como mucho UNA fila por
    -- analista, asi que el valor de un vendedor no depende de quien mas este en
    -- el conjunto. El total de empresa se calcula en `conversion_mensual_fn`,
    -- no aqui — por eso ALLI el recorte tiene que ir antes y aqui no. Quien
    -- manda es la CTE `visibles` (metas_vendedor ∩ vendedor_ids_visibles), que
    -- es la tabla conductora del join.
    --
    -- COSTE, anotado a proposito: al plegarse el predicado de ambito a `true`,
    -- cada llamada recorre el ledger del mes de TODA la empresa, tambien la de
    -- un vendedor suelto. Hoy es irrelevante (la base tiene 1-2 filas) pero
    -- renuncia a la indexabilidad que peleo la migracion A: revisar cuando
    -- entre la base fria (C2 del plan de escalabilidad).
    select cm.analista_id as vendedor_id,
      (cm.cierres_no_referidos+cm.cierres_referidos)::integer as convertidos,
      cm.divisor::integer as resueltos,
      cm.numerador,
      cm.cierres_no_referidos,
      cm.cierres_referidos,
      cm.conversion_pct as conversion_real
    from private.conversion_mensual_por_vendedor(
      v_ini,v_fin,true,'{}'::uuid[],v_factor) cm
  ), visibles as (
    select mv.*,p.nombre_completo,s.nombre_completo as supervisor_nombre
    from crm.metas_vendedor mv
    join public.perfiles p on p.id=mv.vendedor_id
    join public.perfiles s on s.id=mv.supervisor_id
    where mv.meta_periodo_id=v_periodo_id
      and (private.es_lector_global()
        or mv.vendedor_id in (select private.vendedor_ids_visibles(v_uid)))
  )
  select jsonb_build_object(
    'version',1,'periodo',p_periodo,'revision',v_revision,
    'publicada_en',v_publicada_en,
    'fuentes_reales',jsonb_build_object(
      'capital_y_contratos','contratos_confirmados',
      'conversion','leads_recibidos_ponderado'
    ),
    'ponderacion_referido',v_factor,
    'vendedores',coalesce((select jsonb_agg(jsonb_build_object(
      'vendedor_id',mv.vendedor_id,'nombre',mv.nombre_completo,
      'supervisor_id',mv.supervisor_id,'supervisor_nombre',mv.supervisor_nombre,
      'conversion_objetivo',mv.conversion_objetivo,
      'conversion_real',cv.conversion_real,
      'convertidos',coalesce(cv.convertidos,0),'resueltos',coalesce(cv.resueltos,0),
      'numerador',coalesce(cv.numerador,0),
      'cierres_no_referidos',coalesce(cv.cierres_no_referidos,0),
      'cierres_referidos',coalesce(cv.cierres_referidos,0),
      'detalles',(select jsonb_agg(jsonb_build_object(
        'categoria',d.categoria,'moneda',d.moneda,
        'capital_objetivo',d.capital_objetivo,
        'capital_real',coalesce(r.capital_real,0),
        'capital_cumplimiento_pct',case when d.capital_objetivo>0
          then round(100.0*coalesce(r.capital_real,0)/d.capital_objetivo,2) end,
        'contratos_objetivo',d.contratos_objetivo,
        'contratos_real',coalesce(r.contratos_real,0),
        'contratos_cumplimiento_pct',case when d.contratos_objetivo>0
          then round(100.0*coalesce(r.contratos_real,0)/d.contratos_objetivo,2) end
      ) order by array_position(array['nuevo','renovacion','upgrade'],d.categoria),d.moneda)
      from crm.metas_vendedor_detalle d
      left join reales r on r.vendedor_id=mv.vendedor_id
        and r.categoria=d.categoria and r.moneda=d.moneda
      where d.meta_vendedor_id=mv.id)
    ) order by mv.supervisor_nombre,mv.nombre_completo) from visibles mv
    left join conversiones cv on cv.vendedor_id=mv.vendedor_id),'[]'::jsonb)
  ) into v_payload;
  return v_payload;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5. Postflight — estructural, SIN depender de datos de negocio
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_def text := pg_get_functiondef('crm.cumplimiento_metas_fn(date)'::regprocedure);
begin
  -- Se ancla la CADENA COMPLETA, no un literal suelto: una CTE que existe pero
  -- que nadie referencia ni siquiera se evalua, asi que buscar solo el nombre
  -- dejaria pasar un cuerpo donde la neutralizacion esta muerta. Es el mismo
  -- defecto vacuo que ya hubo que corregir dos veces en esta misma familia.
  if position('cross join lateral private.contratos_afectados_por_anulacion' in v_def) = 0 then
    raise exception 'postflight: la cuota no consulta que contratos deja de acreditar una anulacion';
  end if;
  if position('from neutralizados n' in v_def) = 0 then
    raise exception 'postflight: la neutralizacion existe pero NADIE la referencia (CTE muerta)';
  end if;
  -- La conversion se entera por el DELEGADO: si dejara de delegar, las
  -- anulaciones de Avance no llegarian al numerador y nadie lo notaria.
  -- Se ancla la DELEGACION, no la respuesta: preguntar si devuelve algo pasaba
  -- igual con el cuerpo VIEJO (que tambien devuelve false), o sea que el guard
  -- pasaba sobre el cuerpo que decia detectar — el mismo defecto que ya se
  -- corrigio en la migracion B.
  if position('private.cierre_anulado(' in
       pg_get_functiondef('private.cierre_externo_anulado(uuid)'::regprocedure)) = 0 then
    raise exception 'postflight: el nombre viejo ya no delega en la pregunta unica';
  end if;
  if position('from crm.cierres_avance_anulados' in
       pg_get_functiondef('private.cierre_anulado(uuid)'::regprocedure)) = 0 then
    raise exception 'postflight: la pregunta unica no mira el canal Avance';
  end if;
end;
$postflight$;

commit;
