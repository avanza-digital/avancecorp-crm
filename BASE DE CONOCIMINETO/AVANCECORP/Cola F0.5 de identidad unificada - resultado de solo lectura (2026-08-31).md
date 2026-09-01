---
tags: [crm, inversionistas, identidad, excepciones, f0-5, produccion]
fecha: 2026-08-31
observado_en_lima: 2026-08-31 17:36:31
estado: cola-preparada-con-deriva-explicada-pendiente-de-decisiones-comerciales
---

# Cola F0.5 de identidad unificada — resultado de solo lectura

## Objetivo comercial

Convertir las excepciones del [[Censo F0 de identidad unificada - resultado de solo lectura (2026-08-31)]] en una cola accionable para decidir qué inversionistas pueden entrar a la ficha única, cuáles necesitan corrección o responsable y cuáles deben quedar en cuarentena, sin modificar datos.

## Ejecución y seguridad

- Base linked observada a las 17:36:31, hora de Lima.
- `transaction_read_only = on` y `ROLLBACK` final.
- 131 salvaguardas estáticas aprobadas.
- Revisión adversarial de Codex; se corrigió el hash directo de documento y ahora los grupos seudónimos se derivan solo de UUID técnicos aleatorios.
- Ningún nombre, documento, teléfono, correo o UUID crudo aparece en la salida.
- Resultado privado: `artifacts/cola-f05-identidad-inversionistas-2026-08-31.json`.

## Resultado ejecutivo actual

- La lectura posterior a las decisiones encontró **405 candidatas técnicas A/B**. Al retirar una identidad A de prueba y la identidad B del demo Qorilazo quedan **403 clientes reales en alcance**. De ellos, **402 son seguros para backfill automático** y **Katherine permanece como caso real de vinculación manual pendiente de confirmar documento**. El número definitivo requiere recenso inmediatamente antes del corte.
- **22 filas de casos individuales**, agrupadas en **16 grupos de persona**; las filas se solapan cuando una misma persona tiene más de una excepción.
- **2 señales débiles agregadas** —teléfono y nombre—, solo informativas y sin casos individualizados.
- El gate contra la foto histórica de las 16:10 quedó en `DETENER_Y_EXPLICAR_DERIVA`. No es un fallo de escritura: la base es viva y además se corrigió el criterio de capital para considerar resolubles solo las clases A/B.

## Cola por categoría

| Categoría | Casos | Resultado comercial |
|---|---:|---|
| Perfil sin documento | 1 | `SANCHEZ KIRK` fue confirmado como prueba; se excluye del universo real. |
| Documento inválido | 1 | `PRUEBA CLEINTE` fue confirmado como prueba; se excluye del universo real. |
| Cliente también en otro rol | 2 | El caso analista–inversionista es legítimo; el caso superadmin corresponde a un placeholder compartido y no se fusiona. |
| Identidad sin responsable | 5 | El responsable puede quedar nulo y Gerencia lo asignará después; el demo Qorilazo se excluye. |
| `no_contactar` sin identidad fuerte | 4 | La ausencia documental es normal en leads; mantener el veto en cada lead sin bloquear F1. |
| Discrepancia documental convertida | 1 | Katherine es cliente real y se conserva íntegramente. Permanece en alcance como vinculación manual; no se elige automáticamente entre los dos DNI hasta confirmarlo antes del contrato. |
| Conversión sin identidad A/B | 3 | Dos cierres Avance y una operación de cartera de agosto; conservan su aporte actual hasta resolver persona. |
| Capital sin identidad A/B | 4 | Cuatro episodios Avance que no pueden hacerse obligatorios todavía. |
| Demo por confirmar | 1 | Cierre Qorilazo S/100,000, actualmente anulado; no infla capital vigente. |

## Capital pendiente de identidad

Los cuatro episodios Avance pendientes son:

- US$7,500;
- US$10,000;
- US$4,000;
- S/100,000.

No se mezclan monedas. Dos episodios USD pertenecen al mismo grupo que el perfil con documento inválido. Otros dos episodios y una conversión se solapan con uno de los casos cliente–otro rol.

## Solapamientos que reducen trabajo manual

La cola contiene 22 filas, pero no son 22 personas. Hay 16 grupos:

1. un caso cliente–otro rol agrupa además dos episodios de capital y una conversión;
2. el candidato demo comparte grupo con una identidad B sin responsable porque su único cierre está anulado;
3. el perfil con documento inválido agrupa dos episodios de capital.

Resolver esos grupos cerrará varias excepciones a la vez.

## Deriva frente a la foto F0 histórica

Entre las 16:10 y las 17:37 se observaron cambios reales del CRM:

- perfiles cliente: 396 → 397;
- documentos válidos: 394 → 395;
- identidades A: 392 → 393;
- operaciones de cartera: 71 → 73;
- operaciones elegibles para conversión: 47 → 48;
- leads vivos: 636 → 628 y descartados: 170 → 178.

También se corrigió una limitación del primer censo: capital resoluble significa identidad clase A/B, no simplemente documento con formato válido. Con el criterio contractual correcto ahora se observan 4 episodios sin identidad, no 2.

La conversión ponderada actual es 58.9 antes y después de la regla por identidad; el delta continúa en **0**. Hay 3 episodios no resolubles que se excluyen prudentemente de la deduplicación.

