---
tags: [crm, pruebas, recordatorios]
fecha: 2026-09-10
---

# Pruebas de recordatorios: fecha fija

El primer intento de push de `d969381` se detuvo en el hook: 3.160 pruebas
pasaron y tres de `lead-nuevo.test.tsx` fallaron al llegar el 10/09/2026.
El fixture de enfriamiento se liberaba ese día, pero los casos dependían del
reloj real y esperaban que aún fuera una fecha futura.

El bloque «Recordarme revisar (F3)» ahora parte del 18/08/2026 a las 17:00 UTC.
Sus helpers conservan esa fecha al alternar los temporizadores simulados y
reales que necesita `waitFor`. `vi.useRealTimers()` también restaura Date;
por eso se vuelve a fijar la fecha después. El afterEach general libera el reloj.

Se conservaron las aserciones de fecha, autoría, guardado, foco y respuesta
tardía. PASS: las 69 pruebas del formulario. El gate de envío completo es
`npm run test:run`; el cambio está limitado a pruebas y esta nota.

Relacionado: [[Inicio]], [[Main unico - sincronizacion y publicacion 2026-09-04]].
