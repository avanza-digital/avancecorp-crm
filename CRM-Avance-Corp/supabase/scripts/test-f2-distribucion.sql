-- Oraculo de F2.3a (Distribucion deja de contar los cierres ANULADOS).
-- El mundo lo siembra fixture-f2-distribucion.sql; aqui solo se comprueba:
--   1. La FORMA del payload no cambia (el front la valida a cierre hermetico).
--   2. `convertidos` excluye los cierres anulados (H17).

set search_path = '';

-- ---------------------------------------------------------------------------
-- 1. EL VALOR: el anulado deja de contar
-- ---------------------------------------------------------------------------
do $$
declare v jsonb; a jsonb; e text := '';
begin
  v := private.metricas_distribucion_leads_core('2026-07-01', '2026-07-31', now());
  select value into a from jsonb_array_elements(v->'analistas') value
   where value->>'analista_id' = '22222222-2222-4222-8222-222222222222';

  -- GUARDA ANTI-VACUIDAD: sin esto, un cambio de ruta dejaria `a` en NULL y
  -- TODAS las comparaciones de abajo serian NULL — ni verdaderas ni falsas —
  -- y la prueba pasaria sin haber comprobado nada. Ya paso una vez.
  if a is null then
    raise exception 'ORACULO VACUO: la vendedora del fixture no aparece en `analistas` (¿cambio la ruta?)';
  end if;
  if (a->'pen'->'cohorte'->>'episodios_recibidos')::int <> 4 then
    raise exception 'ORACULO VACUO: el fixture no llego (episodios_recibidos=%)',
      a->'pen'->'cohorte'->>'episodios_recibidos';
  end if;

  -- 3 episodios con resultado 'convertido': uno ANULADO (no cuenta) y uno que
  -- cerro en AGOSTO (SI cuenta: el episodio es de julio) → 2
  if (a->'pen'->'cohorte'->>'convertidos')::int <> 2 then
    e := e || format(' pen.convertidos=%s(≠2: o cuenta el anulado, o pierde el que cerro despues)',
                     a->'pen'->'cohorte'->>'convertidos'); end if;
  if (a->'pen'->'cohorte'->>'descartados')::int <> 1 then
    e := e || format(' pen.descartados=%s(≠1)', a->'pen'->'cohorte'->>'descartados'); end if;
  -- `ciclos_resueltos` NO cambia: el episodio SI se resolvio, aunque el cierre
  -- se anulara despues. Es lo honesto y evita tocar mas de lo necesario.
  if (a->'pen'->'cohorte'->>'ciclos_resueltos')::int <> 4 then
    e := e || format(' pen.ciclos_resueltos=%s(≠4: no debia cambiar)',
                     a->'pen'->'cohorte'->>'ciclos_resueltos'); end if;
  if (v->'resumen'->>'convertidos_pen')::int <> 2 then
    e := e || format(' resumen.convertidos_pen=%s(≠2)', v->'resumen'->>'convertidos_pen'); end if;
  -- Y la tercera agrupacion, la de rangos, tambien tiene que filtrar
  if (select coalesce(sum((r.value->'cohorte'->>'convertidos')::int), 0)
        from jsonb_array_elements(a->'pen'->'rangos') r) <> 2 then
    e := e || format(' suma de rangos=%s(≠2: esa agrupacion no filtra igual)',
                     (select coalesce(sum((r.value->'cohorte'->>'convertidos')::int), 0)
                        from jsonb_array_elements(a->'pen'->'rangos') r)); end if;

  if e <> '' then raise exception 'ORACULO ROTO (valor):%', e; end if;
  raise notice 'VALOR OK · 3 cierres (1 anulado, 1 en agosto) → convertidos 2 en total, resumen y rangos · resueltos 4 intactos';
end $$;

-- ---------------------------------------------------------------------------
-- 2. LA FORMA: ni una clave de mas ni de menos que la funcion VIEJA
-- ---------------------------------------------------------------------------
do $$
declare v_nueva text; v_vieja text;
begin
  v_nueva := banco.forma(private.metricas_distribucion_leads_core(
    '2026-07-01', '2026-07-31', now()));
  select forma into v_vieja from banco.forma_vieja;

  if v_vieja is null then
    raise exception 'no se guardo la forma de la funcion VIEJA: la prueba seria vacua';
  end if;
  if v_nueva is distinct from v_vieja then
    raise exception 'ORACULO ROTO (forma): el payload cambio de claves.%  VIEJA=[%]%  NUEVA=[%]',
      chr(10), v_vieja, chr(10), v_nueva;
  end if;
  raise notice 'FORMA OK · payload con las MISMAS claves que antes (%)', length(v_nueva);
end $$;

select 'TEST-F2-DISTRIBUCION: TODO VERDE' as resultado;
