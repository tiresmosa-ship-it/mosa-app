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

-- =====================================================================
-- 23) discrepancias_inventario.tipo_discrepancia tenia un CHECK con una
-- lista fija que no incluia 'numero_fuego'/'marca'/'medida' (los valores
-- que usa el Admin en Jornada > Movimientos del día > Discrepancias para
-- distinguir que campo del neumatico corregir al aprobar un ajuste de
-- auditoria). Mismo criterio que los bloques 15/20b/21: se elimina el
-- CHECK en vez de mantener la lista sincronizada a mano.
-- =====================================================================
ALTER TABLE discrepancias_inventario DROP CONSTRAINT IF EXISTS discrepancias_inventario_tipo_discrepancia_check;

-- =====================================================================
-- 24) Renombrado "baja" -> "retiro" y reestructuracion del flujo de salida.
-- neumaticos.bodega ya no tiene CHECK (se saco en el bloque 20a via SQL
-- corrido manualmente por el usuario, confirmado por curl: acepta
-- retiro_desgaste/retiro_daño_otro/para_recauchar/nfu/en_equipo sin problema).
-- Pero estado_actual y cambio_detalle.motivo_salida SI siguen bloqueando esos
-- valores nuevos (confirmado por curl con 23514). Mismo criterio que los
-- bloques 15/20b/21/23: se elimina el CHECK en vez de ampliarlo a mano cada
-- vez que se agregue un estado/motivo nuevo.
-- =====================================================================
ALTER TABLE neumaticos DROP CONSTRAINT IF EXISTS neumaticos_estado_actual_check;
ALTER TABLE cambio_detalle DROP CONSTRAINT IF EXISTS cambio_detalle_motivo_salida_check;

-- =====================================================================
-- 25) neumaticos.milimetros: al terminar una auditoria ("Generar
-- Instructivo") el sistema ahora actualiza cada neumatico auditado con el
-- psi/mm medidos (item 9 del flujo de montaje). psi ya tenia columna
-- (psi_actual); milimetros no existia (confirmado por curl, PGRST204).
-- =====================================================================
ALTER TABLE neumaticos ADD COLUMN IF NOT EXISTS milimetros NUMERIC;

-- =====================================================================
-- 24) Admin > Maestros (equipos/mecanicos/proveedores/inventario/
-- herramientas): permisos + RLS para herramientas_inventario y
-- lotes_inventario, que existen en el proyecto pero todavia bloqueaban
-- INSERT/UPDATE desde el frontend (confirmado: 42501 "new row violates
-- row-level security policy"), mismo patron que el bloque 5. Ademas,
-- constraints de unicidad para evitar los duplicados de numero_interno
-- en equipos (ya paso una vez con AH771HG/119) y de usuario en mecanicos.
-- =====================================================================
GRANT SELECT, INSERT, UPDATE ON herramientas_inventario, lotes_inventario TO anon;

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['herramientas_inventario', 'lotes_inventario']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS anon_all ON %I', t);
    EXECUTE format('CREATE POLICY anon_all ON %I FOR ALL TO anon USING (true) WITH CHECK (true)', t);
  END LOOP;
END $$;

-- mecanicos.usuario ya tiene un indice unico (mecanicos_usuario_key) desde el
-- bloque 1 de esta misma migracion, asi que solo falta el de equipos.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'equipos_cliente_numero_interno_key'
  ) THEN
    ALTER TABLE equipos ADD CONSTRAINT equipos_cliente_numero_interno_key UNIQUE (cliente_id, numero_interno);
  END IF;
END $$;

-- =====================================================================
-- 25) Maestros > Mecanicos pasa a gestionar usuarios (rol='mecanico') en
-- vez de la tabla legacy "mecanicos" (que no se usa para login, ver bloque
-- 9/14). Falta la columna telefono que pide ese formulario.
-- =====================================================================
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS telefono TEXT;

