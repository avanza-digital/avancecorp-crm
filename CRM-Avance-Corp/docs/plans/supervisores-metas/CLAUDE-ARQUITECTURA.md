ROLE: SECONDARY_REVIEWER.
FORMATO DE TRANSPORTE OBLIGATORIO: tu respuesta debe empezar en el primer carácter exactamente con VERDICT: CHANGES_REQUESTED, VERDICT: PASS o VERDICT: BLOCK, en texto plano, seguido de salto de línea. No uses encabezados Markdown, negritas, preámbulo ni fences antes de VERDICT. Las secciones posteriores también pueden ser texto plano. El wrapper rechaza cualquier otro encabezado.
Codex is the PRIMARY. Do not modify files. Do not implement the task. Do not invoke Codex. Do not delegate. Do not create another review chain.
Revisión arquitectónica LEVEL 3 y auditoría RLS, solicitada explícitamente por Miguel junto con apoyo de JEV. Responde en español con VERDICT, SUMMARY, FINDINGS P0-P3 con evidencia, TEST GAPS, NEXT ACTIONS, CONFIDENCE.
Revisa el plan adjunto ANTES de implementarlo. Proporciona cambios imprescindibles y una recomendación concreta sobre el contrato. No inventes metas individuales no solicitadas. Busca dobles conteos, pérdida de capital, acceso cruzado, meses sellados, comparabilidad antes de octubre y transición frontend/backend.
El requerimiento del usuario es incluir ventas personales de supervisores en el avance del equipo desde octubre y mostrarlos al final del ranking (sin alterar orden de analistas). No se ha autorizado despliegue del frontend, y no se tocará producción durante pruebas.
SQL nuevo debe respetar cuatro capas; no introducir lecturas directas de tablas desde UI, ninguna mutación de public, grants mínimos. Evalúa si el plan puede implementarse dentro de la puerta existente o exige extraer núcleo privado acotado.
Esta consulta es de diseño: no declarar que implementación o pruebas pasaron. Señala hipótesis aparte de fallos demostrados.

# Ventas propias de supervisores y meta de equipo

Decisiones de Miguel, 16/10/2026:
- Las ventas de un supervisor conservan su atribución personal y aportan a la meta del equipo.
- Vigencia desde el periodo comercial octubre de 2026; septiembre y anteriores conservan su comportamiento.
- Los supervisores aparecen después de todos los analistas en el ranking.
- Usar Claude y JEV como apoyo. Codex es el único escritor.
- Copia aislada autorizada: /private/tmp/avancecorp-supervisores-20261016, desde main 65764411.

Alcance propuesto para revisión:
1. Separar `supervisores` (ventas propias) de `fuera_ranking` en la respuesta existente de `crm.cumplimiento_metas_fn`, desde octubre. Reutilizar exactamente las medidas de los núcleos existentes, por persona y moneda.
2. Supervisión recibe solo su fila personal; gerencia y lectores de reportes reciben las filas globales. Analistas y roles revocados no adquieren acceso. Sin cambios en grants ni RLS.
3. En meses abiertos, incluir supervisores activos aunque aún no tengan ventas. En meses cerrados, leer exclusivamente `periodos_cerrados.cobertura.fuera_ranking`: la foto ya conserva sus ventas propias. Sin modificar sellos ni el escritor de cierre.
4. Cliente compatible con campo opcional. El avance de capital del equipo suma analistas más ventas propias del supervisor. El total empresa suma cada persona una vez; el detalle por persona conserva todos los responsables.
5. Mostrar las ventas propias de supervisores al final del ranking, conservando los puestos de los analistas. La regla no crea nuevas metas individuales ni modifica la fórmula de conversión: Miguel pidió aparecer al final, no fijó meta individual.
6. Mantener fotografías de meses anteriores y datos de otro equipo aislados. Revisar especialmente bajas, cambios de rol y supervisores sin analistas.

Evidencia actual:
- Función productiva leída sin mutaciones: md5(prosrc)=be18b2feac623d18db695830d70e2a2e.
- 4 supervisores activos; ninguno tiene fila de meta de analista en octubre (consulta agregada).
- La API ya conserva las ventas en `fuera_ranking`, solo para lectores globales; el agregado del supervisor solo suma `vendedores` con su supervisor_id.
- El cliente valida con strictObject; cualquier campo nuevo exige desplegar antes el frontend compatible.
- CodeGraph intentado en la raíz Git: `Explore failed: unable to open database file`. Se usaron fuentes y búsquedas dirigidas como respaldo; no se reindexó.

Pruebas previstas:
- SQL real en banco exclusivo, con dos equipos, supervisores vendedores, actor ajeno, gerencia, directorio, coordinación y revocados.
- Contratos y cooperativas, PEN/USD, cero ventas, antes/después de octubre y fotografía cerrada.
- Paridad de total empresa antes/después; ninguna venta duplicada.
- Contrato frontend viejo/nuevo; avance del equipo y orden final aunque el supervisor venda más que cualquier analista.
- Lint/tipos/unitarias/build y E2E local en Docker.

Estado: análisis y revisión; sin migración implementada ni despliegue.

