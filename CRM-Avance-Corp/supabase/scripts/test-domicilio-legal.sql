\set ON_ERROR_STOP on
\pset pager off

-- ORÁCULO DE COMPORTAMIENTO del domicilio legal faltante (20260819162752).
--
-- Por qué existe, y por qué NO vive dentro de la migración: las sondas del
-- postflight miran el catálogo (¿existe la función? ¿tiene los grants?), y eso
-- no prueba nada de lo que la función HACE — «crear no basta: plpgsql solo
-- valida sintaxis» (nota del vault «Verificar SQL sin gastar un branch»). Dos
-- de las cuatro auditorías adversarias del 2026-08-19 señalaron exactamente
-- este hueco: ninguna sonda EJECUTABA las funciones nuevas.
--
-- Además, una sonda de datos dentro de la migración («tiene que haber clientes
-- sin domicilio») la vuelve irrepetible: se auto-invalida el día en que el
-- arreglo funciona. Aquí sí puede vivir, porque este script se corre cuando se
-- quiere y contra el mundo que se quiera.
--
-- 10 casos. CÓMO SE CORRE. Contra un branch de Supabase ya sembrado:
--     psql "$URL_BRANCH" -f supabase/scripts/test-domicilio-legal.sql
--
-- TODO ocurre dentro de UNA transacción que termina en ROLLBACK: no deja
-- rastro ni siquiera si alguien lo apunta a producción (mismo patrón que la
-- nota «Probar en producción sin escribir nada»). Lo único que toca mientras
-- corre son locks de fila de duración milisegundos.

begin;

do $oraculo$
declare
  v_vendedor uuid;
  v_cliente_vacio uuid;
  v_cliente_ajeno uuid;
  v_otro_vendedor uuid;
  v_sub_previo text := current_setting('request.jwt.claim.sub', true);
  v_r jsonb;
  v_leido text;
  v_ok int := 0;
  v_candidato text;
  v_msg_ajeno text;
  v_msg_inexistente text;
