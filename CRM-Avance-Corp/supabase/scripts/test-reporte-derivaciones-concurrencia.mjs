#!/usr/bin/env node

// Sonda destructiva de branch para el orden causal entre derivar y gestionar.
// Debe correr AL FINAL del gate sobre una branch desechable: necesita que una
// derivación haga COMMIT para que otro backend la observe y, por diseño, deja
// el fixture LUIS GARCIA DEMO asignado y con una nota de prueba. Los datos de
// una preview branch no se mezclan a producción y se eliminan con la branch.

import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import process from 'node:process';

const databaseUrl = process.env.TEST_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || 'psql';

if (!databaseUrl) {
  console.error('Falta TEST_DATABASE_URL de la branch desechable.');
  process.exit(2);
}

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function runPsql(label, sql) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      psqlBin,
      [databaseUrl, '-X', '-v', 'ON_ERROR_STOP=1', '-At', '-c', sql],
      {
        stdio: ['ignore', 'pipe', 'pipe'],
        env: {
          ...process.env,
          PGOPTIONS: [
            process.env.PGOPTIONS,
            '-c statement_timeout=15000',
            '-c lock_timeout=5000',
          ].filter(Boolean).join(' '),
        },
      },
    );
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('error', (error) => reject(new Error(`${label}: ${error.message}`)));
    child.on('close', (code) => {
      if (code === 0) {
        resolve(stdout.trim());
        return;
      }
      reject(new Error(`${label}: psql terminó ${code}\n${stderr || stdout}`));
    });
  });
}

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

try {
  const fixture = await runPsql('resolver fixture', `
    select pg_catalog.concat_ws(
      '|',
      supervisor.id,
      asesor.id,
      lead.id,
      (lead.vendedor_id is null
        and lead.asignado_supervisor_id = supervisor.id)::text
    )
    from public.perfiles supervisor
    cross join public.perfiles asesor
    cross join crm.leads lead
    where supervisor.nombre_completo = 'SUPERVISOR UNO'
      and asesor.nombre_completo = 'VENDEDOR DOS'
      and lead.nombre_completo = 'LUIS GARCIA DEMO'
    limit 1;
  `);
  const [supervisorId, asesorId, leadId, estaEnBandeja] = fixture.split('|');
  if (!supervisorId || !asesorId || !leadId || estaEnBandeja !== 'true') {
    throw new Error(
      `fixture inválido: se esperaba LUIS GARCIA DEMO en la bandeja de SUPERVISOR UNO; recibido ${fixture}`,
    );
  }

  const marca = `SONDA CONCURRENCIA DERIVACIONES ${randomUUID()}`;
  const insertGestion = runPsql('insert concurrente del asesor', `
    with actor as materialized (
      select pg_catalog.set_config(
        'request.jwt.claim.sub',
        ${sqlLiteral(asesorId)},
        false
      )
    ), demora as materialized (
      select pg_catalog.pg_sleep(3)
    )
    insert into crm.actividades (
      lead_id, tipo, detalle, metadata, creado_por, creado_en
    )
    select
      ${sqlLiteral(leadId)}::uuid,
      'nota',
      ${sqlLiteral(marca)},
      pg_catalog.jsonb_build_object(
        'statement_started_at',
        pg_catalog.statement_timestamp()
      ),
      ${sqlLiteral(asesorId)}::uuid,
      pg_catalog.statement_timestamp()
    from actor
    cross join demora
    returning creado_en;
  `);

  // El INSERT ya empezó y conserva T0, pero todavía duerme antes del BEFORE.
  // La derivación completa y confirma en T1. Al despertar, el trigger debe
  // autorizar al dueño nuevo y sellar una hora posterior al lock, no T0.
  await sleep(650);
  await runPsql('derivación concurrente del supervisor', `
    with actor as materialized (
      select pg_catalog.set_config(
        'request.jwt.claim.sub',
        ${sqlLiteral(supervisorId)},
        false
      )
    )
    select crm.derivar_leads_equipo_fn(
      array[${sqlLiteral(leadId)}::uuid],
      array[${sqlLiteral(asesorId)}::uuid]
    )
    from actor;
  `);
  await insertGestion;

  await runPsql('verificar orden causal y candado de devolución', `
    do $sonda$
    declare
      v_asignado_en timestamptz;
      v_gestion_en timestamptz;
      v_statement_started_at timestamptz;
      v_reporte jsonb;
      v_reversible boolean;
      v_mensaje text;
    begin
      select la.asignado_en
        into v_asignado_en
      from crm.lead_asignaciones la
      where la.lead_id = ${sqlLiteral(leadId)}::uuid
        and la.analista_id = ${sqlLiteral(asesorId)}::uuid
        and la.finalizado_en is null;

      select
        actividad.creado_en,
        (actividad.metadata->>'statement_started_at')::timestamptz
        into v_gestion_en, v_statement_started_at
      from crm.actividades actividad
      where actividad.lead_id = ${sqlLiteral(leadId)}::uuid
        and actividad.creado_por = ${sqlLiteral(asesorId)}::uuid
        and actividad.detalle = ${sqlLiteral(marca)}
      order by actividad.creado_en desc
      limit 1;

      if v_asignado_en is null
         or v_gestion_en is null
         or v_statement_started_at is null then
        raise exception 'C01 faltó el episodio o la gestión concurrente';
      end if;
      if not (
        v_statement_started_at < v_asignado_en
        and v_asignado_en <= v_gestion_en
      ) then
        raise exception
          'C02 orden causal inválido: inicio %, asignación %, gestión %',
          v_statement_started_at, v_asignado_en, v_gestion_en;
      end if;

      perform pg_catalog.set_config(
        'request.jwt.claim.sub',
        ${sqlLiteral(supervisorId)},
        true
      );
      v_reporte := crm.reporte_derivaciones_equipo_fn(
        (pg_catalog.now() at time zone 'America/Lima')::date,
        (pg_catalog.now() at time zone 'America/Lima')::date
      );
      select (movimiento->>'reversible')::boolean
        into v_reversible
      from pg_catalog.jsonb_array_elements(v_reporte->'movimientos_hoy') movimiento
      where movimiento->>'lead_id' = ${sqlLiteral(leadId)};
      if v_reversible is distinct from false then
        raise exception 'C03 el reporte no reflejó la gestión concurrente';
      end if;

      begin
        perform crm.revertir_derivacion_equipo_fn(${sqlLiteral(leadId)}::uuid);
        raise exception 'C04 la devolución aceptó una gestión concurrente'
          using errcode = 'P0099';
      exception
        when sqlstate 'P0001' then
          get stacked diagnostics v_mensaje = message_text;
          if v_mensaje not like '%registró gestión%' then
            raise exception 'C05 la devolución falló por otra causa: %', v_mensaje;
          end if;
      end;
    end;
    $sonda$;
  `);

  console.log('REPORTE_DERIVACIONES_CONCURRENCIA_OK');
  console.log('Fixture consumido en la branch: LUIS GARCIA DEMO. Ejecutar esta sonda al final.');
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
