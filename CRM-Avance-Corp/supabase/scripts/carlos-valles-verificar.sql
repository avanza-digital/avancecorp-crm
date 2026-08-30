-- Verificacion del cambio de CARLOS VALLES (solo lectura).
select jsonb_pretty(jsonb_build_object(
  'carlos', (select jsonb_build_object(
        'rol_portal', p.rol, 'activo_portal', p.activo,
        'rol_crm', e.rol_crm, 'membresia_activa', e.activo, 'supervisor', e.supervisor_id)
      from public.perfiles p left join crm.equipo e on e.perfil_id = p.id
      where p.nombre_completo = 'CARLOS VALLES'),
  'gerencias_activas', (select jsonb_agg(p.nombre_completo)
      from crm.equipo e join public.perfiles p on p.id = e.perfil_id
      where e.rol_crm = 'gerencia' and e.activo and p.activo),
  'eventos_de_este_cambio', (select jsonb_agg(jsonb_build_object('accion', ue.accion, 'cuando', ue.creado_en) order by ue.creado_en)
      from crm.usuario_eventos ue
      where ue.objetivo_id = (select id from public.perfiles where nombre_completo = 'CARLOS VALLES')
        and ue.creado_en > now() - interval '1 hour'),
  'filas_de_auditoria', (select count(*) from public.audit_log a
      where a.fila_id = (select id::text from public.perfiles where nombre_completo = 'CARLOS VALLES')
        and a.ts > now() - interval '1 hour')
)) as info;
