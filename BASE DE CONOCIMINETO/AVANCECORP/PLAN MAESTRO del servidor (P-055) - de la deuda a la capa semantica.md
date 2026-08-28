# PLAN MAESTRO del servidor (P-055) — de la deuda a la capa semántica

Código para retomar: **`RETOMAR-SERVIDOR`** · Escrito el 2026-08-28 · Reemplaza como plan vigente a [[Plan de saneamiento del servidor (P-053) - implementacion por tandas]] y a [[Capa semantica del servidor - plan por nucleos (episodios)]] (ambos siguen valiendo como detalle técnico). Inventario de origen: [[Auditoria servidor Supabase - duplicacion y deuda (2026-08-28)]].

Producido con tres arquitecturas independientes, un crítico de cobertura y **una auditoría adversarial de Codex** que refutó dos conclusiones mías antes de que llegaran al plan.

---

## 1. Resumen ejecutivo

El servidor funciona, pero **la misma cifra se calcula en muchos lugares distintos** y **el mismo concepto tiene dos nombres**. Ese segundo problema no es cosmético: durante la sesión que produjo este plan, la doble nomenclatura «analista/vendedor» me hizo dar un diagnóstico comercial equivocado sobre datos correctos.

El plan tiene tres frentes:

1. **Cerrar la deuda que cuesta hoy** — un rastro de auditoría que falta sobre un dato legal, y la protección de los montos antes del primer cierre de mes del 10/09.
2. **Construir la capa semántica** — una sola calculadora por cifra (capital, leads, citas), con una puerta única de autorización y pantallas que no calculan.
3. **Unificar el idioma** — «analista» en todo el sistema.

**La pieza central es el capital**, y la auditoría de Codex dejó claro que el dato que hace falta **no existe todavía**: hay que crearlo.

---

## 2. Decisiones tomadas por Miguel (2026-08-28)

| # | Tema | Decisión |
|---|---|---|
| 1 | **De quién es un contrato** | **Del analista que lo cierra.** El vínculo cliente↔analista es para que el cliente vea a su analista en la app; **no es la guía del ranking**. |
| 2 | **Campo «analista que cierra»** | **Se crea y es obligatorio desde ya.** Cuando registra un administrativo o un supervisor, tiene que **seleccionar el analista**; si no corresponde a nadie, lo pone a su nombre. **Debe poder reasignarse** después. El histórico se rellena con la regla de respaldo. |
| 3 | **Qué fecha define el mes** | **La fecha de inicio del contrato**, no la de registro. |
| 4 | **Cooperativas** | **Son parte del capital**: el núcleo lee contratos **y** cierres en cooperativas (solo vigentes; los anulados descuentan). |
| 5 | **Desglose renovado/adicional** | **Se completa**: hoy está vacío en las 62 operaciones aunque 53 dicen «completo». |
| 6 | **Contratos demo en producción** | **444444 y 888282 son demos** (de Kirk) → se excluyen de métricas y ranking. **001163 es de Adelayda** y cuenta para agosto; **001325 es de Miguel Briceño**. |
| 7 | **Catálogo de productos versionados** (6 funciones dormidas) | **Eliminar.** |
| 8 | **4 funciones esperando pantalla** | **Publicar las pantallas** (Mi cartera, Ficha 360°, período comercial). Salen de la lista de retiros. |
| 9 | **Botón «eliminar cliente»** | **Avisar** qué se va a borrar antes de hacerlo. |
| 10 | **Superadmin borrando perfiles** | **Queda abierto como hoy** — excepción consciente, con su consecuencia aceptada. |
| 11 | **Nomenclatura** | **«analista» en todo el sistema**, CRM y portal. *(Ver §5: Codex recomienda acotar el alcance interno; requiere una decisión final.)* |
| 12 | **Tablero por analista** | **Se abre**, verificado contra el cuadro de agosto. |
| 13 | **Conexión `crm_metricas_bridge`** | No se sabe qué la usa → **investigar antes de retirar nada** que dependa de ella. |
| 14 | **Arranque** | **Nada se ejecuta hasta aprobar este plan.** |

---

## 3. Los hallazgos que cambiaron el plan

