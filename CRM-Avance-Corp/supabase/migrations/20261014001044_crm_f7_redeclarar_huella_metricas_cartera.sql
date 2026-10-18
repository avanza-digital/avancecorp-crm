-- F7: re-declarar la huella de metricas_cartera tras el permiso de Coordinación.
-- El cuerpo y la definición coinciden con la migración aplicada 20261012223850.
-- Se conservan acceso cerrado, propietario, ACL, atributos y las demás piezas.
-- La huella F7 es md5(prosrc), no md5(pg_get_functiondef).
-- Reversa: nueva migración con las huellas invertidas, únicamente si también se
-- restaura el cuerpo anterior; restaurar solo el sello volvería a abrir la alerta.
-- El gate analítico general tiene deriva previa ajena; se registra por separado,
-- sin cambiarlo ni normalizar sus declaraciones dentro de esta corrección F7.
-- Tras aplicar: ejecutar private.vigia_f7_piezas() para cerrar la alerta verificada.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- =====================================================================
-- 0) PREFLIGHT: la fila es la que creo, el mundo es el que creo, y no hay
--    una SEGUNDA deriva que este cambio estaria tapando.
-- =====================================================================
do $pre$
declare
  v_firma    constant text := 'crm.metricas_cartera_fn(date)';
  v_vieja    constant text := '0b4ede547cf7079be1e56073311453b3';
  v_nueva    constant text := '869853c25e903fe2f79245b8176c09b9';
  v_defin    constant text := '67cdc767f0d38277a920b2ec5aebf2ae';
  v_acl      constant text := '{postgres=X/postgres}';
  v_oid oid; v_n int; v_detalle text;
  v_estado text; v_ola text; v_huella text; v_acl_viva text; v_dueno text;
begin
  v_oid := to_regprocedure(v_firma);
  if v_oid is null then
    raise exception 'F7 re-declaracion: % no existe — el mundo no es el que esta migracion asume', v_firma;
  end if;

  select f.estado, f.ola, f.huella_md5
    into v_estado, v_ola, v_huella
  from private.f7_piezas_en_observacion f
   where f.firma = v_firma;
  if v_estado is null then
    raise exception 'F7 re-declaracion: % no esta en el libro', v_firma;
  end if;
  if v_estado is distinct from 'cerrada_permanente' or v_ola is distinct from 'F7.1' then
    raise exception 'F7 re-declaracion: % esta como %/% y se esperaba cerrada_permanente/F7.1', v_firma, v_estado, v_ola;
  end if;
  if v_huella is distinct from v_vieja then
    raise exception 'F7 re-declaracion: la huella declarada de % es % y se esperaba % — alguien ya la toco; revisar antes de reescribirla', v_firma, v_huella, v_vieja;
  end if;

  -- El cuerpo VIVO es exactamente el que se midio, por las DOS anclas: el
  -- `prosrc` que el assert compara y la definicion COMPLETA, que ademas
  -- arrastra firma, lenguaje, volatilidad, SECURITY DEFINER y search_path.
  -- Un cuerpo identico con otro `search_path` seria otra funcion a efectos de
  -- seguridad y cuadraria solo la primera ancla.
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)), p.proacl::text, pg_get_userbyid(p.proowner)
    into v_huella, v_detalle, v_acl_viva, v_dueno
  from pg_proc p where p.oid = v_oid;
  if v_huella is distinct from v_nueva then
    raise exception 'F7 re-declaracion: el cuerpo vivo de % tiene huella % y se midio % — volver a medir antes de sellar', v_firma, v_huella, v_nueva;
  end if;
  if v_detalle is distinct from v_defin then
    raise exception 'F7 re-declaracion: la DEFINICION completa de % cambio (huella %) — el cuerpo cuadra pero los atributos no', v_firma, v_detalle;
  end if;
  if v_acl_viva is distinct from v_acl then
    raise exception 'F7 re-declaracion: % SE REABRIO (ACL %, se esperaba %) — esto ya no es una huella desfasada', v_firma, v_acl_viva, v_acl;
  end if;
  if v_dueno is distinct from 'postgres' then
    raise exception 'F7 re-declaracion: % cambio de dueño a «%»', v_firma, v_dueno;
  end if;

  -- NINGUNA otra pieza vigilada puede estar derivada. Si la hubiera, poner al
  -- dia solo esta dejaria al vigilante en rojo por otra causa y el arreglo
  -- pareceria no haber funcionado.
  select count(*), string_agg(o.firma, ' | ')
    into v_n, v_detalle
  from private.f7_piezas_en_observacion o
  left join pg_proc p on p.oid = to_regprocedure(o.firma)
   where o.estado in ('observacion','cerrada_permanente')
     and o.firma <> v_firma
     and (p.oid is null or md5(p.prosrc) is distinct from o.huella_md5
          or p.proacl::text is distinct from o.acl_esperada);
  if v_n > 0 then
    raise exception 'F7 re-declaracion: hay % pieza(s) MAS con huella o ACL derivada — resolverlas en el mismo paquete o el vigilante sigue en rojo: %', v_n, v_detalle;
  end if;

  -- Y el vigilante esta en rojo HOY por esta causa y no por otra: si ya
  -- estuviera verde, esta migracion no tendria nada que arreglar.
  -- Codex P2 (24/09): `strpos(sqlerrm, firma)` es demasiado laxo — el error de OTRA
  -- pieza que nombrara esta firma (como llamador permitido, por ejemplo) colaria.
  -- Se exige el MENSAJE COMPLETO que el assert produce para esta causa exacta.
  declare
    v_esperado constant text := format(
      'F7: el cuerpo de %s cambio estando cerrada (huella %s)', v_firma, v_nueva);
  begin
    perform private.assert_f7_piezas_cerradas();
    raise exception 'F7 re-declaracion: el vigilante ya esta VERDE — nada que re-declarar';
  exception
    when others then
      if sqlerrm like '%re-declaracion%' then raise; end if;
      if sqlerrm is distinct from v_esperado then
        raise exception 'F7 re-declaracion: el vigilante esta en rojo por OTRA causa. Esperaba «%», recibi «%»', v_esperado, sqlerrm;
      end if;
  end;
