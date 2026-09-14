---
tags: [crm, multiempresa, f8, piloto]
fecha: 2026-09-14
estado: piloto-activo-g7-abierto
---

# F8 — piloto nominal activado

El solicitante aprobó expresamente el SQL nominal y la ventana de siete días.
Se ejecutó una vez la referencia `F8-20260914-01`, sin modificar el SQL aprobado.
Encendido: **14/09/2026 13:23:51 Lima**. Caducidad del acceso:
**21/09/2026 13:23:51 Lima**. Puede cerrarse antes; no exige esperar siete días.

Producción: control ON, revisión 1 y exactamente cuatro miembros vigentes:
Gerencia, supervisor y dos analistas. Identidades y aprobación con SHA256 en el
registro privado, fuera de Git. Cada uno conserva sus permisos y equipo.

PASS: SQL/huella aprobados, preflight previo, relectura posterior, capacidades
F5/F6 y escritura para los cuatro mediante rol SQL authenticated, usuario ajeno
excluido, supervisor limitado a su equipo, cinco auditorías sin simular sesión
humana. RLS/ACL conservados; F3 ON y las cuatro banderas globales OFF.
Las ocho huellas de contratos, cierres, inversiones, personas, titulares,
periodos, Auth y equipo coinciden antes/después del encendido. Corte:
602 fuentes reales (579 Avance, 17 Qorilazo, 6 Prodelco), cero brechas.

Las capacidades se comprobaron por SQL con UID local y ROLLBACK; no se afirma
login real de esas cuatro personas. La primera consulta de F6 bajo READ ONLY
rechazó su SELECT FOR SHARE; se corrigió el modo de la comprobación, sin tocar
código. La repetición permitiendo los locks y terminando en ROLLBACK pasó.
No hubo escrituras económicas de prueba ni reversa productiva.

## Primer recorrido real y condición reafirmada

El solicitante completó el primer caso desde el analista seleccionado que
pertenece al supervisor piloto. Resultado en
[[F8 - primer caso real verificado (2026-09-14)]]: identidad y PEN 9,000
conciliados; lista/ficha de supervisor/Gerencia con timeout, UI/Auth/HTTP pendientes
y observaciones humanas aún por recibir. Un solo caso no cierra G7 ni prueba
por sí solo otros roles/empresas.

**Datos y totales deben obtenerse de los núcleos canónicos del sistema.**
Verificar la ruta de escritura y cada consumidor; no añadir consultas o cálculos
paralelos que produzcan cifras distintas. Esta es una condición explícita del
solicitante del 14/09, no solo una recomendación técnica.

G7 sigue abierto: completar evidencia real, conciliaciones y conformidades del
piloto. La aprobación del encendido no equivale a aceptación de resultados ni
habilita todavía F9. Comisiones continúan fuera del sistema.

Acta: `CRM-Avance-Corp/supabase/scripts/multiempresa-f8/ACTIVACION-2026-09-14.md`.
Antecedente: [[F8 - equipo elegido y activacion preparada (2026-09-14)]].
Plan: [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
