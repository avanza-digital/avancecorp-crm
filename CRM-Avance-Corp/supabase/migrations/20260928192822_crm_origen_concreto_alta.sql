-- Exigir canal concreto al dar de alta. Conserva las filas históricas y sus
-- etiquetas: no reclasifica datos ni modifica capital o conversiones.
-- CREATE OR REPLACE mantiene firmas, permisos, identidad y locks vigentes.
do $origen$
declare
  v_firma regprocedure;
  v_def text;
  v_cambio text[];
  v_acl aclitem[];
begin
  v_firma := 'private.leads_before_insert()'::regprocedure;
  select pg_get_functiondef(p.oid), p.proacl into v_def, v_acl
  from pg_proc p where p.oid=v_firma;
  v_cambio := array[
    E'begin\n  if not v_priv then',
    E'begin\n  -- Tambien aplica a importaciones y mantenimiento: no crear nuevos Otro.\n  if new.origen is null or new.origen not in (''referido'',''landing'',''formulario'',''oficina'',''web'',''campania'',''whatsapp'') then\n    raise exception using errcode = ''22023'', message = ''Selecciona un canal concreto: Landing, Formulario, Referido o Walking'';\n  end if;\n  if not v_priv then'
  ];
  if (length(v_def)-length(replace(v_def,v_cambio[1],'')))/length(v_cambio[1]) <> 1 then
    raise exception 'Preflight: cambio inesperado en leads_before_insert';
  end if;
  execute replace(v_def,v_cambio[1],v_cambio[2]);
  if (select proacl from pg_proc where oid=v_firma) is distinct from v_acl then
    raise exception 'Postflight: permisos del trigger alterados';
  end if;

  v_firma := 'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure;
  select pg_get_functiondef(p.oid),p.proacl into v_def,v_acl
  from pg_proc p where p.oid=v_firma;
  foreach v_cambio slice 1 in array array[
    array[
      'if p_origen not in (''referido'', ''landing'', ''formulario'', ''oficina'', ''otro'') then',
      'if p_origen is null or p_origen not in (''referido'', ''landing'', ''formulario'', ''oficina'') then'
    ],
    array[
      'Ese origen entra solo por el puente: el alta manual admite referido, oficina u otro',
      'Selecciona un canal concreto: Landing, Formulario, Referido o Walking'
    ],
    array[
      E'  -- D8 (2026-08-11) · «landing y formulario se carga solo»: los canales\n  -- automáticos (y los heredados) SOLO entran por el puente. Un alta manual que\n  -- los declare está suplantando a la fuente — y con T10 vivo (el referido\n  -- fuera del divisor), el origen mueve el porcentaje de alguien.',
      E'  -- Alta manual: cuatro canales concretos. Los heredados se leen,\n  -- pero no se eligen al crear. Referido conserva sus permisos propios.'
    ]
  ] loop
    if (length(v_def)-length(replace(v_def,v_cambio[1],'')))/length(v_cambio[1]) <> 1 then
      raise exception 'Preflight: cambio inesperado en crear_lead_si_disponible';
    end if;
    v_def := replace(v_def,v_cambio[1],v_cambio[2]);
  end loop;
  execute v_def;
  if (select proacl from pg_proc where oid=v_firma) is distinct from v_acl then
    raise exception 'Postflight: permisos de alta alterados';
  end if;
end;
$origen$;

comment on function crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text) is
'Alta manual atomica con disponibilidad e idempotencia. Canales activos: referido, landing, formulario y oficina. Otro e historicos no admitidos en nuevas altas. Referido conserva restriccion de vendedor a su propio nombre. LANDING/FORMULARIO manuales conservan su politica del divisor.';
