-- Sonda de lectura sin escrituras de negocio ni sesiones humanas. Solo devuelve
-- conteos por rol; los UUID y datos personales permanecen dentro de la transacción.
begin;
set local statement_timeout='60s';
create temporary table gestion_sonda(rol text,visibles integer,contextos integer,avance integer,coopac integer) on commit drop;
do $sonda$
declare a record;p record;c jsonb;n integer;total integer;av integer;co integer;fuente uuid;
begin
  for a in select e.perfil_id,e.rol_crm from crm.equipo e join public.perfiles perfil on perfil.id=e.perfil_id where e.activo and perfil.activo and e.rol_crm in('gerencia','supervisor','vendedor') loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',a.perfil_id,'role','authenticated')::text,true);
    select count(*) into n from private.cartera_f5_personas_visibles();
    total:=0;av:=0;co:=0;
    for p in select * from (select v.*,row_number() over(partition by v.perfil_id is null order by v.inversionista_id) as muestra from private.cartera_f5_personas_visibles() v) s where muestra<=2 loop
      set local role authenticated;
      c:=crm.inversionista_gestion_fn(p.inversionista_id);
      assert c->>'inversionista_id'=p.inversionista_id::text;
      assert jsonb_typeof(c#>'{contacto,puede_corregir}')='boolean';
      assert jsonb_typeof(c#>'{documento,puede_corregir}')='boolean';
      reset role;
      total:=total+1;
      select t.id into fuente from public.contratos t where t.cliente_id=any(p.perfil_ids) order by t.creado_en desc limit 1;
      if fuente is not null then
        set local role authenticated;
        c:=crm.inversionista_gestion_fn(p.inversionista_id,fuente);
        assert c#>>'{inversion,contrato,id}'=fuente::text;
        reset role;
        av:=av+1;
      end if;
      select t.id into fuente from crm.cierres_externos t where t.inversionista_id=p.inversionista_id and t.anulado_en is null order by t.creado_en desc limit 1;
      if fuente is not null then
        set local role authenticated;
        c:=crm.inversionista_gestion_fn(p.inversionista_id,fuente);
        assert c#>>'{inversion,fuente_id}'=fuente::text;
        assert jsonb_typeof(c#>'{inversion,coopac}')='object';
        reset role;
        co:=co+1;
      end if;
    end loop;
    insert into gestion_sonda values(a.rol_crm,n,total,av,co);
  end loop;
end;
$sonda$;
select rol,count(*) as cuentas,min(visibles) as minimo_visibles,max(visibles) as maximo_visibles,sum(contextos) as contextos,sum(avance) as avance,sum(coopac) as coopac from gestion_sonda group by rol order by rol;
rollback;
