-- B8 · ¿Hay leads con el teléfono o el DNI fuera de la forma normalizada? (Codex r1, hueco: el envoltorio de identidad y el
-- verificador de la casa comparan por IGUALDAD EXACTA con el valor normalizado). SOLO LECTURA: banco, rama con datos o
-- producción (`supabase db query --linked --file`). Una fila por familia con su conteo y hasta 3 ejemplos de FORMA (sin datos:
-- solo el patrón con los dígitos cambiados por 9 y las letras por x).
-- Si alguna cuenta > 0 en producción, el envoltorio debe comparar normalizando AMBOS lados (ver MIGRACIONES.md, B8 r1 #7).
with l as (
  select l.telefono, l.dni, l.activo, l.etapa,
         private.normalizar_telefono(l.telefono) as tel_norm,
         nullif(pg_catalog.btrim(l.dni), '') as dni_norm
    from crm.leads l
),
fam as (
  select 'telefono distinto de su normalizado' as familia, telefono as valor from l where telefono is distinct from tel_norm
  union all
  select 'telefono fuera de ^\+519[0-9]{8}$ (celular peruano)', telefono from l where telefono !~ '^\+519[0-9]{8}$'
  union all
  select 'dni con espacios al borde o vacío', dni from l where dni is not null and dni is distinct from dni_norm
  union all
  select 'dni fuera de ^[0-9]{8}$', dni from l where dni is not null and dni !~ '^[0-9]{8}$'
)
select f.familia, count(*) as leads,
       string_agg(distinct pg_catalog.regexp_replace(pg_catalog.regexp_replace(f.valor, '[0-9]', '9', 'g'), '[A-Za-z]', 'x', 'g'), ' · ') as formas
  from fam f group by f.familia
union all
select 'total leads', (select count(*) from crm.leads), null
order by 1;
