-- El vigilante de analitica vuelve a funcionar (Miguel, 21/09/2026).
--
-- ESTADO DE PARTIDA, medido en produccion el 21/09 (ensayo con rollback, nada
-- escrito): private.assert_analitica_leads_citas() esta en ROJO por DOS motivos.
--
--   1) `crm.contrato_eliminar_auditado(uuid,uuid)` aparece en el censo SIN
--      declarar. Es un FALSO POSITIVO demostrado: el censo exige (menciona
--      crm.leads o reunion) Y (tiene count( o sum(1)); esa funcion menciona
--      crm.leads porque limpia el vinculo del lead al borrar el contrato, y su
--      unico count() es `count(distinct c.conrelid) from pg_constraint`: cuenta
--      LLAVES FORANEAS DEL CATALOGO para fallar cerrado si el esquema gana
--      dependencias que su copia versionada todavia no cubre. No publica
--      ninguna metrica de analitica; devuelve el acta de la eliminacion.
--
--   2) Declararla NO basta, y se comprobo: el error solo cambia de cara a «Los
--      contadores crudos subieron de 30 a 31: el trinquete solo deja bajar».
--      La carraca esta disparada desde el 05/09 y el techo no puede subir
--      (trigger trg_analitica_lc_tope_solo_baja). Mientras siga asi,
--      `npm run gate:analitica` esta rojo y el cron vigia de las 06:49 alerta
--      cada dia sin que nadie pueda hacer nada con ese aviso.
--
-- DECISION DE MIGUEL (21/09): «los inspectores no son sospechosos». El censo ya
-- se excluye a si mismo y a los dos nucleos POR IDENTIDAD EXACTA (no por
-- nombre, para que un overload no se cuele). Se extiende esa misma idea a los
-- VERIFICADORES: piezas que cuentan para comprobar cifras ajenas y que no
-- publican ninguna cifra propia.
--
-- LA EXCLUSION VA ATADA A LA HUELLA DECLARADA, Y LA HUELLA LA CALCULA LA BASE.
-- Un verificador sale del censo solo mientras su cuerpo siga siendo EXACTAMENTE
-- el que se declaro en `private.analitica_leads_citas_exenciones`. Si alguien lo
-- cambia —por ejemplo, si el borrado de contratos empieza de verdad a contar
-- leads— la huella deja de coincidir, vuelve al censo y el vigilante salta. Eso
-- es lo que separa esto de apagar el detector.
--
-- Aqui NO se escribe ninguna huella a mano: el primer intento de esta migracion
-- las incrustaba como literales y la prueba en produccion demostro que una de
-- las dos estaba mal (venia del mensaje de error de un ensayo, no del censo), asi
-- que el falso positivo habria seguido dentro y el vigilante en rojo. Ahora la
-- huella sale de la propia declaracion, calculada por la base con la misma
-- expresion que usa el censo.
--
-- ARITMETICA, medida en produccion antes de escribir esto:
--   censo hoy 35 · auxiliares 4 · sujetos al techo 31 · techo 30  -> ROJO
--   censo estrechado 34 · auxiliares 4 · sujetos 30 · techo 30    -> CABE
--   0 quedarian sin declarar · 0 con huella caducada
-- Con el testigo de Citas instalado (20260921181323): 36 -> 34, sujetos 30.
-- Esta migracion funciona en CUALQUIER ORDEN respecto a esa: si el testigo aun
-- no existe, su identidad simplemente no casa con nada.
--
-- QUE NO HACE: no toca el techo, ni sus candados, ni la lista de auxiliares, ni
-- ninguna cifra de ninguna pantalla. Solo declara un falso positivo y estrecha
-- el censo en dos identidades ancladas a su huella declarada.
--
-- ⚠️ ORDEN CON OTRA SESION. El mismo 21/09 hay pendiente otra migracion ajena,
-- `20260921183436_crm_eliminacion_contrato_con_registro_inicial.sql`, que
-- REDEFINE el cuerpo de crm.contrato_eliminar_auditado. Como la huella de la
-- declaracion se calcula al instalar, esta migracion debe ir DESPUES de esa (su
-- sello de tiempo ya lo garantiza: 190145 > 183436). Si por lo que sea aquella
-- se aplicara despues, la declaracion queda caducada y el vigilante vuelve a
-- rojo con «la razon caduco»: se arregla volviendo a correr solo el bloque de
-- declaracion con `supabase/scripts/conversion/redeclarar-verificador.sql`.
-- El preflight de abajo comprueba el estado real antes de tocar nada.
--
-- Plan: «Una sola definicion de conversion», fase F3b (vault, 21/09/2026).
-- Reversa: reinstalar private.contadores_crudos_leads_citas() de 20260912151320
-- tal cual (queda en ese archivo, sin la clausula nueva) y borrar la exencion de
-- crm.contrato_eliminar_auditado, resellando.
-- Requiere aprobacion expresa antes de instalar en produccion.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = pg_catalog;
lock table private.analitica_leads_citas_exenciones, private.analitica_lc_sello
  in share row exclusive mode;

