-- ============================================================================
-- REVERSA de 20260917235656 (Prodelco en dólares).
-- ============================================================================
-- Devuelve Prodelco a SOLO SOLES y restaura los CINCO escritores byte a byte
-- con la definición que tenía producción el 17/09/2026 (leída de producción, no
-- reescrita a mano). No toca datos.
--
-- ⚠️ ANTES DE ESTO, LEE ESTO: casi nunca hace falta.
-- Los escritores preguntan al catálogo, así que para CERRAR la puerta basta:
--
--     update crm.empresas set monedas = array['PEN'] where clave = 'prodelco';
--
-- Eso deja de admitir dólares nuevos en el acto, sin desplegar una línea y sin
-- tocar los cierres en USD que ya existan. Esta reversa completa solo se
-- justifica si hay que volver al código anterior (por ejemplo, porque un
-- escritor nuevo resultó defectuoso por otra causa).
--
-- Y SOLO se puede si NO hay cierres en dólares: el CHECK vuelve a `moneda =
-- 'PEN'` y una fila en USD lo violaría. Si ya hay dólares vivos, este guion se
-- niega: primero hay que decidir qué se hace con ese dinero, que es una
-- decisión de negocio y no de despliegue.
--
-- 🔴 La reversa restaura LOS CINCO, incluida `crm.corregir_solicitud_inversion_fn`.
-- Si se dejara fuera, su cuerpo nuevo se quedaría vivo y la migración YA NO SE
-- PODRÍA REINSTALAR: su preflight exige la huella anterior de esa función.
begin;
set local lock_timeout='10s';
-- Mismo candado y MISMO ORDEN que la migración: fila del catálogo primero,
-- tablas después (los escritores vivos van en ese orden; invertirlo mete
-- interbloqueo con un cierre en vuelo).
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm_prodelco_usd_20260917235656'));
select 1 from crm.empresas where clave in ('prodelco','qorilazo') for no key update;
lock table crm.empresas in share row exclusive mode;
lock table crm.cierres_externos in access exclusive mode;

do $guarda$
declare x record;
begin
  -- No se revierte a ciegas: los cinco escritores tienen que ser los que
  -- publicó ESTA entrega. Si otra sesión los cambió después, paramos.
  for x in select * from (values
    ('crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text,integer,numeric)','f1759833df86b0a7e6f08d21ec2260c4'),
    ('crm.corregir_cierre_externo(uuid,numeric,text,text,text,text,date,text)','93c3c6eb72b37fdf58b537781154ab88'),
    ('private.inversion_validar_datos(uuid,jsonb,jsonb)','7c7f4bb5d77a7834571af850585f505f'),
    ('crm.confirmar_inversion_revisada_fn(uuid,integer)','eb671aa677a9ba63fa995510e4f48192'),
    ('crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)','fe210a25d8a08cfbce923d3ac12ab199')
  ) as esperadas(firma,huella) loop
    if to_regprocedure(x.firma) is null
       or md5(pg_get_functiondef(to_regprocedure(x.firma))) is distinct from x.huella then
      raise exception 'REVERSA: % no es la publicada el 17/09; revisar antes de revertir', x.firma;
    end if;
  end loop;
  -- El estado del que se revierte es el que dejó la migración.
  if (select monedas from crm.empresas where clave='prodelco') is distinct from array['PEN','USD'] then
    raise exception 'REVERSA: Prodelco no está en {PEN,USD}: ya se revirtió o cambió por otra vía';
  end if;
  if (select monedas from crm.empresas where clave='qorilazo') is distinct from array['PEN'] then
    raise exception 'REVERSA: Qorilazo no está en {PEN}; revisar antes de seguir';
  end if;
  -- LA GUARDA QUE IMPORTA: dinero en dólares ya registrado.
  if exists (select 1 from crm.cierres_externos where moneda is distinct from 'PEN') then
    raise exception 'REVERSA: hay % cierre(s) en otra moneda; estrechar el CHECK los dejaria invalidos. Decidir primero que se hace con ese dinero',
      (select count(*) from crm.cierres_externos where moneda is distinct from 'PEN');
  end if;
  -- Y una solicitud F4 en dólares todavía sin confirmar: al volver atrás, su
  -- confirmación moriría («moneda ya no admitida») y la moneda dejaría de ser
  -- inmutable, así que un bundle anterior podría reescribirla en soles.
  if exists (select 1 from crm.inversion_solicitudes
             where estado='preparada' and datos->>'moneda' is distinct from 'PEN') then
    raise exception 'REVERSA: hay % solicitud(es) F4 preparadas en otra moneda; cancelarlas o confirmarlas antes de revertir',
      (select count(*) from crm.inversion_solicitudes
       where estado='preparada' and datos->>'moneda' is distinct from 'PEN');
  end if;
end;
$guarda$;

-- 1. La fila del catálogo: Prodelco vuelve a solo soles.
update crm.empresas set monedas = array['PEN'] where clave = 'prodelco';

-- 2. El CHECK estrecho de siempre.
alter table crm.cierres_externos drop constraint cierres_externos_moneda_check;
alter table crm.cierres_externos add constraint cierres_externos_moneda_check
  check (moneda = 'PEN');

comment on column crm.cierres_externos.moneda is
  'Siempre PEN: en cooperativas solo se invierte en soles (Miguel, 2026-08-12). La columna se conserva porque la lectura y la cuota agrupan por moneda, y porque la meta operativa vive normalizada en nuevo/PEN.';

comment on table crm.empresas is
  'F1 multiempresa: catalogo ampliable de empresas de inversion. Claves estables (avance/qorilazo/prodelco); una cuarta empresa se agrega con una fila, no con codigo. monedas/reglas por empresa reflejan las decisiones de F0 (cooperativas solo PEN, solo Avance crea contrato y Portal). fuente_capital dice de que tabla lee Capital para esta empresa; NO nace una segunda calculadora. Sin grants a la Data API.';

-- 3. Los cinco escritores, tal como estaban el 17/09 antes de la migración.

