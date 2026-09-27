# Ranking cartera — ensayo remoto verificado

**Actualización:** entrega A publicada; ver
[[Ranking cartera - publicacion verificada (2026-09-26)]].
Los estados pendientes siguientes son historia del ensayo.

Continúa [[Ranking cartera - entrega A local verificada (2026-09-26)]] y
[[Plan por fases - inversion por empresa y ranking de cartera (2026-09-26)]].

Miguel autorizó ensayo remoto, organización AVANCECORP- CRM-PORTAL y
US$0,01344/h. No autorizó instalar el candidato en producción en este paso.
Rama ranking-cartera-20260927, ref qinpzjnslblwqjrhaqqf, id
8a0d013e-f329-4a9f-bab9-cacc9eed1ffc. Sin clientes productivos; Cron desactivado.

SQL aprobado sin cambios, SHA256
e2bc5cbea16b2efb4f4d9336a7f2cf0af1046f6e1595906951bed94388e30451.
Registro nativo del candidato: 20260927015203_crm_ranking_cartera_legada.
MD5 lector instalado en rama: bfeaa3140c4fcdedb12566dcdf5ae9a6.
Producción conserva lector 52ecf49a1c698e135a531b38ab75e291, sin este candidato.

PASS matriz focal HTTP/Auth+SQL antes/después, tres checks HTTP propios,
reversión exacta, preflights y comparación de datos/capital/conversión/ACL.
Tres contratos sintéticos por S/150000 pasan solamente de sin_origen a cartera.
No se cambia la categoría financiera ni se reescriben snapshots sellados.
Advisors: cero avisos nuevos por el candidato. Claude PASS anterior vigente.

El replay histórico inicial falló en la versión 86 por requerir vendedores.
Se reconstruyó únicamente la rama vacía con estructura e historial actuales.
Durante el ensayo entró crm_retirar_cuenta_cliente en producción; se sincronizó
su SQL e historial exactos y bucket privado vacío, y se repitieron pruebas PASS.
Rama: 371 migraciones productivas + candidato. Paridad de todas las funciones
ajenas al lector, tablas, RLS, triggers, índices y vistas; tres CHECK difieren
solo en paréntesis AND equivalentes. La nueva tabla de cuentas trae dos INFO
heredados (deny-all e índice no usado), no atribuibles al ranking.

Acta y evidencia: releases/ranking-cartera-20260926/ENSAYO-REMOTO.md y remoto/.
Estado de automatización/coste final: CIERRE-RAMA.md en la misma carpeta.
No hubo merge, commit, push ni deploy. Entrega B no iniciada.
Antes de publicar: autorización expresa, Main/avancecorp/main sincronizados,
conciliar versión local/remota sin reaplicar y cumplir gate de release.
E2E integral y build frontend NOT RUN en este ensayo SQL; matriz general de
conversión/offboarding NOT RUN (sí la focal de ranking).

## Publicación autorizada, 26/09 21:16 Lima

Miguel autorizó continuar con integración/publicación. PR #112 creada:
https://github.com/avanza-digital/avancecorp-crm/pull/112, commit 7df8167.
Versión local conciliada con 20260927015203, mismo SQL aprobado.
SQL local repetido PASS, seis E2E focalizados Docker PASS. Preflight GitHub PASS;
app-check aún en curso al checkpoint. GitHub exige aprobación de otra cuenta:
REVIEW_REQUIRED, sin reviews. No se hizo bypass ni merge de base productiva.
La respuesta «sii» del chat NO registró una revisión en GitHub. No volver a pedir
autorización de publicación; falta la acción externa requerida por el repositorio.
Retoma detallada: releases/ranking-cartera-20260926/PUBLICACION-PENDIENTE.md.
