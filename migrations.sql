-- =====================================================================
-- MOSA TIRES - Migracion de base de datos (Supabase)
-- Ejecutar en: Supabase Dashboard > SQL Editor
-- Seguro de re-ejecutar (usa IF NOT EXISTS / ON CONFLICT donde aplica)
-- =====================================================================

-- 1) Columnas de login en mecanicos (legado, se mantiene por compatibilidad)
ALTER TABLE mecanicos ADD COLUMN IF NOT EXISTS usuario TEXT;
ALTER TABLE mecanicos ADD COLUMN IF NOT EXISTS password_hash TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS mecanicos_usuario_key ON mecanicos (usuario);

-- 2) Tabla de configuracion por cliente (ya existente)
CREATE TABLE IF NOT EXISTS config_cliente (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id TEXT NOT NULL REFERENCES clientes(id_cliente),
  clave TEXT NOT NULL,
  valor TEXT,
  UNIQUE (cliente_id, clave)
);

-- 3) Parametros de negocio para La Portada (no pisa valores existentes)
INSERT INTO config_cliente (cliente_id, clave, valor) VALUES
  ('la_portada', 'numero_auditoria_inicio', '1'),
  ('la_portada', 'numero_cambio_inicio', '1'),
  ('la_portada', 'numero_flash_inicio', '1'),
  ('la_portada', 'numero_hoja_inicio', '1'),
  ('la_portada', 'numero_fuego_inicio', '1'),
  ('la_portada', 'formula_marca_fuego', 'interno+semana+anio+posicion'),
  ('la_portada', 'psi_delantero', '115'),
  ('la_portada', 'psi_traccion', '95'),
  ('la_portada', 'psi_tolerancia_pct', '5'),
  ('la_portada', 'psi_auxilio_tracto', '115'),
  ('la_portada', 'psi_auxilio_semi', '95'),
  ('la_portada', 'mm_minimo_tracto', '5'),
  ('la_portada', 'mm_minimo_semi', '3'),
  ('la_portada', 'mm_minimo_auxilio', '5'),
  ('la_portada', 'mm_amarillo_tracto', '6'),
  ('la_portada', 'mm_amarillo_semi', '4'),
  ('la_portada', 'mm_rotacion_pct', '20')
ON CONFLICT (cliente_id, clave) DO NOTHING;

-- =====================================================================
-- 4) PERMISOS DEL ROL "anon" - tablas ya existentes desde el prototipo anterior
-- =====================================================================
GRANT USAGE ON SCHEMA public TO anon;

GRANT SELECT, INSERT, UPDATE ON
  clientes, equipos, mecanicos, neumaticos, auditorias, auditoria_posiciones,
  cambios_neumaticos, cambio_detalle, novedades_diarias,
  novedades_checklist, config_cliente
TO anon;

-- =====================================================================
-- 5) PERMISOS DEL ROL "anon" - tablas nuevas del rediseno MOSA TIRES
-- Estas tablas ya existen en el proyecto Supabase pero bloquean INSERT/UPDATE
-- desde el frontend por RLS (confirmado: SELECT funciona, INSERT devuelve
-- 42501 "new row violates row-level security policy"). Sin este bloque el
-- login (tabla usuarios), las auditorias con receta, las alertas, el cierre
-- de dia, etc. no van a poder escribir datos.
-- =====================================================================
GRANT SELECT, INSERT, UPDATE ON
  usuarios, permisos, alertas, insumos, movimientos_bodega, cierre_dia,
  proveedores, auditorias_receta, intervenciones
TO anon;

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'clientes','equipos','mecanicos','neumaticos','auditorias','auditoria_posiciones',
    'cambios_neumaticos','cambio_detalle','novedades_diarias','novedades_checklist','config_cliente',
    'usuarios','permisos','alertas','insumos','movimientos_bodega','cierre_dia',
    'proveedores','auditorias_receta','intervenciones'
  ]
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS anon_all ON %I', t);
    EXECUTE format('CREATE POLICY anon_all ON %I FOR ALL TO anon USING (true) WITH CHECK (true)', t);
  END LOOP;
END $$;

