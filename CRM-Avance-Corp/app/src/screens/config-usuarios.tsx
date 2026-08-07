import { useMemo, useState, type FormEvent } from 'react'
import {
  KeyRound,
  Pencil,
  Plus,
  RefreshCw,
  Search,
  Shield,
  ToggleLeft,
  UserRoundCog,
  Users,
} from 'lucide-react'
import { toast } from 'sonner'
import { ConfiguracionShell } from '@/components/config/configuracion-shell'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import {
  Dialog,
  DialogBody,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import {
  useActualizarJerarquiaUsuario,
  useActualizarUsuarioAdministrable,
  useAsignarRolUsuario,
  useCatalogoUsuariosAdministrables,
  useCrearCandidatoUsuario,
  useEnviarRecuperacionUsuario,
  useFijarMembresiaUsuario,
  useImpactoDesactivacionUsuario,
  useUsuariosAdministrables,
} from '@/data/crm-config-queries'
import { mensajeDeError } from '@/data/crm-api'
import { useAuth } from '@/lib/auth-context'
import {
  TIPOS_DOCUMENTO,
  TIPOS_DOCUMENTO_K,
  validarDocumento,
  type TipoDocumento,
} from '@/lib/documento'
import { fechaHora } from '@/lib/format'
import {
  ROL_LABEL,
  ROLES,
  puedeAdministrarRolesCrm,
  puedeAdministrarUsuariosCrm,
  puedeOrganizarJerarquiaCrm,
  type Rol,
} from '@/lib/roles'
import type {
  ImpactoDesactivacionUsuario,
  UsuarioAdministrable,
} from '@/lib/usuarios-config'

const TAMANO_PAGINA = 25

function identificadorAuditoria(perfilId: string): string {
  return `Usuario CRM · ${perfilId.replaceAll('-', '').slice(-8).toUpperCase()}`
}

const ESTADO_USUARIO = {
  pendiente_rol: { label: 'Pendiente de rol', color: 'var(--warning)' },
  inactivo_crm: { label: 'Inactivo en CRM', color: 'var(--muted-foreground)' },
  activo: { label: 'Activo', color: 'var(--success)' },
  suspendido_portal: { label: 'Suspendido en Portal', color: 'var(--destructive)' },
} as const

interface FormularioPersona {
  correo: string
  nombre: string
  tipoDocumento: TipoDocumento
  documento: string
  telefono: string
  whatsapp: string
  cargo: string
}

const PERSONA_VACIA: FormularioPersona = {
  correo: '',
  nombre: '',
  tipoDocumento: 'DNI',
  documento: '',
  telefono: '',
  whatsapp: '',
  cargo: '',
}

type Modal =
  | { tipo: 'crear' }
  | { tipo: 'editar'; usuario: UsuarioAdministrable }
  | { tipo: 'rol'; usuario: UsuarioAdministrable }
  | { tipo: 'jerarquia'; usuario: UsuarioAdministrable }
  | { tipo: 'membresia'; usuario: UsuarioAdministrable; impacto: ImpactoDesactivacionUsuario | null }
  | { tipo: 'recuperacion'; usuario: UsuarioAdministrable }
  | null

function formularioDe(usuario: UsuarioAdministrable): FormularioPersona {
  return {
    correo: usuario.correo ?? '',
    nombre: usuario.nombre_completo,
    tipoDocumento: TIPOS_DOCUMENTO_K.includes(usuario.tipo_documento as TipoDocumento)
      ? usuario.tipo_documento as TipoDocumento
      : 'DNI',
    documento: usuario.documento ?? '',
    telefono: usuario.telefono ?? '',
    whatsapp: usuario.whatsapp ?? '',
    cargo: usuario.cargo ?? '',
  }
}

function validarPersona(formulario: FormularioPersona, requiereCorreo: boolean): string | null {
  if (formulario.nombre.trim().length < 2 || formulario.nombre.trim().length > 160) {
    return 'El nombre completo debe tener entre 2 y 160 caracteres.'
  }
  if (requiereCorreo && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(formulario.correo.trim())) {
    return 'Ingresa un correo válido.'
  }
  const documento = validarDocumento(formulario.tipoDocumento, formulario.documento)
  if (!documento.ok) return documento.error
  for (const [nombre, valor] of [['Teléfono', formulario.telefono], ['WhatsApp', formulario.whatsapp]] as const) {
    if (valor.trim() && (valor.trim().length < 7 || valor.trim().length > 30)) {
      return `${nombre} debe tener entre 7 y 30 caracteres.`
    }
  }
  if (formulario.cargo.trim().length > 120) return 'El cargo no puede superar 120 caracteres.'
  return null
}

function CamposPersona({
  valor,
  onChange,
  correoEditable,
  disabled,
}: {
  valor: FormularioPersona
  onChange: (siguiente: FormularioPersona) => void
  correoEditable: boolean
  disabled: boolean
}) {
  const cambiar = <K extends keyof FormularioPersona>(campo: K, dato: FormularioPersona[K]) => {
    onChange({ ...valor, [campo]: dato })
  }
  const regla = TIPOS_DOCUMENTO[valor.tipoDocumento]
  return (
    <div className="grid gap-4 sm:grid-cols-2">
      <div className="sm:col-span-2">
        <Label htmlFor="usuario-nombre">Nombre completo</Label>
        <Input id="usuario-nombre" value={valor.nombre} maxLength={160} disabled={disabled} onChange={(e) => cambiar('nombre', e.target.value)} className="mt-1" autoComplete="name" />
      </div>
      <div className="sm:col-span-2">
        <Label htmlFor="usuario-correo">Correo</Label>
        <Input id="usuario-correo" type="email" value={valor.correo} maxLength={254} disabled={disabled || !correoEditable} onChange={(e) => cambiar('correo', e.target.value)} className="mt-1" autoComplete="email" />
        {!correoEditable && <p className="mt-1 text-[10px] text-muted-foreground">El correo pertenece a la identidad de acceso y no se cambia desde el CRM.</p>}
      </div>
      <div>
        <Label htmlFor="usuario-tipo-documento">Tipo de documento</Label>
        <Select id="usuario-tipo-documento" value={valor.tipoDocumento} disabled={disabled} onChange={(e) => cambiar('tipoDocumento', e.target.value as TipoDocumento)} className="mt-1">
          {TIPOS_DOCUMENTO_K.map((tipo) => <option key={tipo} value={tipo}>{TIPOS_DOCUMENTO[tipo].etiqueta}</option>)}
        </Select>
      </div>
      <div>
        <Label htmlFor="usuario-documento">Documento</Label>
        <Input id="usuario-documento" value={valor.documento} maxLength={12} inputMode={regla.inputmode} placeholder={regla.placeholder} disabled={disabled} onChange={(e) => cambiar('documento', regla.mayusculas ? e.target.value.toUpperCase() : e.target.value)} className="mt-1" />
        <p className="mt-1 text-[10px] text-muted-foreground">{regla.regla}</p>
      </div>
      <div>
        <Label htmlFor="usuario-telefono">Teléfono</Label>
        <Input id="usuario-telefono" value={valor.telefono} maxLength={30} disabled={disabled} onChange={(e) => cambiar('telefono', e.target.value)} className="mt-1" inputMode="tel" autoComplete="tel" />
      </div>
      <div>
        <Label htmlFor="usuario-whatsapp">WhatsApp</Label>
        <Input id="usuario-whatsapp" value={valor.whatsapp} maxLength={30} disabled={disabled} onChange={(e) => cambiar('whatsapp', e.target.value)} className="mt-1" inputMode="tel" />
      </div>
      <div className="sm:col-span-2">
        <Label htmlFor="usuario-cargo">Cargo</Label>
        <Input id="usuario-cargo" value={valor.cargo} maxLength={120} disabled={disabled} onChange={(e) => cambiar('cargo', e.target.value)} className="mt-1" />
      </div>
    </div>
  )
}

function ResumenImpacto({ impacto }: { impacto: ImpactoDesactivacionUsuario }) {
  const items = [
    ['Subordinados activos', impacto.subordinados_activos],
    ['Leads asignados', impacto.leads_abiertos],
    ['Leads en bandeja', impacto.leads_en_bandeja],
    ['Tareas pendientes', impacto.tareas_pendientes],
    ['Clientes activos', impacto.clientes_activos],
  ] as const
  return (
    <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
      {items.map(([label, numero]) => (
        <div key={label} className="rounded-lg border border-border bg-muted/30 px-3 py-2">
          <p className="text-lg font-extrabold tabular-nums text-primary">{numero}</p>
          <p className="text-[10px] text-muted-foreground">{label}</p>
        </div>
      ))}
    </div>
  )
}

function motivoBloqueoActivacion(usuario: UsuarioAdministrable): string | null {
  if (!usuario.activo_portal) {
    return 'El perfil del Portal está suspendido. Debe reactivarse allí antes de habilitar el CRM.'
  }
  if (usuario.rol_crm == null) {
    return 'Superadmin debe asignar primero un rol CRM.'
  }
  if (usuario.rol_crm === 'vendedor' && usuario.supervisor_id == null) {
    return 'Asigna un Supervisor activo antes de habilitar a este vendedor.'
  }
  return null
}

export function ConfigUsuarios() {
  const { yo } = useAuth()
  // La demo es una fotografía explorable: ninguna capacidad de Gerencia se
  // convierte en una escritura ficticia ni llega por accidente al backend.
  const sesionReal = Boolean(yo && !yo.demo)
  const administraPersonas = sesionReal && puedeAdministrarUsuariosCrm(yo)
  const administraRoles = sesionReal && puedeAdministrarRolesCrm(yo)
  const administraJerarquia = sesionReal && puedeOrganizarJerarquiaCrm(yo)
  const auditaDirectorio = sesionReal
    && yo?.rol === 'directorio'
    && !administraPersonas
    && !administraRoles
  const [busqueda, setBusqueda] = useState('')
  const [filtro, setFiltro] = useState('')
  const [pagina, setPagina] = useState(0)
  const consulta = useUsuariosAdministrables(filtro, TAMANO_PAGINA, pagina * TAMANO_PAGINA)
  const catalogo = useCatalogoUsuariosAdministrables(administraPersonas)
  const crear = useCrearCandidatoUsuario()
  const editar = useActualizarUsuarioAdministrable()
  const asignarRol = useAsignarRolUsuario()
  const jerarquia = useActualizarJerarquiaUsuario()
  const impacto = useImpactoDesactivacionUsuario()
  const membresia = useFijarMembresiaUsuario()
  const recuperacion = useEnviarRecuperacionUsuario()
  const [modal, setModal] = useState<Modal>(null)
  const [persona, setPersona] = useState<FormularioPersona>(PERSONA_VACIA)
  const [rol, setRol] = useState<Rol>('vendedor')
  const [supervisorId, setSupervisorId] = useState('')
  const [reemplazoId, setReemplazoId] = useState('')

  const filas = consulta.data ?? []
  const total = filas[0]?.total ?? (pagina === 0 ? filas.length : 0)
  const paginas = Math.max(1, Math.ceil(total / TAMANO_PAGINA))
  const ocupada = crear.isPending || editar.isPending || asignarRol.isPending
    || jerarquia.isPending || membresia.isPending || recuperacion.isPending

  const opcionesJerarquia = useMemo(() => {
    if (modal?.tipo !== 'jerarquia') return []
    const rolesPermitidos = modal.usuario.rol_crm === 'vendedor'
      ? new Set<Rol>(['supervisor'])
      : modal.usuario.rol_crm === 'supervisor'
        ? new Set<Rol>(['supervisor', 'gerencia'])
        : new Set<Rol>()
    return (catalogo.data ?? []).filter((usuario) =>
      usuario.perfil_id !== modal.usuario.perfil_id
        && usuario.activo_crm
        && usuario.activo_portal
        && usuario.rol_crm != null
        && rolesPermitidos.has(usuario.rol_crm))
  }, [catalogo.data, modal])

  const abrirCrear = () => {
    setPersona(PERSONA_VACIA)
    setModal({ tipo: 'crear' })
  }
  const abrirEditar = (usuario: UsuarioAdministrable) => {
    setPersona(formularioDe(usuario))
    setModal({ tipo: 'editar', usuario })
  }
  const abrirRol = (usuario: UsuarioAdministrable) => {
    setRol(usuario.rol_crm ?? 'vendedor')
    setModal({ tipo: 'rol', usuario })
  }
  const abrirJerarquia = (usuario: UsuarioAdministrable) => {
    const admiteSupervisor = usuario.rol_crm === 'vendedor' || usuario.rol_crm === 'supervisor'
    setSupervisorId(admiteSupervisor ? usuario.supervisor_id ?? '' : '')
    setModal({ tipo: 'jerarquia', usuario })
  }

  const abrirMembresia = async (usuario: UsuarioAdministrable) => {
    if (usuario.activo_crm !== true) {
      setReemplazoId('')
      setModal({ tipo: 'membresia', usuario, impacto: null })
      return
    }
    try {
      const resultado = await impacto.mutateAsync(usuario.perfil_id)
      setReemplazoId('')
      setModal({ tipo: 'membresia', usuario, impacto: resultado })
    } catch (error) {
      toast.error(mensajeDeError(error, 'No se pudo evaluar la desactivación.'))
    }
  }

  const enviarBusqueda = (evento: FormEvent) => {
    evento.preventDefault()
    setPagina(0)
    setFiltro(busqueda.trim())
  }

  const guardarPersona = async () => {
    const esAlta = modal?.tipo === 'crear'
    if (!esAlta && modal?.tipo !== 'editar') return
    const error = validarPersona(persona, esAlta)
    if (error) {
      toast.error(error)
      return
    }
    const documento = validarDocumento(persona.tipoDocumento, persona.documento)
    if (!documento.ok) return
    try {
      if (esAlta) {
        const resultado = await crear.mutateAsync({
          correo: persona.correo.trim().toLowerCase(),
          nombre_completo: persona.nombre.trim(),
          tipo_documento: persona.tipoDocumento,
          documento: documento.valor,
          telefono: persona.telefono.trim() || undefined,
          whatsapp: persona.whatsapp.trim() || undefined,
          cargo: persona.cargo.trim() || undefined,
        })
        toast.success(resultado.estado === 'candidato_existente'
          ? 'La identidad ya existía y quedó disponible en el directorio.'
          : resultado.recuperacion_enviada
            ? 'Usuario creado. Se envió el correo para definir su acceso.'
            : 'Usuario creado pendiente de rol; el correo de acceso deberá reenviarse.')
      } else {
        if (!modal.usuario.version_perfil) {
          toast.error('Recarga el directorio antes de editar este usuario.')
          return
        }
        await editar.mutateAsync({
          perfil_id: modal.usuario.perfil_id,
          nombre_completo: persona.nombre.trim(),
          tipo_documento: persona.tipoDocumento,
          documento: documento.valor,
          telefono: persona.telefono.trim() || null,
          whatsapp: persona.whatsapp.trim() || null,
          cargo: persona.cargo.trim() || null,
          version_perfil: modal.usuario.version_perfil,
        })
        toast.success('Datos del usuario actualizados.')
      }
      setModal(null)
    } catch (fallo) {
      toast.error(mensajeDeError(fallo, esAlta ? 'No se pudo crear el usuario.' : 'No se pudo actualizar el usuario.'))
    }
  }

  const guardarRol = async () => {
    if (modal?.tipo !== 'rol') return
    try {
      await asignarRol.mutateAsync({
        perfilId: modal.usuario.perfil_id,
        rol,
        versionEquipo: modal.usuario.version_equipo,
      })
      toast.success(modal.usuario.rol_crm ? 'Rol CRM actualizado.' : 'Rol CRM asignado; Gerencia debe completar jerarquía y activación.')
      setModal(null)
    } catch (error) {
      toast.error(mensajeDeError(error, 'No se pudo asignar el rol.'))
    }
  }

  const guardarJerarquia = async () => {
    if (modal?.tipo !== 'jerarquia' || !modal.usuario.version_equipo) return
    if (supervisorId && !opcionesJerarquia.some((usuario) => usuario.perfil_id === supervisorId)) {
      toast.error('Selecciona un supervisor activo y compatible con el rol del usuario.')
      return
    }
    try {
      await jerarquia.mutateAsync({
        perfilId: modal.usuario.perfil_id,
        supervisorId: supervisorId || null,
        versionEquipo: modal.usuario.version_equipo,
      })
      toast.success('Jerarquía actualizada.')
      setModal(null)
    } catch (error) {
      toast.error(mensajeDeError(error, 'No se pudo actualizar la jerarquía.'))
    }
  }

  const guardarMembresia = async () => {
    if (modal?.tipo !== 'membresia' || !modal.usuario.version_equipo) return
    const activar = modal.usuario.activo_crm !== true
    const bloqueo = activar ? motivoBloqueoActivacion(modal.usuario) : null
    if (bloqueo) {
      toast.error(bloqueo)
      return
    }
    if (!activar && modal.impacto?.requiere_reemplazo && !reemplazoId) {
      toast.error('Selecciona un reemplazo para transferir todas las responsabilidades.')
      return
    }
    try {
      await membresia.mutateAsync({
        perfilId: modal.usuario.perfil_id,
        activo: activar,
        reemplazoId: activar ? null : reemplazoId || null,
        versionEquipo: modal.usuario.version_equipo,
      })
      toast.success(activar ? 'Membresía CRM activada.' : 'Membresía desactivada y responsabilidades transferidas.')
      setModal(null)
    } catch (error) {
      toast.error(mensajeDeError(error, activar ? 'No se pudo activar la membresía.' : 'No se pudo desactivar la membresía.'))
    }
  }

  const enviarRecuperacion = async () => {
    if (modal?.tipo !== 'recuperacion') return
    try {
      await recuperacion.mutateAsync(modal.usuario.perfil_id)
      toast.success('Correo de recuperación enviado.')
      setModal(null)
    } catch (error) {
      toast.error(mensajeDeError(error, 'No se pudo enviar la recuperación.'))
    }
  }

  const reemplazos = modal?.tipo === 'membresia'
    ? (catalogo.data ?? []).filter((usuario) =>
      usuario.perfil_id !== modal.usuario.perfil_id
        && usuario.activo_crm
        && usuario.activo_portal
        && usuario.rol_crm === modal.usuario.rol_crm)
    : []
  const bloqueoActivacion = modal?.tipo === 'membresia' && !modal.usuario.activo_crm
    ? motivoBloqueoActivacion(modal.usuario)
    : null

  return (
    <ConfiguracionShell
      icono={Users}
      titulo="Usuarios y jerarquía"
      descripcion="Gerencia administra personas, membresías y estructura. Superadmin asigna roles; Directorio audita una vista redactada."
      soloLectura={!administraPersonas && !administraRoles}
      estado={{
        etiqueta: `${total} usuarios`,
        detalle: administraRoles && !administraPersonas
          ? 'Vista mínima autorizada para gobierno de roles.'
          : auditaDirectorio
            ? 'Auditoría redactada: sin PII, jerarquía ni acciones.'
            : 'Directorio operativo del CRM.',
      }}
      acciones={administraPersonas ? <Button size="sm" onClick={abrirCrear}><Plus aria-hidden /> Nuevo usuario</Button> : undefined}
    >
      <Card>
        <CardContent className="py-4">
          <form className="flex flex-col gap-2 sm:flex-row" onSubmit={enviarBusqueda} role="search">
            <div className="relative min-w-0 flex-1">
              <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
              <Input aria-label="Buscar usuarios" value={busqueda} onChange={(e) => setBusqueda(e.target.value)} placeholder={administraPersonas ? 'Buscar por nombre, correo o documento' : auditaDirectorio ? 'Buscar por identificador, rol o estado' : 'Buscar por nombre'} maxLength={80} className="pl-9" />
            </div>
            <Button type="submit" variant="outline">Buscar</Button>
          </form>
        </CardContent>
      </Card>

      {consulta.isPending && <Card><CardContent className="py-10 text-center text-sm text-muted-foreground" role="status">Cargando el directorio autorizado…</CardContent></Card>}
      {consulta.isError && (
        <Card><CardContent className="flex flex-col items-center gap-3 py-10 text-center">
          <p className="text-sm font-semibold text-destructive">{mensajeDeError(consulta.error, 'No se pudo cargar el directorio.')}</p>
          <Button variant="outline" size="sm" onClick={() => void consulta.refetch()}><RefreshCw aria-hidden /> Reintentar</Button>
        </CardContent></Card>
      )}
      {consulta.isSuccess && filas.length === 0 && (
        <Card><CardContent className="py-10 text-center text-sm text-muted-foreground">No hay usuarios que coincidan con la búsqueda.</CardContent></Card>
      )}

      {filas.length > 0 && (
        <Card className="overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full min-w-[820px] text-left text-xs">
              <thead className="bg-muted/35 text-[10px] font-extrabold uppercase tracking-[0.08em] text-muted-foreground">
                <tr><th className="px-4 py-3">{auditaDirectorio ? 'Identificador' : 'Persona'}</th><th className="px-4 py-3">Rol</th><th className="px-4 py-3">Jerarquía</th><th className="px-4 py-3">Estado</th><th className="px-4 py-3 text-right">Acciones</th></tr>
              </thead>
              <tbody className="divide-y divide-border/70">
                {filas.map((usuario) => {
                  const estado = ESTADO_USUARIO[usuario.estado]
                  const supervisor = (catalogo.data ?? filas).find((fila) => fila.perfil_id === usuario.supervisor_id)
                  return (
                    <tr key={usuario.perfil_id} className="align-top">
                      <td className="px-4 py-3">
                        <p className="font-bold text-primary">{auditaDirectorio ? identificadorAuditoria(usuario.perfil_id) : usuario.nombre_completo}</p>
                        {!auditaDirectorio && usuario.correo && <p className="mt-0.5 text-[11px] text-muted-foreground">{usuario.correo}</p>}
                        {!auditaDirectorio && usuario.documento && <p className="mt-0.5 text-[10px] text-muted-foreground">{usuario.tipo_documento} · {usuario.documento}</p>}
                      </td>
                      <td className="px-4 py-3">
                        {usuario.rol_crm ? <Badge variant="outline">{ROL_LABEL[usuario.rol_crm]}</Badge> : <span className="text-warning">Sin asignar</span>}
                      </td>
                      <td className="px-4 py-3 text-muted-foreground">{auditaDirectorio ? 'Redactada' : supervisor?.nombre_completo ?? (usuario.supervisor_id ? 'Supervisor no visible' : 'Sin supervisor')}</td>
                      <td className="px-4 py-3">
                        <Badge dot color={estado.color}>{estado.label}</Badge>
                        {!auditaDirectorio && usuario.version_equipo && <p className="mt-1 text-[10px] text-muted-foreground">Actualizado {fechaHora(usuario.version_equipo)}</p>}
                      </td>
                      <td className="px-4 py-3">
                        <div className="flex flex-wrap justify-end gap-1.5">
                          {administraPersonas && usuario.version_perfil && <Button size="xs" variant="outline" onClick={() => abrirEditar(usuario)}><Pencil aria-hidden /> Datos</Button>}
                          {administraRoles && <Button size="xs" variant="outline" onClick={() => abrirRol(usuario)}><Shield aria-hidden /> Rol</Button>}
                          {administraJerarquia && usuario.version_equipo && <Button size="xs" variant="outline" onClick={() => abrirJerarquia(usuario)}><UserRoundCog aria-hidden /> Jerarquía</Button>}
                          {administraPersonas && usuario.version_equipo && <Button size="xs" variant="outline" disabled={impacto.isPending} onClick={() => void abrirMembresia(usuario)}><ToggleLeft aria-hidden /> {usuario.activo_crm ? 'Desactivar' : 'Activar'}</Button>}
                          {administraPersonas && <Button size="xs" variant="ghost" onClick={() => setModal({ tipo: 'recuperacion', usuario })}><KeyRound aria-hidden /> Acceso</Button>}
                          {auditaDirectorio && <span className="text-[10px] font-semibold text-muted-foreground">Solo lectura</span>}
                        </div>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
          <div className="flex items-center justify-between border-t border-border px-4 py-3 text-xs text-muted-foreground">
            <span>Página {pagina + 1} de {paginas}</span>
            <div className="flex gap-2">
              <Button size="xs" variant="outline" disabled={pagina === 0} onClick={() => setPagina((actual) => Math.max(0, actual - 1))}>Anterior</Button>
              <Button size="xs" variant="outline" disabled={pagina + 1 >= paginas} onClick={() => setPagina((actual) => actual + 1)}>Siguiente</Button>
            </div>
          </div>
        </Card>
      )}

      <Dialog open={modal?.tipo === 'crear' || modal?.tipo === 'editar'} onClose={() => !ocupada && setModal(null)} ariaLabel={modal?.tipo === 'crear' ? 'Crear usuario CRM' : 'Editar usuario CRM'} className="w-[680px]">
        <DialogHeader><DialogTitle>{modal?.tipo === 'crear' ? 'Nuevo usuario CRM' : 'Editar datos del usuario'}</DialogTitle><DialogDescription>{modal?.tipo === 'crear' ? 'La persona nace pendiente de rol. Superadmin asigna el rol y Gerencia completa su activación.' : 'Solo se modifican los datos operativos; el correo, rol y estado se gobiernan por sus flujos propios.'}</DialogDescription></DialogHeader>
        <DialogBody><CamposPersona valor={persona} onChange={setPersona} correoEditable={modal?.tipo === 'crear'} disabled={ocupada} /></DialogBody>
        <DialogFooter><Button variant="outline" onClick={() => setModal(null)} disabled={ocupada}>Cancelar</Button><Button onClick={() => void guardarPersona()} disabled={ocupada}>{ocupada ? 'Guardando…' : 'Guardar'}</Button></DialogFooter>
      </Dialog>

      <Dialog open={modal?.tipo === 'rol'} onClose={() => !ocupada && setModal(null)} ariaLabel="Asignar rol CRM">
        <DialogHeader><DialogTitle>Rol CRM de {modal?.tipo === 'rol' ? modal.usuario.nombre_completo : ''}</DialogTitle><DialogDescription>Superadmin solo cambia el rol. La jerarquía y el estado permanecen bajo control de Gerencia.</DialogDescription></DialogHeader>
        <DialogBody><Label htmlFor="rol-usuario">Rol CRM</Label><Select id="rol-usuario" value={rol} disabled={ocupada} onChange={(e) => setRol(e.target.value as Rol)} className="mt-1">{ROLES.map((item) => <option key={item} value={item}>{ROL_LABEL[item]}</option>)}</Select></DialogBody>
        <DialogFooter><Button variant="outline" onClick={() => setModal(null)} disabled={ocupada}>Cancelar</Button><Button onClick={() => void guardarRol()} disabled={ocupada}>Confirmar rol</Button></DialogFooter>
      </Dialog>

      <Dialog open={modal?.tipo === 'jerarquia'} onClose={() => !ocupada && setModal(null)} ariaLabel="Actualizar jerarquía">
        <DialogHeader><DialogTitle>Jerarquía de {modal?.tipo === 'jerarquia' ? modal.usuario.nombre_completo : ''}</DialogTitle><DialogDescription>El servidor evita ciclos y destinos inactivos o incompatibles.</DialogDescription></DialogHeader>
        <DialogBody>
          <Label htmlFor="supervisor-usuario">Supervisor</Label>
          <Select id="supervisor-usuario" value={supervisorId} disabled={ocupada || catalogo.isPending} onChange={(e) => setSupervisorId(e.target.value)} className="mt-1">
            <option value="">Sin supervisor</option>
            {opcionesJerarquia.map((item) => <option key={item.perfil_id} value={item.perfil_id}>{item.nombre_completo} · {item.rol_crm ? ROL_LABEL[item.rol_crm] : ''}</option>)}
          </Select>
          {modal?.tipo === 'jerarquia' && modal.usuario.rol_crm === 'vendedor' && !supervisorId && <p className="mt-2 text-xs font-semibold text-warning">Un vendedor debe tener supervisor antes de activarse.</p>}
          {modal?.tipo === 'jerarquia' && modal.usuario.rol_crm != null && !['vendedor', 'supervisor'].includes(modal.usuario.rol_crm) && <p className="mt-2 text-xs text-muted-foreground">Este rol pertenece a la raíz operativa y no admite supervisor.</p>}
        </DialogBody>
        <DialogFooter><Button variant="outline" onClick={() => setModal(null)} disabled={ocupada}>Cancelar</Button><Button onClick={() => void guardarJerarquia()} disabled={ocupada || catalogo.isError}>Guardar jerarquía</Button></DialogFooter>
      </Dialog>

      <Dialog open={modal?.tipo === 'membresia'} onClose={() => !ocupada && setModal(null)} ariaLabel="Cambiar membresía CRM" className="w-[620px]">
        <DialogHeader><DialogTitle>{modal?.tipo === 'membresia' && modal.usuario.activo_crm ? 'Desactivar membresía CRM' : 'Activar membresía CRM'}</DialogTitle><DialogDescription>{modal?.tipo === 'membresia' ? modal.usuario.nombre_completo : ''}</DialogDescription></DialogHeader>
        <DialogBody className="space-y-4">
          {modal?.tipo === 'membresia' && modal.usuario.activo_crm && modal.impacto && <><ResumenImpacto impacto={modal.impacto} />{modal.impacto.requiere_reemplazo && <div><Label htmlFor="reemplazo-usuario">Reemplazo activo del mismo rol</Label><Select id="reemplazo-usuario" value={reemplazoId} disabled={ocupada || catalogo.isPending} onChange={(e) => setReemplazoId(e.target.value)} className="mt-1"><option value="">Selecciona un reemplazo</option>{reemplazos.map((item) => <option key={item.perfil_id} value={item.perfil_id}>{item.nombre_completo}</option>)}</Select><p className="mt-2 text-xs font-semibold text-warning">Subordinados, leads, tareas y clientes se transferirán en la misma transacción.</p></div>}</>}
          {modal?.tipo === 'membresia' && !modal.usuario.activo_crm && (
            bloqueoActivacion
              ? <p className="rounded-lg bg-warning/10 px-3 py-2 text-sm font-semibold text-warning-text">{bloqueoActivacion}</p>
              : <p className="text-sm">Al activar, el usuario podrá entrar al CRM con su rol y jerarquía actuales. El perfil Portal debe seguir activo.</p>
          )}
        </DialogBody>
        <DialogFooter><Button variant="outline" onClick={() => setModal(null)} disabled={ocupada}>Cancelar</Button><Button variant={modal?.tipo === 'membresia' && modal.usuario.activo_crm ? 'destructive' : 'default'} onClick={() => void guardarMembresia()} disabled={ocupada || Boolean(bloqueoActivacion) || (modal?.tipo === 'membresia' && Boolean(modal.impacto?.requiere_reemplazo) && !reemplazoId)}>{ocupada ? 'Procesando…' : modal?.tipo === 'membresia' && modal.usuario.activo_crm ? 'Desactivar y transferir' : 'Activar membresía'}</Button></DialogFooter>
      </Dialog>

      <Dialog open={modal?.tipo === 'recuperacion'} onClose={() => !ocupada && setModal(null)} ariaLabel="Enviar recuperación de acceso">
        <DialogHeader><DialogTitle>Enviar recuperación de acceso</DialogTitle><DialogDescription>Se enviará un enlace al correo registrado de {modal?.tipo === 'recuperacion' ? modal.usuario.nombre_completo : 'la persona'}.</DialogDescription></DialogHeader>
        <DialogBody><p className="text-sm text-muted-foreground">El CRM no genera, muestra ni almacena contraseñas. El usuario definirá una nueva mediante el enlace seguro.</p></DialogBody>
        <DialogFooter><Button variant="outline" onClick={() => setModal(null)} disabled={ocupada}>Cancelar</Button><Button onClick={() => void enviarRecuperacion()} disabled={ocupada}><KeyRound aria-hidden /> {ocupada ? 'Enviando…' : 'Enviar correo'}</Button></DialogFooter>
      </Dialog>
    </ConfiguracionShell>
  )
}
