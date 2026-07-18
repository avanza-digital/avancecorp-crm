begin;

alter table crm.leads
  drop constraint if exists leads_origen_check;

alter table crm.leads
  add constraint leads_origen_check
  check (
    origen in (
      'referido',
      'landing',
      'formulario',
      'oficina',
      'otro',
      'web',
      'campania',
      'whatsapp'
    )
  );

commit;
