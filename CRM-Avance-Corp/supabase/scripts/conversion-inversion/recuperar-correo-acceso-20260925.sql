-- Recuperación puntual del acceso Avance reclamado antes de crear Auth.
-- Mostrar y obtener autorización antes de ejecutar. No es una migración.
-- Sólo cambia el correo de alta por el correo ya guardado en el lead indicado.
-- Si alguna precondición falla, la transacción completa se revierte.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '20s';

do $recuperar$
declare
  v_lead crm.leads%rowtype;
  v_s crm.inversion_solicitudes%rowtype;
  v_saga crm.multiempresa_idempotencia%rowtype;
  v_portal_anterior jsonb;
  v_portal_nuevo jsonb;
  v_datos_nuevos jsonb;
  v_correo_nuevo text;
  v_persona uuid;
  v_hash_anterior text;
  v_hash_nuevo text;
  -- La tabla exige un perfil como actor. Se registra el creador de la solicitud
  -- como solicitante comercial; el ejecutor técnico queda identificado en el
  -- acta de operación, no se finge una sesión autenticada en el SQL Editor.
  v_motivo constant text := 'Corrección comercial del correo de acceso aplicada por operación autorizada antes de crear Auth';
  v_filas integer;
begin
  select * into strict v_lead from crm.leads
    where id = '324b7b7c-fe20-463b-829e-a9194ee2c83e'::uuid for share nowait;
  select * into strict v_s from crm.inversion_solicitudes
    where id = '3b755bb8-8acd-402a-ac77-2ea7669d09cb'::uuid
      and lead_origen_id = v_lead.id for update nowait;
  v_persona := coalesce((v_s.auth_contexto->>'inversionista_id')::uuid, v_s.inversionista_id);
  select * into strict v_saga from crm.multiempresa_idempotencia
    where clave = 'auth_persona:' || v_persona::text for update nowait;

  if v_s.estado <> 'preparada' or v_s.revision_datos <> 0
     or v_s.auth_claim_id is null
     or v_saga.resultado->>'claim_id' is distinct from v_s.auth_claim_id::text
     or v_saga.resultado->>'estado' is distinct from 'reclamado'
     or v_saga.resultado->>'auth_user_id' is not null
     or v_saga.resultado->>'perfil_id' is not null
     or (v_saga.resultado->>'lease_hasta')::timestamptz >= now()
     or (v_saga.resultado->>'actualizado_en')::timestamptz >= now() - interval '10 minutes'
     or v_s.auth_contexto->>'responsable_id' is null then
    raise exception 'La solicitud o la reserva cambiaron; detener la recuperación';
  end if;

  v_correo_nuevo := lower(btrim(v_lead.correo));
  v_portal_anterior := private.inversion_datos_portal(v_s.datos->'alta_portal');
  v_portal_nuevo := private.inversion_datos_portal(
    jsonb_set(v_s.datos->'alta_portal', '{correo}', to_jsonb(v_correo_nuevo), false));
  if v_portal_anterior->>'correo' is not distinct from v_portal_nuevo->>'correo' then
    raise exception 'El correo del lead ya coincide con el acceso';
  end if;
  if exists (select 1 from auth.users u
               where u.raw_app_meta_data->>'claim_id' = v_s.auth_claim_id::text
                  or lower(u.email) = v_correo_nuevo)
     or exists (select 1 from auth.identities i
               where lower(i.identity_data->>'email') = v_correo_nuevo)
     or exists (select 1 from public.perfiles p
               where lower(p.correo) = v_correo_nuevo) then
    raise exception 'Ya existe un acceso para la reserva o el correo nuevo';
  end if;

  v_hash_anterior := private.idem_hash(jsonb_build_object(
    'v', 1, 'inv', v_persona, 'correo', v_portal_anterior->>'correo',
    'nombre', v_portal_anterior->>'nombre_completo',
    'apellidos', coalesce(v_portal_anterior->>'apellidos', ''),
    'nombres', coalesce(v_portal_anterior->>'nombres', ''),
    'telefono', coalesce(v_portal_anterior->>'telefono', ''),
    'domicilio', v_portal_anterior->'domicilio',
    'bancarios', 'null'::jsonb, 'asesor', v_s.auth_contexto->>'responsable_id'));
  v_hash_nuevo := private.idem_hash(jsonb_build_object(
    'v', 1, 'inv', v_persona, 'correo', v_portal_nuevo->>'correo',
    'nombre', v_portal_nuevo->>'nombre_completo',
    'apellidos', coalesce(v_portal_nuevo->>'apellidos', ''),
    'nombres', coalesce(v_portal_nuevo->>'nombres', ''),
    'telefono', coalesce(v_portal_nuevo->>'telefono', ''),
    'domicilio', v_portal_nuevo->'domicilio',
    'bancarios', 'null'::jsonb, 'asesor', v_s.auth_contexto->>'responsable_id'));
  if v_saga.hash_payload is distinct from v_hash_anterior then
    raise exception 'La huella de la reserva no corresponde a los datos anteriores';
  end if;

  v_datos_nuevos := jsonb_set(v_s.datos, '{alta_portal,correo}',
    to_jsonb(v_correo_nuevo), false);
  insert into crm.inversion_solicitud_correcciones
    (id, solicitud_id, revision_anterior, revision, hash_peticion,
     hash_anterior, hash_nuevo, datos_anteriores, datos_nuevos, motivo, corregido_por)
  values
    (gen_random_uuid(), v_s.id, v_s.revision_datos, v_s.revision_datos + 1,
     private.idem_hash(jsonb_build_object('solicitud', v_s.id,
       'revision', v_s.revision_datos, 'datos', v_datos_nuevos, 'motivo', v_motivo)),
     private.idem_hash(v_s.datos), private.idem_hash(v_datos_nuevos),
     v_s.datos, v_datos_nuevos, v_motivo, v_s.creado_por);

  update crm.inversion_solicitudes
     set datos = v_datos_nuevos, revision_datos = revision_datos + 1,
         actualizado_en = statement_timestamp()
   where id = v_s.id and revision_datos = v_s.revision_datos
     and auth_claim_id = v_s.auth_claim_id and estado = 'preparada';
  get diagnostics v_filas = row_count;
  if v_filas <> 1 then raise exception 'La solicitud cambió durante la recuperación'; end if;

  update crm.multiempresa_idempotencia
     set hash_payload = v_hash_nuevo, version = version + 1,
         resultado = jsonb_set(resultado, '{actualizado_en}',
           to_jsonb(statement_timestamp()))
   where clave = v_saga.clave and version = v_saga.version
     and hash_payload = v_hash_anterior
     and resultado->>'claim_id' = v_s.auth_claim_id::text
     and resultado->>'estado' = 'reclamado';
  get diagnostics v_filas = row_count;
  if v_filas <> 1 then raise exception 'La reserva cambió durante la recuperación'; end if;
end;
$recuperar$;

-- Confirmar únicamente si todo lo anterior pasó. El trigger existente audita
-- la solicitud; la tabla de correcciones conserva la versión y el motivo.
commit;
