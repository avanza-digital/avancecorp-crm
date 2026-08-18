-- ============================================================================
-- Centro de ayuda del vendedor — contenido y resolución autoritativos
-- ============================================================================
-- Sin IA ni respuestas redactadas en el navegador. Las frases aprobadas, las
-- guías, las reglas de ambigüedad y la telemetría anonimizada viven en private;
-- el único borde público son dos RPC autenticadas del esquema crm.

begin;
set local lock_timeout = '10s';

create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;

-- Producción tenía pg_trgm en public. La extensión es relocatable y los
-- índices existentes referencian sus objetos por OID, por lo que moverla no
-- los reconstruye; sí elimina la superficie señalada por el advisor 0014.
do $extension_schema$
declare
  v_esquema text;
begin
  select n.nspname
  into v_esquema
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pg_trgm';

  if v_esquema is distinct from 'extensions' then
    alter extension pg_trgm set schema extensions;
  end if;
end;
$extension_schema$;

-- Esta variante inmutable se usa únicamente en columnas GENERATED. La RPC
-- aplica además extensions.unaccent() a la consulta antes de llegar aquí.
create or replace function private.normalizar_texto_ayuda(p_texto text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $function$
  select trim(
    both ' ' from regexp_replace(
      translate(lower(coalesce(p_texto, '')), 'áéíóúüñ', 'aeiouun'),
      '[^a-z0-9]+',
      ' ',
      'g'
    )
  );
$function$;

create or replace function private.normalizar_consulta_ayuda(p_texto text)
returns text
language sql
stable
parallel safe
set search_path = ''
as $function$
  select private.normalizar_texto_ayuda(
    extensions.unaccent(coalesce(p_texto, ''))
  );
$function$;

-- Nunca conserva vocabulario libre: teléfonos/DNI/correos se sustituyen de
-- forma explícita y todo token ajeno al vocabulario de negocio se vuelve
-- [otro]. Así tampoco quedan nombres completos en la telemetría.
create or replace function private.redactar_consulta_ayuda(p_texto text)
returns text
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_texto text := coalesce(p_texto, '');
  v_normalizado text;
  v_resultado text;
  v_permitidos constant text[] := array[
    'a','accion','actividad','actualizar','agenda','agendar','algo','anular',
    'archivo','asistio','borrar','busco','buscar','cambiar','cancelar','capital',
    'cartera','celular','cerrar','cierre','cita','cliente','como','completar',
    'confirmar','confirmada','contactar','contacto','contrato','convertir','corregir',
    'crear','datos','descargar','descartar','dni','documento','donde','duplicado',
    'editar','el','eliminar','en','encontrar','error','es','esta','etapa','existe',
    'fallo','fecha','gestion','guardar','hacer','hice','historial','la','lead','llamada',
    'llamar','llego','lo','marcar','mover','no','nombre','nuevo','numero','ocupado',
    'pdf','pendiente','persona','plantado','por','programar','prospecto','propuesta',
    'proxima','quitar','que','recordatorio','registrar','reintentar','reprogramar',
    'resultado','reunion','sacar','siguiente','tarea','telefono','trabajar','venta',
    'whatsapp','ya','quiero','piicorreo','piinumero'
  ];
begin
  v_texto := regexp_replace(
    v_texto,
    '[[:alnum:]._%+\-]+@[[:alnum:].\-]+\.[[:alpha:]]{2,}',
    ' piicorreo ',
    'gi'
  );
  v_texto := regexp_replace(
    v_texto,
    '([0-9][[:space:].()\-]*){8,}',
    ' piinumero ',
    'g'
  );
  v_normalizado := private.normalizar_consulta_ayuda(v_texto);

  select string_agg(
    case
      when token = 'piicorreo' then '[correo]'
      when token = 'piinumero' then '[numero]'
      when token = any(v_permitidos) then token
      else '[otro]'
    end,
    ' ' order by orden
  )
  into v_resultado
  from unnest(regexp_split_to_array(v_normalizado, '[[:space:]]+'))
       with ordinality as t(token, orden)
  where token <> '';

  return coalesce(v_resultado, '');
end;
$function$;

create table private.ayuda_intenciones (
  id bigint generated always as identity primary key,
  clave text not null,
  version integer not null default 1,
  pregunta text not null,
  contenido jsonb not null,
  vistas text[] not null,
  grupos_obligatorios jsonb not null default '[]'::jsonb,
  terminos_excluidos text[] not null default '{}'::text[],
  prioridad smallint not null default 100,
  estado text not null default 'borrador',
  publicado_en timestamptz,
  creado_en timestamptz not null default clock_timestamp(),
  constraint ayuda_intenciones_clave_formato
    check (clave ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  constraint ayuda_intenciones_version_positiva check (version > 0),
  constraint ayuda_intenciones_pregunta_longitud
    check (char_length(pregunta) between 3 and 180),
  constraint ayuda_intenciones_contenido_objeto
    check (jsonb_typeof(contenido) = 'object'),
  constraint ayuda_intenciones_vistas_validas check (
    cardinality(vistas) > 0
    and vistas <@ array[
      'hoy','alertas','conversiones','ranking-vendedores','reuniones','metas',
      'rendimiento','capital-cierres','pipeline','cartera','agenda','mi-cartera',
      'repartir','equipo','config','config-usuarios','config-productos',
      'config-metas','config-sla'
    ]::text[]
  ),
  constraint ayuda_intenciones_grupos_array
    check (jsonb_typeof(grupos_obligatorios) = 'array'),
  constraint ayuda_intenciones_estado_valido
    check (estado in ('borrador', 'publicado', 'retirado')),
  constraint ayuda_intenciones_publicacion_coherente check (
    (estado = 'publicado' and publicado_en is not null)
    or (estado <> 'publicado')
  ),
  unique (clave, version)
);

create unique index ayuda_intenciones_una_publicada_idx
  on private.ayuda_intenciones (clave)
  where estado = 'publicado';
create index ayuda_intenciones_inicio_idx
  on private.ayuda_intenciones (estado, prioridad, clave)
  include (pregunta, vistas);
create index ayuda_intenciones_vistas_idx
  on private.ayuda_intenciones using gin (vistas);

create table private.ayuda_expresiones (
  id bigint generated always as identity primary key,
  intencion_id bigint not null
    references private.ayuda_intenciones(id) on delete cascade,
  texto text not null,
  texto_normalizado text generated always as (
    private.normalizar_texto_ayuda(texto)
  ) stored,
  vector_busqueda tsvector generated always as (
    to_tsvector('spanish'::regconfig, private.normalizar_texto_ayuda(texto))
  ) stored,
  peso numeric(4,3) not null default 1,
  tipo text not null default 'coloquial',
  constraint ayuda_expresiones_texto_longitud
    check (char_length(texto) between 2 and 180),
  constraint ayuda_expresiones_peso_valido check (peso > 0 and peso <= 1),
  constraint ayuda_expresiones_tipo_valido
    check (tipo in ('canonica', 'exacta', 'coloquial')),
  unique (texto_normalizado)
);

create index ayuda_expresiones_intencion_idx
  on private.ayuda_expresiones (intencion_id);
create index ayuda_expresiones_vector_idx
  on private.ayuda_expresiones using gin (vector_busqueda);
create index ayuda_expresiones_trgm_idx
  on private.ayuda_expresiones using gin (
    texto_normalizado extensions.gin_trgm_ops
  );

create table private.ayuda_reglas_aclaracion (
  id bigint generated always as identity primary key,
  clave text not null unique,
  todos text[] not null default '{}'::text[],
  alguno text[] not null,
  ninguno text[] not null default '{}'::text[],
  titulo text not null,
  detalle text not null,
  opciones jsonb not null,
  prioridad smallint not null default 100,
  activa boolean not null default true,
  constraint ayuda_reglas_clave_formato
    check (clave ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  constraint ayuda_reglas_alguno_no_vacio check (cardinality(alguno) > 0),
  constraint ayuda_reglas_opciones_validas check (
    jsonb_typeof(opciones) = 'array'
    and jsonb_array_length(opciones) between 2 and 3
  )
);

create table private.ayuda_consultas (
  id bigint generated always as identity primary key,
  usuario_id uuid not null,
  vista text not null,
  consulta_redactada text not null,
  longitud smallint not null,
  resultado text not null,
  intencion_id bigint
    references private.ayuda_intenciones(id) on delete set null,
  puntuacion numeric(5,4),
  segunda_puntuacion numeric(5,4),
  motivo text not null,
  creado_en timestamptz not null default clock_timestamp(),
  retener_hasta timestamptz not null default (clock_timestamp() + interval '90 days'),
  constraint ayuda_consultas_resultado_valido
    check (resultado in ('respuesta', 'aclaracion', 'sin_resultado')),
  constraint ayuda_consultas_longitud_valida check (longitud between 2 and 240),
  constraint ayuda_consultas_puntuacion_valida check (
    (puntuacion is null or puntuacion between 0 and 1)
    and (segunda_puntuacion is null or segunda_puntuacion between 0 and 1)
  )
);

create index ayuda_consultas_intencion_idx
  on private.ayuda_consultas (intencion_id);
create index ayuda_consultas_usuario_fecha_idx
  on private.ayuda_consultas (usuario_id, creado_en desc);
create index ayuda_consultas_retencion_idx
  on private.ayuda_consultas (retener_hasta);

alter table private.ayuda_intenciones enable row level security;
alter table private.ayuda_expresiones enable row level security;
alter table private.ayuda_reglas_aclaracion enable row level security;
alter table private.ayuda_consultas enable row level security;

revoke all on table private.ayuda_intenciones
  from public, anon, authenticated, service_role;
revoke all on table private.ayuda_expresiones
  from public, anon, authenticated, service_role;
revoke all on table private.ayuda_reglas_aclaracion
  from public, anon, authenticated, service_role;
revoke all on table private.ayuda_consultas
  from public, anon, authenticated, service_role;
revoke all on sequence
  private.ayuda_intenciones_id_seq,
  private.ayuda_expresiones_id_seq,
  private.ayuda_reglas_aclaracion_id_seq,
  private.ayuda_consultas_id_seq
  from public, anon, authenticated, service_role;

revoke all on function private.normalizar_texto_ayuda(text)
  from public, anon, authenticated, service_role;
revoke all on function private.normalizar_consulta_ayuda(text)
  from public, anon, authenticated, service_role;
revoke all on function private.redactar_consulta_ayuda(text)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- Catálogo inicial aprobado: 17 guías + lenguaje real de vendedores
-- ============================================================================

do $seed$
declare
  v_articulo jsonb;
  v_expresion jsonb;
  v_intencion_id bigint;
begin
  for v_articulo in
    select value
    from jsonb_array_elements($catalogo$
[
  {
    "clave":"anular-tarea-pendiente",
    "pregunta":"¿Cómo elimino una acción que ya no voy a realizar?",
    "vistas":["agenda","hoy","pipeline","cartera"],
    "requeridos":[["accion","tarea","pendiente","llamada","whatsapp","recordatorio","reunion"]],
    "excluidos":["actividad","gestion","historial","contrato","lead","cliente"],
    "prioridad":10,
    "contenido":{
      "id":"anular-tarea-pendiente",
      "titulo":"Quitar una acción pendiente de tu agenda",
      "resumen":"Si esa llamada, WhatsApp, tarea o reunión ya no se hará, no la cierres con un resultado falso: anúlala.",
      "duracion":"1 min",
      "traduccion":{"lenguajeVendedor":"Eliminar o borrar una acción","lenguajeCrm":"Anular tarea"},
      "pasos":[
        {"titulo":"Ubica la acción pendiente","detalle":"Encuéntrala en Agenda o abre la ficha del lead y ve a \"Próxima acción\"."},
        {"titulo":"Abre la opción de anular","detalle":"En Agenda, pulsa \"Cerrar tarea\" y luego \"Ya no hace falta — anular esta tarea\". En la ficha puedes usar directamente \"Anular tarea\"."},
        {"titulo":"Revisa qué cambiará","detalle":"El CRM te avisará si el lead quedará sin próxima acción o si una reunión hará retroceder su etapa."},
        {"titulo":"Confirma \"Sí, anular\"","detalle":"La acción saldrá de tu agenda, no contará como gestión realizada y no se podrá recuperar."}
      ],
      "advertencia":"Si sí vas a realizarla pero en otra fecha, usa Reprogramar. Si ya registraste una gestión en el historial, no se borra: debes dejar una Nota de corrección.",
      "accion":{"tipo":"navegar","vista":"agenda","etiqueta":"Ir a Agenda"},
      "fuente":"Manual del vendedor · Acciones pendientes · versión aprobada"
    },
    "expresiones":[
      {"texto":"¿Cómo elimino una acción que ya no voy a realizar?","peso":1,"tipo":"canonica"},
      {"texto":"como elimino una accion","peso":0.98,"tipo":"exacta"},
      {"texto":"quiero borrar una tarea","peso":0.97,"tipo":"coloquial"},
      {"texto":"como quito un pendiente","peso":0.97,"tipo":"coloquial"},
      {"texto":"quiero sacar un pendiente","peso":0.97,"tipo":"coloquial"},
      {"texto":"ya no voy a hacer esa llamada","peso":0.95,"tipo":"coloquial"},
      {"texto":"quiero cancelar un recordatorio","peso":0.95,"tipo":"coloquial"},
      {"texto":"como saco una accion de mi agenda","peso":0.95,"tipo":"coloquial"}
    ]
  },
  {
    "clave":"registrar-lead",
    "pregunta":"¿Cómo registro y empiezo a trabajar un lead?",
    "vistas":["hoy","pipeline","cartera"],
    "requeridos":[["lead","contacto","prospecto","numero","celular"]],
    "excluidos":["actividad","gestion","historial","contrato","cliente"],
    "prioridad":20,
    "contenido":{
      "id":"registrar-lead",
      "titulo":"Registrar un lead y dejarlo listo para trabajar",
      "resumen":"Crea el contacto, deja que el CRM compruebe su disponibilidad y termina con una siguiente acción concreta.",
      "duracion":"2 min",
      "pasos":[
        {"titulo":"Abre \"Nuevo lead\"","detalle":"Usa el botón azul de la parte superior. La guía se minimizará, pero conservará este punto."},
        {"titulo":"Completa los datos obligatorios","detalle":"Registra nombre, celular peruano, origen y capital estimado. Añade contexto en Nota si lo tienes."},
        {"titulo":"Revisa la disponibilidad","detalle":"Con un celular válido, el CRM comprueba si el contacto ya está ocupado antes de guardarlo."},
        {"titulo":"Agenda el siguiente paso","detalle":"Al crear el lead se abrirá su ficha. En \"Próxima acción\", programa una llamada, WhatsApp o reunión."}
      ],
      "advertencia":"No crees otro registro si el CRM indica que el contacto ya existe. Sigue la instrucción de disponibilidad que aparece en pantalla.",
      "accion":{"tipo":"nuevo_lead","etiqueta":"Abrir Nuevo lead"},
      "fuente":"Manual del vendedor · Leads · versión aprobada"
    },
    "expresiones":[
      {"texto":"¿Cómo registro y empiezo a trabajar un lead?","peso":1,"tipo":"canonica"},
      {"texto":"como creo un contacto nuevo","peso":0.97,"tipo":"coloquial"},
      {"texto":"quiero ingresar un prospecto","peso":0.97,"tipo":"coloquial"},
      {"texto":"como meto un lead al sistema","peso":0.97,"tipo":"coloquial"},
      {"texto":"tengo un numero nuevo para llamar","peso":0.94,"tipo":"coloquial"}
    ]
  },
  {
    "clave":"contactar-registrar-gestion",
    "pregunta":"¿Cómo llamo o escribo por WhatsApp y dejo registrada la gestión?",
    "vistas":["hoy","cartera","pipeline"],
    "requeridos":[["llamada","llamar","whatsapp","contacto","cliente","gestion","resultado"]],
    "excluidos":["borrar","eliminar","corregir","anular","reprogramar"],
    "prioridad":30,
    "contenido":{
      "id":"contactar-registrar-gestion",
      "titulo":"Contactar al lead y registrar lo que ocurrió",
      "resumen":"Haz el contacto desde su ficha y registra el resultado real para que el historial y tu seguimiento queden actualizados.",
      "duracion":"2 min",
      "pasos":[
        {"titulo":"Abre la ficha del lead","detalle":"Encuéntralo en Leads o Pipeline y abre su detalle."},
        {"titulo":"Realiza el contacto","detalle":"Usa el acceso de llamada o WhatsApp y conversa con el lead antes de registrar un resultado."},
        {"titulo":"Pulsa \"Registrar actividad…\"","detalle":"Elige el tipo de gestión y el resultado que realmente ocurrió; agrega un detalle útil para el siguiente contacto."},
        {"titulo":"Deja el siguiente paso","detalle":"Si corresponde, agenda la próxima llamada, WhatsApp o reunión para que el lead no quede sin seguimiento."}
      ],
      "advertencia":"Abrir WhatsApp o copiar el teléfono no registra por sí solo una gestión. Registra la actividad después de saber qué ocurrió.",
      "accion":{"tipo":"navegar","vista":"cartera","etiqueta":"Ir a Leads"},
      "fuente":"Manual del vendedor · Contacto y actividades · versión aprobada"
    },
    "expresiones":[
      {"texto":"¿Cómo llamo o escribo por WhatsApp y dejo registrada la gestión?","peso":1,"tipo":"canonica"},
      {"texto":"como marco que ya llame","peso":0.98,"tipo":"coloquial"},
      {"texto":"ya le escribi por whatsapp","peso":0.98,"tipo":"coloquial"},
      {"texto":"como registro que no contesto","peso":0.97,"tipo":"coloquial"},
      {"texto":"donde pongo el resultado de la llamada","peso":0.97,"tipo":"coloquial"},
      {"texto":"como dejo constancia del contacto","peso":0.95,"tipo":"coloquial"},
      {"texto":"ya hable con el cliente","peso":0.94,"tipo":"coloquial"}
    ]
  },
  {
    "clave":"editar-datos-lead",
    "pregunta":"¿Cómo corrijo o completo los datos de un lead?",
    "vistas":["cartera","pipeline","hoy"],
    "requeridos":[["datos","celular","numero","nombre","correo","dni","capital","lead","prospecto"]],
    "excluidos":["actividad","gestion","historial","etapa","reunion","cita","contrato"],
    "prioridad":40,
    "contenido":{
      "id":"editar-datos-lead",
      "titulo":"Actualizar los datos de un lead",
      "resumen":"Corrige o completa la información desde la sección Datos de la ficha, sin crear un contacto duplicado.",
      "duracion":"1 min",
      "pasos":[
        {"titulo":"Abre la ficha del lead","detalle":"Busca al contacto en Leads o Pipeline."},
        {"titulo":"Entra a \"Datos\"","detalle":"Pulsa \"Editar\" o \"Completar\", según lo que muestre la ficha."},
        {"titulo":"Corrige la información","detalle":"Actualiza solo los campos necesarios y verifica especialmente celular, documento y correo."},
        {"titulo":"Pulsa \"Guardar\"","detalle":"Comprueba que la ficha muestre los datos nuevos antes de continuar trabajando."}
      ],
      "advertencia":"Editar los datos del contacto no cambia una actividad del historial. Si registraste mal una gestión, deja una Nota de corrección.",
      "accion":{"tipo":"navegar","vista":"cartera","etiqueta":"Buscar el lead"},
      "fuente":"Manual del vendedor · Datos del lead · versión aprobada"
    },
    "expresiones":[
      {"texto":"¿Cómo corrijo o completo los datos de un lead?","peso":1,"tipo":"canonica"},
      {"texto":"como cambio el numero de un lead","peso":0.98,"tipo":"coloquial"},
      {"texto":"me equivoque en el dni","peso":0.98,"tipo":"coloquial"},
      {"texto":"quiero actualizar el correo","peso":0.97,"tipo":"coloquial"},
      {"texto":"donde cambio el capital","peso":0.96,"tipo":"coloquial"},
      {"texto":"como completo los datos del prospecto","peso":0.97,"tipo":"coloquial"},
      {"texto":"el nombre esta mal","peso":0.94,"tipo":"coloquial"}
    ]
  },
  {
    "clave":"agendar-siguiente-accion",
    "pregunta":"¿Cómo agendo una llamada, WhatsApp o reunión?",
    "vistas":["hoy","agenda","cartera","pipeline"],
    "requeridos":[["llamada","whatsapp","reunion","cita","recordatorio","accion","tarea","pendiente"]],
    "excluidos":["borrar","eliminar","anular","cerrar","realizada","hice","reprogramar"],
    "prioridad":50,
    "contenido":{
      "id":"agendar-siguiente-accion",
      "titulo":"Agendar la próxima acción de un lead",
      "resumen":"Programa el siguiente contacto desde la ficha para que aparezca en tu agenda en el día y la hora correctos.",
      "duracion":"1 min",
      "traduccion":{"lenguajeVendedor":"Poner un pendiente o recordatorio","lenguajeCrm":"Agendar próxima acción"},
      "pasos":[
        {"titulo":"Abre la ficha del lead","detalle":"Busca al contacto y ubica la sección \"Próxima acción\"."},
        {"titulo":"Elige el tipo de acción","detalle":"Selecciona llamada, WhatsApp, reunión o tarea, según el compromiso real."},
        {"titulo":"Define fecha, hora y motivo","detalle":"Escribe un título concreto para recordar qué debes conseguir en ese contacto."},
        {"titulo":"Pulsa \"Agendar\"","detalle":"La nueva acción aparecerá en Agenda y en el seguimiento del lead."}
      ],
      "advertencia":"No uses una tarea genérica si ya acordaste una reunión: registra el tipo correcto para que las métricas y recordatorios funcionen.",
      "accion":{"tipo":"navegar","vista":"cartera","etiqueta":"Ir a Leads"},
      "fuente":"Manual del vendedor · Próxima acción · versión aprobada"
    },
    "expresiones":[
      {"texto":"¿Cómo agendo una llamada, WhatsApp o reunión?","peso":1,"tipo":"canonica"},
      {"texto":"quiero poner un recordatorio","peso":0.97,"tipo":"coloquial"},
      {"texto":"como programo una llamada","peso":0.98,"tipo":"coloquial"},
      {"texto":"donde dejo el siguiente paso","peso":0.95,"tipo":"coloquial"},
      {"texto":"quiero agendar una cita","peso":0.98,"tipo":"coloquial"},
      {"texto":"como hago para llamarlo manana","peso":0.94,"tipo":"coloquial"},
      {"texto":"quiero dejar una tarea pendiente","peso":0.96,"tipo":"coloquial"}
    ]
  },
  {
    "clave":"reprogramar-reunion",
    "pregunta":"¿Cómo reprogramo una reunión?",
    "vistas":["agenda","hoy"],
    "requeridos":[["reunion","cita"]],
    "excluidos":["anular","cancelar","cerrar","realizada","asistio","confirmar","recordatorio"],
    "prioridad":60,
    "contenido":{
      "id":"reprogramar-reunion",
      "titulo":"Reprogramar una reunión sin perder el seguimiento",
      "resumen":"Muévela desde Agenda para conservar su historial y la trazabilidad de la gestión comercial.",
      "duracion":"1 min",
      "pasos":[
        {"titulo":"Entra a Agenda","detalle":"Ubica la reunión pendiente por el nombre del lead o por su fecha."},
        {"titulo":"Elige el nuevo plazo","detalle":"Usa \"+1d\", \"+3d\" o \"+1sem\" en la misma tarjeta. No necesitas abrir otra pantalla."},
        {"titulo":"Comprueba el nuevo día","detalle":"El CRM mostrará la fecha resultante y moverá la tarea fuera de vencidas si corresponde."}
      ],
      "advertencia":"Si solo cambió la fecha, no uses \"Anular\". Anular cancela la reunión y puede devolver el lead a una etapa anterior.",
      "accion":{"tipo":"navegar","vista":"agenda","etiqueta":"Ir a Agenda"},
      "fuente":"Manual del vendedor · Agenda · versión aprobada"
    },
    "expresiones":[
      {"texto":"¿Cómo reprogramo una reunión?","peso":1,"tipo":"canonica"},
      {"texto":"como cambio la fecha de una cita","peso":0.98,"tipo":"coloquial"},
      {"texto":"quiero mover una reunion","peso":0.98,"tipo":"coloquial"},
      {"texto":"el cliente me pidio otra fecha","peso":0.94,"tipo":"coloquial"},
      {"texto":"como paso la reunion para manana","peso":0.97,"tipo":"coloquial"}
    ]
  },
  {
    "clave":"confirmar-recordar-reunion",
    "pregunta":"¿Cómo confirmo una reunión o envío un recordatorio?",
    "vistas":["agenda","hoy"],
    "requeridos":[["reunion","cita"]],
    "excluidos":["reprogramar","mover","anular","cancelar","cerrar","asistio"],
    "prioridad":70,
    "contenido":{
      "id":"confirmar-recordar-reunion",
      "titulo":"Recordar y confirmar una reunión",
      "resumen":"Envía el recordatorio desde Agenda y marca la reunión como confirmada solo después de recibir la respuesta del lead.",
      "duracion":"1 min",
      "pasos":[
        {"titulo":"Ubica la reunión en Agenda","detalle":"Revisa que el lead, la fecha y la hora sean correctos."},
        {"titulo":"Pulsa \"Recordar cita\"","detalle":"Usa el mensaje preparado para pedir confirmación por WhatsApp."},
        {"titulo":"Espera la respuesta","detalle":"La cita todavía no está confirmada solo por haber enviado el mensaje."},
        {"titulo":"Pulsa \"Marcar confirmada\"","detalle":"Hazlo cuando el lead haya aceptado la fecha y la hora."}
      ],
      "advertencia":"No marques una reunión como confirmada si el lead no respondió. Si pidió otra fecha, usa Reprogramar.",
      "accion":{"tipo":"navegar","vista":"agenda","etiqueta":"Revisar reuniones"},
      "fuente":"Manual del vendedor · Confirmación de reuniones · versión aprobada"
    },
    "expresiones":[
      {"texto":"¿Cómo confirmo una reunión o envío un recordatorio?","peso":1,"tipo":"canonica"},
      {"texto":"quiero recordar la cita al cliente","peso":0.97,"tipo":"coloquial"},
      {"texto":"como mando la confirmacion","peso":0.95,"tipo":"coloquial"},
      {"texto":"el cliente ya confirmo","peso":0.95,"tipo":"coloquial"},
      {"texto":"como marco la reunion confirmada","peso":0.98,"tipo":"coloquial"},
      {"texto":"quiero enviarle un whatsapp de recordatorio","peso":0.95,"tipo":"coloquial"}
    ]
  },
  {
    "clave":"cerrar-tarea-resultado",
    "pregunta":"¿Cómo marco que ya hice una llamada, tarea o reunión?",
    "vistas":["agenda","hoy"],
    "requeridos":[["llamada","tarea","reunion","accion","pendiente"]],
    "excluidos":["borrar","eliminar","anular","cancelar","reprogramar","mover"],
    "prioridad":80,
    "contenido":{
      "id":"cerrar-tarea-resultado",
      "titulo":"Cerrar una acción con su resultado real",
      "resumen":"Cierra la acción desde Agenda, registra qué ocurrió y deja el próximo paso cuando todavía exista seguimiento.",
      "duracion":"2 min",
      "pasos":[
        {"titulo":"Ubica la acción en Agenda","detalle":"Verifica que sea la llamada, tarea o reunión que efectivamente realizaste."},
        {"titulo":"Pulsa \"Cerrar tarea\"","detalle":"Se abrirán los resultados disponibles para ese tipo de acción."},
        {"titulo":"Elige el resultado real","detalle":"Indica si hubo contacto, si se realizó la reunión o el resultado equivalente que muestre el CRM."},
        {"titulo":"Registra el detalle y continúa","detalle":"Escribe lo importante y agenda la siguiente acción si el proceso comercial continúa."}
      ],
      "advertencia":"Si la acción no se realizó, no la cierres con un resultado inventado. Reprográmala o anúlala, según corresponda.",
      "accion":{"tipo":"navegar","vista":"agenda","etiqueta":"Ir a Agenda"},
      "fuente":"Manual del vendedor · Cierre de tareas · versión aprobada"
    },
    "expresiones":[
      {"texto":"¿Cómo marco que ya hice una llamada, tarea o reunión?","peso":1,"tipo":"canonica"},
      {"texto":"como cierro una llamada que ya hice","peso":0.98,"tipo":"coloquial"},
      {"texto":"ya termine la tarea","peso":0.97,"tipo":"coloquial"},
      {"texto":"donde pongo como salio la llamada","peso":0.96,"tipo":"coloquial"},
      {"texto":"como marco una reunion realizada","peso":0.98,"tipo":"coloquial"},
      {"texto":"quiero completar un pendiente","peso":0.96,"tipo":"coloquial"},
      {"texto":"ya hice la accion","peso":0.96,"tipo":"coloquial"}
    ]
  },
  {
    "clave":"marcar-no-asistio",
    "pregunta":"¿Cuándo marco \"No asistió\"?",
    "vistas":["agenda","hoy"],
    "requeridos":[["asistio","plantado","llego","conecto","reunion","cliente"]],
    "excluidos":["reprogramar","mover","confirmar","recordatorio","cancelar"],
    "prioridad":90,
    "contenido":{
      "id":"marcar-no-asistio",
      "titulo":"Cerrar una reunión como \"No asistió\"",
      "resumen":"Úsalo cuando llegó la hora acordada y el lead no participó. Así el resultado queda separado de una cancelación.",
      "duracion":"1 min",
      "pasos":[
        {"titulo":"Confirma que la reunión ya venció","detalle":"Primero valida la fecha, la hora y que no exista una reprogramación acordada."},
        {"titulo":"Pulsa \"Cerrar\" en la tarea","detalle":"En el resultado de una reunión verás las opciones \"Se realizó\" y \"No asistió\"."},
        {"titulo":"Selecciona \"No asistió\"","detalle":"El CRM registrará el no-show en el historial y en las métricas de reuniones."},
        {"titulo":"Deja una siguiente acción","detalle":"Programa el nuevo contacto recomendado para que el lead no quede sin seguimiento."}
      ],
      "advertencia":"Si el lead avisó antes que necesitaba otra fecha, reprograma. \"No asistió\" es un resultado real, no una forma de mover la cita.",
      "accion":{"tipo":"navegar","vista":"agenda","etiqueta":"Revisar mi Agenda"},
      "fuente":"Manual del vendedor · Resultados de reunión · versión aprobada"
    },
    "expresiones":[
      {"texto":"¿Cuándo marco No asistió?","peso":1,"tipo":"canonica"},
      {"texto":"el cliente no vino","peso":0.97,"tipo":"coloquial"},
      {"texto":"me dejaron plantado","peso":0.98,"tipo":"coloquial"},
      {"texto":"me dejo plantado","peso":0.98,"tipo":"coloquial"},
      {"texto":"el cliente no se conecto","peso":0.96,"tipo":"coloquial"},
      {"texto":"no llego a la reunion","peso":0.98,"tipo":"coloquial"}
    ]
  },
  {
    "clave":"corregir-actividad-registrada",
    "pregunta":"¿Puedo borrar una gestión que ya registré?",
    "vistas":["cartera","pipeline","hoy"],
    "requeridos":[["actividad","gestion","historial","llamada"]],
    "excluidos":["pendiente","tarea","agenda","recordatorio","reprogramar","contrato","pago","pagos","cobranza","banco","bancaria"],
    "prioridad":100,
    "contenido":{
      "id":"corregir-actividad-registrada",
      "titulo":"Corregir una gestión que ya quedó en el historial",
      "resumen":"Las actividades registradas no se editan ni se borran porque forman parte de la trazabilidad. La corrección se deja como una nueva Nota.",
      "duracion":"1 min",
      "traduccion":{"lenguajeVendedor":"Borrar una gestión registrada","lenguajeCrm":"Registrar una Nota de corrección"},
      "pasos":[
        {"titulo":"Abre la ficha del lead","detalle":"Busca al contacto y entra a su historial de Actividad."},
        {"titulo":"Pulsa \"Registrar actividad…\"","detalle":"En \"Tipo de actividad\", elige \"Nota\"."},
        {"titulo":"Explica la corrección","detalle":"Indica qué registro fue incorrecto y cuál es el dato correcto; por ejemplo: \"Corrección: la llamada del 17/08 no fue contestada\"."},
        {"titulo":"Registra la Nota","detalle":"La anotación quedará junto al historial original para que supervisión entienda el cambio."}
      ],
      "advertencia":"No registres una segunda gestión con un resultado contrario solo para compensar el error: usa una Nota clara y menciona la fecha del registro corregido.",
      "accion":{"tipo":"navegar","vista":"cartera","etiqueta":"Ir a Leads"},
      "fuente":"Manual del vendedor · Historial de actividad · versión aprobada"
    },
    "expresiones":[
      {"texto":"¿Puedo borrar una gestión que ya registré?","peso":1,"tipo":"canonica"},
      {"texto":"como elimino una actividad","peso":0.99,"tipo":"exacta"},
      {"texto":"registre mal una llamada","peso":0.98,"tipo":"coloquial"},
      {"texto":"me equivoque al poner una gestion","peso":0.98,"tipo":"coloquial"},
      {"texto":"quiero borrar algo del historial","peso":0.98,"tipo":"coloquial"},
      {"texto":"como corrijo una actividad","peso":0.98,"tipo":"coloquial"}
    ]
  },
  {
    "clave":"mover-etapa-lead",
    "pregunta":"¿Cómo cambio un lead de etapa en el proceso?",
    "vistas":["pipeline","cartera","hoy"],
    "requeridos":[["etapa","estado","contactado","interesado","propuesta","nuevo"]],
    "excluidos":["datos","celular","dni","correo","reunion","cita","contrato"],
    "prioridad":110,
    "contenido":{
      "id":"mover-etapa-lead",
      "titulo":"Mover un lead a la etapa que corresponde",
      "resumen":"Actualiza la etapa desde su ficha cuando el avance comercial sea real y completa los datos que el CRM solicite.",
      "duracion":"1 min",
      "traduccion":{"lenguajeVendedor":"Cambiar el estado del prospecto","lenguajeCrm":"Mover el lead de etapa"},
      "pasos":[
        {"titulo":"Abre la ficha del lead","detalle":"Encuéntralo en Pipeline o Leads."},
        {"titulo":"Ubica el recorrido de etapas","detalle":"En la parte superior de la ficha verás la etapa actual y las siguientes opciones."},
        {"titulo":"Selecciona la etapa correcta","detalle":"Pulsa la etapa que representa el avance real y completa la información adicional si se solicita."},
        {"titulo":"Comprueba el cambio","detalle":"Verifica la etapa nueva en la ficha y deja una próxima acción coherente con ella."}
      ],
      "advertencia":"No avances una etapa solo para ordenar tu lista. Algunas gestiones y reuniones ya actualizan la etapa automáticamente.",
      "accion":{"tipo":"navegar","vista":"pipeline","etiqueta":"Ir a Pipeline"},
      "fuente":"Manual del vendedor · Etapas comerciales · versión aprobada"
    },
    "expresiones":[
      {"texto":"¿Cómo cambio un lead de etapa en el proceso?","peso":1,"tipo":"canonica"},
      {"texto":"como lo paso a contactado","peso":0.98,"tipo":"coloquial"},
      {"texto":"quiero moverlo a interesado","peso":0.98,"tipo":"coloquial"},
      {"texto":"como avanzo el lead","peso":0.96,"tipo":"coloquial"},
      {"texto":"donde cambio el estado del prospecto","peso":0.98,"tipo":"coloquial"},
      {"texto":"como lo pongo en propuesta enviada","peso":0.97,"tipo":"coloquial"},
      {"texto":"el lead sigue en nuevo","peso":0.95,"tipo":"coloquial"}
    ]
  },
  {
    "clave":"descartar-lead",
    "pregunta":"¿Cómo descarto un lead que ya no continuará?",
    "vistas":["pipeline","cartera"],
    "requeridos":[["lead","prospecto","contacto","pipeline","interesado","numero"]],
    "excluidos":["tarea","accion","pendiente","actividad","gestion","contrato","cliente"],
    "prioridad":120,
    "contenido":{
      "id":"descartar-lead",
      "titulo":"Descartar un lead con el motivo correcto",
      "resumen":"Retira del proceso comercial a un lead que realmente no continuará y deja el motivo para conservar la trazabilidad.",
      "duracion":"1 min",
      "pasos":[
        {"titulo":"Abre la ficha del lead","detalle":"Confirma que sea el contacto correcto y revisa sus últimas gestiones."},
        {"titulo":"Pulsa \"Descartar\"","detalle":"Selecciona el motivo que mejor explica por qué sale del proceso."},
        {"titulo":"Añade contexto","detalle":"Escribe una nota breve cuando el motivo necesite explicación para supervisión."},
        {"titulo":"Confirma el descarte","detalle":"El lead dejará el pipeline activo y el motivo quedará registrado."}
      ],
      "advertencia":"No uses \"No responde\" sin haber realizado los intentos de contacto requeridos. Si solo debes llamar después, agenda una próxima acción.",
      "accion":{"tipo":"navegar","vista":"pipeline","etiqueta":"Ir a Pipeline"},
      "fuente":"Manual del vendedor · Descarte de leads · versión aprobada"
    },
    "expresiones":[
      {"texto":"¿Cómo descarto un lead que ya no continuará?","peso":1,"tipo":"canonica"},
      {"texto":"como saco un lead del pipeline","peso":0.98,"tipo":"coloquial"},
      {"texto":"el prospecto ya no quiere","peso":0.97,"tipo":"coloquial"},
      {"texto":"como marco que no esta interesado","peso":0.97,"tipo":"coloquial"},
      {"texto":"quiero cerrar un lead perdido","peso":0.97,"tipo":"coloquial"},
      {"texto":"el numero no corresponde","peso":0.94,"tipo":"coloquial"},
      {"texto":"este contacto no va","peso":0.93,"tipo":"coloquial"}
    ]
  },
  {
    "clave":"convertir-lead-cliente",
    "pregunta":"¿Cómo convierto un lead en cliente después del cierre?",
    "vistas":["pipeline","cartera","mi-cartera"],
    "requeridos":[["venta","cierre","cliente","inversionista","inversion","compro","acepto"]],
    "excluidos":["contrato","pdf","archivo","buscar","encontrar","datos"],
    "prioridad":130,
    "contenido":{
      "id":"convertir-lead-cliente",
      "titulo":"Convertir un lead en cliente",
      "resumen":"Haz la conversión cuando la inversión esté confirmada; el CRM solicitará el destino y los datos necesarios para continuar.",
      "duracion":"2 min",
      "pasos":[
        {"titulo":"Abre la ficha del lead cerrado","detalle":"Revisa que los datos personales y el capital acordado estén correctos."},
        {"titulo":"Pulsa \"Convertir a cliente\"","detalle":"Elige el destino de la inversión y completa los datos que solicite el formulario."},
        {"titulo":"Revisa antes de confirmar","detalle":"Valida identidad, monto y producto para evitar correcciones posteriores."},
        {"titulo":"Confirma la conversión","detalle":"El contacto pasará a Mi cartera y podrás continuar con el contrato cuando corresponda."}
      ],
      "advertencia":"No uses la conversión solo para cambiar de etapa. Debe existir un cierre real y los datos deben coincidir con lo acordado.",
      "accion":{"tipo":"navegar","vista":"pipeline","etiqueta":"Buscar el lead"},
      "fuente":"Manual del vendedor · Conversión a cliente · versión aprobada"
    },
    "expresiones":[
      {"texto":"¿Cómo convierto un lead en cliente después del cierre?","peso":1,"tipo":"canonica"},
      {"texto":"ya cerre la venta","peso":0.98,"tipo":"coloquial"},
      {"texto":"como lo paso a cliente","peso":0.98,"tipo":"coloquial"},
      {"texto":"el inversionista ya acepto","peso":0.96,"tipo":"coloquial"},
      {"texto":"como marco que ya compro","peso":0.96,"tipo":"coloquial"},
      {"texto":"quiero convertir el prospecto","peso":0.97,"tipo":"coloquial"},
      {"texto":"donde registro el cierre","peso":0.95,"tipo":"coloquial"}
    ]
  },
  {
    "clave":"buscar-lead-cliente",
    "pregunta":"¿Dónde busco a una persona: en Leads o en Mi cartera?",
    "vistas":["cartera","mi-cartera","pipeline"],
    "requeridos":[["buscar","encuentro","encontrar","aparece","buscador"]],
    "excluidos":["crear","nuevo","convertir","contrato","pdf","actividad","gestion"],
    "prioridad":140,
    "contenido":{
      "id":"buscar-lead-cliente",
      "titulo":"Buscar un lead o un cliente en el lugar correcto",
      "resumen":"Los prospectos activos se consultan en Leads; las personas ya convertidas se encuentran en Mi cartera.",
      "duracion":"1 min",
      "pasos":[
        {"titulo":"Identifica qué estás buscando","detalle":"Si aún es prospecto, ve a Leads. Si ya fue convertido después de una venta, ve a Mi cartera."},
        {"titulo":"Busca por nombre o celular","detalle":"Escribe solo una parte del dato y revisa los resultados disponibles para tu usuario."},
        {"titulo":"Revisa el otro módulo si cambió de estado","detalle":"Un lead convertido deja de aparecer como prospecto activo y pasa a la cartera de clientes."}
      ],
      "advertencia":"Cada vendedor ve únicamente la información permitida para su rol y asignación. Si debería aparecer y no aparece, deriva el caso con el nombre y celular exactos.",
      "accion":{"tipo":"navegar","vista":"cartera","etiqueta":"Buscar en Leads"},
      "fuente":"Manual del vendedor · Búsqueda de contactos · versión aprobada"
    },
    "expresiones":[
      {"texto":"¿Dónde busco a una persona: en Leads o en Mi cartera?","peso":1,"tipo":"canonica"},
      {"texto":"no encuentro al cliente","peso":0.98,"tipo":"coloquial"},
      {"texto":"donde busco un prospecto","peso":0.98,"tipo":"coloquial"},
      {"texto":"el buscador no encuentra a la persona","peso":0.98,"tipo":"coloquial"},
      {"texto":"como busco por celular","peso":0.97,"tipo":"coloquial"},
      {"texto":"donde estan mis clientes","peso":0.96,"tipo":"coloquial"},
      {"texto":"no me aparece el lead","peso":0.97,"tipo":"coloquial"}
    ]
  },
  {
    "clave":"contacto-ya-existe",
    "pregunta":"¿Qué hago si el CRM dice que el celular ya existe o está ocupado?",
    "vistas":["hoy","cartera","pipeline"],
    "requeridos":[["existe","ocupado","duplicado","registrado","guardar"]],
    "excluidos":["buscar","encontrar","contrato","pdf","actividad","gestion"],
    "prioridad":150,
    "contenido":{
      "id":"contacto-ya-existe",
      "titulo":"Resolver un contacto que ya existe en el CRM",
      "resumen":"La validación evita duplicados y protege la asignación vigente. Sigue el estado que muestre el CRM antes de intentar registrarlo otra vez.",
      "duracion":"1 min",
      "pasos":[
        {"titulo":"Verifica el celular","detalle":"Confirma que tenga nueve dígitos y que no exista un error de escritura."},
        {"titulo":"Lee el estado de disponibilidad","detalle":"El CRM indicará si el contacto ya está asignado, si existe o si puede registrarse."},
        {"titulo":"Sigue la acción disponible","detalle":"Abre el contacto existente o respeta la asignación informada; registra uno nuevo solo si el sistema lo permite."}
      ],
      "advertencia":"No cambies un dígito ni uses otro número para saltar la validación. Eso crea duplicados y rompe la trazabilidad comercial.",
      "accion":{"tipo":"nuevo_lead","etiqueta":"Revisar Nuevo lead"},
      "fuente":"Manual del vendedor · Disponibilidad de contactos · versión aprobada"
    },
    "expresiones":[
      {"texto":"¿Qué hago si el CRM dice que el celular ya existe o está ocupado?","peso":1,"tipo":"canonica"},
      {"texto":"no me deja crear el lead","peso":0.96,"tipo":"coloquial"},
      {"texto":"el numero ya esta registrado","peso":0.98,"tipo":"coloquial"},
      {"texto":"el contacto aparece ocupado","peso":0.98,"tipo":"coloquial"},
      {"texto":"me sale celular duplicado","peso":0.98,"tipo":"coloquial"},
      {"texto":"ya existe ese prospecto","peso":0.97,"tipo":"coloquial"},
      {"texto":"por que no puedo guardar el contacto","peso":0.95,"tipo":"coloquial"}
    ]
  },
  {
    "clave":"crear-contrato",
    "pregunta":"¿Cómo creo el contrato de un cliente?",
    "vistas":["mi-cartera"],
    "requeridos":[["contrato","documento"]],
    "excluidos":["pdf","archivo","fallo","pendiente","reintentar","descargar","cancelar","anular","borrar","eliminar"],
    "prioridad":160,
    "contenido":{
      "id":"crear-contrato",
      "titulo":"Crear el contrato después de la conversión",
      "resumen":"Inicia el contrato desde el cliente ya convertido, revisa las condiciones y confirma una sola vez.",
      "duracion":"2 min",
      "pasos":[
        {"titulo":"Entra a Mi cartera","detalle":"Busca al cliente convertido y abre su detalle."},
        {"titulo":"Pulsa \"Crear contrato\"","detalle":"Completa las condiciones y los datos solicitados por el formulario."},
        {"titulo":"Revisa la información","detalle":"Valida identidad, producto, capital y datos bancarios antes de confirmar."},
        {"titulo":"Confirma una sola vez","detalle":"Espera la respuesta del CRM; luego revisa el estado del contrato y de su PDF."}
      ],
      "advertencia":"Si el contrato ya existe y solo falló el archivo, usa \"Reintentar PDF\". No crees un segundo contrato.",
      "accion":{"tipo":"navegar","vista":"mi-cartera","etiqueta":"Ir a Mi cartera"},
      "fuente":"Manual del vendedor · Creación de contratos · versión aprobada"
    },
    "expresiones":[
      {"texto":"¿Cómo creo el contrato de un cliente?","peso":1,"tipo":"canonica"},
      {"texto":"donde genero el contrato","peso":0.98,"tipo":"coloquial"},
      {"texto":"ya converti al cliente y ahora que hago","peso":0.94,"tipo":"coloquial"},
      {"texto":"como saco el documento de inversion","peso":0.96,"tipo":"coloquial"},
      {"texto":"quiero hacer el contrato","peso":0.98,"tipo":"coloquial"},
      {"texto":"donde pongo los datos del contrato","peso":0.96,"tipo":"coloquial"}
    ]
  },
  {
    "clave":"reintentar-pdf",
    "pregunta":"¿Qué hago si falló el PDF del contrato?",
    "vistas":["mi-cartera"],
    "requeridos":[["pdf","archivo"]],
    "excluidos":["crear","generar","hacer","nuevo"],
    "prioridad":170,
    "contenido":{
      "id":"reintentar-pdf",
      "titulo":"Recuperar un contrato cuyo PDF quedó pendiente",
      "resumen":"El contrato ya creado no se duplica. Reintenta únicamente el archivo desde el contrato existente.",
      "duracion":"2 min",
      "pasos":[
        {"titulo":"Entra a tu Cartera","detalle":"Busca al cliente y abre el contrato que ya fue confirmado por el servidor."},
        {"titulo":"Revisa el estado documental","detalle":"El detalle indicará si el PDF sigue pendiente, está sellado o requiere revisión de integridad."},
        {"titulo":"Usa \"Reintentar PDF\"","detalle":"Si el estado lo permite, reintenta el archivo desde ese mismo contrato. No vuelvas a crear el contrato."}
      ],
      "advertencia":"Si aparece \"bloqueado por integridad\", no reintentes ni generes otro contrato: solicita revisión administrativa.",
      "accion":{"tipo":"navegar","vista":"mi-cartera","etiqueta":"Ir a Mi cartera"},
      "fuente":"Manual del vendedor · Contratos y PDF · versión aprobada"
    },
    "expresiones":[
      {"texto":"¿Qué hago si falló el PDF del contrato?","peso":1,"tipo":"canonica"},
      {"texto":"no salio el pdf","peso":0.98,"tipo":"coloquial"},
      {"texto":"fallo el contrato","peso":0.92,"tipo":"coloquial"},
      {"texto":"no puedo descargar el contrato","peso":0.96,"tipo":"coloquial"},
      {"texto":"el archivo quedo pendiente","peso":0.98,"tipo":"coloquial"},
      {"texto":"quiero reintentar el pdf","peso":0.98,"tipo":"coloquial"},
      {"texto":"como reintento el pdf","peso":0.98,"tipo":"coloquial"}
    ]
  }
]
$catalogo$::jsonb)
  loop
    insert into private.ayuda_intenciones (
      clave,
      version,
      pregunta,
      contenido,
      vistas,
      grupos_obligatorios,
      terminos_excluidos,
      prioridad,
      estado,
      publicado_en
    )
    values (
      v_articulo ->> 'clave',
      1,
      v_articulo ->> 'pregunta',
      v_articulo -> 'contenido',
      array(select jsonb_array_elements_text(v_articulo -> 'vistas')),
      v_articulo -> 'requeridos',
      array(select jsonb_array_elements_text(v_articulo -> 'excluidos')),
      (v_articulo ->> 'prioridad')::smallint,
      'publicado',
      clock_timestamp()
    )
    returning id into v_intencion_id;

    for v_expresion in
      select value
      from jsonb_array_elements(v_articulo -> 'expresiones')
    loop
      insert into private.ayuda_expresiones (
        intencion_id,
        texto,
        peso,
        tipo
      )
      values (
        v_intencion_id,
        v_expresion ->> 'texto',
        (v_expresion ->> 'peso')::numeric,
        v_expresion ->> 'tipo'
      );
    end loop;
  end loop;
end;
$seed$;

insert into private.ayuda_reglas_aclaracion (
  clave, todos, alguno, ninguno, titulo, detalle, opciones, prioridad
)
values
  (
    'eliminar-sin-objeto',
    '{}'::text[],
    array['eliminar','borrar','quitar','sacar','anular','cancelar'],
    array[
      'accion','tarea','pendiente','llamada','whatsapp','recordatorio','reunion',
      'cita','actividad','gestion','historial','lead','prospecto','contacto',
      'cliente','contrato','pdf','datos','celular','dni','correo','etapa'
    ],
    '¿Qué quieres quitar?',
    'En el CRM no es lo mismo anular una acción pendiente, corregir una gestión registrada o descartar un lead.',
    '[
      {"etiqueta":"Una acción que todavía está pendiente","detalle":"Una llamada, WhatsApp, tarea o reunión que ya no realizarás.","consulta":"como elimino una accion"},
      {"etiqueta":"Una gestión ya registrada","detalle":"Una actividad que quedó guardada por error en el historial.","consulta":"como elimino una actividad"},
      {"etiqueta":"Un lead que no continuará","detalle":"Un prospecto que debe salir del proceso comercial.","consulta":"como descarto un lead que ya no continuará"}
    ]'::jsonb,
    10
  ),
  (
    'cambiar-sin-objeto',
    '{}'::text[],
    array['cambiar','corregir','mover','actualizar','editar'],
    array[
      'datos','celular','numero','nombre','correo','dni','capital','reunion','cita',
      'fecha','etapa','estado','contactado','interesado','propuesta','actividad',
      'gestion','historial','contrato','pdf'
    ],
    '¿Qué necesitas cambiar?',
    'Indica qué elemento cambió para mostrarte los pasos correctos.',
    '[
      {"etiqueta":"Los datos de un lead","detalle":"Nombre, celular, DNI, correo o capital.","consulta":"como corrijo los datos de un lead"},
      {"etiqueta":"La fecha de una reunión","detalle":"El cliente pidió otro día u otra hora.","consulta":"como cambio la fecha de una cita"},
      {"etiqueta":"La etapa del lead","detalle":"El prospecto avanzó realmente en el proceso.","consulta":"como cambio un lead de etapa en el proceso"}
    ]'::jsonb,
    20
  ),
  (
    'realizado-sin-objeto',
    '{}'::text[],
    array['hice','termine','complete','cerrar','marcar'],
    array[
      'accion','tarea','pendiente','llamada','whatsapp','reunion','cita',
      'actividad','gestion','contacto','cliente','lead','contrato','pdf'
    ],
    '¿Qué fue lo que realizaste?',
    'Necesito distinguir si vas a cerrar una acción agendada o registrar el resultado de un contacto.',
    '[
      {"etiqueta":"Una acción de mi Agenda","detalle":"Una llamada, tarea o reunión que estaba pendiente.","consulta":"ya hice la accion"},
      {"etiqueta":"Un contacto con el lead","detalle":"Llamaste o escribiste y quieres dejar el resultado.","consulta":"como marco que ya llame"}
    ]'::jsonb,
    30
  );

