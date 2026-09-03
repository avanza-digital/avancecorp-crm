-- ============================================================================
-- P-055 · MULTIEMPRESA F2 — Backfill: enganchar lo que ya existe a la identidad
-- ============================================================================
--
-- QUE, en una linea: recorre el historico (clientes Avance, cierres de
-- cooperativa, leads convertidos) y lo amarra a la identidad neutral de F1,
-- POR CLASES, sin adivinar nada. Deja un MAPA auditable de cada decision.
--
-- CLASES (contrato §13.2) — SOLO lo INEQUIVOCO se enlaza; el resto va a E:
--   A: perfil cliente, documento valido y UNICO EN TODOS LOS PERFILES -> identidad.
--   B: cierre coop (no el demo), documento valido -> identidad + inversion inicial.
--   C: lead convertido que hereda una identidad INEQUIVOCA de su perfil o cierre,
--      y cuyo propio DNI NO discrepa de esa identidad.
--   E (revision humana, NO se enlaza): sin documento, formato invalido, documento
--      COMPARTIDO con otro perfil (multirrol/colision), convertido con perfil y
--      cierre que discrepan, o convertido cuyo DNI discrepa de la identidad.
--   (D/F del contrato no se materializan en F2.)
--
-- Excepciones REALES que esto respeta (censo F0 / cola F0.5, 2026-08-31):
--   * 2 documentos de cliente que tambien son de otro rol -> E (no se fusiona).
--   * 2 perfiles de prueba (sin doc / doc invalido) -> E (fuera del backfill).
--   * Katherine: convertida con DNI que discrepa de su perfil -> E (no autoelegir).
--   * Cierre demo Qorilazo S/100.000 (anulado, motivo DEMO) -> EXCLUIDO por id.
--
-- INVARIANTES: aditivo; IDEMPOTENTE (migracion re-aplicable y funcion re-ejecutable
-- sin efecto); REVERSIBLE con procedencia; NO mueve Capital (postflight compara la
-- huella antes/despues); un solo lead VIVO por persona; escribe los enlaces
-- protegidos solo con crm.op_privilegiada='on' (la valvula sancionada, que la
-- funcion enciende y RESTAURA). Banderas de F1 siguen APAGADAS (no enciende puertas).
--
-- Requiere F1 (migracion 20260903160000). Reversa: scripts/rollback-f2-backfill.sql.

begin;

set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2_backfill'));

-- ── 0. Guardas ───────────────────────────────────────────────────────────────
do $guard$
begin
  if to_regclass('crm.inversionistas') is null
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
  from private.capital_episodios('-infinity'::timestamptz,'infinity'::timestamptz, true, '{}'::uuid[]) e;

-- ============================================================================
-- 1. crm.backfill_multiempresa_mapa — el ACTA auditable (DDL idempotente)
-- ============================================================================
create table if not exists crm.backfill_multiempresa_mapa (
  id uuid primary key default gen_random_uuid(),
  fuente text not null check (fuente in ('perfil','cierre','lead')),
  fila_id uuid not null,
  inversionista_id uuid references crm.inversionistas(id),
  clase text not null check (clase in ('A','B','C','D','E','F')),
  regla text not null,
  confianza text not null default 'alta' check (confianza in ('alta','media','revision')),
  revisor uuid references public.perfiles(id),
  creado_en timestamptz not null default now() check (isfinite(creado_en)),
  actualizado_en timestamptz not null default now() check (isfinite(actualizado_en)),
  constraint backfill_mapa_fuente_fila_uq unique (fuente, fila_id)
);
comment on table crm.backfill_multiempresa_mapa is
  'F2 multiempresa: mapa auditable del backfill. Una fila por origen (perfil/cierre/lead) con la identidad asignada, la clase (A-F), la regla y la confianza. Fuente de la reversa y de la revision de las clases E. Sin grants a la Data API.';

alter table crm.backfill_multiempresa_mapa enable row level security;
revoke all on crm.backfill_multiempresa_mapa from public, anon, authenticated, service_role;
drop policy if exists backfill_mapa_select_gerencia on crm.backfill_multiempresa_mapa;
create policy backfill_mapa_select_gerencia on crm.backfill_multiempresa_mapa
  for select to authenticated using (private.es_gerencia_crm_activa());
