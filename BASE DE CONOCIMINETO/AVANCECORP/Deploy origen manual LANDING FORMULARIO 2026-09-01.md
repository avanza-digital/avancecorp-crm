# Deploy origen manual LANDING/FORMULARIO — 2026-09-01

Relacionado con [[Deploy a Hostinger]] y [[Ficha comercial 360 de clientes - plan]].

## Resultado productivo

- Los analistas pueden seleccionar `LANDING` y `FORMULARIO` al crear un lead manual.
- El alta manual cuenta en las métricas que le corresponden y, si cierra, aporta al numerador de conversión.
- Un alta manual con origen `LANDING` o `FORMULARIO` no aporta al divisor mensual del analista.
- Los leads automáticos de esos orígenes conservan su aporte normal al divisor.
- No se agregó ninguna función ni sobrecarga persistente; se actualizaron los contratos existentes.

## Base de datos

- Migración: `20260901185600_habilitar_landing_formulario_alta_manual.sql`.
- Aplicada y registrada en producción el 2026-09-01.
- Verificación remota: `crm.leads.alta_manual` es `NOT NULL DEFAULT false`; la RPC sella el alta manual; el divisor excluye solo el caso manual; la pierna de cierre permanece intacta.
- Advisors de seguridad: sin errores nuevos.

## Frontend

- Release desplegado: `crm-20260901T203415Z-561eee765c87`.
- Build vivo: `build-20260901T203414854Z`.
- Commit del artefacto: `561eee765c87` en `release/landing-formulario-20260901`.
- El preflight impidió publicar el primer candidato porque no contenía la Ficha 360 que estaba en el sitio vivo. Se integró la línea `release/restaurar-ficha360-20260831` antes de crear el artefacto definitivo.
- Verificación: 184 archivos de prueba y 2,488 tests verdes; typecheck y lint verdes; SHA-256 del ZIP validado.
- Los módulos servidos por producción coinciden byte a byte con el artefacto local y contienen `LANDING`, `FORMULARIO`, `Capital vigente`, `Inversiones y contratos` e `Historial de gestiones`.
- El ZIP del release devuelve 404 tanto en `crm.miavance.com` como en `miavance.com`.

