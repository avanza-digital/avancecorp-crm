-- Trinquete F7 (Ola 0): el veredicto viaja como FILA y sale de LA FUNCION real
-- private.veredicto_f7() (alertas de TODAS las fases + vigia exacto con dueno y
-- ultima corrida + assert de piezas). El gate y el mutante ejercitan el MISMO
-- codigo: no hay copia que pueda divergir.
select private.veredicto_f7() as veredicto;