create or replace function private.consulta_contiene_termino_ayuda(
  p_consulta_normalizada text,
  p_termino text
)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $function$
  select position(
    ' ' || private.normalizar_texto_ayuda(p_termino) || ' '
    in ' ' || coalesce(p_consulta_normalizada, '') || ' '
  ) > 0;
$function$;

create or replace function private.cumple_grupos_ayuda(
  p_consulta_normalizada text,
  p_grupos jsonb
)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $function$
  select not exists (
    select 1
    from jsonb_array_elements(coalesce(p_grupos, '[]'::jsonb)) as grupo(valor)
    where jsonb_typeof(grupo.valor) <> 'array'
       or not exists (
         select 1
         from jsonb_array_elements_text(grupo.valor) as termino(valor)
         where private.consulta_contiene_termino_ayuda(
           p_consulta_normalizada,
           termino.valor
         )
       )
  );
$function$;

-- Cobertura léxica conservadora. Un candidato solo sobrevive si cada palabra
-- significativa de la consulta aparece en el vocabulario aprobado de esa
-- intención, comparte su raíz en español o es una errata trigram cercana.
-- Esto evita que un término nuevo
-- (p. ej. "judicial" en "acción judicial") sea ignorado por un score alto.
create or replace function private.vocabulario_cubre_consulta_ayuda(
  p_consulta_normalizada text,
  p_vocabulario_normalizado text
)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $function$
  select not exists (
    select 1
    from unnest(regexp_split_to_array(coalesce(p_consulta_normalizada, ''), '[[:space:]]+'))
         as consulta(token)
    where (char_length(consulta.token) >= 3 or consulta.token = 'no')
      and consulta.token <> all(array[
        'ahora','algo','aqui','como','cuando','donde','este','esta','esto',
        'hacer','hago','hoy','luego','necesito','para','pero','porque','puede',
        'puedo','quiere','quiero','saber','tambien','tengo','tiene','toda','todo',
        'una','uno','unos','unas','que','con','por','del','los','las','les','sus',
        'ese','esa','otra','otro','antes','despues','muy','voy','sea','fue','hay'
      ]::text[])
      and not (
        to_tsvector('spanish'::regconfig, coalesce(p_vocabulario_normalizado, ''))
          @@ plainto_tsquery('spanish'::regconfig, consulta.token)
      )
      and not exists (
        select 1
        from unnest(regexp_split_to_array(coalesce(p_vocabulario_normalizado, ''), '[[:space:]]+'))
             as expresion(token)
        where expresion.token = consulta.token
           or (
             char_length(consulta.token) >= 5
             and char_length(expresion.token) >= 5
             and extensions.similarity(consulta.token, expresion.token) >= 0.50
           )
      )
  );
