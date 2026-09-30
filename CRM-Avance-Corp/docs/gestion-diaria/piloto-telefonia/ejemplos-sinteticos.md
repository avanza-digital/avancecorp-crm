# Ejemplos sintéticos de teléfonos — F0.4.2

Entregable de **F0.4.2**: casos sintéticos de teléfonos compartidos, históricos, reciclados y contexto contradictorio, para probar en F1 (match exacto) y F5 (Jev) sin datos reales. **Todos los números son inventados**; nunca se marcan ni se cargan como leads reales. Los leads se llaman L1, L2… y sus datos son ficticios.

Cómo se guarda un teléfono hoy en el CRM (verificado el 29/09 en las migraciones): el principal, `crm.leads.telefono`, lo normaliza el trigger con `private.normalizar_telefono` (9 dígitos → `+51` + dígitos; cualquier otra cosa → `+` + dígitos); el alternativo, `telefono_alternativo`, lo canoniza `private.canonizar_contacto` (celular `+519…`, fijo con marca `+51` + 8 dígitos, internacional E.164). Por eso un mismo fijo puede estar guardado de dos formas.

Resultado esperado según el contrato 4.1 del plan: `unico`, `ambiguo`, `sin_coincidencia`, `incompleto` o `error`. Nada se autoselecciona salvo `unico`.

## A. Coincidencia exacta (lo normal)

| # | Número capturado por el celular | Leads sintéticos y cómo están guardados | Resultado esperado | Por qué |
| --- | --- | --- | --- | --- |
| A1 | `+51900000001` | L1 `telefono = +51900000001` | `unico` → L1 | Canónico idéntico |
| A2 | `900000001` (sin código de país) | L1 `telefono = +51900000001` | `unico` → L1 | La canonización añade `+51` a 9 dígitos |
| A3 | `+51 900 000 001` (con espacios) | L1 | `unico` → L1 | Solo dígitos cuentan |
| A4 | `+51900000002` | L2 `telefono_alternativo = +51900000002`, `telefono = +51900000003` | `unico` → L2 | El alternativo también identifica |

## B. Históricos (dos formas guardadas)

| # | Número capturado | Leads y forma guardada | Resultado esperado | Por qué |
| --- | --- | --- | --- | --- |
| B1 | `014457890` (fijo de Lima con 0) | L3 `telefono = +51014457890` (forma legado: 9 dígitos → `+51`) | `unico` → L3 | El match debe canonizar también con la regla legado |
| B2 | `+5114457890` (mismo fijo en E.164) | L3 `telefono = +51014457890` | `unico` → L3 | Las dos formas son el mismo fijo; comparar cada forma contra su columna |
| B3 | `014457890` | L4 `telefono_alternativo = +5114457890` | `unico` → L4 | El alternativo está en forma nueva |
| B4 | `084234567` (fijo de Cusco con 0) | L5 `telefono = +51084234567` | `unico` → L5 | Igual que B1, otra provincia |

## C. Compartidos y reciclados

| # | Número capturado | Leads y forma guardada | Resultado esperado | Por qué |
| --- | --- | --- | --- | --- |
| C1 | `+51900000010` | L6 `telefono = +51900000010` y L7 `telefono_alternativo = +51900000010` (pareja que comparte celular) | `ambiguo` (L6, L7) | Dos leads distintos; decide la persona (o Jev propone, persona confirma) |
| C2 | `+51900000011` | L8 `telefono = +51900000011` (activo) y L9 `telefono = +51900000011` (descartado hace un año, etapa terminal) | `unico` → L8 con aviso «número reciclado» | Solo cuentan leads vivos; el descartado se muestra como contexto, no como candidato |
| C3 | `+51900000012` | L10 `telefono = +51900000012` y L10 `telefono_alternativo = +51900000012` (mismo lead en dos campos) | `unico` → L10 | Contar leads distintos, no campos |
| C4 | `+51900000013` | L11 y L12 con el mismo número, ambos convertidos (clientes) | `sin_coincidencia` en leads + aviso «existe como cliente» | Los clientes con contrato requieren la ampliación aparte (plan, sección 2) |

## D. Contexto contradictorio (para F5)

| # | Número capturado | Contexto | Resultado esperado | Por qué |
| --- | --- | --- | --- | --- |
| D1 | `+51900000020` | El analista llamó desde la ficha de L13 (`telefono = +51900000021`) pero cambió el número en el marcador | `sin_coincidencia` + mostrar «intención: L13, número distinto» | Conservar lead y número intentados; no adjudicar por la intención sola |
| D2 | `+51900000022` | Nota de L14 dice «llamar al 900000022 (hermano)»; L14 `telefono = +51900000023` | `sin_coincidencia`; Jev puede proponer L14 con el hecho «figura en una nota» | Código extrae y canoniza el fragmento; nunca genera dígitos; confirma la persona |
| D3 | `+51900000031` | L15 `telefono = +51900000030` (un dígito de diferencia) | `sin_coincidencia` | Un dígito distinto es otro número; no «corregir» por parecido |
| D4 | `+51900000040` | L16 `telefono = +51900000040`; asociación confirmada hace 8 meses a L17 (número reciclado) | `unico` → L16 con aviso «hubo asociación previa a L17, vencida» | El historial confirmado caduca y se revalida |

## E. Internacionales, ocultos e inválidos

| # | Número capturado | Leads y forma guardada | Resultado esperado | Por qué |
| --- | --- | --- | --- | --- |
| E1 | `+34987654321` | L18 `telefono = +51987654321` | `sin_coincidencia` | Mismo sufijo, distinto país: nunca recortar nueve dígitos |
| E2 | `+34987654321` | L19 `telefono_alternativo = +34987654321` | `unico` → L19 | E.164 completo coincide |
| E3 | `` (vacío) o «Número privado» | — | `sin_coincidencia` clasificado como **oculto** | Número legítimamente oculto; no es error |
| E4 | `12345678` (8 dígitos pelados, parece DNI) | L20 `dni = 12345678` | `sin_coincidencia` (inválido como teléfono) | Ocho dígitos sin marca de fijo no son teléfono (regla de `canonizar_contacto`) |
| E5 | `+51123456789` | — | `sin_coincidencia` (inválido) | Dice ser peruano y no tiene forma de celular ni de fijo |

## F. Completitud de la búsqueda

| # | Número capturado | Leads y forma guardada | Resultado esperado | Por qué |
| --- | --- | --- | --- | --- |
| F1 | `+51900000050` | 9 leads distintos cuyo `telefono` contiene `900000050` como subcadena (p. ej. `+51900000050`, `+51190000005001`…) y solo uno exacto | `unico` → el exacto, **solo si** la recuperación fue completa; si la página de 8 no alcanzó, `incompleto` | Una página de ocho resultados no demuestra unicidad (plan, sección 3) |
| F2 | `+51900000060` | Fallo de red o `42501` al consultar | `error` | Error operativo separado de «sin coincidencia» |

## Cómo usar estos casos

- F1.3.1 y F1.3.2: casos A, B, C, E y F como tests unitarios del match (cliente y servidor con reglas compatibles).
- F2.4.1: C1–C4 y D4 para el modelo de asociación y el historial.
- F5.1.1: D1–D4 como semilla del banco; después se añaden casos etiquetados y autorizados, separando ajuste de evaluación.
- Antes de usar datos reales, sustituir estos casos por una muestra anonimizada de la base con las dos formas guardadas (propuesta de ajuste #2, pendiente de Miguel).
