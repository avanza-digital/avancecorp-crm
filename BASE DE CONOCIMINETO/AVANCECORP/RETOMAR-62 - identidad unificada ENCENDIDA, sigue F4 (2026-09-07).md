---
tags: [crm, multiempresa, identidad, activacion, retomar, roadmap]
fecha: 2026-09-07
estado: identidad-encendida-en-produccion
codigo: RETOMAR-62
sustituye_a: RETOMAR-60
---

# RETOMAR-62 — La identidad unificada está ENCENDIDA. Sigue F4.

> [!success] Hito
> El **07/09/2026 a las 10:09:16 (Lima)** se encendió en producción `crm.multiempresa_flags.resolver_en_puertas`.
> El CRM reconoce a la persona a través de leads, clientes del Portal y contratos. Tres fases de nueve completadas.

## 1. Qué decir en una frase

Terminamos el **reconocimiento de la persona** (F3). Falta el **motor de inversiones multiempresa** (F4), que es lo
que permite que un cliente de Avance invierta en Qorilazo o Prodelco. Hoy eso **todavía no se puede**.

## 2. Lo que se publicó el 06 y 07/09

| Pieza | Qué hace | Estado |
|---|---|---|
| `[D-17]` `20260906160000` | Poner y levantar «No insistir» y la conversión en cooperativa leen la bandera bajo su candado | ✅ prod, 2 `!` |
| `[D-18]` `20260906190000` | La conversión no abre tramo a un analista que se está dando de baja; la fusión cancela también las tareas de cliente | ✅ prod, 2 `!` |
| `[D-19]` `20260906200000` | **Las 34 funciones** que leen la bandera lo hacen bajo su candado. Censo en producción: **cero sueltas** | ✅ prod, 2 `!` |
| `[D-20]` `20260906210000` | El cliente que vuelve por la web deja **nota en su ficha y tarea para su analista** | ✅ prod, 2 `!` + edge `crm-importar-leads` **v20** |
| Encendido | `resolver_en_puertas = true` | ✅ 07/09 10:09 Lima |

243 migraciones registradas al terminar. Las otras dos banderas (`inversiones_escritura`, `ficha_360_neutral`) siguen
en `false`: son los interruptores de F4 y F5.

## 3. Verificación del encendido (07/09, 10:09–10:30)

Seis sondeos independientes en producción (errores, leads, conversión, contratos, veto/tareas, métricas) y un
escéptico por hallazgo. **33 observaciones, CERO confirmadas como problema del encendido.** 664 peticiones sin un solo
4xx ni 5xx, cero errores de base, cero contención de candados, y las cifras de Gerencia (capital por moneda, contratos,
clientes, leads) **idénticas** al minuto anterior. Los analistas siguieron trabajando sin notar nada.

> [!warning] 🔴 El hallazgo que sí importa: **los leads no traen documento**
> La identidad reconoce a la persona **por su documento**, y el canal principal de entrada no lo captura.
> - Septiembre: **440 leads, solo 10 con DNI** (430 sin él).
> - Leads vivos hoy: **930 de 937 sin documento**.
> - La tanda del 07/09 (114 leads): **ninguno** con documento.
>
> Consecuencia: sobre un lead que entra por la web sin documento, el motor **no puede actuar** — no detecta el
> duplicado, no reconoce al cliente que vuelve y no genera la nota ni la tarea de D-20.
> **Dónde sí actúa ya:** cuando el analista escribe el DNI en la ficha, al convertir, al crear contrato y en la
> corrección de documento de Gerencia. De las 35 conversiones históricas, 27 tenían documento.
>
> **Por eso la pieza de mayor valor inmediato NO es F4, sino pedir el documento en el formulario.** Tiene coste
> comercial (baja la tasa de llenado) → **decisión de Miguel**, abajo.

Otros datos de contexto: el veto extendido está en **0 de 427 personas** (nadie lo ha usado aún), y la saga de Auth
(`crm.multiempresa_idempotencia`) nunca ha corrido en producción.

## 4. Decisiones pendientes de Miguel

1. **🔴 ¿Se pide el documento en el formulario de la web?** Es lo que activa de verdad todo lo construido. Opciones:
   obligatorio, opcional, o en un segundo paso tras captar el teléfono. Sin esto, F3 solo actúa al convertir, que es tarde.
