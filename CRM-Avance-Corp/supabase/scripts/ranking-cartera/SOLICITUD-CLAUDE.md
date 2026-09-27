ROLE: SECONDARY_REVIEWER (auditor-rls). Codex is PRIMARY.
Review ONLY the attached evidence. Do not modify files, invoke agents, use tools, or delegate.
Return the final review in Spanish, starting exactly with an unformatted first line "VERDICT: PASS", "VERDICT: CHANGES_REQUESTED", or "VERDICT: BLOCK". Include SUMMARY, evidence-backed P0-P3 FINDINGS or none, test gaps/risks, NEXT ACTIONS, CONFIDENCE. Prefer <=1100 words.

Task LEVEL 3: independent code/SQL/RLS review of Delivery A, locally implemented and tested. NOT a release request. User approved LOCAL implementation only, production unchanged pending exact SQL approval and branch/apply/RLS/advisors/native merge gates. Do not interpret intentionally pending release gates as claims they passed.

Requirement: legacy Avance contracts category nuevo with no direct lead and no temporally eligible profile lead may display channel cartera only when an operations ledger row matches new contract, client, currency, date and type upgrade/renovacion. Ambiguous/direct/known origin must keep old result. Do NOT change financial category, amounts, owner attribution, conversion, COOPAC branch, or sealed snapshots. No UI/company restriction work.

Navigation evidence: CodeGraph FIRST queries for ranking_capital_origen_filas, ranking_origen_vendedor_fn and operaciones_cartera found legacy portal and unrelated symbols, so PRIMARY used focused migration source plus live pg_get_functiondef and pg_proc. Only direct textual caller of reader on live pg_proc: private.ranking_origen_live. Unique indexed operaciones_cartera.contrato_nuevo_id FK to public.contratos; no dependency on mirror crm.inversiones. No reindex or tools changed.

Isolation: clean local clone base published commit 526d6d90c621e4072251818d1325b7bd0c01b2ca. New migration created CLI, existing migration untouched. Main dirty user tree preserved. Local DB cloned from synthetic ranking_enlaces_20260926 to dedicated ranking_cartera_20260926; every test ends ROLLBACK, no triggers disabled.
Live and local before-body MD5: reader 52ecf49a1c698e135a531b38ab75e291; capital_episodios 214c6bada3dc63f553d7f9b62fd7963c; produccion_mes_por_vendedor ecfdf7e030497af2f299ba327102a5ea.
Candidate body MD5 bfeaa3140c4fcdedb12566dcdf5ae9a6.
Old reader is the same full function below but CREATE FUNCTION and WITHOUT the added commented WHEN EXISTS block. All other lines are unchanged.
Old owner postgres, proacl={postgres=X/postgres}, SQL STABLE SECURITY DEFINER search_path=''. Replacing preserves owner/ACL; final revoke matches old. No new privileges.
The migration is a private SELECT-only helper, not a standalone authorized endpoint; caller RPC retains existing scope gate. SECURITY DEFINER is required for internal ledger/contract reads behind that gate. Review guard chain, no new public objects, no RLS/table/trigger changes.

TEST EVIDENCE actual PASS:
1. 23 assertions in attached new SQL test, exact 5-row oracle over synthetic bank, PEN/USD, with/without investment mirror, all raw data and canonical totals/conversions unchanged, ambiguous direct/fallback leads preserved, mismatched currency/date/client rejected, renewal ledger recognized, ACL/owner/signatures/search_path unchanged, exact old function and old results restored by rollback SQL.
2. Existing ranking-origen/prueba-local.sql rerun unchanged AFTER candidate: PASS mixed lead ambiguity, COOPAC, conversion Referido15% / null without weight, manager/supervisor scope/other identity denied, canonical production parity, no duplicates, JSON concordance, adjustments negative, discrepant payload unavailable, ACL, new snapshot, failing snapshot isolated, immutability. August has 0 groups (not meaningful monetary proof); September2 nonemptygroups.
3. Existing suite run BEFORE installing candidate created 2 sealed Sept snapshots; after migration full snapshot rows AND RPC response identical, snapshots nonempty. Rollback.
4. Frontend existing published baseline tests 66 PASS across ranking-origen.test.ts, ranking-vendedores.test.tsx, equipo-ranking-mensual.test.tsx; no frontend source changes. Parser uses strictObject with origen v.string(), exact fields unchanged; UI already labels cartera, hides conversion for it.
5. Production READ ONLY projection of EXACT new SQL function body (no CREATE/DML, p_ini/p_fin/meta replaced with Sept2026 constants): 143→143 rows, 0 duplicates, exactly12sin_origen→cartera, every other returned column unchanged. 8PEN=2092254;4USD=54971. Focusanalyst3PEN=150000, other origins untouched.
6. node --check PASS, diff whitespace PASS.
HTTP/RLS entirematrix and seed preflight: NOT RUN, blocked missing SUPABASE_URL in isolatedclone (deps installed offline). No credentials configured. Advisors/remote branch/production merge NOT RUN pending explicit authority. Fullfrontendbuild/E2E NOT RUN nofrontendchange, notyetrelease. These remain release gates.
Migration ledger now records LOCAL ONLY, newSQL purpose/constraints/tests, pending review and remotegates. database.types.ts unchanged because exact signature/returns/schema unchanged.
Potential residual matters: exact reviewer concern about unsupported ledger semantics, date equality, role widening, cost of EXISTS against unique index, preflight hashes or rollback safety. Don't recommend recategorizing data or newfeatures outside scope without evidence.

