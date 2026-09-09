---
tags: [crm, cartera, F5, publicacion, regresion]
fecha: 2026-09-09
estado: salto-publicado-banco-f5-ensayado
---

# F5 — prepublicación y salto de cartera

Actualización: Miguel confirmó el SQL original y el banco remoto. El ensayo
terminó con 44 pruebas locales y 15 remotas aprobadas y dos correcciones
adicionales. Estado vigente: [[F5 - banco remoto y correcciones de instalacion (2026-09-09)]].
El relato siguiente conserva el momento anterior a esa confirmación.

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
El arreglo se publicó y comprobó en `crm.miavance.com` a las 11:09 Lima del
09/09: release `crm-20260909T160038Z-baad8cfad3e8`, desde el commit `baad8cf`
verificado contra Main y `avancecorp/main`. Los 79 archivos públicos responden
HTTP 200; la configuración del servidor también fue cotejada. El ZIP y su
reversa están guardados en `RESPALDOS-CARTERA/f5-publicacion-salto-20260909-1602/`.

Pendiente inmediato: confirmar el SQL exacto y el banco Supabase temporal
(cómputo cotizado desde US$0,01344/h, más uso adicional). El paquete F5 queda
actualizado y verificado; no se instaló SQL, no se creó la rama de prueba ni
se publicó la función documental. Mantener F5 y la escritura apagadas y
conciliar los 15 huecos antes de cualquier encendido. No adelantar el piloto.

Relacionados: [[RETOMAR-68 - F5 adaptacion visual verificada (2026-09-08)]],
[[F5 - prueba manual de VoiceOver iniciada (2026-09-09)]],
[[Plan de implementacion F5 - cartera y ficha multiempresa (2026-09-08)]],
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