do $preflight$
declare
  v_n integer;
  v_aux integer;
  v_tope integer;
begin
  select count(*) into v_n from private.contadores_crudos_leads_citas();
  select count(*) into v_aux from private.auxiliares_analitica_lc_auditados();
  select tope into v_tope from private.analitica_leads_citas_tope where id;
  if v_tope is distinct from 30 then
    raise exception 'PREFLIGHT F3b: el techo ya no es 30 sino %; revisar antes de estrechar el censo', v_tope;
  end if;
  if v_aux is distinct from 4 then
    raise exception 'PREFLIGHT F3b: los auxiliares ya no son 4 sino %', v_aux;
  end if;
  if v_n not between 35 and 36 then
    raise exception 'PREFLIGHT F3b: el censo tiene % contadores, no los 35-36 medidos el 21/09', v_n;
  end if;
  -- El falso positivo tiene que seguir estando en el censo y sin declarar: si ya
  -- no esta, alguien lo resolvio de otra forma y esto no debe aplicarse a ciegas.
  if not exists (select 1 from private.contadores_crudos_leads_citas() c
                 where c.objeto = 'crm.contrato_eliminar_auditado(uuid,uuid)' and not c.declarada) then
    raise exception 'PREFLIGHT F3b: crm.contrato_eliminar_auditado ya no es un contador sin declarar; revisar el estado real';
  end if;
end;
$preflight$;

-- 1) La razon escrita del falso positivo. La huella la calcula la base con la
--    MISMA expresion que el censo, nunca a mano.
insert into private.analitica_leads_citas_exenciones (objeto, tipo, huella, razon)
select 'crm.contrato_eliminar_auditado(uuid,uuid)', 'funcion',
  md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
    '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
  'Falso positivo del censo: NO cuenta leads ni citas. Es la eliminacion auditada de un contrato; menciona crm.leads porque limpia el vinculo del lead con el contrato borrado, y su unico count() es count(distinct c.conrelid) sobre pg_constraint, o sea llaves foraneas del catalogo, para fallar cerrado si el esquema gana dependencias nuevas que su copia versionada todavia no cubre. No publica ninguna metrica de analitica: devuelve el acta de la eliminacion. Declarada con la huella de su cuerpo: si algun dia empieza a contar leads de verdad, la huella deja de coincidir, vuelve al censo y el trinquete salta.'
from pg_catalog.pg_proc p
where p.oid = 'crm.contrato_eliminar_auditado(uuid,uuid)'::regprocedure
-- `objeto` es la clave primaria: si ya estuviera declarada (por ejemplo porque
-- otra sesion cambio el cuerpo y hubo que re-declarar), se refresca la huella
-- en vez de fallar. La razon se reescribe para que nunca quede una obsoleta.
on conflict (objeto) do update
  set huella = excluded.huella, tipo = excluded.tipo,
      razon = excluded.razon, declarado_en = now();

update private.analitica_lc_sello
  set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
  where id;

