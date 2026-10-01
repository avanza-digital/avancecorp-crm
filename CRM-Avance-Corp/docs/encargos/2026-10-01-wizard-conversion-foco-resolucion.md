# Wizard de conversión que se cerraba al volver a la ventana — resolución de las revisiones (01/10/2026)

Cambio de nivel 2 (solo pantalla). Dos rondas de Codex (`-r1`, `-r2` en esta carpeta) y una del
subagente `revisor-a11y`. Los diffs transcritos en los encargos son los de CADA ronda, no el final:
lo que quedó es lo que dice este archivo y el commit.

## Codex r1 — CHANGES_REQUESTED

| Hallazgo | Decisión |
|---|---|
| P2 · cerrar durante la carga/error no borraba la marca | Aceptado: el envoltorio la limpia en su cierre. |
| Hipótesis · reutilización entre cuentas o leads | La frontera existía (`<Ficha key={l.id}>`); se hizo explícita con `key` en `DialogConvertir`. |
| Hipótesis · retoma tras perder `puede_contratar` | Aceptado: la reapertura exige `puedeConvertir`. El servidor ya lo exigía (`private.puede_gestionar_contratos_crm()`). |
| Hueco · cancelar → iniciar otra → recargar | Aceptado: la marca ya no guarda la solicitud, solo la persona. |

## revisor-a11y — CHANGES_REQUESTED

| Hallazgo | Decisión |
|---|---|
| P2 · tras el relevo carga → formulario, cancelar dejaba el foco en `body` | Aceptado en el camino habitual: el formulario abre con la copia de la ficha y es el primer diálogo (conserva su origen). |
| P2 (parte previa) · al cerrar el wizard el foco cae en `body` | **NO resuelto.** Se probó un respaldo en `ui/dialog.tsx` (enfocar la capa abierta de debajo); pasaba en jsdom, pero en Chromium real el foco siguió en `body` al cerrar el wizard reabierto. Se retiró: `dialog.tsx` queda idéntico a producción. Es el comportamiento que ya tenía producción; queda como pendiente aparte. |
| P3 · la reapertura sola podía pillar a la persona escribiendo | Aceptado: al primer clic o tecla deja de abrirse sola; el botón la retoma. |
| P3 · diálogo de carga mudo para lector de pantalla | Aceptado: `role="status"` oculto y `role="alert"` en el error. |
| Prueba vacía en el e2e (nombre accesible equivocado) | Aceptado: busca «Registrar la inversión del lead» y «Documento del lead». |

## Codex r2 — CHANGES_REQUESTED

| Hallazgo | Decisión |
|---|---|
| P2 · una respuesta tardía del documento podía descartar una identidad en curso | Aceptado: «Continuar» queda apagado hasta fijar el documento. |
| Hipótesis · el respaldo de foco actuaba también con origen real | Sin objeto: el respaldo se retiró entero (ver arriba). |

## Verificación del código final

- `npm run check`: PASS, 330 archivos, 5.184 pruebas, build y bundle.
- 15 mutantes de las defensas nuevas: 15 cazados (los 2 del respaldo de foco dejaron de aplicar al retirarlo).
- E2E Docker del flujo (conversión, ficha, cartera, clientes, postventa): 40 pasan, 13 omitidas, 0 fallan.
- E2E completa (325) con el mismo código de aplicación: solo fallan `gerencia-operativa.spec.ts:108` y
  `gestion-diaria-vuelta.spec.ts:11`, que fallan igual sobre la base sin este cambio (acreditado).
- Gate de realidad: NOT RUN (pide la llave de servicio de producción).
