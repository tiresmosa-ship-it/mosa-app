/* =====================================================================
   MOSA TIRES — capa compartida: credenciales, config, utilidades,
   almacenamiento local, capa de datos, motor de sincronización offline
   y toda la lógica de negocio sin JSX. Cargado como <script> clásico
   (sin módulos) antes de cualquier script de página, así que todo lo
   declarado acá queda disponible como global para index.html,
   mecanico.html, admin.html, superadmin.html y cliente.html.

   Nota: el cliente de Supabase se guarda en la variable global `sb`
   (no `supabase`) porque la librería @supabase/supabase-js@2 (UMD, vía
   CDN) ya declara su propio binding global `supabase`, y redeclararlo
   con `const` revienta con "Identifier 'supabase' has already been
   declared" y aborta la carga de todo este script sin ningún error
   visible en pantalla.
===================================================================== */

/* =====================================================================
   CONFIG
===================================================================== */
const SUPABASE_URL = "https://dnbrqjenkiwobzfssxlf.supabase.co";
const SUPABASE_KEY = "sb_publishable_zi1xe8N5H1nx_X6xbb4BjQ_a4eqc6G0";
const CLIENTE_ID_DEFAULT = "la_portada";
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

const DEFAULT_CFG = {
  psi_delantero: 115, psi_traccion: 95, psi_tolerancia_pct: 5,
  psi_auxilio_tracto: 115, psi_auxilio_semi: 95,
  mm_minimo_tracto: 5, mm_minimo_semi: 3, mm_minimo_auxilio: 5,
  mm_amarillo_tracto: 6, mm_amarillo_semi: 4, mm_rotacion_pct: 20,
  numero_auditoria_inicio: 1, numero_cambio_inicio: 1,
  formula_marca_fuego: "interno+semana+anio+posicion"
};

const TOOLS_CHECKLIST = [
  "Dado 33","Dado 32","Dado 22","Gata","Medidor PSI","Profundímetro",
  "Caimán","Sacatapas","Cuñas","Mangueras","Banquillos","Desmontadora neumática",
  "Extractor de rueda","Conos verdes","Destalonador","Espejo","Barra para montar",
  "Turbina","Copa","Rulín","Marcador Elrick","Inflador","Llave punta corona 16",
  "Atomizador rost off","Sacapepas","Llave punta corona 14","Limpieza taller",
  "Pata de cabra","Multiplicador","Chita","Pistola 1\"","Cadenas","Alicate pequeño"
];

const MARCAS_NEUMATICOS = ["Triangle", "Aeolus", "Roadx", "Windforce", "Goodyear", "Michelin", "Bridgestone", "Pirelli", "Continental", "Otra"];

/* Configuraciones de eje: filas visuales + grupos de rotacion permitidos.
   "ejeTipo" (distinto del "type" usado para psi/mm, que no se toca) clasifica
   cada fila para las reglas de rotacion:
   - "D"  direccional: sin sentido de giro, cambio de lado siempre permitido.
   - "M"  traccional/motriz: banda caluga, sentido de giro obligatorio -> solo
          puede rotar dentro del mismo lado (izq/der), nunca cruzando.
   - "T"  libre/flotante (eje de apoyo o semi): banda lineal, sin sentido de
          giro, se puede rotar libremente dentro del eje sin restriccion de lado.
   - "auxilio": posicion de auxilio del semi, aislada (grupo de una sola posicion).
   En 6x2 el eje motriz (M) y el libre (T) son grupos separados (bloqueado
   cruzar). En 6x4 ambos ejes traseros son motrices (M+M) y comparten un solo
   grupo de rotacion, pero como ambos son ejeTipo "M" igual se exige mismo lado. */
const AXLE_CONFIGS = {
  "4x2": {
    total: 6,
    rows: [
      { label: "D", type: "D", ejeTipo: "D", positions: [1, 2] },
      { label: "T", type: "M", ejeTipo: "M", positions: [3, 4, 5, 6] }
    ],
    groups: [[1, 2], [3, 4, 5, 6]]
  },
  "6x2": {
    total: 10,
    rows: [
      { label: "D", type: "D", ejeTipo: "D", positions: [1, 2] },
      { label: "M", type: "M", ejeTipo: "M", positions: [3, 4, 5, 6] },
      { label: "T", type: "M", ejeTipo: "T", positions: [7, 8, 9, 10] }
    ],
    groups: [[1, 2], [3, 4, 5, 6], [7, 8, 9, 10]]
  },
  "6x4": {
    total: 10,
    rows: [
      { label: "D", type: "D", ejeTipo: "D", positions: [1, 2] },
      { label: "M", type: "M", ejeTipo: "M", positions: [3, 4, 5, 6] },
      { label: "T", type: "M", ejeTipo: "M", positions: [7, 8, 9, 10] }
    ],
    groups: [[1, 2], [3, 4, 5, 6, 7, 8, 9, 10]]
  },
  "semi": {
    total: 13,
    rows: [
      { label: "Eje 1", type: "M", ejeTipo: "T", positions: [1, 2, 3, 4] },
      { label: "Eje 2", type: "M", ejeTipo: "T", positions: [5, 6, 7, 8] },
      { label: "Eje 3", type: "M", ejeTipo: "T", positions: [9, 10, 11, 12] },
      { label: "Auxilio", type: "auxilio", ejeTipo: "auxilio", positions: [13] }
    ],
    groups: [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12], [13]]
  }
};
function axleConfigFor(equipo) {
  if (!equipo) return AXLE_CONFIGS["4x2"];
  if (equipo.tipo === "SEMI") return AXLE_CONFIGS["semi"];
  return AXLE_CONFIGS[equipo.configuracion_ejes] || AXLE_CONFIGS["4x2"];
}
function posType(cfg, pos) {
  const row = cfg.rows.find(r => r.positions.includes(pos));
  return row ? row.type : "M";
}
function ejeTipoDePosicion(cfg, pos) {
  const row = cfg.rows.find(r => r.positions.includes(pos));
  return row ? row.ejeTipo : "M";
}
// Lado (izq/der) de una posicion dentro de SU propia fila: primera mitad de
// row.positions = izquierda, segunda mitad = derecha. Se usa solo para
// validar ejes traccionales (ejeTipo "M"), que no pueden cambiar de lado.
function ladoDePosicion(cfg, pos) {
  const row = cfg.rows.find(r => r.positions.includes(pos));
  if (!row) return null;
  const idx = row.positions.indexOf(pos);
  const mitad = Math.ceil(row.positions.length / 2);
  return idx < mitad ? "izq" : "der";
}