end $pre$;

-- Foto de la fila ANTES de tocarla, para poder acreditar despues que solo se
-- movieron los dos campos previstos (Codex P3: el postflight afirmaba «nada mas
-- se movio» sin compararlo). Temporal: muere con la sesion.
create temporary table f7_foto_previa on commit drop as
select * from private.f7_piezas_en_observacion
 where firma = 'crm.metricas_cartera_fn(date)';

-- =====================================================================
-- 1) LA RE-DECLARACION. `trg_f7_obs_00_solo_crece` congela `huella_md5` a
--    proposito; su propio comentario manda bajar este candado NOMBRADO en un
--    DO de migracion (doctrina limpieza-leads) y volver a subirlo. Se baja
--    SOLO este trigger, por nombre, y se re-activa en la MISMA transaccion.
-- =====================================================================
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;

do $acta$
declare v_n int;
begin
  update private.f7_piezas_en_observacion
     set huella_md5 = '869853c25e903fe2f79245b8176c09b9',
         nota = coalesce(nota, '') || E'\n'
                || 'Huella RE-DECLARADA el '
                || to_char((now() at time zone 'America/Lima')::date, 'YYYY-MM-DD')
                || ' (0b4ede54 → 869853c2): Coordinación en lectura, migración aplicada'
                || ' 20261012223850 crm_coordinacion_reportes_lectura. Se conserva el cierre,'
                || ' el propietario, los atributos y los permisos; solo se actualiza el sello.'
   where firma = 'crm.metricas_cartera_fn(date)'
     and estado = 'cerrada_permanente'
     and huella_md5 = '0b4ede547cf7079be1e56073311453b3';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'F7 re-declaracion: el UPDATE toco % filas, esperaba exactamente 1', v_n;
  end if;
end $acta$;

alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;

-- =====================================================================
-- 2) POSTFLIGHT: el vigilante en verde, el candado MORDIENDO otra vez, y
--    ninguna otra fila movida.
-- =====================================================================
do $post$
declare
  v_firma constant text := 'crm.metricas_cartera_fn(date)';
  v_verd text; v_n int; v_mordio boolean := false; v_msg text;
