-- Sólo banco sintético. Comprueba la lectura de identidades sin conversión.
begin;
set local statement_timeout='60s';
do $test$
declare
  v_analista uuid; v_gerencia uuid;
  v_persona uuid:=gen_random_uuid(); v_alias uuid:=gen_random_uuid();
  v_lead1 uuid:=gen_random_uuid(); v_lead2 uuid:=gen_random_uuid();
  v_lead3 uuid:=gen_random_uuid(); v_lead4 uuid:=gen_random_uuid(); v_lead5 uuid:=gen_random_uuid();
  v_perfil1 uuid:=gen_random_uuid(); v_perfil2 uuid:=gen_random_uuid();
  v_r jsonb; v_a text; v_b text; v_c text; v_d text; v_e text;
begin
  if exists(select 1 from auth.users where email not like '%@pruebas.example' and email not like '%@demo.avancecorp.pe') then
    raise exception 'Sólo banco de pruebas';
  end if;
  select id into strict v_analista from public.perfiles where correo='vend1.crm@demo.avancecorp.pe';
  select id into strict v_gerencia from public.perfiles where correo='gerencia.crm@demo.avancecorp.pe';
  perform set_config('request.jwt.claim.sub','',true);
  insert into auth.users(id,email) values
    (v_perfil1,'identidad-'||v_perfil1::text||'@pruebas.example'),
    (v_perfil2,'identidad-'||v_perfil2::text||'@pruebas.example');
  insert into public.perfiles(id,correo,nombre_completo,rol,activo) values
    (v_perfil1,'identidad-'||v_perfil1::text||'@pruebas.example','IDENTIDAD SINTETICA A','cliente',true),
    (v_perfil2,'identidad-'||v_perfil2::text||'@pruebas.example','IDENTIDAD SINTETICA B','cliente',true)
    on conflict(id) do nothing;
  insert into crm.inversionistas(id,estado,creado_por) values(v_persona,'activo',v_analista);
  insert into crm.inversionistas(id,estado,inversionista_canonico_id,fusionado_en,creado_por,perfil_id)
    values(v_alias,'fusionado',v_persona,now(),v_analista,v_perfil1);
  -- Estado histórico de fusión: la persona canónica no tiene perfil; un alias sí.
  -- Sólo la preparación del banco usa la válvula de los escritores internos.
  -- La lectura se comprueba sin ella; no se deshabilitan triggers ni se convierte.
  perform set_config('crm.op_privilegiada','on',true);
  insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,moneda,vendedor_id,creado_por,inversionista_id,perfil_id)
    values(v_lead1,'IDENTIDAD CITAS A','+51962009981','referido',10000,'PEN',v_analista,v_analista,v_persona,v_perfil1),
          (v_lead2,'IDENTIDAD CITAS B','+51962009982','referido',10000,'PEN',v_analista,v_analista,v_alias,null),
          (v_lead3,'IDENTIDAD CITAS C','+51962009983','referido',10000,'PEN',v_analista,v_analista,null,v_perfil1),
          (v_lead4,'IDENTIDAD CITAS D','+51962009984','referido',10000,'PEN',v_analista,v_analista,null,v_perfil2),
          (v_lead5,'IDENTIDAD CITAS E','+51962009985','referido',10000,'PEN',v_analista,v_analista,null,null);
  perform set_config('crm.op_privilegiada','off',true);
  perform set_config('request.jwt.claim.sub',v_gerencia::text,true);
  v_r:=crm.citas_gerencia_consulta_fn(date_trunc('month',current_date)::date,(date_trunc('month',current_date)+interval '1 month -1 day')::date);
  select p->>'identidad_persona' into v_a from jsonb_array_elements(v_r->'gestion'->'poblacion') p where p->>'lead_id'=v_lead1::text;
  select p->>'identidad_persona' into v_b from jsonb_array_elements(v_r->'gestion'->'poblacion') p where p->>'lead_id'=v_lead2::text;
  select p->>'identidad_persona' into v_c from jsonb_array_elements(v_r->'gestion'->'poblacion') p where p->>'lead_id'=v_lead3::text;
  select p->>'identidad_persona' into v_d from jsonb_array_elements(v_r->'gestion'->'poblacion') p where p->>'lead_id'=v_lead4::text;
  select p->>'identidad_persona' into v_e from jsonb_array_elements(v_r->'gestion'->'poblacion') p where p->>'lead_id'=v_lead5::text;
  assert v_a is not null and v_a='persona:'||v_persona::text and v_b=v_a and v_c=v_a,'Tres leads, con y sin perfil, comparten la persona canónica sin perfil';
  assert v_d is not null and v_d='perfil:'||v_perfil2::text,'Perfil sin inversionista conserva su identidad';
  assert v_e is not null and v_e='lead:'||v_lead5::text,'Lead sin vínculo no se fusiona por datos personales';
  assert not exists(select 1 from jsonb_array_elements(v_r->'gestion'->'conversiones') c where c->>'lead_id' in(v_lead1::text,v_lead2::text,v_lead3::text,v_lead4::text,v_lead5::text)),'El vínculo no inventa clientes';
  assert (v_r->'gestion'->'control'->>'version')::integer=0,'Sin aplicación previa se conserva versión cero';
  assert v_r->'gestion'->'control'->'configuracion'->'base_depositos'='null'::jsonb,'Los defaults del editor no aplican reglas en el servidor';
end $test$;
select 'PASS: identidad canónica sin conversión, sin clientes inventados y sin aplicación automática' as evidencia;
rollback;
