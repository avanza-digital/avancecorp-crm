-- P-047b · Grants a nivel de tabla.
-- La RLS sigue limitando la escritura a gerencia.
grant select, insert, update on crm.enfriamiento_politica to authenticated;
