# Gestión Diaria F4 — pausa y conflicto HTTP pendiente

Relacionado: [[Inicio]], [[Gestion Diaria F4 - cierre en copia aislada y banco Docker propio (2026-09-22)]].

Miguel pidió commits y luego pausar hasta mañana. **No continuar automáticamente.**
El punto completo de retoma es `CRM-Avance-Corp/docs/gestion-diaria/F4-PAUSA-2026-09-22.md`
en la copia aislada `/private/tmp/avancecorp-release.hvdub4/repo`, rama
`codex/gestion-diaria-f4-cierre`. El plan principal enlaza esa acta.

Main `e5957443` integrado; 4.158 tests y 234 E2E Docker PASS, 26 SKIPPED.
Matrices Auth/RLS hosted baseline y candidato: 2.196/0 cada una. Carga y roles PASS.
Concurrencia remota detectó un bloqueo real: `40001` se reintenta indefinidamente
en PostgREST 14.5; el banco local previo usaba 16.2. No publicar todavía.

Quinto SQL `20260923021512_crm_gestion_diaria_conflicto_http.sql`: dos RPC cambian
a `PT409` y se actualizan dos huellas del verificador. SQL local/24 mutantes PASS;
HTTP 14.5 pendiente por adaptador 404. Ya aplicado solo localmente: no reinstalar.
Hace falta terminar esa prueba y mostrar el quinto SQL para autorización remota.
No pedir otra vez las aprobaciones previas de los cuatro SQL, conciliación,
organización, banco hasta US$1 ni `$release-crm`.

Rama remota propia eliminada y ausencia verificada; coste horario estimado
US$0,048. Siete contenedores propios detenidos, volúmenes conservados. Evidencia
privada empaquetada; el dump final agotó 60 s y NO sirve para restaurar. Los dumps
anteriores, fixtures y scripts siguen disponibles para recrear el banco.

Producción comprobada v1 OFF, ninguno de los cuatro SQL nuevos ni del correctivo.
Etapa 3 conciliada sin reinstalarla. Tasa baja NULL hasta F5. Restan ensayo
correctivo, autorización del quinto SQL, merge SQL, release, política futura y
primera jornada real. No confundir con F4 multiempresa ni declarar F4 terminada.
