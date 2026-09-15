---
tags: [crm, cartera, rendimiento, pendiente]
actualizado: 2026-09-15
---

# Ficha rápida — preparada localmente

Objetivo activo: bajar la consulta de la ficha de Gerencia de aproximadamente
2,7 segundos a menos de un segundo, conservando diseño, datos de los núcleos
y permisos. Antecedente: [[Rendimiento ligero - medicion de Cartera y Hoy (2026-09-15)]].

**No instalada ni publicada. La meta productiva sigue pendiente.**
No se creó ningún banco remoto nuevo ni se generó coste remoto en este trabajo.

Se preparó `20260915170237_crm_ficha_lectura_individual.sql`: un único núcleo F5
con sobrecarga privada UUID/NULL. La firma de listado existente delega al mismo
núcleo. La ficha consulta una persona, conserva las dos validaciones de acceso,
el filtro canónico externo y todos sus datos/capacidades. Sin nuevo cálculo
financiero, cambio de frontend, banderas productivas, fuentes ni objetos public.

PASS local: 640 fichas completas, 328 salidas del núcleo, 10 aliases,
demos/mixtos, bandeja del supervisor, perfil provisional, inactivos, NULL e id
inexistente. Ocho huellas conservadas, 15 controles de seguridad/reversa y
12 lecturas en seis oleadas reales de 1/2/3 sesiones con datos/capacidades iguales.
El banco de volumen tiene 490 personas, 475 perfiles, 1.750 leads y 587 fuentes
Avance. No reproduce toda la penalización del plan elegido en producción.

Diagnóstico READ ONLY del SQL vigente: unas 12.278 iteraciones del lateral
consumen aproximadamente 921 ms; las fuentes, 73 ms, sobre 1.055 ms del núcleo.
Esto sustenta el recorte temprano de personas; no prueba aún la velocidad del
cambio instalado. Datos y contexto completos en `supabase/scripts/ficha-rendimiento/`.

Claude: primer intento inválido; segundo CHANGES_REQUESTED, sin P0/P1.
Codex documentó NULL, agregó poscondiciones de MD5/configuración/owner/ACL,
conservó el núcleo único y repitió verificaciones. El requisito de medir en
Supabase antes de cerrar sigue vigente. No declarar PASS del revisor.

Siguiente paso: confirmar el SQL exacto y un banco temporal nuevo de
PortalAvanceCorp (tarifa consultada US$0,01344/h; presupuesto propuesto US$1).
Probar migración, Auth/HTTP, RLS pertinente, advisors, tipos, replay y rendimiento;
preflight de esquema/historial/Edge, merge autorizado, medición real y eliminación
solo del banco propio. `banco-f7` es ajeno y no se toca.

La copia propia local es `ficha_rapida_20260915` en
`supabase_db_avancecorp-f5-bank`; el origen `multiempresa_f8_ajustes_20260914`
permanece intacto. Los scripts restablecen las definiciones y banderas.
Ante una interrupción externa, verificar restauración antes de reutilizarla.

[[F8 - ficha anterior recuperada para multiempresa (2026-09-15)]],
[[F8 - piloto nominal activado (2026-09-14)]] y
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]]
mantienen su estado anterior; esta mejora no cierra G7.

## Resultado posterior

Autorización, ensayo remoto y publicación completados. Estado vigente en [[Ficha rapida - publicada y verificada (2026-09-15)]]: Gerencia 723,414 ms, mismos datos y permisos; banco eliminado. Esta nota conserva la preparación local histórica.
