CREATE OR REPLACE FUNCTION crm.reservar_conversion_lead(p_lead_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid      uuid := (select auth.uid());
  v_rol      text := private.rol_crm((select auth.uid()));
  v_lead     crm.leads%rowtype;
  v_expira   timestamptz;
  v_ahora    timestamptz := now();
  v_ventana  interval := interval '5 minutes';
  -- Tope absoluto: más allá de esto, ni el propio dueño renueva. Holgado para
  -- cualquier conversión real (que tarda segundos) y corto para un secuestro.
  v_tope     interval := interval '30 minutes';
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;

  -- El FOR UPDATE serializa contra el cierre externo DENTRO de esta
  -- transacción: si el externo va ganando, aquí se espera y luego se ve el lead
  -- ya convertido → la edge se entera ANTES de crear nada.
  select *
    into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true
    and (
      v_rol = 'gerencia'
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
      or (
        vendedor_id is null
        and asignado_supervisor_id in (
          select private.vendedor_ids_visibles((select auth.uid()))
        )
      )
    )
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito';
  end if;

  if v_lead.etapa in ('convertido', 'descartado') then
    raise exception 'El lead ya esta cerrado';
  end if;

  -- Alias explícito `r`: en el WHERE del DO UPDATE hay que nombrar la fila que
  -- YA existe, y `crm.conversion_reservas.expira_en` ahí se lee peor de lo que
  -- se ejecuta. Si el WHERE no se cumple no se actualiza nada y el RETURNING no
  -- devuelve fila: eso es la señal de «hay una conversión en vuelo».
  --
  -- Se puede tomar/renovar SOLO si la anterior está caducada, o si es del mismo
  -- actor Y no ha pasado su tope absoluto. Las dos condiciones exigen además
  -- que NADIE haya iniciado efectos: una vez creada la cuenta de Auth, esa
  -- reserva es definitiva y ni su propio dueño la reinicia.
  -- Quién puede tomar o retomar la reserva:
  --   · nadie, si hay efectos iniciados y la reserva es DE OTRO (esa conversión
  --     ya creó una cuenta: solo su dueño puede terminarla);
  --   · SU DUEÑO, siempre que no se haya pasado el tope absoluto — incluso con
  --     efectos ya iniciados. Esto es lo que hace posible el REINTENTO: si la
  --     conversión Avance falla en el último paso, la pantalla dice «reintenta»
  --     y ese reintento tiene que poder entrar. Sin esta rama, un fallo de red
  --     en la última llamada dejaba el lead trabado PARA SIEMPRE.
  --   · cualquiera, si la reserva caducó y nunca hubo efectos.
  -- `efectos_iniciados_en` NO se limpia al retomar: el cierre en cooperativa
  -- sigue vetado, que es la garantía que importa.
  insert into crm.conversion_reservas as r
    (lead_id, reservado_por, expira_en, vence_absoluto_en)
  values (p_lead_id, v_uid,
          v_ahora + v_ventana, v_ahora + v_tope)
  on conflict (lead_id) do update
     set reservado_por = excluded.reservado_por,
         reservado_en  = v_ahora,
         -- El tope absoluto MANDA sobre la ventana: sin este `least`, renovar a
         -- los 29 minutos daba 5 más y el tope no era un tope.
         expira_en     = least(excluded.expira_en,
                               case when r.reservado_por = v_uid
                                    then r.vence_absoluto_en
                                    else excluded.vence_absoluto_en end),
         vence_absoluto_en = case
           -- Retomar la propia reserva NO reinicia el tope.
           when r.reservado_por = v_uid then r.vence_absoluto_en
           else excluded.vence_absoluto_en
         end
   where (r.reservado_por = v_uid and r.vence_absoluto_en > v_ahora)
      or (r.efectos_iniciados_en is null and r.expira_en <= v_ahora)
  returning r.expira_en into v_expira;

  if v_expira is null then
    -- Distinguir los motivos importa: uno se resuelve esperando y el otro no.
    if exists (select 1 from crm.conversion_reservas r2
               where r2.lead_id = p_lead_id and r2.efectos_iniciados_en is not null) then
      raise exception using
        errcode = 'P0409',
        message = 'Este lead ya tiene una conversion a cliente de Avance empezada por otra persona',
        hint    = 'Ya existe una cuenta de portal a su nombre: quien la empezo tiene que terminarla.';
    end if;
    raise exception using
      errcode = 'P0409',
      message = 'Otra persona esta convirtiendo este lead en este momento',
      hint    = 'Espera unos minutos y vuelve a intentarlo.';
  end if;

  return jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'expira_en', v_expira);
end;
$function$

