-- MUTANTE del trinquete de la analitica (P-055 F6.a). DIEZ filos; el gate
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

  if f <> '' then
    raise exception 'MUTANTE_ANALITICA_SOBREVIVIO en el/los filo(s):% (todo deshecho)', f;
  end if;
  raise exception 'MUTANTE_ANALITICA_CAZADO por los 10 filos. Punto de partida: %. TODO DESHECHO.', r;
end $$;
