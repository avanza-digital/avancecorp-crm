---
tags: [portal, crm, cuentas-bancarias, pagos, gloria, en-pausa]
actualizado: 2026-09-26
---

# Cuentas de Gloria · F3 — cambiar la cuenta de pago (⏸️ EN PAUSA, 26/09/2026)

**Estado:** ⏸️ **en pausa a pedido de Miguel** (26/09, tras la auditoría). Todo está hecho y
ensayado en el banco Docker, pero **nada está aplicado en producción ni publicado**. Plan general
y fases anteriores: [[Cuentas bancarias - Gloria ve y añade cuentas, fase 1 publicada (2026-09-26)]].

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

## Qué está listo (sin commit de producción)

- **Migración** `CRM-Avance-Corp/supabase/migrations/20260926204051_crm_cambio_cuenta_pago.sql`,
  con su prueba, reversa y registro en `CRM-Avance-Corp/supabase/scripts/cuentas-gloria/`. Detalle
  en `MIGRACIONES.md`.
- **Edge Function** `_supabase_functions/functions/notificar-cambio-cuenta/`. No está desplegada.
- **Portal:**
  - `clientes.js v54` / `clientes.html`, `cambio-cuenta-core.js v1`, `cuentas-cliente-core v5`,
    `cuentas-pago-core v3`, `pagos.js v44` / `pagos.html` y SW `v133`;
  - ⛔ **no publicar antes de aplicar la migración**: la ventana «Cuentas» llamaría funciones que
    no existen.
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

## Riesgos aceptados (a confirmar con Miguel al retomar)

- **Mismo día:** un depósito a la cuenta anterior el MISMO día del cambio (o después, con un Excel
  viejo) puede quedar anotado en la cuenta nueva, porque la fecha no dice la hora.
  → **Propuesta de fase aparte:** que el registro de pagos diga a qué cuenta se depositó. Se preparó
  y probó una RPC que registra con el CCI del Excel, y se retiró por alcance.
- **El tipo del archivo de respaldo lo declara el navegador.** Solo lo sube un admin vigente.
- **Falta una prueba con dos sesiones del orden de bloqueos.** El auditor lo razonó correcto.
- **El gate `test-rls` no se corrió:** su siembra choca con el fixture P-0XX del banco.

## Cómo retomar (en este orden)

1. **Mostrar el SQL a Miguel** y pedir su **OK explícito**. Toca `public` (dos triggers AFTER en
   `cronograma_pagos` y bloqueos FOR SHARE de `contratos`) y `storage` (bucket y 7 políticas).
   Anotarlo en `MIGRACIONES.md`.
2. Si el código cambió desde el 26/09, repetir el ciclo del banco. La huella del registro y de la
   reversa debe coincidir con la viva.
3. **Aplicar:** `supabase db query --linked --file .../20260926204051_crm_cambio_cuenta_pago.sql`. Si
   el clasificador bloquea, que lo lance Miguel con `!`. Después, **registrar** con
   `registrar-cambio-cuenta-pago.sql` y revisar los **advisors**.
4. **Edge:** desplegar `notificar-cambio-cuenta` (verify_jwt activo) con el OK de Miguel. Probar con
   `dry_run`.
5. **Portal:**
   - comprobar las versiones vivas (SW, `pagos.js`, `clientes.js`) por si otra sesión publicó;
   - preflight, subida por TUS archivo por archivo, SW al final;
   - purga y 3 lecturas.
6. Marcar ☑ la tarjeta F3 del tablero (`18:50`, estado `18:52`). Luego commit y `main`.

Relacionadas: [[Cuentas bancarias por contrato]] · [[Cuentas bancarias - ledger vs casillas del perfil]]