CREATE OR REPLACE FUNCTION crm.convertir_lead_externo(p_lead_id uuid, p_cooperativa text, p_monto numeric, p_moneda text, p_documento_tipo text, p_documento text, p_nombre text, p_numero_transaccion text, p_referencia text DEFAULT NULL::text, p_vence_en date DEFAULT NULL::date, p_nota text DEFAULT NULL::text, p_plazo_meses integer DEFAULT NULL::integer, p_tasa_anual numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid         uuid := (select auth.uid());
  v_rol         text := private.rol_crm((select auth.uid()));
  v_lead        crm.leads%rowtype;
  v_documento   text := upper(btrim(p_documento));
  v_nombre      text := btrim(p_nombre);
  v_transaccion text := btrim(p_numero_transaccion);
  v_referencia  text := nullif(btrim(p_referencia), '');
  v_reserva     timestamptz;
  v_efectos     timestamptz;
  v_cierre_id   uuid;
  v_vence       date := p_vence_en;
  v_flag        boolean;
  v_escribe_inversion boolean;
  v_inv         uuid;
  v_lead_canon  uuid;
  v_clave       text;
  v_hash        text;
  v_prev        jsonb;
  v_res         jsonb;
begin
  -- La autoridad no se reinterpreta en esta puerta. El helper canónico
  -- resuelve identidad, vigencia y membresía CRM activa, incluido el caso NULL.
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;
  -- F2.b [D-17] (Codex, 3.ª ronda del bloque 4): la bandera se lee con READ COMMITTED y bajo el candado
  -- COMPARTIDO por bandera; el UPDATE de crm.multiempresa_flags toma el EXCLUSIVO en su trigger (D-5).
  -- Así una llamada que entró APAGADA termina apagada aunque espere por una fila, y una que entra después
  -- del encendido lo ve: sin esto, una llamada en vuelo podía escribir con la bandera cambiada a medias.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  v_flag := coalesce((select activo from crm.multiempresa_flags where nombre = 'resolver_en_puertas'), false);
  v_escribe_inversion := private.inversiones_escritura_bajo_candado();

  -- IDEMPOTENCIA (contrato §8.3, Codex #5): misma clave + mismo payload -> mismo
  -- resultado; misma clave con otro payload -> P0409. Se evalúa ANTES de validar
  -- para que un reintento idéntico ni siquiera toque el lead.
  -- (Gateada por la bandera: APAGADA = comportamiento previo exacto.) El hash cubre
  -- TODO lo que se persiste (Codex), con el número de operación en MAYÚSCULAS como
  -- se compara y reclama.
  if v_flag then
    v_clave := 'conversion_coop:' || p_lead_id::text;
    v_hash  := private.idem_hash(pg_catalog.jsonb_build_object(
                 'lead', p_lead_id, 'coop', p_cooperativa, 'monto', p_monto, 'moneda', p_moneda,
                 'tipo', p_documento_tipo, 'doc', v_documento, 'trx', upper(v_transaccion),
                 'nombre', v_nombre, 'ref', v_referencia, 'vence', p_vence_en,
                 'nota', nullif(btrim(coalesce(p_nota,'')), ''))
                 || case when p_plazo_meses is not null or p_tasa_anual is not null then
                   jsonb_build_object('plazo_meses',p_plazo_meses,'tasa_anual',p_tasa_anual)
                   else '{}'::jsonb end);
    v_prev  := private.idem_leer(v_clave, v_hash);
    if v_prev is not null then
      return v_prev || pg_catalog.jsonb_build_object('reintento', true);
    end if;
  end if;

  -- Validaciones de entrada ANTES de tocar el lead: un payload inválido no
  -- debe dejar ni un lock tomado.
  if p_cooperativa is null or p_cooperativa not in ('qorilazo', 'prodelco') then
    raise exception 'Cooperativa invalida: debe ser qorilazo o prodelco'
      using errcode = '22023';
  end if;
  -- El NaN se rechaza EXPLÍCITAMENTE y primero: `NaN <= 0` es false y
  -- `NaN <> round(NaN,2)` también, así que sin esta línea se cuela por las dos
  -- validaciones de abajo y acaba envenenando la suma de la cuota.
  if p_monto is null or p_monto = 'NaN'::numeric or p_monto <= 0 then
    raise exception 'El monto invertido debe ser mayor que cero'
      using errcode = '22023';
  end if;
  if p_monto <> round(p_monto, 2) then
    -- numeric(14,2) redondearía en silencio; con dinero, mejor rechazar.
    raise exception 'El monto admite como maximo 2 decimales'
      using errcode = '22023';
  end if;
  -- En cooperativas solo se invierte en soles. Se valida en vez de forzar: un
  -- bundle viejo que mande USD merece un rechazo claro, no que le cambiemos la
  -- moneda por debajo y le contemos el monto como si fueran soles.
  if p_moneda is distinct from 'PEN' then
    raise exception 'En cooperativas solo se registran inversiones en soles'
      using errcode = '22023';
  end if;
  if p_documento_tipo is null
     or p_documento_tipo not in ('DNI', 'CE', 'PASAPORTE') then
    raise exception 'Tipo de documento invalido: DNI, CE o PASAPORTE'
      using errcode = '22023';
  end if;
  -- Mismas reglas que src/lib/documento.ts y el CHECK de la tabla; el error
  -- aquí habla el idioma del formulario, no el del constraint.
  if (p_documento_tipo = 'DNI'       and v_documento !~ '^[0-9]{8}$')
     or (p_documento_tipo = 'CE'        and v_documento !~ '^[0-9]{9,12}$')
     or (p_documento_tipo = 'PASAPORTE' and v_documento !~ '^[A-Z0-9]{6,12}$') then
    raise exception 'Documento invalido para el tipo %', p_documento_tipo
      using errcode = '22023';
  end if;
  if v_nombre is null or v_nombre = '' then
    raise exception 'El nombre completo es obligatorio'
      using errcode = '22023';
  end if;
  -- El número de operación es OBLIGATORIO (y único por cooperativa, ver el
  -- índice): es lo único que impide cobrar dos veces un mismo cierre real.
  if v_transaccion is null or v_transaccion = '' then
    raise exception 'El numero de operacion del deposito es obligatorio'
      using errcode = '22023';
  end if;
  if length(v_transaccion) > 64 then
    raise exception 'El numero de operacion admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;
  if v_referencia is not null and length(v_referencia) > 64 then
    raise exception 'El numero de certificado admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;
  -- La fecha del cierre es HOY (automática): el vencimiento de una inversión
  -- recién cerrada solo puede ser futuro. En corregir_cierre_externo este
  -- check NO existe a propósito: una corrección tardía de otro campo debe
  -- poder reenviar un vencimiento que ya pasó.
  if p_vence_en is not null and p_vence_en <= (now() at time zone 'America/Lima')::date then
    raise exception 'El vencimiento de la inversion debe ser una fecha futura'
      using errcode = '22023';
  end if;

  if p_plazo_meses is not null or p_tasa_anual is not null then
    v_vence:=private.coopac_validar_condiciones((now() at time zone 'America/Lima')::date,
      p_plazo_meses,p_tasa_anual);
    if p_vence_en is not null and p_vence_en is distinct from v_vence then
      raise exception 'El vencimiento debe corresponder a la fecha de inicio y al plazo' using errcode='22023';
    end if;
  end if;

  -- ── PUERTA DE IDENTIDAD (solo con la bandera encendida) ──────────────────
  -- Resolver ANTES del lock del lead (orden identidad->lead, comparte orden con
  -- la fusión y mata el deadlock). El documento ya se validó arriba. Con bandera
  -- APAGADA nada de esto corre (comportamiento idéntico a hoy).
  if v_flag then
    v_inv := private.inversionista_resolver(p_documento_tipo, v_documento, true, 'conversion');
    perform 1 from crm.inversionistas where id = v_inv for update;
    -- F2.b (b4): la PERSONA (no solo este lead) puede tener una conversión Avance en curso en OTRO
    -- lead: reserva viva o sellada con su inversionista_id. Lectura bajo el lock de la identidad
    -- (el sellado también lo toma desde b4): orden identidad -> lead -> reserva, sin cambios.
    if exists (select 1 from crm.conversion_reservas r
                where r.inversionista_id = v_inv and r.lead_id <> p_lead_id
                  and (r.efectos_iniciados_en is not null or r.expira_en > now())) then
      raise exception using
        errcode = 'P0409',
        message = 'Esta persona tiene una conversion a cliente de Avance en curso en otro lead',
        hint    = 'Quien la empezo tiene que terminarla o dejar que caduque.';
    end if;
  end if;

  -- Ámbito y lock: copiados VERBATIM de crm.convertir_lead para que los dos
  -- caminos de conversión signifiquen lo mismo.
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

  -- Reintento tras éxito: el lead ya se convirtió y su cierre lleva ESTE número de
  -- operación -> mismo resultado, sin efectos (idempotente).
  if v_flag and v_lead.etapa = 'convertido' then
    -- Revalidar TRAS el lock (Codex): la clave guardada manda; payload distinto → P0409.
    v_prev := private.idem_leer(v_clave, v_hash);
    if v_prev is not null then
      return v_prev || pg_catalog.jsonb_build_object('reintento', true);
    end if;
    -- Sin clave guardada (p.ej. conversión previa a este lote): mismo número de
    -- operación en su cierre = mismo hecho.
    select ce.id into v_cierre_id
    from crm.cierres_externos ce
    where ce.lead_id = p_lead_id and ce.es_cierre_inicial
      and upper(ce.numero_transaccion) = upper(v_transaccion)
      and ce.plazo_meses is not distinct from p_plazo_meses
      and ce.tasa_anual is not distinct from p_tasa_anual
    limit 1;
    if v_cierre_id is not null then
      v_res := pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'cierre_id', v_cierre_id,
                                             'cooperativa', p_cooperativa);
      perform private.idem_guardar(v_clave, 'conversion_coop', v_hash, v_res, v_uid);
      return v_res || pg_catalog.jsonb_build_object('reintento', true);
    end if;
  end if;
  if v_lead.etapa in ('convertido', 'descartado') then
    raise exception 'El lead ya esta cerrado';
  end if;
  if v_lead.vendedor_id is null then
    raise exception 'Asigna el lead a un analista antes de convertirlo'
      using errcode = '22023';
  end if;

  -- Un solo lead total (invariante #6, decisión Miguel 03/09): un 2.º lead de la
  -- misma persona no se convierte aquí; la nueva inversión sobre el cliente
  -- existente es F5. Mensaje de negocio en vez del choque con leads_inversionista_uidx.
  if v_flag and v_inv is not null then
    select l2.id into v_lead_canon from crm.leads l2
    where l2.inversionista_id = v_inv and l2.id <> p_lead_id limit 1;
    if v_lead_canon is not null then
      raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
        using errcode = 'P0409';
    end if;
  end if;
  -- F2.b (b5) [Codex B2]: «un solo lead» cuenta también el PUENTE (históricos del backfill sin enlace vivo).
  if v_flag and v_inv is not null
     and exists (select 1 from private.leads_de_identidades(array[v_inv]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex #1): también los leads SUELTOS vivos que llevan un documento vigente de la persona (nacieron antes
  -- de que existiera la persona) cuentan en «un solo lead».
  if v_flag and v_inv is not null
     and exists (select 1 from private.leads_de_personas(array[v_inv]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
      using errcode = 'P0409';
  end if;
  -- F2.b (b5) [E3-11]: la persona YA reconocida de este lead manda; el documento del cierre
  -- no se lo lleva a otra identidad (eso es corrección o fusión de Gerencia).
  if v_flag and v_lead.inversionista_id is not null and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona de este lead no es la del documento del cierre: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex D-10 #2): el PUENTE del propio lead también manda (por la canónica), como en la reserva por persona (D-10).
  if v_flag and v_inv is not null
     and exists (select 1 from crm.inversionista_leads il
                  where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) is distinct from v_inv) then
    raise exception 'La persona de este lead (según su puente) no es la del documento del cierre: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;

  -- LA CARRERA (ver sección 1-bis): si hay una conversión Avance en vuelo, sus
  -- efectos irreversibles —usuario de Auth, perfil, correo de bienvenida— ya
  -- pueden haber ocurrido, y cerrar aquí dejaría a un inversionista de
  -- cooperativa con cuenta de portal. Se rechaza SIN MIRAR QUIÉN reservó: lo que
  -- importa no es el actor, es que el correo quizá ya salió.
  -- Dos casos, y solo uno se cura esperando.
  --
  -- ⚠️ `for update` y NO una lectura suelta. En READ COMMITTED un SELECT normal
  -- ve la última versión CONFIRMADA: si la edge está sellando la reserva en ese
  -- mismo instante (su UPDATE aún sin confirmar), este cierre vería la versión
  -- vieja —caducada y sin efectos—, entraría, y acto seguido la edge crearía la
  -- cuenta de portal. Ventana de milisegundos, pero es EXACTAMENTE el fallo que
  -- toda esta tabla existe para impedir. Con el lock, este cierre espera al
  -- sellado y decide DESPUÉS, sobre el estado real.
  --
  -- El orden de bloqueo es el mismo en los dos caminos —primero `crm.leads`
  -- (arriba), luego `crm.conversion_reservas`— para que no puedan abrazarse.
  -- Sin `and (expira_en > now() …)` en el WHERE: primero se toma la fila, y la
  -- vigencia se juzga con lo que haya tras esperar.
  select r.expira_en, r.efectos_iniciados_en into v_reserva, v_efectos
  from crm.conversion_reservas r
  where r.lead_id = p_lead_id
  for update;
  if v_efectos is null and coalesce(v_reserva, '-infinity'::timestamptz) <= now() then
    -- Caducada y sin efectos: no manda.
    v_reserva := null;
  end if;
  if v_efectos is not null then
    -- Ya existe una cuenta de portal a nombre de esta persona. Este cierre NO
    -- puede entrar nunca: sería justo el inversionista de cooperativa con
    -- portal que toda esta función existe para impedir.
    raise exception using
      errcode = 'P0409',
      message = 'Esta persona ya tiene una cuenta de cliente de Avance en proceso',
      hint    = 'Se le creo (o se le esta creando) su acceso al portal. Termina esa conversion; este lead ya no se puede cerrar en una cooperativa.';
  end if;
  if v_reserva is not null then
    raise exception using
      errcode = 'P0409',
      message = 'Hay una conversion a cliente de Avance en curso para este lead',
      hint    = pg_catalog.format(
        'Vuelve a intentarlo despues de las %s (hora de Lima). Si esa conversion no debia hacerse, avisa antes de cerrar en la cooperativa.',
        pg_catalog.to_char(v_reserva at time zone 'America/Lima', 'HH24:MI'));
  end if;

  -- La FOTO primero: así, cuando el UPDATE de etapa dispare el BEFORE trigger,
  -- la P4 relajada ya encuentra el cierre y deja pasar el convertido sin
  -- perfil. El UNIQUE(lead_id) es el cinturón contra un doble cierre que el
  -- gate de etapa no haya visto (el FOR UPDATE ya serializa el camino normal).
  begin
    insert into crm.cierres_externos (
      lead_id, cooperativa, monto, moneda,
      documento_tipo, documento, nombre_completo,
      numero_transaccion, referencia_externa, vence_en, nota,
      vendedor_id, creado_por, inversionista_id, plazo_meses, tasa_anual
    ) values (
      p_lead_id, p_cooperativa, p_monto, p_moneda,
      p_documento_tipo, v_documento, v_nombre,
      v_transaccion, v_referencia, v_vence, nullif(btrim(p_nota), ''),
      v_lead.vendedor_id, v_uid, v_inv, p_plazo_meses, p_tasa_anual
    )
    returning id into v_cierre_id;

    -- La reclamación es PARTE del mismo insert: si el número ya se declaró
    -- alguna vez —aunque su cierre se haya corregido después y el índice vivo
    -- lo haya soltado— este insert choca y el cierre entero se deshace.
    insert into crm.depositos_reclamados (numero_norm, cierre_id, reclamado_por)
    values (upper(v_transaccion), v_cierre_id, v_uid);
  exception when unique_violation then
    -- El índice habla en idioma de constraint; el vendedor merece saber QUÉ
    -- pasó. El UNIQUE del lead ya lo cazó el gate de etapa más arriba, así que
    -- aquí el choque es el del depósito (vivo o histórico).
    raise exception using
      errcode = 'P0409',
      message = 'Ese numero de operacion ya esta registrado',
      hint    = 'Ese deposito ya se declaro antes, aqui o en la otra cooperativa. Si lo escribiste mal, corrigelo; si es otro cierre, usa su propio numero de operacion.';
  end;

  -- El cierre del lead, IDÉNTICO al de convertir_lead salvo que perfil_id
  -- queda NULL (no hay portal). El AFTER trg_leads_asignaciones cierra el
  -- episodio con resultado='convertido' — por eso la conversión mensual cuenta
  -- este cierre sin tocar su fórmula.
  -- Inversión (colgada de la identidad) + titular principal (solo bandera).
  -- F2.b (b4) [Codex v2 #17]: los HECHOS de inversión son de F4: solo con `inversiones_escritura`.
  if v_flag and v_inv is not null and v_escribe_inversion then
    perform private.inversion_vincular_fuente(v_inv,null,v_cierre_id,v_uid,true);
  end if;

  -- El cierre del lead. inversionista_id viaja en el MISMO UPDATE bajo la válvula.
  perform set_config('crm.op_privilegiada', 'on', true);
  update crm.leads
     set etapa = 'convertido',
         convertido_en = now(),
         inversionista_id = coalesce(v_inv, inversionista_id)
   where id = p_lead_id;
  perform set_config('crm.op_privilegiada', 'off', true);

  -- Reconocimiento de identidad (reemplaza al trigger 200000 para coop).
  if v_flag and v_inv is not null then
    insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
    select v_inv, p_lead_id, 'canonico'
    where not exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead_id);
    -- Responsable de relación = vendedor del cierre (si activo y sin tramo abierto).
    if v_lead.vendedor_id is not null
       and exists (select 1 from crm.equipo e where e.perfil_id = v_lead.vendedor_id and e.activo)
       and not exists (select 1 from crm.inversionista_responsables ir where ir.inversionista_id = v_inv and ir.hasta is null) then
      insert into crm.inversionista_responsables (inversionista_id, responsable_id, motivo)
      values (v_inv, v_lead.vendedor_id, 'conversion');
      update crm.inversionistas set responsable_relacion_id = v_lead.vendedor_id
        where id = v_inv and responsable_relacion_id is null;
    end if;
    -- no_contactar del lead se centraliza en la persona.
    if v_lead.no_contactar then
      update crm.inversionistas set no_contactar = true, no_contactar_en = coalesce(no_contactar_en, pg_catalog.now())
      where id = v_inv and no_contactar = false;
    end if;
  end if;

  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    p_lead_id,
    'conversion',
    'Convertido en ' || case p_cooperativa
      when 'qorilazo' then 'COOPAC Qorilazo'
      else 'COOPAC Prodelco'
    end,
    jsonb_build_object(
      'cooperativa', p_cooperativa,
      'monto', p_monto,
      'moneda', p_moneda,
      'cierre_externo_id', v_cierre_id
    ),
    v_uid
  );

  v_res := jsonb_build_object(
    'ok', true,
    'lead_id', p_lead_id,
    'cierre_id', v_cierre_id,
    'cooperativa', p_cooperativa
  );
  if v_flag then
    perform private.idem_guardar(v_clave, 'conversion_coop', v_hash, v_res, v_uid);
  end if;
  return v_res;
end;
$function$;

CREATE OR REPLACE FUNCTION crm.corregir_cierre_externo(p_cierre_id uuid, p_monto numeric, p_moneda text, p_cooperativa text, p_numero_transaccion text, p_referencia text, p_vence_en date, p_nota text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid         uuid := (select auth.uid());
  v_rol         text := private.rol_crm((select auth.uid()));
  v_cierre      crm.cierres_externos%rowtype;
  v_transaccion text := btrim(p_numero_transaccion);
  v_referencia  text := nullif(btrim(p_referencia), '');
begin
  if v_uid is null or v_rol is distinct from 'gerencia' then
    raise exception 'Solo gerencia corrige cierres externos'
      using errcode = '42501';
  end if;

  if p_cooperativa is null or p_cooperativa not in ('qorilazo', 'prodelco') then
    raise exception 'Cooperativa invalida: debe ser qorilazo o prodelco'
      using errcode = '22023';
  end if;
  -- El NaN se rechaza EXPLÍCITAMENTE y primero: `NaN <= 0` es false y
  -- `NaN <> round(NaN,2)` también, así que sin esta línea se cuela por las dos
  -- validaciones de abajo y acaba envenenando la suma de la cuota.
  if p_monto is null or p_monto = 'NaN'::numeric or p_monto <= 0 then
    raise exception 'El monto invertido debe ser mayor que cero'
      using errcode = '22023';
  end if;
  if p_monto <> round(p_monto, 2) then
    raise exception 'El monto admite como maximo 2 decimales'
      using errcode = '22023';
  end if;
  if p_moneda is distinct from 'PEN' then
    raise exception 'En cooperativas solo se registran inversiones en soles'
      using errcode = '22023';
  end if;
  if v_transaccion is null or v_transaccion = '' then
    raise exception 'El numero de operacion del deposito es obligatorio'
      using errcode = '22023';
  end if;
  if length(v_transaccion) > 64 then
    raise exception 'El numero de operacion admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;
  if v_referencia is not null and length(v_referencia) > 64 then
    raise exception 'El numero de certificado admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;

  select * into v_cierre
  from crm.cierres_externos
  where id = p_cierre_id
  for update;
  if not found then
    raise exception 'Cierre externo no encontrado';
  end if;
  -- Un cierre anulado no se retoca: corregirlo daría a entender que vuelve a
  -- contar, y no vuelve. Si el monto anulado estaba mal, da igual: no paga.
  if v_cierre.anulado_en is not null then
    raise exception using
      errcode = 'P0409',
      message = 'Ese cierre esta anulado: ya no cuenta y no se corrige',
      detail  = pg_catalog.format('cierre %s, anulado el %s', v_cierre.id, v_cierre.anulado_en);
  end if;

  perform set_config('crm.op_privilegiada', 'on', true);
  begin
    update crm.cierres_externos
       set monto = p_monto,
           moneda = p_moneda,
           cooperativa = p_cooperativa,
           numero_transaccion = v_transaccion,
           referencia_externa = v_referencia,
           vence_en = p_vence_en,
           nota = nullif(btrim(p_nota), '')
     where id = p_cierre_id;

    -- Si gerencia cambia el número, el NUEVO se reclama para siempre. El
    -- ANTERIOR no se libera: sigue en la memoria histórica, que es justo lo que
    -- impide que otro lead lo declare y el mismo depósito se cobre dos veces.
    if upper(v_transaccion) is distinct from upper(v_cierre.numero_transaccion) then
      insert into crm.depositos_reclamados (numero_norm, cierre_id, reclamado_por)
      values (upper(v_transaccion), p_cierre_id, v_uid);
    end if;
  exception when unique_violation then
    raise exception using
      errcode = 'P0409',
      message = 'Ese numero de operacion ya esta registrado',
      hint    = 'Ese deposito ya se declaro antes (aunque su cierre se haya corregido despues): no se puede reusar.';
  end;
  perform set_config('crm.op_privilegiada', 'off', true);

  -- Rastro de negocio en la línea de tiempo del lead. Tipo 'nota' porque el
  -- CHECK de actividades no tiene 'correccion' y ampliarlo por esto no paga:
  -- el QUÉ cambió va en metadata (y el audit trigger guarda la fila entera).
  if v_cierre.lead_id is not null and (coalesce(current_setting('crm.gestion_neutral',true),'off')<>'on' or exists(select 1 from crm.leads where id=v_cierre.lead_id and activo)) then
  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    v_cierre.lead_id,
    'nota',
    'Gerencia corrigio el cierre externo',
    jsonb_build_object(
      'accion', 'correccion_cierre_externo',
      'cierre_externo_id', p_cierre_id,
      'antes', jsonb_build_object(
        'monto', v_cierre.monto, 'moneda', v_cierre.moneda,
        'cooperativa', v_cierre.cooperativa,
        'numero_transaccion', v_cierre.numero_transaccion,
        'referencia_externa', v_cierre.referencia_externa,
        'vence_en', v_cierre.vence_en, 'nota', v_cierre.nota),
      'despues', jsonb_build_object(
        'monto', p_monto, 'moneda', p_moneda,
        'cooperativa', p_cooperativa,
        'numero_transaccion', v_transaccion,
        'referencia_externa', v_referencia,
        'vence_en', p_vence_en, 'nota', nullif(btrim(p_nota), ''))
    ),
    v_uid
  );
  end if;

  return jsonb_build_object('ok', true, 'cierre_id', p_cierre_id);
end;
$function$;

CREATE OR REPLACE FUNCTION private.inversion_validar_datos(p_clave uuid, p_datos jsonb, p_contexto jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_persona uuid:=(p_datos->>'inversionista_id')::uuid;
  v_ctx jsonb:=p_contexto;
  v_e crm.empresas%rowtype;
  v_monto numeric; v_fecha date; v_vence date; v_ruta text;
begin
  if p_clave is null or p_datos is null or jsonb_typeof(p_datos)<>'object' then
    raise exception 'Falta la clave o el contenido de la inversión' using errcode='22023';
  end if;
  if exists (select 1 from jsonb_object_keys(p_datos) k where k not in (
    'inversionista_id','empresa','monto','moneda','fecha_comercial','vence_en','numero_transaccion',
    'referencia','evidencia','producto_condicion_id','contrato','cronograma','cuenta','alta_portal','plazo_meses','tasa_anual'
  )) then
    raise exception 'La solicitud contiene campos no admitidos' using errcode='22023';
  end if;
  select * into v_e from crm.empresas where clave=p_datos->>'empresa' and activa for share;
  if not found or v_e.clave not in ('avance','qorilazo','prodelco') then
    raise exception 'Empresa no disponible para invertir' using errcode='22023';
  end if;
  if v_e.fuente_capital='cierres_externos' then
    begin
      v_monto := (p_datos->>'monto')::numeric;
      v_fecha := (p_datos->>'fecha_comercial')::date;
      v_vence := (p_datos->>'vence_en')::date;
    exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'Revisa el monto y las fechas de la inversión' using errcode='22023';
    end;
    if v_monto is null or v_monto in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)
       or v_monto<=0 or v_monto>999999999999.99 or v_monto<>trunc(v_monto,2) then
      raise exception 'El monto debe ser positivo y tener como máximo dos decimales' using errcode='22023';
    end if;
    if p_datos->>'moneda' is distinct from 'PEN' or not ('PEN'=any(v_e.monedas)) then
      raise exception 'Esta cooperativa registra inversiones en soles' using errcode='22023';
    end if;
    if v_fecha is null or not isfinite(v_fecha) or v_fecha>(statement_timestamp() at time zone 'America/Lima')::date
       or v_vence is null or not isfinite(v_vence) or v_vence<=v_fecha then
      raise exception 'La fecha comercial no puede ser futura y el vencimiento debe ser posterior' using errcode='22023';
    end if;
    if p_datos ? 'plazo_meses' or p_datos ? 'tasa_anual' then
      if jsonb_typeof(p_datos->'plazo_meses') is distinct from 'number'
        or jsonb_typeof(p_datos->'tasa_anual') is distinct from 'number'
        or (p_datos->>'plazo_meses')::numeric<>trunc((p_datos->>'plazo_meses')::numeric) then
        raise exception 'Completa el plazo en meses enteros y la rentabilidad anual' using errcode='22023';
      end if;
      if private.coopac_validar_condiciones(v_fecha,(p_datos->>'plazo_meses')::integer,
        (p_datos->>'tasa_anual')::numeric) is distinct from v_vence then
        raise exception 'El vencimiento debe corresponder a la fecha de inicio y al plazo' using errcode='22023';
      end if;
    end if;
    if length(btrim(coalesce(p_datos->>'numero_transaccion',''))) not between 1 and 64
       or length(btrim(coalesce(p_datos->>'referencia',''))) not between 1 and 64 then
      raise exception 'El depósito y la referencia son obligatorios, con un máximo de 64 caracteres' using errcode='22023';
    end if;
    v_ruta := p_datos#>>'{evidencia,ruta}';
    if v_ruta is null or v_ruta !~ ('^'||v_persona::text||'/'||p_clave::text||'/[a-zA-Z0-9_-]+\.(pdf|jpg|jpeg|png)$') then
      raise exception 'El comprobante debe pertenecer a esta persona y solicitud' using errcode='22023';
    end if;
  else
    if jsonb_typeof(p_datos->'contrato') is distinct from 'object'
       or jsonb_typeof(p_datos->'cronograma') is distinct from 'array'
       or jsonb_typeof(p_datos->'cuenta') is distinct from 'object' then
      raise exception 'Avance requiere contrato, cronograma y cuenta de pago' using errcode='22023';
    end if;
    if p_datos#>>'{contrato,moneda}' is null or not (p_datos#>>'{contrato,moneda}'=any(v_e.monedas)) then
      raise exception 'Moneda no admitida por Avance' using errcode='22023';
    end if;
    if p_datos#>>'{contrato,cliente_id}' is not null
       and p_datos#>>'{contrato,cliente_id}' is distinct from v_ctx->>'perfil_id' then
      raise exception 'El contrato debe pertenecer a esta persona' using errcode='P0409';
    end if;
    if v_ctx->>'perfil_id' is null or p_datos ? 'alta_portal' then
      perform private.inversion_datos_portal(p_datos->'alta_portal');
    end if;
    if p_datos#>>'{contrato,analista_cierre_id}' is not null
       and p_datos#>>'{contrato,analista_cierre_id}' is distinct from v_ctx->>'responsable_id' then
      raise exception 'El analista debe corresponder al responsable de la persona al preparar la inversión' using errcode='P0409';
    end if;
  end if;
  return v_e.id;
end;
$function$;

CREATE OR REPLACE FUNCTION crm.confirmar_inversion_revisada_fn(p_solicitud uuid, p_revision_datos_esperada integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$begin

declare
  v_uid uuid := (select auth.uid());
  v_persona uuid;
  v_origen uuid;
  v_ctx jsonb;
  v_s crm.inversion_solicitudes%rowtype;
  v_e crm.empresas%rowtype;
  v_obj storage.objects%rowtype;
  v_cierre uuid;
  v_contrato uuid;
  v_inversion uuid;
  v_fecha date;
  v_imputacion date;
  v_periodo date;
  v_ahora timestamptz := statement_timestamp();
  v_ajuste boolean := false;
  v_fuente jsonb;
  v_payload_contrato jsonb;
  v_condicion uuid;
  v_config_producto text := current_setting('crm.producto_condicion_id',true);
  v_responsable_inicial uuid;
  v_res jsonb;
begin
  if v_uid is null or not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para registrar inversiones' using errcode='42501';
  end if;
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  if not found then raise exception 'Solicitud no encontrada' using errcode='P0002'; end if;
  v_origen := v_persona;
  v_ctx := private.inversion_persona_autorizada(v_persona);
  v_persona := (v_ctx->>'inversionista_id')::uuid;
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or v_s.inversionista_id is distinct from v_origen then
    raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='PT409';
  end if;
  if v_s.estado='confirmada' then
    v_res:=v_s.resultado;
    select contrato_id into v_contrato from crm.inversiones where id=v_s.inversion_id;
    if v_contrato is not null then
      if private.contrato_en_eliminacion(v_contrato) then
        raise exception 'El contrato está en proceso de eliminación; requiere revisión' using errcode='55000';
      end if;
      v_res:=jsonb_set(v_res,'{fuente,pdf}',private.contrato_pdf_estado_base(v_contrato));
    end if;
    return v_res||jsonb_build_object('inversionista_id',v_persona,'reintento',true);
  end if;
  if v_s.estado<>'preparada' then raise exception 'La solicitud está cancelada' using errcode='P0409'; end if;
  if p_revision_datos_esperada is distinct from v_s.revision_datos then
    raise exception 'Los datos cambiaron; revisa la versión vigente antes de confirmar' using errcode='PT409';
  end if;
  v_ctx := private.inversion_persona_contexto(v_persona);
  if v_s.responsable_esperado_id is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'El responsable cambió; revisa esta misma solicitud antes de confirmarla' using errcode='P0409';
  end if;
  select * into v_e from crm.empresas where id=v_s.empresa_id and activa for share;
  if not found then raise exception 'La empresa ya no está disponible para nuevas inversiones' using errcode='P0409'; end if;
  if v_e.fuente_capital='cierres_externos' then
    if v_s.datos->>'moneda' is distinct from 'PEN' or not ('PEN'=any(v_e.monedas)) then
      raise exception 'La moneda ya no está admitida por la cooperativa' using errcode='P0409';
    end if;
    -- Revalida el contenido guardado, también al retomar una solicitud anterior.
    perform private.inversion_validar_datos(v_s.id,v_s.datos,v_ctx);
    select * into v_obj from storage.objects
    where bucket_id='f4-comprobantes' and name=v_s.datos#>>'{evidencia,ruta}' for key share;
    if not found or coalesce((v_obj.metadata->>'size')::bigint,0) not between 1 and 10485760
       or coalesce(v_obj.metadata->>'mimetype','') not in ('application/pdf','image/jpeg','image/png') then
      raise exception 'Sube el comprobante válido antes de confirmar la inversión' using errcode='P0409';
    end if;
    v_fecha := (v_s.datos->>'fecha_comercial')::date;
    v_periodo := date_trunc('month',v_fecha)::date;
    -- Mismo candado que el sello mensual. El sello no puede aparecer entre la
    -- decisión y el alta. Un mes sellado recibe un hecho posterior trazable.
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_periodo-date '2000-01-01')::integer);
    v_ajuste := exists(select 1 from crm.periodos_cerrados where periodo=v_periodo);
    v_imputacion := case when v_ajuste then (v_ahora at time zone 'America/Lima')::date else v_fecha end;
    if v_ajuste then
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
        (date_trunc('month',v_imputacion)::date-date '2000-01-01')::integer);
      if exists(select 1 from crm.periodos_cerrados where periodo=date_trunc('month',v_imputacion)::date) then
        raise exception 'El período de registro también está sellado; corresponde revisión de Gerencia' using errcode='P0409';
      end if;
    end if;
    begin
      insert into crm.cierres_externos(lead_id,cooperativa,monto,moneda,documento_tipo,documento,
        nombre_completo,numero_transaccion,referencia_externa,vence_en,vendedor_id,creado_por,
        inversionista_id,creado_en,es_cierre_inicial,fecha_comercial,fecha_imputacion,comprobante_objeto_id,
        plazo_meses,tasa_anual)
      values((v_ctx->>'lead_id')::uuid,v_e.clave,(v_s.datos->>'monto')::numeric,'PEN',
        v_ctx->>'documento_tipo',v_ctx->>'documento',v_ctx->>'nombre',
        upper(btrim(v_s.datos->>'numero_transaccion')),btrim(v_s.datos->>'referencia'),
        (v_s.datos->>'vence_en')::date,(v_ctx->>'responsable_id')::uuid,v_uid,v_persona,
        v_ahora,false,v_fecha,v_imputacion,v_obj.id,
        (v_s.datos->>'plazo_meses')::integer,(v_s.datos->>'tasa_anual')::numeric) returning id into v_cierre;
      -- La reclamación histórica del depósito es global para ambas cooperativas.
      insert into crm.depositos_reclamados(numero_norm,cierre_id,reclamado_por)
      values(upper(btrim(v_s.datos->>'numero_transaccion')),v_cierre,v_uid);
    exception when unique_violation then
      raise exception 'Ese número de operación del depósito ya está registrado' using errcode='P0409';
    end;
    v_fuente:=jsonb_build_object('cierre_id',v_cierre,'fecha_comercial',v_fecha,
      'fecha_imputacion',v_imputacion,'ajuste_mes_cerrado',v_ajuste,
      'plazo_meses',(v_s.datos->>'plazo_meses')::integer,'tasa_anual',(v_s.datos->>'tasa_anual')::numeric,
      'vence_en',(v_s.datos->>'vence_en')::date);
  elsif v_e.clave='avance' then
    if v_ctx->>'perfil_id' is null then
      raise exception 'Completa el acceso Avance de esta persona y vuelve a confirmar la misma solicitud' using errcode='P0409';
    end if;
    v_payload_contrato := v_s.datos->'contrato';
    select r.responsable_anterior_id into v_responsable_inicial
      from crm.inversion_solicitud_revisiones r where r.solicitud_id=v_s.id order by r.revision limit 1;
    v_responsable_inicial:=coalesce(v_responsable_inicial,v_s.responsable_esperado_id);
    if v_payload_contrato->>'cliente_id' is not null
       and v_payload_contrato->>'cliente_id' is distinct from v_ctx->>'perfil_id' then
      raise exception 'El contrato no corresponde a esta persona' using errcode='P0409';
    end if;
    if v_payload_contrato->>'analista_cierre_id' is not null
       and v_payload_contrato->>'analista_cierre_id' is distinct from v_responsable_inicial::text then
      raise exception 'El analista del contenido original no corresponde al responsable con que se preparó la inversión' using errcode='P0409';
    end if;
    -- El contenido original conserva su huella. Una revisión explícita cambia
    -- el responsable con quien se confirma, sin reescribir las condiciones.
    v_payload_contrato := v_payload_contrato||jsonb_build_object('cliente_id',v_ctx->>'perfil_id',
      'analista_cierre_id',v_ctx->>'responsable_id');
    -- La fuente existente conserva producto, tasa, cronograma, cuenta, titularidad
    -- documental y operaciones de cartera. Todo participa de esta transacción.
    -- Reutiliza además la reserva y el snapshot documentales del alta publicada.
    -- Un PDF pendiente no vuelve a crear el contrato cuando se recupera el envío.
    -- El flujo Avance vigente es libre y fotografía sus términos. El catálogo
    -- sigue siendo opcional: F4 no lo convierte en un requisito comercial nuevo.
    perform pg_catalog.set_config('crm.producto_condicion_id',
      coalesce((nullif(v_s.datos->>'producto_condicion_id','')::uuid)::text,''),true);
    begin
      v_fuente := crm.crear_contrato_con_cuenta_pdf_v2(
        v_payload_contrato||jsonb_build_object('clave_idempotencia',v_s.id),
        v_s.datos->'cronograma',v_s.datos->'cuenta');
    exception when others then
      perform pg_catalog.set_config('crm.producto_condicion_id',coalesce(v_config_producto,''),true);
      raise;
    end;
    perform pg_catalog.set_config('crm.producto_condicion_id',coalesce(v_config_producto,''),true);
    v_contrato := (v_fuente->>'id')::uuid;
    if v_contrato is null then raise exception 'El contrato no devolvió su identificador' using errcode='P0001'; end if;
    select producto_condicion_id into v_condicion from public.contratos where id=v_contrato;
    v_fuente:=v_fuente||private.metadata_condicion_producto(v_condicion);
  else
    raise exception 'Empresa sin puerta de inversión disponible' using errcode='P0409';
  end if;
  v_inversion := private.inversion_vincular_fuente(v_persona,v_contrato,v_cierre,v_uid,false);
  if v_ajuste then
    insert into crm.inversion_ajustes_mes_cerrado(inversion_id,periodo_origen,fecha_imputacion,creado_por)
    values(v_inversion,v_periodo,v_imputacion,v_uid);
  end if;
  insert into crm.inversion_eventos(inversion_id,tipo,creado_por) values(v_inversion,'registro',v_uid);
  v_res := jsonb_build_object('ok',true,'solicitud_id',v_s.id,'inversion_id',v_inversion,
    'inversionista_id',v_persona,'lead_id',v_ctx->>'lead_id','empresa',v_e.clave,'fuente',v_fuente,
    'revision_datos',v_s.revision_datos);
  update crm.inversion_solicitudes set estado='confirmada',inversion_id=v_inversion,
    resultado=v_res,confirmado_por=v_uid,actualizado_en=statement_timestamp() where id=v_s.id;
  return v_res;
end;

exception when serialization_failure then
  if not exists(select 1 from crm.inversion_solicitud_origenes where solicitud_id=p_solicitud) then raise; end if;
  raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
end;
$function$;

CREATE OR REPLACE FUNCTION crm.corregir_solicitud_inversion_fn(p_solicitud uuid, p_clave uuid, p_revision_datos_esperada integer, p_datos jsonb, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$begin

declare
  v_persona uuid; v_ctx jsonb; v_validacion jsonb;
  v_s crm.inversion_solicitudes%rowtype;
  v_r crm.inversion_solicitud_correcciones%rowtype;
  v_hash text; v_inicial uuid; v_empresa uuid;
begin
  if p_clave is null or p_revision_datos_esperada is null or p_revision_datos_esperada<0
    or p_datos is null or jsonb_typeof(p_datos)<>'object' then
    raise exception 'Indica clave, versión y contenido de la corrección' using errcode='22023';
  end if;
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  if not found then raise exception 'Solicitud no encontrada' using errcode='P0002'; end if;
  -- Siempre ámbito/membresía actuales, también al recuperar una corrección.
  v_ctx:=private.inversion_persona_autorizada(v_persona);
  perform private.motivo_sin_documento(p_motivo,(select array_agg(documento_normalizado)
    from crm.inversionista_identificadores where inversionista_id=private.inversionista_canonica(v_persona)));
  v_hash:=private.idem_hash(jsonb_build_object('solicitud',p_solicitud,'revision',p_revision_datos_esperada,
    'datos',p_datos,'motivo',btrim(p_motivo)));
  perform pg_advisory_xact_lock(hashtextextended('f4_correccion:'||p_clave::text,0));
  select * into v_r from crm.inversion_solicitud_correcciones where id=p_clave;
  if found then
    if v_r.hash_peticion is distinct from v_hash then
      raise exception 'La clave de corrección ya se usó con otros datos' using errcode='P0409';
    end if;
    return private.inversion_solicitud_resultado(p_solicitud,v_ctx)||
      jsonb_build_object('correccion_id',v_r.id,'revision_aplicada',v_r.revision,'reintento',true);
  end if;
  v_ctx:=private.inversion_persona_contexto(v_persona);
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if v_s.estado<>'preparada' then
    raise exception 'Sólo se corrigen solicitudes todavía preparadas' using errcode='P0409';
  end if;
  if v_s.revision_datos is distinct from p_revision_datos_esperada then
    raise exception 'Los datos cambiaron; vuelve a revisar la solicitud' using errcode='PT409';
  end if;
  if v_s.responsable_esperado_id is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'Revisa primero el cambio de responsable de esta solicitud' using errcode='P0409';
  end if;
  if p_datos->'inversionista_id' is distinct from v_s.datos->'inversionista_id'
    or p_datos->'empresa' is distinct from v_s.datos->'empresa'
    or p_datos#>'{contrato,cliente_id}' is distinct from v_s.datos#>'{contrato,cliente_id}'
    or p_datos#>'{contrato,analista_cierre_id}' is distinct from v_s.datos#>'{contrato,analista_cierre_id}' then
    raise exception 'La corrección conserva la persona, empresa y referencias originales del contrato' using errcode='22023';
  end if;
  if p_datos->'evidencia' is distinct from v_s.datos->'evidencia' then
    raise exception 'La corrección conserva la ruta del comprobante de esta solicitud' using errcode='22023';
  end if;
  if v_s.auth_claim_id is not null and p_datos->'alta_portal' is distinct from v_s.datos->'alta_portal' then
    raise exception 'El acceso Avance ya está reservado; conserva sus datos de alta' using errcode='P0409';
  end if;
  select responsable_anterior_id into v_inicial from crm.inversion_solicitud_revisiones
    where solicitud_id=p_solicitud order by revision limit 1;
  v_validacion:=v_ctx||jsonb_build_object('responsable_id',coalesce(v_inicial,v_s.responsable_esperado_id));
  v_empresa:=private.inversion_validar_datos(p_solicitud,p_datos,v_validacion);
  if v_empresa is distinct from v_s.empresa_id then
    raise exception 'La empresa cambió; revisa la solicitud' using errcode='PT409';
  end if;
  if p_datos=v_s.datos then raise exception 'No hay datos distintos que corregir' using errcode='22023'; end if;
  insert into crm.inversion_solicitud_correcciones(id,solicitud_id,revision_anterior,revision,
    hash_peticion,hash_anterior,hash_nuevo,datos_anteriores,datos_nuevos,motivo,corregido_por)
    values(p_clave,p_solicitud,v_s.revision_datos,v_s.revision_datos+1,v_hash,
    private.idem_hash(v_s.datos),private.idem_hash(p_datos),v_s.datos,p_datos,btrim(p_motivo),(select auth.uid()));
  -- La huella original permanece: repetir preparar con su petición original
  -- recupera esta misma solicitud, nunca crea otra ni revierte una corrección.
  update crm.inversion_solicitudes set datos=p_datos,revision_datos=revision_datos+1,
    actualizado_en=statement_timestamp() where id=p_solicitud;
  return private.inversion_solicitud_resultado(p_solicitud,v_ctx)||
    jsonb_build_object('correccion_id',p_clave,'revision_aplicada',v_s.revision_datos+1,'reintento',false);
end;

exception when serialization_failure then
  if not exists(select 1 from crm.inversion_solicitud_origenes where solicitud_id=p_solicitud) then raise; end if;
  raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
end;
$function$;

do $postreversa$
begin
  if (select jsonb_object_agg(clave, monedas order by clave) from crm.empresas)
     is distinct from '{"avance":["PEN","USD"],"prodelco":["PEN"],"qorilazo":["PEN"]}'::jsonb then
    raise exception 'POSTREVERSA: el catalogo no volvio a su estado anterior';
  end if;
  if (select pg_get_constraintdef(oid) from pg_constraint
      where conrelid='crm.cierres_externos'::regclass and conname='cierres_externos_moneda_check')
     is distinct from 'CHECK ((moneda = ''PEN''::text))' then
    raise exception 'POSTREVERSA: el CHECK no volvio a solo PEN';
  end if;
  -- Byte a byte: las CINCO huellas que tenia produccion ANTES de la migracion.
  -- Si una no coincide, la migracion no se podria reinstalar y hay que saberlo
  -- AHORA, no cuando falle su preflight.
  if md5(pg_get_functiondef('crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text,integer,numeric)'::regprocedure))
       is distinct from '3f1cded7e40c54c98bcf461665c6f8ff'
    or md5(pg_get_functiondef('crm.corregir_cierre_externo(uuid,numeric,text,text,text,text,date,text)'::regprocedure))
       is distinct from '894806c9b0a765eff7896f42d51f8bff'
    or md5(pg_get_functiondef('private.inversion_validar_datos(uuid,jsonb,jsonb)'::regprocedure))
       is distinct from '96b4e342df9cc08a875bac34ca17a829'
    or md5(pg_get_functiondef('crm.confirmar_inversion_revisada_fn(uuid,integer)'::regprocedure))
       is distinct from '8ab0be625fecb7916de44286425c0688'
    or md5(pg_get_functiondef('crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)'::regprocedure))
       is distinct from '3de3d2689706371cdc46f0a29836cb5c' then
    raise exception 'POSTREVERSA: un escritor no quedo con la definicion previa a la migracion';
  end if;
end;
$postreversa$;

notify pgrst,'reload schema';
commit;
