# PORTAL DIGITAL DE INVERSIONES — AVANCE CORP S.A.C.
## Documento Maestro de Implementación para Claude Code
**Versión:** 1.0 | **Fecha:** Abril 2026 | **Propietario:** Área Comercial MasCapital

---

## INSTRUCCIONES PARA CLAUDE CODE

Eres el desarrollador principal de este portal. Debes leer este documento completo antes de escribir cualquier línea de código. Este documento es tu única fuente de verdad. Toda decisión técnica, de arquitectura, de diseño y de funcionalidad está aquí definida. No improvises nada que no esté documentado. Si algo no está claro, pregunta antes de ejecutar.

**Reglas de trabajo:**
- Construye en HTML/JS vanilla. Sin frameworks como React o Vue.
- Todo el frontend va en un solo archivo index.html por vista, más archivos JS y CSS separados.
- Usa Supabase como backend completo: base de datos, autenticación y storage.
- Cada módulo debe ser funcional al 100% antes de pasar al siguiente.
- Aplica Row Level Security en Supabase desde el primer día, no al final.
- Comenta el código en español.
- Ante cualquier duda de diseño visual, usa como referencia estética el banco BCP: limpio, profesional, confiable.

---

## SECCIÓN 1: CONTEXTO DEL NEGOCIO

### 1.1 La Empresa
**Avance Corp S.A.C.** es una empresa peruana rentabilizadora de inversiones en mercados financieros internacionales (Forex, oro, criptomonedas). Pertenece al holding MasCapital. RUC: 20611392088. Domicilio: Av. República de Panamá N° 3635, San Isidro, Lima.

### 1.2 El Producto
Contratos de Asociación en Participación donde el cliente (Asociado) aporta capital y Avance Corp (Asociante) lo gestiona en mercados financieros, retribuyendo una rentabilidad anual de hasta el 15% a mas esto va a depender lo que se acuerde con la persona.

### 1.3 Escala
- Aproximadamente 5,000 clientes activos
- Contratos en soles (PEN) y dólares (USD)
- Modalidades de pago: mensual, trimestral, semestral y anual
- Monto mínimo: S/ 1,000 o US$ 1,000

### 1.4 Objetivo del Portal
Plataforma digital privada donde cada cliente ve el estado de su inversión en tiempo real. No es un sitio web público. Es el equivalente a la banca por internet de un banco, pero para contratos de inversión.

---

## SECCIÓN 2: STACK TECNOLÓGICO

| Componente | Tecnología | Versión/Plan |
|---|---|---|
| Frontend | HTML5 + CSS3 + JavaScript vanilla | — |
| Base de datos | Supabase PostgreSQL | Pro |
| Autenticación | Supabase Auth | Pro |
| Storage (PDFs) | Supabase Storage | Pro |
| Gráficos de inversión | Chart.js | CDN última versión |
| Gráficos de mercados | TradingView Widgets | Gratuito embebido |
| Hosting | Hostinger Business | Ya contratado |
| Dominio | A definir por el cliente | Ya gestionado |

---

## SECCIÓN 3: ARQUITECTURA DEL SISTEMA

```
USUARIO (browser)
      │
      │ HTTPS / SSL (Hostinger)
      │
FRONTEND (Hostinger)
      │
      │ Supabase JS Client
      │
SUPABASE
  ├── Auth          → Login, sesiones, roles
  ├── PostgreSQL    → Datos del negocio
  ├── Storage       → PDFs de contratos
  └── Row Level Security → Aislamiento por usuario
```

### 3.1 Estructura de archivos del proyecto

```
/portal-avance-corp
  ├── index.html              → Pantalla de login
  ├── dashboard.html          → Dashboard cliente
  ├── inversion.html          → Panel Mi Inversión
  ├── documentos.html         → Panel Documentos
  ├── novedades.html          → Panel Novedades
  ├── mercados.html           → Panel Mercados
  ├── perfil.html             → Panel Mi Perfil
  ├── admin/
  │   ├── dashboard.html      → Dashboard admin
  │   ├── clientes.html       → Gestión de clientes
  │   ├── contratos.html      → Gestión de contratos
  │   ├── pagos.html          → Registro de pagos
  │   ├── novedades.html      → Envío de novedades
  │   └── documentos.html     → Subida de documentos
  ├── css/
  │   ├── main.css            → Estilos globales
  │   ├── dashboard.css       → Estilos dashboard
  │   └── admin.css           → Estilos admin
  └── js/
      ├── supabase.js         → Configuración cliente Supabase
      ├── auth.js             → Lógica de autenticación
      ├── dashboard.js        → Lógica dashboard cliente
      ├── inversion.js        → Lógica inversión y gráficos
      ├── mercados.js         → Widgets TradingView
      └── admin/
          ├── clientes.js     → CRUD clientes
          ├── contratos.js    → CRUD contratos
          ├── pagos.js        → Registro pagos
          └── novedades.js    → Sistema mensajes
```

---

## SECCIÓN 4: BASE DE DATOS — ESQUEMA COMPLETO

### 4.1 Tabla: perfiles

```sql
CREATE TABLE perfiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  nombre_completo TEXT NOT NULL,
  dni TEXT UNIQUE,
  telefono TEXT,
  correo TEXT,
  rol TEXT NOT NULL DEFAULT 'cliente'
    CHECK (rol IN ('cliente', 'admin', 'superadmin')),
  activo BOOLEAN DEFAULT TRUE,
  creado_en TIMESTAMPTZ DEFAULT NOW(),
  actualizado_en TIMESTAMPTZ DEFAULT NOW()
);
```