CANDIDATE FILE CRM-Avance-Corp/supabase/migrations/20260927003433_crm_ranking_cartera_legada.sql (line numbers):
1	-- Entrega A: capital Avance sin origen con continuidad acreditada en el ledger.
2	-- Solo cambia el canal de lectura. No recategoriza contratos, no toca
3	-- conversión/atribución, ni la rama COOPAC, ni snapshots ya sellados.
4	-- Mantiene firma, tipos, owner y ACL; el helper sigue cerrado a clientes.
5	do $preflight$
6	begin
7	  if (select md5(prosrc) from pg_proc where oid =
8	      'private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure)
9	      is distinct from '52ecf49a1c698e135a531b38ab75e291' then
10	    raise exception 'Cambió el lector de orígenes: revisar la base antes de instalar';
11	  end if;
12	  if (select md5(prosrc) from pg_proc where oid =
13	      'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure)
14	      is distinct from '214c6bada3dc63f553d7f9b62fd7963c'
15	    or (select md5(prosrc) from pg_proc where oid =
16	      'private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure)
17	      is distinct from 'ecfdf7e030497af2f299ba327102a5ea' then
18	    raise exception 'Cambió el núcleo monetario: volver a conciliar antes de instalar';
19	  end if;
20	end;
21	$preflight$;
22	
23	create or replace function private.ranking_capital_origen_filas(
24	  p_ini timestamptz, p_fin timestamptz, p_periodo_id uuid
25	)
26	returns table (
27	  vendedor_id uuid, origen text, moneda text, capital numeric,
28	  categoria text, operacion_id uuid
29	)
30	language sql stable security definer set search_path = ''
31	as $function$
32	  with contratos_base as materialized (
33	    select c.id, c.cliente_id, c.fecha, c.categoria, c.moneda, c.capital,
34	      c.creado_por, c.analista_cierre_id,
35	      coalesce(enlaces.tiene_vendedor_explicito, false) as tiene_vendedor_explicito,
36	      coalesce(enlaces.vendedores_distintos, 0) as vendedores_distintos,
37	      enlaces.vendedor_unico,
38	      case
39	        when c.categoria <> 'nuevo' then 'cartera'
40	        when directo.cantidad > 0 then
41	          case when directo.origenes_distintos = 1 then directo.origen_unico else 'sin_origen' end
42	        when cliente.cantidad > 0 then
43	          case when cliente.origenes_distintos = 1 then cliente.origen_unico else 'sin_origen' end
44	        -- Solo rescata falta de origen: los leads directos y el fallback
45	        -- anterior (incluso ambiguos) conservan precedencia. EXISTS evita
46	        -- multiplicar capital y no depende del espejo crm.inversiones.
47	        when exists (
48	          select 1 from crm.operaciones_cartera o
49	          where o.contrato_nuevo_id = c.id
50	            and o.cliente_id = c.cliente_id
51	            and o.moneda = c.moneda
52	            and o.fecha_operacion = c.fecha_cierre_comercial
53	            and o.tipo in ('upgrade', 'renovacion')
54	        ) then 'cartera'
55	        else 'sin_origen'
56	      end as origen
57	    from (
58	      select k.contrato_id as id, k.cliente_id, k.categoria, k.moneda,
59	        k.monto as capital, k.registrado_por as creado_por,
60	        k.analista_id as analista_cierre_id, k.fecha,
61	        (k.fecha at time zone 'America/Lima')::date as fecha_cierre_comercial
62	      from private.capital_episodios(p_ini, p_fin, true, '{}'::uuid[]) k
63	      where left(k.tipo, 9) = 'contrato_' and k.medida = 'stock'
64	    ) c
65	    left join lateral (
66	      select count(*) filter (where l.vendedor_id is not null) > 0 as tiene_vendedor_explicito,
67	        count(distinct l.vendedor_id) filter (where l.vendedor_id is not null)::integer
68	          as vendedores_distintos,
69	        case when count(distinct l.vendedor_id) filter (where l.vendedor_id is not null) = 1
70	          then min(l.vendedor_id::text) filter (where l.vendedor_id is not null)::uuid
71	        end as vendedor_unico
72	      from crm.leads l where l.contrato_id = c.id
73	    ) enlaces on true
74	    left join lateral (
75	      select count(*) as cantidad,
76	        count(distinct coalesce(l.origen, 'sin_origen')) as origenes_distintos,
77	        min(coalesce(l.origen, 'sin_origen')) as origen_unico
78	      from crm.leads l where l.contrato_id = c.id
79	    ) directo on true
80	    left join lateral (
81	      select count(*) as cantidad,
82	        count(distinct coalesce(l.origen, 'sin_origen')) as origenes_distintos,
83	        min(coalesce(l.origen, 'sin_origen')) as origen_unico
84	      from crm.leads l
85	      where l.perfil_id = c.cliente_id and l.creado_en < c.fecha + interval '1 day'
86	    ) cliente on true
87	    where c.fecha_cierre_comercial >= (p_ini at time zone 'America/Lima')::date
88	      and c.fecha_cierre_comercial < (p_fin at time zone 'America/Lima')::date
89	      and c.categoria in ('nuevo', 'renovacion', 'upgrade')
90	      and c.moneda in ('PEN', 'USD')
91	  ), atribuidos as materialized (
92	    select base.id,
93	      case
94	        when base.analista_cierre_id is not null
95	          then coalesce(meta_analista.vendedor_id, base.analista_cierre_id)
96	        when base.vendedores_distintos > 1 then null
97	        when base.tiene_vendedor_explicito
98	          then coalesce(meta_lead.vendedor_id, base.vendedor_unico)
99	        else coalesce(meta_autor.vendedor_id, equipo_autor.perfil_id)
100	      end as vendedor_id,
101	      base.origen, base.categoria, base.moneda, base.capital
102	    from contratos_base base
103	    left join crm.metas_vendedor meta_lead
104	      on meta_lead.meta_periodo_id = p_periodo_id and meta_lead.vendedor_id = base.vendedor_unico
105	    left join crm.metas_vendedor meta_autor
106	      on meta_autor.meta_periodo_id = p_periodo_id and meta_autor.vendedor_id = base.creado_por
107	    left join crm.metas_vendedor meta_analista
108	      on meta_analista.meta_periodo_id = p_periodo_id and meta_analista.vendedor_id = base.analista_cierre_id
109	    left join crm.equipo equipo_autor
110	      on equipo_autor.perfil_id = base.creado_por and equipo_autor.rol_crm = 'vendedor'
111	  ), externos_confirmados as materialized (
112	    select ce.id, coalesce(mv.vendedor_id, ce.vendedor_id) as vendedor_id,
113	      coalesce(l.origen, 'sin_origen') as origen, 'nuevo'::text as categoria,
114	      ce.moneda, ce.capital
115	    from (
116	      select k.cierre_externo_id as id, k.lead_id, k.analista_id as vendedor_id,
117	        k.moneda, k.monto as capital, k.medida, k.fecha as creado_en
118	      from private.capital_episodios(p_ini, p_fin, true, '{}'::uuid[]) k
119	      where k.tipo = 'cooperativa'
120	    ) ce
121	    left join crm.metas_vendedor mv
122	      on mv.meta_periodo_id = p_periodo_id and mv.vendedor_id = ce.vendedor_id
123	    left join crm.leads l on l.id = ce.lead_id
124	    where ce.creado_en >= p_ini and ce.creado_en < p_fin
125	      and ce.medida = 'stock' and ce.moneda in ('PEN', 'USD')
126	  )
127	  select a.vendedor_id, a.origen, a.moneda, a.capital, a.categoria, a.id
128	  from atribuidos a where a.vendedor_id is not null
129	  union all
130	  select e.vendedor_id, e.origen, e.moneda, e.capital, e.categoria, e.id
131	  from externos_confirmados e
132	$function$;
133	
134	revoke all on function private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)
135	  from public, anon, authenticated, service_role;
136	

UNCHANGED CALLERS from 20260925190000_crm_ranking_origen_vendedor.sql lines190-361:
create function private.ranking_origen_live(
  p_periodo date, p_vendedor_id uuid, p_detalles jsonb
)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_ini timestamptz := p_periodo::timestamp at time zone 'America/Lima';
  v_fin timestamptz := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';
  v_periodo_id uuid;
  v_neto_pen numeric := 0;
  v_neto_usd numeric := 0;
  v_ajuste_pen numeric := 0;
  v_ajuste_usd numeric := 0;
  v_bruto_pen numeric := 0;
  v_bruto_usd numeric := 0;
  v_filas jsonb;
begin
  if p_detalles is null or jsonb_typeof(p_detalles) <> 'array' then
    return jsonb_build_object('disponible', false, 'filas', '[]'::jsonb);
  end if;

  select mp.id into v_periodo_id
  from crm.meta_periodos mp where mp.periodo = p_periodo
  order by mp.revision desc limit 1;

  select
    coalesce(sum((d.valor->>'capital_real')::numeric) filter (where d.valor->>'moneda' = 'PEN'), 0),
    coalesce(sum((d.valor->>'capital_real')::numeric) filter (where d.valor->>'moneda' = 'USD'), 0),
    coalesce(sum(coalesce((d.valor->>'capital_ajuste')::numeric, 0)) filter (where d.valor->>'moneda' = 'PEN'), 0),
    coalesce(sum(coalesce((d.valor->>'capital_ajuste')::numeric, 0)) filter (where d.valor->>'moneda' = 'USD'), 0)
  into v_neto_pen, v_neto_usd, v_ajuste_pen, v_ajuste_usd
  from jsonb_array_elements(p_detalles) d(valor);

  with capital_filas as materialized (
    select f.* from private.ranking_capital_origen_filas(v_ini, v_fin, v_periodo_id) f
    where f.vendedor_id = p_vendedor_id
  ), bruto as (
    select coalesce(sum(f.capital) filter (where f.moneda = 'PEN'), 0) as pen,
      coalesce(sum(f.capital) filter (where f.moneda = 'USD'), 0) as usd
    from capital_filas f
  ), capital as materialized (
    select c.origen,
      coalesce(sum(c.capital) filter (where c.moneda = 'PEN'), 0) as capital_pen,
      coalesce(sum(c.capital) filter (where c.moneda = 'USD'), 0) as capital_usd,
      count(*)::integer as contratos
    from capital_filas c
    group by c.origen
  ), conversion as materialized (
    select cv.origen, cv.leads, cv.cierres, cv.conversion_pct
    from private.ranking_conversion_origen_mes(
      v_ini, v_fin, p_periodo, private.peso_referido_conversion(p_periodo)
    ) cv
    where cv.vendedor_id = p_vendedor_id
  ), origenes as (
    select unnest(array['landing','formulario','referido','oficina']) as origen
    union select c.origen from capital c
    union select cv.origen from conversion cv
    union select 'ajuste' where v_ajuste_pen <> 0 or v_ajuste_usd <> 0
  )
  select b.pen, b.usd, coalesce(jsonb_agg(jsonb_build_object(
    'origen', o.origen,
    'capital_pen', case when o.origen = 'ajuste' then -v_ajuste_pen else coalesce(c.capital_pen, 0) end,
    'capital_usd', case when o.origen = 'ajuste' then -v_ajuste_usd else coalesce(c.capital_usd, 0) end,
    'contratos', coalesce(c.contratos, 0),
    'leads', coalesce(cv.leads, 0),
    'cierres', coalesce(cv.cierres, 0),
    'conversion_pct', cv.conversion_pct
  ) order by case o.origen
    when 'landing' then 1 when 'formulario' then 2 when 'referido' then 3
    when 'oficina' then 4 when 'cartera' then 5 when 'ajuste' then 99 else 50 end,
    o.origen), '[]'::jsonb) into v_bruto_pen, v_bruto_usd, v_filas
  from bruto b
  cross join origenes o
  left join capital c on c.origen = o.origen
  left join conversion cv on cv.origen = o.origen
  group by b.pen, b.usd;

  if v_bruto_pen <> v_neto_pen + v_ajuste_pen
    or v_bruto_usd <> v_neto_usd + v_ajuste_usd then
    return jsonb_build_object('disponible', false, 'filas', '[]'::jsonb);
  end if;

  return jsonb_build_object('disponible', true, 'filas', v_filas);
end;
$function$;

revoke all on function private.ranking_origen_live(date,uuid,jsonb)
  from public, anon, authenticated, service_role;

-- El BEFORE INSERT participa en la transacción del sello. No modifica fotos
-- antiguas ni permite cambiar una foto existente (sigue append-only).
alter table crm.cierre_mes_vendedor add column origenes_ranking jsonb;

create function private.ranking_origen_sellado_trg()
returns trigger
language plpgsql security definer set search_path = ''
as $function$
begin
  begin
    new.origenes_ranking := private.ranking_origen_live(
      new.periodo, new.vendedor_id, new.detalles
    );
  exception when others then
    -- Un desglose secundario no debe impedir el sello financiero del mes.
    raise warning 'Ranking origen no disponible al sellar % / %: SQLSTATE %',
      new.periodo, new.vendedor_id, sqlstate;
    new.origenes_ranking := jsonb_build_object(
      'disponible', false, 'filas', '[]'::jsonb
    );
  end;
  return new;
end;
$function$;

revoke all on function private.ranking_origen_sellado_trg()
  from public, anon, authenticated, service_role;

create trigger trg_cierre_mes_vendedor_10_ranking_origen
before insert on crm.cierre_mes_vendedor
for each row execute function private.ranking_origen_sellado_trg();

-- El acceso usa la lista de vendedores del payload autoritativo, con el mismo
-- ámbito de Gerencia/Supervisión y la misma foto del mes seleccionado.
create function crm.ranking_origen_vendedor_fn(p_periodo date, p_vendedor_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_base jsonb;
  v_vendedor jsonb;
  v_detalle jsonb;
  v_cerrado boolean;
begin
  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date
    or p_vendedor_id is null then
    raise exception 'Periodo o analista inválido' using errcode = '22023';
  end if;

  v_base := crm.cumplimiento_metas_fn(p_periodo);
  select e.valor into v_vendedor
  from jsonb_array_elements(coalesce(v_base->'vendedores', '[]'::jsonb)) e(valor)
  where e.valor->>'vendedor_id' = p_vendedor_id::text;
  if v_vendedor is null then
    raise exception 'Analista fuera del ámbito' using errcode = '42501';
  end if;

  v_cerrado := coalesce((v_base #>> '{cierre,cerrado}')::boolean, false);
  if v_cerrado then
    select s.origenes_ranking into v_detalle
    from crm.cierre_mes_vendedor s
    where s.periodo = p_periodo and s.vendedor_id = p_vendedor_id;
  else
    v_detalle := private.ranking_origen_live(
      p_periodo, p_vendedor_id, v_vendedor->'detalles'
    );
  end if;

  return jsonb_build_object(
    'version', 1, 'periodo', p_periodo, 'vendedor_id', p_vendedor_id
  ) || coalesce(v_detalle, jsonb_build_object(
    'disponible', false, 'filas', '[]'::jsonb
  ));
end;
$function$;

revoke all on function crm.ranking_origen_vendedor_fn(date,uuid) from public, anon;
grant execute on function crm.ranking_origen_vendedor_fn(date,uuid)
  to authenticated, service_role;

comment on function crm.ranking_origen_vendedor_fn(date,uuid) is
  'Detalle del Ranking por canal. Capital neto conciliado por moneda con cumplimiento_metas_fn; conversión mensual ponderada por origen. Mes sellado: foto inmutable; mes antiguo sin foto: no disponible.';


NEW SQL TEST file supabase/scripts/ranking-cartera/prueba-local.sql (numbered):
     1	-- Banco derivado de ranking_enlaces_20260926, solo fixtures sintéticos.
     2	-- Todos los cambios (incluida la migración) se deshacen al terminar.
     3	begin;
     4	set local statement_timeout = '40s';
     5	set local lock_timeout = '3s';
     6	select set_config('crm.op_privilegiada','on',true);
     7	
     8	create function pg_temp.exigir(ok boolean, mensaje text) returns void
     9	language plpgsql as $$ begin
    10	  if ok is distinct from true then raise exception 'FAIL: %',mensaje; end if;
    11	  raise notice 'PASS: %',mensaje;
    12	end $$;
    13	select pg_temp.exigir(current_database()='ranking_cartera_20260926','destino sintético exclusivo');
    14	select pg_temp.exigir((select count(*)=3 from public.contratos where numero_contrato in ('BANCO-A1','BANCO-A2','BANCO-A3')),'fixtures de tres upgrades presentes');
    15	
    16	-- Conservar los términos válidos del fixture: 22000 + 30000 + 18000.
    17	-- El caso productivo 150000 se concilia por lectura aparte, no se copia PII.
    18	insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_nuevo_id,
    19	  fecha_operacion,periodo,moneda,elegible_conversion,fuente,creado_por)
    20	select cliente_id,analista_cierre_id,'upgrade',id,fecha_cierre_comercial,
    21	  date_trunc('month',fecha_cierre_comercial)::date,moneda,false,'flujo_cartera',creado_por
    22	from public.contratos where numero_contrato in ('BANCO-A1','BANCO-A2','BANCO-A3');
    23	
    24	-- Un cierre cooperativo real en el banco evita una comparación vacía de esa rama.
    25	insert into crm.cierres_externos(lead_id,cooperativa,monto,moneda,documento_tipo,documento,
    26	  nombre_completo,numero_transaccion,vendedor_id,creado_por,creado_en)
    27	values('79119955-54e8-441b-8298-dcbc9ed20291','qorilazo',1000,'PEN','DNI','12345678',
    28	  'Prueba cartera','CARTERA-LOCAL-20260926','b0000000-0000-4000-8000-000000000002',
    29	  'b0000000-0000-4000-8000-000000000003','2026-09-15 12:00:00-05');
    30	
    31	create temp table contexto as select id as meta from crm.meta_periodos
    32	where periodo=date '2026-09-01' order by revision desc limit 1;
    33	create function pg_temp.filas() returns table(vendedor_id uuid,origen text,moneda text,
    34	 capital numeric,categoria text,operacion_id uuid) language sql as $$
    35	 select f.* from contexto x cross join lateral private.ranking_capital_origen_filas(
    36	 '2026-09-01 00:00:00-05','2026-10-01 00:00:00-05',x.meta) f
    37	$$;
    38	create function pg_temp.invariantes() returns jsonb language sql as $$
    39	 select jsonb_build_object(
    40	 'contratos',(select jsonb_agg(to_jsonb(x) order by id) from public.contratos x),
    41	 'leads',(select jsonb_agg(to_jsonb(x) order by id) from crm.leads x),
    42	 'ledger',(select jsonb_agg(to_jsonb(x) order by id) from crm.operaciones_cartera x),
    43	 'fuentes',(select jsonb_agg(to_jsonb(x) order by id) from crm.cierres_externos x),
    44	 'inversiones',(select jsonb_agg(to_jsonb(x) order by id) from crm.inversiones x),
    45	 'auditoria',(select count(*) from public.audit_log),
    46	 'produccion',(select jsonb_agg(to_jsonb(f) order by to_jsonb(f)::text) from contexto x
    47	   cross join lateral private.produccion_mes_por_vendedor('2026-09-01 00:00:00-05','2026-10-01 00:00:00-05',x.meta) f),
    48	 'conversion',(select jsonb_agg(to_jsonb(f) order by to_jsonb(f)::text) from private.conversion_cierres(
    49	   '2026-09-01 00:00:00-05','2026-10-01 00:00:00-05','2026-09-01',true,'{}'::uuid[],0.15,null::uuid[]) f),
    50	 'canales',(select jsonb_agg(to_jsonb(f) order by to_jsonb(f)::text) from private.ranking_conversion_origen_mes(
    51	   '2026-09-01 00:00:00-05','2026-10-01 00:00:00-05','2026-09-01',0.15) f),
    52	 'sellos',(select jsonb_agg(to_jsonb(s) order by periodo,vendedor_id) from crm.cierre_mes_vendedor s))
    53	$$;
    54	create temp table antes as select pg_temp.invariantes() as datos;
    55	create temp table filas_antes as select * from pg_temp.filas();
    56	create temp table permisos_antes as select proowner,proacl,proconfig,prorettype,proargtypes,proallargtypes,proargmodes,proargnames,prosecdef,provolatile
    57	from pg_proc where oid='private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure;
    58	create temp table esperado as
    59	select f.* from filas_antes f;
    60	-- Oráculo independiente y explícito para este banco, no repite el CASE del candidato.
    61	update esperado set origen='cartera' where operacion_id in
    62	 ('e0000000-0000-4000-8000-00000000000a','e0000000-0000-4000-8000-00000000000b',
    63	  'e0000000-0000-4000-8000-000000000010','e0000000-0000-4000-8000-00000000000d',
    64	  'e0000000-0000-4000-8000-00000000000f');
    65	select pg_temp.exigir((select count(*)=5 from esperado e join filas_antes a using(operacion_id) where e.origen<>a.origen),
    66	 'cinco diferencias esperadas no vacías, en PEN y USD');
    67	
    68	-- @MIGRACION@
    69	
    70	select pg_temp.exigir((select datos=pg_temp.invariantes() from antes),
    71	 'contratos, leads, ledger, auditoría, capital, conversión, canales y sellos idénticos');
    72	select pg_temp.exigir(not exists((select * from esperado except all select * from pg_temp.filas())
    73	 union all (select * from pg_temp.filas() except all select * from esperado)),
    74	 'solo cinco cambios de canal, sin duplicar filas ni mover vendedores');
    75	select pg_temp.exigir((select sum(f.capital)=70000 and count(*)=3 and bool_and(f.origen='cartera' and f.moneda='PEN' and f.categoria='nuevo')
    76	 from pg_temp.filas() f join public.contratos c on c.id=f.operacion_id
    77	 where c.numero_contrato in ('BANCO-A1','BANCO-A2','BANCO-A3')),
    78	 'tres upgrades PEN: Cartera por 70000 del fixture sin recategorizar contrato');
    79	select pg_temp.exigir(not exists(select 1 from crm.inversiones where contrato_id='e0000000-0000-4000-8000-00000000000a')
    80	 and (select count(*)=2 from crm.inversiones where contrato_id in
    81	 ('e0000000-0000-4000-8000-00000000000b','e0000000-0000-4000-8000-000000000010')),
    82	 'misma clasificación con un contrato sin espejo y dos con espejo');
    83	select pg_temp.exigir((select count(*)=1 and sum(capital)=1000 and bool_and(origen='landing') from pg_temp.filas() f
    84	 join crm.cierres_externos ce on ce.id=f.operacion_id),'COOPAC conserva origen y monto');
    85	select pg_temp.exigir(not exists(select 1 from pg_temp.filas() group by operacion_id having count(*)>1),
    86	 'una fila por operación');
    87	select pg_temp.exigir((select row(p.proowner,p.proacl,p.proconfig,p.prorettype,p.proargtypes,p.proallargtypes,p.proargmodes,p.proargnames,p.prosecdef,p.provolatile)
    88	 is not distinct from row(a.*) from pg_proc p cross join permisos_antes a
    89	 where p.oid='private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure),
    90	 'firma, owner, ACL, volatilidad y search_path intactos');
    91	select pg_temp.exigir(not has_function_privilege('anon','private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)','execute')
    92	 and not has_function_privilege('authenticated','private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)','execute')
    93	 and not has_function_privilege('service_role','private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)','execute'),
    94	 'helper cerrado a anon, authenticated y service_role');
    95	
    96	-- Lead tardío explícitamente enlazado gana incluso si existe ledger upgrade.
    97	savepoint casos;
    98	update crm.leads set contrato_id='e0000000-0000-4000-8000-00000000000a'
    99	where perfil_id='c0000000-0000-4000-8000-000000000001';
   100	select pg_temp.exigir((select origen='referido' from pg_temp.filas() where operacion_id='e0000000-0000-4000-8000-00000000000a'),
   101	 'lead tardío enlazado conserva Referido sobre ledger');
   102	-- Dos leads directos de canales distintos conservan sin_origen, no Cartera.
   103	update crm.leads set contrato_id='e0000000-0000-4000-8000-00000000000a'
   104	where id='803b9178-8918-4484-b892-b5168df6f72e';
   105	select pg_temp.exigir((select origen='sin_origen' from pg_temp.filas() where operacion_id='e0000000-0000-4000-8000-00000000000a'),
   106	 'origen directo ambiguo no se maquilla como Cartera');
   107	
   108	-- Fallback anterior y fallback ambiguo, sin enlaces directos.
   109	-- El guard conserva creado_en del lead. Crear un contrato posterior válido,
   110	-- con su snapshot legacy coherente y fecha comercial inferida por el servidor.
   111	do $$ declare c public.contratos%rowtype; d jsonb; cols text; vals text;
   112	begin
   113	 select * into strict c from public.contratos where numero_contrato='BANCO-A2';
   114	 c.id:='e0000000-0000-4000-8000-000000000021';
   115	 c.numero_contrato:='CARTERA-FALLBACK';
   116	 c.fecha_vencimiento:=c.fecha_vencimiento + (date '2026-09-25'-c.fecha_inicio);
   117	 c.fecha_inicio:='2026-09-25';
   118	 c.creado_en:='2026-09-25 12:00:00-05';
   119	 c.fecha_cierre_comercial:=null;
   120	 c.fuente_cierre_comercial:=null;
   121	 c.producto_condicion_id:=private.crear_snapshot_producto_legacy(c.id,c.categoria,
   122	  c.moneda,c.modalidad,c.tipo_interes,c.capital,c.tasa_anual,c.fecha_inicio,c.fecha_vencimiento);
   123	 d:=to_jsonb(c);
   124	 select string_agg(quote_ident(attname),',' order by attnum),
   125	 string_agg('r.'||quote_ident(attname),',' order by attnum) into cols,vals
   126	 from pg_attribute where attrelid='public.contratos'::regclass
   127	 and attnum>0 and not attisdropped and attgenerated='';
   128	 execute format('insert into public.contratos(%s) select %s from jsonb_populate_record(null::public.contratos,$1) r',cols,vals) using d;
   129	end $$;
   130	insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_nuevo_id,
   131	 fecha_operacion,periodo,moneda,elegible_conversion,fuente,creado_por)
   132	select cliente_id,analista_cierre_id,'upgrade',id,fecha_cierre_comercial,
   133	 date_trunc('month',fecha_cierre_comercial)::date,moneda,false,'flujo_cartera',creado_por
   134	from public.contratos where numero_contrato='CARTERA-FALLBACK';
   135	select pg_temp.exigir((select origen='formulario' from pg_temp.filas() where operacion_id='e0000000-0000-4000-8000-000000000021'),
   136	 'origen anterior por perfil conserva precedencia');
   137	update crm.leads set perfil_id='c0000000-0000-4000-8000-000000000002',origen='referido'
   138	where id='255a6b9c-f49e-4dc4-8d06-01e61be27274';
   139	select pg_temp.exigir((select origen='sin_origen' from pg_temp.filas() where operacion_id='e0000000-0000-4000-8000-000000000021'),
   140	 'fallback ambiguo no se maquilla como Cartera');
   141	
   142	-- Contrato repetido sin ledger no basta (B1-JUL), ni un lead tardío sin enlace (B2-1).
   143	select pg_temp.exigir((select origen='sin_origen' from pg_temp.filas() where operacion_id='e0000000-0000-4000-8000-00000000000e'),
   144	 'sin ledger válido no se infiere continuidad');
   145	
   146	-- Ledger discordante: reemplazo exclusivamente sintético dentro de savepoint.
   147	-- Se usa la válvula existente de eliminación, sin apagar el trigger inmutable.
   148	savepoint discrepancia;
   149	select set_config('crm.elimina_operacion_cartera','on',true);
   150	delete from crm.operaciones_cartera where contrato_nuevo_id='e0000000-0000-4000-8000-000000000010';
   151	insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_nuevo_id,
   152	 fecha_operacion,periodo,moneda,elegible_conversion,fuente,creado_por)
   153	select cliente_id,analista_cierre_id,'upgrade',id,fecha_cierre_comercial,
   154	 date_trunc('month',fecha_cierre_comercial)::date,'USD',false,'flujo_cartera',creado_por
   155	from public.contratos where numero_contrato='BANCO-A3';
   156	select pg_temp.exigir((select origen='sin_origen' from pg_temp.filas() where operacion_id='e0000000-0000-4000-8000-000000000010'),
   157	 'ledger de otra moneda no clasifica');
   158	rollback to discrepancia;
   159	savepoint discrepancia;
   160	select set_config('crm.elimina_operacion_cartera','on',true);
   161	delete from crm.operaciones_cartera where contrato_nuevo_id='e0000000-0000-4000-8000-000000000010';
   162	insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_nuevo_id,
   163	 fecha_operacion,periodo,moneda,elegible_conversion,fuente,creado_por)
   164	select cliente_id,analista_cierre_id,'upgrade',id,fecha_cierre_comercial+1,
   165	 date_trunc('month',fecha_cierre_comercial+1)::date,moneda,false,'flujo_cartera',creado_por
   166	from public.contratos where numero_contrato='BANCO-A3';
   167	select pg_temp.exigir((select origen='sin_origen' from pg_temp.filas() where operacion_id='e0000000-0000-4000-8000-000000000010'),
   168	 'ledger de otra fecha no clasifica');
   169	rollback to discrepancia;
   170	
   171	savepoint discrepancia;
   172	select set_config('crm.elimina_operacion_cartera','on',true);
   173	delete from crm.operaciones_cartera where contrato_nuevo_id='e0000000-0000-4000-8000-000000000010';
   174	insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_nuevo_id,
   175	 fecha_operacion,periodo,moneda,elegible_conversion,fuente,creado_por)
   176	select 'c0000000-0000-4000-8000-000000000004',analista_cierre_id,'upgrade',id,fecha_cierre_comercial,
   177	 date_trunc('month',fecha_cierre_comercial)::date,moneda,false,'flujo_cartera',creado_por
   178	from public.contratos where numero_contrato='BANCO-A3';
   179	select pg_temp.exigir((select origen='sin_origen' from pg_temp.filas() where operacion_id='e0000000-0000-4000-8000-000000000010'),
   180	 'ledger de otro cliente no clasifica');
   181	rollback to discrepancia;
   182	
   183	savepoint renovacion;
   184	select set_config('crm.elimina_operacion_cartera','on',true);
   185	delete from crm.operaciones_cartera where contrato_nuevo_id='e0000000-0000-4000-8000-00000000000d';
   186	insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,contrato_nuevo_id,contrato_origen_id,
   187	 fecha_operacion,periodo,moneda,elegible_conversion,fuente,creado_por,capital_renovado,capital_adicional)
   188	select cliente_id,analista_cierre_id,'renovacion',id,'e0000000-0000-4000-8000-00000000000c',fecha_cierre_comercial,
   189	 date_trunc('month',fecha_cierre_comercial)::date,moneda,true,'flujo_cartera',creado_por,capital,0
   190	from public.contratos where numero_contrato='BANCO-B1-SEP';
   191	select pg_temp.exigir((select origen='cartera' from pg_temp.filas() where operacion_id='e0000000-0000-4000-8000-00000000000d')
   192	 and exists(select 1 from crm.operaciones_cartera where contrato_nuevo_id='e0000000-0000-4000-8000-00000000000d' and tipo='renovacion'),
   193	 'renovación legada acreditada también clasifica');
   194	rollback to renovacion;
   195	
   196	rollback to casos;
   197	-- @REVERSION@
   198	select pg_temp.exigir((select md5(prosrc)='52ecf49a1c698e135a531b38ab75e291' from pg_proc
   199	 where oid='private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure),
   200	 'reversión restaura definición exacta anterior');
   201	select pg_temp.exigir(not exists((select * from filas_antes except all select * from pg_temp.filas())
   202	 union all (select * from pg_temp.filas() except all select * from filas_antes)),
   203	 'reversión restaura resultados anteriores');
   204	select pg_temp.exigir((select datos=pg_temp.invariantes() from antes),'reversión no modifica datos ni métricas');
   205	rollback;


Rollback file revertir.sql: checks current candidate body MD5 exactly bfeaa3140c4fcdedb12566dcdf5ae9a6, create-or-replace original function byte-identical body (no EXISTS branch), restores same revoke list. Verified in real local PostgreSQL by checking old body hash AND all old result rows and unchanged raw data.

