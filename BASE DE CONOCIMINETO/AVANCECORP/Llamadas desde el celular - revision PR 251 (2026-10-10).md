# Llamadas desde el celular - revision PR 251 (2026-10-10)

Relacionadas: [[Inicio]], [[Llamadas desde el celular - revision conjunta PR 232 y 249 (2026-10-10)]], [[Llamadas desde el celular - reparto con Jhosep y analisis H-P5 H-P10 (2026-10-09)]].

## Estado

PR#251: unión manual F4.2.4, ACTIVAR-C2 y borrador AVISO-TRATAMIENTO. Base82e5edde (#249 ya fusionado10/10 19:54UTC). Cabeza inicial59fb5faa; durante el review subió8e6aa9317b0aa2ede0f5e1f75f47d4efd5edc4c9, solo estado/AVANCE. El runtime probado permanece idéntico.

**Codex: CHANGES_REQUESTED, dos P2.** No se aprobó/fusionó/publicó ni se envió comentario en GitHub durante esta revisión.

## Hallazgos

1. P2 `app/src/data/llamadas-celular-api.ts:170`: corta tras500 actividades de cualquier tipo. Repro MSW con API real:500 notas y un resultado válido en página6 → devuelve[] tras5páginas. La UI informa que no hay resultados y sugiere registrar. Corregir paginación/lotes de marcas o exponer truncamiento y cargar más; no dar búsqueda incompleta por exhaustiva.
2. P2 `AVISO-TRATAMIENTO.md:48–49`: cerrar el celular revoca la credencial, pero no detiene captura, apertura ni POST/reintentos de las macros. Ante401 la cola persiste. Corregir aviso y procedimiento de retiro con detención local/cola, conservando historial CRM.
3. P3: aviso dice que nadie guarda clave en claro, aunque MacroDroid la necesita como variable global; precisar servidor vs equipo. ACTIVAR-C2 vuelve a afirmar número vacío sin permiso cuando SOPORTE lo deja como hipótesis. Demo busca sin excluir actividades ya unidas. Texto «después» debe reflejar margen10min antes.
4. ExportarC1 es ruta por probar; no afirmar fuga: verificar con plantilla sintética que no incluya credencial/números/colas antes de distribuirla. Aviso es borrador, base legal pendiente; review técnico no la aprueba.

## Recomendaciones

Permitir resultados de cualquier autor dentro del mismo lead visible, mostrando autor y elección explícita, corresponde a RPC existente; sincronizar plan «mismo analista». Botón en identificadas y margen inferior10min sin tope superior adicional corresponden a puerta vigente. Probar unión sobre llamada reasignada antes de declarar ese recorrido aceptado. Primero corregirP2; luego checks/fusión/publicación y aceptación focalizadaC1 (guardar ficha/PC y unir sin crear actividad). No repetirP1–P15 completos.

C2/C3: lunes12/10/2026, unaSIM/sin internacionales; Pro hastaS/57 aprobado. H-P5/H-P10 siguen en nuestra sesión; JevOFF. Plan47/102, sin nuevas casillas cerradas por estePR.

## Verificación

PASS lint/typecheck/build,125tests en4archivos,2E2E Docker locales. FAIL adicional esperado del test de reproducción: demuestra corte500, no infraestructura. PASS JSON/diffcheck/regeneración idéntica, historial preservado+8entradas. Código evaluado59fb5faa idéntico a cabeza final8e6aa931; documentos finales revalidados. CI finalconsultado:preflight/cambiosPASS,app-checken curso,verifypendiente,Previewomitido. Claude wrapperexit1 sinVERDICT:NOTRUN, no aprobación. No nueva suite completa6619 ni SQL/RLS ni físicoC1; proporcionado alalcance. CodeGraph no tenía índice en copiaaislada; fuente/diff/tests como complemento. Sharedcheckout intacto y copiaaislada limpia.

Informe/evidencias: `/private/tmp/avancecorp-pr251-review-20261010/REVISION.md`, `checks.json`, `probe-paginacion.log`, `pr251-review.test.ts`, `tests-existentes.log`, `e2e.log`, `build.log`.

https://github.com/avanza-digital/avancecorp-crm/pull/251

## Informe provisional enviado a Jhosep — 10/10/2026, 16:41 Lima

Miguel avisó que el PR continuaba recibiendo actualizaciones y después ordenó «enviale todo a jhsoep». Se verificó la cabeza `41f0edbb3e06b0aeb40eadb3842208ec8dfb11b1`: el delta desde `8e6aa931` solo cambia coordinación/seguimiento; ambos P2 siguen presentes. CI de `41f0edbb`: verify, app-check, preflight y cambios PASS; Supabase Preview omitido. Este estado sustituye el CI en curso del review anterior.

Se publicó **un único comentario provisional** con los dos P2, los cuatro ajustes P3, riesgos distinguidos de hallazgos, recomendaciones sobre autores/margen, evidencia de 125 tests y 2 E2E, y el código completo de la prueba que reproduce el corte de 500 actividades. Se pidió a Jhosep avisar «listo para revisión» con el SHA final al terminar sus actualizaciones; el dictamen final queda pendiente de esa cabeza.

https://github.com/avanza-digital/avancecorp-crm/pull/251#issuecomment-6102475635

El cuerpo remoto se volvió a leer y coincide íntegramente con el preparado. No se hizo aprobación formal, fusión ni publicación de producto. H-P5/H-P10 permanecen en nuestra sesión; C2/C3 el lunes 12/10, una SIM y sin internacionales; Jev apagado.