### supabase/scripts/supervisores-metas/vivo/crm.cumplimiento_metas_fn.sql:1-200
1: CREATE OR REPLACE FUNCTION crm.cumplimiento_metas_fn(p_periodo date)
2:  RETURNS jsonb
3:  LANGUAGE plpgsql
4:  STABLE SECURITY DEFINER
5:  SET search_path TO ''
6: AS $function$
7: declare
8:   v_uid uuid := (select auth.uid());
9:   v_rol text := private.rol_crm(v_uid);
10:   v_lector boolean := private.es_lector_global() or private.es_coordinador_reportes();
11:   v_base jsonb;
12:   v_vendedores jsonb;
13:   v_fuera_ranking jsonb := '[]'::jsonb;
14:   v_cerrado boolean;
15:   v_global boolean;
16:   v_periodo_id uuid;
17:   v_ini timestamptz;
18:   v_fin timestamptz;
19: begin
20:   if v_uid is null or (v_rol is null and not v_lector) then
21:     raise exception 'No autorizado' using errcode = '42501';
22:   end if;
23: 
24:   v_base := crm.cumplimiento_metas_sin_cartera_fn(p_periodo);
25:   v_cerrado := coalesce((v_base #>> '{cierre,cerrado}')::boolean, false);
26: 
27:   -- Solo Gerencia y el lector global reciben identidades fuera del ranking.
28:   -- Para un mes cerrado salen del JSON append-only del sello; para uno abierto
29:   -- se proyectan en vivo desde los mismos nucleos de conversion, produccion y
30:   -- cartera. Los demás roles reciben siempre un arreglo vacío.
31:   v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
32:   if v_global and v_cerrado then
33:     select coalesce(pc.cobertura->'fuera_ranking', '[]'::jsonb)
34:       into v_fuera_ranking
35:     from crm.periodos_cerrados pc
36:     where pc.periodo = p_periodo;
37:   elsif v_global then
38:     v_ini := p_periodo::timestamp at time zone 'America/Lima';
39:     v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';
40:     select mp.id into v_periodo_id
41:     from crm.meta_periodos mp
42:     where mp.periodo = p_periodo
43:     order by mp.revision desc
44:     limit 1;
45: 
46:     with conv as materialized (
47:       -- La MISMA pieza del nucleo que la oficial y que la #8. Solo quien aparece
48:       -- en el nucleo del mes: una deuda sin actividad no crea fila aqui.
49:       select n.*
50:       from private.conversion_neta_por_vendedor(p_periodo, true, '{}'::uuid[]) n
51:       where n.en_nucleo
52:     ), nombrados as materialized (
53:       -- A quien la oficial NOMBRA en `responsables` le publica el NETO; al resto
54:       -- lo suma BRUTO y sin nombre en `cobertura.fuera_de_roster`. Aqui se
55:       -- publica, para cada persona, lo mismo que la oficial (C2, auditoria 21/09).
56:       select r.vendedor_id
57:       from private.roster_conversion_mensual(p_periodo, true, '{}'::uuid[]) r
58:     ), prod as materialized (
59:       select r.*
60:       from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
61:     ), car as materialized (
62:       select m.* from private.metricas_cartera_por_vendedor(p_periodo) m
63:   ), personas as (
64:     select c.analista_id as persona_id from conv c where c.analista_id is not null
65:       union
66:       select p.vendedor_id from prod p where p.vendedor_id is not null
67:       union
68:       select c.vendedor_id from car c where c.vendedor_id is not null
69:     ), dentro as (
70:       select (e.value->>'vendedor_id')::uuid as persona_id
71:       from jsonb_array_elements(coalesce(v_base->'vendedores', '[]'::jsonb)) e
72:     ), fuera as (
73:       select
74:         p.persona_id,
75:         coalesce(nullif(btrim(pf.nombre_completo), ''),
76:                  '(sin nombre · ' || left(p.persona_id::text, 8) || ')') as nombre,
77:         coalesce(eq.rol_crm, 'fuera_equipo') as rol_crm,
78:         case
79:           when eq.rol_crm = 'vendedor' and sup.perfil_id is not null
80:             then 'analista_sin_meta'
81:           when eq.rol_crm = 'vendedor' then 'analista_sin_supervisor'
82:           when eq.rol_crm = 'supervisor' then 'supervisor'
83:           when eq.rol_crm = 'gerencia' then 'gerencia'
84:           else 'fuera_estructura'
85:         end as motivo
86:       from personas p
87:       left join crm.equipo eq on eq.perfil_id = p.persona_id
88:       left join crm.equipo sup
89:         on sup.perfil_id = eq.supervisor_id and sup.rol_crm = 'supervisor'
90:       left join public.perfiles pf on pf.id = p.persona_id
91:       where not exists (
92:         select 1 from dentro d where d.persona_id = p.persona_id
93:       )
94:     )
95:     select coalesce(jsonb_agg(jsonb_build_object(
96:       'persona_id', f.persona_id,
97:       'nombre', f.nombre,
98:       'rol_crm', f.rol_crm,
99:       'motivo', f.motivo,
100:       'conversion', case when cv.analista_id is null then null else jsonb_build_object(
101:         'divisor', coalesce(cv.divisor, 0),
102:         'divisor_aproximado', coalesce(cv.divisor_aproximado, 0),
103:         'divisor_por_motivo', coalesce(cv.divisor_por_motivo, '{}'::jsonb),
104:         'cierres_no_referidos', coalesce(cv.cierres_no_referidos, 0),
105:         'cierres_referidos', coalesce(cv.cierres_referidos, 0),
106:         'cierres_de_arrastre', coalesce(cv.cierres_de_arrastre, 0),
107:         'referidos_recibidos', coalesce(cv.referidos_recibidos, 0),
108:         'numerador', case
109:           when exists (select 1 from nombrados nm where nm.vendedor_id = f.persona_id)
110:             then coalesce(cv.numerador, 0)
111:           else coalesce(cv.numerador_bruto, 0) end
112:       ) end,
113:       'detalles', det.detalles,
114:       'cartera', jsonb_build_object(
115:         'conversiones_clientes', coalesce(car.conversiones_clientes, 0),
116:         'conversiones_renovacion', coalesce(car.conversiones_renovacion, 0),
117:         'conversiones_upgrade', coalesce(car.conversiones_upgrade, 0),
118:         'operaciones_renovacion', coalesce(car.operaciones_renovacion, 0),
119:         'operaciones_upgrade', coalesce(car.operaciones_upgrade, 0),
120:         'capital_renovado_pen', coalesce(car.capital_renovado_pen, 0),
121:         'capital_renovado_usd', coalesce(car.capital_renovado_usd, 0),
122:         'capital_adicional_pen', coalesce(car.capital_adicional_pen, 0),
123:         'capital_adicional_usd', coalesce(car.capital_adicional_usd, 0),
124:         'renovaciones_sin_desglose', coalesce(car.renovaciones_sin_desglose, 0)
125:       )
126:     ) order by f.nombre, f.persona_id), '[]'::jsonb)
127:       into v_fuera_ranking
128:     from fuera f
129:     left join conv cv on cv.analista_id = f.persona_id
130:     left join car on car.vendedor_id = f.persona_id
131:     left join lateral (
132:       select jsonb_agg(jsonb_build_object(
133:         'categoria', d.categoria,
134:         'moneda', d.moneda,
135:         'capital_objetivo', 0,
136:         'capital_real', coalesce(pr.capital_real, 0),
137:         'capital_cumplimiento_pct', null,
138:         'contratos_objetivo', 0,
139:         'contratos_real', coalesce(pr.contratos_real, 0),
140:         'contratos_cumplimiento_pct', null,
141:         'capital_ajuste', 0,
142:         'contratos_ajuste', 0
143:       ) order by array_position(
144:         array['nuevo','renovacion','upgrade'], d.categoria
145:       ), d.moneda) as detalles
146:       from (values
147:         ('nuevo'::text, 'PEN'::text), ('nuevo', 'USD'),
148:         ('renovacion', 'PEN'), ('renovacion', 'USD'),
149:         ('upgrade', 'PEN'), ('upgrade', 'USD')
150:       ) d(categoria, moneda)
151:       left join prod pr on pr.vendedor_id = f.persona_id
152:         and pr.categoria = d.categoria and pr.moneda = d.moneda
153:     ) det on true;
154:   end if;
155: 
156:   with m as materialized (
157:     select x.*
158:     from private.metricas_cartera_por_vendedor(p_periodo) x
159:     where not v_cerrado
160:     union all
161:     select
162:       f.vendedor_id,
163:       (f.cartera->>'conversiones_clientes')::int,
164:       (f.cartera->>'conversiones_renovacion')::int,
165:       (f.cartera->>'conversiones_upgrade')::int,
166:       (f.cartera->>'operaciones_renovacion')::int,
167:       (f.cartera->>'operaciones_upgrade')::int,
168:       (f.cartera->>'capital_renovado_pen')::numeric,
169:       (f.cartera->>'capital_renovado_usd')::numeric,
170:       (f.cartera->>'capital_adicional_pen')::numeric,
171:       (f.cartera->>'capital_adicional_usd')::numeric,
172:       (f.cartera->>'renovaciones_sin_desglose')::int
173:     from private.cierre_mes_reportes_visible(p_periodo, v_uid) f
174:     where v_cerrado
175:   )
176:   select coalesce(jsonb_agg(
177:     jsonb_set(
178:       e.value,
179:       '{convertidos}',
180:       to_jsonb(coalesce((e.value->>'convertidos')::int, 0)
181:                + coalesce(m.conversiones_clientes, 0)),
182:       true
183:     ) order by e.ord
184:   ), '[]'::jsonb) into v_vendedores
185:   from jsonb_array_elements(coalesce(v_base->'vendedores','[]'::jsonb))
186:        with ordinality e(value, ord)
187:   left join m on m.vendedor_id = (e.value->>'vendedor_id')::uuid;
188: 
189:   v_base := jsonb_set(v_base, '{vendedores}', v_vendedores, true);
190:   return jsonb_set(v_base, '{fuera_ranking}', v_fuera_ranking, true);
191: end;
192: $function$;

### app/src/lib/objetivos.ts:346-375
346: export const CumplimientoMetasSchema = v.strictObject({
347:   // ── EL CONTRATO DE LA UNIFICACIÓN (Ola 1 de las doce puertas) ─────────────
348:   // Dicen DE DÓNDE salió la cifra. Opcionales a propósito: el front entra
349:   // PRIMERO (regla de la casa), y mientras el servidor no las emita,
350:   // `undefined` significa «servidor previo», no «no se sabe».
351:   es_mes_calendario: v.optional(v.boolean()),
352:   fuente: v.optional(v.picklist(['mensual', 'rango_vivo'])),
353:   sellado: v.optional(v.nullable(v.boolean())),
354:   ajuste_aplicado: v.optional(v.boolean()),
355:   mensual_comparada: v.optional(v.boolean()),
356:   paridad_mensual: v.optional(v.nullable(v.number())),
357:   version: v.literal(1),
358:   periodo: FechaSchema,
359:   revision: EnteroNoNegativoRpcSchema,
360:   publicada_en: v.nullable(FechaHoraSchema),
361:   fuentes_reales: v.strictObject({
362:     capital_y_contratos: v.literal('contratos_confirmados'),
363:     // Tolerar los DOS literales es lo que hace barata la reversión de la
364:     // migración B: el bundle acepta el servidor viejo (`leads_resueltos`) y el
365:     // nuevo (`leads_recibidos_ponderado`) sin redeploy.
366:     conversion: v.picklist(['leads_resueltos', 'leads_recibidos_ponderado']),
367:   }),
368:   // Llega con la migración B; optional por la misma ventana que arriba.
369:   ponderacion_referido: v.optional(v.pipe(NumeroRpcSchema, v.minValue(0), v.maxValue(1))),
370:   // Llega con el cierre de mes (20260815003742), en las dos ramas.
371:   cierre: v.optional(CierreDelMesSchema),
372:   vendedores: v.array(CumplimientoVendedorSchema),
373:   fuera_ranking: v.optional(v.array(ProduccionFueraRankingSchema)),
374: })
375: 

### app/src/lib/objetivos.ts:660-752
660:  * con meta.
661:  */
662: export function produccionPorPersona(
663:   cumplimiento: Pick<CumplimientoMetasJerarquico, 'porVendedor'> & { fueraRanking?: readonly ProduccionFueraRanking[] } | null | undefined,
664: ): Record<string, Pick<CumplimientoVendedor, 'nombre' | 'detalles'>> | null {
665:   if (cumplimiento == null) return null
666:   const fuera = Object.fromEntries((cumplimiento.fueraRanking ?? [])
667:     .map((fila) => [fila.personaId, { nombre: fila.nombre, detalles: fila.detalles }]))
668:   return { ...fuera, ...cumplimiento.porVendedor }
669: }
670: 
671: export function cumplimientoDesdeRpc(
672:   respuesta: CumplimientoMetasRpc,
673:   actorId?: string | null,
674: ): CumplimientoMetasJerarquico {
675:   const porVendedor = Object.fromEntries(
676:     respuesta.vendedores.map((fila) => [fila.vendedor_id, cumplimientoDesdeVendedor(fila)]),
677:   )
678:   const filas = Object.values(porVendedor)
679:   const fueraRanking: ProduccionFueraRanking[] = (respuesta.fuera_ranking ?? []).map((fila) => ({
680:     personaId: fila.persona_id,
681:     nombre: fila.nombre,
682:     rolCrm: fila.rol_crm,
683:     motivo: fila.motivo,
684:     conversion: fila.conversion == null ? null : {
685:       divisor: fila.conversion.divisor,
686:       divisorAproximado: fila.conversion.divisor_aproximado,
687:       divisorPorMotivo: fila.conversion.divisor_por_motivo,
688:       cierresNoReferidos: fila.conversion.cierres_no_referidos,
689:       cierresReferidos: fila.conversion.cierres_referidos,
690:       cierresDeArrastre: fila.conversion.cierres_de_arrastre,
691:       referidosRecibidos: fila.conversion.referidos_recibidos,
692:       numerador: fila.conversion.numerador,
693:     },
694:     detalles: fila.detalles.map((detalle) => ({
695:       categoria: detalle.categoria,
696:       moneda: detalle.moneda,
697:       capitalObjetivo: detalle.capital_objetivo,
698:       capitalReal: detalle.capital_real,
699:       capitalCumplimientoPct: detalle.capital_cumplimiento_pct,
700:       contratosObjetivo: detalle.contratos_objetivo,
701:       contratosReal: detalle.contratos_real,
702:       contratosCumplimientoPct: detalle.contratos_cumplimiento_pct,
703:       capitalAjuste: detalle.capital_ajuste ?? 0,
704:       contratosAjuste: detalle.contratos_ajuste ?? 0,
705:     })),
706:     cartera: {
707:       conversionesClientes: fila.cartera.conversiones_clientes,
708:       conversionesRenovacion: fila.cartera.conversiones_renovacion,
709:       conversionesUpgrade: fila.cartera.conversiones_upgrade,
710:       operacionesRenovacion: fila.cartera.operaciones_renovacion,
711:       operacionesUpgrade: fila.cartera.operaciones_upgrade,
712:       capitalRenovadoPen: fila.cartera.capital_renovado_pen,
713:       capitalRenovadoUsd: fila.cartera.capital_renovado_usd,
714:       capitalAdicionalPen: fila.cartera.capital_adicional_pen,
715:       capitalAdicionalUsd: fila.cartera.capital_adicional_usd,
716:       renovacionesSinDesglose: fila.cartera.renovaciones_sin_desglose,
717:     },
718:   }))
719:   const fueraComoCumplimiento: CumplimientoComercial[] = fueraRanking.map((fila) => ({
720:     conversionObjetivo: 0,
721:     conversionReal: null,
722:     convertidos: (fila.conversion?.cierresNoReferidos ?? 0)
723:       + (fila.conversion?.cierresReferidos ?? 0)
724:       + fila.cartera.conversionesClientes,
725:     resueltos: fila.conversion?.divisor ?? 0,
726:     numerador: fila.conversion?.numerador ?? 0,
727:     detalles: fila.detalles,
728:   }))
729:   return {
730:     periodo: respuesta.periodo,
731:     revision: respuesta.revision,
732:     publicadaEn: respuesta.publicada_en,
733:     fuentesReales: {
734:       capitalYContratos: respuesta.fuentes_reales.capital_y_contratos,
735:       conversion: respuesta.fuentes_reales.conversion,
736:     },
737:     cierre: respuesta.cierre ?? null,
738:     vendedor: actorId ? (porVendedor[actorId] ?? null) : null,
739:     supervisor: agregarCumplimientos(filas.filter((fila) => fila.supervisorId === actorId)),
740:     gerencia: agregarCumplimientos([...filas, ...fueraComoCumplimiento]),
741:     porVendedor,
742:     fueraRanking,
743:   }
744: }
745: 
746: export function capitalReal(
747:   cumplimiento: CumplimientoAgregado,
748:   moneda: MonedaMeta,
749:   categoria?: CategoriaMeta,
750: ): number {
751:   return cumplimiento.detalles.reduce((total, detalle) => (
752:     detalle.moneda === moneda && (categoria == null || detalle.categoria === categoria)

### app/src/screens/hoy/ranking-vendedores.tsx:574-650
574: 
575: function ProduccionFueraRankingPanel({
576:   filas,
577:   tc,
578: }: {
579:   filas: ProduccionFueraRanking[]
580:   tc: TipoCambio | null | undefined
581: }): JSX.Element | null {
582:   if (filas.length === 0) return null
583: 
584:   return (
585:     <aside
586:       aria-label="Producción fuera del ranking"
587:       className="border-t border-[var(--gi-line)] bg-amber-50/45 px-4 py-4 sm:px-5"
588:     >
589:       <div className="flex flex-wrap items-start justify-between gap-2">
590:         <div>
591:           <h3 className="text-sm font-bold text-[var(--gi-navy)]">Producción fuera del ranking</h3>
592:           <p className="mt-1 max-w-3xl text-[11px] font-medium leading-relaxed text-[var(--gi-muted)]">
593:             Suma al resultado total de la empresa, pero no entrega puesto ni altera el orden de los analistas.
594:           </p>
595:         </div>
596:         <span className="rounded-full border border-amber-300 bg-amber-100 px-2.5 py-1 text-[10px] font-bold text-amber-900">
597:           {numero(filas.length)} {filas.length === 1 ? 'responsable' : 'responsables'} sin puesto
598:         </span>
599:       </div>
600: 
601:       <ul className="mt-3 grid gap-2 lg:grid-cols-2">
602:         {filas.map((fila) => {
603:           const capitalPen = fila.detalles.reduce((total, detalle) => (
604:             detalle.moneda === 'PEN' ? total + detalle.capitalReal : total
605:           ), 0)
606:           const capitalUsd = fila.detalles.reduce((total, detalle) => (
607:             detalle.moneda === 'USD' ? total + detalle.capitalReal : total
608:           ), 0)
609:           const contratos = fila.detalles.reduce(
610:             (total, detalle) => total + detalle.contratosReal,
611:             0,
612:           )
613:           const cierres = (fila.conversion?.cierresNoReferidos ?? 0)
614:             + (fila.conversion?.cierresReferidos ?? 0)
615:           const capital = totalEnSoles(capitalPen, capitalUsd, tc?.promedio)
616: 
617:           return (
618:             <li
619:               key={fila.personaId}
620:               className="rounded-xl border border-amber-200/80 bg-white px-3 py-3"
621:             >
622:               <div className="flex min-w-0 flex-wrap items-start justify-between gap-2">
623:                 <span className="min-w-0">
624:                   <strong className="block truncate text-xs text-[var(--gi-navy)]">{fila.nombre}</strong>
625:                   <span className="mt-0.5 block text-[10px] font-medium text-[var(--gi-muted)]">
626:                     {MOTIVO_FUERA_RANKING[fila.motivo]}
627:                   </span>
628:                 </span>
629:                 <span className="shrink-0 rounded-full bg-slate-100 px-2 py-1 text-[10px] font-bold text-slate-700">
630:                   No suma al ranking
631:                 </span>
632:               </div>
633:               <div className="mt-2 flex flex-wrap items-end justify-between gap-x-4 gap-y-2">
634:                 <span>
635:                   <span className="block text-[10px] font-semibold uppercase tracking-wide text-[var(--gi-muted)]">Capital confirmado</span>
636:                   <strong className="block text-sm tabular-nums text-[var(--gi-navy)]">{money(capital.total, 'PEN')}</strong>
637:                   <DesgloseMonedas pen={capitalPen} usd={capitalUsd} tc={capital.tc} tono="gerencia" />
638:                 </span>
639:                 <span className="text-right text-[10px] font-semibold text-[var(--gi-muted)]">
640:                   {numero(contratos)} {contratos === 1 ? 'contrato' : 'contratos'}
641:                   <span className="block">
642:                     {numero(cierres)} {cierres === 1 ? 'cierre de lead' : 'cierres de lead'} · {numero(fila.cartera.conversionesClientes)} {fila.cartera.conversionesClientes === 1 ? 'operación de cartera' : 'operaciones de cartera'}
643:                   </span>
644:                 </span>
645:               </div>
646:             </li>
647:           )
648:         })}
649:       </ul>
650:     </aside>

### app/src/screens/hoy/ranking-vendedores.tsx:708-773
708:   // puede reintroducir una baja. En un mes cerrado manda exclusivamente la
709:   // foto mensual, de modo que un alta posterior tampoco reescribe la historia.
710:   const equipoRanking = useMemo(() => {
711:     const porId = new Map<string, ConversionEquipoVendedor>()
712:     if (!usarIdentidadSnapshot) {
713:       for (const fila of equipo) {
714:         if (!fila.vendedorId) continue
715:         porId.set(fila.vendedorId, fila)
716:       }
717:       return [...porId.values()]
718:     }
719:     for (const fila of Object.values(cumplimientoVendedores)) {
720:       porId.set(fila.vendedorId, {
721:         vendedorId: fila.vendedorId,
722:         nombre: fila.nombre,
723:         supervisorId: fila.supervisorId,
724:         supervisorNombre: fila.supervisorNombre,
725:         leads: 0,
726:         contactados: 0,
727:         reunionesPactadas: 0,
728:         reunionesRealizadas: 0,
729:         clientes: 0,
730:         descartados: 0,
731:         conversionPct: null,
732:       })
733:     }
734:     return [...porId.values()]
735:   }, [cumplimientoVendedores, equipo, usarIdentidadSnapshot])
736:   const idsPoblacion = useMemo(
737:     () => new Set(equipoRanking.map((fila) => fila.vendedorId).filter((id): id is string => id != null)),
738:     [equipoRanking],
739:   )
740:   // Los núcleos son fuentes de MEDIDAS. Se proyectan al set autoritativo antes
741:   // de usar los adaptadores existentes, para que ni una respuesta obsoleta ni
742:   // fuera_de_roster materialicen una persona en pantalla.
743:   const conversionMensualPoblacion = useMemo(() => (
744:     conversionMensual == null
745:       ? conversionMensual
746:       : {
747:           ...conversionMensual,
748:           responsables: conversionMensual.responsables.filter((fila) => idsPoblacion.has(fila.vendedor_id)),
749:         }
750:   ), [conversionMensual, idsPoblacion])
751:   const adaptadaMensual = useMemo(
752:     () => adaptarConversionMensualPorFuente(
753:       conversionMensualPoblacion ?? null,
754:       equipoRanking,
755:       fuenteConversion,
756:       lecturaFuente,
757:     ),
758:     [conversionMensualPoblacion, equipoRanking, fuenteConversion, lecturaFuente],
759:   )
760:   const rankingConversion = useMemo(
761:     () => clasificarRankingConversion(adaptadaMensual.vendedores),
762:     [adaptadaMensual.vendedores],
763:   )
764:   // F3.4 sobre la cosecha: solo dos señales explícitas autorizan la cifra. Un
765:   // bloque vivo sin sondas, con NULL o con desvío distinto de cero queda
766:   // oculto; el ranking ponderado no depende de esta segunda lectura.
767:   const cosechaEnRevision = cosecha != null && !sondasNucleoVerificadas(cosecha.sondas)
768:   const rankingCapitalTotal = useMemo(
769:     () => clasificarRankingCapitalTotal(equipoRanking, metasVendedores, cumplimientoVendedores, tc?.promedio ?? null),
770:     [cumplimientoVendedores, equipoRanking, metasVendedores, tc],
771:   )
772:   const filaDetalle = rankingCapitalTotal.conPuesto.find((fila) => fila.vendedor.vendedorId === detalleId) ?? null
773:   const origenesDetalle = useRankingOrigenVendedor(

### supabase/migrations/20260807203757_crm_metas_sla_versionados.sql:35-50
35:   id uuid primary key default gen_random_uuid(),
36:   meta_periodo_id uuid not null references crm.meta_periodos(id) on delete restrict,
37:   vendedor_id uuid not null references crm.equipo(perfil_id) on delete restrict,
38:   supervisor_id uuid not null references crm.equipo(perfil_id) on delete restrict,
39:   conversion_objetivo numeric(5,2) not null check (conversion_objetivo between 0 and 100),
40:   creado_en timestamptz not null default statement_timestamp(),
41:   constraint metas_vendedor_personas_distintas check (vendedor_id <> supervisor_id),
42:   constraint metas_vendedor_periodo_vendedor_uk unique (meta_periodo_id, vendedor_id)
43: );
44: 
45: comment on table crm.metas_vendedor is
46:   'Meta individual inmutable. supervisor_id es snapshot de atribucion; RLS usa jerarquia vigente.';
47: 
48: create index metas_vendedor_vendedor_idx on crm.metas_vendedor (vendedor_id, meta_periodo_id);
49: create index metas_vendedor_supervisor_idx on crm.metas_vendedor (supervisor_id, meta_periodo_id);
50: 

### app/src/screens/hoy/datos-supervisor.ts:164-183
164:     ? objetivos
165:     : objetivosCero(periodoVigente)
166:   const cumplimientoMensual = fotoMensualStoreVigente ? cumplimientoMetas : null
167:   const meta = metaVigente(objetivosMensuales.supervisor, cumplimientoMensual?.supervisor ?? null)
168:   const metaConversion = metaConversionAplicable(meta.conversionObjetivo, objetivosMensualesError)
169:   const cumplimiento = cumplimientoMensual?.supervisor ?? null
170:   const metaCapitalPen = capitalObjetivo(meta, 'PEN')
171:   const metaCapitalUsd = capitalObjetivo(meta, 'USD')
172:   const capitalConfirmadoPen = cumplimiento ? capitalReal(cumplimiento, 'PEN') : null
173:   const capitalConfirmadoUsd = cumplimiento ? capitalReal(cumplimiento, 'USD') : null
174: 
175:   // LA CONVERSIÓN DEL MES del EQUIPO — total del payload de alcance 'equipo'
176:   // (crm.conversion_mensual_fn), no el cumplimiento: la definición acordada
177:   // llega ya, sin esperar a la migración B (E1, plan §4bis). El total viene
178:   // RECALCULADO del servidor (suma÷suma, jamás media de porcentajes).
179:   const esDemoConversion = yo?.demo === true
180:   const qConversionMensual = useConversionMensual(
181:     !esDemoConversion,
182:     periodoVigente,
183:     'equipo',

### supabase/migrations/20261015000852_crm_plazo_carga_mes.sql:1250-1450
1250:   select coalesce(jsonb_agg(jsonb_build_object(
1251:     'persona_id', f.persona_id,
1252:     'nombre', f.nombre,
1253:     'rol_crm', f.rol_crm,
1254:     'motivo', f.motivo,
1255:     'conversion', case when cv.analista_id is null then null else jsonb_build_object(
1256:       'divisor', coalesce(cv.divisor, 0),
1257:       'divisor_aproximado', coalesce(cv.divisor_aproximado, 0),
1258:       'divisor_por_motivo', coalesce(cv.divisor_por_motivo, '{}'::jsonb),
1259:       'cierres_no_referidos', coalesce(cv.cierres_no_referidos, 0),
1260:       'cierres_referidos', coalesce(cv.cierres_referidos, 0),
1261:       'cierres_de_arrastre', coalesce(cv.cierres_de_arrastre, 0),
1262:       'referidos_recibidos', coalesce(cv.referidos_recibidos, 0),
1263:       'numerador', coalesce(cv.numerador, 0)
1264:     ) end,
1265:     'detalles', det.detalles,
1266:     'cartera', jsonb_build_object(
1267:       'conversiones_clientes', coalesce(car.conversiones_clientes, 0),
1268:       'conversiones_renovacion', coalesce(car.conversiones_renovacion, 0),
1269:       'conversiones_upgrade', coalesce(car.conversiones_upgrade, 0),
1270:       'operaciones_renovacion', coalesce(car.operaciones_renovacion, 0),
1271:       'operaciones_upgrade', coalesce(car.operaciones_upgrade, 0),
1272:       'capital_renovado_pen', coalesce(car.capital_renovado_pen, 0),
1273:       'capital_renovado_usd', coalesce(car.capital_renovado_usd, 0),
1274:       'capital_adicional_pen', coalesce(car.capital_adicional_pen, 0),
1275:       'capital_adicional_usd', coalesce(car.capital_adicional_usd, 0),
1276:       'renovaciones_sin_desglose', coalesce(car.renovaciones_sin_desglose, 0)
1277:     )
1278:   ) order by f.nombre, f.persona_id), '[]'::jsonb)
1279:     into v_fuera_ranking
1280:   from fuera f
1281:   left join conv cv on cv.analista_id = f.persona_id
1282:   left join car on car.vendedor_id = f.persona_id
1283:   left join lateral (
1284:     select jsonb_agg(jsonb_build_object(
1285:       'categoria', d.categoria,
1286:       'moneda', d.moneda,
1287:       'capital_objetivo', 0,
1288:       'capital_real', coalesce(pr.capital_real, 0),
1289:       'capital_cumplimiento_pct', null,
1290:       'contratos_objetivo', 0,
1291:       'contratos_real', coalesce(pr.contratos_real, 0),
1292:       'contratos_cumplimiento_pct', null,
1293:       'capital_ajuste', 0,
1294:       'contratos_ajuste', 0
1295:     ) order by array_position(
1296:       array['nuevo','renovacion','upgrade'], d.categoria
1297:     ), d.moneda) as detalles
1298:     from (values
1299:       ('nuevo'::text, 'PEN'::text), ('nuevo', 'USD'),
1300:       ('renovacion', 'PEN'), ('renovacion', 'USD'),
1301:       ('upgrade', 'PEN'), ('upgrade', 'USD')
1302:     ) d(categoria, moneda)
1303:     left join prod pr on pr.vendedor_id = f.persona_id
1304:       and pr.categoria = d.categoria and pr.moneda = d.moneda
1305:   ) det on true;
1306: 
1307:   v_cobertura := v_cobertura || jsonb_build_object(
1308:     'fuera_ranking', v_fuera_ranking
1309:   );
1310: 
1311:   -- Sin analista forma parte del total de empresa, no del ranking de personas.
1312:   -- Se congela junto a la foto; una asignación posterior no reescribe el cierre.
1313:   v_cobertura := v_cobertura || coalesce((
1314:     select jsonb_build_object('conversion_sin_analista', to_jsonb(cm) - 'analista_id')
1315:     from private.conversion_mensual_por_vendedor(v_ini, v_fin, true, '{}'::uuid[], v_factor) cm
1316:     where cm.analista_id is null
1317:   ), '{}'::jsonb);
1318: 
1319:   -- Tope de referidos (07/10/2026): el aporte EXACTO de los referidos por analista queda en la foto. El porcentaje de cada fila está
1320:   -- redondeado y es NULL para quien solo recibe referidos (divisor 0); el total de «aporta» se sirve de aquí, nunca se reconstruye.
1321:   if private.tope_referidos_conversion(p_periodo) is not null then
1322:     v_cobertura := v_cobertura || jsonb_build_object('referidos_aporte', coalesce((
1323:       select jsonb_object_agg(coalesce(r.analista_id::text, 'sin_analista'), r.aporte)
1324:       from private.referidos_aporte_por_analista(v_ini, v_fin, p_periodo, true, '{}'::uuid[], v_factor) r
1325:     ), '{}'::jsonb));
1326:   end if;
1327: 
1328:   -- El peso de la RENOVACION se guarda CON la foto desde el 23/09/2026. Antes
1329:   -- solo se guardaba el del referido, y el de renovacion se RECONSTRUIA a
1330:   -- partir de el al leer: mientras los dos valieron lo mismo no se noto, pero
1331:   -- en cuanto se separan (migracion 20260923155859) un mes sellado contaria la
1332:   -- renovacion con un peso que no es el que se uso. Y eso, una vez sellado, ya
1333:   -- no se puede recuperar: la foto es la unica memoria de con que se calculo.
1334:   -- Tope de referidos (07/10/2026): la foto guarda el tope con el que se calculó el mes, igual que guarda los pesos.
1335:   insert into crm.periodos_cerrados (
1336:     periodo, cerrado_por, automatico, ponderacion_referido, ponderacion_renovacion,
1337:     tope_referidos_pct, meta_revision, cobertura
1338:   ) values (
1339:     p_periodo,
1340:     case when v_automatico then null else v_uid end,
1341:     v_automatico, v_factor, private.peso_renovacion_conversion(p_periodo),
1342:     private.tope_referidos_conversion(p_periodo),
1343:     v_revision, v_cobertura
1344:   );
1345: 
1346:   -- 5) La foto. El conjunto de personas es el ROSTER DEL MES (quien tenia meta),
1347:   --    en union con quien PRODUJO aunque no tuviera meta: los dos importan para
1348:   --    una foto de pago, y quien produjo sin meta tiene que quedar registrado
1349:   --    con su nombre en vez de disolverse en un agregado anonimo — que es lo que
1350:   --    hace la pantalla viva, y esta bien alli (privacidad) y mal aqui (pago).
1351:   with conv as (
1352:     select cm.*
1353:     from private.conversion_mensual_por_vendedor(v_ini, v_fin, true, '{}'::uuid[], v_factor) cm
1354:   ), prod as (
1355:     select r.vendedor_id, r.categoria, r.moneda, r.contratos_real, r.capital_real
1356:     from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
1357:   ), car as (
1358:     select m.* from private.metricas_cartera_por_vendedor(p_periodo) m
1359:   ), roster as (
1360:     -- `distinct on`: una fila por persona, pase lo que pase. La foto tiene la
1361:     -- clave (periodo, vendedor), asi que dos metas del mismo vendedor en el
1362:     -- mismo periodo harian reventar el cierre entero con un duplicado — un mes
1363:     -- que no se puede cerrar por una fila repetida es peor que el duplicado.
1364:     -- (Lo cazo el oraculo ejecutando, no leyendo.)
1365:     select distinct on (mv.vendedor_id)
1366:       mv.vendedor_id, mv.supervisor_id, mv.conversion_objetivo, mv.id as meta_vendedor_id
1367:     from crm.metas_vendedor mv
1368:     where mv.meta_periodo_id = v_periodo_id
1369:     order by mv.vendedor_id, mv.id
1370:   ), personas as (
1371:     select vendedor_id from roster
1372:     union
1373:     select analista_id from conv
1374:     union
1375:     select vendedor_id from prod where vendedor_id is not null
1376:     union
1377:     select vendedor_id from car where vendedor_id is not null
1378:   ), foto as (
1379:     select
1380:       pe.vendedor_id,
1381:       r.meta_vendedor_id,
1382:       coalesce(r.supervisor_id, supervisor_actual.perfil_id) as supervisor_id,
1383:       coalesce(r.conversion_objetivo, 0::numeric) as conversion_objetivo
1384:     from personas pe
1385:     left join roster r on r.vendedor_id = pe.vendedor_id
1386:     left join crm.equipo vendedor_actual
1387:       on vendedor_actual.perfil_id = pe.vendedor_id
1388:     left join crm.equipo supervisor_actual
1389:       on supervisor_actual.perfil_id = vendedor_actual.supervisor_id
1390:      and supervisor_actual.rol_crm = 'supervisor'
1391:     where r.meta_vendedor_id is not null
1392:        or (
1393:          vendedor_actual.rol_crm = 'vendedor'
1394:          and supervisor_actual.perfil_id is not null
1395:        )
1396:   )
1397:   insert into crm.cierre_mes_vendedor (
1398:     periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre,
1399:     divisor, divisor_aproximado, divisor_por_motivo,
1400:     cierres_no_referidos, cierres_referidos, cierres_de_arrastre,
1401:     numerador, conversion_pct, estado,
1402:     referidos_recibidos, referidos_dados_de_alta, referidos_aporta_pct, procedencia,
1403:     ajuste_numerador, ajuste_pen, ajuste_usd,
1404:     conversion_objetivo, detalles, cartera
1405:   )
1406:   select
1407:     p_periodo,
1408:     pe.vendedor_id,
1409:     coalesce(nullif(btrim(pf.nombre_completo), ''),
1410:              '(sin nombre · ' || left(pe.vendedor_id::text, 8) || ')'),
1411:     pe.supervisor_id,
1412:     coalesce(nullif(btrim(sup.nombre_completo), ''), '(sin ficha)'),
1413:     coalesce(c.divisor, 0),
1414:     coalesce(c.divisor_aproximado, 0),
1415:     coalesce(c.divisor_por_motivo, '{}'::jsonb),
1416:     coalesce(c.cierres_no_referidos, 0),
1417:     coalesce(c.cierres_referidos, 0),
1418:     coalesce(c.cierres_de_arrastre, 0),
1419:     -- NETO: lo bruto menos lo que este mes absorbio de deudas viejas. Es lo que
1420:     -- se paga, asi que es lo que se sella.
1421:     coalesce(c.numerador, 0::numeric) - sal.aplicado_numerador,
1422:     case when coalesce(c.divisor, 0) > 0
1423:       then round(100.0 * (coalesce(c.numerador, 0::numeric) - sal.aplicado_numerador)
1424:                  / coalesce(c.divisor, 0), 2) end,
1425:     case
1426:       when coalesce(c.divisor, 0) > 0 then 'medible'
1427:       when coalesce(c.referidos_recibidos, 0) > 0 then 'solo_referidos'
1428:       when coalesce(c.cierres_no_referidos, 0) + coalesce(c.cierres_referidos, 0) > 0 then 'solo_arrastre'
1429:       else 'sin_actividad'
1430:     end,
1431:     coalesce(c.referidos_recibidos, 0),
1432:     coalesce(alta.dados_de_alta, 0),
1433:     c.referidos_aporta_pct,
1434:     coalesce(c.procedencia, '[]'::jsonb),
1435:     sal.aplicado_numerador,
1436:     sal.aplicado_pen,
1437:     sal.aplicado_usd,
1438:     pe.conversion_objetivo,
1439:     coalesce(det.detalles, '[]'::jsonb),
1440:     jsonb_build_object(
1441:       'conversiones_clientes', coalesce(car.conversiones_clientes, 0),
1442:       'conversiones_renovacion', coalesce(car.conversiones_renovacion, 0),
1443:       'conversiones_upgrade', coalesce(car.conversiones_upgrade, 0),
1444:       'operaciones_renovacion', coalesce(car.operaciones_renovacion, 0),
1445:       'operaciones_upgrade', coalesce(car.operaciones_upgrade, 0),
1446:       'capital_renovado_pen', coalesce(car.capital_renovado_pen, 0),
1447:       'capital_renovado_usd', coalesce(car.capital_renovado_usd, 0),
1448:       'capital_adicional_pen', coalesce(car.capital_adicional_pen, 0),
1449:       'capital_adicional_usd', coalesce(car.capital_adicional_usd, 0),
1450:       'renovaciones_sin_desglose', coalesce(car.renovaciones_sin_desglose, 0)

### Protocolo de auditor RLS
---
name: auditor-rls
description: Auditor de seguridad RLS del esquema crm. Usar PROACTIVAMENTE sobre toda migración SQL nueva que toque tablas, policies, funciones o grants del CRM, antes del gate de test-rls.
tools: Read, Grep, Glob
---

Eres un auditor de seguridad de PostgreSQL/Supabase especializado en RLS, revisando
migraciones del esquema `crm` de CRM-Avance-Corp. Responde SIEMPRE en español.

ROLE: SECONDARY_REVIEWER. Sigue `.ai/REVIEW_PROTOCOL.md`: solo analiza, no
modifiques archivos, no ejecutes agentes ni delegues o inicies otro review.
El PRIMARY adjunta contexto de CodeGraph y decide si esta consulta corresponde
al nivel de riesgo y al presupuesto compartido de 0–2 reviews de la tarea.

Contexto fijo del proyecto:
- Tres roles con visibilidad escalonada: comercial (solo su cartera/subárbol),
  coordinador, gerencia/lector global (`private.es_lector_global()`).
- PII sensible en `crm.leads`: DNI, teléfono, fecha_nacimiento, genero, monto_estimado.
- Ledger inmutable `crm.lead_asignaciones`; log inmutable `crm.actividades`.
- Reglas no negociables: RLS ON al crear la tabla; deny-by-default; sin policy DELETE
  (soft-delete `activo=false`); nada de tocar objetos de `public`; toda tabla `crm.*`
  lleva el trigger de auditoría `private.log_audit_crm` (o `private.log_audit_sin_secretos`,
  con las columnas a enmascarar, si guarda secretos: tokens, claves, contraseñas o credenciales).
- ⚠️ `crm.leads` tiene grants POR COLUMNA: columna nueva sin GRANT explícito = invisible
  para PostgREST (falla silenciosa conocida del proyecto).

Checklist de auditoría sobre cada `.sql` bajo revisión:

1. **RLS**: ¿toda tabla nueva tiene `ENABLE ROW LEVEL SECURITY` en el mismo bloque?
   ¿Las policies son deny-by-default (nada de `USING (true)` sin justificación)? ¿Existe
   alguna policy DELETE? (prohibido).
2. **Fugas entre roles**: ¿puede un comercial ver leads/clientes fuera de su subárbol?
   ¿Un miembro con `activo=false` conserva lecturas? ¿Alguna vista o función expone PII
   cross-rol? Compara contra los patrones ya aceptados (`clientes_basicos_fn` gateada).
3. **SECURITY DEFINER**: cada función definer debe tener `SET search_path` fijo,
   justificación escrita y gate interno de rol. Vistas: preferir invoker + función
   definer gateada (patrón del proyecto); `security_definer_view` es hallazgo ERROR.
4. **Grants**: mínimos necesarios; en `crm.leads`, grants por columna presentes para
   toda columna nueva. ¿Se revoca lo que sobra (hardening)? ¿`service_role` pierde o gana
   EXECUTE sin que el ledger lo documente?
5. **Inmutabilidad**: ¿la migración debilita triggers de inmutabilidad de actividades o
   del ledger de asignaciones?
6. **`public` intocable**: cualquier statement sobre objetos de `public` es hallazgo
   BLOQUEANTE salvo que el ledger documente OK explícito de Miguel.
7. **Matriz de pruebas**: ¿`supabase/scripts/test-rls.mjs` cubre los casos nuevos
   (permitido Y denegado por rol)? Si no, señalar exactamente qué casos faltan.
8. **Ledger**: ¿`MIGRACIONES.md` tiene la fila nueva con estado honesto?

Formato de salida: `.ai/REVIEW_PROTOCOL.md`, con VERDICT, hallazgos P0–P3,
archivo:línea, evidencia, impacto y fix propuesto. Si no hay hallazgos,
decláralo explícitamente junto con qué verificaste. No modifiques archivos.

### Apoyo de JEV: orden de relevancia documental (NO veredicto financiero ni de permisos)
{
  "consulta": "¿Qué extractos explican cómo incorporar ventas propias de supervisores a la meta del equipo, preservando atribución, visibilidad y meses cerrados, y ubicarlos al final del ranking?",
  "corte": 2,
  "extractos": [
    {
      "de": "app/src/lib/objetivos.ts:660-752",
      "puntos": 2.14,
      "confianza": 0.72
    },
    {
      "de": "supabase/scripts/supervisores-metas/vivo/crm.cumplimiento_metas_fn.sql:1-200",
      "puntos": 2,
      "confianza": 0.69
    },
    {
      "de": "app/src/screens/hoy/ranking-vendedores.tsx:574-650",
      "puntos": 1.82,
      "confianza": 0.61
    },
    {
      "de": "supabase/migrations/20261015000852_crm_plazo_carga_mes.sql:1250-1450",
      "puntos": 1.73,
      "confianza": 0.6
    },
    {
      "de": "app/src/lib/objetivos.ts:346-375",
      "puntos": 1.66,
      "confianza": 0.64
    },
    {
      "de": "supabase/migrations/20260807203757_crm_metas_sla_versionados.sql:35-50",
      "puntos": 1.55,
      "confianza": 0.54
    },
    {
      "de": "app/src/screens/hoy/ranking-vendedores.tsx:708-773",
      "puntos": 1.33,
      "confianza": 0.32
    },
    {
      "de": "app/src/screens/hoy/datos-supervisor.ts:164-183",
      "puntos": 0.84,
      "confianza": 0.17
    }
  ]
}
### Complemento escritor del sello: 20261015000852_crm_plazo_carga_mes.sql:1205-1310
1205:       v_ini, v_fin, true, '{}'::uuid[], v_factor
1206:     ) cm
1207:   ), prod as materialized (
1208:     select r.*
1209:     from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
1210:   ), car as materialized (
1211:     select m.* from private.metricas_cartera_por_vendedor(p_periodo) m
1212:   ), roster as materialized (
1213:     select distinct mv.vendedor_id
1214:     from crm.metas_vendedor mv
1215:     where mv.meta_periodo_id = v_periodo_id
1216:   ), personas as (
1217:     select c.analista_id as persona_id from conv c where c.analista_id is not null
1218:     union
1219:     select p.vendedor_id from prod p where p.vendedor_id is not null
1220:     union
1221:     select c.vendedor_id from car c where c.vendedor_id is not null
1222:   ), elegibles as (
1223:     select r.vendedor_id as persona_id from roster r
1224:     union
1225:     select p.persona_id
1226:     from personas p
1227:     join crm.equipo e
1228:       on e.perfil_id = p.persona_id and e.rol_crm = 'vendedor'
1229:     join crm.equipo s
1230:       on s.perfil_id = e.supervisor_id and s.rol_crm = 'supervisor'
1231:   ), fuera as (
1232:     select
1233:       p.persona_id,
1234:       coalesce(nullif(btrim(pf.nombre_completo), ''),
1235:                '(sin nombre · ' || left(p.persona_id::text, 8) || ')') as nombre,
1236:       coalesce(e.rol_crm, 'fuera_equipo') as rol_crm,
1237:       case
1238:         when e.rol_crm = 'vendedor' then 'analista_sin_supervisor'
1239:         when e.rol_crm = 'supervisor' then 'supervisor'
1240:         when e.rol_crm = 'gerencia' then 'gerencia'
1241:         else 'fuera_estructura'
1242:       end as motivo
1243:     from personas p
1244:     left join crm.equipo e on e.perfil_id = p.persona_id
1245:     left join public.perfiles pf on pf.id = p.persona_id
1246:     where not exists (
1247:       select 1 from elegibles ok where ok.persona_id = p.persona_id
1248:     )
1249:   )
1250:   select coalesce(jsonb_agg(jsonb_build_object(
1251:     'persona_id', f.persona_id,
1252:     'nombre', f.nombre,
1253:     'rol_crm', f.rol_crm,
1254:     'motivo', f.motivo,
1255:     'conversion', case when cv.analista_id is null then null else jsonb_build_object(
1256:       'divisor', coalesce(cv.divisor, 0),
1257:       'divisor_aproximado', coalesce(cv.divisor_aproximado, 0),
1258:       'divisor_por_motivo', coalesce(cv.divisor_por_motivo, '{}'::jsonb),
1259:       'cierres_no_referidos', coalesce(cv.cierres_no_referidos, 0),
1260:       'cierres_referidos', coalesce(cv.cierres_referidos, 0),
1261:       'cierres_de_arrastre', coalesce(cv.cierres_de_arrastre, 0),
1262:       'referidos_recibidos', coalesce(cv.referidos_recibidos, 0),
1263:       'numerador', coalesce(cv.numerador, 0)
1264:     ) end,
1265:     'detalles', det.detalles,
1266:     'cartera', jsonb_build_object(
1267:       'conversiones_clientes', coalesce(car.conversiones_clientes, 0),
1268:       'conversiones_renovacion', coalesce(car.conversiones_renovacion, 0),
1269:       'conversiones_upgrade', coalesce(car.conversiones_upgrade, 0),
1270:       'operaciones_renovacion', coalesce(car.operaciones_renovacion, 0),
1271:       'operaciones_upgrade', coalesce(car.operaciones_upgrade, 0),
1272:       'capital_renovado_pen', coalesce(car.capital_renovado_pen, 0),
1273:       'capital_renovado_usd', coalesce(car.capital_renovado_usd, 0),
1274:       'capital_adicional_pen', coalesce(car.capital_adicional_pen, 0),
1275:       'capital_adicional_usd', coalesce(car.capital_adicional_usd, 0),
1276:       'renovaciones_sin_desglose', coalesce(car.renovaciones_sin_desglose, 0)
1277:     )
1278:   ) order by f.nombre, f.persona_id), '[]'::jsonb)
1279:     into v_fuera_ranking
1280:   from fuera f
1281:   left join conv cv on cv.analista_id = f.persona_id
1282:   left join car on car.vendedor_id = f.persona_id
1283:   left join lateral (
1284:     select jsonb_agg(jsonb_build_object(
1285:       'categoria', d.categoria,
1286:       'moneda', d.moneda,
1287:       'capital_objetivo', 0,
1288:       'capital_real', coalesce(pr.capital_real, 0),
1289:       'capital_cumplimiento_pct', null,
1290:       'contratos_objetivo', 0,
1291:       'contratos_real', coalesce(pr.contratos_real, 0),
1292:       'contratos_cumplimiento_pct', null,
1293:       'capital_ajuste', 0,
1294:       'contratos_ajuste', 0
1295:     ) order by array_position(
1296:       array['nuevo','renovacion','upgrade'], d.categoria
1297:     ), d.moneda) as detalles
1298:     from (values
1299:       ('nuevo'::text, 'PEN'::text), ('nuevo', 'USD'),
1300:       ('renovacion', 'PEN'), ('renovacion', 'USD'),
1301:       ('upgrade', 'PEN'), ('upgrade', 'USD')
1302:     ) d(categoria, moneda)
1303:     left join prod pr on pr.vendedor_id = f.persona_id
1304:       and pr.categoria = d.categoria and pr.moneda = d.moneda
1305:   ) det on true;
1306: 
1307:   v_cobertura := v_cobertura || jsonb_build_object(
1308:     'fuera_ranking', v_fuera_ranking
1309:   );
1310: 
