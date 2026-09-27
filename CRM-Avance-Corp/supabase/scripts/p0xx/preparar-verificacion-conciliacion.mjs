// Genera el ensayo desde los SQL reales, sin duplicar su implementacion.
// Uso: node preparar-verificacion-conciliacion.mjs <archivo.sql>
// Ejecutar el SQL resultante SOLO en la rama; termina siempre en ROLLBACK.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const base = path.dirname(fileURLToPath(import.meta.url));
const archivos = {"seed": "seed-conciliacion-ficticia.sql", "versiones": "conciliar-versiones.sql", "banco": "conciliar-banco-legado.sql", "reversa": "revertir-versiones-conciliadas.sql", "reversaBanco": "revertir-banco-legado.sql"};
const fuentes = Object.fromEntries(Object.entries(archivos).map(([clave, archivo]) =>
  [clave, readFileSync(path.join(base, archivo), 'utf8')]));
if (process.argv.length !== 3) throw new Error('Indica el archivo SQL de salida');
const sql = `begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
${fuentes.seed}
create temporary table p0xx_links_antes on commit drop as
select cp.* from crm.contrato_cuentas_pago cp
join p0xx_casos_fixture f on f.contrato_id=cp.contrato_id;

-- El segundo caso falla despues del primero: toda la llamada debe revertirse.
select pg_catalog.set_config('p0xx.casos_versionado',(
 select pg_catalog.jsonb_agg(case when motivo='titular'
 then caso || '{"huella_cuenta":"huella_incorrecta"}'::jsonb else caso end)::text
 from p0xx_casos_config where motivo<>'banco'),true);
do $fallo_atomico$
begin
 begin
  execute $codigo$${fuentes.versiones}$codigo$;
  raise exception 'TEST: la huella incorrecta fue aceptada';
 exception when raise_exception then
  if sqlerrm <> 'P0XX: la cuenta cambio desde la revision; no se concilia' then raise; end if;
 end;
 if (select count(*) from crm.cuentas_bancarias cb
     join p0xx_casos_fixture f on cb.cliente_id=f.cliente_id) <> 3
    or exists (select 1 from crm.cuentas_bancarias cb
     join p0xx_casos_fixture f on cb.id=f.cuenta_id where cb.activa is not true) then
  raise exception 'TEST: una conciliacion fallida dejo cambios parciales';
 end if;
end;
$fallo_atomico$;
select pg_catalog.set_config('p0xx.casos_versionado',(
 select pg_catalog.jsonb_agg(caso)::text from p0xx_casos_config where motivo<>'banco'),true);
${fuentes.versiones}
${fuentes.banco}
do $primera$
begin
 if pg_catalog.current_setting('p0xx.resultado_versiones') <> '2'
    or pg_catalog.current_setting('p0xx.resultado_banco') <> '1'
    or exists (
      with relacionados as materialized (
        select pg_catalog.to_jsonb(p) as perfil,pg_catalog.to_jsonb(cb) as cuenta
        from p0xx_casos_fixture f join public.perfiles p on p.id=f.cliente_id
        join crm.cuentas_bancarias cb on cb.cliente_id=p.id and cb.activa)
      select 1 from relacionados r
      where private.validar_cuenta_bancaria(r.perfil)
        <> private.validar_cuenta_bancaria(r.cuenta))
    or (select count(*) from private.backfill_cuentas_p0xx b
        join p0xx_casos_fixture f on b.cliente_id=f.cliente_id
        where b.revertida_en is null) <> 2 then
  raise exception 'TEST: no se resolvieron las tres discrepancias con ledger';
 end if;
end;
$primera$;
${fuentes.versiones}
${fuentes.banco}
do $idempotencia$
begin
 if pg_catalog.current_setting('p0xx.resultado_versiones') <> '0'
    or pg_catalog.current_setting('p0xx.resultado_banco') <> '0'
    or (select count(*) from crm.cuentas_bancarias cb
        join p0xx_casos_fixture f on cb.cliente_id=f.cliente_id) <> 5 then
  raise exception 'TEST: la conciliacion no fue idempotente';
 end if;
end;
$idempotencia$;
-- Un contrato posterior que reutiliza la nueva version impide toda la reversa.
do $reversa_reutilizada$
begin
 begin
  insert into public.contratos
   (id,numero_contrato,cliente_id,capital,moneda,modalidad,tipo_interes,
    fecha_inicio,fecha_vencimiento,categoria,tasa_anual,creado_por)
  select 'd1000000-0000-4000-8000-000000000004','P0XX-CIERRE-REUSO',
   ct.cliente_id,ct.capital,ct.moneda,ct.modalidad,ct.tipo_interes,
   ct.fecha_inicio,ct.fecha_vencimiento,ct.categoria,ct.tasa_anual,ct.creado_por
  from public.contratos ct join p0xx_casos_fixture f on f.contrato_id=ct.id
  where f.motivo='titular';
  insert into crm.contrato_cuentas_pago (contrato_id,cuenta_bancaria_id,creado_por)
  select 'd1000000-0000-4000-8000-000000000004',cb.id,(select auth.uid())
  from crm.cuentas_bancarias cb
  join p0xx_casos_fixture f on f.cliente_id=cb.cliente_id
  where f.motivo='titular' and cb.activa;
  execute $codigo$${fuentes.reversa}$codigo$;
  raise exception 'TEST: la reversa acepto una cuenta reutilizada';
 exception when raise_exception then
  if sqlerrm <> 'P0XX: la cuenta fue modificada o reutilizada; reversa manual' then raise; end if;
 end;
 if (select count(*) from crm.cuentas_bancarias cb
     join p0xx_casos_fixture f on cb.cliente_id=f.cliente_id) <> 5
    or (select count(*) from private.backfill_cuentas_p0xx b
        join p0xx_casos_fixture f on b.cliente_id=f.cliente_id
        where b.revertida_en is null) <> 2 then
  raise exception 'TEST: una reversa rechazada dejo cambios parciales';
 end if;
end;
$reversa_reutilizada$;
${fuentes.reversa}
${fuentes.reversaBanco}
do $reversa$
begin
 if pg_catalog.current_setting('p0xx.resultado_reversa') <> '2'
    or exists (
      select 1 from p0xx_casos_fixture f
      join crm.cuentas_bancarias actual on actual.cliente_id=f.cliente_id and actual.activa
      join crm.cuentas_bancarias original on original.id=f.cuenta_id
      where private.validar_cuenta_bancaria(pg_catalog.to_jsonb(actual))
        <> private.validar_cuenta_bancaria(pg_catalog.to_jsonb(original)))
    or exists (
      select 1 from p0xx_casos_fixture f join public.perfiles p on p.id=f.cliente_id
      where f.motivo='banco' and p.banco <> 'Interbank')
    or exists (
      select 1 from p0xx_links_antes a
      full join (select cp.* from crm.contrato_cuentas_pago cp
        join p0xx_casos_fixture f on f.contrato_id=cp.contrato_id) b on b.id=a.id
      where pg_catalog.to_jsonb(a) is distinct from pg_catalog.to_jsonb(b))
    or not exists (select 1 from pg_catalog.pg_trigger
      where tgrelid='public.perfiles'::regclass
        and tgname='trg_perfiles_banca_solo_lectura' and tgenabled='O') then
  raise exception 'TEST: reversa, vinculos o proteccion incorrectos';
 end if;
end;
$reversa$;
select 'P0XX_CONCILIACION_ATOMICA_IDEMPOTENTE_REVERSIBLE_OK' as resultado;
rollback;
`;
writeFileSync(process.argv[2], sql, { mode: 0o600 });
console.log('SQL de ensayo generado desde los scripts reales; todavia no ejecutado.');
