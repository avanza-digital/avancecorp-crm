# F4 cerrada — comisiones fuera del sistema

## Decisión explícita de Miguel — 08/09/2026

> «ok pero no quiero eso, como hacemos? las comisiones las calcula por fuera del sistema.»

Las comisiones se calculan, liquidan y pagan fuera del CRM. El sistema no debe
incorporar un calculador de comisiones, indicar cuánto pagar ni conciliar un
registro externo de pagos como requisito de F4. No se solicita importar ese
registro. Las referencias anteriores que lo dejaban pendiente quedan superadas
por esta decisión; no se modifica retrospectivamente el resultado de una prueba.

Se conservan Capital, conversión, atribución por inversión, identidad, documentos,
monedas y meses sellados. Estos datos siguen sus reglas publicadas; la comisión
externa no se convierte en una fuente de dinero ni un permiso dentro del CRM.
La misma exclusión funcional se mantiene para las fases siguientes.

## Cierre técnico F4 / G4

El paquete del commit `bcdfa0d` ya verificó los requisitos técnicos restantes:
3050 tests frontend, 43 PDF Deno, pruebas de permisos/finanzas/históricos,
recuperación Auth/PDF, reconstrucción y restauración pareada. La decisión elimina
el único requisito pendiente por estar fuera del alcance del producto.
**F4 terminada y G4 cerrado en alcance técnico sintético.** Sigue F5: cartera y
Ficha 360 multiempresa. Este cierre no publica, aplica SQL, habilita dinero real
ni enciende banderas productivas.

La candidata SQL conserva su SHA-256
`84f8b3b407812363ebe9705aaaab46b8620d48a79dc7d6d38cc285a18a293afe`.
No se modifican código de producto, migración, pruebas ni evidencias previas.
El encabezado SQL y el manifiesto anterior describen el instante previo a esta
decisión; se conserva su integridad. El acta nueva deja trazabilidad del cierre.
No se atribuye un PASS posterior a Claude ni una comprobación de pagos externos.

Verificación de este cambio documental: parseo JSON, enlaces locales, huellas del
paquete previo contra su commit y fuentes técnicas actuales, `git diff --check`.
El banco completo no se repite porque no cambió el comportamiento del sistema.

Fuentes: [matriz de aceptación](../../CRM-Avance-Corp/supabase/scripts/f4/ESTADO-ACEPTACION.md),
[acta de cierre](../../CRM-Avance-Corp/supabase/scripts/evidencia-f4/cierre-g4-comisiones-externas-2026-09-08.json).
Relacionadas: [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]],
[[F4 multiempresa - reconstruccion, finanzas y lectura vigente (2026-09-08)]].
