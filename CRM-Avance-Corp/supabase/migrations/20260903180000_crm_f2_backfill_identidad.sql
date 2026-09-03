-- ============================================================================
-- P-055 · MULTIEMPRESA F2 — Backfill: enganchar lo que ya existe a la identidad
-- ============================================================================
--
-- QUE, en una linea: recorre el historico (clientes Avance, cierres de
-- cooperativa, leads convertidos) y lo amarra a la identidad neutral de F1,
-- POR CLASES, sin adivinar nada. Deja un MAPA auditable de cada decision.
--
-- POR QUE. F1 creo el registro de "una sola persona" pero esta vacio. F2 lo
-- puebla para que F3 (puertas canonicas) y F5 (ficha) tengan de donde leer.
--
-- CLASES (contrato §13.2):
--   A automatica: perfil cliente con documento valido y unico -> identidad.
--   B automatica: cierre externo con documento valido y unico -> identidad.
--   C automatica: lead convertido hereda la identidad de su perfil o su cierre.
--   E revision humana: sin documento, formato invalido, colision, responsable
--     ambiguo, perfil no-cliente. NUNCA se enlaza; queda en el mapa como E.
--   (D y F no se materializan en F2: D exige leads sueltos con DNI = un unico
--    identificador vigente, que a este volumen no aportan; F es solo candidata.)
--
-- SEGURIDAD/INVARIANTES:
--   * Aditivo y REVERSIBLE (mapa -> scripts/rollback-f2-backfill.sql).
--   * IDEMPOTENTE: se puede repetir sin duplicar (el resolver es idempotente por
--     documento; los enlaces usan guardas `is null`; el mapa hace upsert).
--   * NO toca dinero: contratos, operaciones y cierres NO se modifican; Capital
--     por empresa/moneda es IDENTICO antes y despues (el postflight lo verifica).
--   * NO fusiona por datos debiles (nombre/telefono/correo): eso es clase F.
--   * Escribe crm.leads.inversionista_id con crm.op_privilegiada='on' (la unica
--     via autorizada de pasar el trigger de proteccion de F1).
--   * Las 6 fuentes economicas y el nucleo intactos.
--
-- Requiere F1 aplicada (migracion 20260903160000). Las banderas de F1 siguen
-- APAGADAS: F2 no enciende ninguna puerta (eso es F3).

begin;

set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2_backfill'));

-- ── 0. Guardas ───────────────────────────────────────────────────────────────
do $guard$
begin
  if to_regclass('crm.inversionistas') is null
     or to_regclass('crm.inversionista_identificadores') is null
     or to_regclass('crm.inversiones') is null
     or to_regprocedure('private.inversionista_resolver(text,text,boolean,text)') is null then
    raise exception 'F2: F1 no esta aplicada (faltan identidad/inversiones/resolver)';
  end if;
end
$guard$;

-- Huella de Capital ANTES de tocar nada: el backfill NO debe mover el dinero.
create temp table _f2_capital_antes on commit drop as
  select pg_catalog.md5(pg_catalog.string_agg(pg_catalog.md5(e::text), '|' order by pg_catalog.md5(e::text))) as huella,
         pg_catalog.count(*) as n
  from private.capital_episodios('-infinity'::timestamptz,'infinity'::timestamptz, true, null) e;