/* =====================================================================
   UTILIDADES
===================================================================== */
function cx(...xs) { return xs.filter(Boolean).join(" "); }
function pad2(n) { n = String(n); return n.length < 2 ? "0" + n : n; }
function todayISO() {
  const d = new Date();
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
}
function nowHM() { const d = new Date(); return pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds()); }
function formatDateLong(iso) {
  const dias = ["Domingo","Lunes","Martes","Miércoles","Jueves","Viernes","Sábado"];
  const meses = ["enero","febrero","marzo","abril","mayo","junio","julio","agosto","septiembre","octubre","noviembre","diciembre"];
  const d = iso ? new Date(iso + "T00:00:00") : new Date();
  return `${dias[d.getDay()]}, ${d.getDate()} de ${meses[d.getMonth()]}`;
}
function isoWeek(date) {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  return Math.ceil((((d - yearStart) / 86400000) + 1) / 7);
}
function uuid() {
  if (crypto.randomUUID) return crypto.randomUUID();
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, c => {
    const r = Math.random() * 16 | 0, v = c === "x" ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}
async function sha256Hex(text) {
  const enc = new TextEncoder().encode(text);
  const buf = await crypto.subtle.digest("SHA-256", enc);
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, "0")).join("");
}
function generarFuegoLaPortada(numeroInterno, posicion, fecha) {
  const d = fecha ? new Date(fecha + "T00:00:00") : new Date();
  const semana = pad2(isoWeek(d));
  const anio = pad2(d.getFullYear() % 100);
  return `${numeroInterno || "0"}${semana}${anio}${posicion}`;
}

/* =====================================================================
   ALMACENAMIENTO LOCAL (sesion, turno, cola offline)
===================================================================== */
const LS = {
  session: "mosa_session",
  turno: "mosa_turno",
  queue: "mosa_queue",
  cfg: (cid) => `mosa_cfg_${cid}`,
  equipos: (cid) => `mosa_equipos_${cid}`
};
function getSession() { try { return JSON.parse(localStorage.getItem(LS.session) || "null"); } catch (e) { return null; } }
function setSession(s) { localStorage.setItem(LS.session, JSON.stringify(s)); }
function clearSession() { localStorage.removeItem(LS.session); localStorage.removeItem(LS.turno); }
function getTurno() { try { return JSON.parse(localStorage.getItem(LS.turno) || "null"); } catch (e) { return null; } }
function setTurno(t) { localStorage.setItem(LS.turno, JSON.stringify(t)); }

function getQueue() { try { return JSON.parse(localStorage.getItem(LS.queue) || "[]"); } catch (e) { return []; } }
function setQueue(q) { localStorage.setItem(LS.queue, JSON.stringify(q)); window.dispatchEvent(new Event("mosa-queue-changed")); }
function pushQueue(item) { const q = getQueue(); q.push(item); setQueue(q); }
function removeFromQueue(id) { setQueue(getQueue().filter(x => x.id !== id)); }

function getCache(key, fallback) { try { return JSON.parse(localStorage.getItem(key) || "null") || fallback; } catch (e) { return fallback; } }
function setCache(key, val) { localStorage.setItem(key, JSON.stringify(val)); }

/* =====================================================================
   CAPA DE DATOS
===================================================================== */
const db = {
  async login(usuario, passwordHash) {
    const { data, error } = await sb.from("usuarios").select("*")
      .eq("usuario", usuario).eq("password_hash", passwordHash).eq("activo", true).maybeSingle();
    if (error) throw error;
    return data;
  },
  async fetchUsuario(id) {
    const { data, error } = await sb.from("usuarios").select("*").eq("id", id).maybeSingle();
    if (error) throw error;
    return data;
  },
  async fetchCliente(clienteId) {
    const { data, error } = await sb.from("clientes").select("*").eq("id_cliente", clienteId).maybeSingle();
    if (error) throw error;
    return data;
  },
  async fetchEquipos(clienteId) {
    const { data, error } = await sb.from("equipos").select("*").eq("cliente_id", clienteId).eq("activo", true).order("numero_interno");
    if (error) throw error;
    setCache(LS.equipos(clienteId), data);
    return data;
  },
  async fetchConfig(clienteId) {
    const { data, error } = await sb.from("config_cliente").select("*").eq("cliente_id", clienteId);
    if (error) throw error;
    const map = { ...DEFAULT_CFG };
    (data || []).forEach(r => { const n = parseFloat(r.valor); map[r.clave] = isNaN(n) || r.clave === "formula_marca_fuego" ? r.valor : n; });
    setCache(LS.cfg(clienteId), map);
    return map;
  },
  async setConfigValor(clienteId, clave, valor) {
    const { error } = await sb.from("config_cliente").upsert(
      { cliente_id: clienteId, clave, valor: String(valor) }, { onConflict: "cliente_id,clave" });
    if (error) throw error;
  },
  async fetchAlertas(clienteId, mecanicoId) {
    // discrepancia_inventario es una alerta para el Admin (revisa stock del check
    // diario), el mecanico no debe verla en su pantalla de Alertas.
    let q = sb.from("alertas").select("*").eq("cliente_id", clienteId).neq("tipo", "discrepancia_inventario").order("creado_en", { ascending: false }).limit(100);
    if (mecanicoId) q = q.eq("mecanico_id", mecanicoId);
    const { data, error } = await q;
    if (error) throw error;
    return data || [];
  },
  async fetchUltimaAuditoria(equipoId) {
    const { data, error } = await sb.from("auditorias").select("*").eq("equipo_id", equipoId).order("fecha", { ascending: false }).limit(1);
    if (error) throw error;
    return (data && data[0]) || null;
  },
  async fetchAuditoriasHoy(clienteId) {
    const { data, error } = await sb.from("auditorias").select("equipo_id, fecha").eq("fecha", todayISO());
    if (error) throw error;
    return data || [];
  }
};

/* =====================================================================
   ESTADO DE NEUMATICO (alertas en tiempo real)
===================================================================== */
function evaluarPosicion(axleCfg, cfg, pos, tipoEquipo, data) {
  const tipo = posType(axleCfg, pos); // D | M | auxilio
  const mm = [data.mm_borde_izq, data.mm_centro, data.mm_borde_der].map(v => parseFloat(v)).filter(v => !isNaN(v));
  const minMM = mm.length ? Math.min(...mm) : null;
  const esSemi = tipoEquipo === "SEMI";
  const mmMin = tipo === "auxilio" ? cfg.mm_minimo_auxilio : (esSemi ? cfg.mm_minimo_semi : cfg.mm_minimo_tracto);
  const mmAmarillo = esSemi ? cfg.mm_amarillo_semi : cfg.mm_amarillo_tracto;
  const psiObjetivo = tipo === "D" ? cfg.psi_delantero : tipo === "auxilio" ? (esSemi ? cfg.psi_auxilio_semi : cfg.psi_auxilio_tracto) : cfg.psi_traccion;
  const tol = psiObjetivo * (cfg.psi_tolerancia_pct / 100);
  const psi = parseFloat(data.psi);

  let status = "ok";
  let motivos = [];
  if (minMM != null) {
    if (minMM < mmMin) { status = "alerta"; motivos.push(`mm ${minMM} bajo mínimo ${mmMin}`); }
    else if (minMM < mmAmarillo && status !== "alerta") { status = "atencion"; motivos.push(`mm ${minMM} cerca del mínimo`); }
  }
  if (!isNaN(psi)) {
    if (Math.abs(psi - psiObjetivo) > tol * 2) { status = "alerta"; motivos.push(`psi ${psi} muy fuera de rango`); }
    else if (Math.abs(psi - psiObjetivo) > tol && status !== "alerta") { status = "atencion"; motivos.push(`psi ${psi} fuera de tolerancia`); }
  }
  return { status, motivos, minMM, psiObjetivo, mmMin, mmAmarillo };
}

