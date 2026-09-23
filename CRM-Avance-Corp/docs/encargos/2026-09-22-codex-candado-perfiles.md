ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude. Do not
delegate to another coding agent. Do not create another review chain.

Eres el revisor secundario. Tu único trabajo es **intentar REFUTAR** el
diagnóstico que va abajo. No lo confirmes por cortesía: búscale el fallo. Si no
lo encuentras, dilo, pero solo después de haberlo intentado en serio.

Trabajas sobre el repo en `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop`
(el CRM vive en `CRM-Avance-Corp/`). Tienes lectura del árbol. **No tienes acceso
a la base de datos de producción**, así que los cuerpos vivos van transcritos al
final de este encargo: son la única fuente para lo que está corriendo hoy.

---

## LA DECISIÓN QUE SE QUIERE TOMAR

Actualizar **una fila** de `private.analista_vigencia_exenciones` (esquema
privado del CRM): su columna `huella` y su columna `razon`, para la puerta
`public.proteger_campos_inmutables()`.

**No se toca ninguna función.** No se toca el portal. No se cambia ningún
permiso. La migración propuesta es
`CRM-Avance-Corp/supabase/migrations/20260922200514_crm_vigencia_redeclarar_candado_perfiles.sql`
— léela entera antes de opinar.

## POR QUÉ SE QUIERE HACER

`private.assert_analista_vigencia()` es un trinquete: declara puertas que
mencionan el rol de analista del Portal, cada una con su RAZÓN escrita y la
HUELLA de su cuerpo. Si el cuerpo cambia, la huella deja de cuadrar y el gate se
pone en ROJO con «la razón ya no se puede dar por buena».

Lleva en rojo desde el 05/09 por `public.proteger_campos_inmutables()`. Un vigía
por cron deja un parte cada mañana; hoy son 16, y bloquean un *stop-the-line*
que exige cero alertas abiertas de cualquier fase.

## EL DIAGNÓSTICO QUE DEBES REFUTAR

**Afirmación 1.** El cambio de cuerpo lo hizo F4
(`supabase/migrations/20260908211349_crm_f4_publicacion_compatible_rentabilidad.sql`,
08/09) y es legítimo: esa migración lleva su propio preflight que aborta si el
cuerpo previo no era el esperado, y el cuerpo nuevo se generó por anclas sobre el
cuerpo vivo capturado (ver `supabase/scripts/f4/generar-migracion.mjs`).

**Afirmación 2.** El cambio es UNA excepción de UNA sola columna:

    antes:  NEW.asesor_perfil_id := OLD.asesor_perfil_id;               (incondicional)
    ahora:  IF NOT v_f4_alinea THEN NEW.asesor_perfil_id := OLD.asesor_perfil_id; END IF;

Todo lo demás del candado queda igual: `activo`, `rol`, `asesor_id`, `cargo`,
`debe_cambiar_password`, la rama de `contratos`, y la llamada a
`public.es_analista()` en su posición prohibitiva.

**Afirmación 3 — LA IMPORTANTE, Y LA QUE MÁS QUIERO QUE ATAQUES.** La propiedad
de seguridad que la razón declarada prometía **se sostiene**: un analista sigue
sin poder «blanquear el asesor de su cliente» ni apuntarlo a un tercero. El
razonamiento es que `v_f4_alinea` solo puede ser cierto si
`private.f4_alineacion_perfil_permitida()` devuelve true, y esa función exige a
la vez:

  - `r.transaccion = pg_current_xact_id()` — la revisión que autoriza el cambio
    tiene que haberse escrito en ESA MISMA transacción;
  - `r.revisado_por = auth.uid()` — la hizo el propio usuario en sesión;
  - `s.estado = 'preparada'`;
  - `s.responsable_esperado_id = p_responsable` **y**
    `i.responsable_relacion_id = p_responsable` — el asesor nuevo tiene que
    coincidir con el que la solicitud ya esperaba Y con el que ya lleva la
    relación del inversionista;
  - `i.estado = 'activo'` y `not i.no_contactar`;
  - que el perfil pertenezca a ese inversionista (o case con un claim verificado).

Es decir: solo puede **alinear** al asesor que ya correspondía.