-- 2) Censo identico al de 20260912151320 mas UNA clausula al final de `crudos`.
--    Todo lo demas se conserva palabra por palabra, incluidas las exclusiones
--    de los nucleos por identidad.
create or replace function private.contadores_crudos_leads_citas()
returns table(tipo text, objeto text, declarada boolean, huella_ok boolean)
language sql
stable
security definer
set search_path = ''
as $function$
  with fn as (
    -- TODOS los esquemas de usuario (fail-closed: lo del sistema se excluye por
    -- lista, no al reves - un esquema nuevo entra al censo solo); el cuerpo
    -- viene de prosrc O de pg_get_functiondef (funciones con prosqlbody);
    -- la exclusion de los nucleos y de las piezas del trinquete es por
    -- IDENTIDAD exacta, no por nombre (un overload malicioso no se cuela).
    select 'funcion'::text as tipo,
           p.oid::regprocedure::text as objeto,
           regexp_replace(regexp_replace(
             lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
             '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g') as cuerpo
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where p.prokind in ('f','p')
       and n.nspname not in ('pg_catalog','information_schema','pg_toast',
                             'auth','storage','vault','realtime','extensions',
                             'graphql','graphql_public','pgbouncer','net',
                             'supabase_functions','supabase_migrations','cron','pgsodium')
       and n.nspname not like 'pg\_%'
       and p.oid not in (
             coalesce(to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz)')::oid, 0),
             coalesce(to_regprocedure('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)')::oid, 0),
             coalesce(to_regprocedure('private.contadores_crudos_leads_citas()')::oid, 0),
             coalesce(to_regprocedure('private.assert_analitica_leads_citas()')::oid, 0))
  ),
  vw as (
    select 'vista'::text,
           c.relnamespace::regnamespace::text || '.' || c.relname,
           lower(pg_get_viewdef(c.oid))
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where c.relkind in ('v','m')
       and n.nspname not in ('pg_catalog','information_schema','pg_toast',
                             'auth','storage','vault','realtime','extensions',
                             'graphql','graphql_public','pgbouncer','net',
                             'supabase_functions','supabase_migrations','cron','pgsodium')
       and n.nspname not like 'pg\_%'
  ),
  todo as (select * from fn union all select * from vw),
  crudos as (
    -- Insensible a mayusculas (el cuerpo va en lower), tolera espacio tras el
    -- punto (un comentario borrado deja hueco: `crm. leads`), y caza tambien
    -- `sum(` ademas de `count(`. El SQL dinamico que nombre leads/tareas se
    -- censa entero: si su conteo no es demostrable, se declara.
    select t.tipo, t.objeto, md5(t.cuerpo) as huella
      from todo t
     where (t.cuerpo ~ '\mcrm\.\s*leads\M'
            or t.cuerpo ~ '\mreunion'
            or (t.cuerpo ~ '\mcrm\.\s*tareas\M' and t.cuerpo ~ '\mexecute\M'))
       and (t.cuerpo ~ '\mcount\s*\(' or t.cuerpo ~ '\msum\s*\(\s*1\s*\)')
       -- VERIFICADORES (21/09/2026, decision de Miguel): cuentan para comprobar
       -- cifras ajenas y no publican ninguna cifra propia. Salen del censo SOLO
       -- mientras su cuerpo sea exactamente el declarado: la huella se compara
       -- con la de su exencion, calculada por la base. Si el cuerpo cambia, la
       -- huella deja de casar, el verificador vuelve al censo y el trinquete
       -- salta. No es apagar el detector: es decirle que no vigile a quien esta
       -- ahi para vigilar.
       --   crm.contrato_eliminar_auditado: falso positivo probado. Menciona
       --     crm.leads al limpiar el vinculo del lead, y su unico count() es
       --     count(distinct c.conrelid) sobre pg_constraint.
       --   private.citas_testigo_mes: testigo independiente del Deposito % de
       --     Citas. Cuenta a proposito para contrastar la aritmetica del
       --     navegador; si bebiera de las CTE de la funcion grande seria
       --     tautologico y no probaria nada.
       and not exists (
         select 1
           from private.analitica_leads_citas_exenciones ve
          where ve.objeto = t.objeto
            and ve.huella = md5(t.cuerpo)
            and t.objeto in ('crm.contrato_eliminar_auditado(uuid,uuid)',
                             'private.citas_testigo_mes(date,date)')
       )
  )
  select cr.tipo,
         cr.objeto,
         (e.objeto is not null) as declarada,
         (e.objeto is not null and e.huella = cr.huella) as huella_ok
    from crudos cr
    left join private.analitica_leads_citas_exenciones e on e.objeto = cr.objeto
   order by 3, 4, 1, 2;
$function$;

comment on function private.contadores_crudos_leads_citas() is
  'Censo de contadores crudos de leads/citas. Excluye por identidad exacta los dos nucleos y sus propias piezas, y desde el 21/09/2026 tambien los VERIFICADORES, atados a su huella declarada: crm.contrato_eliminar_auditado (falso positivo, su count() es sobre pg_constraint) y private.citas_testigo_mes (testigo del Deposito % de Citas). Si el cuerpo de un verificador cambia, su huella deja de coincidir con la declarada y vuelve al censo.';

do $postflight$
declare
  v_veredicto text;
  v_n integer;
  v_aux integer;
  v_tope integer;
begin
  -- El falso positivo ya no esta en el censo.
  if exists (select 1 from private.contadores_crudos_leads_citas() c
             where c.objeto = 'crm.contrato_eliminar_auditado(uuid,uuid)') then
    raise exception 'POSTFLIGHT F3b: el falso positivo sigue en el censo: la huella declarada no casa con su cuerpo';
  end if;
  -- El censo no se ha quedado vacio: estrechar no es apagar.
  select count(*) into v_n from private.contadores_crudos_leads_citas();
  select count(*) into v_aux from private.auxiliares_analitica_lc_auditados();
  select tope into v_tope from private.analitica_leads_citas_tope where id;
  if v_n < 25 then
    raise exception 'POSTFLIGHT F3b: el censo bajo a % contadores: eso no es estrechar, es apagarlo', v_n;
  end if;
  if v_n - v_aux > v_tope then
    raise exception 'POSTFLIGHT F3b: siguen % sujetos al techo %', v_n - v_aux, v_tope;
  end if;
  -- Y NADIE se queda sin declarar ni con la razon caducada.
  if exists (select 1 from private.contadores_crudos_leads_citas() c
             where not c.declarada or not c.huella_ok) then
    raise exception 'POSTFLIGHT F3b: quedan contadores sin declarar o con huella caducada: %',
      (select string_agg(c.objeto, ', ') from private.contadores_crudos_leads_citas() c
       where not c.declarada or not c.huella_ok);
  end if;
  -- LA PRUEBA QUE IMPORTA: el vigilante vuelve a decir OK.
  v_veredicto := private.assert_analitica_leads_citas();
  raise notice 'POSTFLIGHT F3b: VIGILANTE EN VERDE >>> %', v_veredicto;
end;
$postflight$;

commit;
