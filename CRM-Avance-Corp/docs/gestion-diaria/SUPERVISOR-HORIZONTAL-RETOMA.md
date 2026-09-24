# Gestión Diaria — retoma del supervisor horizontal

**H6.3 PUBLICADA Y VERIFICADA. Sigue H6.4: aceptación humana. 70/72 tareas.**

- [CRM publicado](https://crm.miavance.com/#/gestion-diaria), fuente `bbe341f6752b29e5e3e9305db3e0076d3cc11ce1`.
- Build `build-20260924T054600240Z`; ZIP `crm-20260924T054601Z-bbe341f6752b.zip`, 116 archivos HTTPS PASS.
- SHA-256 `80ec656216a7404f033f7696b943aaba8a9d93524a17c3d622ef4c1d58bde8d2`.
- SQL H3 `20260923234404` instalada por merge nativo: 348 entradas y 744 funciones;
  347 entradas previas intactas. No volver a aplicar la migración ni publicar por las actas.
- Banco alojado propio eliminado (~US$0,01743); `banco-f7` ajeno intacto.
  Clon local exclusivo H6 y su archivo de credenciales retirados; banco local H3 preservado.
- [H5](SUPERVISOR-HORIZONTAL-H5-EVIDENCIA-2026-09-24.md): 4.274 pruebas y E2E Docker 249/0/26 PASS.
- [H6](SUPERVISOR-HORIZONTAL-H6-ENTREGA-2026-09-24.md): matrices alojadas 2.226/0 antes y después,
  1.008 tareas/11 páginas por Auth/API real, tipos, catálogo/advisors y publicación PASS.
  Recorrido técnico en Chrome con sesión real de supervisor; aceptación humana aún pendiente.
- [PR #87](https://github.com/avanza-digital/avancecorp-crm/pull/87) integrado.
  [PR #88 de actas](https://github.com/avanza-digital/avancecorp-crm/pull/88) requiere revisión humana.
- Copia aislada: `/private/tmp/avancecorp-release.hvdub4/repo`, rama
  `codex/gestion-diaria-horizontal-h5-h6-acta`. Taller principal con trabajo ajeno intacto.

**Próximo paso:** el supervisor valida comparar el equipo, detectar atención y
consultar Resumen/Registro/Pendientes con menos desplazamiento. Registrar su
conformidad y cualquier corrección; repetir sólo las verificaciones afectadas.
El recorrido técnico o el prototipo aprobado no sustituyen H6.4.

Respaldo `e8e4f35f`, ambos ZIP/manifiestos, evidencias saneadas, bundle y
`entrega-final.json` están fuera de `/tmp`:
`/Users/usuario/.local/share/avancecorp-checkpoints/supervisor-horizontal-h6-2026-09-24/`.
El manifiesto del ZIP conserva la fuente publicada aunque estas actas avancen.

CLI `gate:realidad`, VoiceOver/NVDA y Safari siguen NOT RUN según H5.
[Mismo Figma](https://www.figma.com/board/9Pg7jMDRg3UVbb4XfeM80L?node-id=18-2),
[plan](GESTION-DIARIA.md) y [mapa](FIGMA-PLAN.json): 70/72, dos tareas H6.4 pendientes,
76 casillas históricas intactas. F4 del 24/09 (11:30 y 16:00 Lima) y sábado 26/09
permanece separado; tasa baja OFF y TypeSafe/Jev sin cambios.

Frase de retoma: **«Revisemos H6.4: la vista horizontal ya está publicada».**