### 3.1 La doble nomenclatura ya costó un diagnóstico

17 personas tienen a la vez `perfiles.rol='analista'` (portal) y `crm.equipo.rol_crm='vendedor'` (CRM), más 2 analista+supervisor. **No son dos grupos: son el mismo equipo.** Leerlos como grupos distintos me llevó a afirmar que «el capital lo registra el back office» y que «el CRM no captura la venta nueva». **Las dos afirmaciones eran falsas y quedan retractadas.**

### 3.2 Lo que Codex refutó de mi corrección

| Afirmación mía | Veredicto de Codex |
|---|---|
| (a) analista y vendedor son la misma persona | **Confirmada** — 17 + 2, verificado |
| (b) `creado_por` identifica a quien vendió | **Refutada como regla universal.** Reconstruyendo el asesor vigente al momento del alta desde `audit_log`: **7 contratos fueron registrados por gerencia para 3 asesores distintos**. El flujo de conversión ya separa explícitamente operador y asesor (`creado_por: callerId` vs `asesor_perfil_id: asesorId`). |
| (c) 465 de 466 registrados por el equipo comercial | **Confirmada, pero solo como distribución del registrador** — no demuestra quién vendió |
| (d) el mes se cuenta por fecha de registro | **Refutada — hallazgo principal.** El módulo vivo **ya usa `fecha_cierre_comercial`**, no la fecha de registro. Mi cuadro por «quién registró» difiere de la pantalla real en **15 de 18 personas** (S/ 6,53 M contra S/ 4,00 M). |
| (e) el núcleo debe atribuir por `creado_por` | **Refutada.** El núcleo vivo ya es **híbrido**: usa el analista explícito del lead si existe, si no el autor; exige pertenecer al **roster mensual** y suma los cierres en cooperativas. Agosto vivo = 118 − 8 (fuera del roster) + 5 (cooperativas) = **115 unidades**. |

**Conclusión de Codex, que coincide con lo que decidió Miguel:** conservar `creado_por` como *registrador* y **añadir una autoría comercial inmutable**. Ni `creado_por` ni la operación de cartera sirven solos.

**Dato relevante:** hoy **no existe módulo de comisiones** en el servidor (0 tablas, 0 funciones). El ranking no está pagando plata todavía — hay margen para hacerlo bien antes de que lo haga.

### 3.3 Cuánto se mueve el ranking según cómo se cuente

Producción de agosto de las tres primeras, según el criterio:

| Analista | Por fecha de registro | Por fecha de inicio | Definitivo (inicio + coop) |
|---|---:|---:|---:|
| Grecia Ramírez | S/ 1 170 600 | S/ 607 600 | **S/ 807 600** |
| Adelayda Gaspar | S/ 1 104 100 | S/ 366 600 | S/ 383 600 |
| Astrid Centenaro | S/ 653 100 | S/ 573 100 | **S/ 573 100** |

De 210 contratos registrados en agosto, **92 empezaron antes** (S/ 2,61 M, el 42 %). El podio cambia según el criterio: por registro, Adelayda es 2.ª; por fecha de inicio, cae al 5.º y sube Astrid.

⚠️ **Salvedad:** el ranking de arriba aún no aplica el filtro de roster mensual que el sistema vivo sí aplica (8 contratos quedan fuera). El núcleo debe decidir si ese filtro se conserva — está en las preguntas abiertas.

---

## 4. El diseño del capital

**Las tres reglas de la capa:**
1. **El núcleo no autoriza** — recibe la visibilidad resuelta, devuelve filas-hecho. En `private`, sin acceso desde la API.
2. **La ventana autoriza una vez** — un despachador por métrica.
3. **La pantalla no calcula** — solo suma, filtra y da forma.

**La regla que desbloquea todo:** las dimensiones con decisión abierta **viajan como columnas del hecho**. Así una respuesta tardía cambia números, no estructura.