-- =====================================================================
-- 26) Se divide el rol 'cliente' en dos subtipos: 'dueno' (gerencial,
-- cliente.html, pendiente de construir) y 'operativo' (cliente-operativo.html,
-- solo lectura). Sin default: los clientes existentes quedan con subtipo
-- NULL hasta que un admin se los asigne (el login los sigue mandando al
-- placeholder cliente.html mientras tanto, ver App() en index.html).
-- =====================================================================
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS subtipo TEXT
  CHECK (subtipo IN ('dueno', 'operativo'));

-- =====================================================================
-- 27) Soporte multi-moneda (CLP/ARS/USD) en cargas valorizadas. La moneda
-- default por cliente se guarda en config_cliente (clave 'moneda', clave/valor
-- generico, no necesita ALTER TABLE). Estas tres tablas si necesitan columna
-- nueva: guardan un snapshot de la moneda del cliente en el momento de la
-- carga (Entrada de neumaticos / Entrada de insumos, Admin y SuperAdmin >
-- Maestros > Inventario), para que cargas viejas no cambien retroactivamente
-- si despues se cambia la moneda del cliente en Configuracion.
-- =====================================================================
ALTER TABLE lotes_inventario ADD COLUMN IF NOT EXISTS moneda TEXT NOT NULL DEFAULT 'CLP'
  CHECK (moneda IN ('CLP', 'ARS', 'USD'));
ALTER TABLE movimientos_bodega ADD COLUMN IF NOT EXISTS moneda TEXT NOT NULL DEFAULT 'CLP'
  CHECK (moneda IN ('CLP', 'ARS', 'USD'));
ALTER TABLE insumos ADD COLUMN IF NOT EXISTS moneda TEXT NOT NULL DEFAULT 'CLP'
  CHECK (moneda IN ('CLP', 'ARS', 'USD'));

-- =====================================================================
-- 28) Catalogo de marcas/modelos de neumaticos por cliente (Admin >
-- Configuracion > Catalogo de neumaticos), usado por el modal de carga de
-- posicion de la auditoria del mecanico para reemplazar Marca/Modelo de
-- texto libre por un dropdown con las opciones del cliente. auditoria_posiciones
-- no tenia columnas marca/modelo (solo se guardaban en el JSONB del
-- instructivo, no en la fila de la posicion), asi que se agregan aca.
-- =====================================================================
CREATE TABLE IF NOT EXISTS marcas_modelos_cliente (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id TEXT NOT NULL REFERENCES clientes(id_cliente),
  marca TEXT NOT NULL,
  modelo TEXT NOT NULL,
  tipo TEXT NOT NULL CHECK (tipo IN ('direccional', 'traccional', 'eje_libre', 'auxilio')),
  activo BOOLEAN NOT NULL DEFAULT true,
  creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (cliente_id, marca, modelo)
);
GRANT SELECT, INSERT, UPDATE ON marcas_modelos_cliente TO anon;
ALTER TABLE marcas_modelos_cliente ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS anon_all ON marcas_modelos_cliente;
CREATE POLICY anon_all ON marcas_modelos_cliente FOR ALL TO anon USING (true) WITH CHECK (true);

ALTER TABLE auditoria_posiciones ADD COLUMN IF NOT EXISTS marca TEXT;
ALTER TABLE auditoria_posiciones ADD COLUMN IF NOT EXISTS modelo TEXT;

