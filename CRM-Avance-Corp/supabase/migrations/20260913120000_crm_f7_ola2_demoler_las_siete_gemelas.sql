-- P-055 F7 · OLA 2 — DEMOLER LAS SIETE GEMELAS DEL CATALOGO VIEJO.
--
-- Tercer paso del metodo de Miguel: CERRAR (F5.d, 30/08, registro 186) →
-- OBSERVAR (14 dias) → DERRIBAR. Las siete llevan revocadas desde el 30/08:
-- nadie puede llamarlas, y su intento muere en 42501 antes del cuerpo.
--
-- ⛔ NO SE PUEDE APLICAR ANTES DEL 2026-09-13. No es disciplina: el libro
--    guarda `drop_no_antes_de` por fila y el preflight lo exige. Si se corre
--    antes, ABORTA — y esta bien que aborte.
--
-- MATERIAL DE MARCHA ATRAS: `scripts/rollback-f7-ola2-gemelas.sql` recrea las
-- siete con su DEFINICION VIVA capturada de produccion el 01/09 (owner, ACL y
-- atributos incluidos). El repo tiene 167 de 193 archivos y la F5.d cambio sus
-- cuerpos despues de nacer: la fuente es el REGISTRO y el catalogo vivo, jamas
-- la carpeta local.
--
-- ARTEFACTOS (leccion de la auditoria de Codex del 01/09): el oraculo
-- `scripts/test-productos-inversion.sql` NO se retira — es parte de
-- `gate:config` y prueba tambien snapshots, inmutabilidad, seleccion y ACL. Se
-- PODA aparte. Los mocks e2e comparten ramas con los endpoints PDF VIVOS.
--
-- Publicacion (Miguel, con `!`): esta migracion → registrar-f7-ola2-version.sql
-- → gates → advisors.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =====================================================================
-- 0) PREFLIGHT: la ventana, el libro, el vigia y las huellas.
-- =====================================================================
do $ola2_pre$
declare
  v_fn constant text[][] := array[
    array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', '8640b1246f620ab40558cec2875ada23'],
    array['crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', '4156191492c25479be73b0365263d946'],
    array['crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)', '06f79b07b4d65dcf50cd4359fb598723'],
    array['crm.crear_contrato_producto(uuid,jsonb,jsonb)', '1148d0ca1beb33797995eeff3c579bd4'],
    array['public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', 'b7e0de18b559ec7fd650619cd22b9cb5'],
    array['public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', 'f0e519cc4ee79c9334ae59a23844b23b'],
    array['public.crear_contrato_producto(uuid,jsonb,jsonb)', '893c857e27ec6405a3ac6e291458c346']
  ];
  v_fila text[]; v_h text; v_n int; v_hoy date;
  v_firmas constant text[] := array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', 'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', 'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)', 'crm.crear_contrato_producto(uuid,jsonb,jsonb)', 'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', 'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', 'public.crear_contrato_producto(uuid,jsonb,jsonb)'];
begin
  -- (a) LA VENTANA. Cada pieza trae su fecha en el libro; ninguna se adelanta.
  v_hoy := (now() at time zone 'America/Lima')::date;
  select count(*) into v_n
  from private.f7_piezas_en_observacion f
  where f.estado = 'observacion' and f.ola = 'F5.d'
    and (f.drop_no_antes_de is null or f.drop_no_antes_de::date > v_hoy);
  if v_n > 0 then
    raise exception 'OLA 2 preflight: % pieza(s) todavia en su ventana de observacion (hoy % en Lima). NO se adelanta el trinquete.', v_n, v_hoy;
  end if;

  -- (b) EL LIBRO: las 7, en observacion, con su OK escrito.
  select count(*) into v_n
  from private.f7_piezas_en_observacion f
  where f.ola = 'F5.d' and f.estado = 'observacion' and length(f.ok_miguel) >= 20;
  if v_n <> 7 then
    raise exception 'OLA 2 preflight: esperaba 7 gemelas en observacion con OK, hay %', v_n;
  end if;

  -- (c) STOP-THE-LINE: ninguna alerta abierta del vigia. Si hay una, se PARA
  --     y se atiende FUERA de este paquete destructivo (nunca dentro).
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'OLA 2 preflight: hay % alerta(s) del vigia sin resolver. Stop-the-line: se atienden ANTES y en otro paquete.', v_n;
  end if;

  -- (d) SON LAS QUE CREO: huella viva == huella capturada el 01/09.
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is null then
      raise exception 'OLA 2 preflight: % ya no existe — investigar antes de seguir', v_fila[1];
    end if;
    if v_h is distinct from v_fila[2] then
      raise exception 'OLA 2 preflight: % cambio de cuerpo desde la captura (huella %)', v_fila[1], v_h;
    end if;
  end loop;

  -- (e) SIGUEN CERRADAS: ni una tiene EXECUTE fuera de postgres.
  select count(*) into v_n
  from pg_proc p, aclexplode(p.proacl) a
  where p.oid = any (array(select f::regprocedure from unnest(v_firmas) f))
    and a.grantee <> 'postgres'::regrole and a.privilege_type = 'EXECUTE';
  if v_n > 0 then
    raise exception 'OLA 2 preflight: % permiso(s) EXECUTE reaparecieron — alguien las reabrio', v_n;
  end if;

  -- (f) NADIE VIVO LAS NOMBRA. `cerrar_altas_legacy_productos` las nombraba por
  --     `to_regprocedure`, y por eso se cerro antes en la F7.2 (01/09) con su
  --     propia acta: una pieza CERRADA CON LLAVE no puede ejecutarse, asi que su
  --     referencia es INERTE y no bloquea. Lo que si bloquea es un cuerpo vivo
  --     y alcanzable — eso es lo que se cuenta aqui.
  select count(*) into v_n
  from pg_proc p, unnest(v_firmas) f
  where p.oid <> f::regprocedure
    and p.pronamespace in ('crm'::regnamespace,'public'::regnamespace,'private'::regnamespace)
    and strpos(lower(p.prosrc), lower(split_part(f,'(',1))) > 0
    -- exentas: las que ya estan en el libro cerradas o demolidas (inertes)
    and not exists (
      select 1 from private.f7_piezas_en_observacion lib
      where lib.firma = p.oid::regprocedure::text
        and lib.estado in ('observacion','cerrada_permanente','demolida'))
  ;
  if v_n > 0 then
    raise exception 'OLA 2 preflight: % cuerpo(s) VIVO(s) y alcanzable(s) todavia nombran a las gemelas — resolverlos primero', v_n;
  end if;
