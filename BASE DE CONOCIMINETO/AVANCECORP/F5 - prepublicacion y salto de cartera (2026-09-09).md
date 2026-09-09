---
tags: [crm, cartera, F5, publicacion, regresion]
fecha: 2026-09-09
estado: correccion-verificada-publicacion-en-preparacion
---

# F5 — prepublicación y salto de cartera

Miguel aprobó el recorrido guiado de VoiceOver y pidió seguir el plan. Reportó
un salto de pantalla en cartera y autorizó publicar su corrección.

El JavaScript ya publicado en la entrega compartida de Citas comprobaba F5
cada 15 segundos. Como su SQL aún no está instalado, esa comprobación
desmontaba la cartera anterior: se cerraba la ficha y se perdían filtros.
Se reprodujo y corrigió en `0eb66b7`, manteniendo apagadas F5 y la escritura.

Gate integral: PASS, 3.131 pruebas unitarias y 150 recorridos de navegador;
26 omisiones preexistentes. Claude revisó como SECONDARY_REVIEWER y dio PASS;
Codex incorporó el tipo explícito del estado y cuatro pruebas HTTP adicionales.
La corrección conserva los errores reales de permisos y servidor.

El destino está identificado y la reversa exacta de la web está respaldada.
F4 está instalada. F5 todavía no tiene SQL ni función documental publicados.
El censo detectó 15 fuentes sin identidad vinculada (13 Avance y 2 Qorilazo):
impiden encender F5 y requieren conciliación mediante lotes F4 revisados.
No impiden preparar e instalar F5 apagada, previa autorización de su SQL.
Las comisiones continúan fuera del sistema.

Acta técnica y SQL enlazado:
`CRM-Avance-Corp/supabase/scripts/f5/PREPUBLICACION-2026-09-09.md`.
Pendiente inmediato: publicar el ZIP del arreglo desde Main sincronizado,
verificar la web y preparar el paquete F5 actualizado. Después mostrar el
SQL para su confirmación; no adelantar el piloto económico.

Relacionados: [[RETOMAR-68 - F5 adaptacion visual verificada (2026-09-08)]],
[[F5 - prueba manual de VoiceOver iniciada (2026-09-09)]],
[[Plan de implementacion F5 - cartera y ficha multiempresa (2026-09-08)]],
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