-- Datos iniciales de La Portada, solo si el catalogo de ese cliente esta vacio.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM marcas_modelos_cliente WHERE cliente_id = 'la_portada') THEN
    INSERT INTO marcas_modelos_cliente (cliente_id, marca, modelo, tipo) VALUES
    ('la_portada','GOODYEAR','KMAX D','traccional'),
    ('la_portada','GOODYEAR','KMAX S','traccional'),
    ('la_portada','GOODYEAR','REGIONAL RHD II','direccional'),
    ('la_portada','MICHELIN','X MULTI D','traccional'),
    ('la_portada','MICHELIN','X MULTI Z','direccional'),
    ('la_portada','BRIDGESTONE','R150','traccional'),
    ('la_portada','TRIANGLE','TRT02','traccional'),
    ('la_portada','WESLAKE','WTR69','traccional')
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- =====================================================================
-- 29) Horas de jornada normal (Admin > Configuracion > Jornada laboral),
-- usado por la alerta de horas extras del mecanico (mecanico.html compara
-- NOW() contra check_diario.hora_inicio de hoy). No es estrictamente
-- necesario correr esto: db.fetchConfig ya cae al default 9 via DEFAULT_CFG
-- si la clave no existe en config_cliente para el cliente. Solo hace falta
-- si se quiere que el valor aparezca explicito en la tabla desde el inicio.
-- =====================================================================
INSERT INTO config_cliente (cliente_id, clave, valor) VALUES
  ('la_portada', 'horas_jornada_normal', '9'),
  ('bys', 'horas_jornada_normal', '9')
ON CONFLICT (cliente_id, clave) DO NOTHING;

-- =====================================================================
-- 30) Panel de desempeno del Admin (SuperAdmin > Productividad > tab Admin).
-- alertas solo tenia leida_admin (booleano) - sin estado de resolucion real,
-- sin timestamps de "visto"/"en proceso"/"resuelto" ni quien la resolvio.
-- Se agrega un state machine minimo (pendiente/en_proceso/resuelta) para
-- poder medir tiempo de resolucion y % en plazo. Filas viejas quedan en
-- 'pendiente' con el resto de columnas NULL (el panel las muestra como
-- "sin datos", no rompe nada). horas_escalada_alerta en config_cliente
-- define el plazo de resolucion esperado (default 4hs si no esta seteado,
-- ver DEFAULT_CFG en js/supabase.js).
-- =====================================================================
ALTER TABLE alertas ADD COLUMN IF NOT EXISTS estado TEXT NOT NULL DEFAULT 'pendiente'
  CHECK (estado IN ('pendiente', 'en_proceso', 'resuelta'));
ALTER TABLE alertas ADD COLUMN IF NOT EXISTS visto_en TIMESTAMPTZ;
ALTER TABLE alertas ADD COLUMN IF NOT EXISTS en_proceso_en TIMESTAMPTZ;
ALTER TABLE alertas ADD COLUMN IF NOT EXISTS resuelto_en TIMESTAMPTZ;
ALTER TABLE alertas ADD COLUMN IF NOT EXISTS resuelto_por UUID REFERENCES usuarios(id);
ALTER TABLE alertas ADD COLUMN IF NOT EXISTS escalada_superadmin BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE alertas ADD COLUMN IF NOT EXISTS justificacion_admin TEXT;

-- =====================================================================
-- 31) Reestructuracion del sistema de alertas (3 niveles visuales +
-- resolucion en vivo + escalada automatica). El bloque 30 uso
-- pendiente/en_proceso/resuelta; esta spec separa "vista" de "en_proceso"
-- como pasos distintos (nueva -> vista -> en_proceso -> resuelta) y quiere
-- registrar QUIEN puso una alerta en_proceso (no solo cuando). Se renombra
-- en_proceso_en -> en_proceso_desde, se agrega en_proceso_por (admin que la
-- tomo) y escalada_en (cuando se escalo, separado del booleano
-- escalada_superadmin que ya existia desde el bloque 30).
-- El CHECK de alertas.tipo ya fue restaurado a mano por el usuario antes de
-- este bloque (confirmado con curl: rechaza tipos inventados, acepta los
-- 19 tipos reales incluyendo escalada_sin_resolver/recordatorio_admin).
-- =====================================================================
-- Version idempotente (el primer intento quedo a medio aplicar: la columna
-- ya se renombro pero el CHECK nuevo nunca prendio, asi que esto se puede
-- correr de nuevo sin romper sin importar en que paso se haya cortado).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alertas' AND column_name = 'en_proceso_en')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alertas' AND column_name = 'en_proceso_desde') THEN
    ALTER TABLE alertas RENAME COLUMN en_proceso_en TO en_proceso_desde;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alertas' AND column_name = 'en_proceso_en')
     AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alertas' AND column_name = 'en_proceso_desde') THEN
    -- Quedaron las dos columnas de un intento anterior a medio aplicar:
    -- en_proceso_desde ya es la que usa el codigo, asi que se descarta la vieja.
    ALTER TABLE alertas DROP COLUMN en_proceso_en;
  END IF;
