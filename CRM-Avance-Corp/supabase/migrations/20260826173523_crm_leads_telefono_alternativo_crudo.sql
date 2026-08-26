-- ---------------------------------------------------------------------------
-- El segundo numero que NO se pudo leer tampoco se tira
-- ---------------------------------------------------------------------------
-- DECISION DE MIGUEL (2026-08-26): «que siempre todos los leads tengan ese
-- numero alternativo, asi ese numero sea errado».
--
-- No se puede cumplir al pie de la letra —el diagnostico del origen midio que el
-- 84,2 % de las personas escribe el MISMO numero en las dos columnas, asi que en
-- esas filas no hay un segundo numero que dar— pero si se puede cumplir lo que
-- hay detras del pedido: que NADA de lo que la persona escribio se pierda en
-- silencio, y que el vendedor nunca se quede con la duda de si el CRM se comio un
-- dato o si nunca lo hubo.
--
-- Son 299 filas de 14.310 (2,1 %) las que hoy traen algo escrito en la columna
-- del segundo numero que no es un telefono reconocible: un numero a medias, con
-- un digito de mas, con una anotacion pegada. Hasta hoy se tiraban.
--
-- QUE HACE. Una columna SIN reglas de formato que guarda ese texto tal como
-- llego. La columna canonica (`telefono_alternativo`) sigue limpia, que es lo
-- que hace que los enlaces de llamar y de WhatsApp funcionen; esta otra es para
-- que un humano la lea y la corrija.
--
-- LAS DOS SON EXCLUYENTES, y hay un CHECK que lo obliga: si el numero se pudo
-- entender vive en la canonica y esta queda en null. Sin esa regla, la ficha
-- tendria que decidir cual de las dos pinta y acabaria mostrando dos «segundos
-- numeros» distintos para el mismo lead.
--
-- El tope de 40 caracteres es un guardia de cordura, no una validacion: cabe
-- cualquier cosa que alguien escriba en una casilla de telefono, y evita que un
-- parrafo entero entre por aqui.
-- ---------------------------------------------------------------------------

begin;

set local lock_timeout = '5s';

-- ---------------------------------------------------------------------------
-- 0. Preflight
-- ---------------------------------------------------------------------------
do $preflight$
begin
  if not exists (
    select 1 from pg_catalog.pg_attribute
     where attrelid = 'crm.leads'::regclass
       and attname = 'telefono_alternativo'
       and not attisdropped
  ) then
    raise exception 'Falta crm.leads.telefono_alternativo: aplicar antes 20260824154218.';
  end if;
  if exists (
    select 1 from pg_catalog.pg_attribute
     where attrelid = 'crm.leads'::regclass
       and attname = 'telefono_alternativo_crudo'
       and not attisdropped
  ) then
    raise exception 'crm.leads.telefono_alternativo_crudo ya existe: esta migracion ya se aplico.';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. La columna
-- ---------------------------------------------------------------------------
alter table crm.leads
  add column telefono_alternativo_crudo text;

alter table crm.leads
  add constraint leads_telefono_alternativo_crudo_cordura
  check (
    telefono_alternativo_crudo is null
    or (
      -- Ni vacio ni solo espacios: «no hay dato» se escribe NULL, no ''. Dos
      -- formas de decir lo mismo obligan a la ficha a comprobar las dos, y
      -- tarde o temprano una se olvida.
      btrim(telefono_alternativo_crudo) <> ''
      and length(telefono_alternativo_crudo) <= 40
    )
  ) not valid;

alter table crm.leads
  add constraint leads_telefono_alternativo_excluyentes
  check (
    telefono_alternativo is null or telefono_alternativo_crudo is null
  ) not valid;

alter table crm.leads validate constraint leads_telefono_alternativo_crudo_cordura;
alter table crm.leads validate constraint leads_telefono_alternativo_excluyentes;

comment on column crm.leads.telefono_alternativo_crudo is
  'El segundo numero TAL COMO LO ESCRIBIO la persona, cuando no se pudo entender como telefono. Existe para que nada se pierda en silencio (decision de Miguel 2026-08-26). Excluyente con telefono_alternativo: si el numero se pudo canonizar vive alli y este queda null. No es marcable — la ficha lo muestra como «sin validar» para que un humano lo lea y lo corrija.';

-- ---------------------------------------------------------------------------
-- 2. Postflight — EJECUTANDO los CHECK sobre una copia temporal
-- ---------------------------------------------------------------------------
-- Misma tecnica que 20260826154500: tabla TEMPORAL con `including constraints`,
-- que hereda los CHECK reales del catalogo y ningun trigger. Insertar en
-- `crm.leads` dispararia la auditoria y borrar despues exige bajar los siete
-- candados nombrados que protegen la tabla en produccion.
do $postflight$
declare
  v_probe record;
begin
  create temp table postflight_crudo
    (like crm.leads including constraints including defaults)
    on commit drop;

  for v_probe in
    select * from (values
      -- (canonico, crudo, debe_entrar)
      (null,            '99988 7',      true),   -- el caso que esta migracion viene a salvar
      (null,            '912-34',       true),
      (null,            'llamar al 9 8', true),  -- con anotacion pegada
      ('+51987654321',  null,           true),   -- se entendio: vive en la canonica
      (null,            null,           true),   -- el origen no dio nada
      ('+51987654321',  '99988 7',      false),  -- LAS DOS: ambiguo, prohibido
      (null,            '',             false),  -- vacio: «no hay dato» se escribe NULL
      (null,            '   ',          false),  -- solo espacios: lo mismo
      (null, repeat('9', 41),           false)   -- pasado del tope de cordura
    ) as t(canonico, crudo, debe_entrar)
  loop
    begin
      insert into postflight_crudo (nombre_completo, telefono, telefono_alternativo,
                                    telefono_alternativo_crudo,
                                    origen, etapa, monto_estimado, moneda)
      values ('probe', '+51900000001', v_probe.canonico, v_probe.crudo,
              'otro', 'nuevo', 1, 'PEN');
      if not v_probe.debe_entrar then
        raise exception 'postflight: se acepto una combinacion invalida: canonico=% crudo=%',
          coalesce(v_probe.canonico, 'NULL'), coalesce(v_probe.crudo, 'NULL');
      end if;
    exception
      when check_violation then
        if v_probe.debe_entrar then
          raise exception 'postflight: se rechazo una combinacion que debe entrar: canonico=% crudo=%',
            coalesce(v_probe.canonico, 'NULL'), coalesce(v_probe.crudo, 'NULL');
        end if;
    end;
  end loop;

  -- Que la copia temporal se llevara los DOS CHECK nuevos. Sin esto, si
  -- `including constraints` fallara, todos los casos entrarian y el postflight
  -- cantaria verde sin haber probado nada.
  if (select count(*) from pg_catalog.pg_constraint
       where conrelid = 'postflight_crudo'::regclass
         and pg_catalog.pg_get_constraintdef(oid) like '%telefono_alternativo_crudo%') < 2 then
    raise exception 'postflight: la tabla de prueba no heredo los CHECK — la prueba no probo nada';
  end if;
end;
$postflight$;

commit;