/* =====================================================================
   MOTOR DE SINCRONIZACION OFFLINE
===================================================================== */
let syncing = false;
async function syncQueue(onProgress) {
  if (syncing || !navigator.onLine) return;
  syncing = true;
  try {
    let queue = getQueue().slice().sort((a, b) => a.ts - b.ts);
    for (const item of queue) {
      try {
        await enviarItem(item);
        removeFromQueue(item.id);
        if (onProgress) onProgress(item);
      } catch (e) {
        // 23505 = unique_violation: el insert anterior en realidad SI llego al
        // servidor (la respuesta se perdio por una conexion inestable, tipica
        // en 3G/4G de campo), y el reintento choca con su propio id. Tratamos
        // esto como exito para no dejar el item trabado para siempre.
        if (e && e.code === "23505") { removeFromQueue(item.id); continue; }
        console.error("Error sincronizando", item, e);
        // No usar "break": un item que sigue fallando (ej. sin conexion real)
        // no debe bloquear la sincronizacion del resto de la cola.
      }
    }
  } finally { syncing = false; }
}
async function enviarItem(item) {
  switch (item.tipo) {
    case "novedad": return enviarNovedad(item.data);
    case "auditoria": return enviarAuditoria(item.data);
    case "cambio": return enviarCambio(item.data);
    case "cierre": return enviarCierre(item.data);
    case "alerta": return enviarAlerta(item.data);
    default: throw new Error("tipo desconocido " + item.tipo);
  }
}
async function enviarAlerta(data) {
  const { error } = await sb.from("alertas").insert(data);
  if (error) throw error;
}
async function enviarNovedad(data) {
  const { checklist, ...cab } = data;
  const { error: e1 } = await sb.from("check_diario").insert(cab);
  if (e1) throw e1;
  const rows = checklist.map(c => ({ id: uuid(), novedad_id: cab.id, herramienta: c.herramienta, cantidad: c.cantidad }));
  if (rows.length) { const { error: e2 } = await sb.from("check_diario_herramientas").insert(rows); if (e2) throw e2; }
}
async function asegurarNeumatico(clienteId, numeroFuego, equipoId, posicion, extra) {
  const { data: existente } = await sb.from("neumaticos").select("id_neumatico").eq("cliente_id", clienteId).eq("numero_fuego", numeroFuego).maybeSingle();
  if (existente) return;
  await sb.from("neumaticos").insert({
    id_neumatico: uuid(), numero_fuego: numeroFuego, cliente_id: clienteId,
    marca: (extra && extra.marca) || null, medida: (extra && extra.medida) || null,
    estado_actual: "nuevo", bodega: null, equipo_actual: equipoId, posicion_actual: posicion,
    fecha_ingreso: todayISO(), activo: true
  });
}
async function enviarAuditoria(data) {
  const { posiciones, receta, cliente_id, ...rest } = data;
  const cab = { ...rest, cliente_id };
  const { error: e1 } = await sb.from("auditorias").insert(cab);
  if (e1) throw e1;
  for (const p of posiciones) {
    if (p.numero_fuego) await asegurarNeumatico(cliente_id, p.numero_fuego, cab.equipo_id, p.posicion, p);
  }
  const rows = posiciones.filter(p => p.numero_fuego).map(p => ({
    id: p.id, posicion: p.posicion, numero_fuego: p.numero_fuego,
    milimetros: p.milimetros, psi: p.psi, mm_borde_izq: p.mm_borde_izq, mm_centro: p.mm_centro, mm_borde_der: p.mm_borde_der,
    auditoria_id: cab.id_auditoria
  }));
  if (rows.length) { const { error: e2 } = await sb.from("auditoria_posiciones").insert(rows); if (e2) throw e2; }
  if (receta) { const { error: e3 } = await sb.from("auditorias_receta").insert({ ...receta, auditoria_id: cab.id_auditoria, cliente_id }); if (e3) throw e3; }
  await sb.from("equipos").update({ kilometros: cab.kilometraje }).eq("id_equipo", cab.equipo_id);
}
async function insertMovimientoBodega(clienteId, mecanicoId, tipo, origen, numeroFuego) {
  const { error } = await sb.from("movimientos_bodega").insert({
    id: uuid(), cliente_id: clienteId, mecanico_id: mecanicoId, fecha: todayISO(),
    categoria: "neumatico", tipo, origen, numero_fuego: numeroFuego
  });
  if (error) console.error("No se pudo registrar movimiento de bodega", error);
}
async function enviarCambio(data) {
  const { sale, entra, rotaciones, intervenciones, alertas, recetaUpdate, cliente_id, ...cab } = data;
  const mecanicoId = cab.bultero_id;
  const { error: e1 } = await sb.from("cambios_neumaticos").insert(cab);
  if (e1) throw e1;
  const detalle = [];
  // SALIDAS: cambio_detalle (tipo='sale', motivo_salida), neumaticos (bodega/estado),
  // movimientos_bodega (tipo='salida', origen segun motivo).
  for (const s of sale) {
    await asegurarNeumatico(cliente_id, s.numero_fuego, null, null, s);
    detalle.push({ id: uuid(), cambio_id: cab.id_cambio, tipo: "sale", numero_fuego: s.numero_fuego, posicion: s.posicion || null, milimetros: s.milimetros || null, psi: s.psi || null, estado: null, motivo_salida: s.motivo_salida || s.motivo || null });
    await actualizarNeumaticoSale(cliente_id, s);
    await insertMovimientoBodega(cliente_id, mecanicoId, "salida", s.origen_mov || s.motivo || "salida", s.numero_fuego);
  }
  // ENTRADAS (montaje): cambio_detalle (tipo='entra', estado=tipo original),
  // neumaticos (equipo/posicion, estado_actual='en_uso'), movimientos_bodega
  // (tipo='entrada', origen='montaje').
  for (const en of entra) {
    await asegurarNeumatico(cliente_id, en.numero_fuego, cab.equipo_id, en.posicion, en);
    detalle.push({ id: uuid(), cambio_id: cab.id_cambio, tipo: "entra", numero_fuego: en.numero_fuego, posicion: en.posicion || null, milimetros: en.milimetros || null, psi: en.psi || null, estado: en.estado || null, motivo_salida: null });
    await actualizarNeumaticoEntra(cliente_id, cab.equipo_id, en);
    await insertMovimientoBodega(cliente_id, mecanicoId, "entrada", "montaje", en.numero_fuego);
  }
  // ROTACIONES: 4 filas de cambio_detalle (sale A / entra A / sale B / entra B),
  // se intercambia posicion_actual entre A y B. El inventario NO cambia y no se
  // registran movimientos_bodega.
  for (const r of (rotaciones || [])) {
    const a = r.a, b = r.b;
    detalle.push({ id: uuid(), cambio_id: cab.id_cambio, tipo: "sale", numero_fuego: a.numero_fuego, posicion: r.origen, milimetros: a.mm || null, psi: a.psi || null, estado: null, motivo_salida: "rotacion" });
    detalle.push({ id: uuid(), cambio_id: cab.id_cambio, tipo: "entra", numero_fuego: a.numero_fuego, posicion: r.destino, milimetros: a.mm || null, psi: a.psi || null, estado: null, motivo_salida: "rotacion" });
    if (b) {
      detalle.push({ id: uuid(), cambio_id: cab.id_cambio, tipo: "sale", numero_fuego: b.numero_fuego, posicion: r.destino, milimetros: b.mm || null, psi: b.psi || null, estado: null, motivo_salida: "rotacion" });
      detalle.push({ id: uuid(), cambio_id: cab.id_cambio, tipo: "entra", numero_fuego: b.numero_fuego, posicion: r.origen, milimetros: b.mm || null, psi: b.psi || null, estado: null, motivo_salida: "rotacion" });
      // Swap seguro (evita choque si hay indice unico por equipo/posicion):
      // A -> null, B -> origen, A -> destino.
      await sb.from("neumaticos").update({ posicion_actual: null }).eq("cliente_id", cliente_id).eq("numero_fuego", a.numero_fuego).eq("equipo_actual", cab.equipo_id);
      await sb.from("neumaticos").update({ posicion_actual: r.origen }).eq("cliente_id", cliente_id).eq("numero_fuego", b.numero_fuego).eq("equipo_actual", cab.equipo_id);
      await sb.from("neumaticos").update({ posicion_actual: r.destino }).eq("cliente_id", cliente_id).eq("numero_fuego", a.numero_fuego).eq("equipo_actual", cab.equipo_id);
    } else {
      await sb.from("neumaticos").update({ posicion_actual: r.destino }).eq("cliente_id", cliente_id).eq("numero_fuego", a.numero_fuego).eq("equipo_actual", cab.equipo_id);
    }
  }
  if (detalle.length) { const { error: e2 } = await sb.from("cambio_detalle").insert(detalle); if (e2) throw e2; }
  if (intervenciones && intervenciones.length) {
    const { error: e3 } = await sb.from("intervenciones").insert(intervenciones); if (e3) throw e3;
    // Regulacion de PSI: actualizar neumaticos.psi_actual (no se toca auditoria_posiciones).
    for (const iv of intervenciones) {
      if (iv.tipo === "regulacion_psi" && iv.psi_nuevo != null && iv.numero_fuego) {
        await sb.from("neumaticos").update({ psi_actual: iv.psi_nuevo }).eq("cliente_id", cliente_id).eq("numero_fuego", iv.numero_fuego);
      }
    }
  }
  await sb.from("equipos").update({ kilometros: cab.kilometraje }).eq("id_equipo", cab.equipo_id);
  // Cierre del instructivo asociado: parcial (quedan tareas) o completado.
  if (recetaUpdate && recetaUpdate.id) {
    const { error: e4 } = await sb.from("auditorias_receta").update({
      estado: recetaUpdate.estado, tareas_cumplidas: recetaUpdate.tareas_cumplidas, tareas_pendientes: recetaUpdate.tareas_pendientes
    }).eq("id", recetaUpdate.id);
    if (e4) console.error("No se pudo actualizar el estado del instructivo", e4);
  }
  for (const a of (alertas || [])) await insertAlerta(a);
}
async function enviarCierre(data) {
  const { error } = await sb.from("cierre_dia").insert(data);
  if (error) throw error;
  await insertAlerta({
    id: uuid(), cliente_id: data.cliente_id, equipo_id: null, mecanico_id: data.mecanico_id,
    tipo: "cierre_dia", severidad: "info", titulo: "Cierre de jornada",
    descripcion: `Jornada cerrada: ${data.auditorias_realizadas} auditorías, ${data.cambios_realizados} cambios.`,
    leida_mecanico: true, leida_admin: false, leida_superadmin: false
  });
}
async function insertAlerta(a) {
  const { error } = await sb.from("alertas").insert(a);
  if (error) console.error("No se pudo registrar alerta", error);
}
async function actualizarNeumaticoSale(clienteId, s) {
  // destino = motivo de salida: transito | reparacion | baja.
  // bodega = destino (baja/transito/reparacion), estado_actual valido del CHECK.
  const destino = s.motivo;
  const bodega = destino === "baja" ? "baja" : destino; // 'baja' | 'transito' | 'reparacion'
  const estado = destino === "baja" ? "baja" : "transito";
  const { data: existente } = await sb.from("neumaticos").select("*").eq("cliente_id", clienteId).eq("numero_fuego", s.numero_fuego).maybeSingle();
  if (existente) {
    const { error } = await sb.from("neumaticos").update({ estado_actual: estado, bodega, equipo_actual: null, posicion_actual: null }).eq("id_neumatico", existente.id_neumatico);
    if (error) throw error;
  } else {
    const { error } = await sb.from("neumaticos").insert({ id_neumatico: uuid(), numero_fuego: s.numero_fuego, cliente_id: clienteId, estado_actual: estado, bodega, equipo_actual: null, posicion_actual: null, fecha_ingreso: todayISO(), activo: true });
    if (error) throw error;
  }
}
async function actualizarNeumaticoEntra(clienteId, equipoId, en) {
  // Montaje: el neumatico queda montado en el equipo -> estado_actual='en_uso',
  // bodega=NULL (spec hoja de cambio). El tipo original (nuevo/transito/
  // recauchado) queda registrado en cambio_detalle.estado.
  const { data: existente } = await sb.from("neumaticos").select("*").eq("cliente_id", clienteId).eq("numero_fuego", en.numero_fuego).maybeSingle();
  if (existente) {
    const { error } = await sb.from("neumaticos").update({ estado_actual: "en_uso", bodega: null, equipo_actual: equipoId, posicion_actual: en.posicion || null }).eq("id_neumatico", existente.id_neumatico);
    if (error) throw error;
  } else {
    const { error } = await sb.from("neumaticos").insert({
      id_neumatico: uuid(), numero_fuego: en.numero_fuego, cliente_id: clienteId,
      marca: en.marca || null, medida: en.medida || null, estado_actual: "en_uso", bodega: null,
      equipo_actual: equipoId, posicion_actual: en.posicion || null, fecha_ingreso: todayISO(), activo: true
    });
    if (error) throw error;
  }
}
window.addEventListener("online", () => syncQueue());
setInterval(() => { if (navigator.onLine) syncQueue(); }, 15000);