END $$;
ALTER TABLE alertas ADD COLUMN IF NOT EXISTS en_proceso_por UUID REFERENCES usuarios(id);
ALTER TABLE alertas ADD COLUMN IF NOT EXISTS escalada_en TIMESTAMPTZ;
-- El DROP tiene que ir ANTES del UPDATE: el CHECK viejo (pendiente/en_proceso/
-- resuelta) todavia esta activo en este punto y rechaza el 'nueva' que
-- pone el UPDATE de abajo si se corre en el orden equivocado.
ALTER TABLE alertas DROP CONSTRAINT IF EXISTS alertas_estado_check;
-- Cualquier fila con un estado que no entre en la lista nueva (viejas
-- 'pendiente', o filas de prueba cargadas entre intentos) se normaliza antes
-- de agregar el CHECK, para que la validacion de filas existentes no falle.
UPDATE alertas SET estado = 'nueva' WHERE estado NOT IN ('nueva', 'vista', 'en_proceso', 'resuelta') OR estado IS NULL;
ALTER TABLE alertas ALTER COLUMN estado SET DEFAULT 'nueva';
ALTER TABLE alertas ADD CONSTRAINT alertas_estado_check CHECK (estado IN ('nueva', 'vista', 'en_proceso', 'resuelta'));

INSERT INTO config_cliente (cliente_id, clave, valor) VALUES
  ('la_portada', 'horas_escalada_alerta', '4'),
  ('bys', 'horas_escalada_alerta', '4')
ON CONFLICT (cliente_id, clave) DO NOTHING;

-- 32) discrepancias_inventario.valor_sistema tenia NOT NULL, pero una
-- discrepancia de auditoria legitima puede no tener valor de sistema (el
-- mecanico encontro un neumatico con numero de fuego que el sistema no
-- tiene registrado en esa posicion -> valor_sistema queda null a proposito,
-- ver enviarDiscrepanciaAuditoria/discrepanciasParaAdmin en js/supabase.js).
-- Esto trababa el insert para siempre (3 reintentos y la cola offline deja
-- de reintentar solo, el registro queda "pendiente de sincronizar" sin
-- explicacion visible para el mecanico). Igual que con los CHECK viejos
-- (ver notas de arriba), el criterio es sacar la restriccion, no ampliarla.
ALTER TABLE discrepancias_inventario ALTER COLUMN valor_sistema DROP NOT NULL;

-- 33) Instructivos dinamicos con estados HACER_HOY/PENDIENTE/COMPLETADA
-- (motor de reglas + tareas pendientes por camion, ver notas en js/supabase.js
-- funcion generarRecomendaciones/fetchTareasPendientesEquipo). Cada tarea
-- sigue viviendo dentro de auditorias_receta.posiciones_alerta (recomendaciones/
-- tareas_extra), no se creo tabla nueva -- solo se agrega el permiso por
-- mecanico para poder derivar tareas a pendiente / agregar tareas propias.
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS puede_modificar_instructivo BOOLEAN NOT NULL DEFAULT false;