-- ============================================================================
-- 1. crm.backfill_multiempresa_mapa — el ACTA auditable de cada decision
-- ============================================================================
create table if not exists crm.backfill_multiempresa_mapa (
  id uuid primary key default gen_random_uuid(),
  fuente text not null check (fuente in ('perfil','cierre','lead')),
  fila_id uuid not null,             -- id del perfil / cierre / lead de origen
  inversionista_id uuid references crm.inversionistas(id),  -- null si clase E/F
  clase text not null check (clase in ('A','B','C','D','E','F')),
  regla text not null,               -- descripcion legible de la regla aplicada
  confianza text not null default 'alta' check (confianza in ('alta','media','revision')),
  revisor uuid references public.perfiles(id),
  creado_en timestamptz not null default now() check (isfinite(creado_en)),
  actualizado_en timestamptz not null default now() check (isfinite(actualizado_en)),
  -- una fila de origen aparece UNA vez en el mapa (idempotencia del backfill).
  constraint backfill_mapa_fuente_fila_uq unique (fuente, fila_id)
);
comment on table crm.backfill_multiempresa_mapa is
  'F2 multiempresa: mapa auditable del backfill. Una fila por origen (perfil/cierre/lead) con la identidad asignada, la clase (A-F), la regla y la confianza. Es la fuente de la reversa y de la revision de las clases E. Sin grants a la Data API.';

alter table crm.backfill_multiempresa_mapa enable row level security;
revoke all on crm.backfill_multiempresa_mapa from public, anon, authenticated, service_role;
create policy backfill_mapa_select_gerencia on crm.backfill_multiempresa_mapa
  for select to authenticated using (private.es_gerencia_crm_activa());
create trigger trg_audit_backfill_mapa
  after insert or update or delete on crm.backfill_multiempresa_mapa
  for each row execute function private.log_audit_crm();
create trigger trg_backfill_mapa_touch
  before update on crm.backfill_multiempresa_mapa
  for each row execute function private.set_actualizado_en_crm();
create index backfill_mapa_inv_idx   on crm.backfill_multiempresa_mapa (inversionista_id);
create index backfill_mapa_clase_idx on crm.backfill_multiempresa_mapa (clase);

-- ============================================================================
-- 2. private.backfill_multiempresa_ejecutar() — el pipeline, IDEMPOTENTE
-- ============================================================================
create or replace function private.backfill_multiempresa_ejecutar()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  r record; v_inv uuid; v_norm text; v_valido boolean;
  v_a int:=0; v_b int:=0; v_c int:=0; v_e int:=0; v_resp int:=0; v_noc int:=0;
