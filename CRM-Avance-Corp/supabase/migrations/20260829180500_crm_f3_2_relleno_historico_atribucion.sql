-- P-055 Fase 3.2 - El relleno del historico, decision por decision.
--
-- TOCA `public` (datos, no estructura): con permiso explicito de Miguel.
--
-- ⚠️ AQUI NO SE INVENTA NINGUNA REGLA. El plan maestro dice «el historico se
-- rellena con la regla de respaldo» y esa regla NO ESTA DEFINIDA en ninguna
-- parte del plan. En vez de inventarla, se midio el historico entero el
-- 2026-08-29 y resulto que las decisiones que Miguel YA tomo cubren
-- practicamente todo. Lo que queda fuera se deja VACIO y se declara, en vez de
-- rellenarse a ojo.
--
-- LO MEDIDO (466 contratos):
--   * 16 los registro gerencia. Los 16 estan resueltos uno por uno por las
--     decisiones 6 y 18 -ver abajo-.
--   * 4 los registro alguien sin rol activo en el CRM: 3 de IVETT TEEVIN
--     (analista del portal, `vendedor` INACTIVA en el equipo) y 1 de GLORIA
--     (`admin` del portal, que nunca estuvo en el equipo comercial).
--   * 446 los registro el equipo comercial en activo.
--   * 0 de 466 tienen lead enlazado (`crm.leads.contrato_id` esta muerto), asi
--     que el camino del «analista explicito del lead» no existe para nada del
--     historico.
--
-- LAS CINCO REGLAS QUE SE APLICAN, CON SU FUENTE:
--
--   (1) DEMOS -> `es_demo = true`, sin dueno.
--       Decision 6: «444444 y 888282 son demos (de Kirk) → se excluyen de
--       metricas y ranking».
--
--   (2) 001163 -> ADELAYDA GASPAR MARTINEZ.
--       Decision 6, literal: «001163 es de Adelayda y cuenta para agosto».
--
--   (3) 001325 -> MIGUEL BRICENO.
--       Decision 6, literal: «001325 es de Miguel Briceno».
--
--   (4) LOS 12 DE MAYO A JULIO QUE REGISTRO GERENCIA -> SE QUEDAN SIN DUENO.
--       Decision 18: «se quedan sin dueno y fuera del ranking historico. El
--       podio arranca limpio desde agosto». No se escribe nada en ellos: el
--       vacio ES la decision.
--
--   (5) TODO LO DEMAS QUE REGISTRO ALGUIEN DEL EQUIPO COMERCIAL ->
--       `analista_cierre_id = creado_por`.
--       Esto es lo unico que NO sale de una frase literal de Miguel, asi que se
--       explica: Codex refuto `creado_por` como regla UNIVERSAL, y su
--       contraejemplo fueron exactamente los contratos que registro gerencia
--       para otros. Esos 16 quedan resueltos uno a uno arriba. Lo que sobra es
--       el flujo normal: un analista registrando su propia venta. Se incluye a
--       quien ya no esta en activo (IVETT) porque la decision 15 dice que «su
--       venta cuenta igual».
--       ⚠️ SI MIGUEL PREFIERE OTRA REGLA, ESTE ES EL PASO A CAMBIAR: se revierte
--       con `scripts/rollback-f3-p055.sql` ENTERO (no solo este paso: la
--       migracion 181500 cuelga un candado sobre la columna y un re-relleno
--       parcial rebotaria contra el) y se vuelve a correr. Nada mas depende
--       de el. Este bloque ademas abre la valvula del candado por si acaso:
--       es la MISMA transaccion y se cierra sola.
--
--   (6) EL UNICO CASO SIN REGLA: `2026-01-000180` (S/ 160 000, febrero), que
--       registro GLORIA, administrativa que nunca estuvo en el equipo comercial.
--       El cliente tiene analista (LINDA CONDORI) pero la decision 1 dice que
--       ese vinculo «NO es la guia del ranking», asi que NO se usa.
--       SE DEJA SIN DUENO y se declara aqui. Es de febrero: no afecta al podio,
--       que «arranca limpio desde agosto».
--
-- RESULTADO ESPERADO: 15 contratos sin dueno (12 de la decision 18 + 2 demos +
-- 1 de GLORIA), 2 marcados como demo, y todo lo demas con dueno. El postflight
-- NO usa conteos absolutos de la tabla entera: la base esta viva -mientras se
-- escribia esto Astrid registro el 001333- y cada venta nueva los volveria
-- mentira. Comprueba la FORMA: quien tenia que quedar vacio esta vacio, quien
-- tenia que quedar marcado esta marcado, y nadie perdio su registrador.