**La fila-hecho de capital lleva:**
- El **analista que cerró** (campo nuevo, inmutable, reasignable con rastro)
- El registrador (`creado_por`), que se conserva y **no se pisa**
- Fecha de inicio del contrato (eje del mes) y fecha de registro (para auditar cargas tardías)
- Moneda (PEN y USD **nunca** se suman)
- Origen: contrato del portal o cierre en cooperativa
- Estado de anulación
- Marca de demo/prueba (para excluir 444444 y 888282 y los que vengan)

---

## 5. La campaña de nomenclatura — con el veredicto de Codex

**Inventario corregido por Codex:** 10 columnas, 4 tablas, 13 funciones, 17 índices con el término en el nombre; **54 funciones** con el literal; **7 políticas** que comparan el valor (no 18: las otras solo lo mencionan); **3 CHECK** (no 6); 19 filas de equipo; 3 236 apariciones en 218 archivos del CRM (228 son literales, 3 008 son identificadores y textos). **El portal desplegable tiene 0 apariciones.**

**Lo que rompería, por gravedad:**

| Nivel | Qué se rompe |
|---|---|
| **P0** | Si se migran las 19 filas primero, `crm.mi_acceso_fn` no reconoce el rol y devuelve **«revocado»**: el CRM deja de dejar entrar a todo el mundo. |
| **P0** | `vendedor_ids_visibles` cae a su rama vacía y `roster_metas_vendedores` devuelve nada: **leads, ranking y metas en blanco**. |
| **P0** | La edge de conversión rechaza al rol nuevo con **403**, y `ciclo-contratos` deja de enviar avisos a esos analistas. |
| **P0** | **Colisión de significados:** `perfiles.rol='analista'` habilita el portal; el nuevo `rol_crm='analista'` significaría fuerza de ventas. Además hay 2 vendedores del CRM cuyo rol de portal es `comercial`. |
| **P1** | Renombrar columnas, tablas o funciones **cambia las direcciones de la API**: los navegadores con la versión vieja reciben errores. |
| **P1** | La edge de usuarios llama por nombre a `registrar_vendedor_usuario_fn`, y la hoja de leads manda la clave `vendedor_correo`. |
| **P2** | Los tres gates de pruebas usan el literal: quedarían verdes probando el mundo viejo. |
| **P3** | Los 17 índices solo tienen el término en el nombre: renombrarlos no cambia nada. |

**Recomendación de Codex:** cambiar **solo lo que se lee** a «Analista» y conservar `vendedor` como contrato interno estable. Es la única variante sin indisponibilidad y sin compatibilidad eterna.

**Si el renombre interno se mantiene** (decisión de Miguel), el único orden seguro es: aditivo en la base (aceptar ambos valores) → edges que aceptan ambos → CRM que lee ambos → recién ahí migrar las 19 filas → y la limpieza final **solo** con un gate de versión que fuerce recarga y telemetría que pruebe que no queda nadie en la versión vieja.

---

## 6. Las etapas

### Bloque A — lo urgente (fecha dura)

**E1 · Blindaje pre-sellado** — *2 sesiones · en producción antes del 05/09*
Rastro de auditoría en co-titulares de contratos (el único hallazgo realmente roto), en actividades de cliente y en la agenda; completar el rastro de borrado en historial de gestión y en cuotas; declarar con comentario las 5 tablas que no llevan auditoría a propósito. Y la malla que impide que un monto inválido entre a cronograma de pagos y al cierre mensual — **hoy esas tablas están vacías, así que es gratis; después del 10/09 deja de serlo**.

**E2 · Congelamiento y vigilancia del primer cierre** — *08–12/09*
Ninguna migración esa semana. Se observa el cierre del 10/09, se verifica que nada rebotó, y se guarda el fixture del mes real como oráculo de las etapas siguientes.

### Bloque B — el capital (lo que más te importa)

**E3 · Diseño y cola de decisiones** — *1–2 sesiones · puede correr durante el congelamiento*
La ficha del hecho de capital, el trinquete que impide que nazcan calculadoras nuevas, y las preguntas que falten, con sus números.

**E4 · El campo «analista que cierra»** — *2 sesiones*
Se crea en el contrato, obligatorio en el alta, con selección explícita cuando registra un administrativo o un supervisor, y **reasignable con rastro**. Se rellena el histórico con la regla de respaldo (verificada: para agosto da el mismo ranking). Se marcan los dos contratos demo.

