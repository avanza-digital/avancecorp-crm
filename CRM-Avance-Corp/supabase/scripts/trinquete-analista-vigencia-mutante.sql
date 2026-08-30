-- MUTANTE del trinquete de la vigencia (P-055 F5.a).
-- Rompe el arreglo de SIETE formas y exige que el gate ENTERO
-- -`private.assert_analista_vigencia()`, la misma funcion que ejecutan el guion
-- del repo, el postflight y el vigia- se ponga rojo en las siete. Si sobrevive a
-- alguna, la prueba no prueba nada. Termina SIEMPRE en `raise exception`.
--
-- Los filos 2, 3, 4 y 6 son EVASIONES REALES que un censo por texto suelto no
-- caza: el comentario senuelo, la puerta mixta, la vista y el rol comprobado a
-- mano sin nombrar la funcion.
do $$
declare
  f text := '';
  r text;
begin
  begin
    r := private.assert_analista_vigencia();
  exception when others then
    raise exception 'MUTANTE: el gate ya estaba ROJO antes de empezar: %', sqlerrm;
  end;

  -- m1: puerta nueva con la pregunta cruda.
  execute $d$ create or replace function public.f5a_mut_1() returns boolean
              language sql stable as $g$ select public.es_analista() $g$ $d$;
  begin perform private.assert_analista_vigencia(); f := f || ' [m1] puerta nueva sin declarar;';
  exception when others then null; end;
  execute 'drop function public.f5a_mut_1()';

  -- m2: COMENTARIO SENUELO. La funcion pregunta lo viejo pero menciona la nueva
  --     en un comentario. Un censo por substring la daria por migrada.
  execute $d$ create or replace function public.f5a_mut_2() returns boolean
              language sql stable as $g$
                -- ya migrado a private.es_analista_vigente()
                select public.es_analista() $g$ $d$;
  begin perform private.assert_analista_vigencia(); f := f || ' [m2] comentario senuelo;';
  exception when others then null; end;
  execute 'drop function public.f5a_mut_2()';

  -- m3: PUERTA MIXTA. Pregunta la nueva Y la vieja con un `or`.
  execute $d$ create or replace function public.f5a_mut_3() returns boolean
              language sql stable as $g$
                select private.es_analista_vigente() or public.es_analista() $g$ $d$;
  begin perform private.assert_analista_vigencia(); f := f || ' [m3] puerta mixta;';
  exception when others then null; end;
  execute 'drop function public.f5a_mut_3()';

  -- m4: una VISTA con la pregunta cruda.
  execute $d$ create or replace view public.f5a_mut_vista as
              select 1 as x where public.es_analista() $d$;
  begin perform private.assert_analista_vigencia(); f := f || ' [m4] vista sin declarar;';
  exception when others then null; end;
  execute 'drop view public.f5a_mut_vista';

  -- m5: una POLITICA nueva con la pregunta cruda.
  execute $d$ create policy f5a_mut_policy on public.contratos for select to authenticated
              using (public.es_analista()) $d$;
  begin perform private.assert_analista_vigencia(); f := f || ' [m5] politica sin vigencia;';
  exception when others then null; end;
  execute 'drop policy f5a_mut_policy on public.contratos';

  -- m6: EL ROL A MANO, sin nombrar la funcion.
  execute $d$ create or replace function public.f5a_mut_6() returns boolean
              language sql stable as $g$
                select exists (select 1 from public.perfiles
                                where id = auth.uid() and rol = 'analista') $g$ $d$;
  begin perform private.assert_analista_vigencia(); f := f || ' [m6] comprobacion cruda del rol;';
  exception when others then null; end;
  execute 'drop function public.f5a_mut_6()';

  -- m7: una funcion YA EXENTA cambia de cuerpo -> su razon caduca.
  execute $d$ create or replace function public.f5a_mut_placeholder() returns boolean
              language sql stable as $g$ select true $g$ $d$;
  execute 'drop function public.f5a_mut_placeholder()';
  update private.analista_vigencia_exenciones
     set huella = 'huella-que-ya-no-cuadra-0000000000'
   where objeto = 'public.crear_contrato(jsonb,jsonb)';
  begin perform private.assert_analista_vigencia(); f := f || ' [m7] exencion caducada;';
  exception when others then null; end;

  if f <> '' then
    raise exception 'MUTANTE_VIGENCIA_SOBREVIVIO en el/los filo(s):% (todo deshecho)', f;
  end if;
  raise exception 'MUTANTE_VIGENCIA_CAZADO por los 7 filos. Punto de partida: %. TODO DESHECHO.', r;
end $$;