/* =====================================================================
   CHECK DIARIO — campos de conteo y comparación de inventario
===================================================================== */
const DIRECCIONAL_FIELDS = [
  { key: "nuevos", label: "Nuevos" }, { key: "transito", label: "Tránsito" },
  { key: "reparar", label: "Por reparar" }, { key: "recauchados", label: "Recauchados" }
];
const TRACCIONAL_FIELDS = [
  { key: "tra_nuevos", label: "Nuevos" }, { key: "tra_transito", label: "Tránsito" },
  { key: "tra_reparar", label: "Por reparar" }, { key: "tra_recauchados", label: "Recauchados" }
];
const LIBRE_FIELDS = [
  { key: "libre_nuevos", label: "Nuevos" }, { key: "libre_transito", label: "Tránsito" },
  { key: "libre_reparar", label: "Por reparar" }, { key: "libre_recauchados", label: "Recauchados" }
];
const PATIO_FIELDS = [
  { key: "llantas_am_aluminio", label: "Americana aluminio" }, { key: "llantas_am_fierro", label: "Americana fierro" },
  { key: "llantas_eu_aluminio", label: "Europea aluminio" }, { key: "llantas_eu_fierro", label: "Europea fierro" }
];
const ALL_STOCK_FIELDS = [...DIRECCIONAL_FIELDS, ...TRACCIONAL_FIELDS, ...LIBRE_FIELDS, ...PATIO_FIELDS];