-- =====================================================================
-- 6) Constraint de unicidad en usuarios.usuario (necesaria para el login)
-- =====================================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'usuarios_usuario_key'
  ) THEN
    ALTER TABLE usuarios ADD CONSTRAINT usuarios_usuario_key UNIQUE (usuario);
  END IF;
END $$;

-- =====================================================================
-- 6b) Columnas para separar stock traccional en el check diario
-- (las columnas nuevos/transito/reparar/recauchados ya existentes pasan
-- a representar los direccionales; estas nuevas son las traccionales)
-- =====================================================================
ALTER TABLE novedades_diarias ADD COLUMN IF NOT EXISTS tra_nuevos INT;
ALTER TABLE novedades_diarias ADD COLUMN IF NOT EXISTS tra_transito INT;
ALTER TABLE novedades_diarias ADD COLUMN IF NOT EXISTS tra_reparar INT;
ALTER TABLE novedades_diarias ADD COLUMN IF NOT EXISTS tra_recauchados INT;

-- =====================================================================
-- 7) Usuarios iniciales (password_hash = SHA-256 de la clave en texto plano)
--   admin  / mosadmin2026  -> superadmin
--   andrei / mosaadmin2026 -> admin
--   carlos / mosa2026      -> mecanico
--   pedro  / mosa2026      -> mecanico
--   miguel / mosa2026      -> mecanico
-- =====================================================================
INSERT INTO usuarios (cliente_id, nombre, apellido, usuario, password_hash, rol, activo) VALUES
  ('la_portada', 'Admin',   '',       'admin',  'a8210296c18741d307e1f8309f025ec107b0cc441c2d525eeb1619a1536275f9', 'superadmin', true),
  ('la_portada', 'Andrei',  '',       'andrei', '3faa27f3b4350acca534566b5d437745370bc7326185dae9a2e9b601a93acf19', 'admin',      true),
  ('la_portada', 'Carlos',  '',       'carlos', 'af50d8fd1c8f238c6b0e7ecc557173053611d254e4cbc792f3e4f7e84893973c', 'mecanico',   true),
  ('la_portada', 'Pedro',   '',       'pedro',  'af50d8fd1c8f238c6b0e7ecc557173053611d254e4cbc792f3e4f7e84893973c', 'mecanico',   true),
  ('la_portada', 'Miguel',  '',       'miguel', 'af50d8fd1c8f238c6b0e7ecc557173053611d254e4cbc792f3e4f7e84893973c', 'mecanico',   true)
ON CONFLICT (usuario) DO NOTHING;

-- =====================================================================
-- 8) Bucket de Storage para las fotos de checkpoint (montaje de neumático nuevo)
-- Esto NO se puede crear por SQL: andá a Supabase Dashboard > Storage >
-- "New bucket", nombralo exactamente "checkpoints" y marcalo como Public.
-- Sin este bucket, el montaje de neumáticos nuevos no va a poder subir la
-- foto obligatoria (la app te va a avisar con un error si falta).
-- =====================================================================

-- =====================================================================
-- 9) Sacar las FK viejas que apuntaban a "mecanicos"
-- El login ahora usa la tabla "usuarios" (no "mecanicos"), pero columnas
-- como bultero_id/mecanico_id en novedades_diarias, auditorias,
-- cambios_neumaticos, intervenciones, alertas y cierre_dia todavía tienen
-- una constraint de clave foranea que exige que ese id exista en
-- "mecanicos". Como el id que se guarda ahora es el de "usuarios", todo
-- insert fallaba con "violates foreign key constraint ..._fkey". Este
-- bloque busca y elimina esas constraints puntuales (no toca las FK a
-- clientes/equipos, que siguen siendo validas).
-- =====================================================================
DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT tc.constraint_name, tc.table_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
    WHERE tc.constraint_type = 'FOREIGN KEY' AND ccu.table_name = 'mecanicos'
      AND tc.table_name IN ('novedades_diarias','auditorias','cambios_neumaticos','intervenciones','alertas','cierre_dia')
  LOOP
    EXECUTE format('ALTER TABLE %I DROP CONSTRAINT %I', rec.table_name, rec.constraint_name);
  END LOOP;
