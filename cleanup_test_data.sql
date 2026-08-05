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
  '77000001','77000003','77000007',
  'TESTRETIRO001','TESTRETIRO002','TESTRETIRO003','TESTRETIRO004','TESTITEM9001',
  '900001','900002','900003','900004','900005','900006'
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

-- Herramienta "Gata" (id 11111111-1111-1111-1111-111111111111) creada para
-- probar la comparacion de check diario vs herramientas_inventario (mejora
-- del check diario: discrepancias de herramientas). Su cantidad quedo en 5
-- tras probar el flujo de aprobacion (empezo en 3).
DELETE FROM herramientas_inventario WHERE id = '11111111-1111-1111-1111-111111111111';

-- Carga valorizada de neumaticos de prueba (lotes_inventario + neumaticos +
-- movimientos_bodega) usada para verificar el flujo completo end-to-end.
DELETE FROM lotes_inventario WHERE numero_documento LIKE 'DOC-NEU-TEST%' OR numero_documento LIKE 'DEBUGDOC%';
DELETE FROM neumaticos WHERE marca LIKE 'MarcaTest%' OR marca LIKE 'DebugLote%' OR marca = 'DebugNeu';

-- Neumatico de prueba usado para verificar el correlativo secuencial de
-- numero_fuego de BYS (Admin > Configuracion > Correlativos).
DELETE FROM neumaticos WHERE id_neumatico = '77777777-9999-0000-0000-000000000001';

-- Datos de prueba de superadmin.html (Clientes / Usuarios y permisos):
-- cliente de prueba "mosa_test_qa" (quedo desactivado tras probar el toggle
-- en cascada) y usuario mecanico "usuario_qa_test" creado para probar el
-- panel de permisos, junto con las filas de permisos que genero.
DELETE FROM permisos WHERE usuario_id IN (SELECT id FROM usuarios WHERE usuario = 'usuario_qa_test');
DELETE FROM usuarios WHERE usuario = 'usuario_qa_test';
DELETE FROM config_cliente WHERE cliente_id = 'mosa_test_qa';
DELETE FROM clientes WHERE id_cliente = 'mosa_test_qa';

-- Permisos de prueba generados al verificar el boton "Resetear permisos al
-- default del rol" contra el usuario real 'carlos' (mecanico, La Portada).
DELETE FROM permisos WHERE usuario_id = (SELECT id FROM usuarios WHERE usuario = 'carlos')
  AND seccion IN ('auditoria','hoja_cambio','cierre_dia','alertas_propias');

-- Usuario de prueba para verificar cliente-operativo.html (rol=cliente,
-- subtipo=operativo) contra la base real.
DELETE FROM usuarios WHERE usuario = 'clienteoperativo_test';

-- Movimiento de prueba para verificar la columna moneda (multi-moneda) en
-- Entrada de insumos. El insumo afectado (llanta americana_aluminio,
-- La Portada) ya se revirtio a mano a cantidad=0/precio=0 via REST, solo
-- falta borrar el movimiento (anon no tiene DELETE).
DELETE FROM movimientos_bodega WHERE numero_documento = 'TEST-MONEDA-1';

-- Usuarios de prueba para verificar cliente-gerencia.html (rol=cliente,
-- subtipo=dueno) y la creacion de operativos desde ese panel.
DELETE FROM usuarios WHERE usuario IN ('clientegerencia_test', 'operativo_prueba2_test');

-- Datos de demo cargados para mostrarle a Nelson el flujo completo (check
-- diario, 2 auditorias, hoja de cambio con foto, cierre, alertas) sobre
-- JFTH64 y JP2221. Las filas en cambio_detalle/intervenciones/auditoria_*
-- /cierre_dia/check_diario*/alertas ya quedan cubiertas por los DELETE
-- genericos del inicio de este archivo -- lo unico que NO cubren esos
-- DELETE es la tabla neumaticos, que se limpia aca puntualmente:
DELETE FROM neumaticos WHERE numero_fuego IN (
  '30829241','30829261','30829262','30829263','30829264','30829265','30829266',
  '41629261','41629262','41629263','41629264','41629265','41629266','41629267',
  '41629268','41629269','41629270','41629271','41629272','41629273'
);

-- Neumatico de prueba creado al verificar el fix de asegurarNeumatico (Bug 1:
-- auditoria con numero de fuego inexistente debia grabar tipo/estado/bodega
-- bien) contra NAK810. No se pudo borrar en el momento por REST (anon sin
-- DELETE en neumaticos).
DELETE FROM neumaticos WHERE numero_fuego LIKE 'AUDTEST%';

-- Filas de prueba insertadas al verificar db.registrarEventoSesion/Realtime
-- en vivo contra AE289ZB (anon sin DELETE en sesiones_trabajo).
DELETE FROM sesiones_trabajo WHERE id IN (
  '552c8f90-854a-4b7f-9401-9cc937365419',
  '9927e72a-78f8-4001-bf48-e90858c413f5',
  '007928fa-15e6-4f0f-9c80-726ea44ae007'
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
