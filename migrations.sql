-- =====================================================================
-- MOSA Neumaticos - Migracion de base de datos (Supabase)
-- Ejecutar en: Supabase Dashboard > SQL Editor
-- Seguro de re-ejecutar (usa IF NOT EXISTS / ON CONFLICT donde aplica)
-- =====================================================================

-- 1) Columnas de login en mecanicos
ALTER TABLE mecanicos ADD COLUMN IF NOT EXISTS usuario TEXT;
ALTER TABLE mecanicos ADD COLUMN IF NOT EXISTS password_hash TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS mecanicos_usuario_key ON mecanicos (usuario);

-- 2) Tabla de configuracion por cliente
CREATE TABLE IF NOT EXISTS config_cliente (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id TEXT NOT NULL REFERENCES clientes(id_cliente),
  clave TEXT NOT NULL,
  valor TEXT,
  UNIQUE (cliente_id, clave)
);

-- 3) Valores por defecto para La Portada (no pisa valores existentes)
INSERT INTO config_cliente (cliente_id, clave, valor)
VALUES
  ('la_portada', 'numero_auditoria_inicio', '1'),
  ('la_portada', 'numero_cambio_inicio', '1'),
  ('la_portada', 'numero_flash_inicio', '1'),
  ('la_portada', 'numero_hoja_inicio', '1'),
  ('la_portada', 'numero_fuego_inicio', '1'),
  ('la_portada', 'psi_minimo', '85'),
  ('la_portada', 'mm_minimo', '4'),
  ('la_portada', 'formula_marca_fuego', 'interno_semana_anio_posicion')
ON CONFLICT (cliente_id, clave) DO NOTHING;

-- =====================================================================
-- 4) PERMISOS DEL ROL "anon"
-- La app usa la clave publica (publishable/anon) desde el navegador y
-- maneja su propio login de mecanicos (no usa Supabase Auth), por lo
-- que el rol "anon" necesita permisos GRANT directos sobre las tablas
-- (esto es independiente de RLS). Sin esto, todas las consultas fallan
-- con "permission denied for table X" (error 42501).
-- =====================================================================

GRANT USAGE ON SCHEMA public TO anon;

GRANT SELECT, INSERT, UPDATE ON
  clientes, equipos, mecanicos, neumaticos, auditorias, auditoria_posiciones,
  cambios_neumaticos, cambio_detalle, flash_diario, novedades_diarias,
  novedades_checklist, config_cliente
TO anon;

-- =====================================================================
-- 5) RLS (Row Level Security)
-- Si ademas de los GRANT de arriba estas tablas tienen RLS activado,
-- hay que agregar politicas permisivas para el rol anon (ejecutar solo
-- si RLS esta activo y bloqueando el acceso):
--
-- ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY anon_all ON clientes FOR ALL TO anon USING (true) WITH CHECK (true);
--
-- (repetir para: equipos, mecanicos, neumaticos, auditorias,
--  auditoria_posiciones, cambios_neumaticos, cambio_detalle,
--  flash_diario, novedades_diarias, novedades_checklist, config_cliente)