### 4.2 Tabla: contratos

```sql
CREATE TABLE contratos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  numero_contrato TEXT UNIQUE NOT NULL,
  cliente_id UUID REFERENCES perfiles(id) ON DELETE RESTRICT NOT NULL,
  capital NUMERIC(12,2) NOT NULL,
  moneda TEXT NOT NULL DEFAULT 'PEN'
    CHECK (moneda IN ('PEN', 'USD')),
  tasa_anual NUMERIC(5,2) NOT NULL DEFAULT 15.00,
  modalidad TEXT NOT NULL
    CHECK (modalidad IN ('mensual', 'trimestral', 'semestral', 'anual')),
  tipo_interes TEXT NOT NULL DEFAULT 'simple'
    CHECK (tipo_interes IN ('simple', 'compuesto')),
  fecha_inicio DATE NOT NULL,
  fecha_vencimiento DATE NOT NULL,
  estado TEXT NOT NULL DEFAULT 'activo'
    CHECK (estado IN ('activo', 'vencido', 'renovado', 'retirado')),
  notas_internas TEXT,
  creado_por UUID REFERENCES perfiles(id),
  creado_en TIMESTAMPTZ DEFAULT NOW(),
  actualizado_en TIMESTAMPTZ DEFAULT NOW()
);
```

### 4.3 Tabla: cronograma_pagos

```sql
CREATE TABLE cronograma_pagos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contrato_id UUID REFERENCES contratos(id) ON DELETE CASCADE NOT NULL,
  numero_cuota INTEGER NOT NULL,
  fecha_programada DATE NOT NULL,
  monto_programado NUMERIC(12,2) NOT NULL,
  estado TEXT NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'pagado', 'vencido')),
  fecha_pago_real DATE,
  monto_pagado NUMERIC(12,2),
  registrado_por UUID REFERENCES perfiles(id),
  creado_en TIMESTAMPTZ DEFAULT NOW()
);
```

### 4.4 Tabla: documentos

```sql
CREATE TABLE documentos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contrato_id UUID REFERENCES contratos(id) ON DELETE CASCADE NOT NULL,
  nombre TEXT NOT NULL,
  tipo TEXT NOT NULL DEFAULT 'contrato'
    CHECK (tipo IN ('contrato', 'estado_cuenta', 'otro')),
  storage_path TEXT NOT NULL,
  subido_por UUID REFERENCES perfiles(id),
  creado_en TIMESTAMPTZ DEFAULT NOW()
);
```

### 4.5 Tabla: novedades

```sql
CREATE TABLE novedades (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  titulo TEXT NOT NULL,
  mensaje TEXT NOT NULL,
  destinatario_id UUID REFERENCES perfiles(id),
  -- NULL = mensaje para TODOS los clientes
  leido BOOLEAN DEFAULT FALSE,
  enviado_por UUID REFERENCES perfiles(id),
  creado_en TIMESTAMPTZ DEFAULT NOW()
);
```

### 4.6 Índices de rendimiento

```sql
CREATE INDEX idx_contratos_cliente ON contratos(cliente_id);
CREATE INDEX idx_contratos_estado ON contratos(estado);
CREATE INDEX idx_contratos_vencimiento ON contratos(fecha_vencimiento);
CREATE INDEX idx_cronograma_contrato ON cronograma_pagos(contrato_id);
CREATE INDEX idx_cronograma_estado ON cronograma_pagos(estado);
CREATE INDEX idx_novedades_destinatario ON novedades(destinatario_id);
CREATE INDEX idx_perfiles_dni ON perfiles(dni);
CREATE INDEX idx_perfiles_rol ON perfiles(rol);
```

---

## SECCIÓN 5: SEGURIDAD — ROW LEVEL SECURITY COMPLETO

### 5.1 Activar RLS en todas las tablas

```sql
ALTER TABLE perfiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE contratos ENABLE ROW LEVEL SECURITY;
ALTER TABLE cronograma_pagos ENABLE ROW LEVEL SECURITY;
ALTER TABLE documentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE novedades ENABLE ROW LEVEL SECURITY;
```

### 5.2 Políticas: perfiles

```sql
-- Cliente ve solo su perfil
CREATE POLICY "cliente_ve_su_perfil"
ON perfiles FOR SELECT
USING (auth.uid() = id);

-- Admin y superadmin ven todos los perfiles
CREATE POLICY "admin_ve_todos_perfiles"
ON perfiles FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM perfiles p
    WHERE p.id = auth.uid()
    AND p.rol IN ('admin', 'superadmin')
  )
);

-- Solo admin puede crear perfiles
CREATE POLICY "admin_crea_perfiles"
ON perfiles FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM perfiles p
    WHERE p.id = auth.uid()
    AND p.rol IN ('admin', 'superadmin')
  )
);

-- Solo admin puede actualizar perfiles
CREATE POLICY "admin_actualiza_perfiles"
ON perfiles FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM perfiles p
    WHERE p.id = auth.uid()
    AND p.rol IN ('admin', 'superadmin')
  )
);

-- Solo superadmin puede eliminar perfiles
CREATE POLICY "superadmin_elimina_perfiles"
ON perfiles FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM perfiles p
    WHERE p.id = auth.uid()
    AND p.rol = 'superadmin'
  )
);
```

### 5.3 Políticas: contratos