begin;

-- ---------------------------------------------------------------- PREFLIGHT --
do $preflight$
declare
  v_sin_campo integer;
  v_ya_escrito integer;
begin
  -- 3.1 tiene que haber corrido.
  select count(*) into v_sin_campo from pg_attribute
  where attrelid='public.contratos'::regclass
    and attname in ('analista_cierre_id','es_demo') and not attisdropped;
  if v_sin_campo <> 2 then
    raise exception 'Falta la migracion 20260829180000 (el campo y la marca): ABORTA';
  end if;

  -- Se corre UNA vez sobre un lienzo limpio. Si ya hay algo escrito, parar:
  -- reejecutar sobre datos ya corregidos a mano pisaria el trabajo de alguien.
  select count(*) into v_ya_escrito from public.contratos
  where analista_cierre_id is not null or es_demo;
  if v_ya_escrito <> 0 then
    raise exception 'Ya hay % contratos con atribucion o marca de demo: ABORTA (esta migracion es para un lienzo limpio; revisar a mano)', v_ya_escrito;
  end if;

  -- Los cuatro contratos que Miguel nombro tienen que existir, o la decision 6
  -- se estaria aplicando a algo que no es lo que el miro. En una base LIMPIA
  -- (0 contratos) no aplica: el bloque de relleno se omite entero mas abajo.
  if (select count(*) from public.contratos) > 0
     and (select count(*) from public.contratos
          where split_part(numero_contrato,'-',3) in ('444444','888282','001163','001325')) <> 4 then
    raise exception 'No estan los 4 contratos nombrados en la decision 6 (444444, 888282, 001163, 001325): ABORTA';
  end if;
end
$preflight$;

-- ------------------------------------------------------------------ CAMBIO --
set local lock_timeout = '5s';

do $relleno$
declare
  v_adelayda   uuid;
  v_miguel     uuid;
  v_nombre     text;
  v_demos      integer;
  v_regla5     integer;
begin
  -- P2-3 (Codex): en una base LIMPIA (db reset, preview branch, replay de
  -- esquema) no hay contratos y los 4 numeros de la decision 6 no existen.
  -- Ese no es un fallo del relleno: es que no hay nada que rellenar. Se sale
  -- en voz alta en vez de abortar todo el historial de migraciones.
  if (select count(*) from public.contratos) = 0 then
    raise notice 'RELLENO OMITIDO: base sin contratos (replay limpio); el relleno es solo para la base real';
    return;
  end if;

  -- Las DOS valvulas de los candados de 181500 (si existen): en el primer
  -- despliegue no estan y esto es un no-op; en un re-run tras rollback+ajuste,
  -- evita rebotar contra ellos (P1-1 de Codex: el paso de demos abre la SUYA).
  -- Transaccion-local: se apagan solas.
  perform set_config('crm.reasignando_analista', 'on', true);
  perform set_config('crm.marcando_demo', 'on', true);

  ----------------------------------------------------------------- (1) DEMOS --
  update public.contratos
     set es_demo = true
   where split_part(numero_contrato,'-',3) in ('444444','888282');
  get diagnostics v_demos = row_count;
  if v_demos <> 2 then
    raise exception 'Se esperaban 2 demos y se marcaron %: ABORTA', v_demos;
  end if;

  ------------------------------------------------------- (2) 001163 = ADELAYDA --
  -- Se toma del analista del cliente y se COMPRUEBA contra el nombre que dijo
  -- Miguel. Si no coincide, aborta: prefiero no escribir a escribir mal.
  select cli.asesor_perfil_id into v_adelayda
  from public.contratos c
  join public.perfiles cli on cli.id = c.cliente_id
  where split_part(c.numero_contrato,'-',3) = '001163';

  select nombre_completo into v_nombre from public.perfiles where id = v_adelayda;
  if v_nombre is null or upper(v_nombre) not like 'ADELAYDA%' then
    raise exception 'El 001163 no apunta a Adelayda sino a "%": ABORTA (decision 6)', coalesce(v_nombre,'(nadie)');
  end if;

  update public.contratos
     set analista_cierre_id = v_adelayda
   where split_part(numero_contrato,'-',3) = '001163';

  --------------------------------------------------- (3) 001325 = MIGUEL BRICENO --
  select cli.asesor_perfil_id into v_miguel
  from public.contratos c
  join public.perfiles cli on cli.id = c.cliente_id
  where split_part(c.numero_contrato,'-',3) = '001325';

  select nombre_completo into v_nombre from public.perfiles where id = v_miguel;
  if v_nombre is null or upper(v_nombre) not like 'MIGUEL BRICE%' then
    raise exception 'El 001325 no apunta a Miguel Briceno sino a "%": ABORTA (decision 6)', coalesce(v_nombre,'(nadie)');
  end if;

  update public.contratos
     set analista_cierre_id = v_miguel
   where split_part(numero_contrato,'-',3) = '001325';

  ------------------------------------------------------------------ (5) EL RESTO --
  -- Quien lo tecleo es del equipo comercial (activo o no) -> la venta es suya.
  -- Quedan fuera, sin tocar: lo que registro gerencia (decisiones 6 y 18), los
  -- demos, y lo que registro alguien ajeno al equipo comercial (GLORIA).
  update public.contratos c
     set analista_cierre_id = c.creado_por
   where c.analista_cierre_id is null
     and not c.es_demo
     and c.creado_por is not null
     -- Del equipo comercial pero NO gerencia. La membresia se mira DIRECTO en
     -- crm.equipo y sin exigir `activo`: `private.rol_crm()` devuelve NULL para
     -- una gerencia dada de baja (hoy hay UNA) y con ella la excluida dejaria
     -- de excluirse — sus contratos se auto-atribuirian contra la decision 18.
     -- (Hallazgo M8 del auditor RLS, 29/08.)
     and exists (select 1 from crm.equipo e
                 where e.perfil_id = c.creado_por
                   and e.rol_crm <> 'gerencia');
  get diagnostics v_regla5 = row_count;

  raise notice 'RELLENO: 2 demos, 2 nombrados por Miguel, % por el equipo que los registro', v_regla5;
