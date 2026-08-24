-- Conserva el segundo celular que ya existe en la fuente de Google sin cambiar
-- la identidad histórica del lead: `telefono` sigue gobernando dedup, reparto y
-- conversión; este campo es un canal de contacto alternativo e informativo.
begin;
set local lock_timeout = '5s';

alter table crm.leads
  add column telefono_alternativo text;

alter table crm.leads
  add constraint leads_telefono_alternativo_formato
  check (
    telefono_alternativo is null
    or telefono_alternativo ~ '^\+519[0-9]{8}$'
  ) not valid;

alter table crm.leads
  validate constraint leads_telefono_alternativo_formato;

comment on column crm.leads.telefono_alternativo is
  'Segundo celular peruano canónico del lead, si es distinto del principal. Es informativo: telefono sigue siendo la identidad usada por el dedup.';

commit;
