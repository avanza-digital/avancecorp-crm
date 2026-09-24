# Gestión Diaria: recorrido de supervisión conforme

**24/09/2026, hora de Lima. Recorrido de negocio ACEPTADO por Miguel.**
H6.4 queda cerrada, con 72/72 tareas del supervisor horizontal. La etapa 6
de F4 conserva pendientes sus comprobaciones operativas posteriores.

Miguel confirmó «Lo valido yo con esta cuenta» y, después del recorrido,
«Sí, doy por conforme este recorrido». La conformidad corresponde a comparar
al equipo, detectar atención y abrir su registro para la gestión comercial;
no se deduce de las pruebas técnicas anteriores.

## Producto y alcance

- [CRM publicado](https://crm.miavance.com/#/gestion-diaria), fuente
  `929fbbcccb5710e1031f734a034e8ce90a79b0b2`, build
  `build-20260924T161347948Z`, comprobado por HTTPS durante este recorrido.
- Chrome con la sesión existente de supervisor y su equipo propio. Lecturas
  de contraste por Supabase en transacciones `READ ONLY`, sin suplantar roles.
- Sin cambios de producto, políticas, permisos, relojes ni actividad ficticia.
  La única acción operativa de este recorrido fue el aplazamiento solicitado
  expresamente por Miguel. No se ejecutó reconocimiento.

## Evidencia de negocio

| Comprobación | Resultado observado |
|---|---|
| Equipo | 10 personas: 6 con llamadas y 4 sin llamadas; 10 con pendientes y atención. |
| Conteo directo de actividades | 43 llamadas acumuladas a las 12:30; coinciden los diez casos anonimizados con la pantalla. |
| Primer corte | 4 cumplieron al corte, 1 recuperó y 5 seguían bajo el mínimo; ninguno sin cartera abierta. |
| Recuperación real | Un caso tenía 1 llamada a las 11:30. El registro muestra 11:25, 11:40 y 12:10; al alcanzar 3, se retiró su aviso de corte. |
| Contacto y cantidad | Las tres llamadas no contestadas cuentan para el corte. El resumen conserva contacto 0 %, 3 llamadas útiles y muestra insuficiente frente al mínimo 5. |
| Pendientes | El caso recuperado mantiene 104 tareas pendientes y 46 vencidas. El filtro de vencidas cargó 25 y luego 46, hasta fin de páginas. |
| Lista y campana | Antes de posponer: un grupo de corte y otros cuatro avisos. Después: campana con 4 pendientes; el grupo pospuesto sigue visible en la lista y en Gestión Diaria. |
| Regla vigente | Política v2 desde medianoche Lima: cortes ON, 11:30 mínimo 3, 16:00 crecimiento 150 %, piso 8 y techo 30; sábado mínimo 3. Canal ON, tasa baja NULL/OFF. |

Las consultas conservaron la diferencia entre la base fija del corte y las
llamadas posteriores para recuperación. Resumen, registro y pendientes abrieron
el caso seleccionado. No se detectó una incidencia nueva ni se pidió un ajuste
de producto en este recorrido. La evidencia versionada no incluye nombres ni
IDs de analistas/clientes, notas comerciales o capturas del CRM real.

## Aplazamiento real solicitado

Miguel eligió «Posponer 1 hora y comprobarlo» para el aviso real de las 11:30,
que agrupaba a cinco analistas. La UI guardó una sola acción `posponer` a las
**12:34:21.131818**, con vencimiento **13:34:21.131818**, exactamente 3.600 segundos.

**PASS:** lectura persistida, recarga completa y nueva pestaña del mismo
navegador. En ambos recorridos figura «Pospuesto hasta las 13:34; el pendiente
sigue visible». Ya no se ofrece otro botón «Posponer 1 hora». El resultado
del corte mantiene sus cinco pendientes; posponer no los borra.
La lectura final de las 12:50 confirma un aplazamiento, cero reconocimientos
y una sola entrega del aviso, sin duplicados después de reabrir.

**NOT RUN:** otra sesión autenticada o dispositivo independiente. Una pestaña
nueva comparte la sesión y no acredita esa comprobación. Tampoco se pulsó
«Lo estoy atendiendo», porque la decisión de Miguel fue posponer.

## Seguimiento que permanece abierto

- [x] Recorrido de negocio con supervisión y conformidad humana.
- [x] Primer corte observado después de su horario y cifras contrastadas.
- [x] Aplazamiento real, recarga y nueva apertura comprobados.
- [ ] Desde las **13:34**, comprobar un único reaviso si aún corresponde y
  completar el reconocimiento con la decisión operativa del supervisor.
- [ ] Contrastar reconocimiento/aplazamiento en otra sesión o dispositivo.
- [ ] Observar el corte de las **16:00** y sus objetivos sobre la base de
  las 11:30; verificar la ausencia de reaviso al cierre de las 18:00.
- [ ] Consolidar incidencias y evidencia final de F4 cuando terminen esos pasos.
- [ ] Sábado **26/09, 11:30**: corte único, mínimo 3, cierre de jornada 13:00.

No se marca «Observar ambos cortes» ni «Confirmar cifras, avisos,
reconocimiento y aplazamiento entre sesiones o dispositivos» como completas.
La validación de analista, Safari/lectores y `gate:realidad` conserva los límites
anteriores. No se instaló ningún monitor ni se promete seguimiento automático.

## Evidencia y plan

- [Datos anonimizados del recorrido](recorrido-2026-09-24/evidencia.json).
- [Lectura posterior de Figma](recorrido-2026-09-24/figma-despues.json).
- [Etapa 6](recorrido-2026-09-24/figma-f4-recorrido.png) y
  [H6 aceptada](recorrido-2026-09-24/figma-h6-aceptada.png), inspeccionadas sin
  recortes ni solapamientos.
- [Mismo tablero](https://www.figma.com/board/9Pg7jMDRg3UVbb4XfeM80L?node-id=2-90):
  se cierra solo la quinta casilla de F4.6; los otros controles quedan abiertos.
  H6 pasa de 70/72 a 72/72; los 76 puntos del plan general conservan sus IDs.
- Copia durable: `/Users/usuario/.local/share/avancecorp-checkpoints/gestion-diaria-recorrido-2026-09-24/`.

Esta acta no requiere publicar de nuevo. La fuente del artefacto sigue siendo
`929fbbcc`, aunque se integre después este cierre documental.
