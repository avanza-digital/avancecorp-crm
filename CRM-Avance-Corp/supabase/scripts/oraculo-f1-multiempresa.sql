-- ORÁCULO F1 multiempresa — SOLO en el BANCO (nunca en producción).
-- Corre DESPUÉS de aplicar 20260903160000 en el banco. Todo en una transacción
-- que hace ROLLBACK: no persiste datos de prueba. Prueba el gate G1 de F1:
--   (a) cierre total a la Data API; (b) resolver idempotente; (c) el índice
--   único arbitra; (d) documentos distintos no colapsan; (e) el DNI NO viaja en
--   claro a public.audit_log (enmascarado tras el fix B1); (f) núcleo intacto.
-- La CONCURRENCIA real (N sesiones a la vez) va en oraculo-f1-concurrencia.sh.
begin;
do $ora$
declare
  v1 uuid; v2 uuid; v_ce uuid; v_inv int; v_ident int; v_rol text; t text;
  v_doc text := '87654321'; v_leak int;
  v_tablas text[] := array[
    'empresas','inversionistas','inversionista_identificadores','inversionista_leads',
    'inversionista_responsables','inversionista_fusiones','inversiones','inversion_titulares',
    'multiempresa_idempotencia','multiempresa_flags'];
begin
  -- (a) CERO acceso de la Data API a las 10 tablas.
  foreach t in array v_tablas loop
    foreach v_rol in array array['anon','authenticated','service_role'] loop
      if has_table_privilege(v_rol,'crm.'||t,'SELECT') or has_table_privilege(v_rol,'crm.'||t,'INSERT')
         or has_table_privilege(v_rol,'crm.'||t,'UPDATE') or has_table_privilege(v_rol,'crm.'||t,'DELETE') then
        raise exception 'ORACULO F1: % alcanza crm.% por la Data API', v_rol, t;
      end if;
    end loop;
  end loop;
  -- y el resolver no es ejecutable por la API.
  foreach v_rol in array array['anon','authenticated','service_role'] loop
    if has_function_privilege(v_rol,'private.inversionista_resolver(text,text,boolean,text)','EXECUTE') then
      raise exception 'ORACULO F1: % puede ejecutar el resolver', v_rol;
    end if;
  end loop;

  -- (b) idempotencia: el mismo documento (con formato distinto) -> la misma persona.
  v1 := private.inversionista_resolver('DNI','8-765-4321', true);   -- verificado; normaliza a 87654321
  v2 := private.inversionista_resolver('DNI', v_doc);   -- sin verificar: debe RESOLVER la existente
  if v1 is null or v1 <> v2 then raise exception 'ORACULO F1: resolver no idempotente (% <> %)', v1, v2; end if;
  select count(*) into v_inv   from crm.inversionistas where id = v1;
  select count(*) into v_ident from crm.inversionista_identificadores where inversionista_id=v1 and estado='vigente';
  if v_inv<>1 or v_ident<>1 then raise exception 'ORACULO F1: se esperaba 1 persona y 1 doc vigente (%/%)', v_inv, v_ident; end if;

  -- (c) el índice único parcial arbitra: un segundo vigente del mismo doc no entra.
  begin
    insert into crm.inversionista_identificadores(inversionista_id,tipo_documento,documento_normalizado,estado,verificado)
      values (v1,'DNI',v_doc,'vigente',false);
    raise exception 'ORACULO F1: el índice único NO arbitró (segundo vigente se coló)';
  exception when unique_violation then null;
  end;

  -- (d) documento distinto -> identidad distinta.
  v_ce := private.inversionista_resolver('CE','123456789', true);  -- CE 9-12 digitos
  if v_ce = v1 then raise exception 'ORACULO F1: documentos distintos colapsaron en una identidad'; end if;

  -- (e) el DNI NO viaja en claro a public.audit_log (enmascarado, fix B1).
  select count(*) into v_leak from public.audit_log
   where tabla = 'inversionista_identificadores'
     and (coalesce(data_despues::text,'') like '%'||v_doc||'%'
       or coalesce(data_antes::text,'')   like '%'||v_doc||'%');
  if v_leak <> 0 then raise exception 'ORACULO F1: el documento % aparece en audit_log (% filas) — PII en claro', v_doc, v_leak; end if;

  -- (f) el núcleo de Capital existe con su forma (F1 no toca dinero).
  if to_regprocedure('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])') is null then
    raise exception 'ORACULO F1: desapareció private.capital_episodios';
  end if;

  raise notice 'ORÁCULO F1 TODO VERDE: API cerrada, resolver idempotente y único, documentos separados, PII enmascarada, núcleo intacto.';
end
$ora$;
rollback;
