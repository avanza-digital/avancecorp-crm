-- ---------------------------------------------------------------------------
-- `private.canonizar_contacto` — la regla del telefono, en SQL
-- ---------------------------------------------------------------------------
-- Es el SEXTO espejo de la misma regla, y el primero que vive en la base como
-- funcion (los otros: telefonos.ts del conector, validacion.ts del front,
-- reconocerTelefono() del puente, el CHECK leads_telefono_alternativo_formato y
-- el regex del alta manual). Se crea aparte, con nombre propio y probada, para
-- que la 20260826182500 pueda LLAMARLA en vez de re-escribir el criterio dentro
-- de una funcion de 200 lineas — que es como los espejos empiezan a divergir.
--
-- QUE NO ES. NO sustituye a `private.normalizar_telefono`, que sigue intacta y
-- la sigue usando el trigger de `crm.leads` y todo el resto del CRM. Aquella
-- responde «como se guarda este numero»; esta responde «es esto un telefono, y
-- de que tipo». Tocar la otra moveria la huella con la que el CRM decide que dos
-- leads son el mismo — dedup, reparto y conversion — y esa es exactamente la
-- razon por la que Miguel eligio la opcion A (2026-08-26).
--
-- DEVUELVE (canonico, clase, movil) o NULL si no hay telefono que rescatar:
--   celular_pe      +51 9XXXXXXXX
--   fijo_pe         +51 XXXXXXXX   (ocho digitos nacionales, y SOLO si viene
--                                   MARCADO: con +51/0051 o con el 0 de larga
--                                   distancia — ocho digitos pelados son un DNI)
--   internacional   +CC…           (E.164: 8 a 15 digitos, el primero 1-9)
-- ---------------------------------------------------------------------------

begin;

set local lock_timeout = '5s';

create or replace function private.canonizar_contacto(p text)
returns table (e164 text, clase text, movil boolean)
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_bruto text := pg_catalog.btrim(coalesce(p, ''));
  v_digitos text;
  v_internacional boolean;
  v_sin_salida text;
  v_nacional text;
  v_declara_peru boolean;
  v_n text;
  v_sin_cero text;
begin
  if v_bruto = '' then return; end if;
  -- Un correo metido en la casilla del telefono es otro dato en el sitio
  -- equivocado, no un numero roto.
  if pg_catalog.strpos(v_bruto, '@') > 0 then return; end if;

  v_digitos := pg_catalog.regexp_replace(v_bruto, '[^0-9]', '', 'g');
  if v_digitos = '' then return; end if;

  v_internacional := pg_catalog.left(v_bruto, 1) = '+'
                     or pg_catalog.left(v_digitos, 2) = '00';
  v_sin_salida := pg_catalog.regexp_replace(v_digitos, '^00', '');

  v_nacional := case when pg_catalog.left(v_sin_salida, 2) = '51'
                     then pg_catalog.substr(v_sin_salida, 3)
                     else v_sin_salida end;
  -- Todo lo que dice ser peruano se juzga con la vara peruana: si no tiene la
  -- forma exacta NO se cuela por la puerta internacional. Sin esto,
  -- '+51123456789' entraria como numero valido y nadie podria llamarlo nunca.
  v_declara_peru := pg_catalog.left(v_sin_salida, 2) = '51'
                    and pg_catalog.length(v_nacional) >= 8;

  if v_declara_peru or not v_internacional then
    v_n := case when v_declara_peru then v_nacional else v_sin_salida end;

    if v_n ~ '^9[0-9]{8}$' then
      return query select '+51' || v_n, 'celular_pe'::text, true;
      return;
    end if;

    -- ⚠️ UN FIJO EXIGE MARCA. El nacional de un fijo peruano tiene ocho digitos
    -- (Lima 1+siete, provincias 84+seis)… y el DNI peruano TAMBIEN tiene ocho.
    -- Aceptar ocho digitos pelados convertiria todo DNI en un telefono.
    v_sin_cero := case when pg_catalog.left(v_n, 1) = '0'
                       then pg_catalog.substr(v_n, 2) else v_n end;
    if (v_declara_peru or pg_catalog.left(v_n, 1) = '0')
       and v_sin_cero ~ '^[1-8][0-9]{7}$' then
      return query select '+51' || v_sin_cero, 'fijo_pe'::text, false;
      return;
    end if;

    -- Dijo ser peruano y no lo es: se acaba aqui. Y sin `+` no hay pais que
    -- suponer: no se inventa uno.
    if v_declara_peru or not v_internacional then return; end if;
  end if;

  -- E.164 puro. No se valida el codigo de pais contra una lista: mantenerla al
  -- dia en seis capas es peor deuda que aceptar un numero raro.
  if pg_catalog.length(v_sin_salida) between 8 and 15
     and v_sin_salida ~ '^[1-9][0-9]*$' then
    -- Movil o fijo es indecidible fuera de Peru sin libphonenumber. Se asume
    -- MOVIL: esconder el unico canal que hay seria peor que ofrecer uno que
    -- quiza no conteste.
    return query select '+' || v_sin_salida, 'internacional'::text, true;
  end if;
  return;
