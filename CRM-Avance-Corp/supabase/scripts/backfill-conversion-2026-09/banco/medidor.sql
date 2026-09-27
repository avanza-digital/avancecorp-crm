-- Medidor de pantallas (SOLO banco). Uso: psql -v etapa=<nombre> -f medidor.sql
-- Llama, como cada actor y con su rol real (authenticated + claims), a las RPC que
-- el front usa para capital, conversión, cartera, Ficha 360, postventa y el lead.
create schema if not exists ensayo;
create table if not exists ensayo.foto(etapa text, actor text, rpc text, ok boolean, resultado jsonb,
  primary key (etapa, actor, rpc));
delete from ensayo.foto where etapa = :'etapa';

\set actor_id 'b0000000-0000-4000-8000-000000000003'
\set actor gerencia
\ir medidor-actor.sql
\set actor_id 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127'
\set actor admin
\ir medidor-actor.sql
\set actor_id 'b0000000-0000-4000-8000-000000000001'
\set actor supervisor
\ir medidor-actor.sql
\set actor_id 'b0000000-0000-4000-8000-000000000002'
\set actor vendedor
\ir medidor-actor.sql

-- Funciones internas (sin EXECUTE para authenticated): como postgres, con los claims de gerencia.
\ir medidor-interno.sql

select :'etapa' etapa, count(*) llamadas, count(*) filter (where ok) ok from ensayo.foto where etapa = :'etapa';