async function compararInventarioNeumaticos(clienteId, checkTotales) {
  const { data: neus } = await sb.from("neumaticos").select("bodega").eq("cliente_id", clienteId).eq("activo", true);
  const sistema = { nuevo: 0, transito: 0, recauchado: 0 };
  (neus || []).forEach(n => { if (sistema[n.bodega] !== undefined) sistema[n.bodega]++; });
  const labels = { nuevo: "Neumáticos nuevos", transito: "Neumáticos en tránsito", recauchado: "Neumáticos recauchados" };
  const diffs = [];
  for (const bucket of ["nuevo", "transito", "recauchado"]) {
    if (checkTotales[bucket] !== sistema[bucket]) diffs.push({ bucket, label: labels[bucket], sistema: sistema[bucket], fisico: checkTotales[bucket] });
  }
  return diffs;
}
async function registrarDiscrepancias(clienteId, mecanicoId, fecha, diffs) {
  const rows = diffs.map(d => ({
    id: uuid(), origen: "check_diario", tipo_item: "neumatico", item_detalle: d.label,
    valor_sistema: d.sistema, valor_fisico: d.fisico, diferencia: d.fisico - d.sistema,
    cliente_id: clienteId, mecanico_id: mecanicoId, fecha
  }));
  if (rows.length) await sb.from("discrepancias_inventario").insert(rows);
  await sb.from("alertas").insert({
    id: uuid(), cliente_id: clienteId, equipo_id: null, mecanico_id: mecanicoId,
    tipo: "discrepancia_inventario", severidad: "rojo", titulo: "Discrepancia en el check diario",
    descripcion: diffs.map(d => `${d.label}: sistema ${d.sistema} · contado ${d.fisico}`).join(" · "),
    leida_mecanico: true, leida_admin: false, leida_superadmin: false
  });
  return rows.map(r => r.id);
}
async function guardarObservacionDiscrepancia(ids, texto) {
  if (!ids.length || !texto.trim()) return;
  await sb.from("discrepancias_inventario").update({ observacion_mecanico: texto.trim() }).in("id", ids);
}
async function marcarInicioJornada(clienteId, mecanicoId, fecha, horaInicio) {
  const { data: existente } = await sb.from("cierre_dia").select("id").eq("mecanico_id", mecanicoId).eq("fecha", fecha).maybeSingle();
  if (existente) {
    await sb.from("cierre_dia").update({ hora_inicio: horaInicio }).eq("id", existente.id);
  } else {
    await sb.from("cierre_dia").insert({
      id: uuid(), cliente_id: clienteId, mecanico_id: mecanicoId, fecha, hora_inicio: horaInicio,
      auditorias_realizadas: 0, cambios_realizados: 0, regulaciones_psi: 0, retorqueos: 0, rotaciones: 0, reparaciones: 0, cerrado: false
    });
  }
}

/* =====================================================================
   ESTADO VISUAL (compartido: mapa de neumaticos y alertas)
===================================================================== */
function statusColor(s) { return s === "alerta" ? "red" : s === "atencion" ? "amber" : "green"; }
function statusLabel(s) { return s === "alerta" ? "Con alertas" : s === "atencion" ? "Atención" : "Al día"; }

/* =====================================================================
   GENERADOR DE RECOMENDACIONES (receta)
===================================================================== */
function generarRecomendaciones(posData, axleCfg, equipoTipo, cfg) {
  const recs = [];
  const posicionesAlerta = [];
  Object.values(posData).forEach(d => {
    if (d.status === "alerta" || d.status === "atencion") posicionesAlerta.push({ posicion: d.posicion, status: d.status, motivos: d.motivos });
  });

  const conPsiFuera = Object.values(posData).filter(d => (d.motivos || []).some(m => m.startsWith("psi"))).sort((a, b) => a.posicion - b.posicion);
  conPsiFuera.forEach(d => recs.push({ id: "psi_" + d.posicion, key: "rec_calibrar_psi", texto: `Calibrar presión de aire en P${d.posicion} (actual ${d.psi} psi)` }));

  const criticos = Object.values(posData).filter(d => d.status === "alerta" && (d.motivos || []).some(m => m.startsWith("mm"))).sort((a, b) => a.posicion - b.posicion);
  criticos.forEach(d => recs.push({ id: "cambiar_" + d.posicion, key: "rec_cambiar_neumaticos", texto: `Cambiar neumático en P${d.posicion} (${d.minMM} mm)` }));

  axleCfg.groups.forEach((grupo, i) => {
    const mms = grupo.map(p => posData[p] && posData[p].minMM).filter(v => v != null);
    if (mms.length < 2) return;
    const max = Math.max(...mms), min = Math.min(...mms);
    if (max > 0 && ((max - min) / max) * 100 >= cfg.mm_rotacion_pct) {
      const row = axleCfg.rows[i];
      const label = row ? row.label : `Eje ${i + 1}`;
      if (row && row.type === "D") recs.push({ id: "rot_" + i, key: "rec_rotar_delanteros", texto: `Rotar neumáticos delanteros (desgaste desparejo, eje ${label})` });
      else recs.push({ id: "rot_" + i, key: equipoTipo === "SEMI" ? `rec_rotar_semi_e${i + 1}` : "rec_rotar_traccionales", texto: `Rotar neumáticos del eje ${label} (desgaste desparejo)` });
    }
  });

  if (!recs.length) recs.push({ id: "ok", key: null, texto: "Todo en orden, sin tareas pendientes" });
  return { recs, posicionesAlerta };
}

/* =====================================================================
   HOJA DE CAMBIO — bodega, storage, motivos de baja
===================================================================== */
async function fetchNeumaticosBodega(clienteId, bodega) {
  const { data, error } = await sb.from("neumaticos").select("*").eq("cliente_id", clienteId).eq("bodega", bodega).eq("activo", true).limit(200);
  if (error) throw error;
  return data || [];
}

async function subirFotoCheckpoint(clienteId, pos, file) {
  const path = `${clienteId}/${Date.now()}_p${pos}_${file.name}`;
  const { error } = await sb.storage.from("checkpoints").upload(path, file, { upsert: true });
  if (error) throw error;
  const { data } = sb.storage.from("checkpoints").getPublicUrl(path);
  return data.publicUrl;
}

const BAJA_MOTIVOS = [
  { slug: "desgaste_normal", label: "Desgaste normal" },
  { slug: "pinchadura", label: "Pinchadura" },
  { slug: "corte", label: "Corte" },
  { slug: "dano_prematuro", label: "Daño prematuro" },
  { slug: "otro", label: "Otro" }
];