begin
  -- La valvula: unica via autorizada para escribir identidad en leads (trigger de
  -- proteccion de F1) y en cierres (trigger de inmutabilidad). Local a la tx.
  perform pg_catalog.set_config('crm.op_privilegiada','on', true);

  -- ── Clase A: cliente Avance, documento valido y unico -> identidad + perfil ──
  for r in
    select p.id, p.tipo_documento as tipo, p.dni, p.asesor_perfil_id
    from public.perfiles p where p.rol='cliente'
  loop
    if r.dni is null or pg_catalog.btrim(r.dni)='' then
      insert into crm.backfill_multiempresa_mapa (fuente,fila_id,inversionista_id,clase,regla,confianza)
      values ('perfil', r.id, null, 'E', 'cliente sin documento', 'revision')
      on conflict (fuente,fila_id) do update set inversionista_id=null, clase='E', regla=excluded.regla, confianza='revision';
      v_e := v_e+1; continue;
    end if;
    v_norm := pg_catalog.upper(pg_catalog.regexp_replace(r.dni,'[^A-Za-z0-9]','','g'));
    v_valido := coalesce(case r.tipo when 'DNI' then v_norm ~ '^[0-9]{8}$'
      when 'CE' then v_norm ~ '^[0-9]{9,12}$'
      when 'PASAPORTE' then v_norm ~ '^[A-Z0-9]{6,12}$' else false end, false);
    if not v_valido then
      insert into crm.backfill_multiempresa_mapa (fuente,fila_id,inversionista_id,clase,regla,confianza)
      values ('perfil', r.id, null, 'E', 'documento con formato invalido para '||r.tipo, 'revision')
      on conflict (fuente,fila_id) do update set inversionista_id=null, clase='E', regla=excluded.regla, confianza='revision';
      v_e := v_e+1; continue;
    end if;
    v_inv := private.inversionista_resolver(r.tipo, r.dni, true, 'backfill-A');
    update crm.inversionistas set perfil_id = r.id
      where id = v_inv and perfil_id is null
        and not exists (select 1 from crm.inversionistas i2 where i2.perfil_id = r.id and i2.id <> v_inv);
    insert into crm.backfill_multiempresa_mapa (fuente,fila_id,inversionista_id,clase,regla,confianza)
    values ('perfil', r.id, v_inv, 'A', 'perfil cliente con documento valido y unico', 'alta')
    on conflict (fuente,fila_id) do update set inversionista_id=excluded.inversionista_id, clase='A', regla=excluded.regla, confianza='alta';
    v_a := v_a+1;
    if r.asesor_perfil_id is not null
       and exists (select 1 from crm.equipo e where e.perfil_id=r.asesor_perfil_id and e.activo)
       and not exists (select 1 from crm.inversionista_responsables ir where ir.inversionista_id=v_inv and ir.hasta is null) then
      insert into crm.inversionista_responsables (inversionista_id, responsable_id, motivo)
      values (v_inv, r.asesor_perfil_id, 'backfill: asesor del perfil cliente');
      update crm.inversionistas set responsable_relacion_id = r.asesor_perfil_id where id=v_inv and responsable_relacion_id is null;
      v_resp := v_resp+1;
    end if;
  end loop;

  -- ── Clase B: cierre coop no-anulado (la demo lo esta), doc valido -> identidad + inversion ──
  for r in
    select ce.id, ce.documento_tipo as tipo, ce.documento, ce.cooperativa, ce.vendedor_id
    from crm.cierres_externos ce where ce.anulado_en is null
  loop
    v_norm := pg_catalog.upper(pg_catalog.regexp_replace(r.documento,'[^A-Za-z0-9]','','g'));
    v_valido := case r.tipo when 'DNI' then v_norm ~ '^[0-9]{8}$'
      when 'CE' then v_norm ~ '^[0-9]{9,12}$'
      when 'PASAPORTE' then v_norm ~ '^[A-Z0-9]{6,12}$' else false end;
    if not v_valido then
      insert into crm.backfill_multiempresa_mapa (fuente,fila_id,inversionista_id,clase,regla,confianza)
      values ('cierre', r.id, null, 'E', 'documento de cierre invalido', 'revision')
      on conflict (fuente,fila_id) do update set inversionista_id=null, clase='E', regla=excluded.regla, confianza='revision';
      v_e := v_e+1; continue;
    end if;
    v_inv := private.inversionista_resolver(r.tipo, r.documento, true, 'backfill-B');
    update crm.cierres_externos set inversionista_id = v_inv where id = r.id and inversionista_id is null;
    insert into crm.inversiones (inversionista_id, empresa_id, cierre_externo_id, estado, fecha_comercial, es_primera_conversion, creado_por)
    select v_inv, e.id, ce.id, 'vigente', (ce.creado_en at time zone 'America/Lima')::date, true, ce.creado_por
    from crm.empresas e join crm.cierres_externos ce on ce.id = r.id
    where e.clave = r.cooperativa
      and not exists (select 1 from crm.inversiones inv where inv.cierre_externo_id = r.id);
    insert into crm.inversion_titulares (inversion_id, inversionista_id, rol)
    select inv.id, v_inv, 'principal' from crm.inversiones inv
    where inv.cierre_externo_id = r.id
      and not exists (select 1 from crm.inversion_titulares it where it.inversion_id=inv.id and it.rol='principal');
    insert into crm.backfill_multiempresa_mapa (fuente,fila_id,inversionista_id,clase,regla,confianza)
    values ('cierre', r.id, v_inv, 'B', 'cierre coop con documento valido; inversion externa inicial', 'alta')
    on conflict (fuente,fila_id) do update set inversionista_id=excluded.inversionista_id, clase='B', regla=excluded.regla, confianza='alta';
    v_b := v_b+1;
    if r.vendedor_id is not null
       and not exists (select 1 from crm.inversionista_responsables ir where ir.inversionista_id=v_inv and ir.hasta is null) then
      insert into crm.inversionista_responsables (inversionista_id, responsable_id, motivo)
      values (v_inv, r.vendedor_id, 'backfill: vendedor del cierre coop');
      update crm.inversionistas set responsable_relacion_id = r.vendedor_id where id=v_inv and responsable_relacion_id is null;
      v_resp := v_resp+1;
    end if;
  end loop;

  -- ── Clase C: lead convertido hereda identidad de su perfil o su cierre ──
  for r in
    select l.id as lead_id, l.no_contactar,
      coalesce((select i.id from crm.inversionistas i where i.perfil_id = l.perfil_id),
               (select ce.inversionista_id from crm.cierres_externos ce where ce.lead_id = l.id)) as inv
    from crm.leads l where l.etapa='convertido'
  loop
    if r.inv is null then
      insert into crm.backfill_multiempresa_mapa (fuente,fila_id,inversionista_id,clase,regla,confianza)
      values ('lead', r.lead_id, null, 'E', 'lead convertido sin identidad inequivoca de perfil ni cierre', 'revision')
      on conflict (fuente,fila_id) do update set inversionista_id=null, clase='E', regla=excluded.regla, confianza='revision';
      v_e := v_e+1; continue;
    end if;
    -- Un solo lead VIVO por persona (contrato §3): el primero se lleva el puntero
    -- vivo (leads.inversionista_id + bridge canonico); los demas van al bridge
    -- como historico SIN tocar leads.inversionista_id (evita la unique parcial).
    if exists (select 1 from crm.leads l2 where l2.inversionista_id = r.inv) then
      insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
      select r.inv, r.lead_id, 'historico'
      where not exists (select 1 from crm.inversionista_leads il where il.lead_id = r.lead_id);
    else
      update crm.leads set inversionista_id = r.inv where id = r.lead_id and inversionista_id is null;
      insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
      select r.inv, r.lead_id, 'canonico'
      where not exists (select 1 from crm.inversionista_leads il where il.lead_id = r.lead_id);
    end if;
    insert into crm.backfill_multiempresa_mapa (fuente,fila_id,inversionista_id,clase,regla,confianza)
    values ('lead', r.lead_id, r.inv, 'C', 'lead convertido hereda identidad de perfil/cierre', 'alta')
    on conflict (fuente,fila_id) do update set inversionista_id=excluded.inversionista_id, clase='C', regla=excluded.regla, confianza='alta';
    v_c := v_c+1;
    if r.no_contactar then
      update crm.inversionistas set no_contactar = true, no_contactar_en = coalesce(no_contactar_en, pg_catalog.now())
      where id = r.inv and no_contactar = false;
      v_noc := v_noc+1;
    end if;
  end loop;

  return jsonb_build_object('A',v_a,'B',v_b,'C',v_c,'E',v_e,'responsables',v_resp,'no_contactar',v_noc);