```sql
-- Cliente ve solo sus contratos
CREATE POLICY "cliente_ve_sus_contratos"
ON contratos FOR SELECT
USING (cliente_id = auth.uid());

-- Admin ve todos los contratos
CREATE POLICY "admin_ve_todos_contratos"
ON contratos FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM perfiles p
    WHERE p.id = auth.uid()
    AND p.rol IN ('admin', 'superadmin')
  )
);

-- Admin crea y edita contratos
CREATE POLICY "admin_gestiona_contratos"
ON contratos FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM perfiles p
    WHERE p.id = auth.uid()
    AND p.rol IN ('admin', 'superadmin')
  )
);
```

### 5.4 Políticas: cronograma_pagos

```sql
-- Cliente ve cronograma de sus contratos
CREATE POLICY "cliente_ve_su_cronograma"
ON cronograma_pagos FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM contratos c
    WHERE c.id = contrato_id
    AND c.cliente_id = auth.uid()
  )
);

-- Admin gestiona todo el cronograma
CREATE POLICY "admin_gestiona_cronograma"
ON cronograma_pagos FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM perfiles p
    WHERE p.id = auth.uid()
    AND p.rol IN ('admin', 'superadmin')
  )
);
```

### 5.5 Políticas: documentos

```sql
-- Cliente ve documentos de sus contratos
CREATE POLICY "cliente_ve_sus_documentos"
ON documentos FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM contratos c
    WHERE c.id = contrato_id
    AND c.cliente_id = auth.uid()
  )
);

-- Admin gestiona todos los documentos
CREATE POLICY "admin_gestiona_documentos"
ON documentos FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM perfiles p
    WHERE p.id = auth.uid()
    AND p.rol IN ('admin', 'superadmin')
  )
);
```

### 5.6 Políticas: novedades

```sql
-- Cliente ve novedades dirigidas a él o a todos (NULL)
CREATE POLICY "cliente_ve_sus_novedades"
ON novedades FOR SELECT
USING (
  destinatario_id = auth.uid()
  OR destinatario_id IS NULL
);

-- Admin gestiona todas las novedades
CREATE POLICY "admin_gestiona_novedades"
ON novedades FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM perfiles p
    WHERE p.id = auth.uid()
    AND p.rol IN ('admin', 'superadmin')
  )
);
```

---

## SECCIÓN 6: AUTENTICACIÓN Y ROLES

### 6.1 Configuración Supabase Auth

En el dashboard de Supabase → Authentication → Settings:
- Habilitar email/password login: ON
- Disable email confirmations: ON (para que el admin pueda crear cuentas directamente)
- Minimum password length: 8 caracteres
- JWT expiry: 3600 segundos (1 hora)

### 6.2 Configuración del cliente Supabase en JS

```javascript
// js/supabase.js
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js/+esm'

const SUPABASE_URL = 'TU_SUPABASE_URL'
const SUPABASE_ANON_KEY = 'TU_SUPABASE_ANON_KEY'

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
```

### 6.3 Lógica de autenticación

```javascript
// js/auth.js
import { supabase } from './supabase.js'

// Login
export async function login(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password
  })
  if (error) throw error

  // Obtener rol del usuario
  const { data: perfil } = await supabase
    .from('perfiles')
    .select('rol')
    .eq('id', data.user.id)
    .single()

  // Redirigir según rol
  if (perfil.rol === 'cliente') {
    window.location.href = '/dashboard.html'
  } else if (perfil.rol === 'admin' || perfil.rol === 'superadmin') {
    window.location.href = '/admin/dashboard.html'
  }
}

// Logout
export async function logout() {
  await supabase.auth.signOut()
  window.location.href = '/index.html'
}

// Verificar sesión activa
export async function verificarSesion() {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) {
    window.location.href = '/index.html'
    return null
  }
  return session
}

// Verificar que es admin
export async function verificarAdmin() {
  const session = await verificarSesion()
  if (!session) return

  const { data: perfil } = await supabase
    .from('perfiles')
    .select('rol')
    .eq('id', session.user.id)
    .single()

  if (!['admin', 'superadmin'].includes(perfil.rol)) {
    window.location.href = '/dashboard.html'
  }
}
```

### 6.4 Crear el superusuario inicial

Ejecutar en Supabase SQL Editor después de crear la primera cuenta:

```sql
-- Primero crear el usuario desde Supabase Auth Dashboard
-- Luego ejecutar esto con el UUID del usuario creado:

INSERT INTO perfiles (id, nombre_completo, dni, telefono, correo, rol)
VALUES (
  'UUID_DEL_SUPERUSUARIO',
  'Nombre del Superusuario',
  'DNI',
  'Teléfono',
  'correo@avancecorp.pe',
  'superadmin'
);
```

---

## SECCIÓN 7: CÁLCULOS DE RENTABILIDAD

### 7.1 Fórmula de rentabilidad acumulada a hoy

```javascript
// Interés simple acumulado a hoy
function calcularRentabilidadHoy(capital, tasaAnual, fechaInicio) {
  const hoy = new Date()
  const inicio = new Date(fechaInicio)
  const diasTranscurridos = Math.floor((hoy - inicio) / (1000 * 60 * 60 * 24))
  const rentabilidadDiaria = (capital * (tasaAnual / 100)) / 365
  return rentabilidadDiaria * diasTranscurridos
}

// Total actual (capital + rentabilidad)
function calcularTotalActual(capital, tasaAnual, fechaInicio) {
  return capital + calcularRentabilidadHoy(capital, tasaAnual, fechaInicio)
}

// Porcentaje del plazo transcurrido
function calcularPorcentajePlazo(fechaInicio, fechaVencimiento) {
  const hoy = new Date()
  const inicio = new Date(fechaInicio)
  const fin = new Date(fechaVencimiento)
  const totalDias = Math.floor((fin - inicio) / (1000 * 60 * 60 * 24))
  const diasTranscurridos = Math.floor((hoy - inicio) / (1000 * 60 * 60 * 24))
  return Math.min((diasTranscurridos / totalDias) * 100, 100).toFixed(1)
}
```