**Afirmación 4.** No hubo reapertura de permisos. La ACL ya era la de por
defecto antes de F4, y da igual: es una función `returns trigger`, y a una
función de trigger no se la puede llamar directamente.

**Afirmación 5.** Un cabo suelto que ya se miró:
`private.inversiones_escritura_bajo_candado()` se reescribió el 13/09
(`20260913215240_crm_f8_piloto_controlado.sql`) y ganó una segunda vía (el
piloto F8). Medido hoy: **el piloto está apagado**. Y aunque se encendiera, ese
candado solo decide *si se puede escribir inversiones*; lo que impide mover el
asesor a un tercero es la Afirmación 3, que no cambió.

## POR DÓNDE ATACAR, EN ORDEN DE INTERÉS

1. **¿Existe ALGÚN camino** por el que un analista (o cualquiera que no sea
   admin) consiga que `v_f4_alinea` sea cierto con un `p_responsable` que no le
   corresponde? Piensa en: ejecutar `crm.revisar_solicitud_inversion_fn` con
   datos que él mismo controla; crear la solicitud y la revisión en la misma
   transacción; que `responsable_relacion_id` sea modificable por él antes;
   reutilizar un claim. **Ese es el fallo caro. Búscalo ahí.**
2. `current_user='postgres'` se cumple dentro de CUALQUIER función
   `SECURITY DEFINER` propiedad de postgres. ¿Hay algún otro definer que escriba
   `public.perfiles` y que, con el GUC puesto por otra vía, active la excepción?
   ¿Y puede el GUC quedar puesto fuera de la transacción prevista?
3. ¿Hay alguna migración POSTERIOR al 08/09 que vuelva a tocar
   `proteger_campos_inmutables`, `f4_alineacion_perfil_permitida` o
   `revisar_solicitud_inversion_fn`, y que el diagnóstico no haya visto?
4. La razón nueva que se propone escribir (está en la migración, en el `update`):
   ¿describe con honestidad lo que la función hace hoy, o promete de más?
5. ¿Re-declarar esta huella tiene algún efecto colateral sobre el trinquete que
   no se haya considerado? (Ojo: el censo sella el cuerpo **sin comentarios**;
   la migración calcula la huella en la base con esa misma normalización.)

## CONTEXTO QUE NO DEBES IGNORAR

- Objetos de `public` = **portal en producción**. Cualquier duda ahí es LEVEL 3.
- Regla de la casa: «recrear una función en `public` la REABRE» (los default
  privileges le devuelven EXECUTE). Comprueba si aplica aquí o no.
- **NO HAY HALLAZGO SIN EVIDENCIA**: cada afirmación con archivo:línea y cita
  literal. Distingue hecho de hipótesis, y dilo cuando sea hipótesis.
- Ya hubo un error en este mismo diagnóstico, corregido: se comparó
  `md5(prosrc)` **crudo** contra la huella declarada y «aparecieron» cuatro
  puertas cambiadas; el censo normaliza **sin comentarios** y solo había UNA.
  Si ves más errores de ese tipo, dilos.

## FORMATO DE SALIDA

VERDICT (REFUTADO / NO REFUTADO / REFUTADO EN PARTE) · SUMMARY · FINDINGS P0–P3
(cada uno con archivo:línea y cita) · RIESGOS Y TEST GAPS · NEXT ACTIONS ·
CONFIDENCE. Di explícitamente qué NO pudiste verificar.

---

# ANEXO — CUERPOS VIVOS EN PRODUCCIÓN (medidos el 22/09/2026)

Esta es la única fuente de lo que está corriendo. El árbol puede diferir.