end
$fn$;
revoke all on function private.backfill_multiempresa_ejecutar() from public, anon, authenticated, service_role;

-- ============================================================================
-- 3. Ejecutar el backfill (idempotente; se puede repetir sin duplicar)
-- ============================================================================
do $run$
declare v jsonb;
begin
  v := private.backfill_multiempresa_ejecutar();
  raise notice 'F2 backfill ejecutado: %', v;
end
$run$;

-- ============================================================================
-- 4. Postflight (gate G2): 100% clasificado, dinero intacto, cero ambiguo
-- ============================================================================
do $post$
declare v_falta int; v_h_antes text; v_h_despues text; v_n_antes bigint; v_n_despues bigint;
begin
  -- 4.1 Cobertura 100%: cada cliente, cada cierre no-anulado y cada convertido en el mapa.
  select count(*) into v_falta from public.perfiles p
   where p.rol='cliente' and not exists (select 1 from crm.backfill_multiempresa_mapa m where m.fuente='perfil' and m.fila_id=p.id);
  if v_falta<>0 then raise exception 'POSTFLIGHT F2: % clientes sin clasificar', v_falta; end if;
  select count(*) into v_falta from crm.cierres_externos ce
   where ce.anulado_en is null and not exists (select 1 from crm.backfill_multiempresa_mapa m where m.fuente='cierre' and m.fila_id=ce.id);
  if v_falta<>0 then raise exception 'POSTFLIGHT F2: % cierres vigentes sin clasificar', v_falta; end if;
  select count(*) into v_falta from crm.leads l
   where l.etapa='convertido' and not exists (select 1 from crm.backfill_multiempresa_mapa m where m.fuente='lead' and m.fila_id=l.id);
  if v_falta<>0 then raise exception 'POSTFLIGHT F2: % leads convertidos sin clasificar', v_falta; end if;

  -- 4.2 Coherencia del mapa: A/B/C con identidad; E sin identidad.
  select count(*) into v_falta from crm.backfill_multiempresa_mapa
   where (clase in ('A','B','C','D') and inversionista_id is null) or (clase in ('E','F') and inversionista_id is not null);
  if v_falta<>0 then raise exception 'POSTFLIGHT F2: % filas con clase e identidad incoherentes', v_falta; end if;

  -- 4.3 El dinero NO se movio: la huella de Capital es identica.
  select huella, n into v_h_antes, v_n_antes from _f2_capital_antes;
  select pg_catalog.md5(pg_catalog.string_agg(pg_catalog.md5(e::text), '|' order by pg_catalog.md5(e::text))), pg_catalog.count(*)
    into v_h_despues, v_n_despues
    from private.capital_episodios('-infinity'::timestamptz,'infinity'::timestamptz, true, null) e;
  if v_h_antes is distinct from v_h_despues or v_n_antes is distinct from v_n_despues then
    raise exception 'POSTFLIGHT F2: el backfill MOVIO Capital (huella % -> %, n % -> %)', v_h_antes, v_h_despues, v_n_antes, v_n_despues;
  end if;

  -- 4.4 Cero ambiguo: ninguna persona con >1 lead vivo ni >1 canonico.
  if exists (select inversionista_id from crm.leads where inversionista_id is not null group by inversionista_id having count(*)>1) then
    raise exception 'POSTFLIGHT F2: una persona quedo con mas de un lead vivo';
  end if;
  if exists (select inversionista_id from crm.inversionista_leads where rol='canonico' group by inversionista_id having count(*)>1) then
    raise exception 'POSTFLIGHT F2: una persona quedo con mas de un lead canonico';
  end if;

  -- 4.5 Toda identidad creada por el backfill tiene su identificador vigente.
  select count(*) into v_falta from crm.inversionistas i
   where i.creado_en >= now() - interval '1 hour'  -- las de este backfill
     and not exists (select 1 from crm.inversionista_identificadores d where d.inversionista_id=i.id and d.estado='vigente');
  if v_falta<>0 then raise exception 'POSTFLIGHT F2: % identidades sin documento vigente', v_falta; end if;

  -- 4.6 Cada inversion externa creada corresponde a un cierre y su empresa (candado #5 de F1 ya lo vela).
  select count(*) into v_falta from crm.inversiones inv
   where inv.cierre_externo_id is not null
     and not exists (select 1 from crm.inversion_titulares it where it.inversion_id=inv.id and it.rol='principal');
  if v_falta<>0 then raise exception 'POSTFLIGHT F2: % inversiones externas sin titular principal', v_falta; end if;

  raise notice 'F2 OK: 100%% clasificado, Capital identico (huella %, % episodios), 0 ambiguo, identidades con documento, inversiones con titular.', v_h_despues, v_n_despues;
end
$post$;

commit;