-- 34) Actividad en Faena en vivo: log de eventos de sesion de trabajo por
-- equipo (AUDITORIA_INICIADA/AUDITORIA_FINALIZADA/HOJA_CAMBIO_EN_PROCESO/
-- HOJA_CAMBIO_FINALIZADA), usado por el widget "Actividad en Faena (En Vivo)"
-- del Admin/SuperAdmin para mostrar el estado actual de cada equipo/mecanico
-- sin tener que inferirlo de auditorias/cambios_neumaticos. Se inserta una
-- fila por evento (no se pisa la anterior) -- el estado "actual" de un
-- equipo es su fila mas reciente, ver db.fetchActividadFaena.
CREATE TABLE IF NOT EXISTS sesiones_trabajo (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id TEXT NOT NULL,
  equipo_id UUID NOT NULL REFERENCES equipos(id_equipo),
  usuario_id UUID NOT NULL REFERENCES usuarios(id),
  evento TEXT NOT NULL CHECK (evento IN ('AUDITORIA_INICIADA', 'AUDITORIA_FINALIZADA', 'HOJA_CAMBIO_EN_PROCESO', 'HOJA_CAMBIO_FINALIZADA')),
  auditoria_id UUID REFERENCES auditorias(id_auditoria),
  cambio_id UUID REFERENCES cambios_neumaticos(id_cambio),
  creado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sesiones_trabajo_equipo_creado ON sesiones_trabajo (equipo_id, creado_en DESC);
CREATE INDEX IF NOT EXISTS idx_sesiones_trabajo_cliente_creado ON sesiones_trabajo (cliente_id, creado_en DESC);
ALTER TABLE sesiones_trabajo ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sesiones_trabajo_all ON sesiones_trabajo;
CREATE POLICY sesiones_trabajo_all ON sesiones_trabajo FOR ALL USING (true) WITH CHECK (true);

-- Habilitar Realtime (postgres_changes) para el widget "Actividad en Faena
-- (En Vivo)" (sesiones_trabajo) y para reflejar en vivo, sin refrescar, las
-- tareas del instructivo entre Admin/SuperAdmin y mecanico.html
-- (auditorias_receta) -- ver mosa-app/js/supabase.js y mecanico.html
-- (canal "hc-checklist-...") y admin.html/superadmin.html (canal
-- "dashboard-actividad-faena...").
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'sesiones_trabajo') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE sesiones_trabajo;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'auditorias_receta') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE auditorias_receta;
  END IF;
END $$;

-- 35) Faltaba el GRANT de tabla para el rol anon en sesiones_trabajo (la RLS
-- policy sola no alcanza -- Postgres exige el GRANT ademas, mismo patron que
-- discrepancias_inventario/marcas_modelos_cliente arriba). Sin esto el
-- insert de db.registrarEventoSesion falla con 42501 "permission denied".
GRANT SELECT, INSERT, UPDATE ON sesiones_trabajo TO anon;

-- 36) Alargadera y Checkpoint por posicion de neumatico (toggle en el modal
-- de detalle de la HC, mecanico.html TireInfoModal) -- viven junto al resto
-- del estado del neumatico montado (psi_actual/milimetros), no en
-- intervenciones (su CHECK de tipo no incluye "alargadera" y este flag no es
-- un evento de auditoria puntual sino un estado persistente del neumatico).
ALTER TABLE neumaticos ADD COLUMN IF NOT EXISTS alargadera BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE neumaticos ADD COLUMN IF NOT EXISTS checkpoint BOOLEAN NOT NULL DEFAULT false;

-- 37) Herramientas extra del Check Diario (Paso 3): array libre de
-- {nombre, cantidad} que el mecanico puede agregar ademas de la checklist
-- estandar (TOOLS_CHECKLIST). Las columnas neu_dir_*/neu_trac_*/neu_libre_*
-- para discriminar el stock de neumaticos por tipo ya existian en la tabla
-- (creadas a mano en algun momento) pero el codigo nunca las escribia -- ver
-- CheckDiario.continuar() en mecanico.html.
ALTER TABLE check_diario ADD COLUMN IF NOT EXISTS herramientas_extra JSONB NOT NULL DEFAULT '[]'::jsonb;

-- 38) alertas.tipo tenia de nuevo un CHECK constraint con una lista fija
-- (restaurado a mano en algun momento despues del bloque 15) que rechaza el
-- nuevo tipo 'herramienta_nueva' (alerta de herramienta declarada en terreno
-- por el mecanico que no esta en el catalogo, ver Check Diario Paso 3 en
-- mecanico.html). Mismo criterio que en el bloque 15: se saca la restriccion
-- en vez de tener que ampliarla cada vez que se agrega un tipo de alerta.
ALTER TABLE alertas DROP CONSTRAINT IF EXISTS alertas_tipo_check;