/* =====================================================================
   COMPARACION DE NEUMATICOS (auditoria vs sistema)
   Por cada posicion auditada busca el neumatico que el sistema tiene
   registrado en ese equipo/posicion y compara numero_fuego / marca /
   medida. numero_fuego siempre se compara (si el sistema no tiene nada en
   esa posicion, es un neumatico no registrado). marca/medida solo se
   comparan cuando el sistema tiene un valor cargado, para no generar ruido
   con los neumaticos viejos que todavia tienen marca/medida en null.
===================================================================== */
const CAMPO_LABELS = { numero_fuego: "N° de fuego", marca: "marca", medida: "medida" };
function normStr(v) { return (v == null ? "" : String(v)).trim().toLowerCase(); }
async function compararNeumaticosAuditoria(clienteId, equipoId, posData) {
  const { data: neus, error } = await sb.from("neumaticos")
    .select("numero_fuego, marca, medida, posicion_actual")
    .eq("cliente_id", clienteId).eq("equipo_actual", equipoId).eq("activo", true);
  if (error) throw error;
  const porPos = {};
  (neus || []).forEach(n => { if (n.posicion_actual != null) porPos[n.posicion_actual] = n; });
  const discrepancias = [];
  Object.values(posData).forEach(d => {
    if (!d.numero_fuego) return;
    const sis = porPos[d.posicion] || {};
    const campos = [
      { campo: "numero_fuego", sistema: sis.numero_fuego, mecanico: d.numero_fuego, siempre: true },
      { campo: "marca", sistema: sis.marca, mecanico: d.marca, siempre: false },
      { campo: "medida", sistema: sis.medida, mecanico: d.medida, siempre: false }
    ];
    campos.forEach(c => {
      const s = normStr(c.sistema), m = normStr(c.mecanico);
      if (!m) return;                    // el mecanico no cargo ese campo
      if (!c.siempre && !s) return;      // marca/medida: no comparar si el sistema no tiene dato
      if (s !== m) {
        discrepancias.push({
          posicion: d.posicion, campo: c.campo,
          valor_sistema: c.sistema == null ? null : String(c.sistema),
          valor_mecanico: String(c.mecanico),
          aprobada: false, aprobada_por: null, justificacion: null
        });
      }
    });
  });
  return discrepancias;
}

/* =====================================================================
   GUARDADO DE AUDITORIA (encabezado + posiciones + receta)
===================================================================== */
async function construirYGuardarAuditoria({ user, clienteId, equipo, cfg, posData, axleCfg, km, checklist, recsInfo, discrepanciasNeumaticos, recetaEstado }) {
  const numero_auditoria = await siguienteNumeroAuditoria(clienteId, cfg).catch(() => String(Date.now()).slice(-6));
  const sistemaTotal = checklist.filter(c => !c.extra).length;
  const cumplidas = checklist.filter(c => !c.extra && c.done).length;
  const pct = sistemaTotal ? Math.round((cumplidas / sistemaTotal) * 100) : 100;
  const flags = {};
  recsInfo.recs.forEach(r => { if (r.key) flags[r.key] = checklist.find(c => c.id === r.id) ? true : false; });

  const alertasGeneradas = [];
  const posiciones = Object.values(posData).map(d => {
    if (d.status !== "ok") {
      alertasGeneradas.push({
        id: uuid(), cliente_id: clienteId, equipo_id: equipo.id_equipo, mecanico_id: user.id,
        tipo: (d.motivos || []).some(m => m.startsWith("mm")) ? (d.status === "alerta" ? "mm_critico" : "mm_bajo") : (d.status === "alerta" ? "psi_bajo" : "psi_alto"),
        severidad: d.status === "alerta" ? "rojo" : "amarillo", titulo: `Posición P${d.posicion} en ${statusLabel(d.status).toLowerCase()}`,
        descripcion: (d.motivos || []).join("; "), posicion: d.posicion, numero_fuego: d.numero_fuego,
        leida_mecanico: false, leida_admin: false, leida_superadmin: false
      });
    }
    const mmVals = [d.mm_borde_izq, d.mm_centro, d.mm_borde_der].map(v => parseFloat(v)).filter(v => !isNaN(v));
    const promedioMM = mmVals.length ? Math.round((mmVals.reduce((a, b) => a + b, 0) / mmVals.length) * 100) / 100 : null;
    return {
      id: uuid(), posicion: d.posicion, numero_fuego: d.numero_fuego,
      milimetros: promedioMM, psi: d.psi ? parseInt(d.psi, 10) : null,
      mm_borde_izq: d.mm_borde_izq !== "" ? parseFloat(d.mm_borde_izq) : null,
      mm_centro: d.mm_centro !== "" ? parseFloat(d.mm_centro) : null,
      mm_borde_der: d.mm_borde_der !== "" ? parseFloat(d.mm_borde_der) : null
    };
  });

  // Recomendaciones reales (se excluye el placeholder "Todo en orden").
  const realRecs = recsInfo.recs.filter(r => r.key);
  const recomendacionesJSON = realRecs.map(r => ({ id: r.id, key: r.key, texto: r.texto, done: false }));
  const tareasExtraJSON = checklist.filter(c => c.extra).map(c => ({ texto: c.texto, done: c.done }));
  const totalTareas = realRecs.length;

  // Alerta amarilla por cada rotacion recomendada (desgaste desparejo entre
  // posiciones de un mismo eje/grupo). El mecanico la ve en su pantalla de Alertas.
  realRecs.filter(r => r.key.startsWith("rec_rotar_")).forEach(r => {
    alertasGeneradas.push({
      id: uuid(), cliente_id: clienteId, equipo_id: equipo.id_equipo, mecanico_id: user.id,
      tipo: "rotacion_recomendada", severidad: "amarillo", titulo: "Rotación recomendada",
      descripcion: r.texto, posicion: null, numero_fuego: null,
      leida_mecanico: false, leida_admin: false, leida_superadmin: false
    });
  });
  const recetaId = uuid();
  const cab = {
    id_auditoria: uuid(), equipo_id: equipo.id_equipo, bultero_id: user.id, cliente_id: clienteId,
    fecha: todayISO(), kilometraje: parseInt(km, 10) || equipo.kilometros, numero_auditoria,
    posiciones,
    receta: {
      id: recetaId, cliente_id: clienteId,
      rec_calibrar_psi: !!flags.rec_calibrar_psi, rec_cambiar_neumaticos: !!flags.rec_cambiar_neumaticos,
      rec_rotar_delanteros: !!flags.rec_rotar_delanteros, rec_rotar_traccionales: !!flags.rec_rotar_traccionales,
      rec_rotar_eje_libre: !!flags.rec_rotar_eje_libre, rec_rotar_semi_e1: !!flags.rec_rotar_semi_e1,
      rec_rotar_semi_e2: !!flags.rec_rotar_semi_e2, rec_rotar_semi_e3: !!flags.rec_rotar_semi_e3,
      // posiciones_alerta agrupa recomendaciones + discrepancias + tareas extra (spec).
      posiciones_alerta: {
        recomendaciones: recomendacionesJSON,
        discrepancias_neumaticos: discrepanciasNeumaticos || [],
        tareas_extra: tareasExtraJSON
      },
      total_tareas: totalTareas, tareas_cumplidas: 0, tareas_pendientes: totalTareas,
      seguio_receta: pct === 100, pct_receta_seguida: pct,
      tareas_extra: tareasExtraJSON,
      discrepancias_neumaticos: discrepanciasNeumaticos || [],
      estado: recetaEstado || "pendiente",
      observaciones_mecanico: null
    }
  };

  // Una alerta por cada discrepancia de neumatico detectada (informativa para
  // el mecanico, pendiente de aprobacion del administrador).
  (discrepanciasNeumaticos || []).forEach(dn => {
    alertasGeneradas.push({
      id: uuid(), cliente_id: clienteId, equipo_id: equipo.id_equipo, mecanico_id: user.id,
      tipo: "neumatico_no_registrado", severidad: "rojo",
      titulo: `Neumático no coincide en P${dn.posicion}`,
      descripcion: `${CAMPO_LABELS[dn.campo] || dn.campo}: sistema ${dn.valor_sistema == null ? "sin registro" : dn.valor_sistema} · mecánico ${dn.valor_mecanico}`,
      posicion: dn.posicion, numero_fuego: dn.valor_mecanico,
      leida_mecanico: true, leida_admin: false, leida_superadmin: false
    });
  });

  pushQueue({ id: uuid(), tipo: "auditoria", clienteId, ts: Date.now(), data: cab });
  alertasGeneradas.forEach(a => pushQueue({ id: uuid(), tipo: "alerta", clienteId, ts: Date.now(), data: a }));
  syncQueue();
  return { alertas: alertasGeneradas.length, recetaId, auditoriaId: cab.id_auditoria };
}

