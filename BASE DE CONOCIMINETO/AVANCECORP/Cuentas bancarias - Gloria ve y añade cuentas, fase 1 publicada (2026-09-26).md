---
tags: [portal, cuentas-bancarias, permisos, gloria]
actualizado: 2026-09-26
---

# Cuentas bancarias — Gloria ve y añade cuentas (fase 1 publicada, 26/09/2026)

**Pedido de Miguel (25/09, en Codex; retomado en Claude el 26/09):** que Gloria (rol `admin` del portal)
vea todo el detalle bancario del cliente sin nada oculto, pueda añadir cuentas y, cuando un cliente lo pide,
**dejar de pagarle en una cuenta y pagarle en otra**; todo visible también en el CRM.

## Plan por fases (aprobado)

1. **Gloria ve todo** (solo pantalla) — ✅ **PUBLICADA Y VERIFICADA 26/09.**
2. **Historial de cuentas** (lectura en servidor): las cuentas retiradas visibles con fecha y quién.
3. **Cambiar la cuenta de pago por pedido del cliente** (servidor, delicada): hoy el enlace contrato→cuenta es
   inmutable por diseño (`crm.contrato_cuentas_pago`, trigger «La cuenta de pago del contrato es histórica y no se
   reemplaza»). Hay que versionarlo por fechas y guardar en cada cuota pagada la cuenta usada.
4. **Retirar una cuenta**: nunca se borra; si tiene cuotas pendientes, primero se cambia (fase 3).

Decisiones que Miguel aún debe tomar para la fase 3: ¿cambio por contrato entero o cuota por cuota? (recomendado:
contrato entero) · ¿Gerencia del CRM también ve números completos? (recomendado: solo administradores).

## Qué hace la fase 1

- Botón **«Cuentas»** en cada fila de *Clientes* → ventana con las cuentas vigentes en soles y dólares y
  **«+ Añadir cuenta»** (moneda, banco, tipo, N°, CCI, beneficiario). Guarda con la misma función que ya usaban
  el CRM y «Editar cliente» → aparece en el CRM.
- **Admin y superadmin** ven N°, CCI y titular/beneficiario completos (también en «Editar»). Operaciones, analistas
  y el resto siguen viendo `••••1234`.
- Añadir **no** retira cuentas ni cambia la cuenta de pago de contratos existentes (eso es la fase 3).

## Evidencia

- Portal commit `46ce6c7` (`main` local; el portal no tiene remoto). Bumps: `cuentas-cliente-core v2`,
  `clientes.js v51`, SW `avance-v130`. Detalle técnico en `public_html/CLAUDE.md` (26/09).
- Pruebas: 138/138 PASS (5 nuevas), 4 mutantes cazados. Maqueta local con datos ficticios: admin completo,
  analista enmascarado, móvil apilado.
- Codex (encargo `CRM-Avance-Corp/docs/encargos/2026-09-26-codex-portal-cuentas-cliente-f1.md`): BLOCK con 2 P1.
  **Aceptado:** carrera al cerrar la ventana con ESC durante un guardado → corregido. **No aceptado en esta fase
  (fuera de alcance, preexistente):** el servidor entrega los números completos a todo rol autorizado; el
  enmascarado es solo de pantalla.
- Publicado por TUS archivo por archivo (4 archivos; pre-check «producción = d13117a»), purga de CDN,
  12/12 lecturas idénticas; el HTML vivo pide `clientes.js?v=51` → `cuentas-cliente-core.js?v=2`.
  Preflight del portal OK (0 archivos vivos perdidos, solo esos 4 cambian).

## Pendiente

- 🔴 **Verificación visual de Miguel/Gloria:** entrar como admin → Clientes → «Cuentas» (números completos) y
  añadir una cuenta real que un cliente haya pedido → comprobar que aparece en su ficha del CRM.
- 🔴 **Riesgo preexistente:** `crm.cuentas_bancarias_cliente_fn` devuelve números completos a operaciones y
  analistas autorizados (se ven con las herramientas del navegador). Si se quiere confidencialidad real por rol,
  hay que enmascarar en el servidor (candidato a la fase 2).
- La raíz del repo tiene `main` local desfasado de `avancecorp/main` (10 atrás / 42 adelante): el commit de esta
  nota queda local hasta la integración.

Relacionado: [[P-0XX - publicación y conciliación pendiente (2026-09-25)]],
[[Cuentas bancarias - ledger vs casillas del perfil]], [[Arquitectura del portal]].
