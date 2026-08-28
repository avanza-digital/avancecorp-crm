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

## 6. El plan por fases

### FASE 0 · Decidir — *esta semana, no se toca nada*
Responder las 5 preguntas abiertas de §7 y aprobar el plan.
**Al terminar:** el trabajo puede arrancar sin frenarse a mitad de camino.
**De ti:** una conversación.

---

### FASE 1 · Proteger lo que ya tienes — *antes del 5 de septiembre* ⏰
- Que quede registro de quién agrega o quita un co-titular de una cuenta mancomunada. Hoy no queda ninguno, y es el dato con más peso legal del sistema.
- Que quede registro de quién borra el historial de gestión de un cliente y quién borra cuotas de pago. Hoy tampoco.
- Blindar los montos para que no pueda entrar un valor inválido al cronograma de pagos ni al cierre mensual.

**Por qué ahora:** el primer cierre de mes real es el **10 de septiembre**. Esas tablas hoy están vacías, así que blindarlas no cuesta nada. Después del 10 sí cuesta.
**Al terminar:** ningún dato con valor probatorio se puede cambiar sin dejar rastro.
**De ti:** nada. **Duración:** 2 sesiones.

---

### FASE 2 · Mirar el primer cierre de mes — *8 al 12 de septiembre*
Semana de quietud: no se publica ni una sola modificación. Se observa que el cierre del día 10 corra bien y se guarda una copia de ese mes como referencia para verificar todo lo que venga después.

**Por qué:** si algo falla el 10, quiero saber que fue el cierre y no un cambio nuestro.
**Al terminar:** el primer cierre real, ejecutado y observado.
**De ti:** nada. **Duración:** media sesión de vigilancia.

---

### FASE 3 · Que cada venta tenga dueño — *segunda mitad de septiembre*
- Crear el campo **«analista que cierra»** en el contrato, obligatorio al registrar.
- Cuando registra un administrativo o un supervisor, tiene que **elegir el analista**; si la venta no es de nadie, va a su nombre.
- Poder **reasignar** después, dejando rastro de quién reasignó.
- Rellenar el histórico con la regla de respaldo y **marcar los dos contratos demo** para que dejen de contar.

**Al terminar:** el ranking de agosto en adelante es exacto, y ya no depende de quién tipeó.
**De ti:** confirmar los casos dudosos del histórico. **Duración:** 2 sesiones.

---

### FASE 4 · Una sola calculadora de capital — *fines de septiembre a principios de octubre*
- Construir la calculadora única, que lee **contratos y cierres en cooperativas**, cuenta por fecha de inicio y descuenta lo anulado.
- Pasar las **16 pantallas** que hoy calculan capital por su cuenta a consumirla, en tres tandas, verificando que ningún número cambie ni un céntimo.
- Al final, las dos funciones que sellan el mes también leen de ahí — **antes del 3 de octubre**, porque el cierre del 10 de octubre es su prueba.

**Al terminar:** gerencia, el supervisor y el analista ven siempre el mismo número, y cambiar una regla se hace en un solo lugar.
**De ti:** las respuestas de la mesa de capital. **Duración:** 6–7 sesiones.

---

### FASE 5 · Cerrar puertas — *mitad de septiembre, después del cierre*
- Recortar permisos heredados de fábrica, incluido uno que permite vaciar tablas enteras sin que la seguridad por filas lo frene.
- Cerrar el borrado de cuotas de pago sin rastro.
- Poner el aviso en «eliminar cliente» antes de borrar.
- Arreglar el alta de usuarios con pasaporte corto, que hoy falla.

**Al terminar:** no queda ninguna puerta abierta que nadie esté usando.
**De ti:** nada nuevo. **Duración:** 2 sesiones.

---

### FASE 6 · Las otras dos calculadoras — *octubre*
Lo mismo que la fase 4, para el conteo de leads (21 lugares) y de citas (6 lugares). Y un solo criterio de «producto seleccionable», que hoy está escrito tres veces: si alguien lo ajusta en una sola copia, CRM y portal ofrecerían catálogos distintos sin que nadie se entere.

**Al terminar:** las cuatro cifras del negocio tienen una sola fuente.
**De ti:** nada. **Duración:** 7–8 sesiones.

---

### FASE 7 · Ordenar la casa — *noviembre*
Índices que faltan y los que sobran, campos obligatorios donde el dato ya está siempre, listas de valores con un solo punto de verdad, corrección de 3 documentos que hoy quedan fuera de todo cruce, y retiro de lo que nadie usa (el catálogo de productos dormido incluido), siempre apagando primero y borrando después.

**Al terminar:** el servidor no arrastra piezas muertas ni reglas duplicadas.
**De ti:** una sesión corta para los 3 documentos y el visto bueno de cada retiro. **Duración:** 5–6 sesiones.

---

### FASE 8 · Un solo idioma — *cuando lo demás esté estable*
«Analista» en todo el sistema. Va al final a propósito: hacerlo a mitad de una verificación de cifras haría imposible saber qué cambió un número. El alcance depende de tu respuesta a la pregunta 2 de §7.

**Al terminar:** el mismo concepto se llama igual en todas partes, y no vuelve a pasar lo que pasó en esta sesión.
**De ti:** la decisión de alcance. **Duración:** depende del alcance.

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