drop trigger if exists trg_audit_backfill_mapa on crm.backfill_multiempresa_mapa;
create trigger trg_audit_backfill_mapa
  after insert or update or delete on crm.backfill_multiempresa_mapa
  for each row execute function private.log_audit_crm();
drop trigger if exists trg_backfill_mapa_touch on crm.backfill_multiempresa_mapa;
create trigger trg_backfill_mapa_touch
  before update on crm.backfill_multiempresa_mapa
  for each row execute function private.set_actualizado_en_crm();
create index if not exists backfill_mapa_inv_idx   on crm.backfill_multiempresa_mapa (inversionista_id);
create index if not exists backfill_mapa_clase_idx on crm.backfill_multiempresa_mapa (clase);

-- ============================================================================
-- 2. Helper de mapeo IDEMPOTENTE + el pipeline
-- ============================================================================
-- El upsert NO re-escribe (ni dispara touch/auditor) cuando la decision es
-- identica: asi la 2a pasada del backfill es realmente inocua.
create or replace function private.f2_mapear(
  p_fuente text, p_fila uuid, p_inv uuid, p_clase text, p_regla text, p_confianza text
) returns void
language sql
security definer
set search_path = ''
as $m$
  insert into crm.backfill_multiempresa_mapa (fuente, fila_id, inversionista_id, clase, regla, confianza)
  values (p_fuente, p_fila, p_inv, p_clase, p_regla, p_confianza)
  on conflict (fuente, fila_id) do update
    set inversionista_id = excluded.inversionista_id, clase = excluded.clase,
        regla = excluded.regla, confianza = excluded.confianza
    where crm.backfill_multiempresa_mapa.inversionista_id is distinct from excluded.inversionista_id
       or crm.backfill_multiempresa_mapa.clase       is distinct from excluded.clase
       or crm.backfill_multiempresa_mapa.regla       is distinct from excluded.regla
       or crm.backfill_multiempresa_mapa.confianza   is distinct from excluded.confianza;
$m$;
revoke all on function private.f2_mapear(text,uuid,uuid,text,text,text) from public, anon, authenticated, service_role;

create or replace function private.backfill_multiempresa_ejecutar()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  r record; v_inv uuid; v_valido boolean;
  v_old_priv text := pg_catalog.current_setting('crm.op_privilegiada', true);
  v_demo_cierre constant uuid := 'a112aead-184a-4979-9041-943978fadae4';
  v_a int:=0; v_b int:=0; v_c int:=0; v_e int:=0; v_resp int:=0; v_noc int:=0;