-- 39) alertas.datos_extra (JSONB) -- payload estructurado para alertas que
-- necesitan mas datos de los que caben en titulo/descripcion (por ahora,
-- 'herramienta_nueva': nombre_herramienta/cantidad/empresa_id, para que el
-- boton "Sumar a Catalogo" del Admin no tenga que parsear el texto libre de
-- la descripcion).
ALTER TABLE alertas ADD COLUMN IF NOT EXISTS datos_extra JSONB;

-- 40) sesiones_trabajo.evento tiene un CHECK constraint con una lista fija
-- (AUDITORIA_INICIADA/AUDITORIA_FINALIZADA/HOJA_CAMBIO_EN_PROCESO/
-- HOJA_CAMBIO_FINALIZADA) que rechaza el nuevo estado 'EN_RECOMENDACIONES'
-- (transicion al cerrar la auditoria y pasar a la pantalla de
-- Recomendaciones, antes de entrar a la Hoja de Cambio -- ver
-- db.registrarEventoSesion en js/supabase.js y mecanico.html). Mismo
-- criterio que en los bloques 15/38: se saca la restriccion en vez de
-- ampliarla cada vez que se agrega un evento nuevo.
ALTER TABLE sesiones_trabajo DROP CONSTRAINT IF EXISTS sesiones_trabajo_evento_check;

-- 41) cambio_detalle.foto_url -- evidencia fotografica obligatoria al
-- retirar un neumatico por Daño/Otro (RetiroModal en mecanico.html, sube a
-- un bucket nuevo 'neumaticos-evidencia'). Queda vinculada al registro del
-- desmonte para que el Admin la pueda auditar despues, no solo la
-- descripcion de texto libre de la alerta baja_prematura.
ALTER TABLE cambio_detalle ADD COLUMN IF NOT EXISTS foto_url TEXT;

-- 42) Bucket de Storage "neumaticos-evidencia" (fotos de retiro por Daño/Otro)
-- Igual que el bucket "checkpoints" (bloques 8/11), esto NO se puede crear
-- por SQL: andá a Supabase Dashboard > Storage > "New bucket", nombralo
-- exactamente "neumaticos-evidencia" y marcalo como Public. Sin este
-- bucket, el retiro por Daño/Otro no va a poder subir la foto obligatoria
-- (la app avisa con un error si falta). Despues de crearlo, correr estas
-- politicas para que el rol anon pueda subir/leer en ese bucket puntual:
DROP POLICY IF EXISTS "anon puede subir a neumaticos-evidencia" ON storage.objects;
CREATE POLICY "anon puede subir a neumaticos-evidencia" ON storage.objects
  FOR INSERT TO anon
  WITH CHECK (bucket_id = 'neumaticos-evidencia');

DROP POLICY IF EXISTS "anon puede actualizar neumaticos-evidencia" ON storage.objects;
CREATE POLICY "anon puede actualizar neumaticos-evidencia" ON storage.objects
  FOR UPDATE TO anon
  USING (bucket_id = 'neumaticos-evidencia');

DROP POLICY IF EXISTS "anon puede leer neumaticos-evidencia" ON storage.objects;
CREATE POLICY "anon puede leer neumaticos-evidencia" ON storage.objects
  FOR SELECT TO anon
  USING (bucket_id = 'neumaticos-evidencia');

-- 43) equipos.configuracion_ejes tenia un CHECK constraint con una lista fija
-- (4x2/6x2/6x4, presumiblemente) que rechaza las configuraciones nuevas del
-- cliente ELB ("1+1", "3+1", y a futuro "3x2" para los Moffett -- ver
-- AXLE_CONFIGS en js/supabase.js). Mismo criterio que en los bloques
-- 15/38/40: se saca la restriccion en vez de tener que ampliarla cada vez
-- que se agrega una flota con ejes distintos.
ALTER TABLE equipos DROP CONSTRAINT IF EXISTS equipos_configuracion_ejes_check;