END $$;

-- =====================================================================
-- 10) Columna faltante en auditorias_receta
-- La tabla real no tenia la columna "tareas_extra" (JSONB) que usa la app
-- para guardar las tareas que el mecanico agrega a mano en el instructivo.
-- =====================================================================
ALTER TABLE auditorias_receta ADD COLUMN IF NOT EXISTS tareas_extra JSONB;

-- =====================================================================
-- 11) Permisos para subir fotos al bucket "checkpoints" (Supabase Storage)
-- Crear el bucket "checkpoints" como Public no alcanza: Storage tambien
-- tiene sus propias politicas de RLS sobre la tabla storage.objects que
-- bloquean la subida (error "new row violates row-level security policy").
-- Este bloque agrega las politicas necesarias para que el rol anon pueda
-- subir y leer archivos en ese bucket puntual.
-- Requisito: el bucket "checkpoints" ya debe existir (Dashboard > Storage > New bucket).
-- =====================================================================
DROP POLICY IF EXISTS "anon puede subir a checkpoints" ON storage.objects;
CREATE POLICY "anon puede subir a checkpoints" ON storage.objects
  FOR INSERT TO anon
  WITH CHECK (bucket_id = 'checkpoints');

DROP POLICY IF EXISTS "anon puede actualizar checkpoints" ON storage.objects;
CREATE POLICY "anon puede actualizar checkpoints" ON storage.objects
  FOR UPDATE TO anon
  USING (bucket_id = 'checkpoints');

DROP POLICY IF EXISTS "anon puede leer checkpoints" ON storage.objects;
CREATE POLICY "anon puede leer checkpoints" ON storage.objects
  FOR SELECT TO anon
  USING (bucket_id = 'checkpoints');

-- =====================================================================
-- 12) Columnas de "Ejes libres" en check_diario
-- El check diario del mecanico ahora tiene una tercera seccion de conteo
-- de neumaticos (Direccionales / Traccionales / Ejes libres), pero la
-- tabla solo tenia columnas neu_dir_* y neu_trac_*.
-- =====================================================================
ALTER TABLE check_diario ADD COLUMN IF NOT EXISTS neu_libre_nuevo INT;
ALTER TABLE check_diario ADD COLUMN IF NOT EXISTS neu_libre_transito INT;
ALTER TABLE check_diario ADD COLUMN IF NOT EXISTS neu_libre_reparar INT;
ALTER TABLE check_diario ADD COLUMN IF NOT EXISTS neu_libre_recauchado INT;

-- =====================================================================
-- 13) Permisos para discrepancias_inventario
-- La tabla existe (columnas: id, origen, tipo_item, valor_sistema,
-- valor_fisico, cliente_id, mecanico_id, fecha, resuelta, creado_en) pero
-- bloqueaba INSERT para anon con "new row violates row-level security
-- policy". La usa el check diario para registrar diferencias entre lo
-- contado a mano y el inventario real de neumaticos.
-- =====================================================================
GRANT SELECT, INSERT, UPDATE ON discrepancias_inventario TO anon;
ALTER TABLE discrepancias_inventario ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS anon_all ON discrepancias_inventario;
CREATE POLICY anon_all ON discrepancias_inventario FOR ALL TO anon USING (true) WITH CHECK (true);

-- =====================================================================
-- 14) Otra FK vieja apuntando a "mecanicos" (mismo problema del punto 9)
-- discrepancias_inventario.mecanico_id todavia exigia que el id exista en
-- "mecanicos" en vez de "usuarios". Se repite el mismo bloque de borrado
-- de constraints, ahora incluyendo esta tabla.
-- =====================================================================
DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT tc.constraint_name, tc.table_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
    WHERE tc.constraint_type = 'FOREIGN KEY' AND ccu.table_name = 'mecanicos'
      AND tc.table_name = 'discrepancias_inventario'
  LOOP
    EXECUTE format('ALTER TABLE %I DROP CONSTRAINT %I', rec.table_name, rec.constraint_name);
  END LOOP;
END $$;

