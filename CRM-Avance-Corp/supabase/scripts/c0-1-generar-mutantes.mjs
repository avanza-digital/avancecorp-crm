#!/usr/bin/env node

import { createHash } from 'node:crypto';
import {
  mkdirSync,
  readFileSync,
  writeFileSync,
} from 'node:fs';
import { join } from 'node:path';

const SIGNATURE_METRICAS = 'crm.metricas_vendedores_fn()';
const SIGNATURE_CARTERA = 'private.metricas_cartera_por_vendedor(date)';

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function functionSlice(sql, signature) {
  const qualifiedName = signature.slice(0, signature.indexOf('('));
  const starts = [...sql.matchAll(new RegExp(
    `create\\s+or\\s+replace\\s+function\\s+${escapeRegex(qualifiedName)}\\s*\\(`,
    'ig',
  ))];
  if (starts.length !== 1 || starts[0].index == null) {
    throw new Error(`${signature}: se esperaba un unico cuerpo candidato`);
  }

  const ddlStart = starts[0].index;
  const afterStart = sql.slice(ddlStart);
  const opening = /\bas\s+(\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$)/i.exec(afterStart);
  if (!opening) throw new Error(`${signature}: falta dollar quote`);
  const tag = opening[1];
  const bodyStart = ddlStart + opening.index + opening[0].length;
  const bodyEnd = sql.indexOf(tag, bodyStart);
  if (bodyEnd < 0) throw new Error(`${signature}: dollar quote sin cerrar`);
  let ddlEnd = bodyEnd + tag.length;
  if (sql[ddlEnd] === ';') ddlEnd += 1;

  return {
    body: sql.slice(bodyStart, bodyEnd),
    bodyEnd,
    bodyStart,
    ddlEnd,
    ddlStart,
  };
}

function op(before, after, count = 1) {
  return { after, before, count };
}

const teamPct = `      case
        when v_conversion_publicable
          and cobertura.completa
          and coalesce(ne.nucleo_divisor, 0) > 0
        then round(
          100.0
          * coalesce(ne.nucleo_numerador, 0::numeric)
          / ne.nucleo_divisor,
          2
        )
      end as nucleo_conversion_pct`;

const parsedNumerator = `      (e.value ->> 'numerador')::numeric as numerador,
      case
        when pg_catalog.jsonb_typeof(
          e.value -> 'conversion_pct'
        ) = 'number'
        then (e.value ->> 'conversion_pct')::numeric
      end as conversion_pct`;