-- 44) usuarios.empresas_adicionales -- mecanicos que trabajan para mas de
-- una empresa (ej. cubren BYS, ELB y La Portada segun el dia). usuarios.
-- cliente_id sigue siendo la empresa "de base"; este array JSONB guarda las
-- demas cliente_id a las que tambien tiene acceso. SeleccionEmpresa
-- (mecanico.html) ya lee esta columna -- si tiene mas de un cliente_id
-- disponible, muestra una lista real para elegir en vez de auto-confirmar.
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS empresas_adicionales JSONB DEFAULT '[]'::jsonb;

-- 45) config_cliente.usa_recauchados -- flag booleano por cliente que activa
-- o desactiva todo el flujo de neumaticos recauchados (conteo en check
-- diario, bodega "Para Recauchar"/"Recauchados", etiqueta "Recauchado" en
-- modales de montaje, y la opcion "Recauchado" en el selector de condicion
-- del Maestro de Neumaticos -- ver DEFAULT_CFG/fetchConfig en
-- js/supabase.js). No requiere ALTER TABLE (config_cliente ya es
-- clave/valor generica, ver bloque 2). Clientes sin fila propia caen al
-- default 'true' en DEFAULT_CFG, asi que La Portada y BYS siguen igual sin
-- necesidad de insertar nada; ELB queda explicito en false.
INSERT INTO config_cliente (cliente_id, clave, valor) VALUES
  ('elb', 'usa_recauchados', 'false'),
  ('bys', 'usa_recauchados', 'false'),
  ('la_portada', 'usa_recauchados', 'true')
ON CONFLICT (cliente_id, clave) DO UPDATE SET valor = EXCLUDED.valor;

-- 46) auditoria_posiciones.url_foto_desgaste_irregular -- evidencia
-- fotografica obligatoria cuando el mecanico marca "Tipo de desgaste:
-- Irregular" en la Auditoria (PosicionModal, mecanico.html). Sube al mismo
-- bucket 'neumaticos-evidencia' que ya usa el retiro por Daño/Otro (bloques
-- 41/42 de esta migracion) -- no hace falta crear un bucket nuevo, las
-- policies de storage.objects ya cubren ese bucket para el rol anon.
ALTER TABLE auditoria_posiciones ADD COLUMN IF NOT EXISTS url_foto_desgaste_irregular TEXT;

-- 47) BUG encontrado en pruebas: neumaticos_bodega_check seguia restringido
-- a una lista fija vieja (nuevo/recauchado/transito/reparacion/baja/salidas,
-- ver bloque 20a) que NUNCA incluyo retiro_dano/retiro_otro (la bodega
-- combinada retiro_daño_otro se separo en dos despues de ese bloque). Se
-- confirmo con inserts de prueba reales: retiro_desgaste/reparacion/nfu/
-- para_recauchar insertan OK, retiro_dano/retiro_otro rechazan con 23514.
-- Resultado: nadie pudo usar Retiro por Daño ni Retiro por Otro desde que
-- se separaron esas bodegas. Mismo criterio que otros CHECK de esta
-- migracion (bloques 15/20b/21/23/24): se saca la restriccion en vez de
-- mantenerla sincronizada a mano cada vez que se agrega una bodega.
ALTER TABLE neumaticos DROP CONSTRAINT IF EXISTS neumaticos_bodega_check;


