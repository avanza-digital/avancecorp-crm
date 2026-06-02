# AWS Fintech Stack — Referencia Técnica
> Documento de referencia sobre el stack que utilizan fintechs y bancos en producción.
> Uso: contexto de arquitectura futura para escalar más allá de Supabase.

---

## Stack completo

```
Usuario → CloudFront → S3 (frontend) → API Gateway → Lambda → Aurora PostgreSQL
                                                          ↓
                                                       Cognito (Auth)
                                                       S3 (archivos)
                                                       SES (emails)
                                                       KMS (encriptación)
```

---

## Componentes y su rol

### Aurora PostgreSQL
- PostgreSQL reescrito por Amazon para alta disponibilidad.
- Replica automáticamente en 3 zonas geográficas simultáneas.
- Failover automático en menos de 30 segundos si un nodo cae.
- Escala de 2 GB a 128 TB sin intervención manual.
- Soporta hasta 15 réplicas de lectura en paralelo.
- Usado por: Nubank, Bancolombia, fintechs reguladas en LATAM.

### Amazon Cognito
- Servicio de autenticación y gestión de usuarios.
- Maneja login, tokens JWT, MFA, sesiones y refresh tokens.
- Escala a millones de usuarios sin configuración adicional.
- Reemplaza: Supabase Auth.

### Amazon S3
- Storage de archivos con durabilidad de 99.999999999% (11 nueves).
- Cada archivo existe en múltiples datacenters simultáneamente.
- Usado para: PDFs de contratos, documentos de clientes, backups.
- Reemplaza: Supabase Storage.

### AWS Lambda
- Lógica de negocio como funciones independientes (serverless).
- Solo se paga cuando se ejecuta, no por servidor encendido.
- Cada función tiene una responsabilidad: procesar pago, generar PDF, enviar email.
- Reemplaza: lógica en Edge Functions de Supabase.

### API Gateway
- Portón de entrada a todas las funciones Lambda.
- Controla autenticación de requests, rate limiting y rutas.
- Reemplaza: endpoints directos de Supabase / PostgREST.

### CloudFront
- CDN global de Amazon.
- Sirve el frontend desde el servidor más cercano al usuario.
- Reduce latencia para usuarios en Lima, Bogotá, Madrid, etc.
- Reemplaza: hosting estático en Hostinger.

### KMS (Key Management Service)
- Gestión de llaves de encriptación para datos sensibles.
- Llaves rotan automáticamente según política configurada.
- Aplica a: DNIs, saldos, contratos, datos bancarios.
- Requerido por reguladores financieros como la SBS en Perú.

### SES (Simple Email Service)
- Emails transaccionales a escala masiva.
- Gestión de reputación de dominio gestionada por Amazon.
- Capacidad: millones de emails por día.
- Reemplaza: Resend.

### CloudTrail
- Registro de auditoría completo de toda actividad en AWS.
- Registra: quién accedió a qué dato, cuándo, desde dónde.
- Requerido por reguladores (SBS, SMV) para auditorías.
- No tiene equivalente directo en Supabase a este nivel.

---

## Por qué lo usan los bancos — 3 razones regulatorias

**1. Auditoría total**
CloudTrail genera un log inmutable de toda actividad. Cualquier regulador puede pedir ese historial y existe. Crítico para cumplimiento con SBS en Perú.

**2. Residencia de datos**
Se puede forzar que todos los datos residan en una región específica (`sa-east-1` = São Paulo, la más cercana a Lima). Reguladores financieros exigen saber físicamente dónde están los datos de clientes.

**3. Compliance certificado**
AWS tiene certificaciones: SOC 2, PCI DSS, ISO 27001. En auditorías de la SBS, operar sobre AWS simplifica enormemente la conversación regulatoria.

---

## Comparación vs Supabase

| Aspecto | Supabase Pro | AWS Stack |
|---|---|---|
| Tiempo para arrancar | 1 día | 2–4 semanas |
| Curva de aprendizaje | Baja | Alta |
| Costo mensual base | ~$25 | $200–$500+ |
| Mantenimiento | Casi cero | Requiere atención continua |
| Todo integrado out-of-the-box | ✅ | Armar pieza por pieza |
| Nivel enterprise / regulatorio | Medio | Total |
| Auditoría regulatoria (SBS) | Limitada | Completa |
| Failover automático | Parcial | Total (multi-AZ) |

---

## Ruta de migración recomendada (por etapas)

### Etapa 1 — Hoy (hasta ~20,000 clientes)
- Stack: Supabase Pro + Hostinger + Resend
- Justificación: velocidad de desarrollo, costo controlado, suficiente para el volumen actual

### Etapa 2 — Escala media (~20,000 clientes o auditoría SBS)
- Migrar DB a Aurora PostgreSQL
- Migrar Storage a S3
- Mantener Auth en Supabase o mover a Cognito
- Mantener frontend en Hostinger o mover a CloudFront + S3

### Etapa 3 — Fintech regulada formalmente
- Stack AWS completo
- Lambda + API Gateway para toda la lógica de negocio
- CloudTrail activo para auditoría regulatoria
- KMS para encriptación de datos sensibles
- SES para emails transaccionales

---

## Nota importante
Supabase internamente corre sobre AWS (instancias EC2 + RDS). La diferencia es quién administra la complejidad: hoy Supabase la absorbe. En etapa 3, se toma ese control directamente a cambio de mayor poder y compliance regulatorio.

---

*Referencia generada: Mayo 2026 — Para uso interno como contexto de arquitectura futura.*
