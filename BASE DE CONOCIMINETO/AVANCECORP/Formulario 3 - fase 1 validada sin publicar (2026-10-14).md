# Formulario 3 - fase 1 validada sin publicar

Fecha: 14/10/2026. **Fase 1 implementada y validada en bancos aislados.**
Producción todavía no tiene el cambio; n8n continúa inactivo, con envío apagado.
Sigue la fase 2: mostrar y filtrar la campaña en el CRM.

Relacionado: [[Formulario 3 - plan de integración en CRM y activación (2026-10-14)]]
· [[n8n - Formulario 3 preparado y avisos conectados (2026-10-14)]]
· [[Canales de origen de leads CRM]].

## Resultado

El importador guarda `campania_origen=Formulario 3` junto con el alta, en la misma
transacción. El canal sigue siendo `formulario`, con las reglas vigentes de
reparto y conversión. Los envíos anteriores siguen funcionando. Duplicados
conservan origen, campaña y responsable; clientes reconocidos reciben campaña
en la actividad o solicitud existente, sin reclasificarlos como nuevos.

Se confirmó y corrigió un defecto previo: al existir una ficha cerrada y otra
viva, el reingreso se anotaba en la cerrada. Ahora la búsqueda de repetición y
la anotación usan la ficha viva. Una nota anterior mal ubicada no se mueve:
un reenvío puede dejar la nota correcta en la ficha viva, sin crear otro lead.

La campaña no se edita manualmente. Se mantienen los permisos efectivos de
todas las columnas anteriores, pasando UPDATE de tabla a UPDATE por columnas.
Las columnas futuras requieren su permiso explícito. Se mantiene lectura bajo
el ámbito actual de cada rol y capacidad de mantenimiento del servidor.

## Evidencia y revisión

- PASS: 36 comprobaciones de importación y 18 de permisos, tanto en local como
  en remoto; regresión de ficha viva también aprobada.
- PASS: 40 pruebas unitarias Edge, manejador HTTP con 4 pasos, deno check,
  check:scripts y check completo de aplicación. Sin cambio visual en esta fase.
- Las huellas de 8 conjuntos históricos coinciden, incluidos 3.677 leads.
  Ninguna campaña se asignó retroactivamente. Advisors sin alertas nuevas.
- Claude revisó la implementación como SECONDARY_REVIEWER: CHANGES_REQUESTED,
  confianza MEDIUM, sin P0/P1 demostrados. Codex incorporó las mejoras
  justificadas y verificó los cambios. No se pidió otro dictamen para obtener PASS.
- Se retiró la rama temporal autorizada `sdgqkuejylkeqabpplyk` a las 21:35:41 UTC,
  sin merge a producción. Sus 12 cron estuvieron desactivados durante el ensayo.
  Una primera rama sin datos había fallado al reconstruir el historial anterior;
  también se retiró. Otras ramas conservadas.

Código y evidencia: `CRM-Avance-Corp/supabase/scripts/formulario3-fase1/LEEME.md`
y `verificacion.json`. SQL local `20261014210146_crm_formulario3_campania_origen.sql`;
versión de ensayo remoto `20261014213157`. No repetir ambas al publicar.
Tipos generados desde el banco e integrados sin sobrescribir cambios ajenos.

[Tablero Figma actualizado](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=2-34):
fase 1 validada sin publicar, fase 2 siguiente, fases 3–6 pendientes.
Captura revisada sin recortes ni solapamientos.

## Continuación

Fase 2: etiqueta en listado/ficha y filtro con paginación y totales coherentes.
Las pruebas integradas Auth/HTTP y E2E visual siguen pendientes para fases 2–3.
Publicar en fase 4 mediante el procedimiento vigente: SQL, comprobación de
capacidad/huellas, Edge y frontend. Mantener n8n apagado hasta validar lo publicado
y probar una fila real. No se importó ninguna fila real en la fase 1.
