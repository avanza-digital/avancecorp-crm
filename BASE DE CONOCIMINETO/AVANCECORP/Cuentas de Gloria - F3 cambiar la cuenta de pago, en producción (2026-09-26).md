---
tags: [portal, crm, cuentas-bancarias, pagos, gloria, en-pausa]
actualizado: 2026-09-26
---

# Cuentas de Gloria · F3 — cambiar la cuenta de pago (✅ EN PRODUCCIÓN, 26/09/2026)

**Estado:** ✅ **en producción desde el 26/09 (~19:55)**:
- **Base:** migración `20260926204051` aplicada y registrada con huella; advisors sin alertas nuevas.
- **Edge:** `notificar-cambio-cuenta` v1 activa.
- **Portal:** publicado (commit `14b3b20`, SW v133).

Hubo una pausa a pedido de Miguel tras la auditoría; al retomar, dio su OK explícito al SQL
(«Sí, aplícala tú»), a la Edge y al portal («Sí, las dos»). El riesgo del «mismo día» quedó
**aceptado por ahora**. Plan general y fases anteriores:
[[Cuentas bancarias - Gloria ve y añade cuentas, fase 1 publicada (2026-09-26)]].

**Pendiente:**
- que Gloria haga el primer cambio real: ejercita el aviso con su sesión, que no se pudo probar sin
  ella;
- la pasada visual de Miguel;
- integrar el `main` local con `avancecorp/main` (el push está bloqueado por divergencia).

## Qué resuelve (comercial)

Cuando un cliente pide cobrar en otra cuenta, Gloria (admin o superadmin) cambia la cuenta de pago
de sus contratos abiertos desde la ventana «Cuentas» del portal:
- elige la cuenta nueva, marca los contratos, adjunta el **correo del cliente** donde lo pide y
  escribe el motivo;
- las cuotas que faltan (y el Excel de Pagos) salen a la cuenta nueva;
- lo ya pagado conserva la cuenta en la que se pagó;
- el cliente recibe un aviso en su portal y por correo, con la cuenta tapada.

Decisiones de Miguel: por contrato entero; solo admin y superadmin; aviso por portal y correo; el
respaldo es el correo del cliente.

## Qué se entregó (en producción)

- **Migración** `CRM-Avance-Corp/supabase/migrations/20260926204051_crm_cambio_cuenta_pago.sql`,
  con su prueba, reversa y registro en `CRM-Avance-Corp/supabase/scripts/cuentas-gloria/`. Detalle
  en `MIGRACIONES.md`. La reversa ya se niega en cuanto haya un pago sellado o un cambio registrado.
- **Edge Function** `_supabase_functions/functions/notificar-cambio-cuenta/` (v1 activa).
- **Portal:** `clientes.js v54` / `clientes.html`, `cambio-cuenta-core.js v1`,
  `cuentas-cliente-core v5`, `cuentas-pago-core v3`, `pagos.js v44` / `pagos.html` y SW `v133`
  (commit `14b3b20`).
- **Evidencia (26/09):**
  - Banco Docker con el esquema de prod: aplicar → 34 comprobaciones con 17 mutantes cazados →
    registro con huella de 16 funciones `21bb1838606355e1161a44fb0b66e809` → reversa con catálogo
    idéntico → ensayos del backfill y de la negativa de la reversa.
  - Portal 154/154 y Edge 7/7.
  - Revisiones: Codex R1 y R2 (BLOCK, resueltos o aceptados abajo); auditor-rls R2 **APPROVED**.

## Lo que se decidió en el camino (y por qué)

- **Los registros no tienen claves foráneas.** Así sobreviven a las eliminaciones auditadas de
  contratos y usuarios, cuyas guardas fallan cerradas ante dependencias nuevas.
- **Orden de bloqueos: contrato → enlace**, el mismo que al registrar un pago. El trigger 00 bloquea
  el contrato FOR UPDATE y el 10 el enlace FOR SHARE. El auditor sugería lo inverso, y eso podía
  trabar pagos.
- **Mientras se envía el aviso de un contrato, no se puede cambiar su cuenta.** Así el aviso nunca
  anuncia una cuenta ya dejada. Además, solo se da por avisado lo que de verdad se anunció.
- **El registro de pagos NO cambia**, como pactó el objetivo de F3. El sello deduce la cuenta por la
  fecha del pago.
- **La importación del Excel solo avisa** las filas cuya cuenta cambió y **nunca pide volver a
  depositar**. Un mensaje anterior («vuelve a exportar y paga a la cuenta nueva») podía causar un
  doble depósito.

## Riesgos aceptados (Miguel, 26/09: «Aceptarlo por ahora» para el del mismo día)

- **Mismo día:** un depósito a la cuenta anterior el MISMO día del cambio (o después, con un Excel
  viejo) puede quedar anotado en la cuenta nueva, porque la fecha no dice la hora.
  → **Propuesta de fase aparte:** que el registro de pagos diga a qué cuenta se depositó. Se preparó
  y probó una RPC que registra con el CCI del Excel, y se retiró por alcance.
- **El tipo del archivo de respaldo lo declara el navegador.** Solo lo sube un admin vigente.
- **Falta una prueba con dos sesiones del orden de bloqueos.** El auditor lo razonó correcto.
- **El gate `test-rls` no se corrió:** su siembra choca con el fixture P-0XX del banco.

## Cómo se publicó (26/09)

1. OK de Miguel anotado en `MIGRACIONES.md` → aplicar (`db query --linked --file`) → registrar con
   la huella (16 funciones `21bb1838…`, idéntica a la ensayada) → advisors: solo INFO esperados.
2. Edge: `npx supabase@2.114.0 functions deploy notificar-cambio-cuenta --project-ref … --use-api`
   desde una copia exacta.
   - Vivo = árbol, `verify_jwt=true`.
   - Smoke: OPTIONS 200, sin sesión 401, token inválido 401.
3. Portal:
   - preflight (0 archivos vivos perdidos; lo vivo era F2b `5998025`);
   - TUS archivo por archivo, con el SW v133 al final;
   - purga;
   - 24/24 lecturas idénticas; las URL versionadas sirven el commit.

Relacionadas: [[Cuentas bancarias por contrato]] · [[Cuentas bancarias - ledger vs casillas del perfil]]