const mutations = [
  {
    id: '01',
    slug: 'avg_porcentajes',
    signature: SIGNATURE_METRICAS,
    stage: 'bank',
    sqlstate: 'P0001',
    oracle: 'C01-BASE bundle exacto parcial o incoherente',
    operations: [
      op(
        '      sum(nm.numerador)::numeric as nucleo_numerador',
        `      sum(nm.numerador)::numeric as nucleo_numerador,
      avg(nm.conversion_pct)::numeric as promedio_pct`,
      ),
      op(
        teamPct,
        `      case
        when v_conversion_publicable
          and cobertura.completa
          and coalesce(ne.nucleo_divisor, 0) > 0
        then round(ne.promedio_pct, 2)
      end as nucleo_conversion_pct`,
      ),
    ],
  },
  {
    id: '02',
    slug: 'formula_legacy_asignados',
    signature: SIGNATURE_METRICAS,
    stage: 'proposal',
    sqlstate: 'P0001',
    oracle: 'POSTFLIGHT C0.1: reaparecio una formula paralela',
    operations: [
      op(
        `      stats.capital_usd,
      coalesce(ne.convertidos, 0)::int as convertidos,`,
        `      stats.capital_usd,
      greatest(stats.activos, 1)::int as asignados_total,
      coalesce(ne.convertidos, 0)::int as convertidos,`,
      ),
      op(
        teamPct,
        `      case
        when v_conversion_publicable and cobertura.completa
        then round(
          100.0 * coalesce(ne.convertidos, 0)
          / greatest(stats.activos, 1),
          2
        )
      end as nucleo_conversion_pct`,
      ),
    ],
  },
  {
    id: '03',
    slug: 'propietario_actual',
    signature: SIGNATURE_METRICAS,
    stage: 'bank',
    sqlstate: 'P0001',
    oracle: 'C01-BASE oraculo dinamico:',
    operations: [
      op(
        `      nullif(e.value ->> 'supervisor_id', '')::uuid
        as supervisor_id,
      (e.value ->> 'divisor')::int as divisor,`,
        `      coalesce(
        (
          select actual.supervisor_id
          from crm.lead_asignaciones la_actual
          join crm.leads l_actual on l_actual.id = la_actual.lead_id
          join crm.equipo actual on actual.perfil_id = l_actual.vendedor_id
          where la_actual.analista_id =
            (e.value ->> 'vendedor_id')::uuid
            and la_actual.resultado = 'convertido'
          order by la_actual.resultado_en, la_actual.id
          limit 1
        ),
        nullif(e.value ->> 'supervisor_id', '')::uuid
      ) as supervisor_id,
      (e.value ->> 'divisor')::int as divisor,`,
      ),
    ],
  },
  {
    id: '04',
    slug: 'sin_cartera_en_numerador',
    signature: SIGNATURE_METRICAS,
    stage: 'bank',
    sqlstate: 'P0001',
    oracle: 'C01-BASE oraculo dinamico:',
    operations: [
      op(
        parsedNumerator,
        `      greatest(
        (e.value ->> 'numerador')::numeric
        - (e.value #>> '{cartera,conversiones_clientes}')::numeric,
        0::numeric
      ) as numerador,
      case
        when (e.value ->> 'divisor')::numeric > 0
        then round(
          100.0 * greatest(
            (e.value ->> 'numerador')::numeric
            - (e.value #>> '{cartera,conversiones_clientes}')::numeric,
            0::numeric
          ) / (e.value ->> 'divisor')::numeric,
          2
        )
      end as conversion_pct`,
      ),
    ],
  },
  {
    id: '05',
    slug: 'cartera_dentro_convertidos',
    signature: SIGNATURE_METRICAS,
    stage: 'bank',
    sqlstate: 'P0001',
    oracle: 'C01-BASE fuera-de-roster no quedo exclusivamente en el total',
    operations: [
      op(
        `      sum(
        nm.cierres_no_referidos
        + nm.cierres_referidos
      )::int as convertidos,`,
        `      sum(
        nm.cierres_no_referidos
        + nm.cierres_referidos
        + nm.operaciones_cartera
      )::int as convertidos,`,
      ),
    ],
  },
  {
    id: '06',
    slug: 'numerador_bruto_sin_ajuste',
    signature: SIGNATURE_METRICAS,
    stage: 'bank',
    sqlstate: 'P0001',
    oracle: 'C01-BASE oraculo dinamico:',
    operations: [
      op(
        parsedNumerator,
        `      (
        (e.value ->> 'numerador')::numeric
        + coalesce((
          select ap.numerador
          from private.ajuste_pendiente_por_vendedor() ap
          where ap.vendedor_id = (e.value ->> 'vendedor_id')::uuid
        ), 0::numeric)
      ) as numerador,
      case
        when (e.value ->> 'divisor')::numeric > 0
        then round(
          100.0 * (
            (e.value ->> 'numerador')::numeric
            + coalesce((
              select ap.numerador
              from private.ajuste_pendiente_por_vendedor() ap
              where ap.vendedor_id = (e.value ->> 'vendedor_id')::uuid
            ), 0::numeric)
          ) / (e.value ->> 'divisor')::numeric,
          2
        )
      end as conversion_pct`,
      ),
    ],
  },
  {
    id: '07',
    slug: 'piso_despues_de_agregar',
    signature: SIGNATURE_METRICAS,
    stage: 'bank',
    sqlstate: 'P0001',
    oracle: 'C01-BASE oraculo dinamico:',
    operations: [
      op(
        '      sum(nm.numerador)::numeric as nucleo_numerador',
        `      greatest(
        coalesce((
          select sum(bruto.numerador)
          from private.conversion_mensual_por_vendedor(
            v_mes::timestamp at time zone 'America/Lima',
            (v_mes + interval '1 month')::timestamp
              at time zone 'America/Lima',
            true,
            '{}'::uuid[],
            v_factor
          ) bruto
          join private.roster_metas_vendedores() rb
            on rb.vendedor_id = bruto.analista_id
          where rb.supervisor_id = nm.supervisor_id
        ), 0::numeric)
        - coalesce((
          select sum(ap.numerador)
          from private.ajuste_pendiente_por_vendedor() ap
          join private.roster_metas_vendedores() ra
            on ra.vendedor_id = ap.vendedor_id
          where ra.supervisor_id = nm.supervisor_id
        ), 0::numeric),
        0::numeric
      )::numeric as nucleo_numerador`,
      ),
    ],
  },
  {
    id: '08',
    slug: 'null_coalesce_cero',
    signature: SIGNATURE_METRICAS,
    stage: 'bank',
    sqlstate: 'P0001',
    oracle: 'C01-BASE bundle exacto parcial o incoherente',
    operations: [
      op(
        teamPct,
        `${teamPct.replace(
          '        )\n      end as nucleo_conversion_pct',
          '        )\n        else 0::numeric\n      end as nucleo_conversion_pct',
        )}`,
      ),
    ],
  },
  {
    id: '09',
    slug: 'redondeo_entero',
    signature: SIGNATURE_METRICAS,
    stage: 'bank',
    sqlstate: 'P0001',
    oracle: 'C01-BASE bundle exacto parcial o incoherente',
    operations: [
      op(teamPct, teamPct.replace('          2\n        )', '          0\n        )')),
    ],
  },
  {
    id: '10',
    slug: 'techo_cien',
    signature: SIGNATURE_METRICAS,
    stage: 'bank',
    sqlstate: 'P0001',
    oracle: 'C01-BASE bundle exacto parcial o incoherente',
    operations: [
      op(
        teamPct,
        `      case
        when v_conversion_publicable
          and cobertura.completa
          and coalesce(ne.nucleo_divisor, 0) > 0
        then least(
          100::numeric,
          round(
            100.0
            * coalesce(ne.nucleo_numerador, 0::numeric)
            / ne.nucleo_divisor,
            2
          )
        )
      end as nucleo_conversion_pct`,
      ),
    ],
  },
  {
    id: '11',
    slug: 'doble_cliente_mes',
    signature: SIGNATURE_CARTERA,
    stage: 'bank',
    sqlstate: 'P0001',
    oracle: 'C01-CARTERA helper altero conteos/economia preservada:',
    operations: [
      op(
        `    ) e
    where e.tipo = 'operacion'
  ), conversion as (`,
        `    ) e
    join ops o
      on o.vendedor_id = e.analista_id
    where e.tipo = 'operacion'
  ), conversion as (`,
      ),
    ],
  },
  {
    id: '12',
    slug: 'fuera_roster_en_equipo',
    signature: SIGNATURE_METRICAS,
    stage: 'bank',
    sqlstate: 'P0001',
    oracle: 'C01-BASE fuera-de-roster no quedo exclusivamente en el total',
    operations: [
      op(
        `      sum(
        nm.cierres_no_referidos
        + nm.cierres_referidos
      )::int as convertidos,`,
        `      (
        sum(
          nm.cierres_no_referidos
          + nm.cierres_referidos
        ) + case when nm.supervisor_id = (
          select r.supervisor_id
          from private.roster_metas_vendedores() r
          order by r.supervisor_id
          limit 1
        ) then (v_mensual #>>
          '{cobertura,fuera_de_roster,cierres}')::int
        else 0 end
      )::int as convertidos,`,
      ),
    ],
  },
  {
    id: '13',
    slug: 'sin_guarda_duplicados',
    signature: SIGNATURE_METRICAS,
    stage: 'bank',
    sqlstate: 'P0001',
    oracle: 'C01-COBERTURA mutante duplicado sobrevivio',
    operations: [
      op('    having count(*) > 1', '    having count(*) > 1000000'),
    ],
  },
  {
    id: '14',
    slug: 'full_join_sin_pierna_extra',
    signature: SIGNATURE_METRICAS,
    stage: 'bank',
    sqlstate: 'P0001',
    oracle: 'C01-COBERTURA mutante extra_rol sobrevivio',
    operations: [
      op(
        `    where x.vendedor_id is null       -- fila extra / rol no vendedor / fuera
       or r.vendedor_id is null       -- vendedor canonico visible faltante
       or r.supervisor_id is distinct from x.supervisor_id
                                      -- equipo inesperado o contaminado`,
        `    where r.vendedor_id is null       -- vendedor canonico visible faltante
       or (
         x.vendedor_id is not null
         and r.vendedor_id is not null
         and r.supervisor_id is distinct from x.supervisor_id
       )                              -- equipo inesperado o contaminado`,
      ),
    ],
  },
  {
    id: '15',
    slug: 'clave_exacta_omitida',
    signature: SIGNATURE_METRICAS,
    stage: 'bank',
    sqlstate: 'P0001',
    oracle: 'C01-BASE fila de vendedor exacta incompleta',
    operations: [
      op(
        `            'nucleo_conversion_pct',
              pv.nucleo_conversion_pct,
            'sin_tocar',`,
        `            'sin_tocar',`,
      ),
    ],
  },
  {
    id: '16',
    slug: 'coordinador_sin_salida_vacia',
    signature: SIGNATURE_METRICAS,
    stage: 'bank',
    sqlstate: 'P0001',
    oracle: 'C01-ROLES coordinador no quedo vacio:',
    operations: [
      op(
        `  if v_rol = 'coordinador' and not coalesce(v_lector, false) then
    return jsonb_build_object(
      'version', 1,
      'generado_en', v_ahora,
      'ventana_convertidos_dias', 45,
      'ventana_metrica', 'mes_calendario',
      'mes_metrica', v_mes,
      'peso_referido', v_factor,
      'cobertura_conversion', null,
      'nucleo_total', jsonb_build_object(
        'nucleo_convertidos', null,
        'operaciones_cartera', null,
        'nucleo_divisor', null,
        'nucleo_numerador', null,
        'nucleo_conversion_pct', null
      ),
      'vendedores', '[]'::jsonb,
      'equipos', '[]'::jsonb
    );
  end if;`,
        `  if v_rol = 'coordinador' and not coalesce(v_lector, false) then
    perform pg_catalog.set_config(
      'request.jwt.claim.sub',
      (
        select e.perfil_id::text
        from crm.equipo e
        where e.rol_crm = 'gerencia' and e.activo
        order by e.perfil_id
        limit 1
      ),
      true
    );
    v_uid := (select auth.uid());
    v_rol := private.rol_crm(v_uid);
    v_lector := private.es_lector_global();
    v_visibles := array(
      select private.vendedor_ids_visibles(v_uid)
    );
    v_global := true;
    v_alcance := 'global';
  end if;`,
      ),
    ],
  },
  {
    id: '17',
    slug: 'sin_ambito_abiertos',
    signature: SIGNATURE_METRICAS,
    stage: 'bank',
    sqlstate: 'P0001',
    oracle: 'C01-BASE S1 incorrecto:',
    operations: [
      op(
        `      (l.etapa not in ('convertido', 'descartado')) as abierto`,
        '      true as abierto',
      ),
    ],
  },
];

