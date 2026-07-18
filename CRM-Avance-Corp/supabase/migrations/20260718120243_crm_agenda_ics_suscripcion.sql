-- crm_agenda_ics_suscripcion — enlace secreto de calendario (ICS) por miembro.
--
-- Cada miembro del equipo puede generar UN token secreto; con él, la edge
-- pública `crm-agenda-ics` (verify_jwt=false: Google no puede mandar JWT)
-- sirve sus tareas PENDIENTES como calendario ICS que Google Calendar consume
-- por URL ("agregar calendario por URL" — se conecta una vez y las citas
-- aparecen solas). Solo lectura hacia afuera: el token no da acceso a nada
-- más que al feed del propio dueño, y se puede rotar (invalida el anterior).
--
-- Diseño en el vault: "Agenda comercial del CRM (plan v2)" (Fase H adelantada
-- en su variante barata: ICS de solo lectura, sin OAuth de Google).

create table crm.agenda_ics (
  perfil_id uuid primary key references crm.equipo(perfil_id) on delete cascade,
  token     uuid not null unique default gen_random_uuid(),
  creado_en timestamptz not null default now(),
  rotado_en timestamptz
);

comment on table crm.agenda_ics is
  'Token secreto por miembro para la suscripción ICS de su agenda (edge crm-agenda-ics). Rotable; sin fila no hay feed.';
comment on column crm.agenda_ics.token is
  'Secreto del feed. Rotarlo (UPDATE) invalida el enlace anterior de inmediato.';

alter table crm.agenda_ics enable row level security;

-- Cada quien SU fila; nadie ve tokens ajenos (ni supervisor ni lector global:
-- un token ajeno permitiría espiar la agenda de otro fuera del CRM).
create policy agenda_ics_select on crm.agenda_ics
  for select to authenticated
  using (perfil_id = (select auth.uid()));

create policy agenda_ics_insert on crm.agenda_ics
  for insert to authenticated
  with check (perfil_id = (select auth.uid()));

-- Rotar = UPDATE del token sobre la propia fila. Sin policy DELETE (estilo de
-- la casa): dejar de compartir el calendario es rotar el token.
create policy agenda_ics_update on crm.agenda_ics
  for update to authenticated
  using (perfil_id = (select auth.uid()))
  with check (perfil_id = (select auth.uid()));

grant select, insert, update on crm.agenda_ics to authenticated;
grant select on crm.agenda_ics to service_role;