begin
  -- (a) El vigilante F7 vuelve a devolver texto en vez de lanzar.
  --     Codex P2 (24/09): `not like` con NULL da NULL y NO entra en el if — un
  --     veredicto nulo pasaria por verde. Se exige no-nulo explicitamente.
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd is null or v_verd not like 'OK%' then
    raise exception 'F7 re-declaracion postflight: el vigilante sigue en rojo: %', coalesce(v_verd, '(NULL)');
  end if;

  -- (b) EL CANDADO MUERDE. Comprobar `tgenabled` solo acredita que el trigger
  --     esta colgado, no que funcione: «puesto» no es «funciona». Se intenta un
  --     UPDATE que DEBE rebotar con 42501; si pasa, el candado quedo suelto.
  --     Codex P2 (24/09): un 42501 de OTRO origen (otro trigger, un permiso)
  --     tambien daria verde, asi que ademas se exige el MENSAJE del candado y
  --     que el trigger este habilitado. Las tres cosas, no una.
  begin
    update private.f7_piezas_en_observacion
       set acl_esperada = acl_esperada || ' '
     where firma = v_firma;
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      v_mordio := v_msg like '%no se reescribe%';
      if not v_mordio then
        raise exception 'F7 re-declaracion postflight: rebota 42501 pero NO es el candado: «%»', v_msg;
      end if;
  end;
  if not v_mordio then
    raise exception 'F7 re-declaracion postflight: trg_f7_obs_00_solo_crece NO rebota — el candado quedo suelto';
  end if;
  select count(*) into v_n from pg_trigger
   where tgrelid = 'private.f7_piezas_en_observacion'::regclass
     and tgname = 'trg_f7_obs_00_solo_crece' and not tgisinternal and tgenabled <> 'D';
  if v_n <> 1 then
    raise exception 'F7 re-declaracion postflight: el candado no quedo HABILITADO (coincidencias %)', v_n;
  end if;

  -- (b2) Solo se movieron los DOS campos previstos. Codex P3: el comentario
  --      afirmaba «nada mas se movio» y nadie lo comparaba.
  select count(*) into v_n
  from private.f7_piezas_en_observacion a
  join f7_foto_previa b on b.firma = a.firma
   where a.firma = v_firma
     and (to_jsonb(a) - 'huella_md5' - 'nota')
         is not distinct from (to_jsonb(b) - 'huella_md5' - 'nota');
  if v_n <> 1 then
    raise exception 'F7 re-declaracion postflight: algun campo AJENO a huella_md5/nota cambio en la fila de %', v_firma;
  end if;

  -- (b3) Las anclas del cuerpo vivo, OTRA VEZ al final. Codex las señala como
  --      riesgo: se comprobaban solo en el preflight, y un `ALTER FUNCTION`
  --      concurrente que cambiara `search_path` conservaria `prosrc` y se
  --      colaria por el assert. Repetirlas no sustituye serializar el DDL, pero
  --      estrecha la ventana.
  select count(*) into v_n from pg_proc p
   where p.oid = to_regprocedure(v_firma)
     and md5(p.prosrc) = '869853c25e903fe2f79245b8176c09b9'
     and md5(pg_get_functiondef(p.oid)) = '67cdc767f0d38277a920b2ec5aebf2ae'
     and pg_get_userbyid(p.proowner) = 'postgres'
     and p.proacl::text = '{postgres=X/postgres}';
  if v_n <> 1 then
    raise exception 'F7 re-declaracion postflight: el cuerpo o los atributos de % cambiaron DURANTE la transaccion', v_firma;
  end if;

  -- (c) La fila quedo como se queria y NADA mas se movio.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = v_firma
     and huella_md5 = '869853c25e903fe2f79245b8176c09b9'
     and estado = 'cerrada_permanente'
     and acl_esperada = '{postgres=X/postgres}'
     and drop_no_antes_de is null;
  if v_n <> 1 then
    raise exception 'F7 re-declaracion postflight: la fila de % no quedo como se esperaba', v_firma;
  end if;

end $post$;

commit;