$function$;

create or replace function private.registrar_consulta_ayuda(
  p_usuario_id uuid,
  p_vista text,
  p_consulta text,
  p_resultado text,
  p_intencion_id bigint,
  p_puntuacion numeric,
  p_segunda_puntuacion numeric,
  p_motivo text
)
returns void
language plpgsql
volatile
set search_path = ''
as $function$
begin
  -- Retención dura y oportunista: cada consulta elimina primero lo vencido.
  delete from private.ayuda_consultas
  where retener_hasta <= statement_timestamp();

  insert into private.ayuda_consultas (
    usuario_id,
    vista,
    consulta_redactada,
    longitud,
    resultado,
    intencion_id,
    puntuacion,
    segunda_puntuacion,
    motivo
  )
  values (
    p_usuario_id,
    p_vista,
    private.redactar_consulta_ayuda(p_consulta),
    char_length(trim(p_consulta))::smallint,
    p_resultado,
    p_intencion_id,
    p_puntuacion,
    p_segunda_puntuacion,
    p_motivo
  );
end;
$function$;

revoke all on function private.consulta_contiene_termino_ayuda(text, text)
  from public, anon, authenticated, service_role;
revoke all on function private.cumple_grupos_ayuda(text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.vocabulario_cubre_consulta_ayuda(text, text)
  from public, anon, authenticated, service_role;
revoke all on function private.registrar_consulta_ayuda(
  uuid, text, text, text, bigint, numeric, numeric, text
) from public, anon, authenticated, service_role;

-- Una versión publicada puede retirarse, pero su texto y sus reglas no se
-- reescriben. Las correcciones se publican como una versión nueva.
create or replace function private.proteger_version_publicada_ayuda()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' and old.estado = 'publicado' then
    raise exception 'Una guía publicada no se elimina; debe retirarse.'
      using errcode = '23514';
  end if;

  if tg_op = 'UPDATE'
     and old.estado = 'publicado'
     and (
       new.clave is distinct from old.clave
       or new.version is distinct from old.version
       or new.pregunta is distinct from old.pregunta
       or new.contenido is distinct from old.contenido
       or new.vistas is distinct from old.vistas
       or new.grupos_obligatorios is distinct from old.grupos_obligatorios
       or new.terminos_excluidos is distinct from old.terminos_excluidos
       or new.prioridad is distinct from old.prioridad
       or new.publicado_en is distinct from old.publicado_en
     ) then
    raise exception 'El contenido publicado es inmutable; cree una versión nueva.'
      using errcode = '23514';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

create trigger ayuda_intenciones_proteger_publicada
before update or delete on private.ayuda_intenciones
for each row execute function private.proteger_version_publicada_ayuda();

revoke all on function private.proteger_version_publicada_ayuda()
  from public, anon, authenticated, service_role;

-- ============================================================================
-- RPC 1: inicio contextual (el contexto solo ordena sugerencias)
-- ============================================================================

create or replace function crm.ayuda_vendedor_inicio(p_vista text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_preguntas jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  if v_uid is null or v_rol is null then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_vista is null or not (p_vista = any(array[
    'hoy','alertas','conversiones','ranking-vendedores','reuniones','metas',
    'rendimiento','capital-cierres','pipeline','cartera','agenda','mi-cartera',
    'repartir','equipo','config','config-usuarios','config-productos',
    'config-metas','config-sla'
  ]::text[])) then
    raise exception 'Vista de ayuda no válida' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(s.pregunta order by s.relacionada desc, s.prioridad, s.clave), '[]'::jsonb)
  into v_preguntas
  from (
    select
      i.pregunta,
      p_vista = any(i.vistas) as relacionada,
      i.prioridad,
      i.clave
    from private.ayuda_intenciones i
    where i.estado = 'publicado'
    order by relacionada desc, i.prioridad, i.clave
    limit 6
  ) s;

  return jsonb_build_object('version', 1, 'preguntas', v_preguntas);
end;
$function$;

comment on function crm.ayuda_vendedor_inicio(text) is
  'Preguntas aprobadas del manual. La vista solo ordena sugerencias; nunca autoriza una respuesta.';

revoke all on function crm.ayuda_vendedor_inicio(text)
  from public, anon, authenticated, service_role;
grant execute on function crm.ayuda_vendedor_inicio(text) to authenticated;

-- ============================================================================
-- RPC 2: decisión conservadora exacta + FTS español + pg_trgm
-- ============================================================================

create or replace function crm.consultar_ayuda_vendedor(
  p_consulta text,
  p_vista text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_limpia text := trim(coalesce(p_consulta, ''));
  v_normalizada text;
  v_tsquery tsquery;
  v_regla record;
  v_exacta record;
  v_ids bigint[];
  v_puntuaciones numeric[];
  v_claves text[];
  v_top numeric;
  v_segunda numeric;
  v_contenido jsonb;
  v_opciones jsonb;
  v_payload jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  if v_uid is null or v_rol is null then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_vista is null or not (p_vista = any(array[
    'hoy','alertas','conversiones','ranking-vendedores','reuniones','metas',
    'rendimiento','capital-cierres','pipeline','cartera','agenda','mi-cartera',
    'repartir','equipo','config','config-usuarios','config-productos',
    'config-metas','config-sla'
  ]::text[])) then
    raise exception 'Vista de ayuda no válida' using errcode = '22023';
  end if;

  if char_length(v_limpia) not between 2 and 240 then
    raise exception 'La consulta debe tener entre 2 y 240 caracteres'
      using errcode = '22023';
  end if;

  v_normalizada := private.normalizar_consulta_ayuda(v_limpia);
  if char_length(v_normalizada) < 2 then
    v_payload := jsonb_build_object(
      'version', 1,
      'tipo', 'sin_resultado',
      'consulta', v_limpia
    );
    perform private.registrar_consulta_ayuda(
      v_uid, p_vista, v_limpia, 'sin_resultado', null, null, null,
      'consulta_sin_terminos'
    );
    return v_payload;
  end if;

  -- Las ambigüedades editoriales conocidas se resuelven antes de buscar.
  select r.*
  into v_regla
  from private.ayuda_reglas_aclaracion r
  where r.activa
    and not exists (
      select 1
      from unnest(r.todos) as requerido(termino)
      where not private.consulta_contiene_termino_ayuda(
        v_normalizada,
        requerido.termino
      )
    )
    and exists (
      select 1
      from unnest(r.alguno) as disparador(termino)
      where private.consulta_contiene_termino_ayuda(
        v_normalizada,
        disparador.termino
      )
    )
    and not exists (
      select 1
      from unnest(r.ninguno) as objeto(termino)
      where private.consulta_contiene_termino_ayuda(
        v_normalizada,
        objeto.termino
      )
    )
  order by r.prioridad, r.clave
  limit 1;

  if found then
    v_payload := jsonb_build_object(
      'version', 1,
      'tipo', 'aclaracion',
      'aclaracion', jsonb_build_object(
        'titulo', v_regla.titulo,
        'detalle', v_regla.detalle,
        'opciones', v_regla.opciones
      )
    );
    perform private.registrar_consulta_ayuda(
      v_uid, p_vista, v_limpia, 'aclaracion', null, null, null,
      'regla:' || v_regla.clave
    );
    return v_payload;
  end if;

  -- Una frase editorial exacta es la única resolución que no necesita score.
  select i.id, i.clave, i.contenido
  into v_exacta
  from private.ayuda_expresiones e
  join private.ayuda_intenciones i on i.id = e.intencion_id
  where e.texto_normalizado = v_normalizada
    and i.estado = 'publicado'
  limit 1;

  if found then
    v_payload := jsonb_build_object(
      'version', 1,
      'tipo', 'respuesta',
      'respuesta', v_exacta.contenido
    );
    perform private.registrar_consulta_ayuda(
      v_uid, p_vista, v_limpia, 'respuesta', v_exacta.id, 1, null,
      'expresion_exacta:' || v_exacta.clave
    );
    return v_payload;
  end if;

  v_tsquery := websearch_to_tsquery('spanish'::regconfig, v_normalizada);

  with vocabularios as materialized (
    select
      e.intencion_id,
      string_agg(e.texto_normalizado, ' ' order by e.id) as texto
    from private.ayuda_expresiones e
    group by e.intencion_id
  ),
  expresiones_candidatas as (
    select
      i.id,
      i.clave,
      i.prioridad,
      greatest(
        extensions.similarity(e.texto_normalizado, v_normalizada),
        extensions.strict_word_similarity(e.texto_normalizado, v_normalizada),
        extensions.strict_word_similarity(v_normalizada, e.texto_normalizado)
      )::numeric as similitud,
      case
        when e.vector_busqueda @@ v_tsquery
        then ts_rank_cd(e.vector_busqueda, v_tsquery, 32)::numeric
        else 0::numeric
      end as rango_fts,
      e.peso
    from private.ayuda_expresiones e
    join private.ayuda_intenciones i on i.id = e.intencion_id
    join vocabularios v on v.intencion_id = i.id
    where i.estado = 'publicado'
      and private.cumple_grupos_ayuda(v_normalizada, i.grupos_obligatorios)
      and private.vocabulario_cubre_consulta_ayuda(
        v_normalizada,
        v.texto
      )
      and not exists (
        select 1
        from unnest(i.terminos_excluidos) as excluido(termino)
        where private.consulta_contiene_termino_ayuda(
          v_normalizada,
          excluido.termino
        )
      )
      and (
        e.vector_busqueda @@ v_tsquery
        or e.texto_normalizado operator(extensions.%) v_normalizada
      )
  ),
  puntuadas as (
    select
      c.id,
      c.clave,
      c.prioridad,
      least(
        1::numeric,
        0.82::numeric * c.similitud
        + 0.14::numeric * least(1::numeric, c.rango_fts * 8::numeric)
        + 0.04::numeric * c.peso
      ) as puntuacion
    from expresiones_candidatas c
  ),
  por_intencion as (
    select
      p.id,
      p.clave,
      min(p.prioridad) as prioridad,
      max(p.puntuacion) as puntuacion
    from puntuadas p
    group by p.id, p.clave
  ),
  primeras as (
    select p.*
    from por_intencion p
    order by p.puntuacion desc, p.prioridad, p.clave
    limit 3
  )
  select
    array_agg(p.id order by p.puntuacion desc, p.prioridad, p.clave),
    array_agg(p.puntuacion order by p.puntuacion desc, p.prioridad, p.clave),
    array_agg(p.clave order by p.puntuacion desc, p.prioridad, p.clave)
  into v_ids, v_puntuaciones, v_claves
  from primeras p;

  v_top := v_puntuaciones[1];
  v_segunda := v_puntuaciones[2];

  -- Umbral y margen son independientes: una opción fuerte pero empatada
  -- pregunta antes de actuar. La pantalla actual no modifica ninguno.
  if v_top >= 0.61
     and (v_segunda is null or v_top - v_segunda >= 0.12) then
    select i.contenido into v_contenido
    from private.ayuda_intenciones i
    where i.id = v_ids[1];

    v_payload := jsonb_build_object(
      'version', 1,
      'tipo', 'respuesta',
      'respuesta', v_contenido
    );
    perform private.registrar_consulta_ayuda(
      v_uid, p_vista, v_limpia, 'respuesta', v_ids[1], v_top, v_segunda,
      'ranking_con_margen:' || v_claves[1]
    );
    return v_payload;
  end if;

  if v_top >= 0.56
     and v_segunda >= 0.56
     and v_top - v_segunda < 0.12 then
    select jsonb_agg(
      jsonb_build_object(
        'etiqueta', i.pregunta,
        'detalle', i.contenido ->> 'resumen',
        'consulta', i.pregunta
      ) order by array_position(v_ids, i.id)
    )
    into v_opciones
    from private.ayuda_intenciones i
    where i.id = any(v_ids[1:2]);

    v_payload := jsonb_build_object(
      'version', 1,
      'tipo', 'aclaracion',
      'aclaracion', jsonb_build_object(
        'titulo', 'Encontré más de una posibilidad',
        'detalle', 'Elige la situación que se parece a lo que necesitas para no aplicar la guía equivocada.',
        'opciones', v_opciones
      )
    );
    perform private.registrar_consulta_ayuda(
      v_uid, p_vista, v_limpia, 'aclaracion', null, v_top, v_segunda,
      'ranking_sin_margen:' || coalesce(v_claves[1], '-') || ':' || coalesce(v_claves[2], '-')
    );
    return v_payload;
  end if;

  v_payload := jsonb_build_object(
    'version', 1,
    'tipo', 'sin_resultado',
    'consulta', v_limpia
  );
  perform private.registrar_consulta_ayuda(
    v_uid, p_vista, v_limpia, 'sin_resultado', null, v_top, v_segunda,
    case when v_top is null then 'sin_candidatos' else 'evidencia_insuficiente' end
  );
  return v_payload;
end;
$function$;

comment on function crm.consultar_ayuda_vendedor(text, text) is
  'Motor V1 del manual: exacto, FTS español y pg_trgm con términos obligatorios, exclusiones, umbral y margen. Nunca usa la vista para autorizar una respuesta.';

revoke all on function crm.consultar_ayuda_vendedor(text, text)
  from public, anon, authenticated, service_role;
grant execute on function crm.consultar_ayuda_vendedor(text, text) to authenticated;

commit;
