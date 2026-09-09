---
tags: [crm, cartera, F5, retomar, revision-visual]
fecha: 2026-09-08
estado: candidata-con-ajuste-visual-sin-publicacion
---

# CARTERA — F5 adaptada al estilo del CRM

Miguel pidió continuar F5 después de indicar que le gustaban las capturas y
confirmar su expectativa de coherencia visual con el CRM. Se retomó la fase
implementada; se conserva la estructura presentada de cartera, ficha e inversión.

## Ajuste completado

- Ancho de cartera y componentes de estado vacío compartidos con el CRM.
- Paginación con los botones comunes, foco visible y controles que se acomodan
  al ancho móvil.
- Filtros y resumen por empresa/moneda adaptados al ancho real del panel.
- Espacios del formulario, tono de errores y botones largos uniformados;
  nombres largos de comprobantes legibles sin desborde.

Se conservan las operaciones, permisos, capital, monedas, fuentes y documentos
ya probados. Las comisiones continúan calculándose fuera del sistema.

## Evidencia y guardado

`npm run check:all`: PASS, con 3.127 pruebas unitarias en 221 archivos y
147 recorridos de navegador; 26 omisiones preexistentes. Se revisaron además
13 capturas a 320, 390, 768 y 1.440 px, incluyendo recuperación, lista vacía y
errores. Este recorrido complementa los siete casos F5 del gate completo.

Acta y capturas actualizadas:
`CRM-Avance-Corp/supabase/scripts/f5/ACABADO-VISUAL.md`.
Código del ajuste guardado en `37ba1fa`; actas y capturas en un commit posterior.
Los commits y el manifiesto del paquete identifican la versión candidata
vigente. El respaldo privado de este ajuste se guarda junto a los anteriores
en `RESPALDOS-CARTERA/`; no reemplaza ni elimina el cierre anterior.

Se mantienen intactos los 229 archivos pendientes de otras tareas en la
carpeta principal. El trabajo de F5 utiliza su carpeta aislada existente,
`/private/tmp/avancecorp-f5-desarrollo`.

## Estado para continuar

F4 permanece publicada; F5 está desarrollada, probada y ajustada visualmente.
No se instaló SQL F5, no se publicó la nueva interfaz ni se activaron nuevas
operaciones en producción durante este ajuste. El 09/09 Miguel realizó el
recorrido básico de teclado y confirmó la lectura de cartera/ficha con
VoiceOver. Después confirmó que funciona la lectura de los campos de Nueva
inversión en Qorilazo; queda aprobado el recorrido manual guiado.
Detalle: [[F5 - prueba manual de VoiceOver iniciada (2026-09-09)]].
El preflight del 09/09 identificó el destino y confirmó F4 instalada/F5 apagada.
También se corrigió un salto de la cartera anterior causado por la comprobación
F5 ya incluida en la entrega compartida de Citas. Miguel autorizó publicar ese
arreglo. Continuación vigente y detalle de los 15 huecos de identidad:
[[F5 - prepublicacion y salto de cartera (2026-09-09)]].
La activación económica conserva F6, F7/G6, F8/G7 y F9/G8; no adelantar el piloto real.

Relacionados: [[F5 - revision visual e integracion con el CRM (2026-09-08)]],
[[RETOMAR-67 - F5 implementada y candidata preparada (2026-09-08)]],
[[Plan de implementacion F5 - cartera y ficha multiempresa (2026-09-08)]],
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
