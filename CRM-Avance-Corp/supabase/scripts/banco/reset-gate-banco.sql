-- ---------------------------------------------------------------------------
-- RESET DEL BANCO ENTRE CORRIDAS DEL GATE `test:rls`
--
-- ⚠️ SOLO PARA UN BANCO. Jamás contra producción: aquí se baja un candado
--    nombrado, y en producción eso está prohibido sin la liturgia completa.
--
-- Por qué existe (01/09): la suite se escribió para branches DESECHABLES
-- (crear → correr → destruir) y deja residuos a propósito o por imposibilidad:
--   · el lead de bolsa F2 queda VIVO en la cola global con teléfono fijo
--     → la corrida siguiente choca con `uq_leads_telefono_vivo` (23505);
--   · los leads convertidos/descartados de los bloques quedan vivos
--     → «gerencia ve 7» vio 8, «directorio ve 7» vio 40;
--   · el bloque de domicilio DEJA ESCRITO `public.perfiles.domicilio` del
--     cliente bancario y lo documenta como imposible de deshacer: el trigger
--     `perfiles_domicilio_legal_no_borrar` prohíbe volver a NULL
--     → «el cliente de la sonda arranca SIN domicilio» se pone rojo.
--
-- En un banco PERSISTENTE, este guion devuelve el mundo al estado que la
-- suite asume. Se corre ANTES de `seed:demo` (el seed re-upserta los fixtures).
-- ---------------------------------------------------------------------------
begin;

-- 1) Leads: solo los 7 del fixture quedan vivos. El resto es residuo de gate
--    (transitorios de otra corrida, convertidos, bolsas). Mismo soft-delete
--    que producción; nada se borra.
update crm.leads
   set activo = false
 where activo
   and id not in (
     '11000000-0000-4000-8000-000000000001',
     '11000000-0000-4000-8000-000000000002',
     '11000000-0000-4000-8000-000000000003',
     '11000000-0000-4000-8000-000000000004',
     '11000000-0000-4000-8000-000000000005',
     '11000000-0000-4000-8000-000000000006',
     '11000000-0000-4000-8000-000000000007'
   );

-- 2) Tareas: las pendientes que no son del fixture se cancelan (el cierre por
--    estado es el mismo de producción; las cerradas son inmutables y se dejan).
update crm.tareas
   set estado = 'cancelada'
 where estado = 'pendiente'
   and id not in (
     '44000000-0000-4000-8000-000000000001',
     '44000000-0000-4000-8000-000000000002',
     '44000000-0000-4000-8000-000000000003',
     '44000000-0000-4000-8000-000000000004',
     '44000000-0000-4000-8000-000000000005'
   );

-- 3) El domicilio de la sonda vuelve a NULL. El candado que lo impide protege
--    un dato LEGAL de producción; esto es residuo de TEST en un banco. Se baja
--    el trigger POR SU NOMBRE, en la misma transacción, y se vuelve a subir —
--    nunca `disable trigger user` a ciegas (regla de la limpieza de leads).
alter table public.perfiles disable trigger perfiles_domicilio_legal_no_borrar;
update public.perfiles
   set domicilio = null
 where (dni = '90000001' or correo = 'cliente-bancario.crm@demo.avancecorp.pe')  -- BANK_CLIENT del fixture (clientBank); por correo también: un bloque dejó el dni en NULL el 05/09
   and domicilio is not null;
alter table public.perfiles enable trigger perfiles_domicilio_legal_no_borrar;

-- 4) Recibo: cuántos vivos quedan (la suite espera exactamente los 7 fixture).
do $recibo$
declare v_leads int; v_dom int;
begin
  select count(*) into v_leads from crm.leads where activo;
  select count(*) into v_dom from public.perfiles where (dni = '90000001' or correo = 'cliente-bancario.crm@demo.avancecorp.pe') and domicilio is not null;
  raise notice 'RESET-GATE: % leads vivos (esperados 7 tras seed) · domicilio sonda escrito: % · sonda hallada: %', v_leads, v_dom,
    (select count(*) from public.perfiles where dni = '90000001' or correo = 'cliente-bancario.crm@demo.avancecorp.pe');
end $recibo$;

commit;