-- 48) Configuraciones de Flota (esquemas de ejes/neumaticos) dinamicas por
-- cliente, en vez de la lista fija CONFIG_EJES_OPCIONES=["4x2","6x2","6x4"]
-- hardcodeada en admin.html y AXLE_CONFIGS hardcodeado en js/supabase.js.
-- "slug" es el valor que se guarda en equipos.configuracion_ejes (mismo
-- string de siempre, ej. "4x2"/"1+1"/"4x2-grua") -- axleConfigFor sigue
-- revisando AXLE_CONFIGS PRIMERO para esos slugs tradicionales (compatibilidad
-- exacta, sin cambios de comportamiento), y recien si no matchea ahi cae a
-- esta tabla (configuraciones nuevas creadas desde Admin > Configuracion >
-- "Configuraciones de Flota"). "ejes" es un JSONB [{eje:1,tipo:"direccional"|
-- "traccion"}, ...] -- direccional=2 ruedas, traccion=4 ruedas (ver
-- construirAxleConfigDesdeDB en js/supabase.js).
CREATE TABLE IF NOT EXISTS configuraciones_equipos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id TEXT NOT NULL REFERENCES clientes(id_cliente),
  nombre TEXT NOT NULL,
  categoria TEXT NOT NULL CHECK (categoria IN ('tractor', 'trailer', 'chasis')),
  slug TEXT NOT NULL,
  numero_ejes INT NOT NULL CHECK (numero_ejes BETWEEN 1 AND 6),
  ejes JSONB NOT NULL,
  auxiliares INT NOT NULL DEFAULT 0 CHECK (auxiliares BETWEEN 0 AND 2),
  activo BOOLEAN NOT NULL DEFAULT true,
  creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (cliente_id, slug)
);
GRANT SELECT, INSERT, UPDATE ON configuraciones_equipos TO anon;
ALTER TABLE configuraciones_equipos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS anon_all ON configuraciones_equipos;
CREATE POLICY anon_all ON configuraciones_equipos FOR ALL TO anon USING (true) WITH CHECK (true);

-- Carga inicial: los esquemas que La Portada y ELB ya usan hoy (ver
-- AXLE_CONFIGS en js/supabase.js), para que aparezcan listados en Admin >
-- Configuracion > "Configuraciones de Flota" desde el arranque. Estos slugs
-- YA renderizan correctamente porque AXLE_CONFIGS los resuelve primero -- esta
-- carga es solo para que el Admin los vea/gestione en la pantalla nueva
-- (algunos matices de rotacion de 6x2/6x4/grua no se pueden expresar 1:1 en
-- el esquema simple del asistente, no afecta el render real).
INSERT INTO configuraciones_equipos (cliente_id, nombre, categoria, slug, numero_ejes, ejes, auxiliares) VALUES
  ('la_portada', 'Tracto 4x2', 'tractor', '4x2', 2,
    '[{"eje":1,"tipo":"direccional"},{"eje":2,"tipo":"traccion"}]', 0),
  ('la_portada', 'Tracto 6x2', 'tractor', '6x2', 3,
    '[{"eje":1,"tipo":"direccional"},{"eje":2,"tipo":"traccion"},{"eje":3,"tipo":"traccion"}]', 0),
  ('la_portada', 'Tracto 6x4', 'tractor', '6x4', 3,
    '[{"eje":1,"tipo":"direccional"},{"eje":2,"tipo":"traccion"},{"eje":3,"tipo":"traccion"}]', 0),
  ('la_portada', 'Semirremolque 3 ejes + auxilio', 'trailer', 'semi', 3,
    '[{"eje":1,"tipo":"traccion"},{"eje":2,"tipo":"traccion"},{"eje":3,"tipo":"traccion"}]', 1),
  ('elb', 'Trailer 1+1', 'trailer', '1+1', 2,
    '[{"eje":1,"tipo":"traccion"},{"eje":2,"tipo":"traccion"}]', 1),
  ('elb', 'Trailer 3+1', 'trailer', '3+1', 4,
    '[{"eje":1,"tipo":"traccion"},{"eje":2,"tipo":"traccion"},{"eje":3,"tipo":"traccion"},{"eje":4,"tipo":"traccion"}]', 1),
  ('elb', 'Grúa Horquilla 4x2', 'chasis', '4x2-grua', 2,
    '[{"eje":1,"tipo":"traccion"},{"eje":2,"tipo":"direccional"}]', 0)
ON CONFLICT (cliente_id, slug) DO NOTHING;
