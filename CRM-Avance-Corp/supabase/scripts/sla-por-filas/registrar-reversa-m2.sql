-- RETIRADO en el kit v4 (17/10/2026, Codex de verificación P1). La reversa de m2 se REGISTRA A SÍ MISMA en la misma
-- transacción que su DDL (ver reversa-m2.sql y LEEME.md, «Si hay que revertir»): ya no hay nada que registrar aparte, y un
-- registro separado podía anotar una versión distinta de la ejecutada. Este archivo solo se detiene con un mensaje claro: no
-- lee ni escribe nada. El historial se comprueba con verificar.sql.
do $retirado$
begin
  raise exception 'RETIRADO (kit v4): la reversa de m2 se registra sola en su misma transacción; no hay nada que registrar aparte. Comprueba el historial con verificar.sql';
end $retirado$;