end
$relleno$;

-- --------------------------------------------------------------- POSTFLIGHT --
do $postflight$
declare
  v_con      integer;
  v_sin      integer;
  v_demos    integer;
  v_ger      integer;
  v_gloria   integer;
  v_pisado   integer;
begin
  if (select count(*) from public.contratos) = 0 then
    raise notice 'POSTFLIGHT OMITIDO: base sin contratos (replay limpio)';
    return;
  end if;

  select count(*) filter (where analista_cierre_id is not null),
         count(*) filter (where analista_cierre_id is null),
         count(*) filter (where es_demo)
    into v_con, v_sin, v_demos
  from public.contratos;

  -- La FORMA anunciada en la cabecera, no un conteo absoluto de la tabla viva.
  if v_demos <> 2 then
    raise exception 'POSTFLIGHT: se esperaban 2 demos, hay %', v_demos;
  end if;
  -- Sin dueno quedan EXACTAMENTE los 15 del pasado con regla (o sin ella):
  -- cualquier otro sin dueno seria un contrato que la regla 5 debio cubrir.
  if v_sin <> 15 then
    raise exception 'POSTFLIGHT: se esperaban 15 sin dueno y hay % — alguno quedo fuera de las reglas', v_sin;
  end if;
  if v_con < 451 then
    raise exception 'POSTFLIGHT: hay % con dueno y el relleno debia dejar al menos 451', v_con;
  end if;

  -- Decision 18: lo que registro CUALQUIER gerencia (activa o dada de baja)
  -- sigue sin dueno, salvo los 2 que Miguel nombro (001163/001325). Se mira la
  -- membresia en crm.equipo, no rol_crm(): asi el postflight caza tambien a la
  -- gerencia inactiva que la regla vieja dejaba pasar.
  select count(*) into v_ger
  from public.contratos c
  where exists (select 1 from crm.equipo e
                where e.perfil_id = c.creado_por and e.rol_crm = 'gerencia')
    and c.analista_cierre_id is not null
    and split_part(c.numero_contrato,'-',3) not in ('001163','001325');
  if v_ger <> 0 then
    raise exception 'POSTFLIGHT: % contratos registrados por gerencia quedaron CON dueno (decision 18)', v_ger;
  end if;

  -- El caso declarado sin regla sigue vacio, no relleno a ojo.
  select count(*) into v_gloria from public.contratos
  where numero_contrato = '2026-01-000180' and analista_cierre_id is not null;
  if v_gloria <> 0 then
    raise exception 'POSTFLIGHT: el 000180 (el caso sin regla) quedo relleno';
  end if;

  -- Y lo esencial: NO SE PISO EL REGISTRADOR. `creado_por` es otra cosa.
  select count(*) into v_pisado from public.contratos where creado_por is null;
  if v_pisado <> 0 then
    raise exception 'POSTFLIGHT: hay % contratos que perdieron su registrador', v_pisado;
  end if;

  raise notice 'POSTFLIGHT OK: % con dueno, % sin dueno (12 de la decision 18 + 2 demos + 1 sin regla), % demos', v_con, v_sin, v_demos;
end
$postflight$;

commit;