### 7.2 Generación automática del cronograma de pagos

```javascript
// Genera el cronograma según la modalidad del contrato
function generarCronograma(capital, tasaAnual, fechaInicio, fechaVencimiento, modalidad) {
  const inicio = new Date(fechaInicio)
  const fin = new Date(fechaVencimiento)
  const totalDias = Math.floor((fin - inicio) / (1000 * 60 * 60 * 24))
  const rentabilidadTotal = capital * (tasaAnual / 100) * (totalDias / 365)

  const cuotas = []

  const intervalos = {
    'mensual': 1,
    'trimestral': 3,
    'semestral': 6,
    'anual': 12
  }

  const mesesIntervalo = intervalos[modalidad]
  let fecha = new Date(inicio)
  let numeroCuota = 1

  while (fecha < fin) {
    fecha.setMonth(fecha.getMonth() + mesesIntervalo)
    if (fecha > fin) fecha = new Date(fin)

    const diasCuota = mesesIntervalo * 30 // aproximación
    const montoCuota = capital * (tasaAnual / 100) * (diasCuota / 365)

    cuotas.push({
      numero_cuota: numeroCuota,
      fecha_programada: fecha.toISOString().split('T')[0],
      monto_programado: montoCuota.toFixed(2),
      estado: 'pendiente'
    })

    numeroCuota++
    if (modalidad === 'anual') break
  }

  return cuotas
}
```

---

## SECCIÓN 8: PANEL DEL CLIENTE — ESPECIFICACIONES COMPLETAS

### 8.1 Login (index.html)

**Elementos:**
- Logo Avance Corp centrado
- Campo email
- Campo contraseña con toggle mostrar/ocultar
- Botón "Ingresar"
- Link "Olvidé mi contraseña"
- Texto legal: "Acceso exclusivo para clientes y administradores de Avance Corp S.A.C."
- Footer: RUC 20611392088 | San Isidro, Lima

**Comportamiento:**
- Al hacer login exitoso → redirige según rol (cliente → dashboard.html / admin → admin/dashboard.html)
- Si sesión ya activa → redirige directamente sin mostrar login
- Error de credenciales → mensaje rojo: "Correo o contraseña incorrectos"
- Cierre de sesión por inactividad de 60 minutos

### 8.2 Dashboard Principal (dashboard.html)

**Header:**
- Logo Avance Corp izquierda
- Menú de navegación: Dashboard | Mi Inversión | Documentos | Novedades | Mercados | Mi Perfil
- Derecha: nombre del usuario + botón cerrar sesión
- Novedades: badge rojo con cantidad no leídas

**Cuatro tarjetas de métricas:**
1. Capital Invertido → monto del contrato con moneda (S/ o US$)
2. Rentabilidad Acumulada → calculada al día de hoy con fórmula de interés simple
3. Total Actual → capital + rentabilidad
4. Días Restantes → días hasta fecha_vencimiento

**Barra de progreso del contrato:**
- Título: "Progreso de tu inversión"
- Barra visual con porcentaje completado en verde
- Etiquetas: fecha inicio izquierda, fecha vencimiento derecha
- Texto: "X de Y días — Z% completado"

**Alerta de vencimiento:**
- Si quedan menos de 60 días → banner amarillo: "Tu contrato vence en X días. Contáctanos para hablar sobre la renovación."

**Mini tabla de últimas novedades:**
- Últimas 3 novedades no leídas con enlace "Ver todas"

**Estado del contrato:**
- Badge visible: ACTIVO (verde) / VENCIDO (rojo) / RENOVADO (azul)

### 8.3 Mi Inversión (inversion.html)

**Gráfico de proyección Chart.js:**
- Tipo: línea con área rellena en gradiente verde
- Eje X: meses desde inicio hasta vencimiento
- Eje Y: valores desde capital - 5% hasta capital + tasa completa
- Punto destacado en "hoy" con tooltip: "Hoy: S/ X,XXX.XX"
- Línea punteada vertical en el mes actual
- Fondo oscuro, cuadrícula sutil

**Tabla de cronograma de pagos:**
- Columnas: N° Cuota | Fecha Programada | Monto | Estado | Fecha Pago Real
- Estado con colores: Pendiente (gris) | Pagado ✅ (verde) | Vencido ⚠️ (rojo)

**Datos del contrato:**
- Número de contrato
- Entidad: Avance Corp S.A.C.
- Capital: monto + moneda
- Tasa anual: 15%
- Modalidad de pago
- Tipo de interés
- Fecha inicio / Fecha vencimiento
- Estado actual

### 8.4 Documentos (documentos.html)

**Lista de documentos disponibles:**
- Nombre del documento
- Tipo (Contrato / Estado de cuenta / Otro)
- Fecha de subida
- Botón "Descargar" → descarga directa desde Supabase Storage

**Mensaje si no hay documentos:**
- "Aún no hay documentos disponibles. Tu contrato firmado será cargado próximamente."

### 8.5 Novedades (novedades.html)

**Lista de novedades:**
- Cada novedad: fecha | título | mensaje completo
- Novedades no leídas: fondo ligeramente resaltado + punto verde
- Al abrir una novedad → marcar como leída (UPDATE en DB)
- Ordenadas de más reciente a más antigua

### 8.6 Mercados (mercados.html)

**Widgets de TradingView a implementar:**