begin
  perform pg_catalog.set_config('crm.op_privilegiada','on', true);

  -- ── Clase A / E: perfiles cliente ──
  for r in
    select p.id, p.tipo_documento as tipo, p.asesor_perfil_id,
           pg_catalog.upper(pg_catalog.regexp_replace(pg_catalog.coalesce(p.dni,''),'[^A-Za-z0-9]','','g')) as dnorm
    from public.perfiles p where p.rol='cliente'
    order by p.id
  loop
    if r.dnorm = '' then
      perform private.f2_mapear('perfil', r.id, null, 'E', 'cliente sin documento', 'revision');
      v_e := v_e+1; continue;
    end if;
    v_valido := pg_catalog.coalesce(case r.tipo
      when 'DNI' then r.dnorm ~ '^[0-9]{8}$'
      when 'CE' then r.dnorm ~ '^[0-9]{9,12}$'
      when 'PASAPORTE' then r.dnorm ~ '^[A-Z0-9]{6,12}$' else false end, false);
    if not v_valido then
      perform private.f2_mapear('perfil', r.id, null, 'E', 'documento con formato invalido para '||r.tipo, 'revision');
      v_e := v_e+1; continue;
    end if;
    if exists (
      select 1 from public.perfiles p2
      where p2.id <> r.id
        and pg_catalog.upper(pg_catalog.regexp_replace(pg_catalog.coalesce(p2.dni,''),'[^A-Za-z0-9]','','g')) = r.dnorm
    ) then
      perform private.f2_mapear('perfil', r.id, null, 'E', 'documento compartido con otro perfil (multirrol/colision)', 'revision');
      v_e := v_e+1; continue;
    end if;
    v_inv := private.inversionista_resolver(r.tipo, r.dnorm, true, 'backfill-A');
    update crm.inversionistas set perfil_id = r.id
      where id = v_inv and perfil_id is null
        and not exists (select 1 from crm.inversionistas i2 where i2.perfil_id = r.id and i2.id <> v_inv);
    perform private.f2_mapear('perfil', r.id, v_inv, 'A', 'perfil cliente con documento valido y unico', 'alta');
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

  -- ── Clase B / E: cierres coop (EXCLUYE el demo por id) ──
  for r in
    select ce.id, ce.documento_tipo as tipo, ce.cooperativa, ce.vendedor_id, ce.creado_por, ce.creado_en,
           pg_catalog.upper(pg_catalog.regexp_replace(ce.documento,'[^A-Za-z0-9]','','g')) as dnorm
    from crm.cierres_externos ce where ce.id <> v_demo_cierre
    order by ce.creado_en, ce.id
  loop
    v_valido := pg_catalog.coalesce(case r.tipo
      when 'DNI' then r.dnorm ~ '^[0-9]{8}$'
      when 'CE' then r.dnorm ~ '^[0-9]{9,12}$'
      when 'PASAPORTE' then r.dnorm ~ '^[A-Z0-9]{6,12}$' else false end, false);
    if not v_valido then
      perform private.f2_mapear('cierre', r.id, null, 'E', 'documento de cierre invalido', 'revision');
      v_e := v_e+1; continue;
    end if;
    v_inv := private.inversionista_resolver(r.tipo, r.dnorm, true, 'backfill-B');
    update crm.cierres_externos set inversionista_id = v_inv where id = r.id and inversionista_id is null;
    insert into crm.inversiones (inversionista_id, empresa_id, cierre_externo_id, estado, fecha_comercial, es_primera_conversion, creado_por)
    select v_inv, e.id, r.id, 'vigente',
           pg_catalog.least((r.creado_en at time zone 'America/Lima')::date, (pg_catalog.now() at time zone 'America/Lima')::date),
           true, r.creado_por
    from crm.empresas e
    where e.clave = r.cooperativa
      and not exists (select 1 from crm.inversiones inv where inv.cierre_externo_id = r.id);
    insert into crm.inversion_titulares (inversion_id, inversionista_id, rol)
    select inv.id, v_inv, 'principal' from crm.inversiones inv
    where inv.cierre_externo_id = r.id
      and not exists (select 1 from crm.inversion_titulares it where it.inversion_id=inv.id and it.rol='principal');
    perform private.f2_mapear('cierre', r.id, v_inv, 'B', 'cierre coop con documento valido; inversion externa inicial', 'alta');
    v_b := v_b+1;
    if r.vendedor_id is not null
       and not exists (select 1 from crm.inversionista_responsables ir where ir.inversionista_id=v_inv and ir.hasta is null) then
      insert into crm.inversionista_responsables (inversionista_id, responsable_id, motivo)
      values (v_inv, r.vendedor_id, 'backfill: vendedor del cierre coop');
      update crm.inversionistas set responsable_relacion_id = r.vendedor_id where id=v_inv and responsable_relacion_id is null;
      v_resp := v_resp+1;
    end if;
  end loop;

  -- ── Clase C / E: leads convertidos ──
  for r in
    select l.id as lead_id, l.no_contactar,
           pg_catalog.upper(pg_catalog.regexp_replace(pg_catalog.coalesce(l.dni,''),'[^A-Za-z0-9]','','g')) as ldni,
           (select i.id from crm.inversionistas i where i.perfil_id = l.perfil_id and i.estado <> 'fusionado' limit 1) as inv_perfil,
           (select ce.inversionista_id from crm.cierres_externos ce where ce.lead_id = l.id) as inv_cierre
    from crm.leads l where l.etapa='convertido'
    order by l.creado_en, l.id
  loop
    if r.inv_perfil is not null and r.inv_cierre is not null and r.inv_perfil <> r.inv_cierre then
      perform private.f2_mapear('lead', r.lead_id, null, 'E', 'convertido con perfil y cierre en identidades distintas', 'revision');
      v_e := v_e+1; continue;
    end if;
    v_inv := pg_catalog.coalesce(r.inv_perfil, r.inv_cierre);
    if v_inv is null then
      perform private.f2_mapear('lead', r.lead_id, null, 'E', 'lead convertido sin identidad inequivoca de perfil ni cierre', 'revision');
      v_e := v_e+1; continue;
    end if;
    if r.ldni <> '' and not exists (
      select 1 from crm.inversionista_identificadores d
      where d.inversionista_id = v_inv and d.documento_normalizado = r.ldni and d.estado='vigente'
    ) then
      perform private.f2_mapear('lead', r.lead_id, null, 'E', 'discrepancia documental del lead convertido', 'revision');
      v_e := v_e+1; continue;
    end if;
    if exists (select 1 from crm.leads l2 where l2.inversionista_id = v_inv) then
      insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
      select v_inv, r.lead_id, 'historico'
      where not exists (select 1 from crm.inversionista_leads il where il.lead_id = r.lead_id);
    else
      update crm.leads set inversionista_id = v_inv where id = r.lead_id and inversionista_id is null;
      insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
      select v_inv, r.lead_id, 'canonico'
      where not exists (select 1 from crm.inversionista_leads il where il.lead_id = r.lead_id);
    end if;
    perform private.f2_mapear('lead', r.lead_id, v_inv, 'C', 'lead convertido hereda identidad de perfil/cierre', 'alta');
    v_c := v_c+1;
    if r.no_contactar then
      update crm.inversionistas set no_contactar = true, no_contactar_en = pg_catalog.coalesce(no_contactar_en, pg_catalog.now())
      where id = v_inv and no_contactar = false;
      v_noc := v_noc+1;
    end if;
  end loop;

  perform pg_catalog.set_config('crm.op_privilegiada', pg_catalog.coalesce(v_old_priv, 'off'), true);
  return jsonb_build_object('A',v_a,'B',v_b,'C',v_c,'E',v_e,'responsables',v_resp,'no_contactar',v_noc);