-- =====================================================================
-- 15) alertas.tipo tenia un CHECK constraint con una lista fija de
-- valores (psi_bajo/psi_alto/mm_bajo/.../cierre_dia) que no incluia el
-- nuevo tipo 'discrepancia_inventario' usado por el check diario. Se
-- saca el constraint para no tener que ampliarlo cada vez que se agregue
-- un tipo de alerta nuevo.
-- =====================================================================
ALTER TABLE alertas DROP CONSTRAINT IF EXISTS alertas_tipo_check;

-- =====================================================================
-- 16) Falta cliente_id en auditorias
-- El correlativo de numero_auditoria tiene que calcularse por cliente
-- (MAX(numero_auditoria) WHERE cliente_id = cliente_activo), pero la
-- tabla auditorias no tenia esa columna (por eso el codigo la sacaba
-- del insert). La agregamos para poder filtrar correctamente.
-- =====================================================================
ALTER TABLE auditorias ADD COLUMN IF NOT EXISTS cliente_id TEXT REFERENCES clientes(id_cliente);
UPDATE auditorias a SET cliente_id = e.cliente_id FROM equipos e WHERE a.equipo_id = e.id_equipo AND a.cliente_id IS NULL;

-- =====================================================================
-- 17) Columna discrepancias_neumaticos en auditorias_receta (JSONB)
-- Al generar el instructivo, la app compara cada posicion auditada contra
-- lo que el sistema tiene registrado en "neumaticos" (numero_fuego, marca,
-- medida) para el equipo_actual. Cuando algo no coincide, guarda el detalle
-- en este JSONB (array de objetos {posicion, campo, valor_sistema,
-- valor_mecanico, aprobada, aprobada_por, justificacion}) para que el
-- administrador pueda revisarlo/aprobarlo mas adelante. El mecanico solo lo
-- ve de forma informativa. Ademas se genera una alerta tipo
-- 'neumatico_no_registrado' por cada discrepancia (el CHECK de alertas.tipo
-- ya fue eliminado en el bloque 15, asi que ese tipo entra sin problema).
-- =====================================================================
ALTER TABLE auditorias_receta ADD COLUMN IF NOT EXISTS discrepancias_neumaticos JSONB DEFAULT '[]'::jsonb;

-- =====================================================================
-- 18) Partes faltantes de la hoja de cambio
-- =====================================================================

-- 18a) neumaticos.estado_actual: el CHECK actual solo permite
-- nuevo/transito/recauchado/baja, pero al montar un neumatico (entrada) la
-- app ahora lo marca como 'en_uso' (spec de la hoja de cambio). Ampliamos el
-- CHECK para incluir ese valor sin perder la validacion.
ALTER TABLE neumaticos DROP CONSTRAINT IF EXISTS neumaticos_estado_actual_check;
ALTER TABLE neumaticos ADD CONSTRAINT neumaticos_estado_actual_check
  CHECK (estado_actual IN ('nuevo','transito','recauchado','baja','en_uso'));

-- 18b) neumaticos.psi_actual: la tabla no guardaba el PSI vigente del
-- neumatico. La regulacion de PSI en la hoja de cambio ahora lo actualiza.
ALTER TABLE neumaticos ADD COLUMN IF NOT EXISTS psi_actual INT;

-- 18c) auditorias_receta.estado: se agregan los estados nuevos del ciclo de
-- vida del instructivo (en_proceso/sin_cambio/parcial/completado). Si existe
-- un CHECK viejo que los limite, lo sacamos (mismo criterio que alertas.tipo
-- en el bloque 15). 'en_proceso' ya se venia guardando sin problema.
ALTER TABLE auditorias_receta DROP CONSTRAINT IF EXISTS auditorias_receta_estado_check;

-- 18d) movimientos_bodega: la hoja de cambio ahora registra cada salida
-- (tipo='salida', origen segun motivo) y cada montaje (tipo='entrada',
-- origen='montaje'). La tabla ya tenia GRANT + policy anon (bloque 5), pero
-- podria conservar una FK vieja de mecanico_id -> mecanicos (mismo patron de
-- los bloques 9 y 14). La sacamos si existe para que el insert con id de
-- 'usuarios' no falle.
DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT tc.constraint_name, tc.table_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
    WHERE tc.constraint_type = 'FOREIGN KEY' AND ccu.table_name = 'mecanicos'
      AND tc.table_name = 'movimientos_bodega'
  LOOP
    EXECUTE format('ALTER TABLE %I DROP CONSTRAINT %I', rec.table_name, rec.constraint_name);
  END LOOP;