function parseTsv(path) {
  return readFileSync(path, 'utf8')
    .trim()
    .split('\n')
    .filter(Boolean)
    .map((line) => line.split('\t'));
}

function replaceOperation(body, mutation, operation) {
  const occurrences = body.split(operation.before).length - 1;
  if (occurrences !== operation.count) {
    throw new Error(
      `${mutation.id}-${mutation.slug}: sustitucion no exacta `
      + `(esperada ${operation.count}, encontrada ${occurrences})`,
    );
  }
  if (operation.before === operation.after) {
    throw new Error(`${mutation.id}-${mutation.slug}: sustitucion vacia`);
  }
  return body.split(operation.before).join(operation.after);
}

function generate(args) {
  const [proposalPath, candidatePath, replacementPath, outputDir, manifestPath] = args;
  if (!manifestPath) {
    throw new Error(
      'uso generate: propuesta candidatos reemplazos directorio manifest',
    );
  }
  const proposal = readFileSync(proposalPath, 'utf8');
  const replacements = new Map(parseTsv(replacementPath));
  const signatureHashes = new Map();
  for (const [placeholder, signature] of parseTsv(candidatePath)) {
    const hash = replacements.get(placeholder);
    if (!/^[0-9a-f]{32}$/.test(hash ?? '')) {
      throw new Error(`${signature}: hash candidato real ausente`);
    }
    signatureHashes.set(signature, hash);
  }
  if (signatureHashes.size !== 2) {
    throw new Error(`se esperaban dos cuerpos candidatos, hay ${signatureHashes.size}`);
  }

  mkdirSync(outputDir, { mode: 0o700, recursive: false });
  const manifest = [];
  for (const mutation of mutations) {
    const slice = functionSlice(proposal, mutation.signature);
    let body = slice.body;
    let applied = 0;
    for (const operation of mutation.operations) {
      body = replaceOperation(body, mutation, operation);
      applied += operation.count;
    }
    if (body.length === 0 || body === slice.body) {
      throw new Error(`${mutation.id}-${mutation.slug}: cuerpo mutado vacio o identico`);
    }

    let mutated = proposal.slice(0, slice.bodyStart)
      + body
      + proposal.slice(slice.bodyEnd);
    const mutatedSlice = functionSlice(mutated, mutation.signature);
    const ddl = mutated.slice(mutatedSlice.ddlStart, mutatedSlice.ddlEnd);
    if (ddl.length === 0) {
      throw new Error(`${mutation.id}-${mutation.slug}: DDL mutado vacio`);
    }

    const oldHash = signatureHashes.get(mutation.signature);
    const hashOccurrences = mutated.split(oldHash).length - 1;
    if (hashOccurrences < 2) {
      throw new Error(
        `${mutation.id}-${mutation.slug}: hash candidato aparece ${hashOccurrences} veces`,
      );
    }
    const token = `__C01_MUTANT_MD5_${mutation.id}__`;
    mutated = mutated.split(oldHash).join(token);
    if (!mutated.includes(token) || mutated === proposal) {
      throw new Error(`${mutation.id}-${mutation.slug}: plantilla no materializada`);
    }

    const prefix = `${mutation.id}-${mutation.slug}`;
    writeFileSync(join(outputDir, `${prefix}.template.sql`), mutated, { flag: 'wx' });
    writeFileSync(join(outputDir, `${prefix}.ddl.sql`), `${ddl}\n`, { flag: 'wx' });
    manifest.push([
      mutation.id,
      mutation.slug,
      mutation.signature,
      mutation.stage,
      mutation.sqlstate,
      mutation.oracle,
      token,
      applied,
      hashOccurrences,
      sha256(slice.body),
      sha256(body),
    ].join('\t'));
  }
  if (manifest.length !== 17 || new Set(manifest.map((line) => line.slice(0, 2))).size !== 17) {
    throw new Error('la matriz no contiene exactamente 17 mutantes identificables');
  }
  writeFileSync(manifestPath, `${manifest.join('\n')}\n`, { flag: 'wx' });
}

function materialize(args) {
  const [templatePath, token, hash, outputPath] = args;
  if (!outputPath) {
    throw new Error('uso materialize: plantilla token md5 salida');
  }
  if (!/^__C01_MUTANT_MD5_[0-9]{2}__$/.test(token)) {
    throw new Error(`token mutante invalido: ${token}`);
  }
  if (!/^[0-9a-f]{32}$/.test(hash)) {
    throw new Error(`hash mutante invalido: ${hash}`);
  }
  const template = readFileSync(templatePath, 'utf8');
  const occurrences = template.split(token).length - 1;
  if (occurrences < 2) {
    throw new Error(`token ${token} aparece ${occurrences} veces`);
  }
  const output = template.split(token).join(hash);
  if (output === template || /__C01_MUTANT_MD5_[0-9]{2}__/.test(output)) {
    throw new Error('materializacion mutante incompleta');
  }
  writeFileSync(outputPath, output, { flag: 'wx' });
}

const [command, ...args] = process.argv.slice(2);
if (command === 'generate') {
  generate(args);
} else if (command === 'materialize') {
  materialize(args);
} else {
  throw new Error('comando esperado: generate | materialize');
}