2. **Bitácora:** ¿se enmascara el detalle de `crm.actividades_cliente` y `crm.tareas` en `public.audit_log`, como se
   hizo en D-9 con leads y cierres? La nota libre del formulario puede traer un documento escrito por el visitante.
3. **Vencimiento de la tarea de D-20:** hoy vence a 24 h exactas y puede caer en domingo o de madrugada. ¿Se redondea
   al siguiente día hábil?
4. **Portal:** «Renovar con mi asesor» y «Hablar con mi asesor» abren WhatsApp y **no dejan rastro en el CRM**. Mismo
   agujero que cerró D-20, por la puerta del cliente. ¿Se cierra?
5. ~~Retoma de Gerencia en pantalla~~ → **decidido el 07/09: se queda solo por SQL.** Pasa ~1 vez cada varias semanas
   (1 de 35 conversiones). Riesgo asumido: si pasa un fin de semana, el lead queda trabado hasta que alguien con consola lo atienda.

## 5. Lo que falta, por fases

| Fase | Qué se construye | Qué te da comercialmente | Estimado |
|---|---|---|---|
| **F4 · Motor de inversiones multiempresa** | Puerta «registrar nueva inversión» para una persona existente; selección de empresa; rama Avance (contrato, cronograma, Portal) y rama cooperativas (monto, depósito, referencia, vencimiento, evidencia); idempotencia por número de transacción; anulaciones sin borrado; migrar los 15 cierres externos vivos como primera inversión. Enciende `inversiones_escritura`. | **Tu cliente de Avance invierte en Qorilazo sin crear otra ficha.** | 2 semanas |
| **F5 · Cartera y Ficha 360 multiempresa** | «Mi cartera» pasa a lista de personas; búsqueda por documento y filtros por empresa; ficha con inversiones agrupadas por empresa y moneda, estado y vencimiento; botón «Nueva inversión»; cuentas bancarias solo en la rama Avance. Enciende `ficha_360_neutral`. | Un cliente, varias empresas, en una sola pantalla. | 2 semanas |
| **F6 · Postventa y próxima inversión** | Alertas de vencimiento por empresa; renovación desde contrato; reinversión desde la inversión anterior; bandeja de inversionistas sin responsable. | El asesor no espera a que el cliente llame. | 1 semana |
| **F7 · Métricas por empresa** | Capital por empresa y moneda; clientes con una, dos o tres empresas; primera inversión vs reinversión; comisión por operación; cross-selling; demos y anulaciones excluidas. | Saber cuánto produjo cada empresa y a quién venderle la siguiente. | 1 semana |
| **F8 · Piloto y activación progresiva** | Gerencia + 1 supervisor + 2 comerciales, 5 días hábiles sin incidencia grave; luego 4 olas hasta todo el equipo. | La operación multiempresa disponible para el equipo. | 1–2 semanas |
| **F9 · Estabilización** | 30/60/90 días: adopción, fricciones, permisos, ¿entran más empresas? | — | continuo |

**Detalle completo de cada fase:** [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].

## 6. Cómo apagar si algo sale mal

```
cd /Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp
npx supabase db query --linked --file supabase/scripts/apagar-resolver-en-puertas.sql
```

Reversible en un comando y sin pérdida de datos. Desde D-19 el cambio de bandera **espera** a las operaciones en
vuelo en vez de rechazarlas. Las notas y tareas que D-20 ya haya creado **no se borran**: son trabajo real.

## 7. Para quien retome

- Empezar por la **decisión 1** (documento en el formulario): sin ella, F4 se construye sobre un motor que no arranca
  en el canal principal.
- El orden de reversa de todo lo publicado es **D-20 → D-19 → D-18 → D-17 → D-15 → D-5 → D-3/D-13**, y ocho reversas
  anteriores quedan inservibles mientras D-19 esté aplicada (también las de D-2, D-10, b5 y E4). Todas rehúsan solas.
- El método que funcionó y conviene mantener: construir desde el **texto vivo de producción** anclado por md5, ensayar
  en banco-f7 con oráculo y mutante, refutar con `auditor-rls` **y** Codex, y publicar apagado con el `!` de Miguel.
  En esta tanda ese método cazó, antes de producción: una bifurcación que no distinguía lead vivo de lead cerrado,
  una huella de idempotencia falsificable desde el formulario, y tres errores de SQL que habrían fallado en vivo.
- 🔴 El banco-f7 es **compartido** entre sesiones: otra sesión puede mover la bandera en mitad de una medida. Los
  oráculos ya la reafirman antes de cada caso.