end $ola2_pre$;

-- =====================================================================
-- 1) LA DEMOLICION.
-- =====================================================================
drop function crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb);
drop function crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb);
drop function crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb);
drop function crm.crear_contrato_producto(uuid,jsonb,jsonb);
drop function public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb);
drop function public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb);
drop function public.crear_contrato_producto(uuid,jsonb,jsonb);

-- =====================================================================
-- 2) EL ACTA: el libro las marca demolidas (la maquina de estados solo deja
--    ir a `demolida` por migracion, y de ahi no se vuelve sin candado bajado).
-- =====================================================================
update private.f7_piezas_en_observacion
   set estado = 'demolida',
       -- El trigger `solo_crece` EXIGE rastro al cambiar de estado: quien y por que.
       nota = coalesce(nota,'') || ' | DEMOLIDA por la OLA 2 (migracion '
              || to_char((now() at time zone 'America/Lima')::date, 'YYYY-MM-DD')
              || ', `!` de Miguel): ventana de observacion cumplida, cero alertas del vigia,'
              || ' huella verificada contra la captura del 01/09 y marcha atras recreadora ensayada.'
 where ola = 'F5.d' and estado = 'observacion';

-- =====================================================================
-- 3) POSTFLIGHT: se fueron las 7, no se fue nada mas, y el libro cuadra.
-- =====================================================================
do $ola2_post$
declare v_n int; v_verd text;
begin
  select count(*) into v_n from pg_proc p
   where p.pronamespace in ('crm'::regnamespace,'public'::regnamespace)
     and p.proname in ('crear_contrato_producto','actualizar_contrato_producto',
                       'crear_contrato_con_cuenta_producto','actualizar_contrato_con_cuenta_producto');
  if v_n <> 0 then
    raise exception 'OLA 2 postflight: quedan % gemelas vivas', v_n;
  end if;

  -- Las piezas VIVAS del contrato siguen en pie (no se llevo nada por delante).
  if to_regprocedure('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)') is null
     and to_regprocedure('crm.crear_contrato_con_cuenta_pdf(jsonb,jsonb,jsonb)') is null then
    raise exception 'OLA 2 postflight: no encuentro la puerta VIVA de alta de contratos';
  end if;

  select count(*) into v_n from private.f7_piezas_en_observacion
   where ola = 'F5.d' and estado = 'demolida';
  if v_n <> 7 then
    raise exception 'OLA 2 postflight: el libro marca % demolidas, esperaba 7', v_n;
  end if;
  -- Nada de la F5.d queda en observacion (se cuenta POR OLA a proposito: el
  -- libro crece con cohortes nuevas y un total fijo se rompe solo).
  select count(*) into v_n from private.f7_piezas_en_observacion
   where ola = 'F5.d' and estado = 'observacion';
  if v_n <> 0 then
    raise exception 'OLA 2 postflight: quedan % gemelas en observacion', v_n;
  end if;
  -- Y no se toco ninguna otra cohorte.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where ola <> 'F5.d' and estado = 'demolida';
  if v_n <> 0 then
    raise exception 'OLA 2 postflight: % pieza(s) de OTRA ola quedaron marcadas demolidas', v_n;
  end if;

  -- Los guardianes, en la misma transaccion.
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then
    raise exception 'OLA 2 postflight: el vigilante F7 en rojo: %', v_verd;
  end if;
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK%' then
    raise exception 'OLA 2 postflight: analitica en rojo: %', v_verd;
  end if;
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'OLA 2 postflight: la demolicion levanto % alerta(s)', v_n;
  end if;
end $ola2_post$;

commit;