```html
<!-- Ticker de mercados en tiempo real -->
<div class="tradingview-widget-container">
  <div class="tradingview-widget-container__widget"></div>
  <script type="text/javascript"
    src="https://s3.tradingview.com/external-embedding/embed-widget-ticker-tape.js">
  {
    "symbols": [
      {"proName": "FX:USDPEN", "title": "USD/PEN"},
      {"proName": "FX:EURUSD", "title": "EUR/USD"},
      {"proName": "TVC:GOLD", "title": "Oro"},
      {"proName": "COINBASE:BTCUSD", "title": "Bitcoin"},
      {"proName": "COINBASE:ETHUSD", "title": "Ethereum"},
      {"proName": "INDEX:S5FI", "title": "S&P 500"},
      {"proName": "NASDAQ:QQQ", "title": "NASDAQ"},
      {"proName": "BVL:SPBLPGPT", "title": "Bolsa Lima"}
    ],
    "showSymbolLogo": true,
    "colorTheme": "dark",
    "isTransparent": false,
    "displayMode": "adaptive",
    "locale": "es"
  }
  </script>
</div>

<!-- Gráfico principal interactivo -->
<div class="tradingview-widget-container">
  <div id="tradingview_chart"></div>
  <script type="text/javascript"
    src="https://s3.tradingview.com/tv.js">
  </script>
  <script>
    new TradingView.widget({
      "width": "100%",
      "height": 500,
      "symbol": "TVC:GOLD",
      "interval": "D",
      "timezone": "America/Lima",
      "theme": "dark",
      "style": "1",
      "locale": "es",
      "toolbar_bg": "#1a1a1a",
      "enable_publishing": false,
      "hide_top_toolbar": false,
      "container_id": "tradingview_chart"
    });
  </script>
</div>

<!-- Widget de noticias financieras -->
<div class="tradingview-widget-container">
  <div class="tradingview-widget-container__widget"></div>
  <script type="text/javascript"
    src="https://s3.tradingview.com/external-embedding/embed-widget-timeline.js">
  {
    "feedMode": "market",
    "market": "forex",
    "isTransparent": false,
    "displayMode": "regular",
    "width": "100%",
    "height": 400,
    "colorTheme": "dark",
    "locale": "es"
  }
  </script>
</div>
```

**Selectores de activo:**
Botones para cambiar el gráfico principal entre:
- Oro (XAU/USD)
- Dólar/Sol (USD/PEN)
- EUR/USD
- Bitcoin
- Ethereum
- S&P 500
- NASDAQ
- Bolsa de Lima (BVL)

**Nota legal obligatoria al pie:**
"La rentabilidad de tu inversión está definida contractualmente al 15% anual y no depende de la fluctuación diaria de los mercados mostrados."

### 8.7 Mi Perfil (perfil.html)

**Datos visibles (solo lectura):**
- Nombre completo
- DNI
- Correo electrónico
- Teléfono

**Acción disponible:**
- Botón "Cambiar contraseña" → formulario: contraseña actual | nueva contraseña | confirmar nueva contraseña

---

## SECCIÓN 9: PANEL DE ADMINISTRADOR — ESPECIFICACIONES COMPLETAS

### 9.1 Dashboard Admin (admin/dashboard.html)

**Métricas en tiempo real:**
- Total contratos activos
- Capital total bajo gestión en PEN (suma de todos los contratos activos en soles)
- Capital total bajo gestión en USD (suma de contratos en dólares)
- Total de clientes registrados
- Contratos próximos a vencer (próximos 30 días)
- Contratos vencidos sin renovar

**Tabla: Contratos próximos a vencer**
- Columnas: Cliente | Monto | Moneda | Fecha vencimiento | Días restantes | Acción
- Ordenada por fecha de vencimiento ascendente

**Tabla: Pagos del mes actual**
- Cuotas programadas para este mes
- Estado: pendiente / pagado

### 9.2 Gestión de Clientes (admin/clientes.html)

**Buscador:**
- Búsqueda por nombre o DNI en tiempo real

**Lista de clientes:**
- Columnas: Nombre | DNI | Correo | Teléfono | Contratos activos | Estado | Acciones

**Crear nuevo cliente:**
Formulario con campos:
- Nombre completo (requerido)
- DNI (requerido, único)
- Correo electrónico (requerido, único, será el usuario de login)
- Teléfono
- Contraseña inicial (mínimo 8 caracteres)
- Rol: cliente (por defecto)

Al guardar:
1. Crear usuario en Supabase Auth con email + contraseña
2. Insertar perfil en tabla perfiles con el UUID generado
3. Mostrar confirmación: "Cliente creado. Credenciales: [email] / [contraseña]"

**Editar cliente:**
- Modificar nombre, DNI, teléfono
- No puede modificar el correo (es el identificador de Auth)
- Puede resetear contraseña: genera nueva contraseña temporal

**Desactivar cliente:**
- Cambiar campo activo = false
- El cliente no puede hacer login
- Sus datos y contratos se conservan

**Crear admin (solo superadmin):**
- Igual que crear cliente pero con rol = 'admin'
- Solo visible para superadmin

### 9.3 Gestión de Contratos (admin/contratos.html)

**Filtros:**
- Por estado: todos | activos | vencidos | renovados | retirados
- Por moneda: todos | PEN | USD
- Por modalidad: todos | mensual | trimestral | semestral | anual
- Búsqueda por número de contrato o nombre de cliente

**Lista de contratos:**
- Columnas: N° Contrato | Cliente | Capital | Moneda | Tasa | Modalidad | Inicio | Vencimiento | Estado | Acciones

