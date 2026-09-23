-- MUTANTE de «los vigias cierran sus propias alertas». SIETE filos; cada uno
-- ejecuta las funciones REALES y las hace fallar si la defensa no esta.
-- Termina SIEMPRE en raise exception: todo se deshace, nada queda escrito.
--
-- Se puede correr contra produccion: las filas que inserta son de prueba
-- (motivo prefijado 'MUTANTE:') y mueren con el rollback del raise final.
--
-- 🔑 POR QUE HAY DOS FILOS ESTATICOS (m6 y m7). Dos de los tres asserts estan
-- en ROJO, asi que la rama `if v_verde then update ...` de sus vigias NO SE
-- PUEDE EJECUTAR hoy: un filo dinamico no la tocaria ni la probaria. Un literal
-- de fase mal escrito SOLO en el `update` de uno de ellos reinstalaria el
-- defecto entero -- alertas que se acumulan para siempre -- y nadie lo veria
-- hasta que frenara la proxima obra. m6 lo lee del cuerpo; m7 lo rompe a
-- proposito y exige que el detector lo cante.
do $$
declare
  f text := '';
  r text;
  v_n integer;
  v_antes integer;
  v_f5a_verde boolean;
  v_def text;
  v_mal text;
begin
  if to_regprocedure('private.vigia_analitica_leads_citas()') is null
     or to_regprocedure('private.vigia_analista_vigencia()') is null
     or to_regprocedure('private.vigia_f7_piezas()') is null
     or to_regprocedure('private.vigia_alertas_sin_cierre()') is null
     or to_regprocedure('private.vigia_fases_cerrables()') is null then
    raise exception 'MUTANTE: falta alguna de las piezas; esta migracion no esta aplicada';
  end if;

  select count(*)::text into r from private.vigia_alertas where resuelta_en is null;

  -- ── m1: en VERDE, el vigia cierra una alerta de SU fase ────────────────────
  insert into private.vigia_alertas (fase, motivo)
  values ('f6a_analitica_leads_citas', 'MUTANTE: alerta plantada para el filo m1');
  perform private.vigia_analitica_leads_citas();
  select count(*) into v_n from private.vigia_alertas
   where motivo = 'MUTANTE: alerta plantada para el filo m1' and resuelta_en is null;
  if v_n <> 0 then f := f || ' [m1] el vigia en verde NO cerro su propia alerta;'; end if;

  -- ── m2: en VERDE, el vigia NO toca las alertas de OTRA fase ────────────────
  insert into private.vigia_alertas (fase, motivo)
  values ('f5a_analista_vigencia', 'MUTANTE: ajena m2'),
         ('f7_piezas_cerradas',    'MUTANTE: ajena m2');
  perform private.vigia_analitica_leads_citas();
  select count(*) into v_n from private.vigia_alertas
   where motivo = 'MUTANTE: ajena m2' and resuelta_en is null;
  if v_n <> 2 then f := f || format(' [m2] el vigia de analitica toco alertas ajenas (quedaban %s de 2);', v_n); end if;

  -- ── m3: el invariante en ROJO, medido ANTES/DESPUES ────────────────────────
  --     La regla es «verde cierra, rojo no». La version anterior de este filo
  --     preguntaba si EXISTIA una alerta f5a abierta no-MUTANTE -- y las 16
  --     reales ya la satisfacian solas, asi que habria pasado aunque el vigia
  --     hubiera perdido entera su rama de insert. Ahora se mide la DIFERENCIA,
  --     que es lo unico que dice algo sobre lo ocurrido durante el filo.
  begin
    perform private.assert_analista_vigencia();
    v_f5a_verde := true;
  exception when others then
    v_f5a_verde := false;
  end;

  select count(*) into v_antes from private.vigia_alertas
   where fase = 'f5a_analista_vigencia' and resuelta_en is null;
  insert into private.vigia_alertas (fase, motivo)
  values ('f5a_analista_vigencia', 'MUTANTE: alerta plantada para el filo m3');
  perform private.vigia_analista_vigencia();
  select count(*) into v_n from private.vigia_alertas
   where fase = 'f5a_analista_vigencia' and resuelta_en is null;

  if v_f5a_verde then
    -- verde: la plantada y las que hubiera tienen que quedar todas cerradas.
    if v_n <> 0 then f := f || format(' [m3] el assert estaba VERDE y quedaron %s alertas f5a abiertas;', v_n); end if;
  else
    -- rojo: las de antes SIGUEN abiertas (+1 plantada) y el vigia anade la suya.
    if v_n <> v_antes + 2 then
      f := f || format(' [m3] en ROJO se esperaban %s alertas f5a abiertas (%s de antes + la plantada + la del vigia) y hay %s;',
                       v_antes + 2, v_antes, v_n);
    end if;
  end if;

  -- ── m4: una fase huerfana se VE ────────────────────────────────────────────
  insert into private.vigia_alertas (fase, motivo)
  values ('f6c_ajuste_sin_episodio', 'MUTANTE: huerfana m4');
  if not exists (select 1 from private.vigia_alertas_sin_cierre() s
                  where s.fase = 'f6c_ajuste_sin_episodio' and s.abiertas >= 1) then
    f := f || ' [m4] una fase sin vigia NO aparece en vigia_alertas_sin_cierre;';
  end if;

  -- ── m5: y ningun vigia la cierra por error ─────────────────────────────────
  perform private.vigia_analitica_leads_citas();
  perform private.vigia_analista_vigencia();
  perform private.vigia_f7_piezas();
  select count(*) into v_n from private.vigia_alertas
   where motivo = 'MUTANTE: huerfana m4' and resuelta_en is null;
  if v_n <> 1 then f := f || ' [m5] un vigia cerro una alerta de una fase que no es la suya;'; end if;

  -- ── m6 (ESTATICO): cada vigia ABRE y CIERRA la misma fase ──────────────────
  --     Se lee del cuerpo. Es lo unico que cubre a los vigias cuyo assert esta
  --     en rojo, porque su rama de cierre no se puede ejecutar hoy.
  select string_agg(v.vigia || ' abre «' || coalesce(v.fase_que_abre,'?') || '» cierra «' || coalesce(v.fase_que_cierra,'?') || '»', '; ')
    into v_mal
    from private.vigia_fases_cerrables() v
   where v.fase_que_abre is null or v.fase_que_cierra is null
      or v.fase_que_abre is distinct from v.fase_que_cierra;
  if v_mal is not null then f := f || ' [m6] un vigia abre y cierra fases distintas: ' || v_mal || ';'; end if;
  select count(*) into v_n from private.vigia_fases_cerrables();
  if v_n <> 3 then f := f || format(' [m6] se esperaban 3 vigias que escriben en vigia_alertas y hay %s;', v_n); end if;

  -- ── m7 (ESTATICO): romper el literal de UN vigia y exigir que se CANTE ─────
  --     Este es el mutante de verdad de la defensa nueva: se desvia el `update`
  --     de vigia_f7_piezas a una fase que no existe. La consecuencia real seria
  --     que f7 no se cerrara NUNCA; lo que se exige es que el detector lo diga
  --     en vez de declararla cubierta.
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p where p.oid = 'private.vigia_f7_piezas()'::regprocedure;
  execute replace(v_def,
    'where fase = ''f7_piezas_cerradas'' and resuelta_en is null',
    'where fase = ''f7_piezas'' and resuelta_en is null');

  if not exists (select 1 from private.vigia_fases_cerrables() v
                  where v.vigia = 'private.vigia_f7_piezas()'
                    and v.fase_que_abre is distinct from v.fase_que_cierra) then
    f := f || ' [m7] se desvio el literal del update y vigia_fases_cerrables no lo noto;';
  end if;
  if not exists (select 1 from private.vigia_alertas_sin_cierre() s
                  where s.fase = 'f7_piezas_cerradas') then
    f := f || ' [m7] con el literal desviado, f7_piezas_cerradas NO aparece como huerfana: el detector la da por cubierta;';
  end if;
  execute v_def;  -- restaurar el cuerpo bueno

  if f <> '' then
    raise exception 'MUTANTE_VIGIAS_SOBREVIVIO en el/los filo(s):% (todo deshecho)', f;
  end if;
  raise exception 'MUTANTE_VIGIAS_CAZADO por los 7 filos. Alertas abiertas al empezar: %. TODO DESHECHO.', r;
end $$;