async function buscarInstructivoPendiente(equipoId) {
  // Instructivo de una auditoria previa que sigue pendiente o parcial.
  const { data, error } = await sb.from("auditorias_receta")
    .select("id,auditoria_id,estado,total_tareas,tareas_cumplidas,tareas_pendientes,posiciones_alerta,tareas_extra,auditorias!inner(equipo_id,fecha)")
    .eq("auditorias.equipo_id", equipoId).in("estado", ["pendiente", "parcial"]);
  if (error) throw error;
  if (!data || !data.length) return null;
  data.sort((a, b) => ((b.auditorias && b.auditorias.fecha) || "").localeCompare((a.auditorias && a.auditorias.fecha) || ""));
  return data[0];
}

async function construirPosDataDesdeEquipo(equipoId) {
  const { data, error } = await sb.from("neumaticos").select("*").eq("equipo_actual", equipoId).eq("activo", true);
  if (error || !data) return {};
  const map = {};
  data.forEach(n => {
    if (!n.posicion_actual) return;
    map[n.posicion_actual] = { posicion: n.posicion_actual, numero_fuego: n.numero_fuego, marca: n.marca, medida: n.medida, psi: n.psi_actual != null ? n.psi_actual : null, status: "ok", minMM: null };
  });
  // Completar PSI/MM con los últimos valores conocidos de la auditoría más reciente
  // (neumaticos no guarda milimetros; psi_actual solo se setea al regular PSI).
  try {
    const { data: ultimaAud } = await sb.from("auditorias").select("id_auditoria")
      .eq("equipo_id", equipoId).order("fecha", { ascending: false }).order("creado_en", { ascending: false }).limit(1);
    if (ultimaAud && ultimaAud.length) {
      const numerosFuego = data.map(n => n.numero_fuego).filter(Boolean);
      const { data: posAud } = await sb.from("auditoria_posiciones").select("numero_fuego,milimetros,psi")
        .eq("auditoria_id", ultimaAud[0].id_auditoria).in("numero_fuego", numerosFuego);
      if (posAud) {
        const porFuego = {};
        posAud.forEach(p => { porFuego[p.numero_fuego] = p; });
        Object.values(map).forEach(d => {
          const ult = porFuego[d.numero_fuego];
          if (!ult) return;
          if (d.psi == null && ult.psi != null) d.psi = ult.psi;
          if (ult.milimetros != null) d.minMM = ult.milimetros;
        });
      }
    }
  } catch (e) { console.error("No se pudieron cargar los últimos valores de auditoría", e); }
  return map;
}

/* =====================================================================
   ARBOL DE DECISION DEL MECANICO (al loguear)
===================================================================== */
function horasDesdeHoraCierre(fecha, horaCierre) {
  if (!horaCierre) return Infinity;
  const then = new Date(fecha + "T" + horaCierre);
  return (Date.now() - then.getTime()) / 3600000;
}
async function evaluarEstadoMecanico(user) {
  const hoy = todayISO();
  const { data: pendientes } = await sb.from("cierre_dia").select("*")
    .eq("mecanico_id", user.id).lt("fecha", hoy).eq("cerrado", false)
    .order("fecha", { ascending: false }).limit(1);
  if (pendientes && pendientes.length) return { estado: "jornada_pendiente", jornada: pendientes[0] };

  const { data: hoyCierres } = await sb.from("cierre_dia").select("*")
    .eq("mecanico_id", user.id).eq("fecha", hoy).eq("cerrado", true)
    .order("creado_en", { ascending: false }).limit(1);
  if (hoyCierres && hoyCierres.length) {
    const c = hoyCierres[0];
    if (horasDesdeHoraCierre(hoy, c.hora_cierre) < 8) return { estado: "jornada_cerrada_hoy" };
  }

  const { data: checks } = await sb.from("check_diario").select("*")
    .eq("bultero_id", user.id).eq("fecha", hoy).eq("completado", true)
    .order("creado_en", { ascending: false }).limit(1);
  if (checks && checks.length) return { estado: "menu_principal", clienteId: checks[0].empresa_id || checks[0].cliente_id };
  return { estado: "bienvenida" };
}
async function contarNeumaticosPorBodega(clienteId, bodega) {
  const { count } = await sb.from("neumaticos").select("id_neumatico", { count: "exact", head: true }).eq("cliente_id", clienteId).eq("bodega", bodega);
  return count || 0;
}

