-- Una cita virtual puede agendarse antes de que exista una sala de Meet/Zoom.
-- El enlace sigue siendo válido solo si es HTTPS, pero deja de ser obligatorio.

begin;
set local lock_timeout = '10s';

alter table crm.tareas
  drop constraint tareas_destino_reunion_coherente;

alter table crm.tareas
  add constraint tareas_destino_reunion_coherente
  check (
    (tipo <> 'reunion' and ubicacion_reunion is null and enlace_reunion is null)
    or
    (tipo = 'reunion' and (
      (modalidad_reunion = 'presencial' and ubicacion_reunion is not null and enlace_reunion is null)
      or (modalidad_reunion = 'virtual' and ubicacion_reunion is null)
      or (modalidad_reunion = 'sin_clasificar' and ubicacion_reunion is null and enlace_reunion is null)
    ))
  );

comment on constraint tareas_destino_reunion_coherente on crm.tareas is
  'Presencial exige ubicación; virtual permite enlace HTTPS opcional; otras tareas no admiten destino.';

commit;
