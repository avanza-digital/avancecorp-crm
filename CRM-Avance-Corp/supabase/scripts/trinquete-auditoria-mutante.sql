-- MUTANTE DEL TRINQUETE DE AUDITORÍA (P-055 F1.4/F1.5)
--
-- Por cada defensa, un mutante que la neutralice: si sobrevive, esa defensa no
-- está probada. Aquí se rompe la regla A PROPÓSITO, de cuatro formas, y se exige
-- que cada filo la cace:
--   1. una tabla nueva sin rastro        → la regla del servidor debe verla
--   2. una tabla con rastro A MEDIAS     → también (es el fallo que la auditoría
--                                          encontró: 9 tablas «auditadas» que no
--                                          cubrían todos los verbos)
--   3. el vigía diario                   → debe abrir su alerta
--   4. una exención metida a mano        → el sello debe delatarla
--
-- 🔴 TERMINA SIEMPRE EN `raise exception`, y por dos razones:
--    (a) así la transacción se DESHACE ENTERA — incluido el DDL de las tablas de
--        prueba, que si no quedaría confirmado en producción (y con él una
--        recarga del esquema de PostgREST en cada corrida);
--    (b) el canal `supabase db query` NO transporta los `raise notice` (medido),
--        pero sí los errores: el veredicto tiene que viajar como excepción.
--    Por eso el ÉXITO de este archivo es el error `MUTANTE_CAZADO`.
do $mutante$
declare
  v_filo_1 boolean;
  v_filo_2 boolean;
  v_filo_3 boolean;
  v_filo_4 boolean;
  v_lista text;
begin
  -- ---- FILO 1: tabla nueva sin ningún rastro ------------------------------
  create table crm.zzz_mutante_sin_rastro (id uuid primary key);
  v_filo_1 := exists (
    select 1 from private.tablas_sin_rastro() s where s.tabla = 'crm.zzz_mutante_sin_rastro');

  -- ---- FILO 2: tabla con rastro A MEDIAS (solo INSERT) --------------------
  create table crm.zzz_mutante_a_medias (id uuid primary key);
  create trigger trg_audit_zzz_mutante_a_medias
    after insert on crm.zzz_mutante_a_medias
    for each row execute function private.log_audit_crm();
  v_filo_2 := exists (
    select 1 from private.tablas_sin_rastro() s where s.tabla = 'crm.zzz_mutante_a_medias');

  -- ---- FILO 3: ¿el vigía las anota? ---------------------------------------
  perform private.vigia_auditoria();
  v_filo_3 := (select pg_catalog.count(*) from private.auditoria_alertas
               where tabla in ('crm.zzz_mutante_sin_rastro','crm.zzz_mutante_a_medias')
                 and resuelta_en is null) = 2;

  -- ---- FILO 4: exención colada sin pasar por el repo -----------------------
  insert into private.auditoria_exenciones (tabla, razon)
  values ('crm.zzz_mutante_sin_rastro',
          'Exencion falsa del mutante: comprueba que el sello y el espejo del repo delatan una exencion metida a mano.');
  v_filo_4 := private.huella_exenciones() is distinct from
              (select huella from private.auditoria_sello);

  -- ---- Veredicto (la transacción se deshace pase lo que pase) -------------
  if not v_filo_1 then
    raise exception 'EL MUTANTE SOBREVIVIÓ (filo 1): una tabla sin rastro no fue detectada';
  end if;
  if not v_filo_2 then
    raise exception 'EL MUTANTE SOBREVIVIÓ (filo 2): una tabla con auditoría A MEDIAS pasó por buena';
  end if;
  if not v_filo_3 then
    raise exception 'EL MUTANTE SOBREVIVIÓ (filo 3): el vigía no abrió las dos alertas';
  end if;
  if not v_filo_4 then
    raise exception 'EL MUTANTE SOBREVIVIÓ (filo 4): una exención metida a mano no rompió el sello';
  end if;

  raise exception 'MUTANTE_CAZADO: los cuatro filos funcionan (tabla sin rastro, tabla a medias, vigía y sello). Esta transacción se deshace entera: nada queda escrito.';
end
$mutante$;
