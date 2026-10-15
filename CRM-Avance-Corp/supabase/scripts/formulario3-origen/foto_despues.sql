do $foto$ declare r record; begin
  if to_regclass('pg_temp._foto_f3_antigua') is not null then
    perform pg_temp.exigir((select to_jsonb(f)=a.fila from crm.cierre_mes_vendedor f
      cross join pg_temp._foto_f3_antigua a where f.periodo='2026-08-01'),
      'A/B conservan la foto sellada byte por byte');
    select * into strict r from private.conversion_divisor_empresa('2026-08-01','2026-08-31');
    perform pg_temp.exigir(r.divisor=10 and r.numerador=2 and r.conversion_pct=20
      and r.nombre='NOMBRE CONGELADO' and r.divisor_formulario_3 is null and r.cierres_formulario_3 is null,
      'foto antigua conserva sus cifras y F3 ausente es NULL, nunca cero inventado');
  end if;
end $foto$;
