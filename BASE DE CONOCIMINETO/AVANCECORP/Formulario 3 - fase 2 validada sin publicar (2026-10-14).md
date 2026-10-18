# Formulario 3 - fase 2 validada sin publicar

Fecha: 2026-10-14. Codex PRIMARY; Claude SECONDARY_REVIEWER. **Implementada y validada localmente; sin publicar.** Sigue la fase 3 del [[Formulario 3 - plan de integración en CRM y activación (2026-10-14)]]. Depende de [[Formulario 3 - fase 1 validada sin publicar (2026-10-14)]].

## Resultado preparado

Etiqueta informativa Formulario 3 en listado, ficha, vista previa y Pipeline. El canal sigue siendo FORMULARIO, con las reglas vigentes de reparto y conversión. Filtro Campaña → Todas / Formulario 3, combinado con los demás filtros, aplicado en servidor antes de paginar y calcular cantidades, capital y embudo. Se conserva la selección al recargar por pestaña, cuenta y modo real/demo.

Registros históricos sin campaña siguen sin etiqueta; una nota o reingreso de esta campaña no cambia el origen del contacto. Cada rol conserva su ámbito; la campaña no se edita manualmente.

## Evidencia de cierre local

- `app/npm run check`: PASS, 420 archivos y 6.700 pruebas, tipos, lint, compilación y bundle; 11 warnings previos ajenos.
- Scripts: PASS. E2E Docker: 9/9 PASS sin reintentos en la pasada final.
- Matriz SQL: 43 comprobaciones PASS con roles reales y ROLLBACK, en el clon local exclusivo `formulario3_fase2_20261014_review`.
- Después de Claude: 262 pruebas enfocadas y typecheck PASS. Advisors del clon final sin nuevas alertas de seguridad, WARN ni ERROR; diferencias INFO de uso de índices entre clones.
- Una revisión Claude (`CHANGES_REQUESTED`): se corrigió pérdida de comentarios al recrear las funciones y se añadieron guardas de dependencias y pruebas. Las dudas de payloads humanos y contraste se resolvieron con código y evidencia. No se pidió un segundo dictamen favorable.

Migración nueva: `20261014215453_crm_formulario3_cartera.sql`. Evidencia: `CRM-Avance-Corp/supabase/scripts/formulario3-fase2/LEEME.md`, `verificacion.json`, `revision-resolucion.md`, logs y capturas. Mantiene el wrapper y los permisos; la firma nueva es única y su parámetro opcional.

## Límites y siguiente paso

El gate general de realidad quedó NOT RUN por variables de credencial ausentes. La inspección SQL específica confirmó que producción todavía no tiene la columna y que la cartera sigue igual. Auth/HTTP contra la base y ensayo remoto de esta migración final corresponden a fase 3; E2E con HTTP simulado más SQL con RLS real no equivalen a ese recorrido integrado.

No se creó otra rama remota de pago. No se publicó, no se cargaron contactos ni se activó n8n. Última lectura del flujo `BjI5m1PKVWhO0NDb`: inactive, activeVersionId null, enviar_crm false, nodo Importar en CRM deshabilitado.

La publicación posterior exige fase 1 SQL → fase 2 SQL → comprobar capacidad → Edge → frontend. Reversión operativa: frontend anterior conservando el esquema aditivo. Publicar corresponde a fase 4 y al procedimiento de release vigente.

[Plan actualizado y verificado visualmente en Figma](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=2-34): fases 1 y 2 preparadas, fase 3 siguiente, fases 4–6 pendientes. Relacionado: [[n8n - Formulario 3 preparado y avisos conectados (2026-10-14)]] · [[Canales de origen de leads CRM]].