**Crear nuevo contrato:**
Formulario:
- Buscar cliente por nombre o DNI (autocomplete)
- Número de contrato (generado automáticamente: AVC-2026-XXXX)
- Capital (monto numérico)
- Moneda: PEN | USD
- Tasa anual (pre-rellenado: 15%)
- Modalidad de pago: mensual | trimestral | semestral | anual
- Tipo de interés: simple | compuesto
- Fecha de inicio
- Fecha de vencimiento

Al guardar:
1. Insertar en tabla contratos
2. Generar automáticamente el cronograma de pagos con la función generarCronograma()
3. Insertar todas las cuotas en tabla cronograma_pagos
4. Mostrar confirmación con resumen del contrato creado

**Editar contrato:**
- Solo puede editar: notas internas y estado
- No puede modificar capital, tasa, fechas ni modalidad (son datos del contrato firmado)

**Cambiar estado:**
- activo → vencido → renovado
- retirado solo accesible para superadmin

### 9.4 Registro de Pagos (admin/pagos.html)

**Filtros:**
- Por mes actual (por defecto)
- Por contrato específico
- Por estado: pendientes | pagados | vencidos

**Lista de cuotas:**
- Columnas: Cliente | N° Contrato | N° Cuota | Fecha Programada | Monto | Estado | Acción

**Registrar pago:**
Al hacer clic en "Registrar pago" de una cuota:
- Modal con: fecha real del pago (por defecto hoy) | monto pagado (pre-rellenado con monto programado)
- Al confirmar: UPDATE cronograma_pagos SET estado='pagado', fecha_pago_real=X, monto_pagado=Y

**Vista de pagos del mes:**
- Resumen: total cuotas del mes | total pagadas | total pendientes | monto total del mes

### 9.5 Novedades Admin (admin/novedades.html)

**Crear novedad:**
- Título (requerido)
- Mensaje (área de texto grande, requerido)
- Destinatario: Todos los clientes | Cliente específico (con buscador por nombre)
- Botón "Enviar"

Al enviar:
- Si destinatario = todos → INSERT con destinatario_id = NULL
- Si destinatario específico → INSERT con destinatario_id = UUID del cliente

**Historial de novedades enviadas:**
- Columnas: Fecha | Título | Destinatario | Enviado por

### 9.6 Documentos Admin (admin/documentos.html)

**Subir documento:**
- Buscar cliente/contrato
- Seleccionar archivo PDF
- Tipo: Contrato | Estado de cuenta | Otro
- Nombre del documento

Al subir:
1. Upload del PDF a Supabase Storage en bucket 'documentos' con path: `{contrato_id}/{timestamp}_{nombre_archivo}.pdf`
   > ⚠️ **Nota histórica (BD-7, auditoría 2026-06):** este documento especificaba originalmente `{cliente_id}/{contrato_id}/{nombre_archivo}.pdf`. La implementación real usa `{contrato_id}/{timestamp}_{nombre}` y la policy RLS valida `contratos.id = (storage.foldername(name))[1]::uuid AND contratos.cliente_id = auth.uid()`. La **fuente de verdad** del esquema vigente es `public_html/CLAUDE.md` §4; este archivo es la especificación inicial (histórica).
2. INSERT en tabla documentos con el storage_path
3. El archivo aparece inmediatamente disponible para el cliente

**Configuración del bucket en Supabase:**
```sql
-- Crear bucket privado
INSERT INTO storage.buckets (id, name, public)
VALUES ('documentos', 'documentos', false);

-- Política: cliente descarga solo sus documentos
CREATE POLICY "cliente_descarga_sus_docs"
ON storage.objects FOR SELECT
USING (
  bucket_id = 'documentos'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- Política: admin sube documentos
CREATE POLICY "admin_sube_docs"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'documentos'
  AND EXISTS (
    SELECT 1 FROM perfiles p
    WHERE p.id = auth.uid()
    AND p.rol IN ('admin', 'superadmin')
  )
);
```

---

## SECCIÓN 10: DISEÑO VISUAL — SISTEMA DE ESTILOS

### 10.1 Paleta de colores

```css
:root {
  /* Primarios */
  --color-primary: #1a5c2a;
  --color-primary-mid: #2d8a3e;
  --color-primary-light: #4CAF50;

  /* Fondos */
  --color-bg: #0a0a0a;
  --color-bg-card: #1a1a1a;
  --color-bg-hover: #222222;

  /* Texto */
  --color-text: #ffffff;
  --color-text-muted: #b0b0b0;

  /* Estados */
  --color-success: #4CAF50;
  --color-warning: #f0a500;
  --color-danger: #e53935;
  --color-info: #2196F3;

  /* Bordes */
  --color-border: #2a2a2a;
  --color-border-green: rgba(45, 138, 62, 0.3);
}
```

### 10.2 Tipografía

```css
body {
  font-family: 'Inter', 'Segoe UI', system-ui, sans-serif;
  font-size: 14px;
  line-height: 1.5;
  color: var(--color-text);
  background-color: var(--color-bg);
}

h1 { font-size: 24px; font-weight: 700; }
h2 { font-size: 20px; font-weight: 600; }
h3 { font-size: 16px; font-weight: 600; }
.metric-value { font-size: 28px; font-weight: 700; }
.label { font-size: 12px; color: var(--color-text-muted); }
```

### 10.3 Componentes base

