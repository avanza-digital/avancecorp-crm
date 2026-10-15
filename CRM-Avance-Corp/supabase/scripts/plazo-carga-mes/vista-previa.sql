-- VISTA PREVIA del ensayo de 20261015000852_crm_plazo_carga_mes. NO se corre sola: va pegada DETRÁS del cuerpo de la
-- migración sin su `commit;` (ver LEEME.md, paso 1), dentro de la MISMA transacción, y termina en ROLLBACK.
-- Con la migración ya instalada (sin confirmar), y con la identidad de una Gerencia activa, muestra:
--   · lo que la pantalla recibiría (crm.plazos_carga_mes_fn);
--   · lo que haría fijar el plazo de septiembre 2026 hasta dentro de 7 días: si lo reabriría (hoy NO: septiembre está
--     abierto desde el 14/10), cuántas acreditaciones «fuera de plazo» se reevaluarían y cuántas chocarían por identidad.
-- Nada queda escrito: la última sentencia es ROLLBACK (y NOTIFY tampoco sale en una transacción deshecha).
-- `supabase db query` solo muestra la ÚLTIMA sentencia con filas: el veredicto va en el último SELECT.
do $vista$
declare
  v_g uuid;
  v_lectura jsonb;
  v_fijar jsonb;
  v_antes jsonb;
  v_despues jsonb;
begin
  -- Gerencia activa (la de «ADMINISTRADOR AVANCE CORP» si existe; si no, la primera). Solo identidad para el ensayo.
  select e.perfil_id into v_g
    from crm.equipo e join public.perfiles p on p.id = e.perfil_id
   where private.rol_crm(e.perfil_id) = 'gerencia'
   order by (p.nombre_completo = 'ADMINISTRADOR AVANCE CORP') desc, e.perfil_id
   limit 1;
  if v_g is null then
    raise exception 'VISTA PREVIA: no hay una Gerencia activa';
  end if;
  perform set_config('request.jwt.claim.sub', v_g::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_g, 'role', 'authenticated')::text, true);
  v_lectura := crm.plazos_carga_mes_fn();
  select jsonb_object_agg(x.estado, x.n) into v_antes from (
    select ca.estado, count(*) as n from crm.conversion_acreditaciones ca
     where ca.periodo_comercial = date '2026-09-01' group by ca.estado) x;
  begin
    v_fijar := crm.fijar_plazo_carga_mes(date '2026-09-01', (now() at time zone 'America/Lima')::date + 7,
                                         'Vista previa del ensayo (se deshace)');
  exception when others then
    v_fijar := jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
  end;
  -- «ENSAYO OK» acredita también la operación simulada, no solo el pre/postflight (revisión Codex r1): si fijar el plazo
  -- de septiembre falla, el ensayo entero falla y no se aplica.
  if v_fijar ? 'error' or (v_fijar ->> 'ok') is distinct from 'true' then
    raise exception 'VISTA PREVIA: fijar el plazo de septiembre falló (%); revisar antes de aplicar', v_fijar ->> 'error';
  end if;
  select jsonb_object_agg(x.estado, x.n) into v_despues from (
    select ca.estado, count(*) as n from crm.conversion_acreditaciones ca
     where ca.periodo_comercial = date '2026-09-01' group by ca.estado) x;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  create temp table _vista_previa_plazo on commit drop as
    select jsonb_build_object(
      'resultado', 'ENSAYO OK: preflight, postflight, foto de trinquetes y fijar el plazo de septiembre pasaron contra producción; TODO SE DESHACE',
      'lectura_de_gerencia', v_lectura,
      'fijar_septiembre_hasta_dentro_de_7_dias', v_fijar,
      'septiembre_sellado', exists (select 1 from crm.periodos_cerrados where periodo = date '2026-09-01'),
      'plazo_septiembre_sin_decision', private.conversion_plazo_base(date '2026-09-01'),
      'acreditaciones_septiembre_antes', v_antes,
      'acreditaciones_septiembre_despues', v_despues
    ) as vista;
end
$vista$;
select vista as vista_previa from pg_temp._vista_previa_plazo;
rollback;
