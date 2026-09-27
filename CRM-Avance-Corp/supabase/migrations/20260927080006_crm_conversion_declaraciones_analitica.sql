-- Complemento de la conversión por fecha comercial: declaraciones técnicas.
-- No cambia funciones, permisos, contratos, importes, períodos ni el techo.
-- Dos escritores internos cuentan para validar integridad, no para publicar
-- métricas: se declaran operativos. La deuda conserva su clase analítica.
-- SQL PROPUESTO: requiere aprobación explícita antes de aplicarse o fusionarse.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

create temporary table _conversion_declaraciones_antes on commit drop as
select * from private.contadores_crudos_leads_citas()
where (not declarada or not huella_ok)
  and objeto not in (
    'private.conversion_conciliar_y_activar(jsonb)',
    'private.conversion_sincronizar_lead(uuid)',
    'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)');

do $preflight$
begin
  if exists (
    select 1 from (values
      ('private.conversion_conciliar_y_activar(jsonb)', '51a1dc582645558eeb2c5b395c7cc355'),
      ('private.conversion_sincronizar_lead(uuid)', '38bf077cb56a54f2741f073c94f51281'),
      ('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)', '1f85397dd87fd73e282990238f151742')
    ) x(objeto, huella)
    where to_regprocedure(x.objeto) is null
      or md5(pg_get_functiondef(to_regprocedure(x.objeto))) <> x.huella
  ) then raise exception 'Una definición difiere del SQL de conversión revisado'; end if;
  if not exists (
    select 1 from private.analitica_leads_citas_exenciones
    where objeto = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'
      and clase = 'analitica' and huella = '3d97f6a6f5dc7fdf853fb33d8bc0d1df'
  ) then raise exception 'La declaración previa de deuda cambió: revisar antes de sellar'; end if;
  if exists (
    select 1 from private.analitica_leads_citas_exenciones
    where objeto in ('private.conversion_conciliar_y_activar(jsonb)',
      'private.conversion_sincronizar_lead(uuid)')
  ) then raise exception 'Una declaración nueva ya existe: no sobrescribir'; end if;
  if (select sello from private.analitica_lc_sello where id)
    is distinct from private.huella_exenciones_analitica_lc()
  then raise exception 'La lista de declaraciones ya tiene una deriva sin sellar'; end if;
end;
$preflight$;

insert into private.analitica_leads_citas_exenciones (objeto,tipo,huella,razon,clase)
select x.objeto, 'funcion',
  md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc,pg_get_functiondef(p.oid))),
    '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
  x.razon, 'operativo'
from (values
  ('private.conversion_conciliar_y_activar(jsonb)',
   'Escritor administrativo privado, invoker y sin EXECUTE API: cuenta entradas y fuentes del manifiesto para rechazar duplicados, omisiones o conciliaciones parciales. No publica una tasa ni agrega resultados para Ranking o Metas; registra hechos mediante conversion_acreditar_fuente.'),
  ('private.conversion_sincronizar_lead(uuid)',
   'Escritor interno invoker sin EXECUTE API: cuenta las fuentes explícitamente enlazadas a un único lead para exigir exactamente una. Cero o múltiples fuentes quedan pendientes. Delega la acreditación en conversion_acreditar_fuente y no publica una métrica.')
) x(objeto,razon)
join pg_proc p on p.oid = to_regprocedure(x.objeto);

update private.analitica_leads_citas_exenciones e
set huella = md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc,pg_get_functiondef(p.oid))),
    '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
    razon = e.razon || ' Desde septiembre de 2026, la deuda toma el mes comercial y exige la pertenencia individual a la foto sellada en conversion_acreditaciones. Conserva el analista y peso congelados; sólo descuenta conversión, con capital cero e idempotencia por lead.'
from pg_proc p
where e.objeto = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'
  and p.oid = to_regprocedure(e.objeto);

update private.analitica_lc_sello
set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
where id;

do $postflight$
begin
  if exists (
    select 1 from private.contadores_crudos_leads_citas()
    where objeto in ('private.conversion_conciliar_y_activar(jsonb)',
      'private.conversion_sincronizar_lead(uuid)',
      'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)')
      and (not declarada or not huella_ok)
  ) or (select count(*) from private.contadores_crudos_leads_citas()
    where objeto in ('private.conversion_conciliar_y_activar(jsonb)',
      'private.conversion_sincronizar_lead(uuid)',
      'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)')) <> 3
  then raise exception 'Falta una declaración vigente de la conversión'; end if;
  if exists (
    (select * from private.contadores_crudos_leads_citas() where not declarada or not huella_ok
     except select * from _conversion_declaraciones_antes)
    union all
    (select * from _conversion_declaraciones_antes
     except select * from private.contadores_crudos_leads_citas() where not declarada or not huella_ok)
  ) then raise exception 'Cambió un hallazgo ajeno al alcance: no ocultarlo ni re-sellarlo'; end if;
  if (select sello from private.analitica_lc_sello where id)
    is distinct from private.huella_exenciones_analitica_lc()
  then raise exception 'Sello de declaraciones incorrecto'; end if;
end;
$postflight$;
commit;
