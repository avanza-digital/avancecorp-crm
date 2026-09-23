-- =========================================================================
-- CRM · Ola 2 · La puerta #12 (`crm.cerrar_periodo`) declara EN SU COMENTARIO
-- =========================================================================
-- QUE HACE: refresca el `COMMENT ON` de `crm.cerrar_periodo(date)` para que
-- diga, por escrito y donde se lee, con que criterio escribe la foto mensual.
-- NO toca el cuerpo. NO toca ningun dato.
--
-- 🔴 POR QUE AQUI NO SE TOCA EL CUERPO, Y ES UNA DECISION, NO UN OLVIDO.
--
-- Las otras once puertas LEEN. Esta ESCRIBE: es la que sella el mes. Para
-- acreditar un cambio en su cuerpo habria que EJECUTARLA, y ejecutarla es
-- SELLAR UN MES DE VERDAD en produccion. Un cambio que no se puede verificar no
-- entra: esa es la regla de la casa («implementar no es verificar»).
--
-- Ensayarla dentro de una transaccion con `rollback` tampoco acredita: es
-- `volatile` y participa en el ceremonial de cierre; cualquier efecto que no
-- viva en las tablas (avisos, llamadas externas) NO se deshace con el rollback.
--
-- Y el coste de equivocarse no es una cifra mal pintada: es que el mes no se
-- pueda cerrar. Hoy no hay ningun mes sellado contra el que comprobarlo.
--
-- 🔑 LO QUE SI SE PUEDE AFIRMAR, Y QUEDA ESCRITO: esta funcion escribe el
--    BRUTO. El descuento por cierres anulados NO se aplica al sellar: se
--    registra como DEUDA en `crm.ajustes_mes_cerrado` y lo resta LA LECTURA
--    (`crm.conversion_mensual_fn`). Medido el 22/09/2026 plantando 2 puntos de
--    deuda: la oficial baja de 6 a 4 sin que la foto se recalcule.
--    Por eso `crm.cerrar_periodo` NO discrepa de nadie: no publica una cifra,
--    fija la base sobre la que las demas calculan.
--
-- CUANDO SE HACE LA DECLARACION EN EL PAYLOAD: en el ENSAYO del primer cierre
-- de mes, que este proyecto ya tiene por costumbre hacer por adelantado en vez
-- de esperar al dia 1. Ahi si hay como ejecutarla y comprobar la foto.
-- Anotado en `pendientes/unificar-puertas.md`.
--
-- El comentario NO vive en `prosrc` ni en `pg_get_functiondef`, asi que este
-- cambio no mueve ninguna huella: ni la del censo (clase `analitica`, md5 del
-- cuerpo `9efc07b35e9b...`) ni la de la F7. El postflight lo comprueba.
-- =========================================================================

begin;

set local statement_timeout = '60s';

do $preflight$
declare v_md5 text;
begin
  select left(md5(pg_get_functiondef(p.oid)), 12) into v_md5
    from pg_proc p where p.oid = to_regprocedure('crm.cerrar_periodo(date)');
  if v_md5 is distinct from '9efc07b35e9b' then
    raise exception 'PREFLIGHT: el cuerpo vivo de cerrar_periodo no es el conocido (md5 %). No se toca nada.', v_md5;
  end if;
end;
$preflight$;

create temp table _p12_antes (md5_def text, md5_prosrc text, trinquete text) on commit drop;
insert into _p12_antes
select md5(pg_get_functiondef(p.oid)), md5(p.prosrc), private.assert_analitica_leads_citas()
  from pg_proc p where p.oid = to_regprocedure('crm.cerrar_periodo(date)');

comment on function crm.cerrar_periodo(date) is
  'Sella una foto mensual coherente de conversion, cumplimiento, capital y cartera. Conserva '
  'los candados global/periodo y los ajustes; incluye al vendedor que produjo sin meta con '
  'objetivos cero y congela aparte, dentro de cobertura.fuera_ranking, la produccion de '
  'supervisores u otros perfiles no analistas. '
  'DECLARACION DE LA UNIFICACION (Ola 2, 22/09/2026): esta funcion ESCRIBE la foto, no '
  'publica una cifra, y la escribe en BRUTO. El descuento por cierres anulados no se aplica '
  'al sellar: se registra como deuda en crm.ajustes_mes_cerrado y lo resta LA LECTURA, en '
  'crm.conversion_mensual_fn. Por eso no discrepa de ninguna puerta: fija la base sobre la '
  'que las demas calculan. Su payload aun no lleva las cuatro claves del contrato '
  '(es_mes_calendario, fuente, sellado, ajuste_aplicado) porque acreditarlas exigiria '
  'ejecutarla, y ejecutarla es sellar un mes de verdad: se hara en el ensayo del primer '
  'cierre.';

do $postflight$
declare v_a record; v_md5_def text; v_md5_prosrc text; v_ok text;
begin
  select * into v_a from _p12_antes;
  select md5(pg_get_functiondef(p.oid)), md5(p.prosrc) into v_md5_def, v_md5_prosrc
    from pg_proc p where p.oid = to_regprocedure('crm.cerrar_periodo(date)');

  -- 1) Ni el cuerpo ni su definicion se movieron: un COMMENT ON no los toca.
  if v_md5_def is distinct from v_a.md5_def or v_md5_prosrc is distinct from v_a.md5_prosrc then
    raise exception 'POSTFLIGHT: el comentario movio el cuerpo, lo que no deberia pasar nunca';
  end if;

  -- 2) El trinquete dice exactamente lo mismo que antes.
  v_ok := private.assert_analitica_leads_citas();
  if v_ok is distinct from v_a.trinquete then
    raise exception 'POSTFLIGHT: el trinquete cambio de veredicto. antes % · despues %', v_a.trinquete, v_ok;
  end if;

  -- 3) Y el comentario nuevo esta puesto.
  if coalesce(obj_description(to_regprocedure('crm.cerrar_periodo(date)')::oid, 'pg_proc'), '')
       not like '%DECLARACION DE LA UNIFICACION%' then
    raise exception 'POSTFLIGHT: el comentario no quedo escrito';
  end if;
end;
$postflight$;

select 'puerta12-declara-en-su-comentario' as migracion,
       private.assert_analitica_leads_citas() as trinquete;

commit;