```sql
--- [1] EL CANDADO, cuerpo VIVO en produccion ---
CREATE OR REPLACE FUNCTION public.proteger_campos_inmutables()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_f4_alinea boolean := false;
BEGIN
  -- Excepción de una única columna desde la revisión F4 del servidor. Las
  -- escrituras directas mantienen todas las congelaciones originales.
  IF TG_TABLE_NAME='perfiles' AND current_user='postgres'
     AND nullif(current_setting('crm.f4_revision_solicitud',true),'') IS NOT NULL THEN
    v_f4_alinea:=private.f4_alineacion_perfil_permitida(OLD.id,NEW.asesor_perfil_id);
  END IF;
  NEW.id         := OLD.id;
  NEW.creado_en  := OLD.creado_en;
  NEW.creado_por := OLD.creado_por;

  -- Campos privilegiados / de asignacion: se congelan para el usuario que edita su PROPIA
  -- fila (cliente) y TAMBIEN para un ANALISTA que edita la fila de un cliente. Antes solo se
  -- congelaban en la auto-edicion (NEW.id=auth.uid()), por eso un analista podia togglear
  -- activo / debe_cambiar_password / blanquear asesor_perfil_id de su cliente via UPDATE forjado.
  -- admin/superadmin quedan EXCLUIDOS (siguen reasignando/activando). service_role
  -- (auth.uid() IS NULL, no es_analista) NO se ve afectado -> las edges de alta/baja siguen igual.
  IF TG_TABLE_NAME = 'perfiles'
     AND NOT public.es_admin()
     AND ( NEW.id = auth.uid() OR public.es_analista() ) THEN
    NEW.activo           := OLD.activo;
    NEW.rol              := OLD.rol;
    NEW.asesor_id        := OLD.asesor_id;
    IF NOT v_f4_alinea THEN NEW.asesor_perfil_id := OLD.asesor_perfil_id; END IF;
    NEW.cargo            := OLD.cargo;
    -- El flag de cambio de clave solo lo baja el PROPIO usuario (primer login);
    -- un analista editando a un cliente NO puede tocarlo.
    IF NEW.id <> auth.uid() THEN
      NEW.debe_cambiar_password := OLD.debe_cambiar_password;
    END IF;
  END IF;

  -- Asiento «Operaciones» (2026-08-21): edita al cliente y lo activa o desactiva,
  -- pero NO lo mueve de analista. El `rol` se congela ademas por si acaso: la
  -- politica ya lo acota a 'cliente', esto es la segunda linea de defensa.
  IF TG_TABLE_NAME = 'perfiles'
     AND NOT public.es_admin()
     AND public.es_operaciones()
     AND NEW.id <> auth.uid() THEN
    IF (NEW.asesor_perfil_id IS DISTINCT FROM OLD.asesor_perfil_id AND NOT v_f4_alinea)
       OR NEW.asesor_id IS DISTINCT FROM OLD.asesor_id THEN
      RAISE EXCEPTION 'El asiento Operaciones no puede reasignar el asesor de un cliente'
        USING ERRCODE = '42501';
    END IF;
    NEW.rol := OLD.rol;
  END IF;

  -- Ciclo de vida de contratos (2026-07-13): una vez cerrado un ciclo, el
  -- enlace de renovacion y los sellos de cierre quedan congelados para
  -- cualquier no-superadmin (correcciones = superadmin).
  IF TG_TABLE_NAME = 'contratos' AND NOT public.es_superadmin() THEN
    IF OLD.renovado_a_id IS NOT NULL THEN NEW.renovado_a_id := OLD.renovado_a_id; END IF;
    IF OLD.cerrado_en    IS NOT NULL THEN NEW.cerrado_en    := OLD.cerrado_en;    END IF;
    IF OLD.cerrado_por   IS NOT NULL THEN NEW.cerrado_por   := OLD.cerrado_por;   END IF;
  END IF;

  RETURN NEW;
END; $function$


--- [2] LA CONTENCION de la excepcion, cuerpo VIVO ---
CREATE OR REPLACE FUNCTION private.f4_alineacion_perfil_permitida(p_perfil uuid, p_responsable uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select exists(
    select 1 from crm.inversion_solicitudes s
    join crm.inversionistas i on i.id=private.inversionista_canonica(s.inversionista_id)
    join crm.inversion_solicitud_revisiones r on r.solicitud_id=s.id
    where s.id=case when current_setting('crm.f4_revision_solicitud',true)
      ~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
      then current_setting('crm.f4_revision_solicitud',true)::uuid else null end
      and s.estado='preparada' and s.responsable_esperado_id=p_responsable
      and i.estado='activo' and not i.no_contactar and i.responsable_relacion_id=p_responsable
      and r.revisado_por=(select auth.uid()) and r.transaccion=pg_current_xact_id()
      and r.responsable_nuevo_id=p_responsable
      and (i.perfil_id=p_perfil or (i.perfil_id is null and exists(
        select 1 from crm.multiempresa_idempotencia m join auth.users u
          on u.id=(m.resultado->>'auth_user_id')::uuid
        where m.clave='auth_persona:'||i.id::text
          and m.resultado->>'claim_id'=s.auth_claim_id::text
          and m.resultado->>'estado' in ('auth_creado','perfil_creado')
          and u.id=p_perfil and u.raw_app_meta_data->>'claim_id'=s.auth_claim_id::text
      )))
  );
$function$


--- [3] El UNICO escritor que enciende la bandera (gates), cuerpo VIVO ---
CREATE OR REPLACE FUNCTION crm.revisar_solicitud_inversion_fn(p_solicitud uuid, p_responsable_revisado uuid, p_revision_esperada integer, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$begin

declare
  v_persona uuid;
  v_origen uuid;
  v_ctx jsonb;
  v_s crm.inversion_solicitudes%rowtype;
  v_revision crm.inversion_solicitud_revisiones%rowtype;
  v_num integer;
  v_motivo text:=btrim(p_motivo);
  v_perfil uuid;
  v_p public.perfiles%rowtype;
  v_saga crm.multiempresa_idempotencia%rowtype;
  v_config text:=current_setting('crm.f4_revision_solicitud',true);
begin
  if p_solicitud is null or p_responsable_revisado is null or p_revision_esperada is null or p_revision_esperada<0 then
    raise exception 'Falta la solicitud, el responsable revisado o su versión' using errcode='22023';
  end if;
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  v_origen:=v_persona;
  v_ctx:=private.inversion_persona_contexto(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=p_solicitud));
  v_persona:=(v_ctx->>'inversionista_id')::uuid;
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or v_s.inversionista_id is distinct from v_origen then
    raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='40001';
  end if;
  if v_s.estado<>'preparada' then
    raise exception 'Solo se revisa el responsable de una solicitud pendiente; las inversiones confirmadas conservan su atribución' using errcode='P0409';
  end if;
  if p_responsable_revisado is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'El responsable actual ya no coincide con el que revisaste' using errcode='40001';
  end if;
  perform private.motivo_sin_documento(v_motivo,
    (select array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id=v_persona));
  select * into v_revision from crm.inversion_solicitud_revisiones r
    where r.solicitud_id=v_s.id order by r.revision desc limit 1;
  v_num:=coalesce(v_revision.revision,0);
  if p_revision_esperada<>v_num then
    if p_revision_esperada=v_num-1 and v_revision.responsable_nuevo_id=p_responsable_revisado
       and v_s.responsable_esperado_id=p_responsable_revisado and v_revision.motivo=v_motivo then
      return private.inversion_solicitud_resultado(v_s.id,v_ctx)||jsonb_build_object('reintento',true);
    end if;
    raise exception 'La revisión cambió; vuelve a cargar la solicitud' using errcode='40001';
  end if;
  if v_s.responsable_esperado_id=p_responsable_revisado then
    return private.inversion_solicitud_resultado(v_s.id,v_ctx)||jsonb_build_object('sin_cambios',true);
  end if;
  v_perfil:=(v_ctx->>'perfil_id')::uuid;
  if v_s.auth_claim_id is not null then
    select * into v_saga from crm.multiempresa_idempotencia m
      where m.clave='auth_persona:'||coalesce(v_s.auth_contexto->>'inversionista_id',v_origen::text)
        and m.resultado->>'claim_id'=v_s.auth_claim_id::text for update;
    if not found then raise exception 'El proceso de acceso requiere conciliación' using errcode='P0409'; end if;
    -- La corrección canónica solo se permite una vez enlazado el acceso. Su
    -- contexto original queda histórico y no impide revisar al nuevo equipo.
    if v_saga.resultado->>'estado'<>'enlazado' and not private.documento_es_de_identidad(
      v_persona,v_s.auth_contexto->>'documento_tipo',v_s.auth_contexto->>'documento') then
      raise exception 'El documento también cambió; revisa primero el acceso pendiente' using errcode='P0409';
    end if;
    if v_saga.resultado->>'auth_user_id' is not null then
      if not exists(select 1 from auth.users u where u.id=(v_saga.resultado->>'auth_user_id')::uuid
        and u.raw_app_meta_data->>'claim_id'=v_s.auth_claim_id::text) then
        raise exception 'El acceso pendiente no tiene la procedencia esperada' using errcode='P0409';
      end if;
      if v_perfil is not null and v_perfil is distinct from (v_saga.resultado->>'auth_user_id')::uuid then
        raise exception 'El perfil y el acceso pertenecen a procesos diferentes' using errcode='P0409';
      end if;
      select id into v_perfil from public.perfiles where id=(v_saga.resultado->>'auth_user_id')::uuid;
      if v_perfil is null and v_saga.resultado->>'estado' in ('perfil_creado','enlazado') then
        raise exception 'El perfil del proceso ya no existe; requiere revisión' using errcode='P0409';
      end if;
    end if;
  end if;
  if v_perfil is not null then
    -- La gestión de tareas puede tener ya una tarea/perfil. No esperar bajo el
    -- candado de persona: el intento se revierte entero y se puede repetir.
    begin
      perform 1 from crm.tareas t where t.perfil_id=v_perfil and t.estado='pendiente'
        order by t.id for update nowait;
      select * into v_p from public.perfiles where id=v_perfil for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando la ficha o sus tareas; vuelve a revisar' using errcode='40001';
    end;
    if not found or v_p.rol<>'cliente' or v_p.activo is not true
       or not private.documento_es_de_identidad(v_persona,v_p.tipo_documento,v_p.dni) then
      raise exception 'El perfil requiere conciliación con esta persona' using errcode='P0409';
    end if;
  end if;

  insert into crm.inversion_solicitud_revisiones(solicitud_id,revision,responsable_anterior_id,
    responsable_nuevo_id,motivo,revisado_por)
  values(v_s.id,v_num+1,v_s.responsable_esperado_id,p_responsable_revisado,v_motivo,(select auth.uid()));
  update crm.inversion_solicitudes set responsable_esperado_id=p_responsable_revisado,
    actualizado_en=statement_timestamp() where id=v_s.id;
  if v_perfil is not null and v_p.asesor_perfil_id is distinct from p_responsable_revisado then
    perform set_config('crm.f4_revision_solicitud',v_s.id::text,true);
    begin
      update public.perfiles set asesor_perfil_id=p_responsable_revisado where id=v_perfil;
      if (select asesor_perfil_id from public.perfiles where id=v_perfil) is distinct from p_responsable_revisado then
        raise exception 'El perfil no pudo alinearse con su responsable actual' using errcode='P0409';
      end if;
    exception when others then
      perform set_config('crm.f4_revision_solicitud',coalesce(v_config,''),true);
      raise;
    end;
    perform set_config('crm.f4_revision_solicitud',coalesce(v_config,''),true);
  end if;
  -- No cambia datos/hash/auth_contexto ni token/versión/lease de la saga.
  return private.inversion_solicitud_resultado(v_s.id,v_ctx)||jsonb_build_object('reintento',false);
end;

exception when serialization_failure then
  if not exists(select 1 from crm.inversion_solicitud_origenes where solicitud_id=p_solicitud) then raise; end if;
  raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
end;
$function$


--- [4] Los dos candados de ese escritor, cuerpos VIVOS ---
CREATE OR REPLACE FUNCTION private.puede_gestionar_contratos_crm()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    private.rol_crm((select auth.uid())) in ('vendedor','supervisor','gerencia'),
    false
  );
$function$


CREATE OR REPLACE FUNCTION private.inversiones_escritura_bajo_candado()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.resolver_en_puertas_bajo_candado() then return false; end if;
  perform pg_advisory_xact_lock_shared(hashtext('crm_flag_inversiones_escritura'));
  if coalesce((select activo from crm.multiempresa_flags
      where nombre='inversiones_escritura'),false) then
    return true;
  end if;
  return private.piloto_f8_control_activo();
end;
$function$


--- [5] MEDIDO HOY 22/09 en produccion ---
ACL del candado: -, anon, authenticated, postgres, service_role
definer: false · devuelve: trigger
piloto F8 activo: false
flag inversiones_escritura: true
```
