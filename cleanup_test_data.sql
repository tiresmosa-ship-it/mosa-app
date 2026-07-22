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
  '30829261','429382413','316042601'
);

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