```css
/* Tarjeta */
.card {
  background: var(--color-bg-card);
  border: 1px solid var(--color-border);
  border-radius: 12px;
  padding: 20px;
  transition: border-color 0.2s;
}
.card:hover { border-color: var(--color-border-green); }

/* Botón primario */
.btn-primary {
  background: var(--color-primary-mid);
  color: white;
  border: none;
  border-radius: 8px;
  padding: 10px 20px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  transition: background 0.2s;
}
.btn-primary:hover { background: var(--color-primary-light); }

/* Badge de estado */
.badge-activo { background: rgba(76,175,80,0.15); color: #4CAF50; }
.badge-vencido { background: rgba(229,57,53,0.15); color: #e53935; }
.badge-renovado { background: rgba(33,150,243,0.15); color: #2196F3; }

/* Sidebar */
.sidebar {
  width: 240px;
  background: var(--color-bg-card);
  border-right: 1px solid var(--color-border);
  height: 100vh;
  position: fixed;
  left: 0; top: 0;
}

/* Contenido principal */
.main-content {
  margin-left: 240px;
  padding: 24px;
  min-height: 100vh;
}
```

---

## SECCIÓN 11: PLAN DE IMPLEMENTACIÓN POR FASES

### FASE 0 — Configuración de Supabase (Día 1)

**Paso 1:** Crear proyecto en Supabase Pro
- Ir a supabase.com → New project
- Nombre: portal-avance-corp
- Región: us-east-1 (más cercana a Perú)
- Guardar URL y anon key

**Paso 2:** Ejecutar el SQL completo
- Ir a SQL Editor en Supabase
- Ejecutar todas las tablas de la Sección 4
- Ejecutar todos los índices de la Sección 4.6
- Ejecutar todo el RLS de la Sección 5

**Paso 3:** Crear el superusuario
- Authentication → Users → Add user
- Email: correo del superadmin
- Password: contraseña segura
- Copiar el UUID generado
- Ejecutar el INSERT de perfil con rol 'superadmin' de la Sección 6.4

**Paso 4:** Configurar Storage
- Storage → New bucket → nombre: 'documentos' → private
- Ejecutar las políticas de storage de la Sección 9.6

**Paso 5:** Verificar configuración Auth
- Authentication → Settings → aplicar configuración de la Sección 6.1

---

### FASE 1 — Login y estructura base (Días 2-5)

**Paso 6:** Crear index.html (login)
- Diseño oscuro con logo Avance Corp centrado
- Formulario email + contraseña
- Implementar lógica de auth.js
- Redirección por rol al hacer login exitoso
- Manejo de errores con mensajes claros

**Paso 7:** Crear layout base del cliente
- Sidebar fijo con navegación de 6 items
- Header con nombre de usuario y logout
- Estructura responsive

**Paso 8:** Crear layout base del admin
- Sidebar fijo con navegación de 6 items admin
- Header con nombre, rol y logout
- Estructura responsive

**Paso 9:** Protección de rutas
- Cada página verifica sesión activa al cargar
- Páginas de cliente verifican rol = 'cliente'
- Páginas de admin verifican rol IN ('admin', 'superadmin')
- Redirect automático si no cumple condición

---

### FASE 2 — Dashboard del cliente (Días 6-10)

**Paso 10:** Cargar datos del contrato activo
- Query a contratos WHERE cliente_id = auth.uid() AND estado = 'activo'
- Si no hay contrato activo → mostrar mensaje informativo

**Paso 11:** Implementar cálculos de rentabilidad
- Usar funciones de la Sección 7
- Actualizar cada 60 segundos (setInterval)

**Paso 12:** Renderizar las 4 tarjetas de métricas
- Con animación de contador al cargar

**Paso 13:** Implementar barra de progreso
- Cálculo de porcentaje con fechas reales

**Paso 14:** Implementar alerta de vencimiento
- Condicional: si días restantes < 60

**Paso 15:** Mini lista de novedades no leídas

---

### FASE 3 — Panel Mi Inversión (Días 11-15)

**Paso 16:** Implementar gráfico Chart.js
- Cargar datos reales del contrato
- Generar puntos de proyección mes a mes
- Marcar punto actual
- Tooltip personalizado con moneda correcta

**Paso 17:** Renderizar cronograma de pagos
- Query a cronograma_pagos WHERE contrato_id = X
- Tabla con estados y colores

**Paso 18:** Mostrar datos completos del contrato
- Todos los campos del contrato formateados

---

### FASE 4 — Documentos y Novedades (Días 16-20)

**Paso 19:** Panel Documentos
- Query a documentos JOIN contratos WHERE cliente_id = auth.uid()
- Botón de descarga con URL firmada de Supabase Storage:
```javascript
const { data } = await supabase.storage
  .from('documentos')
  .createSignedUrl(documento.storage_path, 3600)
window.open(data.signedUrl)
```

**Paso 20:** Panel Novedades
- Query a novedades WHERE destinatario_id = auth.uid() OR destinatario_id IS NULL
- Ordenar por creado_en DESC
- Marcar como leído al abrir
- Badge con cantidad no leídas en el menú

---

### FASE 5 — Panel Mercados (Días 21-23)

**Paso 21:** Implementar ticker tape de TradingView
- Código de la Sección 8.6

**Paso 22:** Implementar gráfico principal interactivo
- Selector de activo con botones
- Cambio dinámico del símbolo en el widget

**Paso 23:** Implementar widget de noticias financieras
- Feed de noticias forex y commodities

**Paso 24:** Agregar nota legal al pie de la sección

---

### FASE 6 — Panel Admin completo (Días 24-35)

**Paso 25:** Dashboard admin con métricas
- Queries agregadas para totales
- Tablas de contratos próximos a vencer
- Tabla de pagos del mes