## Corrección del caso DEMO

El candidato de S/100,000 está anulado y aporta S/0 al capital vigente. Por tanto, el stock vigente observado es:

- Qorilazo: S/305,800;
- Prodelco: S/10,000;
- total cooperativas vigente: S/315,800.

La deuda comercial es rotular el episodio como demo para que no se confunda en el historial, no restarlo del stock vigente. Se agregó una errata fechada al informe F0.

## Decisiones comerciales necesarias

### Decisiones confirmadas por Miguel

- **D-F05-01 — Analistas inversionistas:** un analista también puede invertir. Cuando el documento fuerte confirma que es la misma persona, se conserva una sola identidad neutral; el rol de analista, sus permisos y su acceso permanecen separados de su condición de inversionista. Miguel confirmó que `AGUIRRE VEGA ROSA ESTEFANY` y `ROSA AGUIRRE` son la misma persona.
- **D-F05-02 — Cuenta administrativa:** `ADMINISTRADOR AVANCE CORP.` es la cuenta de Miguel y debe permanecer intacta. El DNI compartido con `PEREZ CARMEN` se trata como placeholder y no autoriza unir ambas fichas.
- **D-F05-03 — Registros de prueba:** `SANCHEZ KIRK` y `PRUEBA CLEINTE` son registros de prueba. Se excluyen del futuro backfill automático, cartera real y métricas reales. Su eventual desactivación o eliminación requiere una operación auditada y una autorización de escritura separada.
- **D-F05-04 — Otros perfiles de prueba:** `-CARMEN-CLIENTE PRUEBA-CARMEN` y `PEREZ CARMEN` también son prueba. El primero tiene un contrato marcado demo; el segundo no tiene contratos. Ambos quedan excluidos de identidad, cartera y métricas reales.
- **D-F05-05 — Responsable diferido:** una identidad válida puede migrarse sin responsable. Gerencia determinará la asignación posteriormente; no se inventa ni hereda un asesor para superar el backfill.
- **D-F05-06 — Documentos en leads:** la ausencia de documento es normal durante la etapa de lead y no constituye por sí sola una excepción ni una cuarentena. El lead continúa operando; no nace una identidad documental automática hasta que exista una fuente fuerte. `no_contactar` permanece en el lead mientras no haya identidad fuerte.
- **D-F05-07 — Qorilazo de desarrollo:** el cierre Qorilazo de S/100,000 es una prueba de desarrollo sin valor comercial. Está anulado y no aporta capital vigente. Tiene un depósito reclamado relacionado, por lo que no puede eliminarse aisladamente; queda excluido de métricas reales y cualquier limpieza física futura debe tratar ambos registros en una transacción auditada.
- **D-F05-08 — Katherine, cliente real:** Miguel confirmó que Katherine es una cliente real, todavía sin contrato cargado, y que no conoce ahora su DNI correcto. Se conservan su lead convertido, seis actividades, una tarea, una asignación, su perfil y su cuenta bancaria. Está incluida en el alcance de identidad unificada como caso manual pendiente de documento; ninguno de los dos DNI en conflicto se toma automáticamente como verdad. Al preparar el contrato se verifica el documento y se vincula la misma persona, sin recrear ni perder historial.
- **D-F05-09 — Un solo lead por persona:** Miguel confirmó que una persona solo puede tener un lead total, sin importar si está vivo, convertido o descartado. Toda gestión posterior reutiliza ese mismo lead y conserva su historial. Las múltiples inversiones se representan mediante contratos, cierres externos y operaciones de cartera, nunca mediante leads adicionales.

1. Definir una limpieza auditada de los registros de prueba y sus dependencias; dos contratos de `PRUEBA CLEINTE` todavía no están marcados como demo.
2. Confirmar el documento de Katherine antes de cargar su contrato y resolver entonces su identificador fuerte, conservando todo el historial actual.
3. Recensar inmediatamente antes de cualquier corte para incorporar la actividad viva del CRM.

Los leads sin documento no quedan en cuarentena por ese solo hecho. Los cuatro vetos permanecen en sus leads y no necesitan una fusión; los casos sin identidad fuerte no bloquean el diseño de F1 si quedan fuera del backfill automático.

## Gate comercial para preparar F1

Se puede preparar —no ejecutar— F1 cuando Miguel apruebe:

- migrar automáticamente las candidatas reales seguras —402 estimadas en la lectura posterior—, sujeto a recenso y exclusiones explícitas justo antes del corte;
- excluir de backfill automático los grupos E y documentales pendientes;
- mantener `no_contactar` en sus leads hasta identidad fuerte;
- excluir del universo real los registros y episodios de prueba confirmados;
- permitir responsable nulo y asignación posterior por Gerencia;
- mantener a Katherine en alcance como vinculación manual pendiente de documento, preservando toda su trazabilidad.

Cualquier SQL de migración requerirá una autorización nueva y separada.

## Relacionadas

- [[Contrato arquitectonico consolidado - identidad unificada de inversionistas (F0 2026-08-31)]]
- [[Censo F0 de identidad unificada - resultado de solo lectura (2026-08-31)]]
- [[Identidad unificada de inversionistas - plan pendiente]]
