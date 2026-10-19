// Contratos y cartera sintéticos con exigencia activa, reversión por transacción.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { contratoPrueba } from '../f4/operaciones-fixture.mjs';
import { sql, literal as q } from './banco.mjs';
const j = valor => q(JSON.stringify(valor)) + '::jsonb';
const cliente = randomUUID();
const analista = 'b0000000-0000-4000-8000-000000000002';
const gerente = 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';
const base = contratoPrueba(cliente, analista, { inicio: '2025-07-01', capital: 1000, numero: '2025-01-989001' });
const upgrade = contratoPrueba(cliente, analista, { categoria: 'upgrade', inicio: '2025-08-01', capital: 700, numero: '2025-01-989002' });
const renovacion = contratoPrueba(cliente, analista, { categoria: 'renovacion', inicio: '2026-08-01', capital: 800, numero: '2026-01-989003' });
const revision = Number(sql('select revision from crm.recorrido_control where id'));
const antes = sql('select md5(to_jsonb(c)::text) from crm.recorrido_control c where id');
const resultado = sql(`begin;set local statement_timeout='60s';set local lock_timeout='3s';
  insert into auth.users(id) values(${q(cliente)});
  insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni,activo,asesor_perfil_id,domicilio,correo)
    values(${q(cliente)},'CLIENTE SINTETICO RECORRIDO','cliente','DNI','98640100',true,${q(analista)},
      'CALLE SINTETICA 123, LIMA',${q('recorrido.' + cliente + '@example.test')});
  set local role authenticated;set local request.jwt.claim.sub=${q(gerente)};
  select crm.recorrido_configurar_fn('exigir','Ensayo de clientes actuales sin nuevo recorrido',${revision});
  reset role;
  do $$
  declare origen uuid;cabeza uuid;persona uuid;s uuid;res jsonb;datos jsonb;hija uuid;n integer;
  begin
    set local role authenticated;
    res:=crm.crear_contrato_con_cuenta_pdf_v2(${j(base.contrato)},${j(base.cronograma)},${j(base.cuenta)});
    reset role;origen:=(res->>'id')::uuid;
    select id into strict persona from crm.inversionistas where perfil_id=${q(cliente)} and estado='activo';
    s:=gen_random_uuid();datos:=jsonb_build_object('inversionista_id',persona,'empresa','avance',
      'contrato',${j(upgrade.contrato)}||jsonb_build_object('contrato_origen_id',origen),
      'cronograma',${j(upgrade.cronograma)},'cuenta',${j(upgrade.cuenta)});
    set local role authenticated;
    perform crm.preparar_inversion_fn(s,datos);res:=crm.confirmar_inversion_revisada_fn(s,0);
    reset role;cabeza:=(res#>>'{fuente,id}')::uuid;
    if not exists(select 1 from crm.inversion_solicitudes where id=s and estado='confirmada'
      and lead_origen_id is null and recorrido_confirmado is null) then raise exception 'Upgrade afectado por recorrido';end if;
    s:=gen_random_uuid();datos:=jsonb_build_object('inversionista_id',persona,'empresa','avance',
      'contrato',${j(renovacion.contrato)}||jsonb_build_object('contrato_origen_id',cabeza,'capital_renovado',700,'capital_adicional',100),
      'cronograma',${j(renovacion.cronograma)},'cuenta',${j(renovacion.cuenta)});
    set local role authenticated;
    perform crm.preparar_inversion_fn(s,datos);res:=crm.confirmar_inversion_revisada_fn(s,0);
    reset role;hija:=(res#>>'{fuente,id}')::uuid;
    if not exists(select 1 from crm.inversion_solicitudes where id=s and estado='confirmada'
      and lead_origen_id is null and recorrido_confirmado is null) then raise exception 'Renovacion afectada por recorrido';end if;
    if (select estado from public.contratos where id=cabeza)<>'renovado'
      or (select capital from public.contratos where id=hija)<>800 then raise exception 'Finanzas alteradas';end if;
    select count(*) into n from public.contratos where cliente_id=${q(cliente)};
    if n<>3 then raise exception 'Numero de contratos incorrecto: %',n;end if;
    set local role authenticated;res:=crm.confirmar_inversion_revisada_fn(s,0);reset role;
    if not (res->>'reintento')::boolean or (res#>>'{fuente,id}')::uuid<>hija then raise exception 'Replay renovacion alterado';end if;
    raise notice 'PASS: cliente existente, upgrade y renovacion con exigencia activa, sin nuevos hechos ni inversiones duplicadas';
  end $$;
  select 'CARTERA_PASS';rollback;`);
assert.match(resultado, /CARTERA_PASS/);
assert.equal(sql('select md5(to_jsonb(c)::text) from crm.recorrido_control c where id'), antes);
assert.equal(sql(`select count(*) from public.perfiles where id=${q(cliente)}`), '0');
console.log('PASS: contrato inicial de cartera, upgrade, renovación y replay; rollback íntegro, sin activar el banco.');
