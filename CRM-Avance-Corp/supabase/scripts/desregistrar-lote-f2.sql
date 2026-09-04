-- DES-REGISTRO de las 7 versiones del lote Contrato-F2 que quedaron REGISTRADAS SIN APLICAR el
-- 04/09 (190000 SÍ se aplicó y se conserva). Usar SOLO si se decide no continuar con 2-8.
-- Devuelve la verdad al registro (las filas se anotaron antes de aplicar). Idempotente.
begin;
delete from supabase_migrations.schema_migrations
 where version in ('20260903205000','20260903210000','20260903220000',
                   '20260903230000','20260903240000','20260903250000','20260903260000');
commit;
select count(*) as quedan from supabase_migrations.schema_migrations
 where version between '20260903205000' and '20260903260000' and version <> '20260903215149';
