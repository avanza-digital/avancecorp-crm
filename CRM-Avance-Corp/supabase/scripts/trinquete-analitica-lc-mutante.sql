-- MUTANTE del trinquete de la analitica (P-055 F6.a). DIECISEIS filos; el gate
-- ENTERO (private.assert_analitica_leads_citas) tiene que ponerse rojo en todos.
-- Termina SIEMPRE en raise exception: todo se deshace.
do $$
declare f text := ''; r text; v_aux text; v_def text;
begin
  begin r := private.assert_analitica_leads_citas();
  exception when others then
    raise exception 'MUTANTE: el gate ya estaba ROJO antes de empezar: %', sqlerrm; end;

  -- m1: contador crudo nuevo sin declarar.
  execute $d$ create or replace function public.f6_mut_1() returns integer
              language sql stable as $g$ select count(*)::int from crm.leads $g$ $d$;
  begin perform private.assert_analitica_leads_citas(); f := f || ' [m1] contador nuevo;';
  exception when others then null; end;
  execute 'drop function public.f6_mut_1()';

  -- m2: COMENTARIO SENUELO (nombra el nucleo pero cuenta crudo).
  execute $d$ create or replace function public.f6_mut_2() returns integer
              language sql stable as $g$
                -- ya migrado a citas_episodios
                select count(*)::int from crm.leads $g$ $d$;
  begin perform private.assert_analitica_leads_citas(); f := f || ' [m2] comentario senuelo;';
  exception when others then null; end;
  execute 'drop function public.f6_mut_2()';

  -- m3: MIXTO no declarado (usa el nucleo Y cuenta crudo aparte).
  execute $d$ create or replace function public.f6_mut_3() returns integer
              language sql stable as $g$
                select (select count(*)::int from private.citas_episodios(now()-interval '1 day', now()))
                     + (select count(*)::int from crm.leads) $g$ $d$;
  begin perform private.assert_analitica_leads_citas(); f := f || ' [m3] mixto sin declarar;';
  exception when others then null; end;
  execute 'drop function public.f6_mut_3()';

  -- m4: una VISTA que cuenta crudo.
  execute $d$ create or replace view public.f6_mut_vista as
              select count(*) as n from crm.leads $d$;
  begin perform private.assert_analitica_leads_citas(); f := f || ' [m4] vista sin declarar;';
  exception when others then null; end;
  execute 'drop view public.f6_mut_vista';

  -- m5: la huella sellada de un exento deja de cuadrar con su cuerpo -> caduca.
  --     (Mismo camino de codigo que si el CUERPO cambiara: la desigualdad.)
  --     El sello de la lista se re-sella para AISLAR el filo, y al final se
  --     RESTAURA todo (huella y sello) para que los filos siguientes partan de
  --     verde - una captura que hereda el rojo anterior no prueba nada.
  select huella into v_aux from private.analitica_leads_citas_exenciones
   where objeto = 'crm.rescate_descartes_meses()';
  update private.analitica_leads_citas_exenciones
     set huella = 'huella-que-ya-no-cuadra-000000000'
   where objeto = 'crm.rescate_descartes_meses()';
  update private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc() where id;
  begin perform private.assert_analitica_leads_citas(); f := f || ' [m5] exencion caducada;';
  exception when others then
    if sqlerrm not like '%cuerpo CAMBIO%' then f := f || format(' [m5] rojo por OTRA razon (%s);', sqlerrm); end if;
  end;
  update private.analitica_leads_citas_exenciones set huella = v_aux
   where objeto = 'crm.rescate_descartes_meses()';
  update private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc() where id;

  -- m6: subir el tope -> rebota.
  begin update private.analitica_leads_citas_tope set tope = tope + 3 where id; v_aux := 'NO';
  exception when others then v_aux := 'si'; end;
  if v_aux <> 'si' then f := f || ' [m6] el tope se dejo subir;'; end if;

  -- m7: la pantalla de reuniones deja de beber del nucleo DE VERDAD (su cuerpo
  --     se reescribe sin la llamada) y el assert tiene que decir exactamente eso.
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p where p.oid = 'private.metricas_reuniones_implementacion(date,date)'::regprocedure;
  execute replace(v_def, 'private.citas_episodios(', 'private.citas_episodios_renombrada_por_mutante(');
  begin perform private.assert_analitica_leads_citas(); f := f || ' [m7] no noto que la pantalla dejo de beber;';
  exception when others then
    if sqlerrm not like '%dejo de beber%' and sqlerrm not like '%cuerpo CAMBIO%' then
      f := f || format(' [m7] rojo por otra razon (%s);', sqlerrm); end if;
  end;
  execute v_def;  -- restaurar

  -- m8: el nucleo de CITAS desaparece (renombrado) -> rojo.
  alter function private.citas_episodios(timestamptz, timestamptz, timestamptz)
    rename to citas_episodios_mutado;
  begin perform private.assert_analitica_leads_citas(); f := f || ' [m8] no noto la desaparicion del nucleo de citas;';
  exception when others then null; end;
  alter function private.citas_episodios_mutado(timestamptz, timestamptz, timestamptz)
    rename to citas_episodios;

  -- m9: el nucleo de LEADS desaparece (renombrado) -> rojo.
  alter function private.conversion_episodios(timestamptz, timestamptz, date, boolean, uuid[], numeric)
    rename to conversion_episodios_mutado;
  begin perform private.assert_analitica_leads_citas(); f := f || ' [m9] no noto la desaparicion del nucleo de leads;';
  exception when others then null; end;
  alter function private.conversion_episodios_mutado(timestamptz, timestamptz, date, boolean, uuid[], numeric)
    rename to conversion_episodios;

  -- m10: quitar el candado del tope -> el assert lo nota SIN que nadie suba nada.
  execute 'alter table private.analitica_leads_citas_tope disable trigger trg_analitica_lc_tope_solo_baja';
  begin perform private.assert_analitica_leads_citas(); f := f || ' [m10] no noto el candado del tope apagado;';
  exception when others then null; end;
  execute 'alter table private.analitica_leads_citas_tope enable trigger trg_analitica_lc_tope_solo_baja';

  -- m11: AFLOJAR una clase (analitica -> operativo) -> el candado rebota.
  --      Es el unico camino por el que el techo podria ceder sin migracion:
  --      reetiquetar y re-sellar. Tiene que ser imposible.
  begin
    update private.analitica_leads_citas_exenciones set clase = 'operativo'
     where objeto = 'crm.cerrar_periodo(date)';
    v_aux := 'NO';
  exception when others then v_aux := 'si'; end;
  if v_aux <> 'si' then
    f := f || ' [m11] la clase se dejo aflojar;';
    update private.analitica_leads_citas_exenciones set clase = 'analitica'
     where objeto = 'crm.cerrar_periodo(date)';
  end if;

  -- m12: quitar el candado de la clase -> el assert lo nota SIN que nadie
  --      reetiquete nada (mismo patron que m10 con el candado del tope).
  execute 'alter table private.analitica_leads_citas_exenciones disable trigger trg_analitica_lc_clase_solo_aprieta';
  begin perform private.assert_analitica_leads_citas(); f := f || ' [m12] no noto el candado de la clase apagado;';
  exception when others then null; end;
  execute 'alter table private.analitica_leads_citas_exenciones enable trigger trg_analitica_lc_clase_solo_aprieta';

  -- m13: APRETAR una clase (operativo -> analitica) si se permite, y entonces
  --      la poblacion vigilada sube por encima del techo: el trinquete tiene
  --      que saltar. Prueba que el conteo nuevo -- el que solo mira
  --      analitica/mixta -- de verdad muerde, y no solo que existe.
  update private.analitica_leads_citas_exenciones set clase = 'analitica'
   where objeto = 'crm.cola_accion_fn(integer)';
  update private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc() where id;
  begin perform private.assert_analitica_leads_citas(); f := f || ' [m13] no noto que la analitica subio por encima del techo;';
  exception when others then
    if sqlerrm not like '%solo deja bajar%' then f := f || format(' [m13] rojo por OTRA razon (%s);', sqlerrm); end if;
  end;
  -- Restaurar: aflojar rebotaria, asi que el candado se apaga un instante.
  execute 'alter table private.analitica_leads_citas_exenciones disable trigger trg_analitica_lc_clase_solo_aprieta';
  update private.analitica_leads_citas_exenciones set clase = 'operativo'
   where objeto = 'crm.cola_accion_fn(integer)';
  execute 'alter table private.analitica_leads_citas_exenciones enable trigger trg_analitica_lc_clase_solo_aprieta';
  update private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc() where id;

  -- m14: reetiquetar SIN re-sellar -> el sello tiene que notarlo. Prueba que
  --      la clase entra de verdad en la huella de la lista. Se elige una fila
  --      de FUERA del censo para aislar el filo: si se tocara una del censo
  --      saltaria antes el techo y este control no quedaria probado.
  select clase into v_aux from private.analitica_leads_citas_exenciones
   where objeto = 'crm.resumen_cartera_fn()';
  update private.analitica_leads_citas_exenciones set clase = 'analitica'
   where objeto = 'crm.resumen_cartera_fn()';
  begin perform private.assert_analitica_leads_citas(); f := f || ' [m14] la clase no entra en el sello;';
  exception when others then
    if sqlerrm not like '%sin re-sellarse%' then f := f || format(' [m14] rojo por OTRA razon (%s);', sqlerrm); end if;
  end;
  execute 'alter table private.analitica_leads_citas_exenciones disable trigger trg_analitica_lc_clase_solo_aprieta';
  update private.analitica_leads_citas_exenciones set clase = v_aux
   where objeto = 'crm.resumen_cartera_fn()';
  execute 'alter table private.analitica_leads_citas_exenciones enable trigger trg_analitica_lc_clase_solo_aprieta';

  -- m15: colar un sujeto DEL CENSO como 'verificador' (la etiqueta que no
  --      consume cupo) y re-sellar -> el assert tiene que negarse. Se parte de
  --      un 'operativo', porque aflojar desde 'analitica' ya rebota en m11.
  update private.analitica_leads_citas_exenciones set clase = 'verificador'
   where objeto = 'crm.cola_accion_fn(integer)';
  update private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc() where id;
  begin perform private.assert_analitica_leads_citas(); f := f || ' [m15] dejo colar un verificador dentro del censo;';
  exception when others then
    if sqlerrm not like '%declaro verificador%' then f := f || format(' [m15] rojo por OTRA razon (%s);', sqlerrm); end if;
  end;
  update private.analitica_leads_citas_exenciones set clase = 'operativo'
   where objeto = 'crm.cola_accion_fn(integer)';
  update private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc() where id;

  -- m16: quitar el NOT NULL de la clase -> el assert lo nota SIN que ninguna
  --      fila se quede sin clase todavia (una declaracion futura podria nacer
  --      sin clasificar, y eso ya es el agujero).
  execute 'alter table private.analitica_leads_citas_exenciones alter column clase drop not null';
  begin perform private.assert_analitica_leads_citas(); f := f || ' [m16] no noto que la clase dejo de ser obligatoria;';
  exception when others then
    if sqlerrm not like '%obligatoria%' then f := f || format(' [m16] rojo por OTRA razon (%s);', sqlerrm); end if;
  end;
  execute 'alter table private.analitica_leads_citas_exenciones alter column clase set not null';

  if f <> '' then
    raise exception 'MUTANTE_ANALITICA_SOBREVIVIO en el/los filo(s):% (todo deshecho)', f;
  end if;
  raise exception 'MUTANTE_ANALITICA_CAZADO por los 16 filos. Punto de partida: %. TODO DESHECHO.', r;
end $$;