end;
$function$;

comment on function private.canonizar_contacto(text) is
  'La regla del telefono del CRM, en SQL: devuelve (e164, clase, movil) o ninguna fila. Espejo de telefonos.ts del conector, validacion.ts del front y reconocerTelefono() del puente. NO sustituye a private.normalizar_telefono, que sigue decidiendo como se GUARDA el telefono principal y con la que el CRM deduplica.';

revoke all on function private.canonizar_contacto(text) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Postflight — EJECUTANDO la funcion, no leyendola
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_caso record;
  v_res record;
  v_e164 text;
begin
  for v_caso in
    select * from (values
      -- Peru
      ('987654321',      '+51987654321'),
      ('+51 999-888-777','+51999888777'),
      ('964,262,777',    '+51964262777'),   -- Sheets lo trato como numero
      ('p:+51910585900', '+51910585900'),   -- fila real del origen
      ('014457890',      '+5114457890'),    -- fijo de Lima con el 0
      ('084 234567',     '+5184234567'),    -- fijo de Cusco
      ('+51 1 445 7890', '+5114457890'),
      -- El mundo
      ('+1 415 555 2671','+14155552671'),
      ('0034612345678',  '+34612345678'),
      -- Lo que NO es telefono
      ('',               null),
      ('   ',            null),
      ('rosa@correo.com',null),
      ('5ooooo',         null),
      ('14457890',       null),   -- ocho digitos pelados = DNI, no telefono
      ('46736918',       null),   -- un DNI no puede parecer un telefono
      ('+51123456789',   null),   -- dice ser Peru sin forma peruana
      ('9158903210',     null),   -- diez digitos: celular peruano malo
      ('4155552671',     null),   -- sin `+` no hay pais que suponer
      -- ⚠️ Los limites de E.164 hay que probarlos CON `+`. Un numero largo sin
      -- `+` se rechaza por «no hay pais que suponer», no por el tope — un
      -- mutante que ensanchaba el rango a 6..20 pasaba con el caso anterior sin
      -- despeinarse, porque nunca llegaba a esa rama.
      ('+39066982',      '+39066982'),   -- ocho digitos: el MINIMO, entra
      ('+123456789012345', '+123456789012345'), -- quince: el MAXIMO, entra
      ('+3906698',       null),   -- siete: por debajo del minimo
      ('+1234567890123456', null),-- dieciseis: pasado del maximo
      ('+0123456789',    null)    -- codigo de pais que empieza en 0
    ) as t(entrada, esperado)
  loop
    v_e164 := null;
    for v_res in select * from private.canonizar_contacto(v_caso.entrada) loop
      v_e164 := v_res.e164;
    end loop;
    if v_e164 is distinct from v_caso.esperado then
      raise exception 'postflight: canonizar_contacto(%) dio % y se esperaba %',
        coalesce(v_caso.entrada, 'NULL'), coalesce(v_e164, 'NULL'),
        coalesce(v_caso.esperado, 'NULL');
    end if;
  end loop;

  -- Y que la CLASE distinga lo que responde WhatsApp de lo que no: de eso
  -- depende que la ficha no ofrezca un boton que escribe al vacio.
  select * into v_res from private.canonizar_contacto('987654321');
  if v_res.clase <> 'celular_pe' or not v_res.movil then
    raise exception 'postflight: un celular peruano no se reconoce como movil';
  end if;
  select * into v_res from private.canonizar_contacto('014457890');
  if v_res.clase <> 'fijo_pe' or v_res.movil then
    raise exception 'postflight: un fijo se esta marcando como movil';
  end if;
  select * into v_res from private.canonizar_contacto('+34612345678');
  if v_res.clase <> 'internacional' or not v_res.movil then
    raise exception 'postflight: un internacional no se reconoce';
  end if;

  -- Que lo que sale de aqui SIEMPRE quepa en la columna. Si un dia divergieran,
  -- el alta reventaria en el insert con un error de constraint ilegible.
  for v_caso in select * from (values
      ('987654321'), ('014457890'), ('+34612345678'), ('+14155552671')
    ) as t(entrada)
  loop
    select * into v_res from private.canonizar_contacto(v_caso.entrada);
    if v_res.e164 !~ '^\+(51(9[0-9]{8}|[1-8][0-9]{7})|(?!51)[1-9][0-9]{7,14})$' then
      raise exception 'postflight: canonizar_contacto(%) devuelve % , que el CHECK de telefono_alternativo rechaza',
        v_caso.entrada, v_res.e164;
    end if;
  end loop;
end;
$postflight$;

commit;
