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
