-- Backfill único · tipo A · molde ENSAYADO en el banco (casos sintéticos).
-- La versión de producción es este mismo cuerpo con la lista de casos real.
-- Modo (solo banco): set ensayo.modo = 'transitorio' | 'conservar'.
--   transitorio (A1′): la inversión inicial y la solicitud de respaldo existen solo
--                     dentro de la transacción; tras convertir se retiran (copia en audit_log).
--   conservar  (A1):  se quedan (lo que se aprobó con condición).
do $a$
declare
  v_admin constant uuid := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';
  v_modo text := coalesce(nullif(current_setting('ensayo.modo', true), ''), 'transitorio');
  v_caso record; v_c public.contratos%rowtype; v_p public.perfiles%rowtype;
  v_inv uuid; v_lead uuid; v_inversion uuid; v_inv_previa boolean; v_primera_previa boolean;
  v_sol uuid; v_empresa uuid; v_n int; v_hechos int := 0; v_saltados int := 0;
  v_sol_original crm.inversion_solicitudes%rowtype; v_sol_apartada boolean; v_foto_original jsonb;
begin
  perform pg_catalog.set_config('lock_timeout', '5s', true);
  -- Mismo orden de candados que crm.convertir_lead (jerarquía → documento → persona → lead): el
  -- interlock COMPARTIDO de jerarquía se toma al entrar, antes que cualquier fila (revisión Codex 23/09).
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  if (clock_timestamp() at time zone 'America/Lima')::date >= date '2026-10-01' then
    raise exception 'Ya es octubre en Lima: los cierres caerían en octubre. Se detiene.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
    (date '2026-09-01' - date '2000-01-01')::integer);
  if exists (select 1 from crm.periodos_cerrados where periodo = date '2026-09-01') then
    raise exception 'Setiembre 2026 está sellado: el backfill se detiene';
  end if;
  select id into strict v_empresa from crm.empresas where clave = 'avance';

  for v_caso in select * from (values
      -- (contrato, su número, origen que dio Miguel, teléfono SOLO si la ficha del cliente no lo tiene)
      ('e0000000-0000-4000-8000-00000000000a'::uuid, 'BANCO-A1', 'referido', null::text),
      ('e0000000-0000-4000-8000-00000000000b'::uuid, 'BANCO-A2', 'formulario', null),
      ('e0000000-0000-4000-8000-00000000000e'::uuid, 'BANCO-B2-1', 'landing', null),
      ('e0000000-0000-4000-8000-000000000010'::uuid, 'BANCO-A3', 'formulario', null)   -- A3: con solicitud sin lead
    ) x(contrato_id, numero, origen, telefono) loop
    perform pg_catalog.set_config('request.jwt.claims', '', true);   -- escritor interno, sin sesión
    select * into strict v_c from public.contratos where id = v_caso.contrato_id for share;
    if v_c.numero_contrato is distinct from v_caso.numero then
      raise exception 'El id % no es el contrato % de la lista', v_caso.contrato_id, v_caso.numero;
    end if;

    -- Idempotencia ESTRICTA: solo se salta si el cliente ya tiene EXACTAMENTE el lead de este
    -- backfill para este contrato, convertido y con su cierre de setiembre para la analista.
    -- Cualquier otro lead del cliente detiene todo (revisión Codex 23/09).
    if exists (select 1 from crm.leads l where l.perfil_id = v_c.cliente_id or l.contrato_id = v_c.id) then
      if exists (select 1 from crm.leads l
                  where (l.perfil_id = v_c.cliente_id or l.contrato_id = v_c.id)
                    and not coalesce(l.alta_manual and l.creado_por = v_admin and l.etapa = 'convertido'
                          and l.vendedor_id = v_c.analista_cierre_id
                          and l.nota like ('Backfill 2026-09 · contrato ' || v_c.numero_contrato || ' · %')
                          and exists (select 1 from crm.lead_asignaciones la
                                       where la.lead_id = l.id and la.resultado = 'convertido'
                                         and la.analista_id = v_c.analista_cierre_id
                                         and (la.resultado_en at time zone 'America/Lima')::date
                                             between date '2026-09-01' and date '2026-09-30'), false)) then
        raise exception 'Contrato %: el cliente ya tiene un lead que no es el de este backfill; revisar', v_c.numero_contrato;
      end if;
      v_saltados := v_saltados + 1;
      continue;
    end if;

    -- Guardas del caso: exactamente la forma revisada.
    if v_c.categoria is distinct from 'nuevo' or v_c.estado <> 'activo' or v_c.es_demo
       or v_c.fecha_cierre_comercial not between date '2026-09-01' and date '2026-09-30'
       or v_c.analista_cierre_id is null or private.contrato_en_eliminacion(v_c.id) then
      raise exception 'Contrato % fuera de la forma revisada', v_c.numero_contrato;
    end if;
    if exists (select 1 from public.contratos c2 where c2.cliente_id = v_c.cliente_id and c2.id <> v_c.id and not c2.es_demo
               and (c2.fecha_cierre_comercial < v_c.fecha_cierre_comercial
                    or (c2.fecha_cierre_comercial = v_c.fecha_cierre_comercial and c2.creado_en < v_c.creado_en))) then
      raise exception 'Contrato %: no es el primer contrato del cliente (sería tipo B)', v_c.numero_contrato;
    end if;
    if v_caso.origen not in ('referido', 'landing', 'formulario', 'oficina') then
      raise exception 'Contrato %: origen % no admitido', v_c.numero_contrato, v_caso.origen;
    end if;
    select * into strict v_p from public.perfiles where id = v_c.cliente_id and rol = 'cliente' and activo;
    select coalesce(i.inversionista_canonico_id, i.id) into strict v_inv
      from crm.inversionistas i where i.perfil_id = v_c.cliente_id and i.estado <> 'fusionado';
    if exists (select 1 from crm.inversionistas i where i.id = v_inv and i.no_contactar) then
      raise exception 'Contrato %: la persona tiene «No insistir»', v_c.numero_contrato;
    end if;
    if exists (select 1 from private.leads_de_personas(array[v_inv])) then
      raise exception 'Contrato %: la persona ya tiene un lead por identidad', v_c.numero_contrato;
    end if;
    if not private.es_destino_crm_activo(v_c.analista_cierre_id, array['vendedor', 'supervisor']::text[]) then
      raise exception 'Contrato %: la analista no está activa', v_c.numero_contrato;
    end if;

    -- 1. El lead, por la vía del escritor interno (la del importador). Sin DNI: con el DNI de
    --    alguien que ya es cliente, la identidad responde «ya_es_cliente» y no hay otra puerta.
    if nullif(btrim(coalesce(v_caso.telefono, v_p.telefono)), '') is null then
      raise exception 'Contrato %: sin teléfono no nace el lead', v_c.numero_contrato;
    end if;
    insert into crm.leads (nombre_completo, telefono, correo, origen, etapa, vendedor_id,
      monto_estimado, moneda, activo, alta_manual, creado_por, nota)
    values (v_p.nombre_completo, coalesce(v_caso.telefono, v_p.telefono), v_p.correo, v_caso.origen, 'nuevo', v_c.analista_cierre_id,
      v_c.capital, v_c.moneda, true, true, v_admin,
      'Backfill 2026-09 · contrato ' || v_c.numero_contrato || ' · cliente creado sin lead')
    returning id into v_lead;

    -- 2. Andamio: la inversión inicial que exige crm.leads (conversion_lead_con_inversion).
    select id, es_primera_conversion into v_inversion, v_primera_previa
      from crm.inversiones where contrato_id = v_c.id for update;
    v_inv_previa := found;
    if not v_inv_previa then
      v_inversion := private.inversion_vincular_fuente(v_inv, v_c.id, null, v_admin, true);
    end if;
    update crm.inversiones set es_primera_conversion = true where id = v_inversion;
    -- La inversión puede traer ya una solicitud: la del formulario usado SIN lead (001377, 001396,
    -- 001416). Solo se admite esa forma exacta: confirmada, sin lead y sin revisiones, correcciones
    -- ni orígenes que dependan de ella. Se APARTA y al final se repone idéntica (mismo id, mismos
    -- datos). Su origen nunca se modifica: el candado inversion_origen_inmutable no se toca.
    select * into v_sol_original from crm.inversion_solicitudes s where s.inversion_id = v_inversion for update;
    v_sol_apartada := found;
    if v_sol_apartada then
      if v_modo <> 'transitorio' then
        raise exception 'Contrato %: con solicitud existente solo cabe el modo transitorio', v_c.numero_contrato;
      end if;
      if v_sol_original.estado <> 'confirmada' or v_sol_original.lead_origen_id is not null
         or v_sol_original.datos ? 'lead_id'
         or exists (select 1 from crm.inversion_solicitud_revisiones r where r.solicitud_id = v_sol_original.id)
         or exists (select 1 from crm.inversion_solicitud_correcciones r where r.solicitud_id = v_sol_original.id)
         or exists (select 1 from crm.inversion_solicitud_origenes r where r.solicitud_id = v_sol_original.id) then
        raise exception 'Contrato %: su solicitud existente no tiene la forma revisada', v_c.numero_contrato;
      end if;
      v_foto_original := to_jsonb(v_sol_original);
      delete from crm.inversion_solicitudes where id = v_sol_original.id;
    end if;

    -- 3. Andamio: la solicitud confirmada que exige la misma regla.
    v_sol := gen_random_uuid();
    insert into crm.inversion_solicitudes (id, inversionista_id, empresa_id, responsable_esperado_id,
      hash_payload, datos, estado, inversion_id, resultado, creado_por, confirmado_por, lead_origen_id)
    values (v_sol, v_inv, v_empresa, v_c.analista_cierre_id,
      encode(sha256(convert_to('backfill-2026-09:' || v_c.id::text, 'UTF8')), 'hex'),
      jsonb_build_object('lead_id', v_lead, 'backfill', '2026-09', 'contrato_id', v_c.id),
      'confirmada', v_inversion, jsonb_build_object('backfill', '2026-09', 'contrato_id', v_c.id),
      v_admin, v_admin, v_lead);

    -- 4. La conversión por su puerta real, como la cuenta ADMIN (gerencia), nunca como la analista.
    perform pg_catalog.set_config('request.jwt.claims',
      json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    perform crm.convertir_lead(v_lead, v_c.cliente_id);
    perform pg_catalog.set_config('request.jwt.claims', '', true);

    -- 5. Retirar el andamio. audit_log registra cada paso, pero de las solicitudes no guarda
    --    `datos` ni `auth_contexto`: la original se repone desde la copia en memoria.
    if v_modo = 'transitorio' then
      delete from crm.inversion_solicitudes where id = v_sol;
      if v_sol_apartada then
        insert into crm.inversion_solicitudes select (v_sol_original).*;
        if (select to_jsonb(s) from crm.inversion_solicitudes s where s.id = v_sol_original.id)
           is distinct from v_foto_original then
          raise exception 'Contrato %: la solicitud original no volvió idéntica', v_c.numero_contrato;
        end if;
      end if;
      if v_inv_previa then
        update crm.inversiones set es_primera_conversion = v_primera_previa where id = v_inversion;
      else
        delete from crm.inversion_titulares where inversion_id = v_inversion;
        delete from crm.inversiones where id = v_inversion;
      end if;
    end if;

    -- 6. Comprobaciones del caso.
    select count(*) into v_n from crm.leads l
     where l.id = v_lead and l.etapa = 'convertido' and l.perfil_id = v_c.cliente_id
       and l.inversionista_id = v_inv and l.alta_manual and l.vendedor_id = v_c.analista_cierre_id;
    if v_n <> 1 then raise exception 'Contrato %: el lead no quedó convertido y enlazado', v_c.numero_contrato; end if;
    select count(*) into v_n from crm.lead_asignaciones la
     where la.lead_id = v_lead and la.resultado = 'convertido' and la.analista_id = v_c.analista_cierre_id
       and (la.resultado_en at time zone 'America/Lima')::date between date '2026-09-01' and date '2026-09-30';
    if v_n <> 1 then raise exception 'Contrato %: el cierre no quedó en setiembre para su analista', v_c.numero_contrato; end if;
    v_hechos := v_hechos + 1;
  end loop;
  raise notice 'Backfill A (%): % convertidos, % ya tenían lead', v_modo, v_hechos, v_saltados;
end;
$a$;