/* =====================================================================
   RESUMEN Y CIERRE DE JORNADA (compartido entre el cierre normal del dia
   y el cierre de una jornada anterior olvidada)
===================================================================== */
async function construirResumenJornada(mecanicoId, clienteId, fecha) {
  const [{ data: auditorias }, { data: cambios }, { data: intervenciones }, { data: cierreActual }] = await Promise.all([
    sb.from("auditorias").select("id_auditoria,equipo_id,creado_en,numero_auditoria").eq("bultero_id", mecanicoId).eq("fecha", fecha),
    sb.from("cambios_neumaticos").select("id_cambio,equipo_id,creado_en,numero_cambio").eq("bultero_id", mecanicoId).eq("fecha", fecha),
    sb.from("intervenciones").select("id,tipo,equipo_id,creado_en").eq("mecanico_id", mecanicoId).eq("fecha", fecha),
    sb.from("cierre_dia").select("id,hora_inicio").eq("mecanico_id", mecanicoId).eq("fecha", fecha).maybeSingle()
  ]);
  const auds = auditorias || [], cams = cambios || [], intervs = intervenciones || [];

  const equipoIds = [...new Set([...auds.map(a => a.equipo_id), ...cams.map(c => c.equipo_id)])].filter(Boolean);
  const equiposMap = {};
  if (equipoIds.length) {
    const { data: eqs } = await sb.from("equipos").select("id_equipo,patente,numero_interno").in("id_equipo", equipoIds);
    (eqs || []).forEach(e => { equiposMap[e.id_equipo] = e.numero_interno ? `${e.numero_interno} · ${e.patente}` : e.patente; });
  }

  const regulaciones_psi = intervs.filter(i => i.tipo === "regulacion_psi").length;
  const retorqueos = intervs.filter(i => i.tipo === "retorqueo").length;
  const reparaciones = intervs.filter(i => i.tipo === "reparacion").length;

  // Rotaciones: cambio_detalle tipo='sale' sin motivo_salida (las salidas por
  // transito/reparacion/baja siempre tienen motivo_salida; solo las rotaciones no).
  let rotaciones = 0;
  const cambioIds = cams.map(c => c.id_cambio);
  if (cambioIds.length) {
    const { data: cd } = await sb.from("cambio_detalle").select("id").in("cambio_id", cambioIds).eq("tipo", "sale").is("motivo_salida", null);
    rotaciones = (cd || []).length;
  }

  // pct_receta_promedio + estado de instructivo por equipo, via auditorias_receta del dia.
  let pct_receta_promedio = null;
  const auditoriaIds = auds.map(a => a.id_auditoria);
  let instructivos = [];
  if (auditoriaIds.length) {
    const { data: recetas } = await sb.from("auditorias_receta").select("auditoria_id,estado,pct_receta_seguida").in("auditoria_id", auditoriaIds);
    const vals = (recetas || []).map(r => r.pct_receta_seguida).filter(v => v != null);
    if (vals.length) pct_receta_promedio = Math.round(vals.reduce((a, b) => a + b, 0) / vals.length);
    instructivos = (recetas || []).map(r => {
      const a = auds.find(x => x.id_auditoria === r.auditoria_id);
      return { equipo: (a && equiposMap[a.equipo_id]) || "-", estado: r.estado, pct: r.pct_receta_seguida };
    });
  }

  const [stock_nuevo, stock_transito, stock_recauchado, stock_nfu] = await Promise.all([
    contarNeumaticosPorBodega(clienteId, "nuevo"), contarNeumaticosPorBodega(clienteId, "transito"),
    contarNeumaticosPorBodega(clienteId, "recauchado"), contarNeumaticosPorBodega(clienteId, "nfu")
  ]);

  const conteos = { auditorias_realizadas: auds.length, cambios_realizados: cams.length, regulaciones_psi, retorqueos, rotaciones, reparaciones, pct_receta_promedio };
  const stock = { stock_nuevo, stock_transito, stock_recauchado, stock_nfu };
  const detalle = {
    hora_inicio: cierreActual ? cierreActual.hora_inicio : null,
    auditorias: auds.map(a => ({ equipo: equiposMap[a.equipo_id] || "-", numero: a.numero_auditoria, hora: (a.creado_en || "").slice(11, 19) })),
    cambios: cams.map(c => ({ equipo: equiposMap[c.equipo_id] || "-", numero: c.numero_cambio, hora: (c.creado_en || "").slice(11, 19) })),
    instructivos,
    intervenciones: { regulaciones_psi, retorqueos, reparaciones, rotaciones },
    stock
  };
  return { conteos, stock, detalle, cierreId: cierreActual ? cierreActual.id : null };
}

async function cerrarJornadaConResumen({ user, clienteId, fecha, horaCierre, motivoSinCierre }) {
  const { conteos, stock, detalle, cierreId } = await construirResumenJornada(user.id, clienteId, fecha);
  const update = { cerrado: true, hora_cierre: horaCierre, motivo_sin_cierre: motivoSinCierre || null, ...conteos, ...stock };
  if (cierreId) {
    await sb.from("cierre_dia").update(update).eq("id", cierreId);
  } else {
    await sb.from("cierre_dia").insert({ id: uuid(), cliente_id: clienteId, mecanico_id: user.id, fecha, hora_inicio: null, ...update });
  }
  await insertAlerta({
    id: uuid(), cliente_id: clienteId, equipo_id: null, mecanico_id: user.id,
    tipo: "cierre_dia", severidad: "info",
    titulo: `Cierre de jornada — ${user.nombre} — ${fecha}`,
    descripcion: JSON.stringify({ hora_inicio: detalle.hora_inicio, hora_cierre: horaCierre, ...detalle }),
    leida_mecanico: true, leida_admin: false, leida_superadmin: false
  });
  return { conteos, stock, detalle };
}

async function resumenJornada(mecanicoId, fecha) {
  const [{ data: aud }, { data: cam }, { data: interv }] = await Promise.all([
    sb.from("auditorias").select("id_auditoria").eq("bultero_id", mecanicoId).eq("fecha", fecha),
    sb.from("cambios_neumaticos").select("id_cambio").eq("bultero_id", mecanicoId).eq("fecha", fecha),
    sb.from("intervenciones").select("id").eq("mecanico_id", mecanicoId).eq("fecha", fecha)
  ]);
  return { auditorias: (aud || []).length, cambios: (cam || []).length, intervenciones: (interv || []).length };
}
async function ultimaActividadDelDia(mecanicoId, fecha) {
  const tablas = [
    { t: "auditorias", campo: "bultero_id" },
    { t: "cambios_neumaticos", campo: "bultero_id" },
    { t: "intervenciones", campo: "mecanico_id" },
    { t: "check_diario", campo: "bultero_id" }
  ];
  let ultima = null;
  for (const { t, campo } of tablas) {
    const { data } = await sb.from(t).select("creado_en").eq(campo, mecanicoId).eq("fecha", fecha).order("creado_en", { ascending: false }).limit(1);
    if (data && data[0] && data[0].creado_en) {
      const ts = new Date(data[0].creado_en);
      if (!ultima || ts > ultima) ultima = ts;
    }
  }
  return ultima;
}

/* =====================================================================
   NUMERACION
===================================================================== */
async function siguienteNumeroAuditoria(clienteId, cfg) {
  const { data, error } = await sb.from("auditorias").select("numero_auditoria").eq("cliente_id", clienteId);
  const inicio = parseInt(cfg.numero_auditoria_inicio || 1, 10);
  let maxExistente = null;
  if (!error && data) {
    data.forEach(r => {
      const n = parseInt(r.numero_auditoria, 10);
      if (!isNaN(n) && (maxExistente === null || n > maxExistente)) maxExistente = n;
    });
  }
  const base = maxExistente === null ? inicio : maxExistente + 1;
  const pendientes = getQueue().filter(q => q.clienteId === clienteId && q.tipo === "auditoria").length;
  return String(base + pendientes);
}
async function siguienteNumeroCambio(clienteId, cfg) {
  const { data, error } = await sb.from("cambios_neumaticos").select("numero_cambio").order("numero_cambio", { ascending: false }).limit(1);
  let base = parseInt(cfg.numero_cambio_inicio || 1, 10);
  if (!error && data && data[0] && !isNaN(parseInt(data[0].numero_cambio, 10))) base = Math.max(base, parseInt(data[0].numero_cambio, 10) + 1);
  const pendientes = getQueue().filter(q => q.clienteId === clienteId && q.tipo === "cambio").length;
  return String(base + pendientes);
}