**E5 · Núcleo de capital y sus pantallas** — *4–5 sesiones*
La calculadora única + su puerta de autorización, y las 16 pantallas que hoy calculan capital pasan a consumirla, en tres tandas, cada una verificando que el número no cambie ni un céntimo.

**E6 · Las dos funciones que sellan el mes** — *2 sesiones · antes del 03/10 o se espera un mes*
Pasan a leer del núcleo. El cierre del 10/10 es su prueba de aceptación.

### Bloque C — el resto de la capa

**E7 · Núcleos de leads y citas** — *6–7 sesiones · octubre*

**E8 · Criterio único de producto seleccionable** — *1 sesión* (hoy escrito 3 veces; un cambio en una sola copia haría que CRM y portal ofrezcan catálogos distintos).

### Bloque D — saneamiento

**E9 · Cierre de superficie** — *1–2 sesiones · semana del 14/09, después del cierre de mes*
Recortar permisos heredados de fábrica (incluido uno que la seguridad por filas no gobierna), unificar las políticas que repiten el chequeo de rol a mano, cerrar el borrado de cuotas sin rastro y aplicar el aviso en «eliminar cliente».

**E10 · Modelo de datos** — *3–4 sesiones*
Índices que faltan y los que sobran, campos obligatorios donde el dato ya está siempre, listas de valores con un solo punto de verdad, y el formato de documento (3 registros a corregir contigo).

**E11 · Retiros** — *2–3 sesiones · noviembre*
Eliminar el catálogo de productos dormido y las funciones que nadie llama, siempre apagando primero y borrando después, con tu visto bueno pieza por pieza.

**E12 · El bug del pasaporte** — *media sesión, cuando quieras*
Un pasaporte de 6 o 7 caracteres hoy no puede crear su cuenta.

### Bloque E — nomenclatura

**E13 · «Analista» en todo el sistema** — *alcance a confirmar (§5)*
No se solapa con las etapas de capital: un renombre a mitad de una verificación de cifras haría imposible saber qué cambió un número.

---

## 7. Preguntas abiertas que faltan para cerrar el plan

1. **El filtro de roster mensual:** hoy el sistema excluye del mes a quien no estaba en la foto del equipo (8 contratos de agosto). ¿Se conserva esa regla en el núcleo nuevo?
2. **El alcance final del renombre**, a la luz de lo que Codex encontró (§5).
3. **Los 12 contratos históricos** de mayo a julio registrados por gerencia: ¿se revisan o se declaran aproximados?
4. **`tipo_documento`** repetido en 3 tablas: ¿se unifica o se tolera?
5. **La FK que borra en cascada la membresía del equipo**: ¿se cambia a que impida el borrado?

---

## 8. Tablero (lo que mide que esto terminó)

| Contador | Hoy | Meta |
|---|---|---|
| Capital calculado fuera del núcleo | 16 + indirectos | 0 |
| Leads contados fuera del núcleo | 21 | 0 |
| Citas contadas fuera del núcleo | 6 | 0 |
| Contratos sin analista que cierra | 466 | 0 |
| Contratos demo contando en métricas | 2 | 0 |
| Tablas sin rastro ni declaración | 8 | 0 |
| Puertas de borrado sin auditoría | 4 | 0 |
| Montos sin protección | 11+ | 0 |
| Permisos de fábrica sin recortar | 10 tablas | 0 |
| Políticas que repiten el rol a mano | 3 + 13 | 0 |
| Versiones vivas de la misma métrica | 3 | 1 |
| Cierres de mes sanos | 0 | 2 |
| Fichas de la capa semántica | 1 | 6 |

---

## 9. Definición de terminado

1. Cada cifra tiene una sola calculadora, y una prueba automática impide que nazca otra.
2. Cada contrato sabe qué analista lo cerró, y ese dato no se mueve solo.
3. Dos cierres de mes reales ejecutados sanos.
4. Ningún hallazgo de la auditoría sin destino: arreglado, retirado, o declarado a propósito y firmado.
5. Un solo idioma en todo el sistema.
