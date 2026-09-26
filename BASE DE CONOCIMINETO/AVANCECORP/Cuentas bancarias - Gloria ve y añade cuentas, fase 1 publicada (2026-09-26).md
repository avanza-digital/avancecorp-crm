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

## Fase 2 — historial de cuentas (PUBLICADA 26/09)

- Base: migración `20260926193424_crm_historial_cuentas_cliente` (lectura nueva
  `crm.historial_cuentas_cliente_fn`, puerta INVOKER + núcleo `private` DEFINER). **El servidor tapa
  N°, CCI y beneficiario para quien no es admin/superadmin** (Codex R1 BLOCK por fuga de números
  retirados → corregido → R2 PASS; auditor-rls PASS con P3 aplicados). Aplicada y registrada en prod con
  huella; advisors limpios; sonda sin datos OK.
- Portal `a233bec`: sección «Cuentas anteriores» («Retirada el [fecha] por [persona]»). 146/146 pruebas;
  4 archivos idénticos en prod (3 lecturas), `clientes.js?v=52`, `cuentas-cliente-core.js?v=3`, SW v131.
- Banco Docker: foto del catálogo antes/después (solo 2 funciones nuevas), prueba de permisos con 3
  mutantes, reversa idéntica. **Gate `test-rls.mjs` NOT RUN**: la semilla choca con un fixture de P-0XX
  (DNI 90000001) que no se tocó; su limpieza estándar sí vació las tablas `crm` del banco local 55322.
- La F2 se separó en **F2b** («números protegidos en el servidor»): hoy los números completos salen por 4
  vías (lista de cuentas, ficha CRM, Excel de Pagos —Operaciones lo usa para pagar— y columnas legado de
  perfiles). Decisión pendiente de Miguel.

## Pendiente

- 🔴 **Verificación visual de Miguel/Gloria:** entrar como admin → Clientes → «Cuentas» (números completos) y
  añadir una cuenta real que un cliente haya pedido → comprobar que aparece en su ficha del CRM.
- 🔴 **Riesgo preexistente:** `crm.cuentas_bancarias_cliente_fn` devuelve números completos a operaciones y
  analistas autorizados (se ven con las herramientas del navegador). Si se quiere confidencialidad real por rol,
  hay que enmascarar en el servidor (candidato a la fase 2).
- La raíz del repo tiene `main` local desfasado de `avancecorp/main` (10 atrás / 42 adelante): el commit de esta
  nota queda local hasta la integración.

## Tablero en Figma (seguimiento de Miguel)

Sección «Plan Cuentas Gloria» en el mismo FigJam del plan de Pagos, a la derecha:
https://www.figma.com/board/kZ8XNjC5fEsbogzzZMNCK7?node-id=18-2 — **al cerrar cada fase, marcar ☐→◉→☑ ahí**
(si no está en el tablero, para Miguel no pasó).

- Raíz `18:2` · título `18:3` · subtítulo `18:4` · **actualizado `18:5`** · leyenda `18:6`
- Columnas: pedido `18:7` · fases `18:8` · reglas `18:9`
- Pedido: P1 `18:13` · P2 «problemas encontrados» `18:18` (status `18:20`) · P3 «dónde vamos» `18:27` (status `18:29`, línea F1–F4 `18:30`)
- F1 `18:32` (status `18:34`, prueba de Gloria `18:39`) · F2 `18:42` (status `18:44`) · F2b `21:2` · F3 `18:50` (status `18:52`) · F4 `18:60` (status `18:62`)
- Reglas: no cambia `18:68` · decisiones `18:74` · **te toca decidir `18:80`** (ítems `18:83`–`18:85`) · riesgos `18:86`

Relacionado: [[P-0XX - publicación y conciliación pendiente (2026-09-25)]],
[[Cuentas bancarias - ledger vs casillas del perfil]], [[Arquitectura del portal]].
