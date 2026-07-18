-- Perfil humano del lead: genero y fecha de nacimiento.
--
-- Motivo: el avatar de silueta por genero ya esta construido en el frontend y
-- hoy cae SIEMPRE a iniciales porque el dato no existe en la base. La fecha de
-- nacimiento viaja con el (mismo momento de captura, mismo formulario).
--
-- Frontera: solo crm.leads. NO toca public.perfiles ni el portal de clientes;
-- por eso el cliente convertido todavia pierde la silueta (diferido con OK de
-- Miguel el 2026-07-18).
--
-- OJO con los permisos: crm.leads tiene GRANT POR COLUMNA. Una columna nueva
-- nace SIN privilegios para authenticated/service_role y seria invisible por
-- PostgREST aunque exista en el catalogo. Los GRANT del final no son opcionales.
-- (anon no tiene ningun privilegio sobre crm.leads y sigue igual.)

begin;

set local lock_timeout = '10s';

alter table crm.leads
  add column genero text,
  add column fecha_nacimiento date;

-- Binario a proposito: mapea al sexo del documento (RENIEC) y decide la
-- silueta. Mismo dominio que el catalogo GENEROS de tipos.ts.
alter table crm.leads
  add constraint leads_genero_valido
    check (genero is null or genero in ('F', 'M'));

-- Rango de cordura contra typos de siglo (anio 202 en vez de 2020). NO valida
-- mayoria de edad: eso exige comparar contra la fecha de hoy y PostgreSQL
-- rechaza expresiones no IMMUTABLE en un CHECK. La regla "debe ser mayor de
-- edad" vive en la validacion del formulario, donde ademas el mensaje es
-- humano; aqui solo se descarta lo imposible.
alter table crm.leads
  add constraint leads_fecha_nacimiento_valida
    check (
      fecha_nacimiento is null
      or (fecha_nacimiento >= date '1900-01-01' and fecha_nacimiento < date '2100-01-01')
    );

comment on column crm.leads.genero is
  'Genero del lead (F/M), opcional. Decide la silueta del avatar; sin dato el frontend cae a iniciales.';

comment on column crm.leads.fecha_nacimiento is
  'Fecha de nacimiento del lead, opcional. Solo rango de cordura en la base; la mayoria de edad se valida en el formulario.';

grant select (genero, fecha_nacimiento) on crm.leads to authenticated, service_role;
grant insert (genero, fecha_nacimiento) on crm.leads to authenticated, service_role;
grant update (genero, fecha_nacimiento) on crm.leads to authenticated, service_role;

commit;
