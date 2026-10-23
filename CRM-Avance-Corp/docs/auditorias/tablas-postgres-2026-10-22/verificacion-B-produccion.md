# Verificación en producción de los hallazgos del frente B (solo lectura, 2026-10-22, entre 20:40 y 21:03 Lima (hora real por `date`))

| Hallazgo | Consulta | Resultado | Lectura |
|---|---|---|---|
| B-1 | acreditaciones selladas / tocadas después del sello / sin analista | 161 / 161 / 0 | Las 161 «tocadas» tienen `actualizado_en − sellado_en < 2 s`: es el mismo UPDATE del sello, NO una edición posterior. La consulta del agente da falso positivo; el hueco estructural (sin trigger) sigue siendo real. Todas son de `2026-09-01` (septiembre ya sellado hoy). |
| B-3 | peso sellado vs peso que daría hoy | ago 0.150=0.150 · sep 0.150=0.150 · `conversion_pesos` tiene 2 filas | Sin desvío hoy. `n_live_tup=0` era estadística vieja. |
| B-4 | estados de `cierre_mes_vendedor` / incoherentes / negativos | medible 32, solo_arrastre 4, sin_actividad 6 / 0 / 0 | Dominio real = 3 de los 4 valores previstos. Datos limpios. |
| B-5 | valores reales de los `text` sin CHECK | veredicto: 7 valores (`tomado`, `tomado_ok`, `libre`, `enfriamiento`, `no_contactar`, `reutilizable`, `ya_es_cliente`) · comando: `tarea`, `agendar`, `revisar_retiro`, `solicitar_retiro` · acreditaciones.origen y lead_asignaciones.origen: todos dentro del CHECK de `leads.origen` · categoria_interes: nuevo/renovacion/upgrade/null · identificadores.fuente: 10 valores, uno con uuid incrustado (`f8-identidades:<uuid>`:7) | Datos coherentes hoy; `fuente` es texto libre de verdad (etiquetas de backfill). |
| B-6 | teléfonos fuera de `+519########` / fuera de E.164 / vivos fuera de formato | 0 / 0 / 0 | Hoy todo normalizado. El CHECK en INSERT sigue faltando (preventivo). |
| B-7 | personas con 2 «primeras conversiones» vigentes | 0 | Limpio; el índice único sería preventivo. |
| B-8 | identificadores incoherentes / 2 docs vigentes mismo tipo / puente invertido / responsables solapados | 0 / 0 / 0 / 0 | Limpio. |
| B-9 | montos y tasas con más de 2 decimales | 0 / 0 / 0 / 0 | Limpio. |
| B-11 | inversiones vigentes sin fecha_comercial / eventos sin motivo / sin actor | 0 / 0 / 0 | Limpio. |
| B-12 | leads con nombre vacío / correo mal formado | 0 / 0 | Limpio. |
| B-13 | inversiones sin ningún evento | 33 | Confirmado: 33 inversiones sin la defensa indirecta de la FK desde `inversion_eventos`. |
| B-15 | roles en `private.pares_autoridad` | 9 pares, todos con valores conocidos (`comercial/vendedor`, `analista/supervisor`, `admin/gerencia`, `superadmin/gerencia`, `directorio/directorio`, `admin/(null)`…) | Sin valor mal escrito hoy. |

Conclusión del frente B: NINGÚN hallazgo tiene datos rotos hoy. Todos son candados que faltan en la base y que hoy
sostiene el código. El único P1 (B-1, `conversion_acreditaciones` sin trigger de inmutabilidad) queda confirmado como
estructural.