END $$;

-- =====================================================================
-- 19) cambio_detalle.motivo_salida: el CHECK actual solo permite
-- transito/reparacion/baja. Pero la baja ahora guarda el MOTIVO especifico
-- (desgaste_normal/pinchadura/corte/dano_prematuro/otro) en motivo_salida, y
-- las filas de rotacion se marcan con 'rotacion'. Ampliamos el CHECK para
-- aceptar esos valores (mas NULL, que usan las entradas/montajes).
-- =====================================================================
ALTER TABLE cambio_detalle DROP CONSTRAINT IF EXISTS cambio_detalle_motivo_salida_check;
ALTER TABLE cambio_detalle ADD CONSTRAINT cambio_detalle_motivo_salida_check
  CHECK (motivo_salida IS NULL OR motivo_salida IN (
    'transito','reparacion','baja',
    'desgaste_normal','pinchadura','corte','dano_prematuro','otro',
    'rotacion'
  ));

-- =====================================================================
-- 20) CHECKs de bodega/origen que bloqueaban las salidas
-- =====================================================================

-- 20a) neumaticos.bodega: el CHECK actual solo permite los valores viejos
-- (nuevo/recauchado/transito/salidas). Al sacar un neumatico la app ahora
-- setea bodega='baja' o 'reparacion' (destino de la salida), que el CHECK
-- rechazaba. Lo ampliamos manteniendo NULL y los valores existentes.
ALTER TABLE neumaticos DROP CONSTRAINT IF EXISTS neumaticos_bodega_check;
ALTER TABLE neumaticos ADD CONSTRAINT neumaticos_bodega_check
  CHECK (bodega IS NULL OR bodega IN
    ('nuevo','recauchado','transito','reparacion','baja','salidas'));

-- 20b) movimientos_bodega.origen: el CHECK fijo bloquea 'baja_<motivo>'
-- (baja_pinchadura, etc.), que es un descriptor compositivo con variantes
-- ilimitadas. Lo eliminamos (mismo criterio que alertas.tipo en el bloque 15);
-- 'montaje', 'transito', 'reparacion' y 'baja_*' quedan todos permitidos.
ALTER TABLE movimientos_bodega DROP CONSTRAINT IF EXISTS movimientos_bodega_origen_check;

-- =====================================================================
-- 21) intervenciones.tipo: el CHECK fijo bloquea el nuevo tipo 'giro_neumatico'
-- (giro sobre la llanta / inversion de cara en un neumatico direccional, sin
-- cambiar de posicion). Mismo criterio que los bloques 15/20b: se elimina el
-- CHECK en vez de tener que ampliarlo cada vez que se agregue un tipo nuevo
-- de intervencion (regulacion_psi/retorqueo/reparacion/checkpoint ya
-- funcionaban y no se ven afectados).
-- =====================================================================
ALTER TABLE intervenciones DROP CONSTRAINT IF EXISTS intervenciones_tipo_check;

-- =====================================================================
-- 22) cierre_dia tenia un UNIQUE(mecanico_id, fecha) que impedia mas de
-- un turno por mecanico por dia. Esto bloqueaba el flujo de desbloqueo del
-- Admin (iniciar nuevo turno / cambiar de empresa), que depende de poder
-- insertar un cierre_dia turno=2, turno=3... para el mismo mecanico en el
-- mismo dia. Se reemplaza por UNIQUE(mecanico_id, fecha, turno).
-- =====================================================================
ALTER TABLE cierre_dia DROP CONSTRAINT IF EXISTS cierre_dia_mecanico_id_fecha_key;
CREATE UNIQUE INDEX IF NOT EXISTS cierre_dia_mecanico_fecha_turno_key ON cierre_dia (mecanico_id, fecha, turno);