end
$fn$;
revoke all on function private.backfill_multiempresa_ejecutar() from public, anon, authenticated, service_role;

-- ============================================================================
-- 3. Ejecutar el backfill (idempotente)
-- ============================================================================
do $run$
declare v jsonb;
begin
  v := private.backfill_multiempresa_ejecutar();
  raise notice 'F2 backfill ejecutado: %', v;
end
$run$;

-- ============================================================================
-- 4. Postflight (gate G2)
-- ============================================================================
do $post$
declare v_falta int; v_h_antes text; v_h_despues text; v_n_antes bigint; v_n_despues bigint;
begin
  -- 4.1 Cobertura 100%.
  select count(*) into v_falta from public.perfiles p
   where p.rol='cliente' and not exists (select 1 from crm.backfill_multiempresa_mapa m where m.fuente='perfil' and m.fila_id=p.id);
  if v_falta<>0 then raise exception 'POSTFLIGHT F2: % clientes sin clasificar', v_falta; end if;
  select count(*) into v_falta from crm.cierres_externos ce
   where ce.id <> 'a112aead-184a-4979-9041-943978fadae4'
     and not exists (select 1 from crm.backfill_multiempresa_mapa m where m.fuente='cierre' and m.fila_id=ce.id);
  if v_falta<>0 then raise exception 'POSTFLIGHT F2: % cierres (no demo) sin clasificar', v_falta; end if;
  select count(*) into v_falta from crm.leads l
   where l.etapa='convertido' and not exists (select 1 from crm.backfill_multiempresa_mapa m where m.fuente='lead' and m.fila_id=l.id);
  if v_falta<>0 then raise exception 'POSTFLIGHT F2: % leads convertidos sin clasificar', v_falta; end if;

  -- 4.2 Coherencia clase<->identidad.
  select count(*) into v_falta from crm.backfill_multiempresa_mapa
   where (clase in ('A','B','C','D') and inversionista_id is null) or (clase in ('E','F') and inversionista_id is not null);
  if v_falta<>0 then raise exception 'POSTFLIGHT F2: % filas con clase e identidad incoherentes', v_falta; end if;

  -- 4.3 Clase A REAL: el perfil quedo enlazado a la identidad del mapa.
  select count(*) into v_falta from crm.backfill_multiempresa_mapa m
   where m.fuente='perfil' and m.clase='A'
     and not exists (select 1 from crm.inversionistas i where i.id=m.inversionista_id and i.perfil_id=m.fila_id);
  if v_falta<>0 then raise exception 'POSTFLIGHT F2: % clase A sin el perfil realmente enlazado', v_falta; end if;

  -- 4.4 Clase B REAL: cierre enlazado + inversion con titular principal coherente.
  select count(*) into v_falta from crm.backfill_multiempresa_mapa m
   where m.fuente='cierre' and m.clase='B'
     and not exists (select 1 from crm.cierres_externos ce where ce.id=m.fila_id and ce.inversionista_id=m.inversionista_id);
  if v_falta<>0 then raise exception 'POSTFLIGHT F2: % clase B sin el cierre enlazado', v_falta; end if;
  select count(*) into v_falta from crm.inversiones inv where inv.cierre_externo_id is not null
     and not exists (select 1 from crm.inversion_titulares it where it.inversion_id=inv.id and it.rol='principal' and it.inversionista_id=inv.inversionista_id);
  if v_falta<>0 then raise exception 'POSTFLIGHT F2: % inversiones externas sin titular principal coherente', v_falta; end if;

  -- 4.5 Ningun documento vigente en DOS identidades.
  select count(*) into v_falta from (
    select tipo_documento, documento_normalizado from crm.inversionista_identificadores
    where estado='vigente' group by 1,2 having count(distinct inversionista_id) > 1
  ) x;
  if v_falta<>0 then raise exception 'POSTFLIGHT F2: % documentos vigentes en mas de una identidad', v_falta; end if;

  -- 4.6 El dinero NO se movio.
  select huella, n into v_h_antes, v_n_antes from _f2_capital_antes;
  select pg_catalog.md5(pg_catalog.string_agg(pg_catalog.md5(e::text), '|' order by pg_catalog.md5(e::text))), pg_catalog.count(*)
    into v_h_despues, v_n_despues
    from private.capital_episodios('-infinity'::timestamptz,'infinity'::timestamptz, true, '{}'::uuid[]) e;
  if v_h_antes is distinct from v_h_despues or v_n_antes is distinct from v_n_despues then
    raise exception 'POSTFLIGHT F2: el backfill MOVIO Capital (huella % -> %, n % -> %)', v_h_antes, v_h_despues, v_n_antes, v_n_despues;
  end if;

  -- 4.7 Cero ambiguo.
  if exists (select inversionista_id from crm.leads where inversionista_id is not null group by inversionista_id having count(*)>1) then
    raise exception 'POSTFLIGHT F2: una persona quedo con mas de un lead vivo';
  end if;
  if exists (select inversionista_id from crm.inversionista_leads where rol='canonico' group by inversionista_id having count(*)>1) then
    raise exception 'POSTFLIGHT F2: una persona quedo con mas de un lead canonico';
  end if;

  -- 4.8 Toda identidad tiene documento vigente.
  select count(*) into v_falta from crm.inversionistas i
   where not exists (select 1 from crm.inversionista_identificadores d where d.inversionista_id=i.id and d.estado='vigente');
  if v_falta<>0 then raise exception 'POSTFLIGHT F2: % identidades sin documento vigente', v_falta; end if;

  raise notice 'F2 OK: 100%% clasificado, Capital identico (huella %, % episodios), enlaces A/B reales, unicidad documental, 0 ambiguo.', v_h_despues, v_n_despues;
end
$post$;

commit;
