-- Estado del gesto de cierre de los vigias. Solo LECTURA: no escribe nada.
--
-- El verde no se da por «no hubo error»: se da por VER esta fila. El canal
-- `supabase db query` devuelve codigo 0 aunque la consulta reviente, asi que el
-- envoltorio (gate-vigias.mjs) exige encontrar el texto que empieza por «OK:».
select case
         -- (1) Cada vigia tiene que ABRIR y CERRAR la misma fase. Se lee de su
         --     cuerpo, no de una lista repetida a mano: un literal desviado
         --     solo en el `update` dejaria esa fase sin cerrar para siempre.
         when exists (select 1 from private.vigia_fases_cerrables() v
                       where v.fase_que_abre is null
                          or v.fase_que_cierra is null
                          or v.fase_que_abre is distinct from v.fase_que_cierra)
           then 'ROJO: un vigia abre y cierra fases distintas: ' ||
                (select string_agg(v.vigia || ' abre «' || coalesce(v.fase_que_abre,'?') ||
                                   '» cierra «' || coalesce(v.fase_que_cierra,'?') || '»', '; ')
                   from private.vigia_fases_cerrables() v
                  where v.fase_que_abre is null
                     or v.fase_que_cierra is null
                     or v.fase_que_abre is distinct from v.fase_que_cierra)

         -- (2) Los tres tienen que seguir estando. Si uno pierde su `update`,
         --     desaparece de la lista y su fase queda sin cerrar.
         when (select count(*) from private.vigia_fases_cerrables()) <> 3
           then 'ROJO: se esperaban 3 vigias que escriben en vigia_alertas y hay ' ||
                (select count(*)::text from private.vigia_fases_cerrables())

         -- (3) Y ninguna alerta abierta puede pertenecer a una fase que nadie
         --     sabe cerrar: eso es lo que bloquea el stop-the-line para siempre.
         when exists (select 1 from private.vigia_alertas_sin_cierre())
           then 'ROJO: hay alertas abiertas de una fase sin cierre: ' ||
                (select string_agg(x.fase || ' (' || x.abiertas || ', desde ' || x.desde || ')', ', ')
                   from private.vigia_alertas_sin_cierre() x)

         else 'OK: ' ||
              (select count(*)::text from private.vigia_fases_cerrables()) ||
              ' vigias abren y cierran su propia fase; ' ||
              (select count(*)::text from private.vigia_alertas where resuelta_en is null) ||
              ' alertas abiertas y ' ||
              (select count(*)::text from private.vigia_alertas where resuelta_en is not null) ||
              ' cerradas; 0 fases sin cierre'
       end as veredicto;
