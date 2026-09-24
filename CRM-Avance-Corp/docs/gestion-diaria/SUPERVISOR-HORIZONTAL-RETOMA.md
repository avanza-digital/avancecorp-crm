# Gestión Diaria — retoma del supervisor horizontal

**H5 cerrada el 24/09/2026. H6.1/H6.2 cerradas; publicación y aceptación pendientes.**

- H1–H5 completas; H6.1 PR, H6.2 artefacto y documentación H6.4 cerradas: **67/72 tareas**.
- Producto H5: `788834cc3c35191fa749ff5239aea7b2ebe032d8`.
- [PR #87](https://github.com/avanza-digital/avancecorp-crm/pull/87), integrado en Main `bbe341f6`. Actas en
  `codex/gestion-diaria-horizontal-h5-h6-acta`.
- Continuar en `/private/tmp/avancecorp-release.hvdub4/repo`.
  El taller principal tiene trabajo ajeno y permanece intacto.
- [H5: evidencia y límites](SUPERVISOR-HORIZONTAL-H5-EVIDENCIA-2026-09-24.md):
  gate 4.274 pruebas PASS; Docker local 249 PASS / 0 fallos / 26 omitidas;
  revisión resuelta, SQL/RLS/HTTP/tipos y REST 1/32 PASS, visual y zoom nativo.
- [H6: entrega](SUPERVISOR-HORIZONTAL-H6-ENTREGA-2026-09-24.md): Main verificado,
  ZIP inicial `crm-20260924T054601Z-bbe341f6752b.zip`, 116 archivos y huella
  `80ec656216a7404f033f7696b943aaba8a9d93524a17c3d622ef4c1d58bde8d2`. Respaldo vivo
  `e8e4f35f` verificado por 114 controles; ZIP/manifiesto preservados en
  `/Users/usuario/.local/share/avancecorp-checkpoints/supervisor-horizontal-h6-2026-09-24/`.

Siguiente: **H6.3**. Consultar el manifiesto exacto y fuente actualizados en
`entrega-final.json` del directorio durable; no atribuir la documentación al
artefacto anterior. Antes de publicar: repetir preflight SQL, ensayar H3 en rama hosted propia y
resolver su autorización. No tocar `banco-f7`, no aplicar directo producción.
SQL antes que frontend. La publicación requiere invocación humana `$release-crm`.
Después comprobar versión/acceso y obtener aceptación real de supervisión;
no crear actividad ficticia productiva. Ni demo ni prototipo cierran H6.

El banco local H3 es `gestion_diaria_h3_20260923`, contenedor
`supabase_db_avancecorp-f5-bank`, puerto 58322. La SQL H3 es inmutable.
CLI gate:realidad no ejecutado por falta de variables/credencial; agregados
productivos complementarios no lo sustituyen. VoiceOver/NVDA, Safari y gate
hosted/aceptación real siguen pendientes.

[Mismo Figma](https://www.figma.com/board/9Pg7jMDRg3UVbb4XfeM80L?node-id=18-2),
[plan](GESTION-DIARIA.md) y [mapa](FIGMA-PLAN.json) conservan las 76 casillas
históricas. Vault: `Gestion Diaria - H5 verificada y H6 preparada (2026-09-24).md`.
F4 real del 24/09 (11:30 y 16:00 Lima) y sábado 26/09 sigue separado;
tasa baja OFF, sin TypeSafe/Jev.

Frase de retoma: **«Continuemos H6 del supervisor horizontal desde el PR #87; H5 está verificada».**
