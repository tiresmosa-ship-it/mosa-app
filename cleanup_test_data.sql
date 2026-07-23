-- =====================================================================
-- MOSA TIRES - Limpieza total de datos de prueba (todas las pruebas de hoy,
-- tanto las tuyas manuales como las mias de verificacion de rotaciones/giro)
-- Ejecutar en: Supabase Dashboard > SQL Editor
--
-- Vacia TODA la actividad operacional (auditorias, cambios, checks diarios,
-- cierres, alertas, discrepancias, movimientos de bodega, intervenciones),
-- ya que el proyecto todavia no salio a produccion con mecanicos reales.
-- NO TOCA: usuarios, equipos, clientes, config_cliente, permisos, insumos,
-- proveedores.
-- =====================================================================

DELETE FROM cambio_detalle;
DELETE FROM movimientos_bodega;
DELETE FROM intervenciones;
DELETE FROM auditoria_posiciones;
DELETE FROM auditorias_receta;
DELETE FROM auditorias;
DELETE FROM cambios_neumaticos;
DELETE FROM alertas;
DELETE FROM discrepancias_inventario;
DELETE FROM check_diario_herramientas;
DELETE FROM check_diario;
DELETE FROM cierre_dia;

-- Neumaticos ficticios creados por las pruebas de hoy (no son inventario
-- real): los de rotacion/giro 6x4, y los de tus pruebas manuales.
DELETE FROM neumaticos WHERE numero_fuego IN (
  '99000001','99000002','99000003','99000010',
  '10830264','10830265','10830266','11229261','11111111',
  '30829261','429382413','316042601',
  '77000001','77000003','77000007'
);

-- Proveedor de prueba usado para verificar el esquema de Maestros > Proveedores.
DELETE FROM proveedores WHERE id = '66666666-0001-0000-0000-000000000001';

-- Datos de prueba de Admin > Maestros (equipos/mecanicos/insumos no se tocan
-- en los DELETE de arriba, asi que se limpian puntualmente aca).
DELETE FROM equipos WHERE patente IN ('ZZ999TEST', 'DUPTEST');
DELETE FROM mecanicos WHERE usuario = 'testmec999';
DELETE FROM insumos WHERE id = '35af66aa-4a0b-4e77-9587-50e841bb930b';

-- Filas de prueba en usuarios (Maestros > Mecanicos ahora gestiona usuarios
-- en vez de la tabla legacy mecanicos): quedaron inactivas, se pueden borrar.
DELETE FROM usuarios WHERE usuario IN ('debugtest999', 'debugtest998', 'nuevotest999', 'verifytest001');

-- Herramientas de prueba usadas para verificar que el bloque 24 (RLS de
-- herramientas_inventario) quedo aplicado, mas la creada por la UI real.
DELETE FROM herramientas_inventario WHERE id = '66666666-0002-0000-0000-000000000002'
  OR nombre = 'Taladro Real Test';

-- Carga valorizada de neumaticos de prueba (lotes_inventario + neumaticos +
-- movimientos_bodega) usada para verificar el flujo completo end-to-end.
DELETE FROM lotes_inventario WHERE numero_documento LIKE 'DOC-NEU-TEST%' OR numero_documento LIKE 'DEBUGDOC%';
DELETE FROM neumaticos WHERE marca LIKE 'MarcaTest%' OR marca LIKE 'DebugLote%' OR marca = 'DebugNeu';

-- =====================================================================
-- Verificacion (deberia devolver 0 en todas)
-- =====================================================================
SELECT
  (SELECT count(*) FROM auditorias) AS auditorias,
  (SELECT count(*) FROM cambios_neumaticos) AS cambios,
  (SELECT count(*) FROM check_diario) AS checks,
  (SELECT count(*) FROM cierre_dia) AS cierres,
  (SELECT count(*) FROM alertas) AS alertas,
  (SELECT count(*) FROM intervenciones) AS intervenciones,
  (SELECT count(*) FROM movimientos_bodega) AS movimientos;
