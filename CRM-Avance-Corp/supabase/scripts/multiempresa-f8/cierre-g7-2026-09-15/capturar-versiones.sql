-- Captura administrativa de catálogo, sin datos de clientes ni escrituras.
begin isolation level repeatable read read only;
set local statement_timeout='30s';
set local search_path='';
select jsonb_build_object(
 'corte',statement_timestamp(),'solo_lectura',current_setting('transaction_read_only'),
 'base',current_database(),'metodo','Catálogo PostgreSQL: definiciones/ACL y columnas/restricciones tocadas',
 'funciones',(select jsonb_agg(jsonb_build_object('firma',p.oid::regprocedure::text,
   'huella',md5(pg_get_functiondef(p.oid)),'propietario',pg_get_userbyid(p.proowner),'acl',p.proacl::text)
   order by p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname in('crm','public','private') and p.proname ~
   '(contrato|capital|conversion|postventa|retiro|renov|upgrade|periodo|cerrar_mes|responsable_relacion|identidad|inversion|coopac|piloto|rol_crm|es_lector|cartera_f5|puede_gestionar_contratos)'),
 'dependencias',(select jsonb_agg(jsonb_build_object('firma',p.oid::regprocedure::text,
   'huella',md5(pg_get_functiondef(p.oid)),'propietario',pg_get_userbyid(p.proowner),'acl',p.proacl::text)
   order by p.oid::regprocedure::text) from pg_proc p where p.oid in(
     'private.rentabilidad_minimo_alta(text,numeric)'::regprocedure,
     'private.cliente_tasa_lead(uuid)'::regprocedure,
     'private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)'::regprocedure)),
 'tablas',(select jsonb_agg(jsonb_build_object('tabla',c.oid::regclass::text,
   'columnas',(select jsonb_agg(jsonb_build_object('nombre',a.attname,'tipo',format_type(a.atttypid,a.atttypmod),
     'not_null',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
     from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
     where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
   'restricciones',(select jsonb_agg(jsonb_build_object('nombre',r.conname,'definicion',pg_get_constraintdef(r.oid))
     order by r.conname) from pg_constraint r where r.conrelid=c.oid)) order by c.oid::regclass::text)
   from pg_class c where c.oid in('crm.solicitudes_tasa'::regclass,'crm.conversion_reservas'::regclass,'private.contrato_pdf_jobs'::regclass))
) evidencia;
rollback;
