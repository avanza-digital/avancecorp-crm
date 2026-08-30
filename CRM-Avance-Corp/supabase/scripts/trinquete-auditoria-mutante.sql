-- MUTANTE DEL TRINQUETE DE AUDITORÍA (P-055 F1.4/F1.5/F1.6)
--
-- Por cada defensa, un mutante que la neutralice: si sobrevive, esa defensa no
-- está probada. Cada filo rompe la regla A PROPÓSITO y ejecuta **el gate
-- entero** (`private.assert_auditoria()`), exigiendo que reviente con P0001.
-- Antes cada filo consultaba una pieza suelta: se podía romper el gate y el
-- mutante seguía verde (hallazgo de Codex).
--
-- 🔴 TERMINA SIEMPRE EN `raise exception`: así la transacción se deshace entera
--    —incluido el DDL de prueba— y el veredicto viaja (este canal no transporta
--    los avisos). El ÉXITO de este archivo es el error `MUTANTE_CAZADO`.
do $mutante$
declare
  v_filos text := '';
  v_cazado boolean;
begin
  -- ---- FILO 1: tabla nueva sin ningún rastro ------------------------------
  create table crm.zzz_mutante_sin_rastro (id uuid primary key);
  v_cazado := false;
  begin
    perform private.assert_auditoria();
  exception when sqlstate 'P0001' then v_cazado := true;
  end;
  if not v_cazado then v_filos := v_filos || '1 (tabla sin rastro) '; end if;
  drop table crm.zzz_mutante_sin_rastro;

  -- ---- FILO 2: tabla con rastro A MEDIAS (solo INSERT) --------------------
  create table crm.zzz_mutante_a_medias (id uuid primary key);
  create trigger trg_audit_zzz_a_medias after insert on crm.zzz_mutante_a_medias
    for each row execute function private.log_audit_crm();
  v_cazado := false;
  begin
    perform private.assert_auditoria();
  exception when sqlstate 'P0001' then v_cazado := true;
  end;
  if not v_cazado then v_filos := v_filos || '2 (rastro a medias) '; end if;
  drop table crm.zzz_mutante_a_medias;

  -- ---- FILO 3: trigger DECORATIVO — los tres verbos, pero anulado ---------
  create table crm.zzz_mutante_senuelo (id uuid primary key, activo boolean default true);
  create trigger trg_audit_zzz_senuelo
    after insert or update or delete on crm.zzz_mutante_senuelo
    for each row when (false) execute function private.log_audit_crm();
  v_cazado := false;
  begin
    perform private.assert_auditoria();
  exception when sqlstate 'P0001' then v_cazado := true;
  end;
  if not v_cazado then v_filos := v_filos || '3 (trigger anulado por WHEN false) '; end if;
  drop table crm.zzz_mutante_senuelo;

  -- ---- FILO 4: exención colada a mano contra el sello ---------------------
  create table crm.zzz_mutante_colado (id uuid primary key);
  insert into private.auditoria_exenciones (tabla, razon)
  values ('crm.zzz_mutante_colado',
          'Exencion falsa del mutante: comprueba que el sello delata una exencion metida a mano sin pasar por el repo.');
  v_cazado := false;
  begin
    perform private.assert_auditoria();
  exception when sqlstate 'P0001' then v_cazado := true;
  end;
  if not v_cazado then v_filos := v_filos || '4 (exención colada) '; end if;
  delete from private.auditoria_exenciones where tabla = 'crm.zzz_mutante_colado';
  drop table crm.zzz_mutante_colado;

  -- ---- FILO 5: el vigía apagado ------------------------------------------
  perform cron.unschedule('crm-auditoria-vigia');
  v_cazado := false;
  begin
    perform private.assert_auditoria();
  exception when sqlstate 'P0001' then v_cazado := true;
  end;
  if not v_cazado then v_filos := v_filos || '5 (vigía apagado) '; end if;

  -- ---- Veredicto (la transacción se deshace pase lo que pase) -------------
  if v_filos <> '' then
    raise exception 'EL MUTANTE SOBREVIVIÓ en el/los filo(s): %. Esa defensa no está probada.', v_filos;
  end if;

  raise exception 'MUTANTE_CAZADO: los cinco filos ejecutan el gate REAL y todos revientan como deben (tabla sin rastro · rastro a medias · trigger anulado · exención colada · vigía apagado). Esta transacción se deshace entera.';
end
$mutante$;
