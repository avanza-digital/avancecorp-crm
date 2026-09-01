-- P-055 F7 · OLA 2b — DEMOLER EL TABLERO DE ALTAS POR ANALISTA.
--
-- Cierre parcial de la cohorte de la Ola 1 (F7.1, cerrada el 31/08, registro
-- 191). ⛔ NO ANTES DEL 2026-09-14 (su `drop_no_antes_de`).
--
-- 🔴 POR QUE SOLO UNA DE LAS TRES — hallazgo del ensayo del 01/09:
--    `metricas_distribucion_leads_fn` y `metricas_distribucion_leads_v2_fn`
--    pertenecen al rol `crm_metricas_bridge`, y por el canal de publicacion
--    (`supabase db query`) NO se puede asumir ese rol: ni `alter function ...
--    owner to` ni `set role` funcionan (42501 «permission denied to set role»).
--    Consecuencia: si se demolieran, la marcha atras las recrearia con dueño
--    `postgres` y el vigilante F7 las veria REABIERTAS respecto de su ACL
--    declarada `{crm_metricas_bridge=X/crm_metricas_bridge}`.
--    ⇒ **No se derriba lo que no se sabe reconstruir.** Las dos se quedan
--    cerradas y en observacion; su demolicion queda como DEUDA DECLARADA hasta
--    tener una via con permisos para restaurar el dueño (panel de Supabase o
--    conexion directa con superusuario).
--
-- 🔴 `metricas_altas_analista_fn` NO tiene archivo en el repo: su partida de
--    nacimiento vive en el registro remoto (version 20260716203331). El
--    material de marcha atras es la CAPTURA VIVA del 01/09, en
--    `scripts/rollback-f7-ola2b-tableros.sql`.
--
-- Publicacion (Miguel, con `!`): migracion → registrar-f7-ola2b-version.sql →
-- gates → advisors.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

do $ola2b_pre$
declare
  v_firma constant text := 'crm.metricas_altas_analista_fn(integer)';
  v_huella constant text := 'df8a99e0dfc4e1d94794073787aa84d7';
  v_h text; v_n int; v_hoy date;
begin
  v_hoy := (now() at time zone 'America/Lima')::date;
  select f.drop_no_antes_de::date into v_hoy
  from private.f7_piezas_en_observacion f where f.firma = v_firma;
  if v_hoy is null or v_hoy > (now() at time zone 'America/Lima')::date then
    raise exception 'OLA 2b preflight: % sigue en su ventana (demolible desde %)', v_firma, v_hoy;
  end if;

  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = v_firma and estado = 'observacion' and length(ok_miguel) >= 20;
  if v_n <> 1 then
    raise exception 'OLA 2b preflight: % no esta en observacion con su OK', v_firma;
  end if;

  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'OLA 2b preflight: % alerta(s) del vigia sin resolver — stop-the-line', v_n;
  end if;

  select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_firma::regprocedure;
  if v_h is distinct from v_huella then
    raise exception 'OLA 2b preflight: % cambio de cuerpo desde la captura (huella %)', v_firma, v_h;
  end if;

  select count(*) into v_n from pg_proc p, aclexplode(p.proacl) a
   where p.oid = v_firma::regprocedure
     and a.grantee <> 'postgres'::regrole and a.privilege_type = 'EXECUTE';
  if v_n > 0 then
    raise exception 'OLA 2b preflight: % permiso(s) EXECUTE reaparecieron', v_n;
  end if;

  select count(*) into v_n from pg_proc p
   where p.oid <> v_firma::regprocedure
     and p.pronamespace in ('crm'::regnamespace,'public'::regnamespace,'private'::regnamespace)
     and strpos(lower(p.prosrc), 'metricas_altas_analista_fn') > 0
     and not exists (select 1 from private.f7_piezas_en_observacion lib
                     where lib.firma = p.oid::regprocedure::text
                       and lib.estado in ('observacion','cerrada_permanente','demolida'));
  if v_n > 0 then
    raise exception 'OLA 2b preflight: % cuerpo(s) vivo(s) la nombran', v_n;
  end if;
end $ola2b_pre$;

drop function crm.metricas_altas_analista_fn(integer);

update private.f7_piezas_en_observacion
   set estado = 'demolida',
       nota = coalesce(nota,'') || ' | DEMOLIDA por la OLA 2b (migracion '
              || to_char((now() at time zone 'America/Lima')::date, 'YYYY-MM-DD')
              || ', `!` de Miguel): ventana cumplida, cero alertas, huella verificada'
              || ' contra la captura del 01/09 y marcha atras recreadora ensayada.'
 where firma = 'crm.metricas_altas_analista_fn(integer)' and estado = 'observacion';

do $ola2b_post$
declare v_n int; v_verd text;
begin
  if to_regprocedure('crm.metricas_altas_analista_fn(integer)') is not null then
    raise exception 'OLA 2b postflight: la funcion sigue viva';
  end if;
  -- Las dos del bridge NO se tocan (deuda declarada): siguen vivas y cerradas.
  if to_regprocedure('crm.metricas_distribucion_leads_fn(date,date)') is null
     or to_regprocedure('crm.metricas_distribucion_leads_v2_fn(date,date)') is null then
    raise exception 'OLA 2b postflight: se demolieron las del bridge y NO debia tocarlas';
  end if;
  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = 'crm.metricas_altas_analista_fn(integer)' and estado = 'demolida';
  if v_n <> 1 then
    raise exception 'OLA 2b postflight: el acta no quedo escrita';
  end if;

  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'OLA 2b postflight: vigilante F7 en rojo: %', v_verd; end if;
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'OLA 2b postflight: analitica en rojo: %', v_verd; end if;
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then raise exception 'OLA 2b postflight: la demolicion levanto % alerta(s)', v_n; end if;
end $ola2b_post$;

commit;