**Paso 26:** CRUD de clientes
- Lista con búsqueda en tiempo real
- Formulario crear cliente (Auth + perfiles)
- Editar cliente
- Desactivar cliente
- Crear admin (solo para superadmin)

**Paso 27:** CRUD de contratos
- Lista con filtros múltiples
- Formulario crear contrato con generación automática de cronograma
- Editar estado y notas

**Paso 28:** Registro de pagos
- Vista de cuotas del mes
- Modal de registro de pago
- Actualización de estado en tiempo real

**Paso 29:** Sistema de novedades
- Formulario con destinatario flexible
- Historial de enviados

**Paso 30:** Gestión de documentos
- Upload de PDF a Supabase Storage
- Registro en tabla documentos
- Disponibilidad inmediata para el cliente

---

### FASE 7 — Mi Perfil y ajustes finales (Días 36-40)

**Paso 31:** Panel Mi Perfil
- Mostrar datos del usuario
- Formulario cambio de contraseña:
```javascript
const { error } = await supabase.auth.updateUser({
  password: nuevaContraseña
})
```

**Paso 32:** Optimización mobile
- Sidebar colapsable en pantallas < 768px
- Menú hamburguesa
- Tarjetas en columna única en mobile
- Tablas con scroll horizontal

**Paso 33:** Footer legal global
- Texto: "Los valores mostrados corresponden a la proyección contractual pactada. No constituyen garantía de resultados de mercado. Avance Corp S.A.C. RUC 20611392088"
- Candado SSL

**Paso 34:** Pruebas completas
- Crear 3 clientes de prueba
- Crear contratos en PEN y USD con todas las modalidades
- Verificar cálculos de rentabilidad
- Verificar cronogramas generados
- Verificar RLS (que un cliente no puede ver datos de otro)
- Probar upload y descarga de documentos
- Probar todas las vistas en mobile

---

### FASE 8 — Despliegue en Hostinger (Días 41-45)

**Paso 35:** Subir todos los archivos a Hostinger via FTP o File Manager

**Paso 36:** Configurar subdominio en panel de Hostinger
- Crear subdominio: portal.avancecorp.pe (o el que corresponda)
- Apuntar al directorio del portal

**Paso 37:** Activar SSL en Hostinger
- Panel de control → SSL → Let's Encrypt → Activar para el subdominio

**Paso 38:** Verificar que las URLs de Supabase estén correctas en producción

**Paso 39:** Prueba final en producción con clientes reales seleccionados

**Paso 40:** Capacitación al admin sobre el uso del panel

---

## SECCIÓN 12: FUNCIONALIDADES ADICIONALES RECOMENDADAS

### 12.1 Número de contrato automático

```javascript
async function generarNumeroContrato() {
  const año = new Date().getFullYear()
  const { count } = await supabase
    .from('contratos')
    .select('*', { count: 'exact' })
  const numero = String(count + 1).padStart(4, '0')
  return `AVC-${año}-${numero}`
}
```

### 12.2 Exportar lista de contratos a CSV (para el admin)

```javascript
function exportarCSV(datos) {
  const headers = ['N° Contrato', 'Cliente', 'Capital', 'Moneda', 'Inicio', 'Vencimiento', 'Estado']
  const filas = datos.map(c => [
    c.numero_contrato, c.cliente_nombre, c.capital,
    c.moneda, c.fecha_inicio, c.fecha_vencimiento, c.estado
  ])
  const csv = [headers, ...filas].map(f => f.join(',')).join('\n')
  const blob = new Blob([csv], { type: 'text/csv' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `contratos_avance_corp_${new Date().toISOString().split('T')[0]}.csv`
  a.click()
}
```

### 12.3 Búsqueda en tiempo real

```javascript
// Para listas de clientes y contratos
document.getElementById('buscador').addEventListener('input', async (e) => {
  const termino = e.target.value.trim()
  if (termino.length < 2) return

  const { data } = await supabase
    .from('perfiles')
    .select('*')
    .or(`nombre_completo.ilike.%${termino}%,dni.ilike.%${termino}%`)
    .eq('rol', 'cliente')

  renderizarClientes(data)
})
```

---

## SECCIÓN 13: CHECKLIST FINAL ANTES DE LANZAR

- [ ] Todas las tablas creadas en Supabase
- [ ] Todos los índices creados
- [ ] RLS activado en todas las tablas
- [ ] Todas las políticas RLS funcionando
- [ ] Bucket de Storage configurado con políticas
- [ ] Superusuario creado y puede hacer login
- [ ] Login redirige correctamente según rol
- [ ] Dashboard cliente muestra datos reales
- [ ] Cálculo de rentabilidad verificado con calculadora manual
- [ ] Cronograma generado correctamente para todas las modalidades
- [ ] Gráfico Chart.js funcionando con datos reales
- [ ] Widgets TradingView cargando correctamente
- [ ] Documentos se pueden subir y descargar
- [ ] Novedades se envían y aparecen en el cliente
- [ ] Pagos se pueden registrar y el estado se actualiza
- [ ] Un cliente NO puede ver datos de otro cliente (verificar manualmente)
- [ ] El portal se ve correctamente en mobile
- [ ] SSL activo en el subdominio
- [ ] Footer legal visible en todas las páginas
- [ ] Prueba con 3 clientes reales completada
- [ ] Admin puede crear clientes sin problemas
- [ ] Superadmin puede crear admins

---

*Documento generado en abril 2026 para el desarrollo del Portal Digital de Inversiones de Avance Corp S.A.C. — Grupo MasCapital.*