begin
  -- ── Reparto de papeles, tomado del mundo REAL de esta base ────────────────
  select p.asesor_perfil_id, p.id
  into v_vendedor, v_cliente_vacio
  from public.perfiles p
  join crm.equipo e on e.perfil_id = p.asesor_perfil_id and e.activo and e.rol_crm = 'vendedor'
  where p.rol = 'cliente'
    and p.activo is true
    and nullif(btrim(coalesce(p.domicilio, '')), '') is null
  limit 1;

  if v_vendedor is null then
    raise exception
      'ORÁCULO: no hay ningún cliente activo SIN domicilio con asesor vendedor; siembra antes de correr esto';
  end if;

  select e.perfil_id into v_otro_vendedor
  from crm.equipo e
  where e.activo and e.rol_crm = 'vendedor' and e.perfil_id <> v_vendedor
  limit 1;

  select p.id into v_cliente_ajeno
  from public.perfiles p
  where p.rol = 'cliente' and p.activo is true
    and p.asesor_perfil_id = v_otro_vendedor
  limit 1;

  perform set_config('request.jwt.claim.sub', v_vendedor::text, true);

  -- ── 1. Lectura: el hueco se ve, y se ve como domicilio ────────────────────
  v_r := crm.datos_legales_contrato_fn(v_cliente_vacio);
  if (v_r->>'falta_domicilio')::boolean is not true then
    raise exception 'CASO 1: datos_legales_contrato_fn no ve el domicilio vacío (%)', v_r;
  end if;
  if not (v_r->'faltan_cliente' ? 'domicilio') then
    raise exception 'CASO 1: el domicilio no aparece en faltan_cliente (%)', v_r;
  end if;
  v_ok := v_ok + 1;

  -- ── 2. Escritura: COMPLETADO y la columna QUEDA escrita de verdad ─────────
  -- Releer es el punto entero de este caso: un UPDATE que toque 0 filas
  -- devolvía 'completado' y dejaba al vendedor bloqueado creyendo que guardó.
  v_r := crm.completar_domicilio_cliente(
    v_cliente_vacio, 'Av. Los Alamos 123, San Isidro, Lima, Lima'
  );
  if v_r->>'accion' <> 'completado' then
    raise exception 'CASO 2: se esperaba completado y llegó % ', v_r;
  end if;
  if v_r ? 'domicilio' then
    raise exception 'CASO 2: la respuesta NO debe devolver el domicilio (vía de lectura de PII)';
  end if;
  select p.domicilio into v_leido from public.perfiles p where p.id = v_cliente_vacio;
  if v_leido is distinct from 'Av. Los Alamos 123, San Isidro, Lima, Lima' then
    raise exception 'CASO 2: la columna no quedó escrita; vale %', coalesce(v_leido, '(null)');
  end if;
  v_ok := v_ok + 1;

  -- ── 3. El hueco quedó cerrado para la lectura ─────────────────────────────
  v_r := crm.datos_legales_contrato_fn(v_cliente_vacio);
  if (v_r->>'falta_domicilio')::boolean is not false then
    raise exception 'CASO 3: tras rellenar, la lectura sigue diciendo que falta (%)', v_r;
  end if;
  v_ok := v_ok + 1;

  -- ── 4. Segunda escritura: CONSERVADO y NO pisa ────────────────────────────
  -- Es la carrera de dos sesiones, jugada en serie: quien llega segundo no
  -- sobreescribe lo que ya está impreso en el contrato de otro.
  v_r := crm.completar_domicilio_cliente(v_cliente_vacio, 'Jr. Otro 999, Cercado, Lima, Lima');
  if v_r->>'accion' <> 'conservado' then
    raise exception 'CASO 4: se esperaba conservado y llegó %', v_r;
  end if;
  select p.domicilio into v_leido from public.perfiles p where p.id = v_cliente_vacio;
  if v_leido <> 'Av. Los Alamos 123, San Isidro, Lima, Lima' then
    raise exception 'CASO 4: el domicilio existente FUE PISADO; ahora vale %', v_leido;
  end if;
  v_ok := v_ok + 1;

  -- ── 5. El domicilio escrito NO se puede vaciar ────────────────────────────
  -- Es la otra mitad de «nunca se pisa»: una vez puesto, ni el dueño de la base
  -- puede dejarlo en blanco. Lo descubrió este mismo oráculo al intentar
  -- reiniciarse entre casos, así que se afirma en vez de esquivarse.
  begin
    update public.perfiles set domicilio = null where id = v_cliente_vacio;
    raise exception 'CASO 5: se pudo VACIAR un domicilio ya registrado';
  exception when sqlstate '23514' then
    null; -- correcto: private.bloquear_borrado_domicilio_legal
  end;
  v_ok := v_ok + 1;

  -- ── 6. Normalización: espacios exóticos y dobles ──────────────────────────
  -- Para volver al punto de partida hay que bajar ESE candado, por su NOMBRE
  -- (nunca `disable trigger user`: así la auditoría sigue copiando). Todo el
  -- script termina en rollback, de modo que no sobrevive nada.
  alter table public.perfiles disable trigger perfiles_domicilio_legal_no_borrar;
  update public.perfiles set domicilio = null where id = v_cliente_vacio;
  alter table public.perfiles enable trigger perfiles_domicilio_legal_no_borrar;
  v_r := crm.completar_domicilio_cliente(
    v_cliente_vacio, '  Av.' || U&'\00A0' || U&'\00A0' || 'Grau   456,' || U&'\3000' || 'Lima  '
  );
  select p.domicilio into v_leido from public.perfiles p where p.id = v_cliente_vacio;
  if v_leido <> 'Av. Grau 456, Lima' then
    raise exception 'CASO 6: la normalización no coincide con la del navegador; quedó «%»', v_leido;
  end if;
  v_ok := v_ok + 1;

  -- ── 7. Lo que NO puede entrar ─────────────────────────────────────────────
  alter table public.perfiles disable trigger perfiles_domicilio_legal_no_borrar;
  update public.perfiles set domicilio = null where id = v_cliente_vacio;
  alter table public.perfiles enable trigger perfiles_domicilio_legal_no_borrar;
  foreach v_candidato in array array[
    'Lima',                                   -- 4 caracteres
    repeat('a', 241),                         -- 241
    -- Un control de VERDAD (campana, 0x07). El tabulador NO vale como caso: es
    -- espacio en blanco y ambos lados lo colapsan a un espacio normal — que es
    -- lo correcto. Lo destapó este oráculo esperando un rechazo que no toca.
    'Av. Lima' || chr(7) || 'x',
    repeat(U&'\200B', 6),                     -- seis espacios de ancho CERO
    repeat(U&'\00AD', 6),                     -- seis guiones suaves
    'Av. Los' || U&'\200B' || ' Alamos 123, Lima'  -- invisible escondido dentro
  ] loop
    begin
      perform crm.completar_domicilio_cliente(v_cliente_vacio, v_candidato);
      raise exception 'CASO 7: se aceptó un domicilio que debía rechazarse (%)', quote_literal(v_candidato);
    exception when sqlstate '22023' then
      null; -- correcto
    end;
  end loop;
  select p.domicilio into v_leido from public.perfiles p where p.id = v_cliente_vacio;
  if v_leido is not null then
    raise exception 'CASO 7: un rechazo dejó rastro; la columna vale %', v_leido;
  end if;
  v_ok := v_ok + 1;

  -- ──── 8. Ajeno: el que cambia es el ACTOR, no el cliente ───────────────────
  -- El seed solo tiene UN cliente, así que «ajeno» se prueba desde el otro lado:
  -- otro vendedor (vend3, de otro subárbol) contra el mismo cliente.
  begin
    perform set_config('request.jwt.claim.sub', v_otro_vendedor::text, true);
    begin
      perform crm.completar_domicilio_cliente(v_cliente_vacio, 'Av. Ajena 123, Lima');
      raise exception 'CASO 8: un vendedor de OTRO subárbol escribió el domicilio';
    exception when sqlstate '42501' then
      get stacked diagnostics v_msg_ajeno = message_text;
    end;
    -- El mismo texto para «no existe» que para «ajeno»: si difirieran, la
    -- función sería un buscador de clientes de otras carteras.
    begin
      perform crm.completar_domicilio_cliente(
        '00000000-0000-4000-8000-000000000000'::uuid, 'Av. Fantasma 1, Lima'
      );
      raise exception 'CASO 8: un cliente inexistente no fue rechazado';
    exception when sqlstate '42501' then
      get stacked diagnostics v_msg_inexistente = message_text;
    end;
    perform set_config('request.jwt.claim.sub', v_vendedor::text, true);
  end;
  if v_msg_ajeno is distinct from v_msg_inexistente then
    raise exception
      'CASO 8: el mensaje distingue ajeno («%») de inexistente («%») → oráculo de existencia',
      v_msg_ajeno, v_msg_inexistente;
  end if;
  v_ok := v_ok + 1;

  -- ── 9. faltan_analista habla de QUIEN LLAMA, no del asesor del cliente ────
  -- Se le vacía el teléfono al PROPIO llamante: si la función mirase al asesor
  -- del cliente (que aquí es el mismo) esto no probaría nada, así que se cambia
  -- de llamante a otro vendedor con permiso... y como no lo tiene sobre este
  -- cliente, se hace al revés: se vacía el teléfono del llamante y se exige que
  -- aparezca en faltan_analista.
  update public.perfiles set telefono = null where id = v_vendedor;
  v_r := crm.datos_legales_contrato_fn(v_cliente_vacio);
  if not (v_r->'faltan_analista' ? 'telefono') then
    raise exception 'CASO 9: faltan_analista no refleja el teléfono vacío del llamante (%)', v_r;
  end if;
  v_ok := v_ok + 1;

  --  ── 10. Sin sesión no se pasa ──────────────────────────────────────────────
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform crm.completar_domicilio_cliente(v_cliente_vacio, 'Av. Anonima 1, Lima, Lima');
    raise exception 'CASO 10: se escribió sin sesión';
  exception when insufficient_privilege then
    null; -- correcto
  end;
  v_ok := v_ok + 1;

  perform set_config('request.jwt.claim.sub', coalesce(v_sub_previo, ''), true);
  raise notice 'ORÁCULO DEL DOMICILIO LEGAL: % / 10 casos OK.', v_ok;
  if v_ok <> 10 then
    raise exception 'ORÁCULO: solo % de 10 casos se ejecutaron', v_ok;
  end if;
end;
$oraculo$;

-- Nada de lo anterior persiste: el oráculo escribe para poder comprobar, y se
-- deshace entero. Si esto fuera un commit, el script no podría correrse dos
-- veces seguidas ni contra un mundo que importe.
rollback;
